-- Wanderlust - anguish system
local WL = Wanderlust
-- ---------------------------------------------------------------------------
-- Midnight / modern client compatibility helpers
-- - GetSpellInfo() is deprecated; use C_Spell when available.
-- ---------------------------------------------------------------------------
local function WL_GetSpellName(spellID)
    if not spellID then return nil end

    -- Modern client (Midnight / Retail)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        return info and info.name or nil
    end

    -- Legacy fallback (Classic-era clients)
    if type(GetSpellInfo) == "function" then
        local name = GetSpellInfo(spellID)
        return name
    end

    return nil
end

local math_abs = math.abs
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local math_pi = math.pi
local math_sin = math.sin

local Anguish = 0
local savedAnguish = 0
local maxAnguish = 100
local lastPlayerHealth = 0
local isInDungeon = false

local isDazed = false

local overlayFrames = {}
local overlayCurrentAlphas = {0, 0, 0, 0}
local overlayTargetAlphas = {0, 0, 0, 0}

local overlayPulsePhase = 0
local OVERLAY_PULSE_SPEED = 0.5
local OVERLAY_PULSE_MIN = 0.7
local OVERLAY_PULSE_MAX = 1.0

local currentPulseType = 0
local currentPulseIntensity = 0
local PULSE_DECAY_RATE = 0.5

local isAnguishDecaying = false

local potionHealingActive = false
local potionHealingRemaining = 0
local potionHealingTimer = 0
local potionHealingExpiresAt = 0
local POTION_HEAL_DURATION = 120.0
local POTION_HEAL_INTERVAL = 5.0

local bandageHealingActive = false

local SCALE_VALUES = {0.05, 0.30, 3.0}
local SCALE_NAMES = {"Default (0.05x)", "Hard (0.3x)", "Insane (3x)"}
local SCALE_TOOLTIPS = {"Intended experience. Anguish builds moderately from damage.",
                        "More dangerous. Combat is significantly more punishing.",
                        "Extremely punishing. Tailored for hardcore and pet/kiting classes."}

local CRIT_MULTIPLIER = 5.0

local DAZE_MULTIPLIER = 5.0

local function GetScaleMultiplier()
    local setting = WL.GetSetting("AnguishScale") or 1
    return SCALE_VALUES[setting] or 0.01
end

function WL.GetAnguishScaleNames()
    return SCALE_NAMES
end

function WL.GetAnguishScaleTooltips()
    return SCALE_TOOLTIPS
end

local function CheckDungeonStatus()
    return WL.IsInDungeonOrRaid()
end

local function ShouldAccumulateAnguish()
    if not WL.GetSetting("AnguishEnabled") then
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

local function ShouldShowOverlay()
    if not WL.GetSetting("AnguishEnabled") then
        return false
    end
    if not WL.GetSetting("anguishOverlayEnabled") then
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

local function GetOverlayLevel()
    if Anguish >= 80 then
        return 4
    elseif Anguish >= 60 then
        return 3
    elseif Anguish >= 40 then
        return 2
    elseif Anguish >= 20 then
        return 1
    else
        return 0
    end
end

local function GetMinHealableAnguish()
    if Anguish >= 75 then
        return 75
    elseif Anguish >= 50 then
        return 50
    elseif Anguish >= 25 then
        return 25
    else
        return 0
    end
end

local Anguish_TEXTURES = {"Interface\\AddOns\\Wanderlust\\assets\\anguish20.png",
                          "Interface\\AddOns\\Wanderlust\\assets\\anguish40.png",
                          "Interface\\AddOns\\Wanderlust\\assets\\anguish60.png",
                          "Interface\\AddOns\\Wanderlust\\assets\\anguish80.png"}

local fullHealthOverlay = nil
local fullHealthAlpha = 0
local fullHealthTargetAlpha = 0

local cityHealPulsePhase = 0
local CITY_HEAL_PULSE_SPEED = 2
local cityHealOverlayAlpha = 0
local cityHealOverlayTarget = 0

