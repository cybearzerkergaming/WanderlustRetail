-- Wanderlust - innkeeper coordinates
local WL = Wanderlust
local ASSET_PATH = WL.ASSET_PATH or "Interface\\AddOns\\Wanderlust\\assets\\"
local GetTime = GetTime

WL.Innkeepers = {
    ["Innkeeper Kimlya"] = { zone = "Ashenvale", subZone = "", faction = "Alliance" },
    ["Innkeeper Shaussiy"] = { zone = "Darkshore", subZone = "", faction = "Alliance" },
    ["Innkeeper Saelienne"] = { zone = "Darnassus", subZone = "Craftsmen's Terrace", faction = "Alliance" },
    ["Innkeeper Lyshaerya"] = { zone = "Desolace", subZone = "", faction = "Alliance" },
    ["Innkeeper Belm"] = { zone = "Dun Morogh", subZone = "", faction = "Alliance" },
    ["Innkeeper Trelayne"] = { zone = "Duskwood", subZone = "", faction = "Alliance" },
    ["Innkeeper Janene"] = { zone = "Dustwallow Marsh", subZone = "", faction = "Alliance" },
    ["Innkeeper Farley"] = { zone = "Elwynn Forest", subZone = "Goldshire", faction = "Alliance" },
    ["Innkeeper Shyria"] = { zone = "Feralas", subZone = "", faction = "Alliance" },
    ["Innkeeper Anderson"] = { zone = "Hillsbrad Foothills", subZone = "", faction = "Alliance" },
    ["Innkeeper Firebrew"] = { zone = "Ironforge", subZone = "The Commons", faction = "Alliance" },
    ["Innkeeper Hearthstove"] = { zone = "Loch Modan", subZone = "", faction = "Alliance" },
    ["Innkeeper Brianna"] = { zone = "Redridge Mountains", subZone = "Lakeshire", faction = "Alliance" },
    ["Innkeeper Faralia"] = { zone = "Stonetalon Mountains", subZone = "", faction = "Alliance" },
    ["Innkeeper Allison"] = { zone = "Stormwind City", subZone = "Trade District", faction = "Alliance" },
    ["Innkeeper Keldamyr"] = { zone = "Teldrassil", subZone = "Dolanaar", faction = "Alliance" },
    ["Innkeeper Thulfram"] = { zone = "The Hinterlands", subZone = "", faction = "Alliance" },
    ["Innkeeper Heather"] = { zone = "Westfall", subZone = "", faction = "Alliance" },
    ["Innkeeper Helbrek"] = { zone = "Wetlands", subZone = "", faction = "Alliance" },

    ["Innkeeper Adegwa"] = { zone = "Arathi Highlands", subZone = "Hammerfall", faction = "Horde" },
    ["Innkeeper Kaylisk"] = { zone = "Ashenvale", subZone = "", faction = "Horde" },
    ["Innkeeper Shul'kar"] = { zone = "Badlands", subZone = "", faction = "Horde" },
    ["Innkeeper Sikewa"] = { zone = "Desolace", subZone = "", faction = "Horde" },
    ["Innkeeper Grosk"] = { zone = "Durotar", subZone = "Razor Hill", faction = "Horde" },
    ["Innkeeper Greul"] = { zone = "Feralas", subZone = "", faction = "Horde" },
    ["Innkeeper Shay"] = { zone = "Hillsbrad Foothills", subZone = "Tarren Mill", faction = "Horde" },
    ["Innkeeper Kauth"] = { zone = "Mulgore", subZone = "", faction = "Horde" },
    ["Innkeeper Gryshka"] = { zone = "Orgrimmar", subZone = "Valley of Strength", faction = "Horde" },
    ["Innkeeper Bates"] = { zone = "Silverpine Forest", subZone = "", faction = "Horde" },
    ["Innkeeper Jayka"] = { zone = "Stonetalon Mountains", subZone = "Sun Rock Retreat", faction = "Horde" },
    ["Innkeeper Thulbek"] = { zone = "Stranglethorn Vale", subZone = "Grom'gol Base Camp", faction = "Horde" },
    ["Innkeeper Karakul"] = { zone = "Swamp of Sorrows", subZone = "", faction = "Horde" },
    ["Innkeeper Boorand Plainswind"] = { zone = "The Barrens", subZone = "Crossroads", faction = "Horde" },
    ["Innkeeper Byula"] = { zone = "The Barrens", subZone = "", faction = "Horde" },
    ["Lard"] = { zone = "The Hinterlands", subZone = "", faction = "Horde" },
    ["Innkeeper Abeqwa"] = { zone = "Thousand Needles", subZone = "Freewind Post", faction = "Horde" },
    ["Innkeeper Pala"] = { zone = "Thunder Bluff", subZone = "Middle Rise", faction = "Horde" },
    ["Innkeeper Renee"] = { zone = "Tirisfal Glades", subZone = "Brill", faction = "Horde" },
    ["Innkeeper Norman"] = { zone = "Undercity", subZone = "Trade Quarter", faction = "Horde" },

    ["Calandrath"] = { zone = "Silithus", subZone = "Cenarion Hold", faction = "Neutral" },
    ["Innkeeper Skindle"] = { zone = "Stranglethorn Vale", subZone = "", faction = "Neutral" },
    ["Innkeeper Fizzgrimble"] = { zone = "Tanaris", subZone = "Gadgetzan", faction = "Neutral" },
    ["Innkeeper Wiley"] = { zone = "The Barrens", subZone = "", faction = "Neutral" },
    ["Innkeeper Vizzie"] = { zone = "Winterspring", subZone = "", faction = "Neutral" },

}

