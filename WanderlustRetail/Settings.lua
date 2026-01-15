-- Wanderlust - settings UI
local WL = Wanderlust
local settingsFrame = nil
local controls = {}
local currentTab = "general"
local tabFrames = {}
local tabButtons = {}

local COLORS = {
    bg = {0.06, 0.06, 0.08, 0.97},
    headerBg = {0.08, 0.08, 0.10, 1},
    accent = {1.0, 0.6, 0.2, 1},
    accentDark = {0.8, 0.45, 0.1, 1},
    accentGlow = {1.0, 0.7, 0.3, 0.3},
    text = {0.9, 0.9, 0.9, 1},
    textDim = {0.55, 0.55, 0.55, 1},
    success = {0.4, 0.9, 0.4, 1},
    warning = {1.0, 0.8, 0.2, 1},
    danger = {0.9, 0.3, 0.3, 1},
    cardBg = {0.09, 0.09, 0.11, 0.95},
    cardBorder = {0.18, 0.18, 0.2, 1},
    sliderBg = {0.12, 0.12, 0.14, 1},
    sliderFill = {1.0, 0.6, 0.2, 0.9},
    ember = {1.0, 0.4, 0.1, 1},
    Anguish = {0.9, 0.3, 0.3, 1},
    tabInactive = {0.1, 0.1, 0.12, 1},
    tabActive = {0.15, 0.15, 0.18, 1}
}

local UpdatePresetButtonVisuals

local function RefreshControls()
    for setting, ctrl in pairs(controls) do
        if ctrl.checkbox then
            ctrl.checkbox:SetChecked(WL.GetSetting(setting))
        end
        if ctrl.update then
            ctrl.update()
        end
    end
end

local function SetDebugVisible(showDebug)
    if showDebug then
        if WL.ShowDebugPanel then
            WL.ShowDebugPanel(settingsFrame)
        end
    else
        if WL.HideDebugPanel then
            WL.HideDebugPanel()
        end
    end
end

local function CreateModernCheckbox(parent, label, tooltip, setting, yOffset)
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetSize(340, 28)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset)
    container:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1
    })
    container:SetBackdropColor(0.09, 0.09, 0.11, 0.95)
    container:SetBackdropBorderColor(0.18, 0.18, 0.2, 1)

    local cb = CreateFrame("CheckButton", nil, container)
    cb:SetSize(20, 20)
    cb:SetPoint("LEFT", 4, 0)

    local cbBg = cb:CreateTexture(nil, "BACKGROUND")
    cbBg:SetAllPoints()
    cbBg:SetColorTexture(0.15, 0.15, 0.2, 1)

    local cbBorder = cb:CreateTexture(nil, "BORDER")
    cbBorder:SetPoint("TOPLEFT", -1, 1)
    cbBorder:SetPoint("BOTTOMRIGHT", 1, -1)
    cbBorder:SetColorTexture(0.3, 0.3, 0.35, 1)
    cbBorder:SetDrawLayer("BORDER", -1)

    local check = cb:CreateTexture(nil, "ARTWORK")
    check:SetSize(14, 14)
    check:SetPoint("CENTER")
    check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    check:SetDesaturated(true)
    check:SetVertexColor(unpack(COLORS.accent))
    cb.check = check

    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", cb, "RIGHT", 10, 0)
    text:SetText(label)
    text:SetTextColor(unpack(COLORS.text))

    local function UpdateVisual()
        if cb:GetChecked() then
            check:Show()
            cbBg:SetColorTexture(0.2, 0.35, 0.5, 1)
        else
            check:Hide()
            cbBg:SetColorTexture(0.15, 0.15, 0.2, 1)
        end
        UpdatePresetButtonVisuals()
    end

    cb:SetChecked(WL.GetSetting(setting))
    cb.setting = setting
    cb.isManuallyDisabled = false
    UpdateVisual()

    cb:SetScript("OnClick", function(self)
        if self.isManuallyDisabled then
            self:SetChecked(not self:GetChecked())
            return
        end
        WL.SetSetting(setting, self:GetChecked())
        UpdateVisual()
    end)

    local disabledTooltip = nil
    function cb:SetDisabledTooltip(text)
        disabledTooltip = text
    end
    cb:SetScript("OnEnter", function(self)
        if self.isManuallyDisabled and disabledTooltip then
            cbBorder:SetColorTexture(unpack(COLORS.danger))
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label .. " |cffFF6666(Disabled)|r", 1, 0.3, 0.3)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Why is this disabled?", 1, 0.8, 0.4)
            GameTooltip:AddLine(disabledTooltip, 1, 1, 1, true)
            GameTooltip:Show()
        else
            cbBorder:SetColorTexture(unpack(COLORS.accent))
            if tooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(label, 1, 1, 1)
                GameTooltip:AddLine(tooltip, unpack(COLORS.textDim))
                GameTooltip:Show()
            end
        end
    end)
    cb:SetScript("OnLeave", function(self)
        cbBorder:SetColorTexture(0.3, 0.3, 0.35, 1)
        GameTooltip:Hide()
    end)

    controls[setting] = {
        checkbox = cb,
        label = text,
        update = UpdateVisual
    }
    return container, -32
end

