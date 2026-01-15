-- Wanderlust - temperature system
local WL = Wanderlust
local IsIndoors = IsIndoors
local IsSwimming = IsSwimming
local UnitIsDead = UnitIsDead
local UnitIsGhost = UnitIsGhost
local UnitOnTaxi = UnitOnTaxi
local GetTime = GetTime
local math_abs = math.abs
local math_ceil = math.ceil
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local math_pi = math.pi
local math_sin = math.sin


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
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local aura = C_UnitAuras.GetAuraDataByIndex("player", index, "HELPFUL")
        if aura then return aura.name end
    end
    if AuraUtil and AuraUtil.GetAuraDataByIndex then
        local aura = AuraUtil.GetAuraDataByIndex("player", index, "HELPFUL")
        if aura then return aura.name end
    end
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
    temperatureEnabled = nil,
    temperatureDebugEnabled = nil,
    temperatureOverlayEnabled = nil
}

local function RefreshCachedSettings()
    if not WL.GetSetting then
        return
    end
    cachedSettings.temperatureEnabled = WL.GetSetting("temperatureEnabled")
    cachedSettings.temperatureDebugEnabled = WL.GetSetting("temperatureDebugEnabled")
    cachedSettings.temperatureOverlayEnabled = WL.GetSetting("temperatureOverlayEnabled")
end

local temperature = 0
local savedTemperature = 0
local MIN_TEMPERATURE = -100
local MAX_TEMPERATURE = 100
local isInDungeon = false

local updateTimer = 0
local UPDATE_INTERVAL = 1.0

local COLD_TEXTURES = {
    Asset("assets\\cold20.png"),
    Asset("assets\\cold40.png"),
    Asset("assets\\cold60.png"),
    Asset("assets\\cold80.png"),
}

local HOT_TEXTURES = {
    Asset("assets\\hot20.png"),
    Asset("assets\\hot40.png"),
    Asset("assets\\hot60.png"),
    Asset("assets\\hot80.png"),
}

local DRYING_TEXTURE = Asset("assets\\hot20.png")

local coldOverlayFrames = {}
local coldOverlayCurrentAlphas = {0, 0, 0, 0}
local coldOverlayTargetAlphas = {0, 0, 0, 0}

local hotOverlayFrames = {}
local hotOverlayCurrentAlphas = {0, 0, 0, 0}
local hotOverlayTargetAlphas = {0, 0, 0, 0}
local DRYING_TEXTURE = "Interface\\AddOns\\Wanderlust\\assets\\hot20.png"
local dryingOverlayFrame = nil
local dryingOverlayCurrentAlpha = 0
local dryingOverlayTargetAlpha = 0
local DRYING_OVERLAY_MAX_ALPHA = 0.60
local DRYING_OVERLAY_FADE_SPEED = 2.0
local dryingOverlayPulsePhase = 0
local DRYING_PULSE_SPEED = 0.8
local DRYING_PULSE_MIN = 0.5
local DRYING_PULSE_MAX = 1.0

local tempOverlayPulsePhase = 0
local TEMP_OVERLAY_PULSE_SPEED = 0.5
local TEMP_OVERLAY_PULSE_MIN = 0.7
local TEMP_OVERLAY_PULSE_MAX = 1.0


local function GetColdOverlayLevel()
    local absTemp = math_abs(temperature)
    if temperature >= 0 then
        return 0
    end
    if absTemp >= 80 then
        return 4
    elseif absTemp >= 60 then
        return 3
    elseif absTemp >= 40 then
        return 2
    elseif absTemp >= 20 then
        return 1
    else
        return 0
    end
end

local function GetHotOverlayLevel()
    if temperature <= 0 then
        return 0
    end
    if temperature >= 80 then
        return 4
    elseif temperature >= 60 then
        return 3
    elseif temperature >= 40 then
        return 2
    elseif temperature >= 20 then
        return 1
    else
        return 0
    end
end

local function ShouldShowTemperatureOverlay()
    if not WL.GetSetting("temperatureEnabled") then
        return false
    end
    if not WL.GetSetting("temperatureOverlayEnabled") then
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
    return true
end

local function CreateColdOverlayFrame(level)
    if coldOverlayFrames[level] then
        return coldOverlayFrames[level]
    end

    local frame = CreateFrame("Frame", "WanderlustColdOverlay_" .. level, UIParent)
    frame:SetAllPoints(UIParent)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(80 + level)

    frame.texture = frame:CreateTexture(nil, "BACKGROUND")
    frame.texture:SetAllPoints()
    frame.texture:SetTexture(COLD_TEXTURES[level])
    frame.texture:SetBlendMode("BLEND")

    frame:SetAlpha(0)
    frame:Hide()

    coldOverlayFrames[level] = frame
    return frame
end

local function CreateHotOverlayFrame(level)
    if hotOverlayFrames[level] then
        return hotOverlayFrames[level]
    end

    local frame = CreateFrame("Frame", "WanderlustHotOverlay_" .. level, UIParent)
    frame:SetAllPoints(UIParent)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(80 + level)

    frame.texture = frame:CreateTexture(nil, "BACKGROUND")
    frame.texture:SetAllPoints()
    frame.texture:SetTexture(HOT_TEXTURES[level])
    frame.texture:SetBlendMode("BLEND")

    frame:SetAlpha(0)
    frame:Hide()

    hotOverlayFrames[level] = frame
    return frame
end

local function CreateDryingOverlayFrame()
    if dryingOverlayFrame then
        return dryingOverlayFrame
    end

    local frame = CreateFrame("Frame", "WanderlustDryingOverlay", UIParent)
    frame:SetAllPoints(UIParent)
    frame:SetFrameStrata("LOW")
    frame:SetFrameLevel(2)

    frame.texture = frame:CreateTexture(nil, "BACKGROUND")
    frame.texture:SetAllPoints()
    frame.texture:SetTexture(DRYING_TEXTURE)
    frame.texture:SetBlendMode("ADD")
    frame.texture:SetVertexColor(1.0, 0.6, 0.2)

    frame:SetAlpha(0)
    frame:Hide()

    dryingOverlayFrame = frame
    return frame
end

local function CreateAllTemperatureOverlayFrames()
    for i = 1, 4 do
        CreateColdOverlayFrame(i)
        CreateHotOverlayFrame(i)
    end
    CreateDryingOverlayFrame()
end

