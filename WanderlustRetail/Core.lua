-- Wanderlust - addon bootstrap and shared helpers
local addonName = ...
Wanderlust = {
    version = "5.0.1",
    name = "Wanderlust",
    isNearFire = false,
    isNearFireRaw = false,
    inCombat = false,
    isManualRestActive = false,
    lastPlayerX = nil,
    lastPlayerY = nil,
    callbacks = {}
}

local WL = Wanderlust
local MIN_LEVEL = 6
WL.ASSET_PATH = "Interface\\AddOns\\" .. (addonName or "Wanderlust") .. "\\assets\\"
local ASSET_PATH = WL.ASSET_PATH

WL.COLORS = {
    ADDON = "|cff88CCFF",
    PROXIMITY = "|cff88FF88",
    EXHAUSTION = "|cffFFAA88",
    ANGUISH = "|cffFF6688",
    HUNGER = "|cffFFBB44",
    TEMPERATURE = "|cffFFCC55",
    WARNING = "|cffFF6600",
    SUCCESS = "|cff00FF00",
    ERROR = "|cffFF0000"
}

local DEBUG_SETTINGS = {
    general = "debugEnabled",
    proximity = "proximityDebugEnabled",
    exhaustion = "exhaustionDebugEnabled",
    Anguish = "AnguishDebugEnabled",
    hunger = "hungerDebugEnabled",
    temperature = "temperatureDebugEnabled"
}

local DEBUG_COLORS = {
    general = WL.COLORS.ADDON,
    proximity = WL.COLORS.PROXIMITY,
    exhaustion = WL.COLORS.EXHAUSTION,
    Anguish = WL.COLORS.ANGUISH,
    hunger = WL.COLORS.HUNGER,
    temperature = WL.COLORS.TEMPERATURE
}

local cachedStatus = {}
local cachedEligibility = nil

local function RefreshEligibility(levelOverride)
    local enabled = WL.GetSetting("enabled")
    if not enabled then
        cachedEligibility = false
        return
    end
    local level = levelOverride or UnitLevel("player")
    cachedEligibility = level >= MIN_LEVEL
end

function WL.IsInDungeonOrRaid()
    if WL.GetSetting and not WL.GetSetting("pauseInInstances") then
        return false
    end
    local inInstance, instanceType = IsInInstance()
    return inInstance and (instanceType == "party" or instanceType == "raid")
end

local DEFAULT_SETTINGS = {
    enabled = true,
    pauseInInstances = true,
    hideUIInInstances = false,
    campfireRange = 2,
    detectPlayerCampfires = false,

    -- 1=Auto Detect, 2=Manual Rest Mode
    fireDetectionMode = 1,

    -- 1=Disabled, 2=Near Fire or Rested, 3=Rested Only
    hideActionBarsMode = 2,

    hideMinimapWithBars = true,

    blockMapWithConstitution = true,

    blockBagsWithConstitution = true,

    meterScale = 1.0,

    selectedPreset = "survival",

    blockMap = true,

    showSurvivalIcons = true,

    metersLocked = false,
    showMinimapButton = true,


    exhaustionEnabled = true,
    exhaustionDecayRate = 0.5,
    exhaustionInnDecayRate = 1.5,

    AnguishEnabled = true,
    -- 1=0.1x, 2=0.5x, 3=3x
    AnguishScale = 1,
    innkeeperHealsAnguish = true,
    innkeeperResetsHunger = true,
    innkeeperResetsThirst = true,
    anguishOverlayEnabled = true,
    exhaustionOverlayEnabled = true,

    hungerEnabled = true,
    hungerMaxDarkness = 0.25,
    hungerOverlayEnabled = true,

    thirstEnabled = true,
    thirstMaxDarkness = 0.25,
    thirstOverlayEnabled = true,

    temperatureEnabled = true,
    manualWeatherEnabled = true,
    temperatureOverlayEnabled = true,

    constitutionEnabled = true,
    hideUIAtLowConstitution = true,
    lingeringEffectsEnabled = true,

    hpTunnelVisionEnabled = true,

    meterBarTexture = 1,

    generalFont = 1,

    -- "bar" or "vial"
    meterDisplayMode = "vial",

    hideVialText = false,

    -- "detailed", "minimal", or "disabled"
    tooltipDisplayMode = "detailed",

    debugEnabled = false,
    proximityDebugEnabled = false,
    exhaustionDebugEnabled = false,
    AnguishDebugEnabled = false,
    hungerDebugEnabled = false,
    temperatureDebugEnabled = false
}

local function InitializeSavedVariables()
    if not WanderlustDB then
        WanderlustDB = {}
    end
    for key, default in pairs(DEFAULT_SETTINGS) do
        if WanderlustDB[key] == nil then
            WanderlustDB[key] = default
        end
    end
    WL.db = WanderlustDB

    if not WanderlustCharDB then
        WanderlustCharDB = {}
    end
    WL.charDB = WanderlustCharDB
end

function WL.GetSetting(key)
    if WL.db and WL.db[key] ~= nil then
        return WL.db[key]
    end
    return DEFAULT_SETTINGS[key]
end

function WL.SetSetting(key, value)
    if WL.db then
        WL.db[key] = value

        if key == "enabled" and value == false then
            WL.db.blockMap = false
            WL.db.showSurvivalIcons = false
            WL.db.debugEnabled = false
            WL.db.proximityDebugEnabled = false
            WL.db.exhaustionDebugEnabled = false
            WL.db.AnguishDebugEnabled = false
            WL.db.temperatureDebugEnabled = false
        end

        WL.FireCallbacks("SETTINGS_CHANGED", key, value)
    end
end

function WL.ResetSettings()
    for key, value in pairs(DEFAULT_SETTINGS) do
        WL.db[key] = value
    end
    WL.FireCallbacks("SETTINGS_CHANGED", "ALL", nil)
end

function WL.GetDefaultSetting(key)
    return DEFAULT_SETTINGS[key]
end

function WL.GetMinLevel()
    return MIN_LEVEL
end

function WL.IsPlayerEligible()
    if cachedEligibility == nil then
        RefreshEligibility()
    end
    return cachedEligibility
end

function WL.RegisterCallback(eventOrFunc, callback)
    if type(eventOrFunc) == "function" then
        if not WL.callbacks["LEGACY"] then
            WL.callbacks["LEGACY"] = {}
        end
        table.insert(WL.callbacks["LEGACY"], eventOrFunc)
        return true
    end
    if type(callback) ~= "function" then
        return false
    end
    if not WL.callbacks[eventOrFunc] then
        WL.callbacks[eventOrFunc] = {}
    end
    table.insert(WL.callbacks[eventOrFunc], callback)
    return true
