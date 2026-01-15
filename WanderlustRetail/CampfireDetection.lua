-- Wanderlust - campfire proximity and rest detection
local WL = Wanderlust
-- ---------------------------------------------------------------------------
-- Midnight / modern client compatibility helpers
-- - WL_UnitBuff() was removed; use C_UnitAuras when available.
-- ---------------------------------------------------------------------------
local function WL_UnitBuff(unit, index, filter)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, index, filter or "HELPFUL")
        if aura then
            -- Legacy UnitBuff return signature (subset)
            return aura.name, aura.icon, aura.applications, aura.dispelName, aura.duration,
                   aura.expirationTime, aura.sourceUnit, aura.isStealable, aura.nameplateShowPersonal, aura.spellId
        end
        return nil
    end
    if UnitBuff then
        return _G.UnitBuff(unit, index, filter)
    end
    return nil
end


local frame = CreateFrame("Frame", "WanderlustDetectionFrame", UIParent)
local math_abs = math.abs
local math_max = math.max
local math_min = math.min
local math_sin = math.sin
local math_sqrt = math.sqrt
local math_pi = math.pi
local UnitIsDead = UnitIsDead
local UnitIsGhost = UnitIsGhost
local IsMounted = IsMounted
local IsSwimming = IsSwimming
local IsIndoors = IsIndoors
local GetZoneText = GetZoneText
local C_Map_GetBestMapForUnit = C_Map.GetBestMapForUnit
local C_Map_GetPlayerMapPosition = C_Map.GetPlayerMapPosition

-- Cache hot-path handlers after login to avoid per-frame table lookups.
local handleExhaustionDecay
local handleAnguishUpdate
local handleHungerDarknessUpdate
local handleThirstDarknessUpdate
local handleHPTunnelVisionUpdate
local handleHungerUpdate
local handleThirstUpdate
local handleTemperatureUpdate
local hungerAccumulator = 0
local thirstAccumulator = 0

local function RefreshHandlers()
    handleExhaustionDecay = WL.HandleExhaustionDecay
    handleAnguishUpdate = WL.HandleAnguishUpdate
    handleHungerDarknessUpdate = WL.HandleHungerDarknessUpdate
    handleThirstDarknessUpdate = WL.HandleThirstDarknessUpdate
    handleHPTunnelVisionUpdate = WL.HandleHPTunnelVisionUpdate
    handleHungerUpdate = WL.HandleHungerUpdate
    handleThirstUpdate = WL.HandleThirstUpdate
    handleTemperatureUpdate = WL.HandleTemperatureUpdate
end

local CHECK_INTERVAL = 0.5
local MOVEMENT_CHECK_INTERVAL = 0.1
local accumulator = 0
local movementAccumulator = 0

local MOVEMENT_THRESHOLD = 0.0001

local warmthOverlay = nil
local warmthCurrentAlpha = 0
local warmthTargetAlpha = 0
local warmthPulsePhase = 0
local WARMTH_LERP_SPEED = 2.0
local WARMTH_PULSE_SPEED = 0.6
local WARMTH_MAX_ALPHA = 1.0

local function CreateWarmthOverlay()
    if warmthOverlay then
        return warmthOverlay
    end

    warmthOverlay = CreateFrame("Frame", "WanderlustWarmthOverlay", UIParent)
    warmthOverlay:SetAllPoints(UIParent)
    warmthOverlay:SetFrameStrata("FULLSCREEN_DIALOG")
    warmthOverlay:SetFrameLevel(50)

    warmthOverlay.texture = warmthOverlay:CreateTexture(nil, "ARTWORK")
    warmthOverlay.texture:SetAllPoints()
    warmthOverlay.texture:SetTexture("Interface\\AddOns\\Wanderlust\\assets\\full-health-overlay.png")
    warmthOverlay.texture:SetBlendMode("ADD")
    warmthOverlay.texture:SetDesaturated(true)
    warmthOverlay.texture:SetVertexColor(1.0, 0.5, 0.1, 1.0)

    warmthOverlay:SetAlpha(0)
    warmthOverlay:EnableMouse(false)

    WL.Debug("Warmth overlay frame created", "general")
    return warmthOverlay
