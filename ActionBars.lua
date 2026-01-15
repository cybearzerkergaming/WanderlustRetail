-- Wanderlust - action bar visibility management
local WL = Wanderlust
local math_abs = math.abs
local math_min = math.min
local math_max = math.max
local C_Timer_After = C_Timer.After
local InCombatLockdown = InCombatLockdown

local ACTION_BAR_FRAMES = {"MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarLeft", "MultiBarRight",

"BonusActionBarFrame", "ShapeshiftBarFrame"}

local EXTRA_UI_FRAMES = {"StanceBarFrame",
                         "ActionBarUpButton", "ActionBarDownButton", "MainMenuBarPageNumber",
                         "MainMenuBarArtFrame", "MainMenuBarArtFrameBackground", "ActionBarPageUpButton",
                         "ActionBarPageDownButton",
"CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton", "QuestLogMicroButton", "SocialsMicroButton",
                         "WorldMapMicroButton", "MainMenuMicroButton", "HelpMicroButton", "AchievementMicroButton",
                         "LFDMicroButton", "CollectionsMicroButton", "EJMicroButton", "StoreMicroButton",
                         "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap", "MainMenuBarTexture0",
                         "MainMenuBarTexture1", "MainMenuBarTexture2", "MainMenuBarTexture3", "MainMenuExpBar",
                         "ReputationWatchBar", "MainMenuBarMaxLevelBar",
"MicroMenu", "MainMenuBarVehicleLeaveButton",
"MainStatusTrackingBarContainer", "StatusTrackingBarManager"}

local MINIMAP_FRAMES = {"MinimapCluster", "Minimap", "MinimapBorder", "MinimapBorderTop", "MinimapZoomIn",
                        "MinimapZoomOut", "MinimapBackdrop", "GameTimeFrame", "MiniMapTracking",
                        "MiniMapMailFrame", "MiniMapBattlefieldFrame", "MiniMapWorldMapButton"}

local PET_BAR_FRAMES = {"PetActionBar", "PetActionBarFrame"}

local barsHidden = false
local introShown = false

local constitutionOverrideActive = false

local currentAlpha = 1
local targetAlpha = 1
local FADE_SPEED = 4
local isAnimating = false

local minimapCurrentAlpha = 1
local minimapTargetAlpha = 1
local isMinimapAnimating = false

-- Track pre-hide visibility so we don't re-show disabled bars.
local frameVisibilityState = {}

local animFrame = CreateFrame("Frame")

local function IsBarEnabledInSettings(frameName)
    if frameVisibilityState[frameName] == true then
        return true
    end

    if frameName == "MainMenuBar" then
        return true
    end

    if frameName == "MultiBarBottomLeft" then
        return GetCVar("SHOW_MULTI_ACTIONBAR_1") == "1"
    elseif frameName == "MultiBarBottomRight" then
        return GetCVar("SHOW_MULTI_ACTIONBAR_2") == "1"
    elseif frameName == "MultiBarRight" then
        return GetCVar("SHOW_MULTI_ACTIONBAR_3") == "1"
    elseif frameName == "MultiBarLeft" then
        return GetCVar("SHOW_MULTI_ACTIONBAR_4") == "1"
    end

    if frameName == "PetActionBarFrame" or frameName == "PetActionBar" then
        local petFrame = _G["PetActionBarFrame"]
        return petFrame and petFrame:IsShown()
    end

    if frameName == "StanceBarFrame" or frameName == "ShapeshiftBarFrame" then
        local numForms = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
        return numForms > 0
    end

    if frameName == "BonusActionBarFrame" then
        local frame = _G[frameName]
        return frame and frame:IsShown()
    end

    return true
end