end

function WL.FireCallbacks(event, ...)
    if WL.callbacks[event] then
        for _, callback in ipairs(WL.callbacks[event]) do
            pcall(callback, ...)
        end
    end
    if event == "FIRE_STATE_CHANGED" and WL.callbacks["LEGACY"] then
        for _, callback in ipairs(WL.callbacks["LEGACY"]) do
            pcall(callback, WL.isNearFire, WL.inCombat)
        end
    end
end

function WL.Debug(msg, category)
    category = category or "general"
    local settingKey = DEBUG_SETTINGS[category]
    if not settingKey or not WL.GetSetting(settingKey) then
        return
    end
    local color = DEBUG_COLORS[category] or WL.COLORS.ADDON
    print(color .. "Wanderlust:|r " .. msg)
end

function WL.ShouldShowActionBars()
    local mode = WL.GetSetting("hideActionBarsMode") or 2
    if mode == 1 then
        return true
    end
    if not WL.IsPlayerEligible() then
        return true
    end
    if WL.inCombat then
        return false
    end
    if mode == 3 then
        return IsResting()
    end
    return WL.isNearFire or IsResting() or UnitOnTaxi("player") or UnitIsDead("player") or UnitIsGhost("player")
end

function WL.CanUseMap()
    if not WL.GetSetting("blockMap") then
        return true
    end
    if not WL.IsPlayerEligible() then
        return true
    end
    if WL.IsInDungeonOrRaid() then
        return true
    end
    if IsResting() then
        return true
    end
    if UnitOnTaxi("player") then
        return true
    end
    if UnitIsDead("player") or UnitIsGhost("player") then
        return true
    end
    local constitution = WL.GetConstitution and WL.GetConstitution()
    if constitution and constitution <= 50 then
        return false
    end
    return WL.isNearFire
end

function WL.GetStatus()
    cachedStatus.isNearFire = WL.isNearFire
    cachedStatus.inCombat = WL.inCombat
    cachedStatus.isManualRestActive = WL.isManualRestActive
    cachedStatus.shouldShowBars = WL.ShouldShowActionBars()
    cachedStatus.canUseMap = WL.CanUseMap()
    cachedStatus.exhaustion = WL.GetExhaustion and WL.GetExhaustion() or 0
    cachedStatus.Anguish = WL.GetAnguish and WL.GetAnguish() or 0
    cachedStatus.temperature = WL.GetTemperature and WL.GetTemperature() or 0
    cachedStatus.exhaustionEnabled = WL.GetSetting("exhaustionEnabled")
    cachedStatus.AnguishEnabled = WL.GetSetting("AnguishEnabled")
    cachedStatus.temperatureEnabled = WL.GetSetting("temperatureEnabled")
    cachedStatus.hideActionBars = WL.GetSetting("hideActionBars")
    cachedStatus.blockMap = WL.GetSetting("blockMap")
    cachedStatus.fireDetectionMode = WL.GetSetting("fireDetectionMode")
    cachedStatus.playerLevel = UnitLevel("player")
    cachedStatus.minLevel = MIN_LEVEL
    cachedStatus.version = WL.version
    return cachedStatus
end

function WL.ActivateManualRest()
    if WL.GetSetting("fireDetectionMode") ~= 2 then
        return false
    end
    WL.isManualRestActive = true
    WL.FireCallbacks("MANUAL_REST_CHANGED", true)
    DoEmote("SIT")
    WL.Debug("Manual rest activated", "general")
    return true
end

function WL.DeactivateManualRest()
    if not WL.isManualRestActive then
        return false
    end
    WL.isManualRestActive = false
    WL.Debug("Manual rest deactivated", "general")
    WL.FireCallbacks("MANUAL_REST_CHANGED", false)
    return true
end

function WL.IsManualRestMode()
    return WL.GetSetting("fireDetectionMode") == 2
end

function WL.GetFireLocations(zoneName)
    if not WanderlustFireDB then
        return nil
    end
    return WanderlustFireDB[zoneName]
end

local function CheckUHCConflict()
    local hasConflict = false
    local conflicts = {}

    local uhcLoaded = false
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        uhcLoaded = C_AddOns.IsAddOnLoaded("UltraHardcore")
    elseif IsAddOnLoaded then
        uhcLoaded = IsAddOnLoaded("UltraHardcore")
    end

    if uhcLoaded and GLOBAL_SETTINGS then
        if GLOBAL_SETTINGS.routePlanner and WL.GetSetting("blockMap") then
            hasConflict = true
            table.insert(conflicts, "Route Planner (map blocking)")
        end
        if GLOBAL_SETTINGS.hideActionBars and WL.GetSetting("hideActionBars") then
            hasConflict = true
            table.insert(conflicts, "Hide Action Bars")
        end
    end

    if hasConflict then
        local msg = "|cffFF6600Wanderlust Warning:|r UltraHardcore has conflicting settings enabled:\n"
        for _, c in ipairs(conflicts) do
            msg = msg .. "  - " .. c .. "\n"
        end
        msg = msg .. "Please disable these in UHC or Wanderlust to avoid issues."

        C_Timer.After(5, function()
            print(msg)
        end)
    end

    return hasConflict, conflicts
end