local function UpdateTemperatureOverlayAlphas(elapsed)
    tempOverlayPulsePhase = tempOverlayPulsePhase + elapsed * TEMP_OVERLAY_PULSE_SPEED
    if tempOverlayPulsePhase > 1 then
        tempOverlayPulsePhase = tempOverlayPulsePhase - 1
    end

    local pulseRange = TEMP_OVERLAY_PULSE_MAX - TEMP_OVERLAY_PULSE_MIN
    local pulseMod = TEMP_OVERLAY_PULSE_MIN + (pulseRange * (0.5 + 0.5 * math_sin(tempOverlayPulsePhase * math_pi * 2)))

    if not ShouldShowTemperatureOverlay() then
        for i = 1, 4 do
            coldOverlayTargetAlphas[i] = 0
            hotOverlayTargetAlphas[i] = 0
        end
    else
        local coldLevel = GetColdOverlayLevel()
        local hotLevel = GetHotOverlayLevel()

        for i = 1, 4 do
            if i <= coldLevel then
                coldOverlayTargetAlphas[i] = 0.7
                if coldOverlayFrames[i] and not coldOverlayFrames[i]:IsShown() then
                    coldOverlayFrames[i]:SetAlpha(0)
                    coldOverlayFrames[i]:Show()
                end
            else
                coldOverlayTargetAlphas[i] = 0
            end

            if i <= hotLevel then
                hotOverlayTargetAlphas[i] = 0.7
                if hotOverlayFrames[i] and not hotOverlayFrames[i]:IsShown() then
                    hotOverlayFrames[i]:SetAlpha(0)
                    hotOverlayFrames[i]:Show()
                end
            else
                hotOverlayTargetAlphas[i] = 0
            end
        end
    end

    for i = 1, 4 do
        local frame = coldOverlayFrames[i]
        if frame then
            local diff = coldOverlayTargetAlphas[i] - coldOverlayCurrentAlphas[i]
            if math_abs(diff) < 0.01 then
                coldOverlayCurrentAlphas[i] = coldOverlayTargetAlphas[i]
            else
                local speed = diff > 0 and 2.0 or 1.0
                coldOverlayCurrentAlphas[i] = coldOverlayCurrentAlphas[i] + (diff * speed * elapsed)
            end
            coldOverlayCurrentAlphas[i] = math_max(0, math_min(1, coldOverlayCurrentAlphas[i]))
            frame:SetAlpha(coldOverlayCurrentAlphas[i] * pulseMod)

            if coldOverlayCurrentAlphas[i] <= 0.01 and coldOverlayTargetAlphas[i] == 0 then
                frame:Hide()
                coldOverlayCurrentAlphas[i] = 0
            end
        end
    end

    for i = 1, 4 do
        local frame = hotOverlayFrames[i]
        if frame then
            local diff = hotOverlayTargetAlphas[i] - hotOverlayCurrentAlphas[i]
            if math_abs(diff) < 0.01 then
                hotOverlayCurrentAlphas[i] = hotOverlayTargetAlphas[i]
            else
                local speed = diff > 0 and 2.0 or 1.0
                hotOverlayCurrentAlphas[i] = hotOverlayCurrentAlphas[i] + (diff * speed * elapsed)
            end
            hotOverlayCurrentAlphas[i] = math_max(0, math_min(1, hotOverlayCurrentAlphas[i]))
            frame:SetAlpha(hotOverlayCurrentAlphas[i] * pulseMod)

            if hotOverlayCurrentAlphas[i] <= 0.01 and hotOverlayTargetAlphas[i] == 0 then
                frame:Hide()
                hotOverlayCurrentAlphas[i] = 0
            end
        end
    end
end

local function UpdateDryingOverlayAlpha(elapsed, isWet, isDrying)
    if not dryingOverlayFrame then
        CreateDryingOverlayFrame()
    end

    dryingOverlayPulsePhase = dryingOverlayPulsePhase + elapsed * DRYING_PULSE_SPEED
    if dryingOverlayPulsePhase > 1 then
        dryingOverlayPulsePhase = dryingOverlayPulsePhase - 1
    end

    local pulseRange = DRYING_PULSE_MAX - DRYING_PULSE_MIN
    local pulseMod = DRYING_PULSE_MIN + (pulseRange * (0.5 + 0.5 * math_sin(dryingOverlayPulsePhase * math_pi * 2)))

    if isWet and isDrying then
        dryingOverlayTargetAlpha = DRYING_OVERLAY_MAX_ALPHA
        if dryingOverlayFrame and not dryingOverlayFrame:IsShown() then
            dryingOverlayFrame:SetAlpha(0)
            dryingOverlayFrame:Show()
        end
    else
        dryingOverlayTargetAlpha = 0
    end

    if dryingOverlayFrame then
        local diff = dryingOverlayTargetAlpha - dryingOverlayCurrentAlpha
        if math_abs(diff) < 0.01 then
            dryingOverlayCurrentAlpha = dryingOverlayTargetAlpha
        else
            dryingOverlayCurrentAlpha = dryingOverlayCurrentAlpha + (diff * DRYING_OVERLAY_FADE_SPEED * elapsed)
        end
        dryingOverlayCurrentAlpha = math_max(0, math_min(1, dryingOverlayCurrentAlpha))

        dryingOverlayFrame:SetAlpha(dryingOverlayCurrentAlpha * pulseMod)

        if dryingOverlayCurrentAlpha <= 0.01 and dryingOverlayTargetAlpha == 0 then
            dryingOverlayFrame:Hide()
            dryingOverlayCurrentAlpha = 0
        end
    end
end

local COMFORTABLE_TEMP = 20

local ZONE_BASE_TEMPS = {
    ["elwynnforest"] = 24,
    ["westfall"] = 25,
    ["redridgemountains"] = 19,
    ["duskwood"] = 12,
    ["stranglethornvale"] = 30,
    ["tirisfalglades"] = 10,
    ["silverpineforest"] = 14,
    ["hillsbradfoothills"] = 18,
    ["arathihighlands"] = 22,
    ["wetlands"] = 16,
    ["lochmodan"] = 17,
    ["thehinterlands"] = 19,
    ["hinterlands"] = 19,
    ["westernplaguelands"] = 11,
    ["easternplaguelands"] = 10,
    ["deadwindpass"] = 9,
    ["swampofsorrows"] = 23,
    ["blastedlands"] = 39,
    ["badlands"] = 37,
    ["searinggorge"] = 41,
    ["burningsteppes"] = 42,
    ["dunmorogh"] = -5,
    ["alteracmountains"] = 8,

    ["stormwindcity"] = 22,
    ["stormwind"] = 22,
    ["ironforge"] = -8,
    ["undercity"] = 10,

    ["durotar"] = 36,
    ["mulgore"] = 20,
    ["thebarrens"] = 35,
    ["barrens"] = 35,
    ["teldrassil"] = 15,
    ["darkshore"] = 13,
    ["ashenvale"] = 12,
    ["stonetalonmountains"] = 20,
    ["desolace"] = 28,
    ["feralas"] = 22,
    ["dustwallowmarsh"] = 27,
    ["thousandneedles"] = 35,
    ["tanaris"] = 40,
    ["ungorocrater"] = 33,
    ["silithus"] = 38,
    ["azshara"] = 29,
    ["felwood"] = 12,
    ["winterspring"] = -10,
    ["moonglade"] = 18,

    ["orgrimmar"] = 38,
    ["thunderbluff"] = 25,
    ["darnassus"] = 16,

    ["ragefirechasm"] = 42,
    ["thewailingcaverns"] = 19,
    ["wailingcaverns"] = 19,
    ["thedeadmines"] = 25,
    ["deadmines"] = 25,
    ["shadowfangkeep"] = 18,
    ["blackfathomdeeps"] = 11,
    ["thestockade"] = 21,
    ["stockade"] = 21,
    ["gnomeregan"] = 24,
    ["razorfenkraul"] = 30,
    ["razorfendowns"] = 17,
    ["scarletmonastery"] = 19,
    ["uldaman"] = 30,
    ["zulfarrak"] = 43,
    ["maraudon"] = 31,
    ["templeofatalhakkar"] = 35,
    ["sunkentemple"] = 35,
    ["diremaul"] = 30,
    ["scholomance"] = 14,
    ["stratholme"] = 26,
    ["lowerblackrockspire"] = 38,
    ["upperblackrockspire"] = 38,
    ["blackrockspire"] = 38,
    ["blackrockdepths"] = 35,

    ["moltencore"] = 60,
    ["onyxiaslair"] = 50,
    ["blackwinglair"] = 55,
    ["zulgurub"] = 35,
    ["ruinsofahnqiraj"] = 40,
    ["templeofahnqiraj"] = 42,
    ["naxxramas"] = -5,

    ["warsonggulch"] = 20,
    ["arathibasin"] = 22,
    ["alteracvalley"] = -8,

    ["default"] = 20
}