end

local function ShouldShowWarmthOverlay()
    if not WL.GetSetting or not WL.GetSetting("enabled") then
        return false
    end
    if not WL.IsPlayerEligible or not WL.IsPlayerEligible() then
        return false
    end
    if UnitIsDead("player") or UnitIsGhost("player") then
        return false
    end
    if WL.inCombat then
        return false
    end
    if IsMounted() then
        return false
    end
    return WL.isNearFireRaw == true
end

local function UpdateWarmthOverlay(elapsed)
    if not warmthOverlay then
        CreateWarmthOverlay()
    end

    local shouldShow = ShouldShowWarmthOverlay()
    local prevTarget = warmthTargetAlpha
    if shouldShow then
        warmthTargetAlpha = WARMTH_MAX_ALPHA
    else
        warmthTargetAlpha = 0
    end

    if prevTarget ~= warmthTargetAlpha then
        if warmthTargetAlpha > 0 then
            WL.Debug("Warmth overlay activating (near fire)", "general")
        else
            WL.Debug("Warmth overlay deactivating", "general")
        end
    end

    local diff = warmthTargetAlpha - warmthCurrentAlpha
    if math_abs(diff) < 0.001 then
        warmthCurrentAlpha = warmthTargetAlpha
    else
        warmthCurrentAlpha = warmthCurrentAlpha + (diff * WARMTH_LERP_SPEED * elapsed)
    end

    warmthCurrentAlpha = math_max(0, math_min(1, warmthCurrentAlpha))

    local finalAlpha = warmthCurrentAlpha
    if warmthCurrentAlpha > 0.01 then
        warmthPulsePhase = warmthPulsePhase + elapsed * WARMTH_PULSE_SPEED
        if warmthPulsePhase > 1 then
            warmthPulsePhase = warmthPulsePhase - 1
        end
        local pulseMod = 0.9 + 0.1 * math_sin(warmthPulsePhase * math_pi * 2)
        finalAlpha = warmthCurrentAlpha * pulseMod
    end

    warmthOverlay:SetAlpha(finalAlpha)

    if finalAlpha > 0.001 then
        if not warmthOverlay:IsShown() then
            warmthOverlay:Show()
        end
    else
        if warmthOverlay:IsShown() then
            warmthOverlay:Hide()
        end
    end
end

local function YardsToMapUnits(yards)
    return yards * 0.001
end

local function GetNormalizedCoord(value)
    return value > 1.0 and value / 100 or value
end

local function GetPlayerPosition()
    local mapID = C_Map_GetBestMapForUnit("player")
    if not mapID then
        return nil, nil, nil
    end
    local pos = C_Map_GetPlayerMapPosition(mapID, "player")
    if not pos then
        return nil, nil, nil
    end
    return pos.x, pos.y, GetZoneText()
end

local function HasPlayerMoved()
    local x, y = GetPlayerPosition()
    if not x or not y then
        return false
    end

    if WL.lastPlayerX and WL.lastPlayerY then
        local dx = math_abs(x - WL.lastPlayerX)
        local dy = math_abs(y - WL.lastPlayerY)
        local moved = (dx > MOVEMENT_THRESHOLD or dy > MOVEMENT_THRESHOLD)

        WL.lastPlayerX = x
        WL.lastPlayerY = y
        return moved
    end

    WL.lastPlayerX = x
    WL.lastPlayerY = y
    return false
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