local function SetBarsAlpha(alpha)
    -- Avoid protected Show/Hide calls during combat; use alpha-only there.
    for _, frameName in ipairs(ACTION_BAR_FRAMES) do
        local frame = _G[frameName]
        if frame then
            if alpha > 0 then
                if IsBarEnabledInSettings(frameName) and frameVisibilityState[frameName] ~= false then
                    if not frame:IsShown() and not InCombatLockdown() then
                        frame:Show()
                    end
                    frame:SetAlpha(alpha)
                    for i = 1, 12 do
                        local buttonName = frameName == "MainMenuBar" and ("ActionButton" .. i) or
                                               (frameName .. "Button" .. i)
                        local button = _G[buttonName]
                        if button then
                            button:SetAlpha(1)
                            if button.cooldown then
                                button.cooldown:SetAlpha(1)
                            end
                        end
                    end
                end
            else
                if frameVisibilityState[frameName] == nil then
                    frameVisibilityState[frameName] = frame:IsShown()
                end
                frame:SetAlpha(0)
                if not InCombatLockdown() then
                    frame:Hide()
                end
                for i = 1, 12 do
                    local buttonName = frameName == "MainMenuBar" and ("ActionButton" .. i) or
                                           (frameName .. "Button" .. i)
                    local button = _G[buttonName]
                    if button then
                        button:SetAlpha(0)
                        if button.cooldown then
                            button.cooldown:SetAlpha(0)
                        end
                        if button.Flash then
                            button.Flash:Hide()
                        end
                        local flash = _G[buttonName .. "Flash"]
                        if flash then
                            flash:Hide()
                        end
                    end
                end
            end
        end
    end

    for _, frameName in ipairs(EXTRA_UI_FRAMES) do
        local frame = _G[frameName]
        if frame then
            if alpha > 0 then
                if IsBarEnabledInSettings(frameName) and frameVisibilityState[frameName] == true then
                    if not frame:IsShown() and not InCombatLockdown() then
                        frame:Show()
                    end
                    frame:SetAlpha(alpha)
                end
            else
                if frameVisibilityState[frameName] == nil then
                    frameVisibilityState[frameName] = frame:IsShown()
                end
                frame:SetAlpha(0)
                if not InCombatLockdown() then
                    frame:Hide()
                end
            end
        end
    end

    for _, frameName in ipairs(PET_BAR_FRAMES) do
        local frame = _G[frameName]
        if frame then
            frame:SetAlpha(alpha)
            for i = 1, 10 do
                local button = _G["PetActionButton" .. i]
                if button then
                    button:SetAlpha(alpha)
                end
            end
        end
    end

    local shouldHideMinimap = constitutionOverrideActive or WL.GetSetting("hideMinimapWithBars")
    if shouldHideMinimap then
        for _, frameName in ipairs(MINIMAP_FRAMES) do
            local frame = _G[frameName]
            if frame then
                if alpha > 0 then
                    if frameVisibilityState[frameName] == true then
                        if not frame:IsShown() and not InCombatLockdown() then
                            frame:Show()
                        end
                        frame:SetAlpha(alpha)
                    end
                else
                    if frameVisibilityState[frameName] == nil then
                        frameVisibilityState[frameName] = frame:IsShown()
                    end
                    frame:SetAlpha(0)
                    if not InCombatLockdown() then
                        frame:Hide()
                    end
                end
            end
        end
    elseif alpha > 0 then
        for _, frameName in ipairs(MINIMAP_FRAMES) do
            local frame = _G[frameName]
            if frame and frameVisibilityState[frameName] == true then
                if not frame:IsShown() and not InCombatLockdown() then
                    frame:Show()
                end
                frame:SetAlpha(1)
            end
        end
    end


    local petFrame = _G["PetActionBarFrame"]
    if petFrame then
        if petFrame.slideTimer == nil then
            petFrame.slideTimer = 0
        end
        if petFrame.timeToSlide == nil then
            petFrame.timeToSlide = 0
        end
        if alpha > 0 then
            if frameVisibilityState["PetActionBarFrame"] == true then
                if not petFrame:IsShown() and not InCombatLockdown() then
                    petFrame:Show()
                end
                petFrame:SetAlpha(alpha)
            end
        else
            if frameVisibilityState["PetActionBarFrame"] == nil then
                frameVisibilityState["PetActionBarFrame"] = petFrame:IsShown()
            end
            petFrame:SetAlpha(0)
        end
    end

    local mainMenuBar = _G["MainMenuBar"]
    if mainMenuBar then
        local pageNumber = mainMenuBar.ActionBarPageNumber or mainMenuBar.PageNumber
        if pageNumber then
            local pageKey = "MainMenuBar.PageNumber"
            if alpha > 0 then
                if frameVisibilityState[pageKey] == true then
                    if not pageNumber:IsShown() and not InCombatLockdown() then
                        pageNumber:Show()
                    end
                    pageNumber:SetAlpha(alpha)
                end
            else
                if frameVisibilityState[pageKey] == nil then
                    frameVisibilityState[pageKey] = pageNumber:IsShown()
                end
                pageNumber:SetAlpha(0)
                if not InCombatLockdown() then
                    pageNumber:Hide()
                end
            end
        end

        for _, child in pairs({mainMenuBar:GetChildren()}) do
            local name = child:GetName()
            if name and (name:find("Page") or name:find("Arrow") or name:find("UpButton") or name:find("DownButton")) then
                local childKey = name or tostring(child)
                if alpha > 0 then
                    if frameVisibilityState[childKey] == true then
                        if not child:IsShown() and not InCombatLockdown() then
                            child:Show()
                        end
                        child:SetAlpha(alpha)
                    end
                else
                    if frameVisibilityState[childKey] == nil then
                        frameVisibilityState[childKey] = child:IsShown()
                    end
                    child:SetAlpha(0)
                    if not InCombatLockdown() then
                        child:Hide()
                    end
                end
            end
        end
    end

    local artFrame = _G["MainMenuBarArtFrame"]
    if artFrame then
        for _, child in pairs({artFrame:GetChildren()}) do
            local name = child:GetName()
            if name and
                (name:find("Page") or name:find("Arrow") or name:find("UpButton") or name:find("DownButton") or
                    name:find("Number")) then
                local childKey = name or tostring(child)
                if alpha > 0 then
                    if frameVisibilityState[childKey] == true then
                        if not child:IsShown() and not InCombatLockdown() then
                            child:Show()
                        end
                        child:SetAlpha(alpha)
                    end
                else
                    if frameVisibilityState[childKey] == nil then
                        frameVisibilityState[childKey] = child:IsShown()
                    end
                    child:SetAlpha(0)
                    if not InCombatLockdown() then
                        child:Hide()
                    end
                end
            end
            if not name then
                if child.GetNormalTexture or child.SetNormalTexture then
                    local childKey = tostring(child)
                    if alpha > 0 then
                        if frameVisibilityState[childKey] == true then
                            if not child:IsShown() and not InCombatLockdown() then
                                child:Show()
                            end
                            child:SetAlpha(alpha)
                        end
                    else
                        if frameVisibilityState[childKey] == nil then
                            frameVisibilityState[childKey] = child:IsShown()
                        end
                        child:SetAlpha(0)
                        if not InCombatLockdown() then
                            child:Hide()
                        end
                    end
                end
            end
        end
        if alpha <= 0 then
            if frameVisibilityState["MainMenuBarArtFrame"] == nil then
                frameVisibilityState["MainMenuBarArtFrame"] = artFrame:IsShown()
            end
            artFrame:SetAlpha(0)
            if not InCombatLockdown() then
                artFrame:Hide()
            end
        elseif frameVisibilityState["MainMenuBarArtFrame"] == true then
            artFrame:SetAlpha(alpha)
            if not artFrame:IsShown() and not InCombatLockdown() then
                artFrame:Show()
            end
        end
    end

    local mainActionBar = _G["MainActionBar"]
    if mainActionBar and mainActionBar.ActionBarPageNumber then
        local pageNum = mainActionBar.ActionBarPageNumber
        local pageKey = "MainActionBar.PageNumber"
        if alpha > 0 then
            if frameVisibilityState[pageKey] == true then
                if not pageNum:IsShown() and not InCombatLockdown() then
                    pageNum:Show()
                end
                pageNum:SetAlpha(alpha)
            end
        else
            if frameVisibilityState[pageKey] == nil then
                frameVisibilityState[pageKey] = pageNum:IsShown()
            end
            pageNum:SetAlpha(0)
            if not InCombatLockdown() then
                pageNum:Hide()
            end
        end
    end