local function CreateModernSlider(parent, label, tooltip, setting, minVal, maxVal, step, yOffset, fmt)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(340, 50)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset)

    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("TOPLEFT", 0, 0)
    text:SetText(label)
    text:SetTextColor(unpack(COLORS.text))

    fmt = fmt or function(v)
        return string.format("%.1f", v)
    end
    local valText = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    valText:SetPoint("TOPRIGHT", 0, 0)
    valText:SetTextColor(unpack(COLORS.accent))

    local trackBg = container:CreateTexture(nil, "BACKGROUND")
    trackBg:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -8)
    trackBg:SetSize(280, 6)
    trackBg:SetColorTexture(unpack(COLORS.sliderBg))

    local trackFill = container:CreateTexture(nil, "BORDER")
    trackFill:SetPoint("TOPLEFT", trackBg, "TOPLEFT")
    trackFill:SetHeight(6)
    trackFill:SetColorTexture(unpack(COLORS.sliderFill))

    local sliderName = "WanderlustSlider" .. setting
    local slider = CreateFrame("Slider", sliderName, container, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", trackBg, "TOPLEFT", 0, 3)
    slider:SetSize(280, 12)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    local thumbTex = slider:GetThumbTexture()
    if thumbTex then
        thumbTex:SetTexture(nil)
    end

    local lowText = _G[sliderName .. "Low"]
    local highText = _G[sliderName .. "High"]
    local sliderText = _G[sliderName .. "Text"]
    if lowText then
        lowText:Hide()
    end
    if highText then
        highText:Hide()
    end
    if sliderText then
        sliderText:Hide()
    end

    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(16, 16)
    thumb:SetPoint("CENTER", slider:GetThumbTexture(), "CENTER")
    thumb:SetColorTexture(1, 1, 1, 1)
    slider.customThumb = thumb

    local function UpdateSlider(value)
        local pct = (value - minVal) / (maxVal - minVal)
        trackFill:SetWidth(math.max(1, 280 * pct))
        valText:SetText(fmt(value))
    end

    local currentVal = WL.GetSetting(setting) or minVal
    slider:SetValue(currentVal)
    UpdateSlider(currentVal)

    slider:SetScript("OnValueChanged", function(self, value)
        WL.SetSetting(setting, value)
        UpdateSlider(value)
    end)

    slider:SetScript("OnEnter", function(self)
        thumb:SetColorTexture(unpack(COLORS.accent))
        if tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tooltip, unpack(COLORS.textDim))
            GameTooltip:Show()
        end
    end)
    slider:SetScript("OnLeave", function(self)
        thumb:SetColorTexture(1, 1, 1, 1)
        GameTooltip:Hide()
    end)

    controls[setting] = {
        update = function()
            local newVal = WL.GetSetting(setting) or minVal
            slider:SetValue(newVal)
            UpdateSlider(newVal)
        end
    }

    return container, -55
end

local function CreateModernDropdown(parent, label, tooltip, setting, options, yOffset, optionTooltips, values)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(340, 55)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset)

    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("TOPLEFT", 0, 0)
    text:SetText(label)
    text:SetTextColor(unpack(COLORS.text))

    local btn = CreateFrame("Button", nil, container, "BackdropTemplate")
    btn:SetSize(200, 28)
    btn:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -5)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1
    })
    btn:SetBackdropColor(0.1, 0.1, 0.12, 1)
    btn:SetBackdropBorderColor(0.25, 0.25, 0.28, 1)

    local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btnText:SetPoint("LEFT", 10, 0)
    btnText:SetTextColor(unpack(COLORS.text))

    local arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    arrow:SetPoint("RIGHT", -10, 0)
    arrow:SetText("v")
    arrow:SetTextColor(unpack(COLORS.accent))

    local menu = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    menu:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
    menu:SetSize(200, #options * 26 + 6)
    menu:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1
    })
    menu:SetBackdropColor(0.08, 0.08, 0.1, 0.98)
    menu:SetBackdropBorderColor(0.25, 0.25, 0.28, 1)
    menu:SetFrameStrata("TOOLTIP")
    menu:Hide()

    for i, opt in ipairs(options) do
        local item = CreateFrame("Button", nil, menu)
        item:SetSize(194, 24)
        item:SetPoint("TOPLEFT", 3, -3 - (i - 1) * 26)

        local itemBg = item:CreateTexture(nil, "BACKGROUND")
        itemBg:SetAllPoints()
        itemBg:SetColorTexture(0, 0, 0, 0)
        item.bg = itemBg

        local itemText = item:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        itemText:SetPoint("LEFT", 8, 0)
        itemText:SetText(opt)
        itemText:SetTextColor(unpack(COLORS.text))

        item:SetScript("OnEnter", function(self)
            itemBg:SetColorTexture(1.0, 0.6, 0.2, 0.3)
            if optionTooltips and optionTooltips[i] then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(opt, 1, 1, 1)
                GameTooltip:AddLine(optionTooltips[i], unpack(COLORS.textDim))
                GameTooltip:Show()
            end
        end)
        item:SetScript("OnLeave", function(self)
            itemBg:SetColorTexture(0, 0, 0, 0)
            GameTooltip:Hide()
        end)
        item:SetScript("OnClick", function()
            local valueToSet = values and values[i] or i
            WL.SetSetting(setting, valueToSet)
            btnText:SetText(opt)
            menu:Hide()
        end)
    end

    local function UpdateDropdown()
        local val = WL.GetSetting(setting) or (values and values[1] or 1)
        if values then
            for i, v in ipairs(values) do
                if v == val then
                    btnText:SetText(options[i] or options[1])
                    return
                end
            end
        end
        btnText:SetText(options[val] or options[1])
    end
    UpdateDropdown()

    btn:SetScript("OnClick", function()
        if menu:IsShown() then
            menu:Hide()
        else
            menu:Show()
        end
    end)
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(COLORS.accent))
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.25, 0.25, 0.28, 1)
    end)

    menu:SetScript("OnShow", function(self)
        self:SetFrameLevel(parent:GetFrameLevel() + 100)
    end)

    controls[setting] = {
        update = UpdateDropdown
    }
    return container, -60
