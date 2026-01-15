-- Wanderlust - Lingering Effects (Survival)
local WL = Wanderlust
----------------------------------------------------------------
-- API compatibility (Midnight / modern clients)
-- GetSpellInfo -> C_Spell.GetSpellInfo
-- UnitDebuff -> C_UnitAuras.GetAuraDataByIndex / AuraUtil
----------------------------------------------------------------
local function WL_GetSpellName(spellID)
    if not spellID then return nil end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        return info and info.name or nil
    end
    if type(GetSpellInfo) == "function" then
        return GetSpellInfo(spellID)
    end
    return nil
end

local function WL_GetAuraDataByIndex(unit, index, filter)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        return C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
    end
    if AuraUtil and AuraUtil.GetAuraDataByIndex then
        return AuraUtil.GetAuraDataByIndex(unit, index, filter)
    end
    return nil
end

local ASSET_PATH = WL.ASSET_PATH or "Interface\\AddOns\\Wanderlust\\assets\\"
local RELIEF_SOUND = ASSET_PATH .. "hungerrelief.wav"

local EFFECTS = {
    poison = {
        duration = 1800,
        sound = ASSET_PATH .. "poisondiseasesound.wav",
        icon = ASSET_PATH .. "poisonicon.png",
        overlays = {
            ASSET_PATH .. "poison20.png",
            ASSET_PATH .. "poison40.png",
            ASSET_PATH .. "poison60.png",
            ASSET_PATH .. "poison80.png"
        }
    },
    disease = {
        duration = 3600,
        sound = ASSET_PATH .. "poisondiseasesound.wav",
        icon = ASSET_PATH .. "diseaseicon.png",
        overlays = {
            ASSET_PATH .. "disease20.png",
            ASSET_PATH .. "disease40.png",
            ASSET_PATH .. "disease60.png",
            ASSET_PATH .. "disease80.png"
        }
    },
    curse = {
        duration = 600,
        sound = ASSET_PATH .. "cursesound.wav",
        icon = ASSET_PATH .. "curseicon.png",
        overlays = {
            ASSET_PATH .. "curse20.png",
            ASSET_PATH .. "curse40.png",
            ASSET_PATH .. "curse60.png",
            ASSET_PATH .. "curse80.png"
        }
    },
    bleed = {
        duration = 900,
        sound = ASSET_PATH .. "bleedsound.wav",
        icon = ASSET_PATH .. "bleedicon.png",
        overlays = {
            ASSET_PATH .. "bleed20.png",
            ASSET_PATH .. "bleed40.png",
            ASSET_PATH .. "bleed60.png",
            ASSET_PATH .. "bleed80.png"
        }
    }
}

local EFFECT_ORDER = {"poison", "disease", "curse", "bleed"}

local LINGERING_COLOR = {
    poison = {0.1, 1.0, 0.2},
    disease = {1.0, 0.9, 0.2},
    curse = {0.7, 0.3, 1.0},
    bleed = {1.0, 0.2, 0.2}
}

-- Immersive messages for contracting lingering effects
local CONTRACTED_MESSAGES = {
    poison = {
        "The venom seeps deeper into your veins",
        "Toxins linger in your weakened body",
        "Your body struggles to purge the poison",
        "The poison takes root in your system",
        "Weakness lets the toxins spread unchecked",
        "Your blood carries the poison further",
        "The venom finds purchase in your flesh",
        "Fatigue allows the poison to fester",
    },
    disease = {
        "Illness creeps through your exhausted body",
        "Your weakened state invites infection",
        "The sickness takes hold of you",
        "Disease spreads through your weary form",
        "Your poor condition lets the plague in",
        "Fever begins to cloud your mind",
        "The infection finds a willing host",
        "Contagion settles into your bones",
    },
    curse = {
        "Dark magic clings to your weary soul",
        "The curse finds purchase in your weakness",
        "Malevolent energy wraps around you",
        "Your exhaustion invites the hex to stay",
        "The malediction seeps into your spirit",
        "Shadow magic binds itself to you",
        "Your worn defenses let the curse through",
        "Dark whispers echo in your tired mind",
    },
    bleed = {
        "The wound refuses to close properly",
        "Your weary body cannot stem the bleeding",
        "Blood continues to seep from the gash",
        "The laceration proves difficult to heal",
        "Exhaustion prevents the wound from clotting",
        "The cut runs deeper than expected",
        "Your body struggles to mend the tear",
        "The bleeding persists despite your efforts",
    },
}

