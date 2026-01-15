-- Wanderlust - exhaustion system
local WL = Wanderlust
local ASSET_PATH = (WL and WL.ASSET_PATH) or "Interface\\AddOns\\Wanderlust\\assets\\"
local math_abs = math.abs
local math_max = math.max
local math_min = math.min
local math_pi = math.pi
local math_sin = math.sin

local exhaustion = 0
local savedExhaustion = 0
local maxExhaustion = 100
local isInDungeon = false

local EXHAUST_TEXTURES = {
    ASSET_PATH .. "exhaustion20.png",
    ASSET_PATH .. "exhaustion40.png",
    ASSET_PATH .. "exhaustion60.png",
    ASSET_PATH .. "exhaustion80.png"
}

local exhaustOverlayFrames = {}
local exhaustOverlayCurrentAlphas = {0, 0, 0, 0}
local exhaustOverlayTargetAlphas = {0, 0, 0, 0}

local exhaustOverlayPulsePhase = 0
local EXHAUST_OVERLAY_PULSE_SPEED = 0.5
local EXHAUST_OVERLAY_PULSE_MIN = 0.7
local EXHAUST_OVERLAY_PULSE_MAX = 1.0

local function GetExhaustOverlayLevel()
    if exhaustion >= 80 then
        return 4
    elseif exhaustion >= 60 then
        return 3
    elseif exhaustion >= 40 then
        return 2
    elseif exhaustion >= 20 then
        return 1
    else
        return 0
    end
end

local function CreateExhaustOverlayFrame(level)
    if exhaustOverlayFrames[level] then
        return exhaustOverlayFrames[level]
    end

    local frame = CreateFrame("Frame", "WanderlustExhaustOverlay_" .. level, UIParent)
    frame:SetAllPoints(UIParent)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(90 + level)

    frame.texture = frame:CreateTexture(nil, "BACKGROUND")
    frame.texture:SetAllPoints()
    frame.texture:SetTexture(EXHAUST_TEXTURES[level])
    frame.texture:SetBlendMode("BLEND")

    frame:SetAlpha(0)
    frame:Hide()

    exhaustOverlayFrames[level] = frame
    return frame
end

local function CreateAllExhaustOverlayFrames()
    for i = 1, 4 do
        CreateExhaustOverlayFrame(i)
    end
end

local function ShouldShowExhaustOverlay()
    if not WL.GetSetting("exhaustionEnabled") then
        return false
    end
    if not WL.GetSetting("exhaustionOverlayEnabled") then
        return false
    end
    if not WL.IsPlayerEligible() then
        return false
    end
    if isInDungeon then
        return false
    end
    if UnitOnTaxi("player") then
        return false
    end
    if UnitIsDead("player") or UnitIsGhost("player") then
        return false
    end
    return true
end

local function UpdateExhaustOverlayAlphas(elapsed)
    exhaustOverlayPulsePhase = exhaustOverlayPulsePhase + elapsed * EXHAUST_OVERLAY_PULSE_SPEED
    if exhaustOverlayPulsePhase > 1 then
        exhaustOverlayPulsePhase = exhaustOverlayPulsePhase - 1
    end

    local pulseRange = EXHAUST_OVERLAY_PULSE_MAX - EXHAUST_OVERLAY_PULSE_MIN
    local pulseMod = EXHAUST_OVERLAY_PULSE_MIN +
                         (pulseRange * (0.5 + 0.5 * math_sin(exhaustOverlayPulsePhase * math_pi * 2)))

    if not ShouldShowExhaustOverlay() then
        for i = 1, 4 do
            exhaustOverlayTargetAlphas[i] = 0
        end
    else
        local level = GetExhaustOverlayLevel()
        for i = 1, 4 do
            if i <= level then
                exhaustOverlayTargetAlphas[i] = 0.7
                if exhaustOverlayFrames[i] and not exhaustOverlayFrames[i]:IsShown() then
                    exhaustOverlayFrames[i]:SetAlpha(0)
                    exhaustOverlayFrames[i]:Show()
                end
            else
                exhaustOverlayTargetAlphas[i] = 0
            end
        end
    end

    for i = 1, 4 do
        local frame = exhaustOverlayFrames[i]
        if frame then
            local diff = exhaustOverlayTargetAlphas[i] - exhaustOverlayCurrentAlphas[i]
            if math_abs(diff) < 0.01 then
                exhaustOverlayCurrentAlphas[i] = exhaustOverlayTargetAlphas[i]
            else
                local speed = diff > 0 and 2.0 or 1.0
                exhaustOverlayCurrentAlphas[i] = exhaustOverlayCurrentAlphas[i] + (diff * speed * elapsed)
            end
            exhaustOverlayCurrentAlphas[i] = math_max(0, math_min(1, exhaustOverlayCurrentAlphas[i]))
            frame:SetAlpha(exhaustOverlayCurrentAlphas[i] * pulseMod)

            if exhaustOverlayCurrentAlphas[i] <= 0.01 and exhaustOverlayTargetAlphas[i] == 0 then
                frame:Hide()
                exhaustOverlayCurrentAlphas[i] = 0
            end
        end
    end