end

local function CreateSectionHeader(parent, text, yOffset, color)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(360, 30)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)

    local accent = container:CreateTexture(nil, "ARTWORK")
    accent:SetSize(4, 20)
    accent:SetPoint("LEFT", 0, 0)
    accent:SetColorTexture(unpack(color or COLORS.accent))

    local header = container:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("LEFT", accent, "RIGHT", 10, 0)
    header:SetText(text)
    header:SetTextColor(unpack(COLORS.text))

    return container, -35
end

local PRESETS = {
    survival = {
        name = "Survival",
        description = "Full survival experience with all meters and restrictions.",
        settings = {
            enabled = true,
            exhaustionEnabled = true,
            AnguishEnabled = true,
            hungerEnabled = true,
            thirstEnabled = true,
            temperatureEnabled = true,
            anguishOverlayEnabled = true,
            exhaustionOverlayEnabled = true,
            hungerOverlayEnabled = true,
            thirstOverlayEnabled = true,
            temperatureOverlayEnabled = true,
            constitutionEnabled = true,
            hideUIAtLowConstitution = true,
            lingeringEffectsEnabled = true,
            hideActionBarsMode = 2,
            blockMap = true,
            blockMapWithConstitution = true,
            blockBagsWithConstitution = true,
            showSurvivalIcons = true,
            hideUIInInstances = false,
            innkeeperHealsAnguish = true,
            meterDisplayMode = "vial",
            hpTunnelVisionEnabled = true
        }
    },
    cozy = {
        name = "Cozy",
        description = "Relaxed experience - temperature and exhaustion only, no restrictions.",
        settings = {
            enabled = true,
            exhaustionEnabled = true,
            AnguishEnabled = false,
            hungerEnabled = false,
            thirstEnabled = false,
            temperatureEnabled = true,
            anguishOverlayEnabled = true,
            exhaustionOverlayEnabled = true,
            hungerOverlayEnabled = true,
            thirstOverlayEnabled = true,
            temperatureOverlayEnabled = true,
            constitutionEnabled = false,
            hideUIAtLowConstitution = false,
            lingeringEffectsEnabled = false,
            hideActionBarsMode = 1,
            blockMap = false,
            blockMapWithConstitution = false,
            blockBagsWithConstitution = false,
            showSurvivalIcons = true,
            hideUIInInstances = false,
            innkeeperHealsAnguish = false,
            hpTunnelVisionEnabled = false
        }
    }
}

local currentPreset = WL.GetSetting and WL.GetSetting("selectedPreset") or "survival"

local function ApplyPreset(presetKey)
    local preset = PRESETS[presetKey]
    if not preset then
        return
    end

    for setting, value in pairs(preset.settings) do
        WL.SetSetting(setting, value)
    end

    currentPreset = presetKey
    if WL.SetSetting then
        WL.SetSetting("selectedPreset", presetKey)
    end
    if WL.FireCallbacks then
        WL.FireCallbacks("SETTINGS_CHANGED", "ALL", nil)
    end

    for setting, ctrl in pairs(controls) do
        if ctrl.checkbox then
            ctrl.checkbox:SetChecked(WL.GetSetting(setting))
        end
        if ctrl.update then
            ctrl.update()
        end
    end

    UpdatePresetButtonVisuals()
    print("|cff88CCFFWanderlust:|r Applied preset: " .. preset.name)
end

local presetButtons = {}

local function CreatePresetButton(parent, presetKey, xOffset, yOffset)
    local preset = PRESETS[presetKey]

    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(150, 50)
    btn:SetPoint("TOPLEFT", xOffset, yOffset)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 2
    })
    btn:SetBackdropColor(0.12, 0.12, 0.14, 1)
    btn:SetBackdropBorderColor(0.25, 0.25, 0.28, 1)

    local btnTitle = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btnTitle:SetPoint("TOP", 0, -8)
    btnTitle:SetText(preset.name)
    btnTitle:SetTextColor(unpack(COLORS.accent))

    local btnDesc = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btnDesc:SetPoint("TOP", btnTitle, "BOTTOM", 0, -4)
    btnDesc:SetText(presetKey == "survival" and "All Features" or "Temperature & Exhaustion")
    btnDesc:SetTextColor(unpack(COLORS.textDim))

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(COLORS.accent))
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(preset.name .. " Preset", 1, 1, 1)
        GameTooltip:AddLine(preset.description, unpack(COLORS.textDim))
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        UpdatePresetButtonVisuals()
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", function()
        ApplyPreset(presetKey)
    end)

    presetButtons[presetKey] = btn
    return btn
end

local function IsPresetActive(presetKey)
    local preset = PRESETS[presetKey]
    if not preset then
        return false
    end
    for setting, value in pairs(preset.settings) do
        if WL.GetSetting(setting) ~= value then
            return false
        end
    end
    return true
end