local function GetZoneKey(zoneName)
    if not zoneName then
        return "default"
    end
    return zoneName:lower():gsub("%s+", ""):gsub("'", ""):gsub("-", "")
end

local function GetTimeFactor()
    local hour, minute = GetGameTime()
    local timeInHours = hour + (minute / 60)
    return math_sin((timeInHours - 8) * math_pi / 12)
end

local function GetFluctuationMagnitude(baseTemp)
    local distanceFromComfort = math_abs(baseTemp - COMFORTABLE_TEMP)
    return 4 + (distanceFromComfort * 0.2)
end

local function GetEnvironmentalTemperature(zoneName)
    local zoneKey = GetZoneKey(zoneName)
    local baseTemp = ZONE_BASE_TEMPS[zoneKey] or ZONE_BASE_TEMPS["default"]
    local timeFactor = GetTimeFactor()
    local fluctuation = GetFluctuationMagnitude(baseTemp)

    local envTemp = baseTemp + (timeFactor * fluctuation)

    return envTemp, baseTemp, timeFactor, fluctuation
end

local DAY_WARM_RATE = 1.5
local DAY_COOL_RATE = 0.6
local NIGHT_COOL_RATE = 1.5
local NIGHT_WARM_RATE = 0.6

local function GetDirectionalRateModifier(tempChangeDirection)
    local timeFactor = GetTimeFactor()

    if timeFactor > 0 then
        if tempChangeDirection > 0 then
            return DAY_WARM_RATE
        else
            return DAY_COOL_RATE
        end
    else
        if tempChangeDirection < 0 then
            return NIGHT_COOL_RATE
        else
            return NIGHT_WARM_RATE
        end
    end
end

local WEATHER_EFFECTS = {
    [1] = -0.025,
    [2] = -0.04,
    [3] = -0.05,
    ["Rain"] = -0.04,
    ["Blood Rain"] = -0.04,

    [6] = -0.075,
    [7] = -0.1,
    [8] = -0.125,
    ["Snow"] = -0.1,

    ["Arcane Storm"] = 0.05,

    ["Dust Storm"] = 0.1,
    ["Sandstorm"] = 0.125
}

local INDOOR_MODIFIER = 0.3
local SWIMMING_HEAT_REDUCTION = -0.1
local SWIMMING_COLD_INCREASE = -0.075
local WET_DURATION = 300
local WET_COLD_MULTIPLIER_MAX = 1.75
local WET_HEAT_EXPOSURE_MULTIPLIER = 0.25
local DRINKING_COOLING_RATE = -0.5
local MANA_POTION_DURATION = 30
local WELL_FED_COLD_MODIFIER = 0.5
local FIRE_OUTDOOR_RECOVERY = 0.05
local FIRE_INDOOR_RECOVERY = 0.2
local INN_RECOVERY = 0.5

local RECOVERY_RATE_MULTIPLIER = 2.0

local lastEquilibriumMessage = nil
local equilibriumMessageCooldown = 0
local EQUILIBRIUM_MESSAGE_COOLDOWN = 30


local WEATHER_TYPE_NONE = 0
local WEATHER_TYPE_RAIN = 1
local WEATHER_TYPE_SNOW = 2
local WEATHER_TYPE_DUST = 3

local ZONE_WEATHER_TYPES = {
    ["elwynnforest"] = WEATHER_TYPE_RAIN,
    ["westfall"] = WEATHER_TYPE_RAIN,
    ["redridgemountains"] = WEATHER_TYPE_RAIN,
    ["duskwood"] = WEATHER_TYPE_RAIN,
    ["stranglethornvale"] = WEATHER_TYPE_RAIN,
    ["tirisfalglades"] = WEATHER_TYPE_RAIN,
    ["silverpineforest"] = WEATHER_TYPE_RAIN,
    ["hillsbradfoothills"] = WEATHER_TYPE_RAIN,
    ["arathihighlands"] = WEATHER_TYPE_RAIN,
    ["wetlands"] = WEATHER_TYPE_RAIN,
    ["lochmodan"] = WEATHER_TYPE_RAIN,
    ["thehinterlands"] = WEATHER_TYPE_RAIN,
    ["hinterlands"] = WEATHER_TYPE_RAIN,
    ["westernplaguelands"] = WEATHER_TYPE_RAIN,
    ["easternplaguelands"] = WEATHER_TYPE_RAIN,
    ["swampofsorrows"] = WEATHER_TYPE_RAIN,
    ["dustwallowmarsh"] = WEATHER_TYPE_RAIN,
    ["ashenvale"] = WEATHER_TYPE_RAIN,
    ["darkshore"] = WEATHER_TYPE_RAIN,
    ["teldrassil"] = WEATHER_TYPE_RAIN,
    ["feralas"] = WEATHER_TYPE_RAIN,
    ["felwood"] = WEATHER_TYPE_RAIN,
    ["stormwindcity"] = WEATHER_TYPE_RAIN,
    ["stormwind"] = WEATHER_TYPE_RAIN,
    ["darnassus"] = WEATHER_TYPE_RAIN,

    ["dunmorogh"] = WEATHER_TYPE_SNOW,
    ["alteracmountains"] = WEATHER_TYPE_SNOW,
    ["winterspring"] = WEATHER_TYPE_SNOW,
    ["ironforge"] = WEATHER_TYPE_SNOW,
    ["alteracvalley"] = WEATHER_TYPE_SNOW,

    ["tanaris"] = WEATHER_TYPE_DUST,
    ["silithus"] = WEATHER_TYPE_DUST,
    ["thousandneedles"] = WEATHER_TYPE_DUST,
    ["badlands"] = WEATHER_TYPE_DUST,
    ["desolace"] = WEATHER_TYPE_DUST,
    ["durotar"] = WEATHER_TYPE_DUST,
    ["thebarrens"] = WEATHER_TYPE_DUST,
    ["barrens"] = WEATHER_TYPE_DUST,
    ["orgrimmar"] = WEATHER_TYPE_DUST,

    ["undercity"] = WEATHER_TYPE_NONE,
    ["deadwindpass"] = WEATHER_TYPE_NONE,
    ["blastedlands"] = WEATHER_TYPE_NONE,
    ["searinggorge"] = WEATHER_TYPE_NONE,
    ["burningsteppes"] = WEATHER_TYPE_NONE,
    ["azshara"] = WEATHER_TYPE_NONE,
    ["moonglade"] = WEATHER_TYPE_NONE,
    ["ungorocrater"] = WEATHER_TYPE_NONE,
    ["stonetalonmountains"] = WEATHER_TYPE_NONE,
    ["mulgore"] = WEATHER_TYPE_NONE,
    ["thunderbluff"] = WEATHER_TYPE_NONE,

    ["default"] = WEATHER_TYPE_NONE
}

