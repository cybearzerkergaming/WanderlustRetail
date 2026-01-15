-- Wanderlust - hunger system
local WL = Wanderlust
local IsSwimming = IsSwimming
local UnitAffectingCombat = UnitAffectingCombat
local UnitIsDead = UnitIsDead
local UnitIsGhost = UnitIsGhost
local UnitOnTaxi = UnitOnTaxi
local GetTime = GetTime
local GetUnitSpeed = GetUnitSpeed
local IsMounted = IsMounted
local math_abs = math.abs
local math_floor = math.floor
local math_max = math.max
local math_min = math.min

----------------------------------------------------------------
-- Aura API compatibility (Midnight / modern clients)
-- Classic uses UnitBuff; modern uses C_UnitAuras.GetAuraDataByIndex
----------------------------------------------------------------
local function WL_GetAuraDataByIndex(unit, index, filter)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        return C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
    end
    if AuraUtil and AuraUtil.GetAuraDataByIndex then
        return AuraUtil.GetAuraDataByIndex(unit, index, filter)
    end
    return nil
end

local function WL_GetBuffName(unit, index)
    local aura = WL_GetAuraDataByIndex(unit, index, "HELPFUL")
    if aura then
        return aura.name, aura
    end
    if type(UnitBuff) == "function" then
        return UnitBuff(unit, index)
    end
    return nil
end

local cachedSettings = {
    hungerEnabled = nil,
    hungerMaxDarkness = nil,
    hungerOverlayEnabled = nil,
    temperatureEnabled = nil,
    exhaustionEnabled = nil
}

local function RefreshCachedSettings()
    if not WL.GetSetting then
        return
    end
    cachedSettings.hungerEnabled = WL.GetSetting("hungerEnabled")
    cachedSettings.hungerMaxDarkness = WL.GetSetting("hungerMaxDarkness")
    cachedSettings.hungerOverlayEnabled = WL.GetSetting("hungerOverlayEnabled")
    cachedSettings.temperatureEnabled = WL.GetSetting("temperatureEnabled")
    cachedSettings.exhaustionEnabled = WL.GetSetting("exhaustionEnabled")
end

local hunger = 0

local MIN_HUNGER = 0
local MAX_HUNGER = 100

local HUNGER_RATE_WALKING = 0.0144
local HUNGER_RATE_RUNNING = 0.0216
local HUNGER_RATE_MOUNTED = 0.0108
local HUNGER_RATE_COMBAT = 0.045
local HUNGER_RATE_SWIMMING = 0.027

local EATING_RECOVERY_RATE = 0.4
local RESTED_EATING_RECOVERY = 0.6

local CHECKPOINT_WORLD = 75
local CHECKPOINT_FIRE = 50
local CHECKPOINT_RESTED = 25
local CHECKPOINT_TRAINER = 0

local isInDungeon = false
local isDecaying = false

local hungerDarknessFrame = nil
local hungerDarknessCurrentAlpha = 0
local hungerDarknessTargetAlpha = 0
local HUNGER_DARKNESS_LERP_SPEED = 0.8

local function CreateHungerDarknessFrame()
    if hungerDarknessFrame then
        return hungerDarknessFrame
    end

    local frame = CreateFrame("Frame", "WanderlustHungerDarkness", UIParent)
    frame:SetAllPoints(UIParent)
    frame:SetFrameStrata("BACKGROUND")
    frame:SetFrameLevel(0)

    frame.texture = frame:CreateTexture(nil, "BACKGROUND")
    frame.texture:SetAllPoints()
    frame.texture:SetTexture("Interface\\AddOns\\Wanderlust\\assets\\tunnel_vision_4.png")
    frame.texture:SetBlendMode("BLEND")

    frame:SetAlpha(0)
    frame:Show()

    frame:EnableMouse(false)

    hungerDarknessFrame = frame
    return frame
end