UpdatePresetButtonVisuals = function()
    local active = WL.GetSetting and WL.GetSetting("selectedPreset") or nil
    if active ~= "survival" and active ~= "cozy" then
        if IsPresetActive("survival") then
            active = "survival"
        elseif IsPresetActive("cozy") then
            active = "cozy"
        else
            active = "survival"
        end
    end

    for key, btn in pairs(presetButtons) do
        if key == active then
            btn:SetBackdropBorderColor(unpack(COLORS.accent))
        else
            btn:SetBackdropBorderColor(0.25, 0.25, 0.28, 1)
        end
    end
end

local function CreateTabButton(parent, tabKey, label, xOffset)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(90, 28)
    btn:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", xOffset, 0)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8"
    })

    local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btnText:SetPoint("CENTER", 0, 0)
    btnText:SetText(label)
    btn.text = btnText
    btn.tabKey = tabKey

    local function UpdateTabVisual()
        if currentTab == tabKey then
            btn:SetBackdropColor(unpack(COLORS.tabActive))
            btnText:SetTextColor(unpack(COLORS.accent))
        else
            btn:SetBackdropColor(unpack(COLORS.tabInactive))
            btnText:SetTextColor(unpack(COLORS.textDim))
        end
    end
    btn.UpdateVisual = UpdateTabVisual
    UpdateTabVisual()

    btn:SetScript("OnClick", function()
        currentTab = tabKey
        for _, tb in pairs(tabButtons) do
            tb:UpdateVisual()
        end
        for key, frame in pairs(tabFrames) do
            if key == tabKey then
                frame:Show()
            else
                frame:Hide()
            end
        end
    end)
    btn:SetScript("OnEnter", function(self)
        if currentTab ~= tabKey then
            btnText:SetTextColor(unpack(COLORS.text))
        end
    end)
    btn:SetScript("OnLeave", function(self)
        UpdateTabVisual()
    end)

    tabButtons[tabKey] = btn
    return btn
end

local function CreateGeneralTab(parent)
    local content = CreateFrame("Frame", nil, parent)
    content:SetAllPoints()

    local y = -10
    local _, o

    _, o = CreateSectionHeader(content, "Quick Presets", y)
    y = y + o

    local presetDesc = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    presetDesc:SetPoint("TOPLEFT", 30, y)
    presetDesc:SetText("Choose a preset to quickly configure Wanderlust:")
    presetDesc:SetTextColor(unpack(COLORS.textDim))
    y = y - 25

    CreatePresetButton(content, "cozy", 30, y)
    CreatePresetButton(content, "survival", 190, y)
    UpdatePresetButtonVisuals()
    y = y - 60

    local tutorialBtn = CreateFrame("Button", nil, content, "BackdropTemplate")
    tutorialBtn:SetSize(320, 28)
    tutorialBtn:SetPoint("TOPLEFT", 30, y)
    tutorialBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1
    })
    tutorialBtn:SetBackdropColor(0.12, 0.12, 0.14, 1)
    tutorialBtn:SetBackdropBorderColor(0.25, 0.25, 0.28, 1)

    local tutorialText = tutorialBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tutorialText:SetPoint("CENTER")
    tutorialText:SetText("Show Tutorial")
    tutorialText:SetTextColor(unpack(COLORS.text))

    tutorialBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(COLORS.accent))
        tutorialText:SetTextColor(1, 1, 1, 1)
    end)
    tutorialBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.25, 0.25, 0.28, 1)
        tutorialText:SetTextColor(unpack(COLORS.text))
    end)
    tutorialBtn:SetScript("OnClick", function()
        if WL.ShowIntroStepper then
            WL.ShowIntroStepper(true)
        end
    end)
    y = y - 40

    _, o = CreateSectionHeader(content, "Core Settings", y)
    y = y + o

    _, o = CreateModernCheckbox(content, "Enable Wanderlust", "Master toggle for all Wanderlust features.", "enabled", y)
    y = y + o

    _, o = CreateModernCheckbox(content, "Pause in Instances", "Pause Wanderlust systems inside dungeons and raids.", "pauseInInstances", y)
    y = y + o

    local hideInstancesContainer
    hideInstancesContainer, o = CreateModernCheckbox(content, "Hide UI in Dungeons",
        "Hide Wanderlust meters while paused in dungeons and raids.", "hideUIInInstances", y)
    y = y + o

    local function UpdateInstanceHideControl()
        local pauseEnabled = WL.GetSetting and WL.GetSetting("pauseInInstances")
        local control = controls.hideUIInInstances
        if control and control.checkbox then
            control.checkbox.isManuallyDisabled = not pauseEnabled
            control.checkbox:SetDisabledTooltip("Enable 'Pause in Instances' to use this option.")
            control.update()
            if hideInstancesContainer then
                hideInstancesContainer:SetAlpha(pauseEnabled and 1 or 0.4)
            end
        end
    end
    UpdateInstanceHideControl()
    WL.RegisterCallback("SETTINGS_CHANGED", function(key)
        if key == "pauseInInstances" or key == "ALL" then
            UpdateInstanceHideControl()
        end
    end)

    _, o = CreateModernCheckbox(content, "Lock Meters", "Prevent meters from being moved by dragging.", "metersLocked",
        y)
    y = y + o

    _, o = CreateModernCheckbox(content, "Show Minimap Button",
        "Show or hide the Wanderlust minimap button. (You can still open settings from the AddOn Compartment menu.)",
        "showMinimapButton", y)
    y = y + o

    _, o = CreateModernCheckbox(content, "HP Tunnel Vision",
        "Adds a gradual tunnel vision effect as HP decreases. The effect intensifies at 80%, 60%, 40%, and 20% HP thresholds.",
        "hpTunnelVisionEnabled", y)
    y = y + o
    y = y - 10

    _, o = CreateSectionHeader(content, "Meter Appearance", y)
    y = y + o

    _, o = CreateModernDropdown(content, "Display Mode", "Choose between horizontal bars or potion vial style.",
        "meterDisplayMode", {"Bar", "Vial"}, y, {"Traditional horizontal progress bars.",
                                                 "Potion bottle style with vertical fill."}, {"bar", "vial"})
    y = y + o
    _, o = CreateModernSlider(content, "Meter Scale", "Scale all meters up or down (50% to 150%).", "meterScale", 0.5,
        1.5, 0.05, y, function(v)
            return string.format("%.0f%%", v * 100)
        end)
    y = y + o
    _, o = CreateModernDropdown(content, "Tooltip Display", "How much information to show in meter tooltips.",
        "tooltipDisplayMode", {"Detailed", "Minimal", "Disabled"}, y,
        {"Full explanations with recovery methods, checkpoints, and pause conditions.",
         "Just current values, trends, and active effects. No how-to information.",
         "No tooltips shown when hovering over meters."}, {"detailed", "minimal", "disabled"})
    y = y + o

    local textureNames = {"Blizzard", "Blizzard Raid", "Smooth", "Flat", "Gloss", "Minimalist", "Otravi", "Striped",
                          "Solid"}
    _, o = CreateModernDropdown(content, "Bar Texture", "Visual style for the meter bars.", "meterBarTexture",
        textureNames, y)
    y = y + o
    local fontNames = {"Default", "Friz Quadrata", "Arial Narrow", "Skurri", "Morpheus", "2002", "2002 Bold",
                       "Express Way", "Nimrod MT"}
    _, o = CreateModernDropdown(content, "General Font", "Font for all addon text. 'Default' inherits from UI.",
        "generalFont", fontNames, y)
    y = y + o
    _, o = CreateModernCheckbox(content, "Hide Vial Text", "Hide the percentage numbers on potion vials.",
        "hideVialText", y)
    y = y + o

    return content