end

local function OnUpdate(self, elapsed)
    if not isAnimating then
        return
    end

    local diff = targetAlpha - currentAlpha
    if math_abs(diff) < 0.01 then
        currentAlpha = targetAlpha
        SetBarsAlpha(currentAlpha)
        isAnimating = false
        animFrame:SetScript("OnUpdate", nil)

        if currentAlpha <= 0 then
            barsHidden = true
            WL.Debug("Action bars hidden (fade complete)", "general")
        else
            barsHidden = false
            wipe(frameVisibilityState)
            WL.Debug("Action bars shown (fade complete)", "general")
            C_Timer_After(0.1, function()
                if UIParent_ManageFramePositions then
                    UIParent_ManageFramePositions()
                end
                if PetActionBar_Update then
                    PetActionBar_Update()
                end
                if PetActionBarFrame and PetActionBarFrame:IsShown() then
                    if EventRegistry and EventRegistry.TriggerEvent then
                        pcall(function() EventRegistry:TriggerEvent("ACTIONBAR_PAGE_CHANGED") end)
                    end
                end
            end)
        end
    else
        local change = FADE_SPEED * elapsed
        if diff > 0 then
            currentAlpha = math_min(targetAlpha, currentAlpha + change)
        else
            currentAlpha = math_max(targetAlpha, currentAlpha - change)
        end
        SetBarsAlpha(currentAlpha)
    end