local function CreateLevelRequirementPopup()
    local popup = CreateFrame("Frame", "WanderlustLevelPopup", UIParent, "BackdropTemplate")
    popup:SetSize(360, 180)
    popup:SetPoint("CENTER", 0, 100)
    popup:SetFrameStrata("DIALOG")
    popup:SetFrameLevel(200)
    popup:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 2
    })
    popup:SetBackdropColor(0.06, 0.06, 0.08, 0.98)
    popup:SetBackdropBorderColor(0.12, 0.12, 0.14, 1)
    popup:EnableMouse(true)
    popup:SetMovable(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", popup.StartMoving)
    popup:SetScript("OnDragStop", popup.StopMovingOrSizing)

    local header = CreateFrame("Frame", nil, popup, "BackdropTemplate")
    header:SetSize(360, 50)
    header:SetPoint("TOP")
    header:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8"
    })
    header:SetBackdropColor(0.08, 0.08, 0.10, 1)

    local iconFrame = CreateFrame("Frame", nil, header)
    iconFrame:SetSize(40, 40)
    iconFrame:SetPoint("LEFT", 15, 0)

    local fireGlow = iconFrame:CreateTexture(nil, "BACKGROUND")
    fireGlow:SetSize(50, 50)
    fireGlow:SetPoint("CENTER", 0, 2)
    fireGlow:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMaskSmall")
    fireGlow:SetVertexColor(1.0, 0.5, 0.1, 0.4)
    fireGlow:SetBlendMode("ADD")

    local fireIcon = iconFrame:CreateTexture(nil, "ARTWORK")
    fireIcon:SetSize(36, 36)
    fireIcon:SetPoint("CENTER")
    fireIcon:SetTexture("Interface\\AddOns\\Wanderlust\\assets\\mainlogo.png")
    fireIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local glowAnim = fireGlow:CreateAnimationGroup()
    glowAnim:SetLooping("REPEAT")
    local pulse1 = glowAnim:CreateAnimation("Alpha")
    pulse1:SetFromAlpha(0.4)
    pulse1:SetToAlpha(0.7)
    pulse1:SetDuration(1.5)
    pulse1:SetOrder(1)
    pulse1:SetSmoothing("IN_OUT")
    local pulse2 = glowAnim:CreateAnimation("Alpha")
    pulse2:SetFromAlpha(0.7)
    pulse2:SetToAlpha(0.4)
    pulse2:SetDuration(1.5)
    pulse2:SetOrder(2)
    pulse2:SetSmoothing("IN_OUT")
    glowAnim:Play()

    local titleShadow = header:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    titleShadow:SetPoint("LEFT", iconFrame, "RIGHT", 11, -1)
    titleShadow:SetText("Welcome!")
    titleShadow:SetTextColor(0, 0, 0, 0.5)

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", iconFrame, "RIGHT", 10, 0)
    title:SetText("Welcome!")
    title:SetTextColor(1.0, 0.75, 0.35, 1)

    local content = CreateFrame("Frame", nil, popup, "BackdropTemplate")
    content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 10, -10)
    content:SetPoint("BOTTOMRIGHT", -10, 50)
    content:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1
    })
    content:SetBackdropColor(0.09, 0.09, 0.11, 0.95)
    content:SetBackdropBorderColor(0.18, 0.18, 0.2, 1)

    local text = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("CENTER", 0, 0)
    text:SetWidth(320)
    text:SetText(
        "Wanderlust survival systems will activate once you reach |cffFF9933Level 6|r.\n\nUntil then, enjoy your early survivals!")
    text:SetTextColor(0.85, 0.85, 0.85)
    text:SetJustifyH("CENTER")

    local okButton = CreateFrame("Button", nil, popup, "BackdropTemplate")
    okButton:SetSize(100, 28)
    okButton:SetPoint("BOTTOM", 0, 12)
    okButton:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1
    })
    okButton:SetBackdropColor(0.12, 0.12, 0.14, 1)
    okButton:SetBackdropBorderColor(1.0, 0.6, 0.2, 1)

    local btnText = okButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btnText:SetPoint("CENTER")
    btnText:SetText("Got it!")
    btnText:SetTextColor(1.0, 0.75, 0.35, 1)

    okButton:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.18, 0.18, 0.2, 1)
        self:SetBackdropBorderColor(1.0, 0.7, 0.3, 1)
    end)
    okButton:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.12, 0.12, 0.14, 1)
        self:SetBackdropBorderColor(1.0, 0.6, 0.2, 1)
    end)
    okButton:SetScript("OnClick", function()
        popup:Hide()
        if WL.charDB then
            WL.charDB.seenLevelPopup = true
        end
    end)

    popup:Hide()
    return popup
end

local levelPopup = nil
local introStepper = nil

