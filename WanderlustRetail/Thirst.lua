-- Wanderlust - thirst system
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
-- Midnight compatibility helpers
-- - Aura scanning: UnitBuff was removed in modern clients
-- - Asset paths: prefer WL.ASSET_PATH when available
-- - Callback registration: safely defer if Core isn't ready yet
----------------------------------------------------------------
local function WL_GetAssetBase()
    local base = (WL and WL.ASSET_PATH) or "Interface\\AddOns\\Wanderlust\\"
    if type(base) ~= "string" then
        base = "Interface\\AddOns\\Wanderlust\\"
    end
    if base:sub(-1) ~= "\\" then
        base = base .. "\\"
    end
    return base
end

local ASSET_BASE = WL_GetAssetBase()
local function Asset(relPath)
    return ASSET_BASE .. relPath
end

local function GetBuffNameByIndex(index)
    -- Modern (Retail/Midnight)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local aura = C_UnitAuras.GetAuraDataByIndex("player", index, "HELPFUL")
        if aura then return aura.name end
    end
    -- AuraUtil fallback
    if AuraUtil and AuraUtil.GetAuraDataByIndex then
        local aura = AuraUtil.GetAuraDataByIndex("player", index, "HELPFUL")
        if aura then return aura.name end
    end
    -- Legacy clients
    if type(UnitBuff) == "function" then
        return UnitBuff("player", index)
    end
    return nil
end