end

local function FadeBarsTo(alpha)
    if InCombatLockdown() then
        return
    end

    targetAlpha = alpha

    if math_abs(currentAlpha - targetAlpha) < 0.01 then
        return
    end

    if alpha > 0 and currentAlpha <= 0 then
        local mainMenuBar = _G["MainMenuBar"]
        if mainMenuBar and frameVisibilityState["MainMenuBar"] ~= false then
            mainMenuBar:Show()
            mainMenuBar:SetAlpha(0.01)
        end

        for _, frameName in ipairs(EXTRA_UI_FRAMES) do
            local frame = _G[frameName]
            if frame and frameVisibilityState[frameName] == true then
                frame:Show()
                frame:SetAlpha(0.01)
            end
        end

        C_Timer_After(0, function()
            for _, frameName in ipairs(ACTION_BAR_FRAMES) do
                if frameName ~= "MainMenuBar" and IsBarEnabledInSettings(frameName) then
                    local frame = _G[frameName]
                    if frame and frameVisibilityState[frameName] ~= false then
                        frame:Show()
                        frame:SetAlpha(currentAlpha > 0.01 and currentAlpha or 0.01)
                    end
                end
            end
        end)
    end

    isAnimating = true
    animFrame:SetScript("OnUpdate", OnUpdate)
end

local function HideBars()
    if InCombatLockdown() then
        return
    end
    FadeBarsTo(0)
end

local function ShowBars()
    if InCombatLockdown() then
        return
    end
    FadeBarsTo(1)
end

function WL.ShowBars()
    ShowBars()
end

local function ForceShowAllBars()
    if InCombatLockdown() then
        return
    end
    FadeBarsTo(1)
    barsHidden = false
end

local function SetMinimapAlpha(alpha)
    for _, frameName in ipairs(MINIMAP_FRAMES) do
        local frame = _G[frameName]
        if frame then
            if alpha > 0 then
                if frameVisibilityState[frameName] == true then
                    if not frame:IsShown() and not InCombatLockdown() then
                        frame:Show()
                    end
                    frame:SetAlpha(alpha)
                end
            else
                if frameVisibilityState[frameName] == nil then
                    frameVisibilityState[frameName] = frame:IsShown()
                end
                frame:SetAlpha(0)
                if not InCombatLockdown() then
                    frame:Hide()
                end
            end
        end
    end
end

local minimapAnimFrame = CreateFrame("Frame")
local function OnMinimapUpdate(self, elapsed)
    if not isMinimapAnimating then
        return
    end

    local diff = minimapTargetAlpha - minimapCurrentAlpha
    if math.abs(diff) < 0.01 then
        minimapCurrentAlpha = minimapTargetAlpha
        SetMinimapAlpha(minimapCurrentAlpha)
        isMinimapAnimating = false
        minimapAnimFrame:SetScript("OnUpdate", nil)
    else
        local change = FADE_SPEED * elapsed
        if diff > 0 then
            minimapCurrentAlpha = math.min(minimapTargetAlpha, minimapCurrentAlpha + change)
        else
            minimapCurrentAlpha = math.max(minimapTargetAlpha, minimapCurrentAlpha - change)
        end
        SetMinimapAlpha(minimapCurrentAlpha)
    end