local manualWeatherActive = false
local currentZoneWeatherType = WEATHER_TYPE_NONE
local lastZoneName = nil
local debugWeatherTypeOverride = nil

local MANUAL_WEATHER_EFFECTS = {
    [WEATHER_TYPE_NONE] = 0,
    [WEATHER_TYPE_RAIN] = -0.04,
    [WEATHER_TYPE_SNOW] = -0.1,
    [WEATHER_TYPE_DUST] = 0.1
}

local function GetZoneWeatherType(zoneName)
    if not zoneName then
        return WEATHER_TYPE_NONE
    end
    local zoneKey = zoneName:lower():gsub("%s+", ""):gsub("'", ""):gsub("-", "")
    return ZONE_WEATHER_TYPES[zoneKey] or ZONE_WEATHER_TYPES["default"]
end

local function UpdateZoneWeatherType()
    local zoneName = GetZoneText()
    if zoneName ~= lastZoneName then
        lastZoneName = zoneName
        currentZoneWeatherType = GetZoneWeatherType(zoneName)
        manualWeatherActive = false
        WL.Debug(string.format("Zone changed to %s - weather type: %d, toggle reset", zoneName, currentZoneWeatherType),
            "temperature")
        WL.FireCallbacks("ZONE_WEATHER_CHANGED", currentZoneWeatherType, manualWeatherActive)
    end
end

function WL.GetZoneWeatherType()
    if debugWeatherTypeOverride then
        return debugWeatherTypeOverride
    end
    return currentZoneWeatherType
end

function WL.IsManualWeatherActive()
    return manualWeatherActive
end

function WL.ToggleManualWeather()
    if currentZoneWeatherType == WEATHER_TYPE_NONE then
        return false
    end
    manualWeatherActive = not manualWeatherActive
    WL.Debug(string.format("Manual weather toggled: %s", manualWeatherActive and "ON" or "OFF"), "temperature")
    WL.FireCallbacks("MANUAL_WEATHER_CHANGED", manualWeatherActive, currentZoneWeatherType)
    return true
end

function WL.SetManualWeather(active)
    if currentZoneWeatherType == WEATHER_TYPE_NONE then
        manualWeatherActive = false
        return
    end
    manualWeatherActive = active
    WL.FireCallbacks("MANUAL_WEATHER_CHANGED", manualWeatherActive, currentZoneWeatherType)
end

function WL.IsWeatherPaused()
    return IsIndoors()
end

local function GetManualWeatherEffect()
    if not WL.GetSetting("manualWeatherEnabled") then
        return 0
    end
    if not manualWeatherActive then
        return 0
    end
    if WL.IsWeatherPaused() then
        return 0
    end
    return MANUAL_WEATHER_EFFECTS[currentZoneWeatherType] or 0
end

local currentGlowType = 0
local currentGlowIntensity = 0
local GLOW_DECAY_RATE = 2.0

local lastTemperature = 0
local temperatureTrend = 0
local isTemperatureBalanced = false
local hasActiveCounterForce = false

function WL.GetTemperatureTrend()
    return temperatureTrend
end

function WL.IsTemperatureBalanced()
    return isTemperatureBalanced
end

function WL.HasActiveCounterForce()
    return hasActiveCounterForce
end

local function UpdateTemperatureTrend(newTemp, tempChange, counterForceActive)
    local diff = newTemp - lastTemperature

    hasActiveCounterForce = counterForceActive

    local nearNeutral = math_abs(newTemp) < 3
    local isStable = math_abs(diff) < 0.05
    isTemperatureBalanced = counterForceActive and nearNeutral and isStable

    if diff > 0.01 then
        temperatureTrend = 1
    elseif diff < -0.01 then
        temperatureTrend = -1
    else
        temperatureTrend = 0
    end
    lastTemperature = newTemp
end

local isRecovering = false
local lastWeatherType = nil
local function CheckDungeonStatus()
    local inInstance, instanceType = IsInInstance()
    return inInstance and (instanceType == "party" or instanceType == "raid")
end

local function ShouldUpdateTemperature()
    if not cachedSettings.temperatureEnabled then
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
    return true
end

local function GetZoneTemperatureEffect()
    local zone = GetZoneText()
    local envTemp, baseTemp, timeFactor, fluctuation = GetEnvironmentalTemperature(zone)

    local equilibrium = (envTemp - COMFORTABLE_TEMP) * 3
    equilibrium = math_max(-90, math_min(90, equilibrium))

    local distFromEquilibrium = equilibrium - temperature
    local baseEffect = distFromEquilibrium * 0.004

    local effect = baseEffect
    if temperature >= 0 and baseEffect > 0 then
        effect = baseEffect * 0.6
    elseif temperature <= 0 and baseEffect < 0 then
        effect = baseEffect * 0.6
    elseif temperature > 0 and baseEffect < 0 then
        effect = baseEffect * 4
    elseif temperature < 0 and baseEffect > 0 then
        effect = baseEffect * 4
    end

    return effect, envTemp, baseTemp, timeFactor, fluctuation, equilibrium
end

local currentWeatherType = 0
local currentWeatherIntensity = 0

local function GetWeatherEffect()
    if currentWeatherType == 0 then
        return 0
    end

    local effect = WEATHER_EFFECTS[currentWeatherType] or 0
    return effect * currentWeatherIntensity
end

local function CanPlayerMount()
    if IsIndoors() then
        return false
    end
    if IsSwimming() then
        return false
    end
    return true
end

local function IsPlayerIndoors()
    return IsIndoors() or not CanPlayerMount()
end

local function IsPlayerSwimming()
    return IsSwimming()
end

local BUFF_SCAN_INTERVAL = 0.2
local lastTempBuffCheck = 0
local cachedWellFed = false
local cachedDrinking = false

local function UpdateTemperatureBuffState()
    local now = GetTime()
    if now - lastTempBuffCheck < BUFF_SCAN_INTERVAL then
        return
    end
    lastTempBuffCheck = now
    cachedWellFed = false
    cachedDrinking = false

    for i = 1, 40 do
        local name = GetBuffNameByIndex(i)
        if not name then
            break
        end
        if not cachedWellFed and (name == "Well Fed" or name:match("Food") or name:match("Stamina")) then
            cachedWellFed = true
        end
        if not cachedDrinking and (name == "Drink" or name == "Refreshment") then
            cachedDrinking = true
        end
        if cachedWellFed and cachedDrinking then
            break
        end
    end
end

