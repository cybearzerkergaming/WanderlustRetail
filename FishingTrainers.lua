-- Wanderlust - fishing trainer coordinates
local WL = Wanderlust

WL.FishingTrainers = {
    ["Astaia"] = { zone = "Darnassus", x = 47.60, y = 56.80, faction = "Alliance" },
    ["Paxton Ganter"] = { zone = "Dun Morogh", x = 35.40, y = 40.20, faction = "Alliance" },
    ["Lee Brown"] = { zone = "Elwynn Forest", x = 47.40, y = 62.20, faction = "Alliance" },
    ["Brannock"] = { zone = "Feralas", x = 32.20, y = 41.60, faction = "Alliance" },
    ["Donald Rabonne"] = { zone = "Hillsbrad Foothills", x = 50.60, y = 61.00, faction = "Alliance" },
    ["Grimnur Stonebrand"] = { zone = "Ironforge", x = 48.20, y = 6.60, faction = "Alliance" },
    ["Warg Deepwater"] = { zone = "Loch Modan", x = 40.60, y = 39.60, faction = "Alliance" },
    ["Matthew Hooper"] = { zone = "Redridge Mountains", x = 26.60, y = 51.20, faction = "Alliance" },
    ["Arnold Leland"] = { zone = "Stormwind City", x = 45.80, y = 58.20, faction = "Alliance" },
    ["Androl Oakhand"] = { zone = "Teldrassil", x = 55.80, y = 93.40, faction = "Alliance" },
    ["Harold Riggs"] = { zone = "Wetlands", x = 8.20, y = 58.60, faction = "Alliance" },

    ["Kil'Hiwana"] = { zone = "Ashenvale", x = 10.80, y = 33.60, faction = "Horde" },
    ["Lui'Mala"] = { zone = "Desolace", x = 22.60, y = 72.40, faction = "Horde" },
    ["Lau'Tiki"] = { zone = "Durotar", x = 53.20, y = 81.40, faction = "Horde" },
    ["Uthan Stillwater"] = { zone = "Mulgore", x = 44.40, y = 60.60, faction = "Horde" },
    ["Lumak"] = { zone = "Orgrimmar", x = 69.60, y = 29.40, faction = "Horde" },
    ["Kah Mistrunner"] = { zone = "Thunder Bluff", x = 56.00, y = 46.80, faction = "Horde" },
    ["Clyde Kellen"] = { zone = "Tirisfal Glades", x = 67.20, y = 51.00, faction = "Horde" },
    ["Armand Cromwell"] = { zone = "Undercity", x = 80.80, y = 31.20, faction = "Horde" },

    ["Myizz Luckycatch"] = { zone = "Stranglethorn Vale", x = 27.40, y = 77.00, faction = "Neutral" },

}

function WL.IsFishingTrainer(npcName)
    if not npcName then return false end
    return WL.FishingTrainers[npcName] ~= nil
end

function WL.GetFishingTrainerInfo(npcName)
    return WL.FishingTrainers[npcName]
end

function WL.GetFactionFishingTrainers()
    local faction = UnitFactionGroup("player")
    local list = {}
    for name, info in pairs(WL.FishingTrainers) do
        if info.faction == faction or info.faction == "Neutral" then
            list[name] = info
        end
    end
    return list
end