end

local function FadeMinimapTo(alpha)
    if InCombatLockdown() then
        return
    end

    minimapTargetAlpha = alpha

    if math.abs(minimapCurrentAlpha - minimapTargetAlpha) < 0.01 then
        return
    end

    if alpha > 0 and minimapCurrentAlpha <= 0 then
        for _, frameName in ipairs(MINIMAP_FRAMES) do
            local frame = _G[frameName]
            if frame and frameVisibilityState[frameName] == true then
                frame:Show()
                frame:SetAlpha(0.01)
            end
        end
    end

    isMinimapAnimating = true
    minimapAnimFrame:SetScript("OnUpdate", OnMinimapUpdate)
end

local function UpdateActionBarVisibility()
    if constitutionOverrideActive then
        HideBars()
        return
    end

    local mode = WL.GetSetting("hideActionBarsMode") or 1

    if mode == 1 then
        ShowBars()
        return
    end

    if not WL.IsPlayerEligible() then
        ShowBars()
        return
    end

    if mode == 3 then
        if IsResting() then
            ShowBars()
        else
            HideBars()
        end
        return
    end

    if WL.ShouldShowActionBars() then
        ShowBars()
    else
        HideBars()
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_UPDATE_RESTING")
frame:RegisterEvent("PLAYER_DEAD")
frame:RegisterEvent("PLAYER_ALIVE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_CONTROL_LOST")
frame:RegisterEvent("PLAYER_CONTROL_GAINED")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(1, function()
            local mode = WL.GetSetting("hideActionBarsMode") or 1
            if mode == 1 or not WL.IsPlayerEligible() then
                currentAlpha = 1
                targetAlpha = 1
                barsHidden = false
                SetBarsAlpha(1)
            elseif mode == 3 then
                if IsResting() then
                    currentAlpha = 1
                    targetAlpha = 1
                    barsHidden = false
                    SetBarsAlpha(1)
                else
                    currentAlpha = 0
                    targetAlpha = 0
                    barsHidden = true
                    SetBarsAlpha(0)
                end
            elseif WL.ShouldShowActionBars() then
                currentAlpha = 1
                targetAlpha = 1
                barsHidden = false
                SetBarsAlpha(1)
            else
                currentAlpha = 0
                targetAlpha = 0
                barsHidden = true
                SetBarsAlpha(0)
            end
        end)

    elseif event == "PLAYER_LEVEL_UP" then
        local newLevel = arg1
        local mode = WL.GetSetting("hideActionBarsMode") or 1
        C_Timer.After(0.5, UpdateActionBarVisibility)

    elseif event == "PLAYER_REGEN_DISABLED" then
        local mode = WL.GetSetting("hideActionBarsMode") or 1
        if mode ~= 1 and WL.IsPlayerEligible() then
            if not InCombatLockdown() then
                targetAlpha = 0
                currentAlpha = 0
                SetBarsAlpha(0)
                barsHidden = true
                isAnimating = false
            end
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        C_Timer.After(0.1, UpdateActionBarVisibility)

    elseif event == "PLAYER_UPDATE_RESTING" then
        C_Timer.After(0.1, UpdateActionBarVisibility)

    elseif event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" then
        C_Timer.After(0.1, UpdateActionBarVisibility)

    elseif event == "PLAYER_CONTROL_LOST" or event == "PLAYER_CONTROL_GAINED" then
        C_Timer.After(0.2, function()
            if UnitOnTaxi("player") or event == "PLAYER_CONTROL_GAINED" then
                UpdateActionBarVisibility()
            end
        end)
    end
end)

WL.RegisterCallback("FIRE_STATE_CHANGED", function(isNearFire, inCombat)
    if not InCombatLockdown() then
        UpdateActionBarVisibility()
    end
end)