end

local function CreateFireTab(parent)
    local content = CreateFrame("Frame", nil, parent)
    content:SetAllPoints()

    local y = -10
    local _, o

    _, o = CreateSectionHeader(content, "Fire Detection", y)
    y = y + o
    _, o = CreateModernDropdown(content, "Detection Mode", "How fire proximity is detected", "fireDetectionMode",
        {"Auto Detect", "Manual Rest Mode"}, y, {"Automatically detect nearby campfires.",
                                                 "Use /rest command to activate. More performance-friendly."})
    y = y + o
    _, o = CreateModernCheckbox(content, "Detect Player Campfires", "Count Basic Campfire spell as a rest point.",
        "detectPlayerCampfires", y)
    y = y + o
    _, o = CreateModernSlider(content, "Detection Range", "How close to be considered 'near fire'.", "campfireRange", 2,
        4, 1, y, function(v)
            return v .. " yards"
        end)
    y = y + o
    y = y - 10

    _, o = CreateSectionHeader(content, "Fire Restrictions", y)
    y = y + o
    _, o = CreateModernDropdown(content, "Show Action Bars", "When action bars are visible (requires level 6+)",
        "hideActionBarsMode", {"Always Visible", "Near Fire or Rested", "Rested Areas Only"}, y,
        {"Action bars always visible (restriction disabled).", "Show near campfires, in inns/cities, on taxi, or dead.",
         "Show only in rested areas (inns/cities)."})
    y = y + o
    _, o = CreateModernCheckbox(content, "Block Map Access",
        "Prevent opening the map when not rested or near a campfire. Requires level 6+. Constitution override (50%) will still block it.",
        "blockMap", y)
    y = y + o
    _, o = CreateModernCheckbox(content, "Hide Minimap with Action Bars",
        "Also fade the minimap when action bars are hidden. Constitution override (25%) will still hide it.",
        "hideMinimapWithBars", y)
    y = y + o
    _, o = CreateModernCheckbox(content, "Show Survival Icons on Map",
        "Display campfire icons on the world map in the current zone.",
        "showSurvivalIcons", y)
    y = y + o

    return content
end