end

local RATE_ON_FOOT = 0.025
local RATE_ON_MOUNT = 0.005
local RATE_IN_COMBAT = 0.05
local RATE_SWIMMING = 0.04

local LOW_CONSTITUTION_THRESHOLD = 25
local LOW_CONSTITUTION_RUN_MULTIPLIER = 3.0
local LOW_CONSTITUTION_WALK_SPEED = 7
local lowConstitutionWarningCooldown = 0

local currentGlowType = 0
local currentGlowIntensity = 0
local GLOW_DECAY_RATE = 3.0
local isDecaying = false

local function CheckDungeonStatus()
    return WL.IsInDungeonOrRaid()
end

local function CanDecayExhaustion()
    if WL.inCombat then
        return false
    end
    if isInDungeon then
        return false
    end
    if UnitOnTaxi("player") then
        return false
    end
    if IsResting() then
        return true
    end
    if WL.isNearFire then
        return true
    end
    return false
end

local function ShouldAccumulateExhaustion()
    if not WL.GetSetting("exhaustionEnabled") then
        return false
    end
    if not WL.IsPlayerEligible() then
        return false
    end
    if isInDungeon then
        return false
    end
    if UnitOnTaxi("player") then
        return false
    end

    local onlyExhaustion = WL.GetSetting("exhaustionEnabled") and not WL.GetSetting("AnguishEnabled") and
                               not WL.GetSetting("hungerEnabled") and not WL.GetSetting("temperatureEnabled")
    if onlyExhaustion then
        if WL.GetSetting("fireDetectionMode") == 2 then
            return WL.isManualRestActive
        end
        return true
    end

    if IsResting() then
        return false
    end
    return true
end

local function IsPlayerMounted()
    return IsMounted() or UnitOnTaxi("player")
end

local function GetMovementRate()
    if WL.inCombat then
        return RATE_IN_COMBAT
    elseif IsSwimming() then
        return RATE_SWIMMING
    elseif IsPlayerMounted() then
        return RATE_ON_MOUNT
    else
        return RATE_ON_FOOT
    end
end

local function CheckMovementAndAccumulate(elapsed)
    if not ShouldAccumulateExhaustion() then
        currentGlowType = 0
        return
    end

    if lowConstitutionWarningCooldown > 0 then
        lowConstitutionWarningCooldown = lowConstitutionWarningCooldown - elapsed
    end

    local playerSpeed = GetUnitSpeed("player")
    local isActivelyMoving = playerSpeed > 0
    local isRunning = playerSpeed > LOW_CONSTITUTION_WALK_SPEED

    local constitution = WL.GetConstitution and WL.GetConstitution()
    local lowConstitutionPenalty = false
    if constitution and constitution < LOW_CONSTITUTION_THRESHOLD and isRunning and not IsPlayerMounted() then
        lowConstitutionPenalty = true
        if lowConstitutionWarningCooldown <= 0 then
            print("|cffFF6600Wanderlust:|r |cffFFAAAAYou're too weak to run! Walking is safer.|r")
            lowConstitutionWarningCooldown = 10
        end
    end

    if WL.inCombat then
        currentGlowType = 3
        currentGlowIntensity = 1.0
    elseif IsSwimming() then
        currentGlowType = 2.5
        currentGlowIntensity = 0.9
    elseif isActivelyMoving then
        if IsPlayerMounted() then
            currentGlowType = 1
            currentGlowIntensity = 0.5
        else
            currentGlowType = 2
            currentGlowIntensity = lowConstitutionPenalty and 1.0 or 0.75
        end
    else
        currentGlowType = 0
        currentGlowIntensity = 0
    end

    if isActivelyMoving or WL.inCombat then
        local rate = GetMovementRate()
        if lowConstitutionPenalty then
            rate = rate * LOW_CONSTITUTION_RUN_MULTIPLIER
        end
        if rate > 0 and WL.IsLingeringActive and WL.IsLingeringActive("curse") then
            rate = rate * 3
        end
        local increase = rate * elapsed
        exhaustion = math_min(maxExhaustion, exhaustion + increase)
    end
end

local logTimer = 0

local function UpdateGlow(elapsed)
    if currentGlowType == 0 and currentGlowIntensity > 0 then
        currentGlowIntensity = currentGlowIntensity - (GLOW_DECAY_RATE * elapsed)
        if currentGlowIntensity <= 0 then
            currentGlowIntensity = 0
        end
    end
end