local function HasWellFedBuff()
    if WL.HasWellFedBuff then
        return WL.HasWellFedBuff()
    end
    UpdateTemperatureBuffState()
    return cachedWellFed
end

local function IsPlayerDrinking()
    UpdateTemperatureBuffState()
    return cachedDrinking
end

local manaPotionCoolingActive = false
local manaPotionCoolingRemaining = 0
local MANA_POTION_DURATION = 600
local MANA_POTION_HEAT_RESIST = 0.5

local drunkLevel = 0
local drunkTimer = 0
local DRUNK_DURATION = 900
local DRUNK_WARMTH_BONUS = {
    [0] = 0,
    [1] = 0.10,
    [2] = 0.20,
    [3] = 0.30
}

local wetEffectActive = false
local wetEffectRemaining = 0
local wasSwimmingLastFrame = false

local function StartManaPotionCooling()
    if isInDungeon then
        return
    end

    manaPotionCoolingRemaining = MANA_POTION_DURATION
    manaPotionCoolingActive = true

    WL.Debug(string.format("Mana potion cooling active: heat gain reduced %.0f%% for %ds",
        (1 - MANA_POTION_HEAT_RESIST) * 100, MANA_POTION_DURATION), "temperature")
end

local function UpdateTemperature(elapsed)
    if not ShouldUpdateTemperature() then
        currentGlowType = 0
        return
    end

    local tempChange = 0
    local isIndoors = IsPlayerIndoors()
    local isSwimming = IsPlayerSwimming()
    local hasWellFed = HasWellFedBuff()
    local isNearFire = WL.isNearFire
    local isResting = IsResting()

    local zoneEffect, envTemp, baseTemp, timeFactor, fluctuation, equilibrium = GetZoneTemperatureEffect()
    tempChange = tempChange + zoneEffect

    local weatherEffect = GetWeatherEffect()
    if weatherEffect ~= 0 then
        if isIndoors then
            weatherEffect = weatherEffect * INDOOR_MODIFIER
        end
        tempChange = tempChange + weatherEffect
    end

    local manualWeatherEffect = GetManualWeatherEffect()
    if manualWeatherEffect ~= 0 then
        if isIndoors then
            manualWeatherEffect = manualWeatherEffect * INDOOR_MODIFIER
        end
        tempChange = tempChange + manualWeatherEffect
    end

    if isSwimming then
        if temperature > 0 then
            tempChange = tempChange + SWIMMING_HEAT_REDUCTION
        elseif temperature < 0 and zoneEffect < 0 then
            tempChange = tempChange + SWIMMING_COLD_INCREASE
        else
            tempChange = tempChange + (SWIMMING_HEAT_REDUCTION * 0.5)
        end
        wetEffectActive = true
        wetEffectRemaining = WET_DURATION
    end
    wasSwimmingLastFrame = isSwimming

    local isRaining = manualWeatherActive and currentZoneWeatherType == WEATHER_TYPE_RAIN
    if isRaining and not isIndoors then
        wetEffectActive = true
        wetEffectRemaining = WET_DURATION
    end

    if wetEffectActive and not isSwimming then
        local dryingMultiplier = (isNearFire or isResting) and 3.0 or 1.0
        wetEffectRemaining = wetEffectRemaining - (elapsed * dryingMultiplier)
        if wetEffectRemaining <= 0 then
            wetEffectActive = false
            wetEffectRemaining = 0
            WL.Debug("Wet effect finished - you've dried off", "temperature")
        elseif temperature < 0 and tempChange < 0 then
            local coldIntensity = math_min(1, math_abs(temperature) / 50)
            local wetMultiplier = 1 + (coldIntensity * (WET_COLD_MULTIPLIER_MAX - 1))
            local coolingBoost = (tempChange * wetMultiplier) - tempChange
            tempChange = tempChange + coolingBoost
            WL.Debug(string.format("Wet effect (cold): %.1fx cold exposure (%.1fs remaining)", wetMultiplier,
                wetEffectRemaining), "temperature")
        elseif temperature > 0 and tempChange > 0 then
            tempChange = tempChange * WET_HEAT_EXPOSURE_MULTIPLIER
            WL.Debug(string.format("Wet effect (hot): heat exposure x%.2f (%.1fs remaining)",
                WET_HEAT_EXPOSURE_MULTIPLIER, wetEffectRemaining), "temperature")
        end
    end

    local isDrinking = IsPlayerDrinking()
    if isDrinking and temperature > 0 then
        tempChange = tempChange + DRINKING_COOLING_RATE
        WL.Debug("Drinking cooling active", "temperature")
    end

    if manaPotionCoolingActive then
        manaPotionCoolingRemaining = manaPotionCoolingRemaining - elapsed
        if manaPotionCoolingRemaining <= 0 then
            manaPotionCoolingActive = false
            WL.Debug("Mana potion effect finished", "temperature")
        end
    end

    if lastWeatherType and
        (lastWeatherType == "Rain" or lastWeatherType == "Blood Rain" or lastWeatherType == 1 or lastWeatherType == 2 or
            lastWeatherType == 3) then
        if temperature > 0 and not isIndoors then
            tempChange = tempChange - 0.5
        end
    end

    if tempChange < 0 and temperature < 0 and hasWellFed then
        tempChange = tempChange * WELL_FED_COLD_MODIFIER
    end
    if tempChange > 0 and temperature > 0 and manaPotionCoolingActive then
        tempChange = tempChange * MANA_POTION_HEAT_RESIST
    end

    if drunkLevel and drunkLevel > 0 then
        drunkTimer = (drunkTimer or 0) - elapsed
        if drunkTimer <= 0 then
            drunkLevel = 0
            drunkTimer = 0
        elseif tempChange < 0 then
            local warmthBonus = DRUNK_WARMTH_BONUS[drunkLevel] or 0
            if warmthBonus and warmthBonus > 0 then
                tempChange = tempChange * (1 - warmthBonus)
            end
        end
    end

    if temperature < 0 and isNearFire then
        local baseRecovery = isIndoors and FIRE_INDOOR_RECOVERY or FIRE_OUTDOOR_RECOVERY

        baseRecovery = baseRecovery * RECOVERY_RATE_MULTIPLIER

        local distanceFrom0 = math_abs(temperature)
        local scaledRecovery = baseRecovery * math_min(1.0, distanceFrom0 / 10)

        if tempChange < 0 then
            local netWarming = math_max(scaledRecovery, math_abs(tempChange) * 1.1)
            tempChange = tempChange + netWarming
        else
            tempChange = tempChange + scaledRecovery
        end

        if isIndoors and equilibrium < 0 then
            local recoveryToward0 = baseRecovery * 2
            if temperature < -1 then
                tempChange = tempChange + recoveryToward0
            end
        end
    end

    if isResting then
        local distanceFrom0 = math_abs(temperature)
        local scaledInnRecovery = INN_RECOVERY * RECOVERY_RATE_MULTIPLIER * math_min(1.0, distanceFrom0 / 10)
        if temperature > 0 then
            tempChange = tempChange - scaledInnRecovery
        elseif temperature < 0 then
            tempChange = tempChange + scaledInnRecovery
        end
    end


    if isIndoors and not isResting and not isNearFire then
        if (tempChange > 0 and temperature >= 0) or (tempChange < 0 and temperature <= 0) then
            tempChange = tempChange * INDOOR_MODIFIER
        end
    end

    if tempChange ~= 0 and not isResting and not isNearFire then
        local rateModifier = GetDirectionalRateModifier(tempChange)
        tempChange = tempChange * rateModifier
    end

    local oldTemp = temperature
    temperature = temperature + (tempChange * elapsed)
    temperature = math_max(MIN_TEMPERATURE, math_min(MAX_TEMPERATURE, temperature))

    local counterForceActive = false
    local isDrinking = IsPlayerDrinking()
    if equilibrium < -5 then
        counterForceActive = isNearFire or isResting
    elseif equilibrium > 5 then
        counterForceActive = isSwimming or isDrinking or (isResting and temperature > 0) or wetEffectActive
    end

    if not counterForceActive and math_abs(temperature - equilibrium) < 1.0 then
        temperature = equilibrium
    end

    local snappedTo0 = false
    if (isNearFire or isResting) and equilibrium < -5 and math_abs(temperature) < 0.5 then
        temperature = 0
        snappedTo0 = true
    end

    if isIndoors and isNearFire and temperature < 0 and temperature > -0.5 then
        temperature = 0
        snappedTo0 = true
    end

    if wetEffectActive and equilibrium > 5 and math_abs(temperature) < 0.5 then
        temperature = 0
        snappedTo0 = true
    end

    if equilibriumMessageCooldown > 0 then
        equilibriumMessageCooldown = equilibriumMessageCooldown - elapsed
    end

    if equilibriumMessageCooldown <= 0 then
        local messageToShow = nil

        if snappedTo0 or (math_abs(temperature) < 0.5 and math_abs(oldTemp) >= 1) then
            if lastEquilibriumMessage ~= "comfortable" then
                messageToShow = "comfortable"
                print("|cff88CCFFWanderlust:|r |cff00FF00You are at a comfortable temperature.|r")
            end
        elseif equilibrium < -5 and not isIndoors and temperature < 0 then
            local atWarmingCap = counterForceActive and math_abs(temperature - equilibrium) < 2 and oldTemp <=
                                     temperature
            if atWarmingCap and temperature < -3 and lastEquilibriumMessage ~= "cant_warm" then
                messageToShow = "cant_warm"
                print("|cff88CCFFWanderlust:|r |cffFFAAAAYou can't seem to get any warmer.|r")
            end
        elseif equilibrium > 5 and temperature > 0 then
            local atCoolingCap = counterForceActive and math_abs(temperature - equilibrium) < 2 and oldTemp >=
                                     temperature
            if atCoolingCap and temperature > 3 and lastEquilibriumMessage ~= "cant_cool" then
                messageToShow = "cant_cool"
                print("|cff88CCFFWanderlust:|r |cffFFAAAAYou can't seem to get any cooler.|r")
            end
        end

        if messageToShow then
            lastEquilibriumMessage = messageToShow
            equilibriumMessageCooldown = EQUILIBRIUM_MESSAGE_COOLDOWN
        end
    end

    if math_abs(temperature) > 5 and lastEquilibriumMessage == "comfortable" then
        lastEquilibriumMessage = nil
    elseif math_abs(temperature - equilibrium) > 5 then
        if lastEquilibriumMessage == "cant_warm" or lastEquilibriumMessage == "cant_cool" then
            lastEquilibriumMessage = nil
        end
    end

    UpdateTemperatureTrend(temperature, tempChange, counterForceActive)

    isRecovering = (isResting or isNearFire) and temperature ~= 0

    if isRecovering then
        currentGlowType = 3
        currentGlowIntensity = 1.0
    elseif temperature < -10 then
        currentGlowType = 1
        currentGlowIntensity = math_min(1.0, math_abs(temperature) / 50)
    elseif temperature > 10 then
        currentGlowType = 2
        currentGlowIntensity = math_min(1.0, math_abs(temperature) / 50)
    else
        currentGlowType = 0
        currentGlowIntensity = 0
    end

    if cachedSettings.temperatureDebugEnabled then
        local hour, minute = GetGameTime()
        WL.Debug(string.format("Temp: %.1f | Eq: %.0f | Env: %.1f°C (base: %d) | Change: %.3f/s | Time: %02d:%02d",
            temperature, equilibrium or 0, envTemp, baseTemp, tempChange, hour, minute), "temperature")
    end