local function CreateFullHealthOverlay()
    if fullHealthOverlay then
        return fullHealthOverlay
    end

    fullHealthOverlay = CreateFrame("Frame", "WanderlustFullHealthOverlay", UIParent)
    fullHealthOverlay:SetAllPoints(UIParent)
    fullHealthOverlay:SetFrameStrata("FULLSCREEN_DIALOG")
    fullHealthOverlay:SetFrameLevel(110)

    fullHealthOverlay.texture = fullHealthOverlay:CreateTexture(nil, "BACKGROUND")
    fullHealthOverlay.texture:SetAllPoints()
    fullHealthOverlay.texture:SetTexture("Interface\\AddOns\\Wanderlust\\assets\\full-health-overlay.png")
    fullHealthOverlay.texture:SetBlendMode("ADD")

    fullHealthOverlay:SetAlpha(0)
    fullHealthOverlay:Hide()

    return fullHealthOverlay
end

local function FlashFullHealthOverlay()
    if not fullHealthOverlay then
        CreateFullHealthOverlay()
    end
    fullHealthOverlay:Show()
    fullHealthAlpha = 0.8
    fullHealthTargetAlpha = 0
end

local function CreateOverlayFrameForLevel(level)
    local frameName = "WanderlustAnguishOverlay_" .. level

    if overlayFrames[level] then
        return overlayFrames[level]
    end

    local frame = CreateFrame("Frame", frameName, UIParent)
    frame:SetAllPoints(UIParent)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(100 + level)

    frame.texture = frame:CreateTexture(nil, "BACKGROUND")
    frame.texture:SetAllPoints()
    frame.texture:SetTexture(Anguish_TEXTURES[level])
    frame.texture:SetBlendMode("BLEND")

    frame:SetAlpha(0)
    frame:Hide()

    overlayFrames[level] = frame
    return frame
end

local function CreateAllOverlayFrames()
    for i = 1, 4 do
        CreateOverlayFrameForLevel(i)
    end
end

local function ShouldShowCityHealOverlay()
    return IsResting() and Anguish > 25 and isAnguishDecaying
end