local function CreateSurvivalTab(parent)
    local content = CreateFrame("Frame", nil, parent)
    content:SetAllPoints()

    local y = -10
    local _, o

    local modeInfo = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    modeInfo:SetPoint("TOPLEFT", 30, y)
    modeInfo:SetWidth(340)
    modeInfo:SetJustifyH("LEFT")
    modeInfo:SetText(
        "System availability is controlled by your selected mode (Cozy or Survival). These settings configure behavior for each system when active.")
    modeInfo:SetTextColor(unpack(COLORS.textDim))
    y = y - 45

    local EXHAUST_COLOR = {1.0, 0.6, 0.4, 1}
    _, o = CreateSectionHeader(content, "Exhaustion System", y, EXHAUST_COLOR)
    y = y + o
    _, o = CreateModernCheckbox(content, "Exhaustion Overlay",
        "Enable the exhaustion screen vignette as exhaustion rises.", "exhaustionOverlayEnabled", y)
    y = y + o
    y = y - 10

    _, o = CreateSectionHeader(content, "Anguish System", y, COLORS.Anguish)
    y = y + o
    _, o = CreateModernCheckbox(content, "Anguish Overlay",
        "Enable the Anguish screen vignette based on trauma levels.", "anguishOverlayEnabled", y)
    y = y + o
    _, o = CreateModernCheckbox(content, "Innkeepers Heal Anguish",
        "Talking to an innkeeper heals your Anguish up to 85% vitality.", "innkeeperHealsAnguish", y)
    y = y + o
    _, o = CreateModernDropdown(content, "Difficulty", nil, "AnguishScale",
        WL.GetAnguishScaleNames and WL.GetAnguishScaleNames() or {"Default", "Hard", "Insane"}, y,
        WL.GetAnguishScaleTooltips and WL.GetAnguishScaleTooltips() or nil)
    y = y + o
    y = y - 10

    local HUNGER_COLOR = {0.9, 0.6, 0.2, 1}
    _, o = CreateSectionHeader(content, "Hunger System", y, HUNGER_COLOR)
    y = y + o
    _, o = CreateModernCheckbox(content, "Hunger Overlay",
        "Enable the hunger vignette that darkens the screen edges.", "hungerOverlayEnabled", y)
    y = y + o
    _, o = CreateModernCheckbox(content, "Innkeepers Reset Hunger",
        "Talking to an innkeeper heals your Hunger up to 85% satiation.", "innkeeperResetsHunger", y)
    y = y + o
    _, o = CreateModernSlider(content, "Max Darkness",
        "Maximum screen vignette darkness when fully hungry (100%). Creates a subtle darkening around screen edges.",
        "hungerMaxDarkness", 0, 0.75, 0.05, y, function(v)
            return string.format("%.0f%%", v * 100)
        end)
    y = y + o
    y = y - 10

    local THIRST_COLOR = {0.4, 0.7, 1.0, 1}
    _, o = CreateSectionHeader(content, "Thirst System", y, THIRST_COLOR)
    y = y + o
    _, o = CreateModernCheckbox(content, "Thirst Overlay",
        "Enable the thirst vignette that adds a blue edge tint.", "thirstOverlayEnabled", y)
    y = y + o
    _, o = CreateModernCheckbox(content, "Innkeepers Reset Thirst",
        "Talking to an innkeeper heals your Thirst up to 85% hydration.", "innkeeperResetsThirst", y)
    y = y + o
    _, o = CreateModernSlider(content, "Max Darkness",
        "Maximum screen vignette darkness when fully thirsty (100%). Creates a subtle darkening around screen edges with a blue tint.",
        "thirstMaxDarkness", 0, 0.75, 0.05, y, function(v)
            return string.format("%.0f%%", v * 100)
        end)
    y = y + o
    y = y - 10

    y = y - 10
    local CONSTITUTION_COLOR = {0.6, 0.9, 0.6, 1}
    _, o = CreateSectionHeader(content, "Constitution System", y, CONSTITUTION_COLOR)
    y = y + o
    _, o = CreateModernCheckbox(content, "Hide UI at Low Constitution",
        "When enabled, low constitution will hide action bars, unit frames, nameplates, minimap, and bags. Disable to prevent constitution from affecting the UI.",
        "hideUIAtLowConstitution", y)
    y = y + o
    _, o = CreateModernCheckbox(content, "Lingering Effects",
        "Lingering Effects (Survival only): Disease affects Hunger, Curse affects Exhaustion, Bleed affects Anguish, Poison affects Thirst. Each effect triples the accumulation rate while active: Disease 1h, Curse 10m, Bleed 15m, Poison 30m.",
        "lingeringEffectsEnabled", y)
    y = y + o
    _, o = CreateModernCheckbox(content, "Block Map at Low Constitution",
        "Prevent opening the world map when constitution drops below 50%. Overrides the Fire tab's 'Block Map Access' setting.",
        "blockMapWithConstitution", y)
    y = y + o
    _, o = CreateModernCheckbox(content, "Block Bags at Low Constitution",
        "Prevent opening bags when constitution drops below 25%. Forces you to find safety before managing inventory.",
        "blockBagsWithConstitution", y)
    y = y + o
    y = y - 10

    local TEMP_COLOR = {1.0, 0.7, 0.3, 1}
    _, o = CreateSectionHeader(content, "Temperature System", y, TEMP_COLOR)
    y = y + o
    _, o = CreateModernCheckbox(content, "Temperature Overlay",
        "Enable the hot/cold screen vignette as temperature swings.", "temperatureOverlayEnabled", y)
    y = y + o
    _, o = CreateModernCheckbox(content, "Manual Weather Toggle",
        "Show a weather toggle button below the temperature meter. Click it to simulate current weather effects (rain, snow, dust storms) since Classic WoW cannot detect weather automatically. Only available in zones where weather can occur.",
        "manualWeatherEnabled", y)
    y = y + o

    return content
end