end

local function UpdateGlow(elapsed)
    if currentGlowType == 0 and currentGlowIntensity > 0 then
        currentGlowIntensity = currentGlowIntensity - (GLOW_DECAY_RATE * elapsed)
        if currentGlowIntensity <= 0 then
            currentGlowIntensity = 0
        end
    end
end

function WL.HandleTemperatureUpdate(elapsed)
    updateTimer = updateTimer + elapsed
    if updateTimer >= UPDATE_INTERVAL then
        UpdateTemperature(updateTimer)
        updateTimer = 0
    end
    UpdateGlow(elapsed)
    UpdateTemperatureOverlayAlphas(elapsed)
    local isDrying = WL.isNearFire or IsResting()
    UpdateDryingOverlayAlpha(elapsed, wetEffectActive, isDrying)
end

function WL.GetTemperature()
    return temperature
end

function WL.IsWetEffectActive()
    return wetEffectActive
end

function WL.GetWetEffectRemaining()
    return wetEffectRemaining
end

function WL.GetDrunkLevel()
    return drunkLevel
end

function WL.GetDrunkRemaining()
    return drunkTimer
end

function WL.IsDrunk()
    return drunkLevel > 0
end

function WL.GetDrunkWarmthBonus()
    return DRUNK_WARMTH_BONUS[drunkLevel] or 0
end

function WL.IsManaPotionCooling()
    return manaPotionCoolingActive
end

function WL.GetManaPotionCoolingRemaining()
    return manaPotionCoolingRemaining
end

function WL.SetWetEffect(active)
    if active then
        wetEffectActive = true
        wetEffectRemaining = WET_DURATION
        WL.Debug("Debug: Wet effect enabled", "temperature")
    else
        wetEffectActive = false
        wetEffectRemaining = 0
        WL.Debug("Debug: Wet effect disabled (dried off)", "temperature")
    end
end

function WL.SetDebugWeatherType(weatherType)
    debugWeatherTypeOverride = weatherType
    if weatherType then
        WL.Debug(string.format("Debug: Weather type override set to %d", weatherType), "temperature")
    else
        WL.Debug("Debug: Weather type override cleared", "temperature")
    end
    WL.FireCallbacks("ZONE_WEATHER_CHANGED", WL.GetZoneWeatherType(), manualWeatherActive)
end

function WL.GetDebugWeatherType()
    return debugWeatherTypeOverride
end

function WL.GetTemperaturePercent()
    return temperature / MAX_TEMPERATURE
end

function WL.GetTemperatureAbsolutePercent()
    return math_abs(temperature)
end