local function UpdateOverlayAlphas(elapsed)
    local showCityHeal = ShouldShowCityHealOverlay()

    if not ShouldShowOverlay() then
        for i = 1, 4 do
            overlayTargetAlphas[i] = 0
        end
        cityHealOverlayTarget = 0
    elseif showCityHeal then
        for i = 1, 4 do
            overlayTargetAlphas[i] = 0
        end
        cityHealOverlayTarget = 1.0
    else
        cityHealOverlayTarget = 0
        local level = GetOverlayLevel()
        for i = 1, 4 do
            if i <= level then
                overlayTargetAlphas[i] = 0.7
                if overlayFrames[i] then
                    if not overlayFrames[i]:IsShown() then
                        overlayFrames[i]:SetAlpha(0)
                        overlayFrames[i]:Show()
                    end
                end
            else
                overlayTargetAlphas[i] = 0
            end
        end
    end

    overlayPulsePhase = overlayPulsePhase + elapsed * OVERLAY_PULSE_SPEED
    if overlayPulsePhase > 1 then
        overlayPulsePhase = overlayPulsePhase - 1
    end
    local pulseRange = OVERLAY_PULSE_MAX - OVERLAY_PULSE_MIN
    local pulseMod = OVERLAY_PULSE_MIN + (pulseRange * (0.5 + 0.5 * math_sin(overlayPulsePhase * math_pi * 2)))

    for i = 1, 4 do
        local frame = overlayFrames[i]
        if frame then
            local diff = overlayTargetAlphas[i] - overlayCurrentAlphas[i]
            if math_abs(diff) < 0.01 then
                overlayCurrentAlphas[i] = overlayTargetAlphas[i]
            else
                local speed = diff > 0 and 2.0 or 1.0
                overlayCurrentAlphas[i] = overlayCurrentAlphas[i] + (diff * speed * elapsed)
            end

            overlayCurrentAlphas[i] = math_max(0, math_min(1, overlayCurrentAlphas[i]))

            local finalAlpha = overlayCurrentAlphas[i] * pulseMod
            frame:SetAlpha(finalAlpha)

            if overlayCurrentAlphas[i] <= 0.01 and overlayTargetAlphas[i] == 0 then
                frame:Hide()
                overlayCurrentAlphas[i] = 0
            end
        end
    end

    if fullHealthOverlay then
        local diff = fullHealthTargetAlpha - fullHealthAlpha
        if math_abs(diff) < 0.01 then
            fullHealthAlpha = fullHealthTargetAlpha
        else
            fullHealthAlpha = fullHealthAlpha + (diff * 2.0 * elapsed)
        end
        fullHealthAlpha = math_max(0, math_min(1, fullHealthAlpha))
        fullHealthOverlay:SetAlpha(fullHealthAlpha)

        if fullHealthAlpha <= 0.01 and fullHealthTargetAlpha == 0 then
            fullHealthOverlay:Hide()
            fullHealthAlpha = 0
        end
    end

    if not fullHealthOverlay then
        CreateFullHealthOverlay()
    end

    local cityHealDiff = cityHealOverlayTarget - cityHealOverlayAlpha
    if math_abs(cityHealDiff) < 0.01 then
        cityHealOverlayAlpha = cityHealOverlayTarget
    else
        local transitionSpeed = 1.5
        cityHealOverlayAlpha = cityHealOverlayAlpha + (cityHealDiff * transitionSpeed * elapsed)
    end
    cityHealOverlayAlpha = math_max(0, math_min(1, cityHealOverlayAlpha))

    if cityHealOverlayAlpha > 0.01 then
        cityHealPulsePhase = cityHealPulsePhase + elapsed * CITY_HEAL_PULSE_SPEED
        local pulseMod = 0.25 + 0.10 * math_sin(cityHealPulsePhase * math_pi * 2)
        fullHealthOverlay:Show()
        fullHealthOverlay:SetAlpha(cityHealOverlayAlpha * pulseMod)
    elseif cityHealOverlayTarget == 0 and fullHealthTargetAlpha == 0 and fullHealthAlpha <= 0.01 then
        if cityHealOverlayAlpha <= 0.01 then
            fullHealthOverlay:Hide()
            cityHealPulsePhase = 0
        end
    end
end

local function TriggerPulse(pulseType, intensity)
    currentPulseType = pulseType
    currentPulseIntensity = math_max(0.3, math_min(1.0, (intensity or 0.5) * 2.0))
end

local function UpdatePulse(elapsed)
    if currentPulseIntensity > 0 then
        currentPulseIntensity = currentPulseIntensity - (PULSE_DECAY_RATE * elapsed)
        if currentPulseIntensity <= 0 then
            currentPulseIntensity = 0
            currentPulseType = 0
        end
    end
end

function WL.GetAnguishPulse()
    return currentPulseType, currentPulseIntensity
end

local lastDamageWasCrit = false

local function ProcessDamage()
    if not ShouldAccumulateAnguish() then
        return
    end

    local current = UnitHealth("player")
    local max = UnitHealthMax("player")
    if not current or not max or max <= 0 then
        return
    end

    local damage = lastPlayerHealth - current
    if damage > 0 then
        local scale = GetScaleMultiplier()
        local increase = (damage / max) * maxAnguish * scale
        if WL.IsLingeringActive and WL.IsLingeringActive("bleed") then
            increase = increase * 3
        end
        local wasCrit = lastDamageWasCrit

        if isDazed then
            increase = increase * DAZE_MULTIPLIER
            WL.Debug(string.format("DAZED! Anguish x%.1f", DAZE_MULTIPLIER), "Anguish")
        end

        if lastDamageWasCrit then
            increase = increase * CRIT_MULTIPLIER
            WL.Debug(string.format("CRIT! Anguish x%.1f", CRIT_MULTIPLIER), "Anguish")
            lastDamageWasCrit = false
        end

        Anguish = math_min(maxAnguish, Anguish + increase)

        WL.Debug(string.format("Damage: %d HP, +%.2f%% (%.2fx) -> Anguish: %.1f%%", damage, increase, scale, Anguish),
            "Anguish")

        local pulseType = wasCrit and 2 or 1
        TriggerPulse(pulseType, damage / max)
    end

    lastPlayerHealth = current