local function GetHungerDarknessTarget()
    if not cachedSettings.hungerEnabled then
        return 0
    end
    if not cachedSettings.hungerOverlayEnabled then
        return 0
    end
    if not WL.IsPlayerEligible() then
        return 0
    end
    local maxDarkness = cachedSettings.hungerMaxDarkness or 0.25
    if maxDarkness <= 0 then
        return 0
    end
    if isInDungeon then
        return 0
    end
    if UnitOnTaxi("player") then
        return 0
    end
    if UnitIsDead("player") or UnitIsGhost("player") then
        return 0
    end
    return (hunger / MAX_HUNGER) * maxDarkness
end

local function UpdateHungerDarkness(elapsed)
    if not hungerDarknessFrame then
        return
    end

    hungerDarknessTargetAlpha = GetHungerDarknessTarget()

    local diff = hungerDarknessTargetAlpha - hungerDarknessCurrentAlpha
    if math_abs(diff) < 0.001 then
        hungerDarknessCurrentAlpha = hungerDarknessTargetAlpha
    else
        hungerDarknessCurrentAlpha = hungerDarknessCurrentAlpha + (diff * HUNGER_DARKNESS_LERP_SPEED * elapsed)
    end

    hungerDarknessCurrentAlpha = math_max(0, math_min(1, hungerDarknessCurrentAlpha))

    hungerDarknessFrame:SetAlpha(hungerDarknessCurrentAlpha)
end

local function ShouldUpdateHunger()
    if not cachedSettings.hungerEnabled then
        return false
    end
    if not WL.IsPlayerEligible() then
        return false
    end
    if UnitIsDead("player") or UnitIsGhost("player") then
        return false
    end
    return true
end

local WELL_FED_BUFFS = {
    ["Well Fed"] = true,
    ["Mana Regeneration"] = true,
    ["Increased Stamina"] = true,
    ["Increased Intellect"] = true,
    ["Increased Spirit"] = true,
    ["Increased Agility"] = true,
    ["Increased Strength"] = true,
    ["Blessing of Blackfathom"] = true,
    ["Spirit of Zanza"] = true,
    ["Gordok Green Grog"] = true,
    ["Rumsey Rum Black Label"] = true,
    ["Sagefish Delight"] = true,
    ["Nightfin Soup"] = true,
    ["Runn Tum Tuber Surprise"] = true,
    ["Monster Omelet"] = true,
    ["Tender Wolf Steak"] = true,
    ["Grilled Squid"] = true,
    ["Smoked Desert Dumplings"] = true,
    ["Dragonbreath Chili"] = true
}

local BUFF_SCAN_INTERVAL = 0.2
local lastFoodBuffCheck = 0
local cachedWellFed = false
local cachedEating = false

local function UpdateFoodBuffState()
    local now = GetTime()
    if now - lastFoodBuffCheck < BUFF_SCAN_INTERVAL then
        return
    end
    lastFoodBuffCheck = now
    cachedWellFed = false
    cachedEating = false

    for i = 1, 40 do
        local name = WL_GetBuffName("player", i)
        if not name then
            break
        end
        if not cachedWellFed and (WELL_FED_BUFFS[name] or name:match("Well Fed")) then
            cachedWellFed = true
        end
        if not cachedEating and (name == "Food" or name == "Refreshment" or name == "Food & Drink") then
            cachedEating = true
        end
        if cachedWellFed and cachedEating then
            break
        end
    end
end

local function HasWellFedBuff()
    UpdateFoodBuffState()
    return cachedWellFed
end

local function IsPlayerEating()
    UpdateFoodBuffState()
    return cachedEating
end

local function GetMovementState()
    if UnitAffectingCombat("player") then
        return "combat"
    end
    if IsSwimming() then
        return "swimming"
    end

    local speed = GetUnitSpeed("player")

    if IsMounted() then
        if speed > 0 then
            return "mounted"
        else
            return "idle"
        end
    end

    if speed > 7 then
        return "running"
    elseif speed > 0 then
        return "walking"
    end
    return "idle"
end