local pendingCallbacks
local function RegisterCallbackOrDefer(eventName, fn)
    if WL and type(WL.RegisterCallback) == "function" then
        WL.RegisterCallback(eventName, fn)
        return
    end
    pendingCallbacks = pendingCallbacks or {}
    pendingCallbacks[#pendingCallbacks + 1] = { eventName, fn }
end

local function FlushPendingCallbacks()
    if not pendingCallbacks then return end
    if not WL or type(WL.RegisterCallback) ~= "function" then return end
    for _, cb in ipairs(pendingCallbacks) do
        WL.RegisterCallback(cb[1], cb[2])
    end
    pendingCallbacks = nil
end
local cachedSettings = {
    thirstEnabled = nil,
    thirstMaxDarkness = nil,
    thirstOverlayEnabled = nil,
    temperatureEnabled = nil,
    exhaustionEnabled = nil
}

local function RefreshCachedSettings()
    if not WL.GetSetting then
        return
    end
    cachedSettings.thirstEnabled = WL.GetSetting("thirstEnabled")
    cachedSettings.thirstMaxDarkness = WL.GetSetting("thirstMaxDarkness")
    cachedSettings.thirstOverlayEnabled = WL.GetSetting("thirstOverlayEnabled")
    cachedSettings.temperatureEnabled = WL.GetSetting("temperatureEnabled")
    cachedSettings.exhaustionEnabled = WL.GetSetting("exhaustionEnabled")
end

local thirst = 0

local MIN_THIRST = 0
local MAX_THIRST = 100

local THIRST_RATE_WALKING = 0.0144
local THIRST_RATE_RUNNING = 0.0216
local THIRST_RATE_MOUNTED = 0.0108
local THIRST_RATE_COMBAT = 0.045
local DRINKING_RECOVERY_RATE = 0.4
local RESTED_DRINKING_RECOVERY = 0.6
local RAIN_RECOVERY_RATE = 0.024
local SWIMMING_RECOVERY_RATE = 0.012

local CHECKPOINT_WORLD = 75
local CHECKPOINT_FIRE = 50
local CHECKPOINT_RESTED = 25
local CHECKPOINT_TRAINER = 0

local isInDungeon = false
local isDecaying = false

local manaPotionQuenchingActive = false
local manaPotionQuenchingRemaining = 0
local MANA_POTION_QUENCH_DURATION = 120.0
local MANA_POTION_QUENCH_CHECKPOINT = 50
local MANA_POTION_QUENCH_RATE = 0.15

local thirstDarknessFrame = nil
local thirstDarknessCurrentAlpha = 0
local thirstDarknessTargetAlpha = 0
local THIRST_DARKNESS_LERP_SPEED = 0.8

local function CreateThirstDarknessFrame()
    if thirstDarknessFrame then
        return thirstDarknessFrame
    end

    local frame = CreateFrame("Frame", "WanderlustThirstDarkness", UIParent)
    frame:SetAllPoints(UIParent)
    frame:SetFrameStrata("BACKGROUND")
    frame:SetFrameLevel(0)

    frame.texture = frame:CreateTexture(nil, "BACKGROUND")
    frame.texture:SetAllPoints()
    frame.texture:SetTexture(Asset("assets\\tunnel_vision_4.png"))
    frame.texture:SetBlendMode("BLEND")
    frame.texture:SetVertexColor(0.7, 0.8, 1.0)

    frame:SetAlpha(0)
    frame:Show()

    frame:EnableMouse(false)

    thirstDarknessFrame = frame
    return frame
end

local function GetThirstDarknessTarget()
    if not cachedSettings.thirstEnabled then
        return 0
    end
    if not cachedSettings.thirstOverlayEnabled then
        return 0
    end
    if not WL.IsPlayerEligible() then
        return 0
    end
    local maxDarkness = cachedSettings.thirstMaxDarkness or 0.25
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
    return (thirst / MAX_THIRST) * maxDarkness
end

local function UpdateThirstDarkness(elapsed)
    if not thirstDarknessFrame then
        return
    end

    thirstDarknessTargetAlpha = GetThirstDarknessTarget()

    local diff = thirstDarknessTargetAlpha - thirstDarknessCurrentAlpha
    if math_abs(diff) < 0.001 then
        thirstDarknessCurrentAlpha = thirstDarknessTargetAlpha
    else
        thirstDarknessCurrentAlpha = thirstDarknessCurrentAlpha + (diff * THIRST_DARKNESS_LERP_SPEED * elapsed)
    end

    thirstDarknessCurrentAlpha = math_max(0, math_min(1, thirstDarknessCurrentAlpha))

    thirstDarknessFrame:SetAlpha(thirstDarknessCurrentAlpha)
end

local function ShouldUpdateThirst()
    if not cachedSettings.thirstEnabled then
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

local REFRESHED_BUFFS = {
    ["Refreshed"] = true,
    ["Mana Regeneration"] = true,
    ["Spirit of Zanza"] = true,
    ["Gordok Green Grog"] = true,
    ["Rumsey Rum Black Label"] = true,
}

local BUFF_SCAN_INTERVAL = 0.2
local lastDrinkBuffCheck = 0
local cachedRefreshed = false
local cachedDrinking = false

local function UpdateDrinkBuffState()
    local now = GetTime()
    if now - lastDrinkBuffCheck < BUFF_SCAN_INTERVAL then
        return
    end
    lastDrinkBuffCheck = now
    cachedRefreshed = false
    cachedDrinking = false

    for i = 1, 40 do
        local name = GetBuffNameByIndex(i)
        if not name then
            break
        end
        if not cachedRefreshed and (REFRESHED_BUFFS[name] or name:match("Refreshed")) then
            cachedRefreshed = true
        end
        if not cachedDrinking and (name == "Drink" or name == "Refreshment" or name == "Food & Drink") then
            cachedDrinking = true
        end
        if cachedRefreshed and cachedDrinking then
            break
        end
    end
end

local function HasRefreshedBuff()
    UpdateDrinkBuffState()
    return cachedRefreshed
end

local function IsPlayerDrinking()
    UpdateDrinkBuffState()
    return cachedDrinking
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

local function GetBaseThirstRate(state)
    if state == "combat" then
        return THIRST_RATE_COMBAT
    elseif state == "swimming" then
        return 0
    elseif state == "mounted" then
        return THIRST_RATE_MOUNTED
    elseif state == "running" then
        return THIRST_RATE_RUNNING
    elseif state == "walking" then
        return THIRST_RATE_WALKING
    end
    return 0
end

local function GetThirstMultiplier()
    local tempFactor = 1.0
    local exhaustionFactor = 1.0

    if cachedSettings.temperatureEnabled then
        local temp = WL.GetTemperature and WL.GetTemperature() or 0
        if temp > 0 then
            tempFactor = 1.0 + (temp / 100) * 1.0
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

function WL.ResetThirstFromTrainer()
    thirst = CHECKPOINT_TRAINER
    WL.Debug("Thirst reset by cooking trainer", "thirst")
end

function WL.ResetThirstFromInnkeeper()
    if WL.GetSetting("innkeeperResetsThirst") then
        local threshold = math_floor(MAX_THIRST * 0.15)
        if thirst > threshold then
            thirst = threshold
            WL.Debug("Thirst healed to 85% by innkeeper", "thirst")
            return true
        else
            WL.Debug(string.format("Thirst already at %.1f%% (below 15%%), innkeeper has no effect", thirst), "thirst")
            return false
        end
    end
    return false
end

local function UpdateThirst(elapsed)
    if not ShouldUpdateThirst() then
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

    local hasRefreshed = HasRefreshedBuff()
    local isDrinking = IsPlayerDrinking()
    local isResting = IsResting()
    local checkpoint = GetCurrentCheckpoint()

    if hasRefreshed then
        if isDrinking then
            if thirst > checkpoint then
                isDecaying = true
                local recoveryRate = isResting and RESTED_DRINKING_RECOVERY or DRINKING_RECOVERY_RATE
                local newThirst = thirst - (recoveryRate * elapsed)
                if newThirst < checkpoint then
                    newThirst = checkpoint
                end
                thirst = math_max(MIN_THIRST, newThirst)
                WL.Debug(string.format("Refreshed + Drinking: thirst decreasing %.1f%% -> checkpoint %d%%", thirst, checkpoint), "thirst")
            else
                isDecaying = false
                WL.Debug(string.format("Refreshed + Drinking: at/below checkpoint %.1f%% <= %d%% (no change)", thirst, checkpoint), "thirst")
            end
            return
        end
        if thirst > checkpoint and isResting then
            isDecaying = true
            local newThirst = thirst - (DRINKING_RECOVERY_RATE * 0.5 * elapsed); if newThirst < checkpoint then newThirst = checkpoint end; thirst = math_max(MIN_THIRST, newThirst)
        else
            isDecaying = false
        end
        return
    end

    if isDrinking then
        if thirst > checkpoint then
            isDecaying = true
            local recoveryRate = isResting and RESTED_DRINKING_RECOVERY or DRINKING_RECOVERY_RATE
            local newThirst = thirst - (recoveryRate * elapsed)

            if newThirst < checkpoint then
                newThirst = checkpoint
            end

            thirst = math_max(MIN_THIRST, newThirst)
            WL.Debug(string.format("Drinking: thirst %.1f%% (checkpoint: %d%%)", thirst, checkpoint), "thirst")
        else
            isDecaying = false
            WL.Debug(string.format("Drinking: at checkpoint %.1f%% <= %d%% (no effect)", thirst, checkpoint), "thirst")
        end
        return
    end

    isDecaying = false

    if manaPotionQuenchingActive then
        manaPotionQuenchingRemaining = manaPotionQuenchingRemaining - elapsed
        if manaPotionQuenchingRemaining <= 0 then
            manaPotionQuenchingActive = false
            WL.Debug("Mana potion quenching finished", "thirst")
        elseif thirst > MANA_POTION_QUENCH_CHECKPOINT then
            isDecaying = true
            local newThirst = thirst - (MANA_POTION_QUENCH_RATE * elapsed)
            if newThirst < MANA_POTION_QUENCH_CHECKPOINT then
                newThirst = MANA_POTION_QUENCH_CHECKPOINT
            end
            thirst = math_max(MIN_THIRST, newThirst)
            WL.Debug(string.format("Mana potion quenching: thirst %.1f%% (limit: %d%%)", thirst, MANA_POTION_QUENCH_CHECKPOINT), "thirst")
        end
    end

    if IsSwimming() then
        if thirst > checkpoint then
            isDecaying = true
            local newThirst = thirst - (SWIMMING_RECOVERY_RATE * elapsed)
            if newThirst < checkpoint then
                newThirst = checkpoint
            end
            thirst = math_max(MIN_THIRST, newThirst)
            WL.Debug(string.format("Swimming: thirst recovering %.1f%% (checkpoint: %d%%)", thirst, checkpoint), "thirst")
        end
        return
    end

    local isRaining = WL.IsRaining and WL.IsRaining()
    if isRaining then
        if thirst > checkpoint then
            isDecaying = true
            local newThirst = thirst - (RAIN_RECOVERY_RATE * elapsed)
            if newThirst < checkpoint then
                newThirst = checkpoint
            end
            thirst = math_max(MIN_THIRST, newThirst)
            WL.Debug(string.format("Rain: thirst recovering %.1f%% (checkpoint: %d%%)", thirst, checkpoint), "thirst")
        end
        return
    end

    local state = GetMovementState()
    local baseRate = GetBaseThirstRate(state)
    local multiplier = GetThirstMultiplier()
    local thirstRate = baseRate * multiplier

    if thirstRate > 0 and WL.IsLingeringActive and WL.IsLingeringActive("poison") then
        thirstRate = thirstRate * 3
    end

    thirst = math_min(MAX_THIRST, thirst + (thirstRate * elapsed))

    if WL.GetSetting("thirstDebugEnabled") then
        WL.Debug(string.format("Thirst: %.1f%% | Rate: %.3f/s (base: %.3f x %.2f) | State: %s", thirst, thirstRate,
            baseRate, multiplier, state), "thirst")
    end
end

function WL.HandleThirstUpdate(elapsed)
    UpdateThirst(elapsed)
end

function WL.HandleThirstDarknessUpdate(elapsed)
    UpdateThirstDarkness(elapsed)
end

local function CheckDungeonStatus()
    isInDungeon = WL.IsInDungeonOrRaid()
end

function WL.GetThirst()
    return thirst
end

function WL.SetThirst(value)
    thirst = math_max(MIN_THIRST, math_min(MAX_THIRST, value))
end

function WL.ApplyLingeringThirstDrain(amount)
    amount = tonumber(amount)
    if not amount or amount <= 0 then
        return
    end
    if not ShouldUpdateThirst() then
        return
    end
    thirst = math_min(MAX_THIRST, thirst + amount)
end

function WL.IsThirstDecaying()
    return isDecaying
end

function WL.IsThirstPaused()
    if not cachedSettings.thirstEnabled then
        return false
    end
    if not WL.IsPlayerEligible() then
        return false
    end
    return isInDungeon or UnitOnTaxi("player") or UnitIsDead("player") or UnitIsGhost("player")
end

function WL.GetThirstCheckpoint()
    return GetCurrentCheckpoint()
end

function WL.GetThirstMovementState()
    return GetMovementState()
end

function WL.HasRefreshedBuff()
    return HasRefreshedBuff()
end

function WL.IsPlayerDrinking()
    return IsPlayerDrinking()
end

function WL.StartManaPotionQuenching()
    if isInDungeon then
        return
    end
    manaPotionQuenchingActive = true
    manaPotionQuenchingRemaining = MANA_POTION_QUENCH_DURATION
    WL.Debug(string.format("Mana potion thirst quenching started: %ds (limit: %d%%)",
        MANA_POTION_QUENCH_DURATION, MANA_POTION_QUENCH_CHECKPOINT), "thirst")
end

function WL.IsManaPotionQuenching()
    return manaPotionQuenchingActive
end

function WL.GetManaPotionQuenchRemaining()
    return manaPotionQuenchingRemaining
end

function WL.GetThirstActivity()
    if WL.IsThirstPaused() then
        return nil
    end
    if isDecaying then
        if IsPlayerDrinking() then
            return "Drinking"
        elseif manaPotionQuenchingActive and thirst > MANA_POTION_QUENCH_CHECKPOINT then
            return "Mana Potion"
        elseif IsSwimming() then
            return "Swimming"
        elseif WL.IsRaining and WL.IsRaining() then
            return "In Rain"
        elseif HasRefreshedBuff() and IsResting() then
            return "Resting (Refreshed)"
        elseif HasRefreshedBuff() then
            return "Refreshed"
        else
            return "Recovering"
        end
    end
    if HasRefreshedBuff() then
        return "Refreshed"
    end
    if manaPotionQuenchingActive then
        return "Mana Potion"
    end
    if IsSwimming() then
        return "Swimming"
    end
    local isRaining = WL.IsRaining and WL.IsRaining()
    if isRaining then
        return "In Rain"
    end
    local state = GetMovementState()
    if state == "combat" then
        return "In combat"
    elseif state == "mounted" then
        return "Mounted"
    elseif state == "running" then
        return "Running"
    elseif state == "walking" then
        return "Walking"
    end
    return nil
end

local eventFrame = CreateFrame("Frame", "WanderlustThirstFrame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        RefreshCachedSettings()
        ASSET_BASE = WL_GetAssetBase()
        FlushPendingCallbacks()
        CreateThirstDarknessFrame()
        if WL.charDB and WL.charDB.savedThirst then
            thirst = WL.charDB.savedThirst
            WL.Debug(string.format("Thirst restored: %.1f%%", thirst), "thirst")
        end
        CheckDungeonStatus()
    elseif event == "PLAYER_ENTERING_WORLD" then
        CheckDungeonStatus()
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        CheckDungeonStatus()
    end
end)

RegisterCallbackOrDefer("SETTINGS_CHANGED", function(key)
    if key == "thirstEnabled" or key == "thirstMaxDarkness" or key == "thirstOverlayEnabled" or
        key == "temperatureEnabled" or key == "exhaustionEnabled" or key == "ALL" then
        RefreshCachedSettings()
    end
    if key == "pauseInInstances" or key == "ALL" then
        CheckDungeonStatus()
    end
end)

RegisterCallbackOrDefer("PLAYER_LOGOUT", function()
    if WL.charDB then
        WL.charDB.savedThirst = thirst
    end
end)