local function CreatePanel()
    if settingsFrame then
        return settingsFrame
    end

    settingsFrame = CreateFrame("Frame", "WanderlustSettingsFrame", UIParent, "BackdropTemplate")
    settingsFrame:SetSize(400, 650)
    settingsFrame:SetPoint("CENTER")
    settingsFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 2
    })
    settingsFrame:SetBackdropColor(unpack(COLORS.bg))
    settingsFrame:SetBackdropBorderColor(0.12, 0.12, 0.14, 1)
    settingsFrame:SetMovable(true)
    settingsFrame:EnableMouse(true)
    settingsFrame:RegisterForDrag("LeftButton")
    settingsFrame:SetScript("OnDragStart", settingsFrame.StartMoving)
    settingsFrame:SetScript("OnDragStop", settingsFrame.StopMovingOrSizing)
    settingsFrame:SetScript("OnHide", function()
        if WL.HideDebugPanel then
            WL.HideDebugPanel()
        end
    end)
    settingsFrame:SetFrameStrata("DIALOG")
    settingsFrame:SetFrameLevel(100)
    settingsFrame:Hide()

    local header = CreateFrame("Frame", nil, settingsFrame, "BackdropTemplate")
    header:SetSize(400, 60)
    header:SetPoint("TOP")
    header:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8"
    })
    header:SetBackdropColor(unpack(COLORS.headerBg))

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
    pulse1:SetFromAlpha(0.3)
    pulse1:SetToAlpha(0.6)
    pulse1:SetDuration(0.8)
    pulse1:SetOrder(1)
    pulse1:SetSmoothing("IN_OUT")
    local pulse2 = glowAnim:CreateAnimation("Alpha")
    pulse2:SetFromAlpha(0.6)
    pulse2:SetToAlpha(0.3)
    pulse2:SetDuration(0.8)
    pulse2:SetOrder(2)
    pulse2:SetSmoothing("IN_OUT")
    glowAnim:Play()

    local titleShadow = header:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    titleShadow:SetPoint("LEFT", iconFrame, "RIGHT", 11, -1)
    titleShadow:SetText("Wanderlust")
    titleShadow:SetTextColor(0, 0, 0, 0.5)

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", iconFrame, "RIGHT", 10, 0)
    title:SetText("Wanderlust")
    title:SetTextColor(1.0, 0.75, 0.35, 1)

    local subtitle = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    subtitle:SetText("A Survival Experience")
    subtitle:SetTextColor(0.6, 0.6, 0.6, 1)

    local versionBg = header:CreateTexture(nil, "ARTWORK")
    versionBg:SetSize(40, 16)
    versionBg:SetPoint("LEFT", title, "RIGHT", 8, 0)
    versionBg:SetColorTexture(1.0, 0.6, 0.2, 0.2)

    local version = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    version:SetPoint("CENTER", versionBg, "CENTER", 0, 0)
    version:SetText("v" .. WL.version)
    version:SetTextColor(1.0, 0.7, 0.3, 1)

    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(30, 30)
    closeBtn:SetPoint("RIGHT", -10, 0)
    local closeText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    closeText:SetPoint("CENTER")
    closeText:SetText("x")
    closeText:SetTextColor(0.5, 0.5, 0.5, 1)
    closeBtn:SetScript("OnEnter", function()
        closeText:SetTextColor(unpack(COLORS.danger))
    end)
    closeBtn:SetScript("OnLeave", function()
        closeText:SetTextColor(0.5, 0.5, 0.5, 1)
    end)
    closeBtn:SetScript("OnClick", function()
        settingsFrame:Hide()
    end)

    local headerLine = header:CreateTexture(nil, "ARTWORK")
    headerLine:SetSize(380, 2)
    headerLine:SetPoint("BOTTOM", header, "BOTTOM", 0, 0)
    headerLine:SetColorTexture(1.0, 0.6, 0.2, 0.3)

    local tabBar = CreateFrame("Frame", nil, settingsFrame, "BackdropTemplate")
    tabBar:SetSize(400, 30)
    tabBar:SetPoint("TOP", header, "BOTTOM", 0, 0)
    tabBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8"
    })
    tabBar:SetBackdropColor(0.05, 0.05, 0.07, 1)

    local tabWidth = 400 / 3
    CreateTabButton(tabBar, "general", "General", 0)
    tabButtons["general"]:SetSize(tabWidth, 30)
    CreateTabButton(tabBar, "fire", "Fire", tabWidth)
    tabButtons["fire"]:SetSize(tabWidth, 30)
    CreateTabButton(tabBar, "survival", "Survival", tabWidth * 2)
    tabButtons["survival"]:SetSize(tabWidth, 30)

    local tabUnderline = tabBar:CreateTexture(nil, "ARTWORK")
    tabUnderline:SetSize(380, 2)
    tabUnderline:SetPoint("BOTTOM", 0, 0)
    tabUnderline:SetColorTexture(0.2, 0.2, 0.22, 1)

    local tabContainer = CreateFrame("Frame", nil, settingsFrame)
    tabContainer:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, 0)
    tabContainer:SetPoint("BOTTOMRIGHT", settingsFrame, "BOTTOMRIGHT", 0, 50)

    local function CreateTabScrollFrame(tabKey, createContentFunc)
        local scrollFrame = CreateFrame("ScrollFrame", nil, tabContainer, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 5, -5)
        scrollFrame:SetPoint("BOTTOMRIGHT", -25, 5)

        local scrollBar = scrollFrame.ScrollBar
        if scrollBar then
            scrollBar:ClearAllPoints()
            scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", -2, -16)
            scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", -2, 16)
        end

        local content = CreateFrame("Frame", nil, scrollFrame)
        content:SetSize(365, 600)
        scrollFrame:SetScrollChild(content)

        createContentFunc(content)

        tabFrames[tabKey] = scrollFrame
        if tabKey ~= "general" then
            scrollFrame:Hide()
        end

        return scrollFrame
    end

    CreateTabScrollFrame("general", CreateGeneralTab)
    CreateTabScrollFrame("fire", CreateFireTab)
    CreateTabScrollFrame("survival", CreateSurvivalTab)

    local bottomBar = CreateFrame("Frame", nil, settingsFrame, "BackdropTemplate")
    bottomBar:SetSize(400, 50)
    bottomBar:SetPoint("BOTTOM")
    bottomBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8"
    })
    bottomBar:SetBackdropColor(unpack(COLORS.headerBg))

    local bottomLine = bottomBar:CreateTexture(nil, "ARTWORK")
    bottomLine:SetSize(380, 1)
    bottomLine:SetPoint("TOP", bottomBar, "TOP", 0, 0)
    bottomLine:SetColorTexture(1.0, 0.6, 0.2, 0.2)

    local function TryReloadUI()
        if InCombatLockdown and InCombatLockdown() then
            print("|cff88CCFFWanderlust:|r Cannot reload UI during combat.")
            return
        end
        print("|cff88CCFFWanderlust:|r Please type /reload to apply changes.")
    end

    local resetBtn = CreateFrame("Button", nil, bottomBar, "BackdropTemplate")
    resetBtn:SetSize(100, 32)
    resetBtn:SetPoint("LEFT", 15, 0)
    resetBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1
    })
    resetBtn:SetBackdropColor(0.12, 0.12, 0.14, 1)
    resetBtn:SetBackdropBorderColor(0.25, 0.25, 0.28, 1)
    local resetText = resetBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    resetText:SetPoint("CENTER")
    resetText:SetText("Reset All")
    resetText:SetTextColor(0.6, 0.6, 0.6, 1)
    resetBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(COLORS.warning))
        resetText:SetTextColor(unpack(COLORS.warning))
    end)
    resetBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.25, 0.25, 0.28, 1)
        resetText:SetTextColor(0.6, 0.6, 0.6, 1)
    end)
    resetBtn:SetScript("OnClick", function()
        if not StaticPopupDialogs or not StaticPopupDialogs["WANDERLUST_RESET"] then
            print("|cff88CCFFWanderlust:|r Reset dialog not ready.")
            return
        end
        StaticPopup_Show("WANDERLUST_RESET")
    end)

    local reloadBtn = CreateFrame("Button", nil, bottomBar, "BackdropTemplate")
    reloadBtn:SetSize(120, 32)
    reloadBtn:SetPoint("CENTER", 0, 0)
    reloadBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1
    })
    reloadBtn:SetBackdropColor(0.15, 0.15, 0.18, 1)
    reloadBtn:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
    local reloadText = reloadBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    reloadText:SetPoint("CENTER")
    reloadText:SetText("Save & Reload")
    reloadText:SetTextColor(0.7, 0.7, 0.7, 1)
    reloadBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.5, 0.7, 1.0, 1)
        reloadText:SetTextColor(0.5, 0.7, 1.0, 1)
    end)
    reloadBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
        reloadText:SetTextColor(0.7, 0.7, 0.7, 1)
    end)
    reloadBtn:SetScript("OnClick", function()
        ReloadUI()
    end)

    local closeBtn = CreateFrame("Button", nil, bottomBar, "BackdropTemplate")
    closeBtn:SetSize(100, 32)
    closeBtn:SetPoint("RIGHT", -15, 0)
    closeBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1
    })
    closeBtn:SetBackdropColor(0.8, 0.45, 0.1, 1)
    closeBtn:SetBackdropBorderColor(1.0, 0.6, 0.2, 1)
    local closeBtnText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    closeBtnText:SetPoint("CENTER")
    closeBtnText:SetText("Close")
    closeBtnText:SetTextColor(1, 1, 1, 1)
    closeBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(1.0, 0.6, 0.2, 1)
    end)
    closeBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.8, 0.45, 0.1, 1)
    end)
    closeBtn:SetScript("OnClick", function()
        settingsFrame:Hide()
    end)

    StaticPopupDialogs["WANDERLUST_RESET"] = {
        text = "Reset all Wanderlust settings to defaults (Survival mode)?\n\n|cffFFFF00This will reload your UI.|r",
        button1 = "Yes",
        button2 = "No",
        OnAccept = function()
            if InCombatLockdown and InCombatLockdown() then
                print("|cff88CCFFWanderlust:|r Cannot reset settings during combat.")
                return
            end
            if not WL.db then
                print("|cff88CCFFWanderlust:|r Settings not ready to reset.")
                return
            end
            WL.ResetSettings()
            C_Timer.After(0.1, TryReloadUI)
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true
    }

    tinsert(UISpecialFrames, "WanderlustSettingsFrame")

    return settingsFrame
end

WL.RegisterCallback("SETTINGS_CHANGED", function(key)
    if key == "ALL" then
        RefreshControls()
    elseif controls[key] then
        if controls[key].checkbox then
            controls[key].checkbox:SetChecked(WL.GetSetting(key))
        end
        if controls[key].update then
            controls[key].update()
        end
    end
end)

function WL.ToggleSettings(showDebug)
    local f = CreatePanel()
    if f:IsShown() then
        if showDebug then
            SetDebugVisible(true)
            return
        end
        f:Hide()
    else
        RefreshControls()
        f:Show()
        f:Raise()
        SetDebugVisible(showDebug)
    end
end

function WL.OpenSettings(showDebug)
    local f = CreatePanel()
    RefreshControls()
    f:Show()
    f:Raise()
    SetDebugVisible(showDebug)
end

function WL.CloseSettings()
    if settingsFrame then
        settingsFrame:Hide()
    end
end