local function GetBaseHungerRate(state)
    if state == "combat" then
        return HUNGER_RATE_COMBAT
    elseif state == "swimming" then
        return HUNGER_RATE_SWIMMING
    elseif state == "mounted" then
        return HUNGER_RATE_MOUNTED
    elseif state == "running" then
        return HUNGER_RATE_RUNNING
    elseif state == "walking" then
        return HUNGER_RATE_WALKING
    end
    return 0
end

local function GetHungerMultiplier()
    local tempFactor = 1.0
    local exhaustionFactor = 1.0

    if cachedSettings.temperatureEnabled then
        local temp = WL.GetTemperature and WL.GetTemperature() or 0
        if temp < 0 then
            tempFactor = 1.0 + (math_abs(temp) / 100) * 1.0
        end
    end

    if cachedSettings.exhaustionEnabled then
        local exhaustion = WL.GetExhaustion and WL.GetExhaustion() or 0
        exhaustionFactor = 1.0 + (exhaustion / 100) * 0.5
    end

    return tempFactor * exhaustionFactor
end

local function GetCurrentCheckpoint()
    if IsResting() then
        return CHECKPOINT_RESTED
    elseif WL.isNearFire then
        return CHECKPOINT_FIRE
    else
        return CHECKPOINT_WORLD
    end
end

function WL.ResetHungerFromTrainer()
    hunger = CHECKPOINT_TRAINER
    WL.Debug("Hunger reset by cooking trainer", "hunger")
end

function WL.ResetHungerFromInnkeeper()
    if WL.GetSetting("innkeeperResetsHunger") then
        local threshold = math_floor(MAX_HUNGER * 0.15)
        if hunger > threshold then
            hunger = threshold
            WL.Debug("Hunger healed to 85% by innkeeper", "hunger")
            return true
        else
            WL.Debug(string.format("Hunger already at %.1f%% (below 15%%), innkeeper has no effect", hunger), "hunger")
            return false
        end
    end
    return false
end

local function UpdateHunger(elapsed)
    if not ShouldUpdateHunger() then
        isDecaying = false
        return
    end

    if isInDungeon then
        isDecaying = false
        return
    end

    if UnitOnTaxi("player") then
        isDecaying = false
        return
    end

    local hasWellFed = HasWellFedBuff()
    local isEating = IsPlayerEating()
    local isResting = IsResting()
    local checkpoint = GetCurrentCheckpoint()

    if hasWellFed then
        if isEating then
            if hunger > checkpoint then
                isDecaying = true
                local recoveryRate = isResting and RESTED_EATING_RECOVERY or EATING_RECOVERY_RATE
                local newHunger = hunger - (recoveryRate * elapsed)
                if newHunger < checkpoint then
                    newHunger = checkpoint
                end
                hunger = math_max(MIN_HUNGER, newHunger)
                WL.Debug(string.format("Well Fed + Eating: hunger decreasing %.1f%% -> checkpoint %d%%", hunger, checkpoint), "hunger")
            else
                isDecaying = false
                WL.Debug(string.format("Well Fed + Eating: at/below checkpoint %.1f%% <= %d%% (no change)", hunger, checkpoint), "hunger")
            end
            return
        end
        if hunger > checkpoint and isResting then
            isDecaying = true
            local newHunger = hunger - (EATING_RECOVERY_RATE * 0.5 * elapsed); if newHunger < checkpoint then newHunger = checkpoint end; hunger = math_max(MIN_HUNGER, newHunger)
        else
            isDecaying = false
        end
        return
    end

    if isEating then
        if hunger > checkpoint then
            isDecaying = true
            local recoveryRate = isResting and RESTED_EATING_RECOVERY or EATING_RECOVERY_RATE
            local newHunger = hunger - (recoveryRate * elapsed)

            if newHunger < checkpoint then
                newHunger = checkpoint
            end

            hunger = math_max(MIN_HUNGER, newHunger)
            WL.Debug(string.format("Eating: hunger %.1f%% (checkpoint: %d%%)", hunger, checkpoint), "hunger")
        else
            isDecaying = false
            WL.Debug(string.format("Eating: at checkpoint %.1f%% <= %d%% (no effect)", hunger, checkpoint), "hunger")
        end
        return
    end

    isDecaying = false

    local state = GetMovementState()
    local baseRate = GetBaseHungerRate(state)
    local multiplier = GetHungerMultiplier()
    local hungerRate = baseRate * multiplier

    if hungerRate > 0 and WL.IsLingeringActive and WL.IsLingeringActive("disease") then
        hungerRate = hungerRate * 3
    end

    hunger = math_min(MAX_HUNGER, hunger + (hungerRate * elapsed))

    if WL.GetSetting("hungerDebugEnabled") then
        WL.Debug(string.format("Hunger: %.1f%% | Rate: %.3f/s (base: %.3f x %.2f) | State: %s", hunger, hungerRate,
            baseRate, multiplier, state), "hunger")
    end