end

local function ProcessDazeApplied()
    if not ShouldAccumulateAnguish() then
        return
    end

    isDazed = true
    local baseIncrease = 1.0
    if WL.IsLingeringActive and WL.IsLingeringActive("bleed") then
        baseIncrease = baseIncrease * 3
    end
    Anguish = math_min(maxAnguish, Anguish + baseIncrease)

    WL.Debug(
        string.format("DAZED! +%.1f%% immediate -> Anguish: %.1f%% (5x damage while dazed)", baseIncrease, Anguish),
        "Anguish")
    TriggerPulse(3, 1.0)
end

local function ProcessDazeRemoved()
    isDazed = false
    WL.Debug("Daze ended - normal Anguish accumulation resumed", "Anguish")
end

local function ProcessBandageHeal()
    if not bandageHealingActive then
        return
    end

    local minAnguish = GetMinHealableAnguish()
    if Anguish <= minAnguish then
        return
    end

    local healing = 0.4
    Anguish = math_max(minAnguish, Anguish - healing)
    isAnguishDecaying = true
    WL.Debug(string.format("Bandage heal: -%.1f%% -> Anguish: %.1f%%", healing, Anguish), "Anguish")
end

local potionHealPerTick = 0

local function UpdatePotionHealing(elapsed)
    if not potionHealingActive then
        return false
    end

    potionHealingTimer = potionHealingTimer + elapsed
    if potionHealingTimer >= POTION_HEAL_INTERVAL then
        potionHealingTimer = potionHealingTimer - POTION_HEAL_INTERVAL

        local minAnguish = GetMinHealableAnguish()
        if potionHealingRemaining <= 0 or (potionHealingExpiresAt > 0 and GetTime() >= potionHealingExpiresAt) then
            potionHealingActive = false
            potionHealingExpiresAt = 0
            WL.Debug("Potion healing complete", "Anguish")
            return false
        end

        if Anguish <= minAnguish then
            return false
        end

        local healing = math_min(potionHealPerTick, potionHealingRemaining)
        healing = math_min(healing, Anguish - minAnguish)
        Anguish = math_max(minAnguish, Anguish - healing)
        potionHealingRemaining = potionHealingRemaining - healing

        WL.Debug(string.format("Potion heal: -%.2f%% -> Anguish: %.1f%% (%.2f%% remaining)", healing, Anguish,
            potionHealingRemaining), "Anguish")
        return true
    end
    return false
end

local function UpdateRestedHealing(elapsed)
    if not IsResting() then
        return false
    end
    if UnitOnTaxi("player") then
        return false
    end
    if Anguish <= 25 then
        return false
    end

    local healing = 0.5 * elapsed
    Anguish = math_max(25, Anguish - healing)
    return true
end

function WL.HandleAnguishUpdate(elapsed)
    UpdatePulse(elapsed)
    UpdateOverlayAlphas(elapsed)

    isAnguishDecaying = false

    if potionHealingActive then
        isAnguishDecaying = true
        UpdatePotionHealing(elapsed)
    end

    if UpdateRestedHealing(elapsed) then
        isAnguishDecaying = true
    end

    if bandageHealingActive and Anguish > 0 then
        isAnguishDecaying = true
    end
end

function WL.IsAnguishDecaying()
    return isAnguishDecaying and Anguish > 0
end

function WL.GetAnguish()
    return Anguish
end

function WL.GetAnguishPercent()
    return Anguish / maxAnguish
end

function WL.SetAnguish(value)
    value = tonumber(value)
    if not value then
        return false
    end
    Anguish = math_min(maxAnguish, math_max(0, value))
    WL.Debug(string.format("Anguish set to %.1f%%", Anguish), "Anguish")
    return true
end

function WL.ApplyLingeringAnguishDrain(amount)
    amount = tonumber(amount)
    if not amount or amount <= 0 then
        return
    end
    if not ShouldAccumulateAnguish() then
        return
    end
    Anguish = math_min(maxAnguish, Anguish + amount)
end

