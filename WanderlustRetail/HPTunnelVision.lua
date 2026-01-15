-- Wanderlust - HP tunnel vision overlay
local WL = Wanderlust

local function WL_Asset(rel)
    -- Use Core-provided asset path if available; otherwise fall back to a safe default.
    -- Long-bracket strings avoid backslash escape pitfalls (e.g. \a) and allow trailing slashes.
    local base = (WL and WL.ASSET_PATH) or [[Interface\AddOns\Wanderlust\assets\]]

    local lastByte = base:byte(-1)
    if lastByte ~= 92 and lastByte ~= 47 then
        base = base .. string.char(92) -- backslash
    end
    return base .. rel
end

local HP_TEXTURES = {
    WL_Asset("tunnel_vision_1.png"),
    WL_Asset("tunnel_vision_2.png"),
    WL_Asset("tunnel_vision_3.png"),
    WL_Asset("tunnel_vision_4.png"),
}


local HP_THRESHOLDS = {0.80, 0.60, 0.40, 0.20}

local overlayFrames = {}
local currentAlphas = {0, 0, 0, 0}
local targetAlphas = {0, 0, 0, 0}

local LERP_SPEED = 3.0

local function CreateOverlayFrame(level)
    if overlayFrames[level] then
        return overlayFrames[level]
    end

    local frame = CreateFrame("Frame", "WanderlustHPTunnelVision_" .. level, UIParent)
    frame:SetAllPoints(UIParent)
    frame:SetFrameStrata("BACKGROUND")
    frame:SetFrameLevel(level)

    frame.texture = frame:CreateTexture(nil, "BACKGROUND")
    frame.texture:SetAllPoints()
    frame.texture:SetTexture(HP_TEXTURES[level])
    frame.texture:SetBlendMode("BLEND")

    frame:SetAlpha(0)
    frame:Hide()

    frame:EnableMouse(false)

    overlayFrames[level] = frame
    return frame
end

local function CreateAllOverlayFrames()
    for i = 1, 4 do
        CreateOverlayFrame(i)
    end
end

local function GetPlayerHPPercent()
    -- Midnight/modern clients can return "secret values" for UnitHealth in some contexts.
    -- Doing arithmetic on secret values throws errors, so we guard carefully.
    if type(UnitHealthPercent) == "function" then
        local p = UnitHealthPercent("player")
        if type(p) == "number" then
            if type(issecretvalue) == "function" and issecretvalue(p) then
                -- Secret value: avoid comparisons/arithmetic; treat as healthy.
                return 1
            end
            return p
        end
    end

    local health = (type(UnitHealth) == "function") and UnitHealth("player") or nil
    local maxHealth = (type(UnitHealthMax) == "function") and UnitHealthMax("player") or nil

    if type(issecretvalue) == "function" then
        if issecretvalue(health) or issecretvalue(maxHealth) then
            -- Can't safely compute; treat as healthy to avoid spam.
            return 1
        end
    end

    health = tonumber(health) or 0
    maxHealth = tonumber(maxHealth) or 0
    if maxHealth <= 0 then
        return 1
    end

    return health / maxHealth
end


local function ShouldShowHPTunnelVision()
    if not WL.GetSetting("hpTunnelVisionEnabled") then
        return false
    end
    if WL.GetMinLevel and UnitLevel("player") < WL.GetMinLevel() then
        return false
    end
    if UnitIsDead("player") or UnitIsGhost("player") then
        return false
    end
    return true
end

local function GetHPLevel()
    if not ShouldShowHPTunnelVision() then
        return 0
    end

    local hpPercent = GetPlayerHPPercent()
    -- If health percent is unavailable/unsafe, don't show the effect.
    if hpPercent == nil then
        return 0
    end
    if type(issecretvalue) == "function" and issecretvalue(hpPercent) then
        return 0
    end
    local level = 0

    for i, threshold in ipairs(HP_THRESHOLDS) do
        if hpPercent <= threshold then
            level = i
        end
    end

    return level
end

local function UpdateHPTunnelVision(elapsed)
    local hpLevel = GetHPLevel()

    for i = 1, 4 do
        if i <= hpLevel then
            targetAlphas[i] = 0.9
            if overlayFrames[i] and not overlayFrames[i]:IsShown() then
                overlayFrames[i]:SetAlpha(0)
                overlayFrames[i]:Show()
            end
        else
            targetAlphas[i] = 0
        end
    end

    for i = 1, 4 do
        local diff = targetAlphas[i] - currentAlphas[i]
        if math.abs(diff) < 0.01 then
            currentAlphas[i] = targetAlphas[i]
        else
            currentAlphas[i] = currentAlphas[i] + (diff * LERP_SPEED * elapsed)
        end

        currentAlphas[i] = math.max(0, math.min(1, currentAlphas[i]))

        if overlayFrames[i] then
            overlayFrames[i]:SetAlpha(currentAlphas[i])

            if currentAlphas[i] < 0.01 and overlayFrames[i]:IsShown() then
                overlayFrames[i]:Hide()
            end
        end
    end
end

function WL.HandleHPTunnelVisionUpdate(elapsed)
    UpdateHPTunnelVision(elapsed)
end

local eventFrame = CreateFrame("Frame", "WanderlustHPTunnelVisionFrame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_DEAD")
eventFrame:RegisterEvent("PLAYER_ALIVE")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_LOGIN" then
        CreateAllOverlayFrames()
    elseif event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" then
    end
end)

WL.RegisterCallback("SETTINGS_CHANGED", function(key, value)
    if key == "hpTunnelVisionEnabled" or key == "ALL" then
        if not value then
            for i = 1, 4 do
                targetAlphas[i] = 0
            end
        end
    end
end)