function WL.HandleExhaustionDecay(elapsed)
    UpdateGlow(elapsed)
    UpdateExhaustOverlayAlphas(elapsed)

    CheckMovementAndAccumulate(elapsed)

    if not CanDecayExhaustion() or exhaustion <= 0 then
        isDecaying = false
        return
    end

    isDecaying = true
    local rate
    if IsResting() then
        rate = WL.GetSetting("exhaustionInnDecayRate") or 1.5
    else
        rate = WL.GetSetting("exhaustionDecayRate") or 0.5
    end
    exhaustion = math_max(0, exhaustion - rate * elapsed)

    logTimer = logTimer + elapsed
    if logTimer >= 1.0 then
        logTimer = 0
        if WL.GetSetting("exhaustionDebugEnabled") then
            local location = IsResting() and "resting" or "near fire"
            WL.Debug(string.format("Recovering (%s @ %.1f/sec)... Exhaustion: %.1f%%", location, rate, exhaustion),
                "exhaustion")
        end
    end
end

function WL.GetExhaustionGlow()
    return currentGlowType, currentGlowIntensity
end

function WL.IsExhaustionDecaying()
    return isDecaying and exhaustion > 0
end

function WL.GetExhaustion()
    return exhaustion
end

function WL.GetExhaustionPercent()
    return exhaustion / maxExhaustion
end

function WL.SetExhaustion(value)
    value = tonumber(value)
    if not value then
        return false
    end
    exhaustion = math_min(maxExhaustion, math_max(0, value))
    WL.Debug(string.format("Exhaustion set to %.1f%%", exhaustion), "exhaustion")
    return true
end

function WL.ApplyLingeringExhaustionDrain(amount)
    amount = tonumber(amount)
    if not amount or amount <= 0 then
        return
    end
    if not ShouldAccumulateExhaustion() then
        return
    end
    exhaustion = math_min(maxExhaustion, exhaustion + amount)
end

function WL.ResetExhaustion()
    exhaustion = 0
end

function WL.IsInDungeon()
    return isInDungeon
end

function WL.IsExhaustionActive()
    return ShouldAccumulateExhaustion()
end

function WL.IsExhaustionPaused()
    if not WL.GetSetting("exhaustionEnabled") then
        return false
    end
    if not WL.IsPlayerEligible() then
        return false
    end
    return isInDungeon or UnitOnTaxi("player") or UnitIsDead("player") or UnitIsGhost("player")
end

function WL.GetExhaustionActivity()
    if WL.IsExhaustionPaused() then
        return nil
    end
    if isDecaying then
        if WL.isNearFire then
            return "Resting by fire"
        elseif IsResting() then
            return "Resting in town"
        end
        return "Recovering"
    end
    local states = {}
    local isSwimming = IsSwimming()

    if isSwimming then
        table.insert(states, "Swimming")
    end

    local glowType = currentGlowType
    if glowType >= 3 or WL.inCombat then
        table.insert(states, "In combat")
    elseif glowType >= 2 and not isSwimming then
        table.insert(states, "On foot")
    elseif glowType >= 1 and not isSwimming then
        table.insert(states, "Mounted")
    elseif glowType >= 0.5 and not isSwimming then
        table.insert(states, "Idle")
    end
    
    if #states > 0 then
        return table.concat(states, ", ")
    end
    return nil
end

local function OnZoneChanged()
    local wasInDungeon = isInDungeon
    isInDungeon = CheckDungeonStatus()

    if isInDungeon and not wasInDungeon then
        savedExhaustion = exhaustion
        WL.Debug(string.format("Entering dungeon - exhaustion paused at %.1f%%", savedExhaustion), "exhaustion")
    elseif not isInDungeon and wasInDungeon then
        exhaustion = savedExhaustion
        WL.Debug(string.format("Leaving dungeon - exhaustion restored to %.1f%%", exhaustion), "exhaustion")
    end
end

local eventFrame = CreateFrame("Frame", "WanderlustExhaustionFrame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_LOGIN" then
        CreateAllExhaustOverlayFrames()
        if WL.charDB and WL.charDB.savedExhaustion then
            exhaustion = WL.charDB.savedExhaustion
            WL.Debug(string.format("Exhaustion restored: %.1f%%", exhaustion), "exhaustion")
        else
            exhaustion = 0
        end
        isInDungeon = CheckDungeonStatus()
        if isInDungeon and WL.charDB and WL.charDB.savedExhaustionPreDungeon then
            savedExhaustion = WL.charDB.savedExhaustionPreDungeon
            WL.Debug(string.format("Pre-dungeon exhaustion restored: %.1f%%", savedExhaustion), "exhaustion")
        else
            savedExhaustion = 0
        end

    elseif event == "PLAYER_LOGOUT" then
        if WL.charDB then
            WL.charDB.savedExhaustion = exhaustion
            if isInDungeon then
                WL.charDB.savedExhaustionPreDungeon = savedExhaustion
            else
                WL.charDB.savedExhaustionPreDungeon = nil
            end
        end

    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        OnZoneChanged()
    end
end)

WL.RegisterCallback("SETTINGS_CHANGED", function(key)
    if key == "pauseInInstances" or key == "ALL" then
        OnZoneChanged()
    end
end)
