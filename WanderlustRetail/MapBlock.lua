-- Wanderlust - world map blocking (Midnight / modern-safe)
-- Updated: Avoid overriding global ToggleWorldMap / ToggleBattlefieldMap (can be protected on modern clients).
-- Instead: secure hooks + OnShow guards that immediately close blocked maps.

local WL = Wanderlust

local mapBlocked = false
local hooksInstalled = false

local function Debug(msg)
    if WL and WL.Debug then
        WL.Debug(msg, "general")
    else
        -- fallback to print only when debug helper not available
        -- (keep quiet in normal play)
    end
end

local function CanUseMap()
    if WL and WL.CanUseMap then
        return WL.CanUseMap()
    end
    return true
end

local function GetSetting(key)
    if WL and WL.GetSetting then
        return WL.GetSetting(key)
    end
    return nil
end

local function TryBoostRestrictionSpin()
    if GetSetting("blockMapWithConstitution") and WL and WL.GetConstitution then
        local constitution = WL.GetConstitution()
        if constitution and constitution < 50 and WL.BoostRestrictionIconSpin then
            WL.BoostRestrictionIconSpin("map")
        end
    end
end

local function CloseWorldMapIfShown()
    if WorldMapFrame and WorldMapFrame.IsShown and WorldMapFrame:IsShown() and not InCombatLockdown() then
        pcall(function() WorldMapFrame:Hide() end)
    end
end

local function CloseBattlefieldMapIfShown()
    if BattlefieldMapFrame and BattlefieldMapFrame.IsShown and BattlefieldMapFrame:IsShown() and not InCombatLockdown() then
        pcall(function() BattlefieldMapFrame:Hide() end)
    end
end

local function HandleWorldMapAttempt()
    if not mapBlocked then return end
    if CanUseMap() then return end

    Debug("Map blocked - find a campfire or inn")
    TryBoostRestrictionSpin()

    -- Can't prevent ToggleWorldMap on modern clients safely; close immediately instead.
    C_Timer.After(0, CloseWorldMapIfShown)
end

local function HandleBattlefieldMapAttempt()
    if not mapBlocked then return end
    if CanUseMap() then return end

    Debug("Battlefield map blocked")
    C_Timer.After(0, CloseBattlefieldMapIfShown)
end

local function InstallHooks()
    if hooksInstalled then return end

    -- Close if something else opens the map (keybinds, UI buttons, other addons)
    if WorldMapFrame and WorldMapFrame.HookScript then
        WorldMapFrame:HookScript("OnShow", function()
            if mapBlocked and not CanUseMap() then
                HandleWorldMapAttempt()
            end
        end)
    end

    if BattlefieldMapFrame and BattlefieldMapFrame.HookScript then
        BattlefieldMapFrame:HookScript("OnShow", function()
            if mapBlocked and not CanUseMap() then
                HandleBattlefieldMapAttempt()
            end
        end)
    end

    -- Hook the toggle functions if they exist (safe even if protected; hooksecurefunc is the safe way)
    if type(ToggleWorldMap) == "function" then
        pcall(function()
            hooksecurefunc("ToggleWorldMap", function()
                if mapBlocked and not CanUseMap() then
                    HandleWorldMapAttempt()
                end
            end)
        end)
    end

    if type(ToggleBattlefieldMap) == "function" then
        pcall(function()
            hooksecurefunc("ToggleBattlefieldMap", function()
                if mapBlocked and not CanUseMap() then
                    HandleBattlefieldMapAttempt()
                end
            end)
        end)
    end

    hooksInstalled = true
end

local function BlockMap()
    if mapBlocked then return end
    InstallHooks()

    if not InCombatLockdown() and not CanUseMap() then
        CloseWorldMapIfShown()
        CloseBattlefieldMapIfShown()
    end

    mapBlocked = true
    Debug("Map blocking enabled")
end

local function UnblockMap()
    if not mapBlocked then return end

    mapBlocked = false
    Debug("Map blocking disabled")
end

local function UpdateMapBlocking()
    if not GetSetting("blockMap") then
        UnblockMap()
        return
    end

    if WL and WL.IsPlayerEligible and not WL.IsPlayerEligible() then
        UnblockMap()
        return
    end

    BlockMap()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("PLAYER_UPDATE_RESTING")
frame:RegisterEvent("PLAYER_CONTROL_LOST")
frame:RegisterEvent("PLAYER_CONTROL_GAINED")
frame:RegisterEvent("PLAYER_DEAD")
frame:RegisterEvent("PLAYER_ALIVE")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(1, UpdateMapBlocking)
    elseif event == "PLAYER_LEVEL_UP" then
        C_Timer.After(0.5, UpdateMapBlocking)
    else
        C_Timer.After(0.1, function()
            if mapBlocked and not CanUseMap() and not InCombatLockdown() then
                CloseWorldMapIfShown()
            end
        end)
    end
end)

-- Optional callbacks (guarded so missing callback systems won't error)
if WL and WL.RegisterCallback then
    WL.RegisterCallback("FIRE_STATE_CHANGED", function(isNearFire, inCombat)
        if mapBlocked and not CanUseMap() and not InCombatLockdown() then
            if WorldMapFrame and WorldMapFrame.IsShown and WorldMapFrame:IsShown() then
                CloseWorldMapIfShown()
                Debug("Map closed - left fire range")
            end
        end
    end)

    WL.RegisterCallback("SETTINGS_CHANGED", function(key)
        if key == "blockMap" or key == "ALL" then
            UpdateMapBlocking()
        end
    end)
end

function WL.IsMapBlocked()
    return mapBlocked and not CanUseMap()
end