local INTRO_PAGES = {{
    title = "Welcome to Wanderlust",
    mainImage = ASSET_PATH .. "tutorial/vialandstatusiconexample.png",
    mainSize = {195, 126},
    mainTexCoord = {0.0, 1.0, 0.0, 1.0},
    body = [[Wanderlust adds survival systems to your journey: Anguish, Exhaustion, Hunger, Thirst, Temperature, and Constitution.

Use the meters to track your status and watch the icons for active effects. Plan your routes around inns, campfires, and trainers to recover safely. 

Action bars in survival mode are disabled by default unless near fires, but if you wish to configure settings use /wander or click the minimap icons.]]
}, {
    title = "Status Icons",
    mainImage = ASSET_PATH .. "tutorial/constitution.png",
    uniformMainSize = true,
    mainTexCoord = {0.0, 1.0, 0.0, 1.0},
    icons = {
        {tex = ASSET_PATH .. "manapotionicon.png", tip = "Mana Potion: heat exposure reduced"},
        {tex = ASSET_PATH .. "potionicon.png", tip = "Health Potion: anguish recovery"},
        {tex = ASSET_PATH .. "bandageicon.png", tip = "Bandage: anguish recovery"},
        {tex = ASSET_PATH .. "weticon.png", tip = "Wet: colder when cold, cooler when warm"},
        {tex = ASSET_PATH .. "swimmingicon.png", tip = "Swimming: chills you and rehydrates slowly"},
        {tex = ASSET_PATH .. "wanderlusticon.png", tip = "Cozy: near fire or safe warmth"},
        {tex = ASSET_PATH .. "restedicon.png", tip = "Rested: recovery boosted"},
        {tex = ASSET_PATH .. "indoorsicon.png", tip = "Indoors: reduced exposure"},
        {tex = ASSET_PATH .. "wellfedicon.png", tip = "Well Fed: hunger paused, cold exposure reduced"},
        {tex = ASSET_PATH .. "alcoholicon.png", tip = "Alcohol: warmth bonus when cold"},
        {tex = ASSET_PATH .. "combaticon.png", tip = "Combat: increased strain"},
        {tex = ASSET_PATH .. "dazedicon.png", tip = "Dazed: extra trauma"},
        {tex = ASSET_PATH .. "constitutionicon.png", tip = "Constitution warning"},
        {tex = ASSET_PATH .. "poisonicon.png", tip = "Lingering Poison: thirst accumulation tripled"},
        {tex = ASSET_PATH .. "diseaseicon.png", tip = "Lingering Disease: hunger accumulation tripled"},
        {tex = ASSET_PATH .. "curseicon.png", tip = "Lingering Curse: exhaustion accumulation tripled"},
        {tex = ASSET_PATH .. "bleedicon.png", tip = "Lingering Bleed: anguish accumulation tripled"}
    },
    body = [[Status icons summarize your current survival effects. Hover them to see details and durations.

Watch these icons as you travel. They tell you when to rest, when you are protected, and when danger is rising.]]
}, {
    title = "Lingering Effects",
    icons = {
        {tex = ASSET_PATH .. "poisonicon.png", tip = "Poison: thirst accumulation tripled"},
        {tex = ASSET_PATH .. "diseaseicon.png", tip = "Disease: hunger accumulation tripled"},
        {tex = ASSET_PATH .. "curseicon.png", tip = "Curse: exhaustion accumulation tripled"},
        {tex = ASSET_PATH .. "bleedicon.png", tip = "Bleed: anguish accumulation tripled"}
    },
    body = [[Lingering Effects can apply after poison, disease, curse, or bleed debuffs expire naturally (not dispelled). Your Constitution roll decides if they stick. Dispelling any debuff prevents the lingering effects roll completely, so do so with haste.

Poison (30m), Disease (1h), Curse (10m), Bleed (15m) each triple accumulation while active.

Cures:
- Poison: shady dealers, First Aid trainers, rogue/shaman/druid trainers.
- Disease: paladin/priest/shaman/druid trainers.
- Curse: druid/mage/shaman/warlock trainers.
- Bleed: bandages (-3m), First Aid trainers, priest/paladin/druid/shaman trainers.
Death clears lingering effects.]]
}, {
    title = "Anguish",
    mainImage = ASSET_PATH .. "tutorial/anguish.png",
    uniformMainSize = true,
    mainTexCoord = {0.0, 1.0, 0.0, 1.0},
    icons = {
        {tex = ASSET_PATH .. "bandageicon.png", tip = "Bandage: anguish recovery"},
        {tex = ASSET_PATH .. "potionicon.png", tip = "Health Potion: anguish recovery"},
        {tex = ASSET_PATH .. "dazedicon.png", tip = "Dazed: extra trauma"},
        {tex = ASSET_PATH .. "combaticon.png", tip = "Combat: anguish builds faster"},
        {tex = ASSET_PATH .. "restedicon.png", tip = "Rested: deeper relief"},
        {tex = ASSET_PATH .. "constitutionicon.png", tip = "Constitution warning"},
        {tex = ASSET_PATH .. "bleedicon.png", tip = "Bleed: anguish accumulation tripled"}
    },
    body = [[Anguish rises from combat damage; critical hits and daze add extra trauma.

Bandages and health potions recover Anguish down to checkpoints. Resting in towns eases it further. Innkeepers provide deeper relief, and First Aid trainers fully restore vitality.]]
}, {
    title = "Exhaustion",
    mainImage = ASSET_PATH .. "tutorial/exhaust.png",
    uniformMainSize = true,
    mainTexCoord = {0.0, 1.0, 0.0, 1.0},
    icons = {
        {tex = ASSET_PATH .. "wanderlusticon.png", tip = "Cozy: exhaustion recovery"},
        {tex = ASSET_PATH .. "restedicon.png", tip = "Rested: stronger recovery"},
        {tex = ASSET_PATH .. "indoorsicon.png", tip = "Indoors: safer recovery"},
        {tex = ASSET_PATH .. "swimmingicon.png", tip = "Swimming: extra fatigue"},
        {tex = ASSET_PATH .. "combaticon.png", tip = "Combat: more exertion"},
        {tex = ASSET_PATH .. "constitutionicon.png", tip = "Constitution warning"},
        {tex = ASSET_PATH .. "curseicon.png", tip = "Curse: exhaustion accumulation tripled"}
    },
    body = [[Exhaustion builds while moving and traveling.

Resting near campfires or inside inns restores exhaustion. Cozy zones make recovery faster and keep you ready for long journeys.]]
}, {
    title = "Hunger",
    mainImage = ASSET_PATH .. "tutorial/hunger.png",
    uniformMainSize = true,
    mainTexCoord = {0.0, 1.0, 0.0, 1.0},
    icons = {
        {tex = ASSET_PATH .. "wellfedicon.png", tip = "Well Fed: hunger paused"},
        {tex = ASSET_PATH .. "wanderlusticon.png", tip = "Cozy: better recovery"},
        {tex = ASSET_PATH .. "restedicon.png", tip = "Rested: better recovery"},
        {tex = ASSET_PATH .. "alcoholicon.png", tip = "Alcohol: warmth, still food needed"},
        {tex = ASSET_PATH .. "combaticon.png", tip = "Combat: faster drain"},
        {tex = ASSET_PATH .. "constitutionicon.png", tip = "Constitution warning"},
        {tex = ASSET_PATH .. "diseaseicon.png", tip = "Disease: hunger accumulation tripled"}
    },
    body = [[Hunger rises with movement and exertion, faster when exhausted or in harsh temperatures.

Eating restores to checkpoints, with better recovery near fire or in rested areas. Well Fed pauses hunger drain and provides cold exposure resistance. Cooking trainers fully restore satiation.]]
}, {
    title = "Thirst",
    mainImage = ASSET_PATH .. "tutorial/thirst.png",
    uniformMainSize = true,
    mainTexCoord = {0.0, 1.0, 0.0, 1.0},
    icons = {
        {tex = ASSET_PATH .. "manapotionicon.png", tip = "Mana Potion: cooling, quenching"},
        {tex = ASSET_PATH .. "weticon.png", tip = "Wet: slight hydration help"},
        {tex = ASSET_PATH .. "swimmingicon.png", tip = "Swimming: slow hydration"},
        {tex = ASSET_PATH .. "restedicon.png", tip = "Rested: better recovery"},
        {tex = ASSET_PATH .. "combaticon.png", tip = "Combat: faster drain"},
        {tex = ASSET_PATH .. "constitutionicon.png", tip = "Constitution warning"},
        {tex = ASSET_PATH .. "poisonicon.png", tip = "Poison: thirst accumulation tripled"}
    },
    body = [[Thirst builds with travel, combat, and hot environments.

Drinking restores to checkpoints. Swimming and rain slowly restore hydration. Mana potions provide a cooling, quenching effect over time.]]
}, {
    title = "Temperature",
    mainImage = ASSET_PATH .. "tutorial/temperature.png",
    mainSize = {360, 34},
    mainTexCoord = {0.0, 1.0, 0.0, 1.0},
    mainBelowIcons = true,
    icons = {
        {tex = ASSET_PATH .. "wanderlusticon.png", tip = "Cozy: warmth near fire"},
        {tex = ASSET_PATH .. "wellfedicon.png", tip = "Well Fed: cold exposure reduced"},
        {tex = ASSET_PATH .. "weticon.png", tip = "Wet: colder when cold, cooler when warm"},
        {tex = ASSET_PATH .. "alcoholicon.png", tip = "Alcohol: warmth bonus"},
        {tex = ASSET_PATH .. "manapotionicon.png", tip = "Mana Potion: heat exposure reduced"},
        {tex = ASSET_PATH .. "indoorsicon.png", tip = "Indoors: reduced exposure"}
    },
    body = [[Hot and cold zones push your temperature away from comfort. Weather and swimming intensify exposure.

Well Fed reduces cold exposure by 50%. Mana potions reduce heat exposure by 50% when hot. Wet increases cold exposure and reduces heat exposure.

Manual Weather: use the weather toggle to simulate rain/snow/dust effects in Classic zones.]]
}, {
    title = "Constitution",
    mainImage = ASSET_PATH .. "tutorial/constitution.png",
    uniformMainSize = true,
    mainTexCoord = {0.0, 1.0, 0.0, 1.0},
    icons = {
        {tex = ASSET_PATH .. "constitutionicon.png", tip = "Constitution: overall survival state"},
        {tex = ASSET_PATH .. "wanderlusticon.png", tip = "Cozy: recovery safe zone"},
        {tex = ASSET_PATH .. "restedicon.png", tip = "Rested: fastest recovery"},
        {tex = ASSET_PATH .. "combaticon.png", tip = "Combat: risky state"},
        {tex = ASSET_PATH .. "dazedicon.png", tip = "Dazed: higher danger"},
        {tex = ASSET_PATH .. "wellfedicon.png", tip = "Well Fed: extra protection"}
    },
    body = [[Constitution blends multiple survival systems into one overall warning. When two or more systems are active, each contributes a weighted share to your Constitution.

Low Constitution hides UI elements and can block map or bags based on settings. Watch the warning icon and rest before it drops too far.

Blocked action icons:
- Map blocked (when constitution is low)
- Bags blocked (when constitution is very low)
These appear in the UI and flash if you press the blocked key.]]
}}