end

function WL.HandleHungerUpdate(elapsed)
    UpdateHunger(elapsed)
end

function WL.HandleHungerDarknessUpdate(elapsed)
    UpdateHungerDarkness(elapsed)
end

local function CheckDungeonStatus()
    isInDungeon = WL.IsInDungeonOrRaid()
end

function WL.GetHunger()
    return hunger
end

function WL.SetHunger(value)
    hunger = math_max(MIN_HUNGER, math_min(MAX_HUNGER, value))
end

function WL.ApplyLingeringHungerDrain(amount)
    amount = tonumber(amount)
    if not amount or amount <= 0 then
        return
    end
    if not ShouldUpdateHunger() then
        return
    end
    hunger = math_min(MAX_HUNGER, hunger + amount)
end

function WL.IsHungerDecaying()
    return isDecaying
end

function WL.IsHungerPaused()
    if not cachedSettings.hungerEnabled then
        return false
    end
    if not WL.IsPlayerEligible() then
        return false
    end
    return isInDungeon or UnitOnTaxi("player") or UnitIsDead("player") or UnitIsGhost("player")
end

function WL.GetHungerCheckpoint()
    return GetCurrentCheckpoint()
end

function WL.GetHungerMovementState()
    return GetMovementState()
end

function WL.HasWellFedBuff()
    return HasWellFedBuff()
end

function WL.GetHungerActivity()
    if WL.IsHungerPaused() then
        return nil
    end
    if isDecaying then
        if IsPlayerEating() then
            return "Eating"
        elseif HasWellFedBuff() and IsResting() then
            return "Resting (Well Fed)"
        elseif HasWellFedBuff() then
            return "Well Fed"
        else
            return "Recovering"
        end
    end
    if HasWellFedBuff() then
        return "Well Fed"
    end
    local state = GetMovementState()
    if state == "combat" then
        return "In combat"
    elseif state == "swimming" then
        return "Swimming"
    elseif state == "mounted" then
        return "Mounted"
    elseif state == "running" then
        return "Running"
    elseif state == "walking" then
        return "Walking"
    end
    return nil
end

local eventFrame = CreateFrame("Frame", "WanderlustHungerFrame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        RefreshCachedSettings()
        CreateHungerDarknessFrame()
        if WL.charDB and WL.charDB.savedHunger then
            hunger = WL.charDB.savedHunger
            WL.Debug(string.format("Hunger restored: %.1f%%", hunger), "hunger")
        end
        CheckDungeonStatus()
    elseif event == "PLAYER_ENTERING_WORLD" then
        CheckDungeonStatus()
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        CheckDungeonStatus()
    end
end)

WL.RegisterCallback("SETTINGS_CHANGED", function(key)
    if key == "hungerEnabled" or key == "hungerMaxDarkness" or key == "hungerOverlayEnabled" or
        key == "temperatureEnabled" or key == "exhaustionEnabled" or key == "ALL" then
        RefreshCachedSettings()
    end
    if key == "pauseInInstances" or key == "ALL" then
        CheckDungeonStatus()
    end
end)

WL.RegisterCallback("PLAYER_LOGOUT", function()
    if WL.charDB then
        WL.charDB.savedHunger = hunger
    end
end)