function WL.ResetAnguish()
    Anguish = math_floor(maxAnguish * 0.15)
    isDazed = false
    FlashFullHealthOverlay()
    WL.Debug("Anguish healed to 85% by innkeeper", "Anguish")
end

function WL.HealAnguishFully()
    Anguish = 0
    isDazed = false
    FlashFullHealthOverlay()
    WL.Debug("Anguish fully healed by First Aid trainer", "Anguish")
end

function WL.GetAnguishCheckpoint()
    return GetMinHealableAnguish()
end

function WL.IsDazed()
    return isDazed
end

function WL.IsAnguishActive()
    return ShouldAccumulateAnguish()
end

function WL.IsAnguishPaused()
    if not WL.GetSetting("AnguishEnabled") then
        return false
    end
    if not WL.IsPlayerEligible() then
        return false
    end
    return isInDungeon or UnitOnTaxi("player") or UnitIsDead("player") or UnitIsGhost("player")
end

function WL.GetAnguishActivity()
    if WL.IsAnguishPaused() then
        return nil
    end
    if bandageHealingActive then
        return "Bandaging"
    end
    if potionHealingActive then
        return "Potion healing"
    end
    if isAnguishDecaying and IsResting() then
        return "Resting in town"
    end
    if isDazed then
        return "Dazed"
    end
    if UnitAffectingCombat("player") then
        return "In combat"
    end
    return nil
end

function WL.IsBandaging()
    return bandageHealingActive
end

function WL.IsPotionHealing()
    return potionHealingActive
end

function WL.GetPotionHealingRemainingTime()
    if not potionHealingActive or potionHealingExpiresAt <= 0 then
        return 0
    end
    return math_max(0, potionHealingExpiresAt - GetTime())
end

local function OnZoneChanged()
    local wasInDungeon = isInDungeon
    isInDungeon = CheckDungeonStatus()

    if isInDungeon and not wasInDungeon then
        savedAnguish = Anguish
        WL.Debug(string.format("Entering dungeon - Anguish paused at %.1f%%", savedAnguish), "Anguish")
    elseif not isInDungeon and wasInDungeon then
        Anguish = savedAnguish
        WL.Debug(string.format("Leaving dungeon - Anguish restored to %.1f%%", Anguish), "Anguish")
    end
end

WL.RegisterCallback("SETTINGS_CHANGED", function(key)
    if key == "AnguishEnabled" or key == "ALL" then
        if not WL.GetSetting("AnguishEnabled") then
            for i = 1, 4 do
                overlayTargetAlphas[i] = 0
            end
        end
    end
    if key == "pauseInInstances" or key == "ALL" then
        OnZoneChanged()
    end
end)

local eventFrame = CreateFrame("Frame", "WanderlustAnguishFrame")
eventFrame:RegisterEvent("UNIT_HEALTH")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:RegisterEvent("PLAYER_DEAD")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