function WL.IsInnkeeper(npcName)
    if not npcName then
        return false
    end
    return WL.Innkeepers[npcName] ~= nil
end

function WL.GetInnkeeperInfo(npcName)
    return WL.Innkeepers[npcName]
end

function WL.GetFactionInnkeepers()
    local faction = UnitFactionGroup("player")
    local innkeepers = {}
    for name, info in pairs(WL.Innkeepers) do
        if info.faction == faction or info.faction == "Neutral" then
            innkeepers[name] = info
        end
    end
    return innkeepers
end

local function ResolveInnkeeperName(name)
    if not name then
        return nil
    end
    if WL.IsInnkeeper(name) then
        return name
    end
    local withTitle = "Innkeeper " .. name
    if WL.IsInnkeeper(withTitle) then
        return withTitle
    end
    local stripped = name:gsub("^Innkeeper%s+", "")
    if stripped ~= name and WL.IsInnkeeper(stripped) then
        return stripped
    end
    return name
end

local innkeeperFrame = CreateFrame("Frame")
innkeeperFrame:RegisterEvent("GOSSIP_SHOW")
innkeeperFrame:RegisterEvent("MERCHANT_SHOW")
local lastInnkeeperTrigger = 0
local INNKEEPER_TRIGGER_COOLDOWN = 1.0

innkeeperFrame:SetScript("OnEvent", function(self, event)
    if event ~= "GOSSIP_SHOW" and event ~= "MERCHANT_SHOW" then
        return
    end

    local now = GetTime()
    if now - lastInnkeeperTrigger < INNKEEPER_TRIGGER_COOLDOWN then
        return
    end
    lastInnkeeperTrigger = now

    local targetName = UnitName("npc")
    if not targetName then
        targetName = UnitName("target")
    end

    if not targetName then
        WL.Debug("Innkeeper check: No NPC name found", "Anguish")
        return
    end

    targetName = ResolveInnkeeperName(targetName)
    if not WL.IsInnkeeper(targetName) then
        return
    end

    WL.Debug("Innkeeper check: Interacting with " .. targetName, "Anguish")

    local messages = {}

    if WL.GetSetting("innkeeperHealsAnguish") then
        WL.Debug("Innkeeper recognized: " .. targetName, "Anguish")
        if WL.GetAnguish and WL.ResetAnguish then
            local currentAnguish = WL.GetAnguish()
            WL.Debug("Current Anguish: " .. tostring(currentAnguish), "Anguish")
            if currentAnguish > 15 then
                WL.ResetAnguish()
                table.insert(messages, "|cff00FF00Anguish healed to 85%!|r")
                WL.Debug("Anguish reset by Innkeeper: " .. targetName, "Anguish")
                if WL.GetSetting("playSoundAnguishRelief") and WL.GetSetting("AnguishEnabled") and WL.IsPlayerEligible() then
                    PlaySoundFile(ASSET_PATH .. "anguishrelief.wav", "SFX")
                end
            end
        else
            WL.Debug("Innkeeper: GetAnguish or ResetAnguish not found", "Anguish")
        end
    end

    if WL.GetSetting("innkeeperResetsHunger") then
        if WL.GetHunger and WL.ResetHungerFromInnkeeper then
            local currentHunger = WL.GetHunger()
            if currentHunger > 0 then
                WL.ResetHungerFromInnkeeper()
                table.insert(messages, "|cff00FF00Hunger fully satisfied!|r")
                WL.Debug("Hunger reset by Innkeeper: " .. targetName, "hunger")
            end
        end
    end

    if WL.GetSetting("innkeeperResetsThirst") then
        if WL.GetThirst and WL.ResetThirstFromInnkeeper then
            local currentThirst = WL.GetThirst()
            if currentThirst > 0 then
                WL.ResetThirstFromInnkeeper()
                table.insert(messages, "|cff66CCFF Thirst quenched!|r")
                WL.Debug("Thirst reset by Innkeeper: " .. targetName, "thirst")
            end
        end
    end

    if #messages > 0 then
        print("|cff88CCFFWanderlust:|r " .. targetName .. " provides comfort and rest. " .. table.concat(messages, " "))
    end
end)