local AVOIDED_MESSAGES = {
    poison = {
        "Your vigor fights off the lingering poison",
        "Good health purges the remaining toxins",
        "Your strong constitution resists the venom",
        "The poison fails to take hold",
        "Your body cleanses itself of the toxins",
        "Vitality burns away the lingering poison",
    },
    disease = {
        "Your healthy body wards off the sickness",
        "Strong constitution repels the infection",
        "The disease cannot take hold of you",
        "Your vigor fights off the illness",
        "Good health keeps the plague at bay",
        "Your body's defenses hold strong",
    },
    curse = {
        "Your spirit shrugs off the dark magic",
        "The curse dissipates against your will",
        "Your resolve breaks the hex's grip",
        "Light within you dispels the shadow",
        "The malediction fails to bind you",
        "Your strength of will repels the curse",
    },
    bleed = {
        "Your healthy body quickly stops the bleeding",
        "The wound begins to close on its own",
        "Strong constitution stems the blood flow",
        "Your vitality helps the wound clot",
        "Good health promotes rapid healing",
        "The bleeding subsides naturally",
    },
}

local function GetRandomMessage(messageTable, effectKey)
    local messages = messageTable[effectKey]
    if messages and #messages > 0 then
        return messages[math.random(1, #messages)]
    end
    return nil
end

local BLEED_KEYWORDS = {
    "bleed", "rend", "rupture", "garrote", "deep wounds", "deep wound", "lacerate", "rip"
}

local DISEASE_CRIT_MOBS = {
    ["diseased young wolf"] = true,
    ["diseased wolf"] = true,
    ["diseased black bear"] = true,
    ["diseased grizzly"] = true,
    ["diseased timber wolf"] = true,
    ["diseased kodo"] = true,
    ["diseased flayer"] = true,
    ["rabid thistle bear"] = true,
    ["rabid dire wolf"] = true,
    ["rabid shadowhide gnoll"] = true,
    ["rabid crag coyote"] = true,
    ["rabid blisterpaw"] = true,
    ["rabid war hound"] = true,
    ["rabid longsnout"] = true,
    ["plagued hatchling"] = true,
    ["plaguebat"] = true,
    ["plagued swine"] = true,
    ["plagued rat"] = true,
    ["plagued maggot"] = true,
    ["plagued insect"] = true,
    ["plagued ghoul"] = true,
    ["rotting slime"] = true,
    ["rotting agam'ar"] = true,
    ["rotting behemoth"] = true,
    ["rotting marine"] = true,
    ["blighted zombie"] = true,
    ["blighted horror"] = true,
    ["decaying horror"] = true
}

local SHADY_DEALERS = {
    ["ezekiel graves"] = true,
    ["tynnus venomsprout"] = true,
    ["jasper fel"] = true,
    ["miles sidney"] = true
}

local LINGER_STATE = {
    poison = {active = false, expiresAt = 0, duration = 0},
    disease = {active = false, expiresAt = 0, duration = 0},
    curse = {active = false, expiresAt = 0, duration = 0},
    bleed = {active = false, expiresAt = 0, duration = 0}
}

local auraState = {
    poison = {present = false, expiresAt = 0},
    disease = {present = false, expiresAt = 0},
    curse = {present = false, expiresAt = 0},
    bleed = {present = false, expiresAt = 0}
}

local overlayFrames = {
    poison = {},
    disease = {},
    curse = {},
    bleed = {}
}

local HideAllOverlays

local overlayCurrentAlphas = {
    poison = {0, 0, 0, 0},
    disease = {0, 0, 0, 0},
    curse = {0, 0, 0, 0},
    bleed = {0, 0, 0, 0}
}

local pulsePhase = {
    poison = 0,
    disease = 0,
    curse = 0,
    bleed = 0
}

local lastDispelTime = {
    poison = 0,
    disease = 0,
    curse = 0,
    bleed = 0
}

local lingeringPaused = false
local lingeringPauseStart = 0

local function ShouldPauseLingering()
    if WL.GetSetting and WL.GetSetting("pauseInInstances") then
        local inInstance = IsInInstance()
        if inInstance then
            return true
        end
    end
    if UnitOnTaxi("player") then
        return true
    end
    if UnitIsDead("player") or UnitIsGhost("player") then
        return true
    end
    return false
end

local PULSE_GROW = 5.0
local PULSE_HOLD = 1.0
local PULSE_SHRINK = 5.0
local PULSE_OFF = 120.0
local PULSE_CYCLE = PULSE_GROW + PULSE_HOLD + PULSE_SHRINK + PULSE_OFF

local lastWarningTarget = nil
local lastWarningTime = 0

local function IsSurvivalMode()
    return WL.GetSetting and WL.GetSetting("selectedPreset") == "survival"
end

local function IsLingeringEnabled()
    if not WL.GetSetting or not WL.GetSetting("lingeringEffectsEnabled") then
        return false
    end
    if not IsSurvivalMode() then
        return false
    end
    if not WL.GetSetting("constitutionEnabled") then
        return false
    end
    if WL.IsPlayerEligible and not WL.IsPlayerEligible() then
        return false
    end
    return true
end

function WL.IsLingeringEnabled()
    return IsLingeringEnabled()
end

local function GetConstitutionChance()
    local constitution = WL.GetConstitution and WL.GetConstitution() or 100
    return math.max(0, math.min(100, constitution))
end

local function SaveState()
    if not WL.charDB then
        return
    end
    WL.charDB.lingeringEffects = WL.charDB.lingeringEffects or {}
    for _, key in ipairs(EFFECT_ORDER) do
        local s = LINGER_STATE[key]
        if s and s.active and s.expiresAt > 0 then
            WL.charDB.lingeringEffects[key] = { expiresAt = s.expiresAt, duration = s.duration }
        else
            WL.charDB.lingeringEffects[key] = nil
        end
    end
end

local function LoadState()
    if not WL.charDB or not WL.charDB.lingeringEffects then
        return
    end
    local now = GetTime()
    for _, key in ipairs(EFFECT_ORDER) do
        local saved = WL.charDB.lingeringEffects[key]
        if saved and saved.expiresAt and saved.expiresAt > now then
            LINGER_STATE[key].active = true
            LINGER_STATE[key].expiresAt = saved.expiresAt
            LINGER_STATE[key].duration = saved.duration or EFFECTS[key].duration
        else
            LINGER_STATE[key].active = false
            LINGER_STATE[key].expiresAt = 0
            LINGER_STATE[key].duration = 0
        end
    end
end

local function PrintLingeringMessage(msg, color)
    local prefix = "|cff88CCFFWanderlust:|r "
    print(prefix .. (color or "") .. msg .. "|r")
end

local function DebugPrint(msg)
    if WL.GetSetting and WL.GetSetting("lingeringDebugEnabled") then
        print("|cffFFFF00[Lingering Debug]|r " .. msg)
    end
end

function WL.SetLingeringDebug(enabled)
    if WL.SetSetting then
        WL.SetSetting("lingeringDebugEnabled", enabled)
    end
    print("|cff88CCFFWanderlust:|r Lingering debug " .. (enabled and "enabled" or "disabled"))
end

local function RollLingering(effectKey)
    if not IsLingeringEnabled() then
        return
    end
    local chance = GetConstitutionChance()
    local roll = math.random(1, 100)
    local avoided = roll <= chance
    local contractChance = math.max(0, 100 - chance)

    if avoided then
        local msg = GetRandomMessage(AVOIDED_MESSAGES, effectKey) or ("Your good health saved you from lingering " .. effectKey)
        PrintLingeringMessage(string.format("%s (%d%% chance to contract)", msg, contractChance), "|cff00FF00")
        return
    end

    local msg = GetRandomMessage(CONTRACTED_MESSAGES, effectKey) or ("Your poor condition allowed lingering " .. effectKey)
    PrintLingeringMessage(string.format("%s (%d%% chance to contract)", msg, contractChance), "|cffFF4444")

    local effect = EFFECTS[effectKey]
    if not effect then
        return
    end

    LINGER_STATE[effectKey].active = true
    LINGER_STATE[effectKey].duration = effect.duration
    LINGER_STATE[effectKey].expiresAt = GetTime() + effect.duration

    SaveState()

    if effect.sound then
        PlaySoundFile(effect.sound, "SFX")
    end
end

local function ClearLingering(effectKey, reason)
    local state = LINGER_STATE[effectKey]
    if not state or not state.active then
        return
    end
    state.active = false
    state.expiresAt = 0
    state.duration = 0
    SaveState()

    if reason then
        PrintLingeringMessage(string.format("%s cleared (%s)", effectKey, reason), "|cff88FF88")
    end

    if reason == "Cured" then
        PlaySoundFile(RELIEF_SOUND, "SFX")
    end
end

function WL.ClearLingeringEffect(effectKey, reason)
    ClearLingering(effectKey, reason)
end

function WL.ClearAllLingeringEffects(reason)
    for _, key in ipairs(EFFECT_ORDER) do
        ClearLingering(key, reason)
    end
end

local function ResetLingeringTimer(effectKey)
    local state = LINGER_STATE[effectKey]
    if not state then
        return
    end
    state.active = true
    state.duration = EFFECTS[effectKey].duration
    state.expiresAt = GetTime() + state.duration
    SaveState()
end

local function ReduceLingeringTimer(effectKey, seconds)
    local state = LINGER_STATE[effectKey]
    if not state or not state.active then
        return
    end
    state.expiresAt = math.max(GetTime(), state.expiresAt - seconds)
    if state.expiresAt <= GetTime() + 0.1 then
        ClearLingering(effectKey, "Recovered")
    else
        SaveState()
    end
end

function WL.IsLingeringActive(effectKey)
    return LINGER_STATE[effectKey] and LINGER_STATE[effectKey].active or false
end

function WL.GetLingeringRemaining(effectKey)
    local state = LINGER_STATE[effectKey]
    if not state or not state.active then
        return 0
    end
    return math.max(0, state.expiresAt - GetTime())
end

local function IsBleedName(name)
    if not name then
        return false
    end
    local lower = name:lower()
    for _, key in ipairs(BLEED_KEYWORDS) do
        if lower:find(key, 1, true) then
            return true
        end
    end
    return false
end

local function ScanDebuffs()
    local found = { poison = nil, disease = nil, curse = nil, bleed = nil }

    -- Modern API
    if (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) or (AuraUtil and AuraUtil.GetAuraDataByIndex) then
        for i = 1, 40 do
            local aura = WL_GetAuraDataByIndex("player", i, "HARMFUL")
            if not aura then
                break
            end

            local name = aura.name
            local debuffType = aura.dispelName -- "Poison" / "Disease" / "Curse" (or nil)
            local expirationTime = aura.expirationTime or 0

            if debuffType == "Poison" then
                if not found.poison or expirationTime > (found.poison.expiresAt or 0) then
                    found.poison = { expiresAt = expirationTime }
                end
            elseif debuffType == "Disease" then
                if not found.disease or expirationTime > (found.disease.expiresAt or 0) then
                    found.disease = { expiresAt = expirationTime }
                end
            elseif debuffType == "Curse" then
                if not found.curse or expirationTime > (found.curse.expiresAt or 0) then
                    found.curse = { expiresAt = expirationTime }
                end
            elseif IsBleedName(name) then
                if not found.bleed or expirationTime > (found.bleed.expiresAt or 0) then
                    found.bleed = { expiresAt = expirationTime }
                end
            end
        end

        return found
    end

    -- Legacy API (Classic)
    for i = 1, 40 do
        local name, _, _, debuffType, _, expirationTime = UnitDebuff("player", i)
        if not name then
            break
        end

        if debuffType == "Poison" then
            if not found.poison or (expirationTime or 0) > (found.poison.expiresAt or 0) then
                found.poison = { expiresAt = expirationTime or 0 }
            end
        elseif debuffType == "Disease" then
            if not found.disease or (expirationTime or 0) > (found.disease.expiresAt or 0) then
                found.disease = { expiresAt = expirationTime or 0 }
            end
        elseif debuffType == "Curse" then
            if not found.curse or (expirationTime or 0) > (found.curse.expiresAt or 0) then
                found.curse = { expiresAt = expirationTime or 0 }
            end
        elseif IsBleedName(name) then
            if not found.bleed or (expirationTime or 0) > (found.bleed.expiresAt or 0) then
                found.bleed = { expiresAt = expirationTime or 0 }
            end
        end
    end

    return found
end

local function HandleAuraChanges()
    if not IsLingeringEnabled() then
        return
    end
    if ShouldPauseLingering() then
        return
    end

    local found = ScanDebuffs()
    local now = GetTime()

    for _, key in ipairs(EFFECT_ORDER) do
        local wasPresent = auraState[key].present
        local isPresent = found[key] ~= nil

        if isPresent then
            auraState[key].present = true
            auraState[key].expiresAt = found[key].expiresAt or 0
        elseif wasPresent then
            auraState[key].present = false
            local exp = auraState[key].expiresAt or 0
            auraState[key].expiresAt = 0

            if exp > 0 and now >= (exp - 0.25) then
                RollLingering(key)
            elseif exp == 0 then
                local dispelWindow = 1.0
                if now - (lastDispelTime[key] or 0) > dispelWindow then
                    RollLingering(key)
                end
            end
        end
    end
end

local function HandleDiseaseCrit(sourceName)
    if not sourceName then
        DebugPrint("HandleDiseaseCrit: sourceName is nil")
        return
    end
    local key = sourceName:lower()
    DebugPrint("HandleDiseaseCrit: sourceName='" .. key .. "', inList=" .. tostring(DISEASE_CRIT_MOBS[key] or false))
    if not DISEASE_CRIT_MOBS[key] then
        return
    end

    if not IsLingeringEnabled() then
        DebugPrint("HandleDiseaseCrit: IsLingeringEnabled=false, skipping roll")
        return
    end

    local chance = GetConstitutionChance()
    local roll = math.random(1, 100)
    local avoided = roll <= chance
    local contractChance = math.max(0, 100 - chance)
    DebugPrint("HandleDiseaseCrit: Rolling for disease - chance=" .. chance .. ", roll=" .. roll .. ", avoided=" .. tostring(avoided))
    if avoided then
        local msg = GetRandomMessage(AVOIDED_MESSAGES, "disease") or "Your good health saved you from disease"
        PrintLingeringMessage(string.format("%s (%d%% chance to contract)", msg, contractChance), "|cff00FF00")
    else
        local msg = GetRandomMessage(CONTRACTED_MESSAGES, "disease") or "Your poor health let disease creep in"
        PrintLingeringMessage(string.format("%s (%d%% chance to contract)", msg, contractChance), "|cffFF4444")
        ResetLingeringTimer("disease")
        local effect = EFFECTS.disease
        if effect and effect.sound then
            PlaySoundFile(effect.sound, "SFX")
        end
    end
end

local function CheckTargetWarning()
    if not IsLingeringEnabled() then
        DebugPrint("CheckTargetWarning: IsLingeringEnabled=false")
        return
    end

    local targetName = UnitName("target")
    if not targetName then
        return
    end
    local lower = targetName:lower()
    DebugPrint("CheckTargetWarning: target='" .. lower .. "', inList=" .. tostring(DISEASE_CRIT_MOBS[lower] or false))
    if not DISEASE_CRIT_MOBS[lower] then
        return
    end

    local now = GetTime()
    if lastWarningTarget ~= lower or (now - lastWarningTime) > 10 then
        PrintLingeringMessage("I should be careful fighting this enemy.", "|cffFFCC66")
        lastWarningTarget = lower
        lastWarningTime = now
    end
end

local function HandleSpellCure(spellName)
    if not spellName then
        DebugPrint("HandleSpellCure: spellName is nil")
        return
    end
    local lower = spellName:lower()

    if lower:find("bandage") or lower:find("first aid") then
        DebugPrint("HandleSpellCure: Detected bandage/first aid spell '" .. spellName .. "', reducing bleed timer by 3 min")
        local bleedState = LINGER_STATE.bleed
        if bleedState and bleedState.active then
            DebugPrint("HandleSpellCure: Bleed is active, remaining before: " .. (bleedState.expiresAt - GetTime()))
            ReduceLingeringTimer("bleed", 180) -- 3 minutes per bandage
            DebugPrint("HandleSpellCure: Bleed remaining after: " .. (bleedState.active and (bleedState.expiresAt - GetTime()) or 0))
        else
            DebugPrint("HandleSpellCure: Bleed is NOT active, nothing to reduce")
        end
    end
end

local function HandleTrainerCure()
    local npcName = UnitName("npc")
    if not npcName then
        return
    end
    local lower = npcName:lower()

    if SHADY_DEALERS[lower] then
        ClearLingering("poison", "Cured")
    end

    if WL.IsFirstAidTrainer and WL.IsFirstAidTrainer(npcName) then
        ClearLingering("bleed", "Cured")
        ClearLingering("poison", "Cured")
    end

    if WL.ClassTrainers and WL.ClassTrainers[npcName] and WL.ClassTrainers[npcName].class then
        local class = WL.ClassTrainers[npcName].class
        if class == "Druid" or class == "Shaman" or class == "Mage" or class == "Warlock" then
            ClearLingering("curse", "Cured")
        end
        if class == "Paladin" or class == "Priest" or class == "Shaman" or class == "Druid" then
            ClearLingering("disease", "Cured")
        end
        if class == "Rogue" or class == "Shaman" or class == "Druid" then
            ClearLingering("poison", "Cured")
        end
        if class == "Priest" or class == "Paladin" or class == "Druid" or class == "Shaman" then
            ClearLingering("bleed", "Cured")
        end
    end
end

local function UpdateOverlays(effectKey, elapsed)
    if not IsLingeringEnabled() then
        return
    end

    local state = LINGER_STATE[effectKey]
    if not state or not state.active then
        for i = 1, 4 do
            local frame = overlayFrames[effectKey][i]
            if frame then
                overlayCurrentAlphas[effectKey][i] = 0
                frame:SetAlpha(0)
                frame:Hide()
            end
        end
        return
    end

    pulsePhase[effectKey] = pulsePhase[effectKey] + elapsed
    local t = pulsePhase[effectKey] % PULSE_CYCLE

    local function SmoothStep(x)
        return x * x * (3 - 2 * x)
    end

    local levelIndex = 0
    local alphaLevels = {0, 0, 0, 0}

    if t <= PULSE_GROW then
        local prog = t / PULSE_GROW
        levelIndex = 1 + (SmoothStep(prog) * 3)
    elseif t <= PULSE_GROW + PULSE_HOLD then
        levelIndex = 4
    elseif t <= PULSE_GROW + PULSE_HOLD + PULSE_SHRINK then
        local prog = (t - PULSE_GROW - PULSE_HOLD) / PULSE_SHRINK
        levelIndex = 4 - (SmoothStep(prog) * 3)
    else
        levelIndex = 0
    end

    if levelIndex > 0 then
        local lower = math.floor(levelIndex)
        local upper = math.ceil(levelIndex)
        if lower < 1 then
            lower = 1
        end
        if upper > 4 then
            upper = 4
        end
        local frac = levelIndex - lower
        if lower == upper then
            alphaLevels[lower] = 1.0
        else
            alphaLevels[lower] = 1 - frac
            alphaLevels[upper] = frac
        end
    end

    for i = 1, 4 do
        local frame = overlayFrames[effectKey][i]
        if frame then
            local current = overlayCurrentAlphas[effectKey][i] or 0
            local target = alphaLevels[i] or 0
            local diff = target - current
            if math.abs(diff) < 0.01 then
                current = target
            else
                current = current + diff * math.min(1, 3 * elapsed)
            end
            overlayCurrentAlphas[effectKey][i] = current
            frame:SetAlpha(current)
            if current > 0.01 then
                if not frame:IsShown() then
                    frame:Show()
                end
            elseif frame:IsShown() then
                frame:Hide()
            end
        end
    end
end

local function UpdateLingeringEffects(elapsed)
    if not IsLingeringEnabled() then
        HideAllOverlays()
        return
    end

    local now = GetTime()
    local shouldPause = ShouldPauseLingering()
    if shouldPause then
        if not lingeringPaused then
            lingeringPaused = true
            lingeringPauseStart = now
        end
        for _, key in ipairs(EFFECT_ORDER) do
            local state = LINGER_STATE[key]
            if state.active then
                state.expiresAt = state.expiresAt + elapsed
            end
        end
        HideAllOverlays()
        return
    elseif lingeringPaused then
        lingeringPaused = false
        lingeringPauseStart = 0
    end

    for _, key in ipairs(EFFECT_ORDER) do
        local aura = auraState[key]
        if aura and aura.present and type(aura.expiresAt) == "number" and aura.expiresAt > 0 and now >= aura.expiresAt then
            aura.present = false
            aura.expiresAt = 0
            RollLingering(key)
        end
        local state = LINGER_STATE[key]
        if state.active and state.expiresAt <= now then
            ClearLingering(key, "Recovered")
        elseif state.active then
            UpdateOverlays(key, elapsed)
        end
    end
end

function WL.UpdateLingeringEffects(elapsed)
    UpdateLingeringEffects(elapsed)
end

local function CreateOverlayFrames(effectKey)
    local textures = EFFECTS[effectKey].overlays
    for i = 1, 4 do
        if not overlayFrames[effectKey][i] then
            local frame = CreateFrame("Frame", "Wanderlust" .. effectKey .. "Overlay" .. i, UIParent)
            frame:SetAllPoints(UIParent)
            frame:SetFrameStrata("FULLSCREEN_DIALOG")
            frame:SetFrameLevel(120 + i)
            frame.texture = frame:CreateTexture(nil, "BACKGROUND")
            frame.texture:SetAllPoints()
            frame.texture:SetTexture(textures[i])
            frame.texture:SetBlendMode("BLEND")
            frame:SetAlpha(0)
            frame:Hide()
            overlayFrames[effectKey][i] = frame
        end
    end
end

local function CreateAllOverlays()
    for _, key in ipairs(EFFECT_ORDER) do
        CreateOverlayFrames(key)
    end
end

HideAllOverlays = function()
    for _, key in ipairs(EFFECT_ORDER) do
        for i = 1, 4 do
            local frame = overlayFrames[key] and overlayFrames[key][i]
            if frame then
                frame:SetAlpha(0)
                frame:Hide()
            end
        end
        pulsePhase[key] = 0
    end
end

local function EnsureStateInitialized()
    if not WL.charDB then
        return
    end
    WL.charDB.lingeringEffects = WL.charDB.lingeringEffects or {}
end

local eventFrame = CreateFrame("Frame", "WanderlustLingeringFrame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:RegisterEvent("PLAYER_DEAD")
eventFrame:RegisterEvent("PLAYER_ALIVE")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("GOSSIP_SHOW")
eventFrame:RegisterEvent("TRAINER_SHOW")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2, ...)
    if event == "PLAYER_LOGIN" then
        EnsureStateInitialized()
        LoadState()
        CreateAllOverlays()
    elseif event == "PLAYER_LOGOUT" then
        SaveState()
    elseif event == "PLAYER_DEAD" then
        WL.ClearAllLingeringEffects("Death")
    elseif event == "PLAYER_ALIVE" then
        -- nothing
    elseif event == "UNIT_AURA" and arg1 == "player" then
        HandleAuraChanges()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" and arg1 == "player" then
        -- In TBC Classic, args are: unit, castGUID, spellID
        local spellID = ...
        local spellName
        DebugPrint("UNIT_SPELLCAST_SUCCEEDED: arg2=" .. tostring(arg2) .. ", spellID=" .. tostring(spellID) .. ", type=" .. type(spellID or "nil"))
        if spellID and type(spellID) == "number" then
            spellName = WL_GetSpellName(spellID)
            DebugPrint("Got spellName from GetSpellInfo: " .. tostring(spellName))
        elseif arg2 and type(arg2) == "string" then
            -- Fallback for older API: unit, spellName, rank, lineID, spellID
            spellName = arg2
            DebugPrint("Using arg2 as spellName: " .. tostring(spellName))
        end
        if spellName then
            DebugPrint("Checking spell: " .. spellName .. ", contains bandage: " .. tostring(spellName:lower():find("bandage") ~= nil))
        end
        HandleSpellCure(spellName)
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local timestamp, subEvent, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
              destGUID, destName, destFlags, destRaidFlags = CombatLogGetCurrentEventInfo()
        if destGUID == UnitGUID("player") then
            if subEvent == "SPELL_DISPEL" or subEvent == "SPELL_STOLEN" then
                local dispelType = select(15, CombatLogGetCurrentEventInfo())
                if dispelType == "Poison" then
                    lastDispelTime.poison = GetTime()
                elseif dispelType == "Disease" then
                    lastDispelTime.disease = GetTime()
                elseif dispelType == "Curse" then
                    lastDispelTime.curse = GetTime()
                end
            elseif subEvent == "SWING_DAMAGE" then
                -- SWING_DAMAGE: amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing
                local critical = select(18, CombatLogGetCurrentEventInfo())
                DebugPrint("SWING_DAMAGE from " .. tostring(sourceName) .. ", critical=" .. tostring(critical))
                if critical then
                    local lowerName = sourceName and sourceName:lower() or ""
                    DebugPrint("Checking if '" .. lowerName .. "' is in DISEASE_CRIT_MOBS: " .. tostring(DISEASE_CRIT_MOBS[lowerName] or false))
                    HandleDiseaseCrit(sourceName)
                end
            elseif subEvent == "SPELL_DAMAGE" or subEvent == "SPELL_PERIODIC_DAMAGE" or subEvent == "RANGE_DAMAGE" then
                -- SPELL_DAMAGE: spellId, spellName, spellSchool, amount, overkill, school, resisted, blocked, absorbed, critical
                local critical = select(21, CombatLogGetCurrentEventInfo())
                DebugPrint(subEvent .. " from " .. tostring(sourceName) .. ", critical=" .. tostring(critical))
                if critical then
                    local lowerName = sourceName and sourceName:lower() or ""
                    DebugPrint("Checking if '" .. lowerName .. "' is in DISEASE_CRIT_MOBS: " .. tostring(DISEASE_CRIT_MOBS[lowerName] or false))
                    HandleDiseaseCrit(sourceName)
                end
            end
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        CheckTargetWarning()
    elseif event == "GOSSIP_SHOW" or event == "TRAINER_SHOW" then
        HandleTrainerCure()
    end
end)

WL.RegisterCallback("SETTINGS_CHANGED", function(key)
    if key == "lingeringEffectsEnabled" or key == "selectedPreset" or key == "constitutionEnabled" or key == "ALL" then
        if not IsLingeringEnabled() then
            WL.ClearAllLingeringEffects("Disabled")
            HideAllOverlays()
        end
    end
end)

local updateFrame = CreateFrame("Frame")
updateFrame:SetScript("OnUpdate", function(self, elapsed)
    UpdateLingeringEffects(elapsed)
end)

-- Debug helpers
function WL.DebugSetLingering(effectKey, active)
    if not EFFECTS[effectKey] then
        return
    end
    if active then
        ResetLingeringTimer(effectKey)
        local effect = EFFECTS[effectKey]
        if effect and effect.sound then
            PlaySoundFile(effect.sound, "SFX")
        end
    else
        ClearLingering(effectKey, "Debug")
    end
end

function WL.GetLingeringColor(effectKey)
    return LINGERING_COLOR[effectKey]
end