local function CheckStaticFireProximity()
    if WL.GetSetting("fireDetectionMode") == 2 then
        return false, GetZoneText()
    end

    local playerX, playerY, zone = GetPlayerPosition()
    if not playerX or not zone then
        return false, nil
    end

    local rangeYards = WL.GetSetting("campfireRange") or 3
    local range = YardsToMapUnits(rangeYards)
    local zoneFires = WanderlustFireDB[zone]

    if not zoneFires then
        WL.Debug("No fires in zone: " .. zone, "proximity")
        return false, zone
    end

    local closestDist = 999
    local closestIdx = 0

    for i, fire in ipairs(zoneFires) do
        local fx = GetNormalizedCoord(fire.x)
        local fy = GetNormalizedCoord(fire.y)
        local dx = fx - playerX
        local dy = fy - playerY
        local dist = math_sqrt(dx * dx + dy * dy)

        if dist < closestDist then
            closestDist = dist
            closestIdx = i
        end

        if dist < range then
            if fire.noMount and CanPlayerMount() then
                if WL.GetSetting("proximityDebugEnabled") then
                    WL.Debug(string.format("Skipping noMount fire %d (player can mount)", i), "proximity")
                end
            else
                if WL.GetSetting("proximityDebugEnabled") then
                    WL.Debug(string.format("FOUND fire %d at %.1f yds", i, dist / 0.001), "proximity")
                end
                return true, zone
            end
        end
    end

    if WL.GetSetting("proximityDebugEnabled") then
        local closestYards = closestDist / 0.001
        WL.Debug(string.format("Closest fire #%d is %.1f yds away (need < %d)", closestIdx, closestYards, rangeYards),
            "proximity")
    end

    return false, zone
end

local function HasBasicCampfireBuff()
    if not WL.GetSetting("detectPlayerCampfires") then
        return false
    end
    if WL.GetSetting("fireDetectionMode") == 2 then
        return false
    end

    for i = 1, 40 do
        local name, _, _, _, _, _, _, _, _, spellId = WL_UnitBuff("player", i)
        if not name then
            break
        end
        if spellId == 7353 or name == "Cozy Fire" then
            WL.Debug("Player campfire buff found", "proximity")
            return true
        end
    end
    return false
end

local function CheckManualRestProximity()
    local playerX, playerY, zone = GetPlayerPosition()
    if not playerX or not zone then
        return false
    end

    local rangeYards = WL.GetSetting("campfireRange") or 3
    local range = YardsToMapUnits(rangeYards)
    local zoneFires = WanderlustFireDB[zone]

    if zoneFires then
        for i, fire in ipairs(zoneFires) do
            local fx = GetNormalizedCoord(fire.x)
            local fy = GetNormalizedCoord(fire.y)
            local dx = fx - playerX
            local dy = fy - playerY
            local dist = math_sqrt(dx * dx + dy * dy)
            if dist < range then
                if not (fire.noMount and CanPlayerMount()) then
                    return true
                end
            end
        end
    end

    if WL.GetSetting("detectPlayerCampfires") then
        for i = 1, 40 do
            local name, _, _, _, _, _, _, _, _, spellId = WL_UnitBuff("player", i)
            if not name then
                break
            end
            if spellId == 7353 or name == "Cozy Fire" then
                return true
            end
        end
    end

    return false
end

local function UpdateFireProximity()
    local mode = WL.GetSetting("fireDetectionMode")
    local foundAny = false

    if mode == 1 then
        local foundStatic = CheckStaticFireProximity()
        local foundPlayer = HasBasicCampfireBuff()
        foundAny = foundStatic or foundPlayer
    else
        if WL.isManualRestActive then
            foundAny = CheckManualRestProximity()
            if not foundAny then
                WL.DeactivateManualRest()
                print("|cff88CCFFWanderlust:|r No campfire nearby. Rest cancelled.")
            end
        end
    end

    WL.isNearFireRaw = foundAny

    local isMounted = IsMounted()
    local newIsNearFire = foundAny and not WL.inCombat and not isMounted
    local safeChanged = WL.isNearFire ~= newIsNearFire

    if safeChanged then
        WL.isNearFire = newIsNearFire

        if WL.GetSetting("debugEnabled") then
            local fire = foundAny and "|cff00FF00FIRE|r" or "|cffFF0000NO FIRE|r"
            local combat = WL.inCombat and "|cffFF0000[COMBAT]|r " or ""
            local result = WL.isNearFire and "|cff00FF00SAFE|r" or "|cffFF0000LOCKED|r"
            print(string.format("|cff88CCFFWanderlust:|r %s%s -> %s", combat, fire, result))
        end

        WL.FireCallbacks("FIRE_STATE_CHANGED", WL.isNearFire, WL.inCombat)
    end

    return safeChanged
end