function WL.SetTemperature(value)
    value = tonumber(value)
    if not value then
        return false
    end
    temperature = math_max(MIN_TEMPERATURE, math_min(MAX_TEMPERATURE, value))
    WL.Debug(string.format("Temperature set to %.1f", temperature), "temperature")
    return true
end

function WL.ResetTemperature()
    temperature = 0
    WL.Debug("Temperature reset to neutral", "temperature")
end

function WL.IsTemperatureCold()
    return temperature < 0
end

function WL.IsTemperatureHot()
    return temperature > 0
end

function WL.GetTemperatureGlow()
    return currentGlowType, currentGlowIntensity
end

function WL.IsTemperatureRecovering()
    return isRecovering
end

function WL.IsTemperaturePaused()
    if not WL.GetSetting("temperatureEnabled") then
        return false
    end
    if not WL.IsPlayerEligible() then
        return false
    end
    return isInDungeon or UnitOnTaxi("player") or UnitIsDead("player") or UnitIsGhost("player")
end

function WL.GetTemperatureEquilibrium()
    local zone = GetZoneText()
    local envTemp = GetEnvironmentalTemperature(zone)
    local equilibrium = (envTemp - COMFORTABLE_TEMP) * 3
    equilibrium = math_max(-90, math_min(90, equilibrium))
    return equilibrium
end

function WL.GetEnvironmentalTemperature()
    local zone = GetZoneText()
    local envTemp, baseTemp = GetEnvironmentalTemperature(zone)
    return envTemp, baseTemp
end

function WL.IsTemperatureAtEquilibrium()
    local equilibrium = WL.GetTemperatureEquilibrium()
    return math_abs(temperature - equilibrium) < 1
end

function WL.GetCurrentWeather()
    return currentWeatherType, currentWeatherIntensity
end

function WL.IsRaining()
    if not WL.GetSetting("manualWeatherEnabled") then
        return false
    end
    if not manualWeatherActive then
        return false
    end
    return currentZoneWeatherType == WEATHER_TYPE_RAIN and not WL.IsWeatherPaused()
end

function WL.GetEnvironmentalTemperature()
    local zone = GetZoneText()
    return GetEnvironmentalTemperature(zone)
end

function WL.GetTimeFactor()
    return GetTimeFactor()
end

function WL.IsDaytime()
    return GetTimeFactor() > 0
end

local cachedEffects = {}

function WL.GetTemperatureEffects()
    for i = #cachedEffects, 1, -1 do
        cachedEffects[i] = nil
    end
    local effects = cachedEffects

    local zone = GetZoneText()
    local envTemp, baseTemp = GetEnvironmentalTemperature(zone)
    if envTemp > COMFORTABLE_TEMP + 20 then
        table.insert(effects, "Very Hot Zone")
    elseif envTemp > COMFORTABLE_TEMP + 5 then
        table.insert(effects, "Hot Zone")
    elseif envTemp < COMFORTABLE_TEMP - 20 then
        table.insert(effects, "Very Cold Zone")
    elseif envTemp < COMFORTABLE_TEMP - 5 then
        table.insert(effects, "Cold Zone")
    else
        table.insert(effects, "Comfortable Zone")
    end

    local timeFactor = GetTimeFactor()
    if timeFactor > 0.3 then
        table.insert(effects, "Daytime (warming)")
    elseif timeFactor < -0.3 then
        table.insert(effects, "Nighttime (cooling)")
    end

    if IsPlayerIndoors() and not IsPlayerSwimming() then
        table.insert(effects, "Indoors (reduced zone effects)")
    end

    if IsPlayerSwimming() then
        if temperature > 0 then
            table.insert(effects, "Swimming (cooling)")
        elseif temperature < 0 then
            table.insert(effects, "Swimming (colder)")
        else
            table.insert(effects, "Swimming")
        end
    end

    if wetEffectActive and not IsPlayerSwimming() then
        local minutes = math_floor(wetEffectRemaining / 60)
        local seconds = math_floor(wetEffectRemaining % 60)
        local timeStr = minutes > 0 and string.format("%d:%02d", minutes, seconds) or string.format("%ds", seconds)
        local dryingNote = (WL.isNearFire or IsResting()) and " [drying 3x]" or ""
        if temperature < 0 then
            local coldIntensity = math_min(1, math_abs(temperature) / 50)
            local wetMultiplier = 1 + (coldIntensity * (WET_COLD_MULTIPLIER_MAX - 1))
            table.insert(effects, string.format("Wet: cold exposure x%.1f (%s)%s", wetMultiplier, timeStr, dryingNote))
        elseif temperature > 0 then
            table.insert(effects, string.format("Wet: heat exposure x%.2f (%s)%s", WET_HEAT_EXPOSURE_MULTIPLIER, timeStr,
                dryingNote))
        else
            table.insert(effects, string.format("Wet: affects temp when hot/cold (%s)%s", timeStr, dryingNote))
        end
    end

    if temperature < 0 and HasWellFedBuff() then
        table.insert(effects, "Well Fed (-50% cold exposure)")
    end

    if drunkLevel > 0 then
        local levelNames = {
            [1] = "Tipsy",
            [2] = "Drunk",
            [3] = "Smashed"
        }
        local bonus = DRUNK_WARMTH_BONUS[drunkLevel] or 0
        local remaining = math_ceil(drunkTimer)
        local minutes = math_floor(remaining / 60)
        local seconds = remaining % 60
        table.insert(effects,
            string.format("%s (%d%% warmth, %d:%02d)", levelNames[drunkLevel], bonus * 100, minutes, seconds))
    end

    if manaPotionCoolingActive and temperature > 0 then
        local remaining = math_ceil(manaPotionCoolingRemaining)
        local minutes = math_floor(remaining / 60)
        local seconds = remaining % 60
        table.insert(effects, string.format("Mana Potion (-50%% heat exposure, %d:%02d)", minutes, seconds))
    end

    if IsPlayerDrinking() and temperature > 0 then
        table.insert(effects, "Drinking (cooling)")
    end

    if WL.isNearFire then
        if temperature < 0 then
            table.insert(effects, "Campfire (warming)")
        elseif temperature > 0 then
            table.insert(effects, "Campfire (no effect - already warm)")
        else
            table.insert(effects, "Campfire (comfortable)")
        end
    end

    if IsResting() then
        if temperature > 0 then
            table.insert(effects, "Resting (cooling)")
        elseif temperature < 0 then
            table.insert(effects, "Resting (warming)")
        else
            table.insert(effects, "Resting (neutral)")
        end
    end

    if WL.GetSetting("manualWeatherEnabled") and manualWeatherActive then
        local weatherNames = {
            [1] = "Rain",
            [2] = "Snow",
            [3] = "Dust Storm"
        }
        local weatherName = weatherNames[currentZoneWeatherType] or "Weather"
        if WL.IsWeatherPaused() then
            table.insert(effects, weatherName .. " (paused - indoors)")
        else
            table.insert(effects, weatherName .. " (manual)")
        end
    end

    return effects
end