eventFrame:SetScript("OnEvent", function(self, event, arg1, ...)
    if event == "PLAYER_LOGIN" then
        if WL.charDB and WL.charDB.savedAnguish then
            Anguish = WL.charDB.savedAnguish
            WL.Debug(string.format("Anguish restored: %.1f%%", Anguish), "Anguish")
        else
            Anguish = 0
        end
        lastPlayerHealth = UnitHealth("player") or 0
        isDazed = false
        isInDungeon = CheckDungeonStatus()
        if isInDungeon and WL.charDB and WL.charDB.savedAnguishPreDungeon then
            savedAnguish = WL.charDB.savedAnguishPreDungeon
            WL.Debug(string.format("Pre-dungeon anguish restored: %.1f%%", savedAnguish), "Anguish")
        else
            savedAnguish = 0
        end
        CreateAllOverlayFrames()

    elseif event == "PLAYER_LOGOUT" then
        if WL.charDB then
            WL.charDB.savedAnguish = Anguish
            if isInDungeon then
                WL.charDB.savedAnguishPreDungeon = savedAnguish
            else
                WL.charDB.savedAnguishPreDungeon = nil
            end
        end

    elseif event == "UNIT_HEALTH" and arg1 == "player" then
        C_Timer.After(0.05, ProcessDamage)

    elseif event == "PLAYER_DEAD" then
        potionHealingActive = false
        potionHealingExpiresAt = 0
        bandageHealingActive = false
        isDazed = false

    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        OnZoneChanged()
        lastPlayerHealth = UnitHealth("player") or 0

    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local timestamp, subevent, _, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName,
            destFlags, destRaidFlags = CombatLogGetCurrentEventInfo()

        if destGUID == UnitGUID("player") then
            if subevent == "SWING_DAMAGE" or subevent == "SPELL_DAMAGE" or subevent == "RANGE_DAMAGE" or subevent ==
                "SPELL_PERIODIC_DAMAGE" then
                local args = {select(12, CombatLogGetCurrentEventInfo())}
                local critical = false
                if subevent == "SWING_DAMAGE" then
                    critical = args[7]
                else
                    critical = args[10]
                end
                if critical then
                    lastDamageWasCrit = true
                end
            end

            if subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REFRESH" then
                local spellId, spellName = select(12, CombatLogGetCurrentEventInfo())
                if spellName == "Dazed" or spellId == 1604 then
                    ProcessDazeApplied()
                end
            end

            if subevent == "SPELL_AURA_REMOVED" then
                local spellId, spellName = select(12, CombatLogGetCurrentEventInfo())
                if spellName == "Dazed" or spellId == 1604 then
                    ProcessDazeRemoved()
                end
            end
        end

    elseif event == "UNIT_SPELLCAST_CHANNEL_START" and arg1 == "player" then
        if isInDungeon then
            return
        end
        local spellName, _, _, _, _, _, _, _, spellTarget = UnitChannelInfo("player")
        if spellName and (spellName:match("Bandage") or spellName:match("First Aid")) then
            local targetUnit = spellTarget or "player"
            if targetUnit == "player" or UnitIsUnit(targetUnit, "player") then
                bandageHealingActive = true
                WL.Debug("Bandage healing started (self)", "Anguish")
            else
                WL.Debug("Bandage on other target - no anguish healing", "Anguish")
            end
        end

    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" and arg1 == "player" then
        if bandageHealingActive then
            bandageHealingActive = false
            WL.Debug("Bandage healing stopped", "Anguish")
        end

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" and arg1 == "player" then
        if isInDungeon then
            return
        end

        local castGUID, spellID = ...
        local spellName = spellID and WL_GetSpellName(spellID)

        WL.Debug(string.format("Spell succeeded: %s (ID: %s)", tostring(spellName), tostring(spellID)), "Anguish")

        if spellName and
            (spellName:match("Healing Potion") or spellName:match("Health Potion") or
                spellName:match("Healthstone") or spellName:match("Rejuvenation Potion") or
                spellName:match("Super Healing") or spellName:match("Mad Alchemist") or
                spellName:match("Fel Regeneration")) and
            not spellName:match("Mana") then
            local maxHeal = 3.0
            potionHealingRemaining = maxHeal
            potionHealPerTick = 0.125
            potionHealingTimer = 0
            potionHealingExpiresAt = GetTime() + POTION_HEAL_DURATION
            potionHealingActive = true
            WL.Debug(string.format("Potion used - will heal %.1f%% Anguish over %d seconds (%.3f%% per tick)", maxHeal,
                POTION_HEAL_DURATION, potionHealPerTick), "Anguish")
        end
    end
end)

local bandageTickTimer = 0
local BANDAGE_TICK_INTERVAL = 1.0

local originalOnUpdate = eventFrame:GetScript("OnUpdate")
eventFrame:SetScript("OnUpdate", function(self, elapsed)
    if originalOnUpdate then
        originalOnUpdate(self, elapsed)
    end

    if bandageHealingActive then
        bandageTickTimer = bandageTickTimer + elapsed
        if bandageTickTimer >= BANDAGE_TICK_INTERVAL then
            bandageTickTimer = bandageTickTimer - BANDAGE_TICK_INTERVAL
            ProcessBandageHeal()
        end
    else
        bandageTickTimer = 0
    end
end)