local function OnCombatStart()
    WL.inCombat = true
    local was = WL.isNearFire
    WL.isNearFire = false

    if WL.isManualRestActive then
        WL.DeactivateManualRest()
    end

    WL.Debug("|cffFF0000Combat Started|r", "general")
    if was then
        WL.FireCallbacks("FIRE_STATE_CHANGED", WL.isNearFire, WL.inCombat)
    end
end

local function OnCombatEnd()
    WL.inCombat = false
    WL.Debug("|cff00FF00Combat Ended|r", "general")
    UpdateFireProximity()
end

local restGracePeriod = 0

local function CheckMovementForManualRest()
    if not WL.isManualRestActive then
        return
    end
    if WL.GetSetting("fireDetectionMode") ~= 2 then
        return
    end

    if restGracePeriod > 0 then
        restGracePeriod = restGracePeriod - MOVEMENT_CHECK_INTERVAL
        local x, y = GetPlayerPosition()
        WL.lastPlayerX = x
        WL.lastPlayerY = y
        return
    end

    if HasPlayerMoved() then
        WL.DeactivateManualRest()
        print("|cff88CCFFWanderlust:|r You moved. Rest ended.")
        UpdateFireProximity()
        if WL.RefreshActionBars then
            WL.RefreshActionBars()
        end
    end
end

WL.RegisterCallback("MANUAL_REST_CHANGED", function(isActive)
    if isActive then
        restGracePeriod = 1.0
        local x, y = GetPlayerPosition()
        WL.lastPlayerX = x
        WL.lastPlayerY = y
    end
end)

frame:SetScript("OnUpdate", function(self, elapsed)
    if handleExhaustionDecay then
        handleExhaustionDecay(elapsed)
    end

    if handleAnguishUpdate then
        handleAnguishUpdate(elapsed)
    end

    if handleHungerDarknessUpdate then
        handleHungerDarknessUpdate(elapsed)
    end

    if handleThirstDarknessUpdate then
        handleThirstDarknessUpdate(elapsed)
    end

    if handleHPTunnelVisionUpdate then
        handleHPTunnelVisionUpdate(elapsed)
    end

    UpdateWarmthOverlay(elapsed)

    hungerAccumulator = hungerAccumulator + elapsed
    if hungerAccumulator >= 2.5 then
        hungerAccumulator = hungerAccumulator - 2.5
        if handleHungerUpdate then
            handleHungerUpdate(2.5)
        end
    end

    thirstAccumulator = thirstAccumulator + elapsed
    if thirstAccumulator >= 2.5 then
        thirstAccumulator = thirstAccumulator - 2.5
        if handleThirstUpdate then
            handleThirstUpdate(2.5)
        end
    end

    if handleTemperatureUpdate then
        handleTemperatureUpdate(elapsed)
    end

    movementAccumulator = movementAccumulator + elapsed
    if movementAccumulator >= MOVEMENT_CHECK_INTERVAL then
        movementAccumulator = movementAccumulator - MOVEMENT_CHECK_INTERVAL
        CheckMovementForManualRest()
    end

    accumulator = accumulator + elapsed
    if accumulator >= CHECK_INTERVAL then
        accumulator = accumulator - CHECK_INTERVAL
        UpdateFireProximity()
    end
end)

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("ZONE_CHANGED")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("UNIT_AURA")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_LOGIN" then
        RefreshHandlers()
        WL.isNearFire = false
        WL.inCombat = InCombatLockdown()
        local x, y = GetPlayerPosition()
        WL.lastPlayerX = x
        CreateWarmthOverlay()
        WL.lastPlayerY = y
        C_Timer.After(1, UpdateFireProximity)
    elseif event == "PLAYER_REGEN_DISABLED" then
        OnCombatStart()
    elseif event == "PLAYER_REGEN_ENABLED" then
        OnCombatEnd()
    elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_NEW_AREA" then
        if WL.isManualRestActive then
            WL.DeactivateManualRest()
        end
        UpdateFireProximity()
    elseif event == "UNIT_AURA" and arg1 == "player" and WL.GetSetting("detectPlayerCampfires") then
        UpdateFireProximity()
    end
end)

function WL.ForceUpdate()
    return UpdateFireProximity()
end