WL.RegisterCallback("SETTINGS_CHANGED", function(key, value)
    if key == "hideActionBarsMode" or key == "ALL" then
        if not InCombatLockdown() then
            UpdateActionBarVisibility()
        end
    elseif key == "hideMinimapWithBars" then
        if not InCombatLockdown() then
            local hideMinimapEnabled = WL.GetSetting("hideMinimapWithBars")
            if not hideMinimapEnabled and not constitutionOverrideActive then
                for _, frameName in ipairs(MINIMAP_FRAMES) do
                    local frame = _G[frameName]
                    if frame and frameVisibilityState[frameName] == nil then
                        frameVisibilityState[frameName] = frame:IsShown() or frame:GetAlpha() > 0
                    end
                end
                minimapCurrentAlpha = 0
                FadeMinimapTo(1)
            elseif hideMinimapEnabled and barsHidden then
                for _, frameName in ipairs(MINIMAP_FRAMES) do
                    local frame = _G[frameName]
                    if frame and frameVisibilityState[frameName] == nil then
                        frameVisibilityState[frameName] = frame:IsShown()
                    end
                end
                minimapCurrentAlpha = 1
                FadeMinimapTo(0)
            end
            UpdateActionBarVisibility()
        end
    elseif key == "enabled" then
        if not InCombatLockdown() then
            if value == false then
                ForceShowAllBars()
            else
                UpdateActionBarVisibility()
            end
        end
    end
end)

function WL.RefreshActionBars()
    UpdateActionBarVisibility()
end

function WL.AreBarsHidden()
    return barsHidden
end

function WL.SetConstitutionOverride(active)
    if InCombatLockdown() then
        return false
    end
    local changed = constitutionOverrideActive ~= active
    constitutionOverrideActive = active
    if changed then
        UpdateActionBarVisibility()
        WL.Debug("Constitution override: " .. (active and "ACTIVE" or "INACTIVE"), "general")
    end
    return true
end

function WL.IsConstitutionOverrideActive()
    return constitutionOverrideActive
end

local bagBlockHookInstalled = false

local function ShouldBlockBags()
    if not constitutionOverrideActive then return false end
    if not WL.GetSetting("blockBagsWithConstitution") then return false end
    if WL.IsInDungeonOrRaid and WL.IsInDungeonOrRaid() then return false end
    if UnitOnTaxi("player") then return false end
    return true
end

local function InstallBagBlockHook()
    if bagBlockHookInstalled then return end
    bagBlockHookInstalled = true

    if OpenAllBags then
        hooksecurefunc("OpenAllBags", function()
            if ShouldBlockBags() then
                CloseAllBags()
                print("|cff88CCFFWanderlust:|r |cffFF6666Bags blocked - constitution too low! Find safety first.|r")
                if WL.BoostRestrictionIconSpin then WL.BoostRestrictionIconSpin("bag") end
            end
        end)
    end

    if OpenBackpack then
        hooksecurefunc("OpenBackpack", function()
            if ShouldBlockBags() then
                CloseBackpack()
                print("|cff88CCFFWanderlust:|r |cffFF6666Bags blocked - constitution too low! Find safety first.|r")
                if WL.BoostRestrictionIconSpin then WL.BoostRestrictionIconSpin("bag") end
            end
        end)
    end

    if ToggleAllBags then
        hooksecurefunc("ToggleAllBags", function()
            if ShouldBlockBags() then
                CloseAllBags()
                if WL.BoostRestrictionIconSpin then WL.BoostRestrictionIconSpin("bag") end
            end
        end)
    end

    if ToggleBackpack then
        hooksecurefunc("ToggleBackpack", function()
            if ShouldBlockBags() then
                CloseBackpack()
                if WL.BoostRestrictionIconSpin then WL.BoostRestrictionIconSpin("bag") end
            end
        end)
    end

    if ToggleBag then
        hooksecurefunc("ToggleBag", function(bagID)
            if ShouldBlockBags() then
                CloseBag(bagID)
                if WL.BoostRestrictionIconSpin then WL.BoostRestrictionIconSpin("bag") end
            end
        end)
    end

    WL.Debug("Bag blocking hooks installed", "general")
end

local bagBlockFrame = CreateFrame("Frame")
bagBlockFrame:RegisterEvent("PLAYER_LOGIN")
bagBlockFrame:SetScript("OnEvent", function()
    C_Timer.After(1, InstallBagBlockHook)
end)