function WL.GetTemperatureExposureInfo()
    if temperature == 0 then
        return "neutral", 1
    end

    if temperature < 0 then
        local multiplier = 1
        if wetEffectActive and not IsPlayerSwimming() then
            local coldIntensity = math_min(1, math_abs(temperature) / 50)
            local wetMultiplier = 1 + (coldIntensity * (WET_COLD_MULTIPLIER_MAX - 1))
            multiplier = multiplier * wetMultiplier
        end
        if HasWellFedBuff() then
            multiplier = multiplier * WELL_FED_COLD_MODIFIER
        end
        return "cold", multiplier
    end

    if temperature > 0 then
        local multiplier = 1
        if wetEffectActive and not IsPlayerSwimming() then
            multiplier = multiplier * WET_HEAT_EXPOSURE_MULTIPLIER
        end
        if manaPotionCoolingActive then
            multiplier = multiplier * MANA_POTION_HEAT_RESIST
        end
        return "heat", multiplier
    end

    return "neutral", 1
end

local function OnZoneChanged()
    local wasInDungeon = isInDungeon
    isInDungeon = CheckDungeonStatus()

    if isInDungeon and not wasInDungeon then
        savedTemperature = temperature
        WL.Debug(string.format("Entering dungeon - temperature paused at %.1f", savedTemperature), "temperature")
    elseif not isInDungeon and wasInDungeon then
        temperature = savedTemperature
        WL.Debug(string.format("Leaving dungeon - temperature restored to %.1f", temperature), "temperature")
    end
end

RegisterCallbackOrDefer("SETTINGS_CHANGED", function(key)
    if key == "temperatureEnabled" or key == "ALL" then
        if not WL.GetSetting("temperatureEnabled") then
            currentGlowType = 0
            currentGlowIntensity = 0
        end
    end
    if key == "pauseInInstances" or key == "ALL" then
        OnZoneChanged()
    end
end)

local eventFrame = CreateFrame("Frame", "WanderlustTemperatureFrame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:RegisterEvent("PLAYER_DEAD")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("ZONE_CHANGED")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")

local DRUNK_MESSAGES = {
    [DRUNK_MESSAGE_SELF1 or "You feel sober again."] = 0,
    [DRUNK_MESSAGE_SELF2 or "You feel tipsy. Whee!"] = 1,
    [DRUNK_MESSAGE_SELF3 or "You feel drunk. Woah!"] = 2,
    [DRUNK_MESSAGE_SELF4 or "You feel completely smashed."] = 3,
    ["You are no longer drunk."] = 0,
    ["You feel sober."] = 0,
    ["You are sober."] = 0
}

local function ParseDrunkMessage(msg)
    if not msg or type(msg) ~= "string" then
        return nil
    end

    if DRUNK_MESSAGES[msg] then
        return DRUNK_MESSAGES[msg]
    end

    if msg:find("[Ss]ober") or msg:find("no longer drunk") then
        return 0
    elseif msg:find("[Cc]ompletely smashed") or msg:find("[Ee]xtremely drunk") then
        return 3
    elseif msg:find("[Ss]lightly tipsy") or msg:find("[Tt]ipsy") then
        return 1
    elseif msg:find("[Vv]ery drunk") or msg:find("[Dd]runk") then
        return 2
    end

    return nil
end

eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2, ...)
    if event == "PLAYER_LOGIN" then
        FlushPendingCallbacks()
        ASSET_BASE = WL_GetAssetBase()
        RefreshCachedSettings()
        if WL.charDB and WL.charDB.savedTemperature then
            temperature = WL.charDB.savedTemperature
            WL.Debug(string.format("Temperature restored: %.1f", temperature), "temperature")
        else
            temperature = 0
        end
        savedTemperature = 0
        isInDungeon = CheckDungeonStatus()
        CreateAllTemperatureOverlayFrames()
        C_Timer.After(0.5, function()
            UpdateZoneWeatherType()
        end)

    elseif event == "PLAYER_LOGOUT" then
        if WL.charDB then
            WL.charDB.savedTemperature = temperature
        end

    elseif event == "PLAYER_DEAD" then
        WL.ResetTemperature()

    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" then
        OnZoneChanged()
        UpdateZoneWeatherType()

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" and arg1 == "player" then
        local extraArgs = {...}
        pcall(function()
            local spellName, spellID
            local extraArg = extraArgs[1]

            if type(arg2) == "string" and arg2:match("^Cast%-") then
                local extractedID = arg2:match("Cast%-%d+%-%d+%-%d+%-%d+%-(%d+)")
                spellID = extraArg or (extractedID and tonumber(extractedID))
                spellName = spellID and GetSpellInfo(spellID)
            elseif type(arg2) == "string" then
                spellName = arg2
                local classicSpellID = extraArgs[4]
                spellID = classicSpellID
            else
                spellID = extraArg
                spellName = spellID and GetSpellInfo(spellID)
            end

            if cachedSettings.temperatureDebugEnabled then
                WL.Debug(string.format("Spell cast: %s (ID: %s)", tostring(spellName), tostring(spellID)), "temperature")
            end

            if spellName then

                local isManaPotion = spellName:match("Mana Potion") or spellName:match("Restore Mana") or
                                         spellName:match("Mana Restored")

                local isManaGem = spellName:match("Mana Emerald") or spellName:match("Mana Ruby") or
                                      spellName:match("Mana Citrine") or spellName:match("Mana Jade") or
                                      spellName:match("Mana Agate")

                local MANA_POTION_SPELL_IDS = {
                    [2023] = true,
                    [2024] = true,
                    [4381] = true,
                    [11903] = true,
                    [17530] = true,
                    [17531] = true
                }

                if isManaPotion or isManaGem or (spellID and MANA_POTION_SPELL_IDS[spellID]) then
                    StartManaPotionCooling()
                    if WL.StartManaPotionQuenching then
                        WL.StartManaPotionQuenching()
                    end
                    WL.Debug(string.format("Mana potion detected: %s (ID: %s)", spellName, tostring(spellID)),
                        "temperature")
                end
            end
        end)

    elseif event == "CHAT_MSG_SYSTEM" then
        local success, newDrunkLevel = pcall(ParseDrunkMessage, arg1)
        if success and newDrunkLevel ~= nil then
            local oldLevel = drunkLevel
            drunkLevel = newDrunkLevel
            if newDrunkLevel > 0 then
                drunkTimer = DRUNK_DURATION
                local levelNames = {
                    [1] = "Tipsy",
                    [2] = "Drunk",
                    [3] = "Completely Smashed"
                }
                WL.Debug(string.format("Drunk level changed: %s -> %s (%d%% cold reduction)",
                    levelNames[oldLevel] or "Sober", levelNames[newDrunkLevel] or "Sober",
                    (DRUNK_WARMTH_BONUS[newDrunkLevel] or 0) * 100), "temperature")
            else
                drunkTimer = 0
                WL.Debug("Sobered up - drunk warmth bonus removed", "temperature")
            end
        end
    end
end)

RegisterCallbackOrDefer("SETTINGS_CHANGED", function(key)
    if key == "temperatureEnabled" or key == "temperatureDebugEnabled" or key == "temperatureOverlayEnabled" or
        key == "ALL" then
        RefreshCachedSettings()
    end
    if key == "pauseInInstances" or key == "ALL" then
        OnZoneChanged()
    end
end)