local function CreateIntroStepper()
    if introStepper then
        return introStepper
    end

    local frame = CreateFrame("Frame", "WanderlustIntroStepper", UIParent, "BackdropTemplate")
    frame:SetSize(600, 480)
    frame:SetPoint("CENTER", 0, 80)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(220)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 2
    })
    frame:SetBackdropColor(0.06, 0.06, 0.08, 0.98)
    frame:SetBackdropBorderColor(0.12, 0.12, 0.14, 1)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    local header = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    header:SetSize(520, 54)
    header:SetPoint("TOP")
    header:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8"
    })
    header:SetBackdropColor(0.08, 0.08, 0.10, 1)

    local iconFrame = CreateFrame("Frame", nil, header)
    iconFrame:SetSize(40, 40)
    iconFrame:SetPoint("LEFT", 15, 0)

    local fireGlow = iconFrame:CreateTexture(nil, "BACKGROUND")
    fireGlow:SetSize(50, 50)
    fireGlow:SetPoint("CENTER", 0, 2)
    fireGlow:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMaskSmall")
    fireGlow:SetVertexColor(1.0, 0.5, 0.1, 0.4)
    fireGlow:SetBlendMode("ADD")

    local headerIcon = iconFrame:CreateTexture(nil, "ARTWORK")
    headerIcon:SetSize(36, 36)
    headerIcon:SetPoint("CENTER")
    headerIcon:SetTexture("Interface\\AddOns\\Wanderlust\\assets\\mainlogo.png")
    headerIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local titleShadow = header:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    titleShadow:SetPoint("LEFT", iconFrame, "RIGHT", 11, -1)
    titleShadow:SetText("Wanderlust Intro")
    titleShadow:SetTextColor(0, 0, 0, 0.5)

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", iconFrame, "RIGHT", 10, 0)
    title:SetText("Wanderlust Intro")
    title:SetTextColor(1.0, 0.75, 0.35, 1)

    local content = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    content:ClearAllPoints()
    content:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -66)
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 60)
    content:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1
    })
    content:SetBackdropColor(0.09, 0.09, 0.11, 0.95)
    content:SetBackdropBorderColor(0.18, 0.18, 0.2, 1)

    local pageIcon = content:CreateTexture(nil, "ARTWORK")
    pageIcon:SetSize(96, 96)
    pageIcon:SetPoint("TOPRIGHT", content, "TOPRIGHT", -16, -16)
    pageIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local pageTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    pageTitle:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -16)
    pageTitle:SetTextColor(1.0, 0.8, 0.4)

    local iconStripLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    iconStripLabel:SetPoint("TOPLEFT", pageTitle, "BOTTOMLEFT", 0, -2)
    iconStripLabel:SetText("Associated Icons")
    iconStripLabel:SetTextColor(0.7, 0.7, 0.7)

    local iconStrip = CreateFrame("Frame", nil, content)
    iconStrip:SetSize(260, 96)
    iconStrip:SetPoint("TOPLEFT", iconStripLabel, "BOTTOMLEFT", 0, -4)

    local iconFrames = {}
    local ICONS_PER_ROW = 7
    local ICON_STRIP_COUNT = 24
    local ICON_SPACING = 28
    for i = 1, ICON_STRIP_COUNT do
        local f = CreateFrame("Frame", nil, iconStrip)
        f:SetSize(24, 24)
        local col = (i - 1) % ICONS_PER_ROW
        local row = math.floor((i - 1) / ICONS_PER_ROW)
        f:SetPoint("TOPLEFT", col * ICON_SPACING, -row * ICON_SPACING)
        f:EnableMouse(true)

        local glow = f:CreateTexture(nil, "BACKGROUND")
        glow:SetSize(30, 30)
        glow:SetPoint("CENTER")
        glow:SetAtlas("ArtifactsFX-SpinningGlowys")
        glow:SetBlendMode("ADD")
        glow:SetVertexColor(1.0, 0.7, 0.2)

        local icon = f:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("CENTER")

        local anim = glow:CreateAnimationGroup()
        anim:SetLooping("REPEAT")
        local spin = anim:CreateAnimation("Rotation")
        spin:SetDegrees(360)
        spin:SetDuration(4.0)
        spin:SetOrder(1)
        anim:Play()

        f.icon = icon
        f.glow = glow
        f.anim = anim
        f:SetScript("OnEnter", function(self)
            if self.tip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.tip, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        f:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)
        iconFrames[i] = f
    end


    local function GetIntroGlowColor(tex)
        if not tex then
            return 1.0, 0.7, 0.2
        end
        local t = string.lower(tex)
        if string.find(t, "manapotion") then
            return 0.2, 0.3, 0.9
        elseif string.find(t, "weticon") then
            return 0.5, 0.8, 1.0
        elseif string.find(t, "swimmingicon") then
            return 0.4, 0.65, 1.0
        elseif string.find(t, "wanderlusticon") then
            return 1.0, 0.7, 0.2
        elseif string.find(t, "restedicon") then
            return 1.0, 0.7, 0.2
        elseif string.find(t, "indoorsicon") then
            return 1.0, 0.7, 0.2
        elseif string.find(t, "wellfedicon") then
            return 1.0, 0.95, 0.8
        elseif string.find(t, "alcoholicon") then
            return 0.7, 0.3, 1.0
        elseif string.find(t, "bandageicon") or string.find(t, "potionicon") then
            return 0.3, 1.0, 0.4
        elseif string.find(t, "combaticon") then
            return 1.0, 0.2, 0.2
        elseif string.find(t, "dazedicon") then
            return 1.0, 0.4, 0.4
        elseif string.find(t, "constitutionicon") then
            return 1.0, 0.2, 0.2
        elseif string.find(t, "poisonicon") then
            return 0.1, 1.0, 0.2
        elseif string.find(t, "diseaseicon") then
            return 1.0, 0.9, 0.2
        elseif string.find(t, "curseicon") then
            return 0.7, 0.3, 1.0
        elseif string.find(t, "bleedicon") then
            return 1.0, 0.2, 0.2
        end
        return 1.0, 0.7, 0.2
    end
    local pageBody = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pageBody:SetPoint("TOPLEFT", iconStrip, "BOTTOMLEFT", 0, -6)
    pageBody:SetPoint("BOTTOMRIGHT", -16, 16)
    pageBody:SetJustifyH("LEFT")
    pageBody:SetTextColor(0.85, 0.85, 0.85)

    local pageIndicator = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pageIndicator:SetPoint("RIGHT", -60, 0)
    pageIndicator:SetTextColor(0.7, 0.7, 0.7)

    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(30, 30)
    closeBtn:SetPoint("RIGHT", -10, 0)
    local closeText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    closeText:SetPoint("CENTER")
    closeText:SetText("x")
    closeText:SetTextColor(0.5, 0.5, 0.5, 1)
    closeBtn:SetScript("OnEnter", function()
        closeText:SetTextColor(0.9, 0.3, 0.3, 1)
    end)
    closeBtn:SetScript("OnLeave", function()
        closeText:SetTextColor(0.5, 0.5, 0.5, 1)
    end)
    closeBtn:SetScript("OnClick", function()
        frame:Hide()
        if WL.charDB then
            WL.charDB.seenIntroStepper = true
        end
    end)

    local backBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    backBtn:SetSize(110, 30)
    backBtn:SetPoint("BOTTOMLEFT", 14, 12)
    backBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1
    })
    backBtn:SetBackdropColor(0.12, 0.12, 0.14, 1)
    backBtn:SetBackdropBorderColor(0.25, 0.25, 0.28, 1)
    local backText = backBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    backText:SetPoint("CENTER")
    backText:SetText("Back")
    backText:SetTextColor(0.8, 0.8, 0.8)

    local nextBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    nextBtn:SetSize(120, 30)
    nextBtn:SetPoint("BOTTOMRIGHT", -14, 12)
    nextBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1
    })
    nextBtn:SetBackdropColor(0.12, 0.12, 0.14, 1)
    nextBtn:SetBackdropBorderColor(1.0, 0.6, 0.2, 1)
    local nextText = nextBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nextText:SetPoint("CENTER")
    nextText:SetTextColor(1.0, 0.75, 0.35, 1)

    frame.pageIndex = 1

    local function UpdatePage()
        if frame.pageIndex < 1 then
            frame.pageIndex = 1
        elseif frame.pageIndex > #INTRO_PAGES then
            frame.pageIndex = #INTRO_PAGES
        end
        local page = INTRO_PAGES[frame.pageIndex]
        pageTitle:SetText(page.title)
        pageBody:SetText(page.body)
        local mainTexture = page.mainImage or page.icon
        if mainTexture then
            pageIcon:SetTexture(mainTexture)
            if page.uniformMainSize then
                pageIcon:SetSize(72, 112)
            elseif page.mainSize then
                pageIcon:SetSize(page.mainSize[1], page.mainSize[2])
            else
                pageIcon:SetSize(96, 96)
            end
            if page.mainTexCoord then
                pageIcon:SetTexCoord(page.mainTexCoord[1], page.mainTexCoord[2], page.mainTexCoord[3], page.mainTexCoord[4])
            else
                pageIcon:SetTexCoord(0, 1, 0, 1)
            end
            pageIcon:Show()
        else
            pageIcon:Hide()
        end

        local hasIcons = page.icons and #page.icons > 0
        iconStripLabel:SetShown(hasIcons)
        iconStrip:SetShown(hasIcons)

        pageIcon:ClearAllPoints()
        pageTitle:ClearAllPoints()
        if hasIcons then
            pageTitle:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -16)
            if page.mainBelowIcons and iconStrip and mainTexture then
                pageIcon:SetPoint("TOPLEFT", iconStrip, "BOTTOMLEFT", 0, -8)
            elseif mainTexture then
                pageIcon:SetPoint("TOPRIGHT", content, "TOPRIGHT", -16, -16)
            end
        else
            pageTitle:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -16)
            if mainTexture then
                pageIcon:SetPoint("TOPLEFT", pageTitle, "BOTTOMLEFT", 0, -8)
            end
        end

        pageBody:ClearAllPoints()
        if hasIcons then
            if page.mainBelowIcons and mainTexture then
                pageBody:SetPoint("TOPLEFT", pageIcon, "BOTTOMLEFT", 0, -6)
            else
                pageBody:SetPoint("TOPLEFT", iconStrip, "BOTTOMLEFT", 0, -6)
            end
        else
            if mainTexture then
                pageBody:SetPoint("TOPLEFT", pageIcon, "BOTTOMLEFT", 0, -6)
            else
                pageBody:SetPoint("TOPLEFT", pageTitle, "BOTTOMLEFT", 0, -8)
            end
        end
        pageBody:SetPoint("BOTTOMRIGHT", -16, 16)

        if iconFrames then
            for i = 1, ICON_STRIP_COUNT do
                local iconData = page.icons and page.icons[i]
                local frame = iconFrames[i]
                if frame and iconData and iconData.tex then
                    frame.icon:SetTexture(iconData.tex)
                    frame.tip = iconData.tip
                    local r, g, b = GetIntroGlowColor(iconData.tex)
                    frame.glow:SetVertexColor(r, g, b, 1)
                    frame:Show()
                elseif frame then
                    frame.tip = nil
                    frame:Hide()
                end
            end
        end
        pageIndicator:SetText(string.format("%d / %d", frame.pageIndex, #INTRO_PAGES))
        backBtn:SetEnabled(frame.pageIndex > 1)
        backText:SetTextColor(frame.pageIndex > 1 and 0.8 or 0.4, frame.pageIndex > 1 and 0.8 or 0.4,
            frame.pageIndex > 1 and 0.8 or 0.4)
        if frame.pageIndex == #INTRO_PAGES then
            nextText:SetText("Finish")
        else
            nextText:SetText("Next")
        end
    end
    backBtn:SetScript("OnClick", function()
        if frame.pageIndex > 1 then
            frame.pageIndex = frame.pageIndex - 1
            UpdatePage()
        end
    end)
    nextBtn:SetScript("OnClick", function()
        if frame.pageIndex >= #INTRO_PAGES then
            frame:Hide()
            if WL.charDB then
                WL.charDB.seenIntroStepper = true
            end
            return
        end
        frame.pageIndex = frame.pageIndex + 1
        UpdatePage()
    end)

    frame.UpdatePage = UpdatePage
    frame:Hide()
    introStepper = frame
    return frame
end

function WL.ShowIntroStepper(force)
    if not force and WL.charDB and WL.charDB.seenIntroStepper then
        return
    end
    local frame = CreateIntroStepper()
    frame.pageIndex = 1
    frame:Show()
    frame:Raise()
    frame.UpdatePage()
end

local function ShowLevelRequirementInfo()
    local playerLevel = UnitLevel("player")
    if playerLevel >= MIN_LEVEL then
        return
    end

    print("|cff88CCFFWanderlust:|r Survival systems will activate at |cffffd700Level " .. MIN_LEVEL ..
              "|r. (Currently Level " .. playerLevel .. ")")

    if WL.charDB and not WL.charDB.seenLevelPopup then
        if not levelPopup then
            levelPopup = CreateLevelRequirementPopup()
        end
        levelPopup:Show()
    end
end

local function OnLevelUp(newLevel)
    if newLevel == MIN_LEVEL then
        WL.ShowIntroStepper(false)
    end
end


----------------------------------------------------------------
-- AddOn Compartment integration (Midnight / Retail)
-- This MUST be independent of the minimap button visibility.
----------------------------------------------------------------
local function WL_RegisterAddonCompartmentEntry()
    if WL._compartmentRegistered then return end

    if AddonCompartmentFrame and AddonCompartmentFrame.RegisterAddon then
        -- Use long bracket strings to avoid accidental backslash-escape issues in Lua.
        local base = WL.ASSET_PATH or [[Interface\AddOns\Wanderlust\assets\]]
        local icon = base .. "fireicon" -- texture file extension optional

        local ok = pcall(function()
            AddonCompartmentFrame:RegisterAddon({
                text = WL.name or "Wanderlust",
                icon = icon,
                notCheckable = true,
                func = function()
                    -- Open settings without depending on minimap button.
                    if WL.OpenSettings then
                        WL.OpenSettings(false)
                    elseif WL.ToggleSettings then
                        WL.ToggleSettings(true)
                    elseif WL.ToggleDebugPanel then
                        WL.ToggleDebugPanel()
                    else
                        print("|cff88CCFFWanderlust:|r Settings UI not available.")
                    end
                end,
            })
        end)

        WL._compartmentRegistered = ok or false
    end
end


local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("PLAYER_LOGOUT")
initFrame:RegisterEvent("PLAYER_LEVEL_UP")

initFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == (addonName or "Wanderlust") then
        InitializeSavedVariables()
    elseif event == "PLAYER_LOGIN" then
        RefreshEligibility()
        print("|cff88CCFFWanderlust|r v" .. WL.version .. " loaded. Type |cffffff00/wander|r for commands.")
        CheckUHCConflict()
        C_Timer.After(2, ShowLevelRequirementInfo)
        WL.FireCallbacks("PLAYER_LOGIN")
        WL_RegisterAddonCompartmentEntry()
    elseif event == "PLAYER_LOGOUT" then
        WL.FireCallbacks("PLAYER_LOGOUT")
    elseif event == "PLAYER_LEVEL_UP" then
        local newLevel = arg1
        RefreshEligibility(newLevel)
        OnLevelUp(newLevel)
    end
end)

WL.RegisterCallback("SETTINGS_CHANGED", function(key)
    if key == "enabled" or key == "ALL" then
        RefreshEligibility()
    end
end)

SLASH_WANDERLUST1 = "/wander"
SLASH_WANDERLUST2 = "/wanderlust"
SLASH_REST1 = "/rest"

SlashCmdList["REST"] = function(msg)
    if WL.GetSetting("fireDetectionMode") == 2 then
        WL.ActivateManualRest()
    else
        print("|cff88CCFFWanderlust:|r /rest only works in Manual Rest Mode. Change mode in settings.")
    end
end

SlashCmdList["WANDERLUST"] = function(msg)
    msg = string.lower(msg or "")
    local command, value = msg:match("([^%s]+)%s*(.*)")
    command = command or ""

    if command == "" then
        if WL.OpenSettings then
            WL.OpenSettings(false)
        else
            print("|cff88CCFFWanderlust:|r Settings UI not available.")
        end
        return
    elseif command == "status" or command == "s" then
        local s = WL.GetStatus()
        local inDungeon = WL.IsInDungeon and WL.IsInDungeon() or false
        local isResting = IsResting()
        local nearFireRaw = WL.isNearFireRaw or false
        local onTaxi = UnitOnTaxi("player")
        local modeNames = {"Auto Detect", "Manual Rest"}

        print("|cff88CCFFWanderlust Status:|r")
        print("  Level: " .. s.playerLevel .. " (min " .. s.minLevel .. ")")
        print("  Detection Mode: |cffFFCC00" .. (modeNames[s.fireDetectionMode] or "Unknown") .. "|r")
        print("  Near Fire: " .. (nearFireRaw and "|cff00FF00YES|r" or "|cffFF0000NO|r"))
        if s.fireDetectionMode == 2 then
            print("  Manual Rest: " .. (s.isManualRestActive and "|cff00FF00ACTIVE|r" or "|cff888888INACTIVE|r"))
        end
        print("  Resting: " .. (isResting and "|cff00FF00YES|r" or "|cff888888NO|r"))
        print("  On Flight: " .. (onTaxi and "|cff00FF00YES|r" or "|cff888888NO|r"))
        print("  In Combat: " .. (s.inCombat and "|cffFF8800YES|r" or "|cff888888NO|r"))
        print("  In Dungeon: " .. (inDungeon and "|cffFFAA00YES|r" or "|cff888888NO|r"))
        print("  Indoors: " .. (IsIndoors() and "|cff00FF00YES|r" or "|cff888888NO|r"))

        if not s.hideActionBars then
            print("  Action Bars: |cff888888ALWAYS SHOWN|r")
        else
            print("  Action Bars: " .. (s.shouldShowBars and "|cff00FF00SHOWN|r" or "|cffFF0000HIDDEN|r"))
        end

        if not s.blockMap then
            print("  Map: |cff888888ALWAYS ALLOWED|r")
        else
            print("  Map: " .. (s.canUseMap and "|cff00FF00ALLOWED|r" or "|cffFF0000BLOCKED|r"))
        end

        if not s.exhaustionEnabled then
            print("  Exhaustion: |cff888888DISABLED|r")
        elseif inDungeon then
            print("  Exhaustion: |cffFFAA00PAUSED|r (" .. string.format("%.1f%%", s.exhaustion) .. ")")
        else
            local canDecay = (isResting or s.isNearFire) and not s.inCombat
            local decayStatus = canDecay and " |cff00FF00(recovering)|r" or ""
            print("  Exhaustion: " .. string.format("%.1f%%", s.exhaustion) .. decayStatus)
        end

        if not s.AnguishEnabled then
            print("  Anguish: |cff888888DISABLED|r")
        elseif inDungeon then
            print("  Anguish: |cffFFAA00PAUSED|r (" .. string.format("%.1f%%", s.Anguish) .. ")")
        else
            print("  Anguish: " .. string.format("%.1f%%", s.Anguish))
        end

        if not s.temperatureEnabled then
            print("  Temperature: |cff888888DISABLED|r")
        elseif inDungeon then
            print("  Temperature: |cffFFAA00PAUSED|r (" .. string.format("%.0f", s.temperature) .. ")")
        else
            local tempColor = "|cff888888"
            local tempStatus = "Neutral"
            if s.temperature < -50 then
                tempColor = "|cff3366FF"
                tempStatus = "Freezing"
            elseif s.temperature < -20 then
                tempColor = "|cff5588FF"
                tempStatus = "Cold"
            elseif s.temperature < -5 then
                tempColor = "|cff77AAFF"
                tempStatus = "Chilly"
            elseif s.temperature > 50 then
                tempColor = "|cffFF6622"
                tempStatus = "Scorching"
            elseif s.temperature > 20 then
                tempColor = "|cffFF9933"
                tempStatus = "Hot"
            elseif s.temperature > 5 then
                tempColor = "|cffFFCC55"
                tempStatus = "Warm"
            end
            local isRecovering = WL.IsTemperatureRecovering and WL.IsTemperatureRecovering()
            local recStatus = isRecovering and " |cff00FF00(recovering)|r" or ""
            print(
                "  Temperature: " .. tempColor .. string.format("%.0f", s.temperature) .. " (" .. tempStatus .. ")|r" ..
                    recStatus)
        end

    elseif command == "debug" or command == "debugpanel" or command == "dp" or command == "sliders" then
        if WL.ToggleSettings then
            WL.ToggleSettings(true)
        else
            print("|cff88CCFFWanderlust:|r Settings UI not available.")
        end
        return
    elseif command == "proximity" then
        local current = WL.GetSetting("proximityDebugEnabled")
        WL.SetSetting("proximityDebugEnabled", not current)
        print("|cff88CCFFWanderlust:|r Proximity debug " .. (not current and "|cff00FF00ON|r" or "|cffFF0000OFF|r"))

    elseif command == "exhaustion" then
        local current = WL.GetSetting("exhaustionDebugEnabled")
        WL.SetSetting("exhaustionDebugEnabled", not current)
        print("|cff88CCFFWanderlust:|r Exhaustion debug " .. (not current and "|cff00FF00ON|r" or "|cffFF0000OFF|r"))

    elseif command == "Anguish" then
        local current = WL.GetSetting("AnguishDebugEnabled")
        WL.SetSetting("AnguishDebugEnabled", not current)
        print("|cff88CCFFWanderlust:|r Anguish debug " .. (not current and "|cff00FF00ON|r" or "|cffFF0000OFF|r"))

    elseif command == "temperature" or command == "temp" then
        local current = WL.GetSetting("temperatureDebugEnabled")
        WL.SetSetting("temperatureDebugEnabled", not current)
        print("|cff88CCFFWanderlust:|r Temperature debug " .. (not current and "|cff00FF00ON|r" or "|cffFF0000OFF|r"))

    elseif command == "debugpanel" or command == "dp" or command == "sliders" then
        if WL.ToggleSettings then
            WL.ToggleSettings(true)
        else
            print("|cff88CCFFWanderlust:|r Settings UI not available.")
        end
        return

    elseif command == "intro" then
        if WL.ShowIntroStepper then
            WL.ShowIntroStepper(true)
        end
        return

    elseif command == "mode" or command == "displaymode" then
        local currentMode = WL.GetSetting("meterDisplayMode")
        local newMode = currentMode == "bar" and "vial" or "bar"
        WL.SetSetting("meterDisplayMode", newMode)
        print("|cff88CCFFWanderlust:|r Meter display mode set to |cffFFD700" .. newMode .. "|r")
        print("|cff88CCFFWanderlust:|r |cffFFFF00/reload required to apply changes|r")

    elseif command == "bar" then
        WL.SetSetting("meterDisplayMode", "bar")
        print("|cff88CCFFWanderlust:|r Meter display mode set to |cffFFD700bar|r")
        print("|cff88CCFFWanderlust:|r |cffFFFF00/reload required to apply changes|r")

    elseif command == "vial" then
        WL.SetSetting("meterDisplayMode", "vial")
        print("|cff88CCFFWanderlust:|r Meter display mode set to |cffFFD700vial|r")
        print("|cff88CCFFWanderlust:|r |cffFFFF00/reload required to apply changes|r")

    elseif command == "config" or command == "options" or command == "settings" then
        if WL.ToggleSettings then
            WL.ToggleSettings(false)
        end

    elseif command == "help" or command == "?" or command == "" then
        print("|cff88CCFF=== Wanderlust v" .. WL.version .. " ===|r")
        print("|cffffff00/wander|r or |cffffff00/wanderlust|r - Open config page")
        print("|cffffff00/rest|r - Activate rest (Manual Rest Mode only)")
        print("|cffffff00/logfire [desc]|r - Log fire at current position")

    else
        print("|cff88CCFFWanderlust:|r Unknown command. Use |cffffff00/wander|r for help.")
    end
end

CookingRangeCheck = Wanderlust
