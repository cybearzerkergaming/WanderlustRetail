-- Wanderlust - herbalism trainer coordinates
local WL = Wanderlust

WL.HerbalismTrainers = {
    ["Cylania Rootstalker"] = { zone = "Ashenvale", x = 50.60, y = 67.00, faction = "Alliance" },
    ["Firodren Mooncaller"] = { zone = "Darnassus", x = 48.00, y = 68.40, faction = "Alliance" },
    ["Brant Jasperbloom"] = { zone = "Dustwallow Marsh", x = 64.00, y = 47.60, faction = "Alliance" },
    ["Herbalist Pomeroy"] = { zone = "Elwynn Forest", x = 39.80, y = 48.45, faction = "Alliance" },
    ["Reyna Stonebranch"] = { zone = "Ironforge", x = 55.60, y = 58.80, faction = "Alliance" },
    ["Kali Healtouch"] = { zone = "Loch Modan", x = 36.40, y = 48.40, faction = "Alliance" },
    ["Alma Jainrose"] = { zone = "Redridge Mountains", x = 21.40, y = 45.80, faction = "Alliance" },
    ["Shylamiir"] = { zone = "Stormwind City", x = 15.20, y = 49.80, faction = "Alliance" },
    ["Tannysa"] = { zone = "Stormwind City", x = 44.80, y = 77.00, faction = "Alliance" },
    ["Malorne Bladeleaf"] = { zone = "Teldrassil", x = 57.60, y = 60.65, faction = "Alliance" },
    ["Telurinon Moonshadow"] = { zone = "Wetlands", x = 8.00, y = 55.80, faction = "Alliance" },

    ["Mishiki"] = { zone = "Durotar", x = 55.40, y = 75.00, faction = "Horde" },
    ["Ruw"] = { zone = "Feralas", x = 76.00, y = 43.40, faction = "Horde" },
    ["Aranae Venomblood"] = { zone = "Hillsbrad Foothills", x = 61.60, y = 19.60, faction = "Horde" },
    ["Jandi"] = { zone = "Orgrimmar", x = 55.40, y = 39.60, faction = "Horde" },
    ["Angrun"] = { zone = "Stranglethorn Vale", x = 32.20, y = 27.40, faction = "Horde" },
    ["Komin Winterhoof"] = { zone = "Thunder Bluff", x = 49.80, y = 39.80, faction = "Horde" },
    ["Faruza"] = { zone = "Tirisfal Glades", x = 59.80, y = 52.00, faction = "Horde" },
    ["Martha Alliestar"] = { zone = "Undercity", x = 54.20, y = 49.80, faction = "Horde" },

    ["Malvor"] = { zone = "Moonglade", x = 45.40, y = 47.00, faction = "Neutral" },
    ["Flora Silverwind"] = { zone = "Stranglethorn Vale", x = 27.60, y = 77.80, faction = "Neutral" },

}

function WL.IsHerbalismTrainer(npcName)
    if not npcName then return false end
    return WL.HerbalismTrainers[npcName] ~= nil
end

function WL.GetHerbalismTrainerInfo(npcName)
    return WL.HerbalismTrainers[npcName]
end

function WL.GetFactionHerbalismTrainers()
    local faction = UnitFactionGroup("player")
    local list = {}
    for name, info in pairs(WL.HerbalismTrainers) do
        if info.faction == faction or info.faction == "Neutral" then
            list[name] = info
        end
    end
    return list
end
