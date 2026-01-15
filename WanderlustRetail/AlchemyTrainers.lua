-- Wanderlust - alchemy trainer coordinates
local WL = Wanderlust

WL.AlchemyTrainers = {
    ["Kylanna"] = { zone = "Ashenvale", x = 50.80, y = 67.00, faction = "Alliance" },
    ["Ainethil"] = { zone = "Darnassus", x = 55.00, y = 23.80, faction = "Alliance" },
    ["Milla Fairancora"] = { zone = "Darnassus", x = 55.20, y = 22.80, faction = "Alliance" },
    ["Sylvanna Forestmoon"] = { zone = "Darnassus", x = 56.20, y = 24.20, faction = "Alliance" },
    ["Alchemist Narett"] = { zone = "Dustwallow Marsh", x = 64.00, y = 47.80, faction = "Alliance" },
    ["Alchemist Mallory"] = { zone = "Elwynn Forest", x = 39.80, y = 48.40, faction = "Alliance" },
    ["Kylanna Windwhisper"] = { zone = "Feralas", x = 32.60, y = 43.80, faction = "Alliance" },
    ["Tally Berryfizz"] = { zone = "Ironforge", x = 66.60, y = 55.20, faction = "Alliance" },
    ["Vosur Brakthel"] = { zone = "Ironforge", x = 66.40, y = 55.20, faction = "Alliance" },
    ["Ghak Healtouch"] = { zone = "Loch Modan", x = 37.00, y = 49.20, faction = "Alliance" },
    ["Lilyssia Nightbreeze"] = { zone = "Stormwind City", x = 46.40, y = 79.20, faction = "Alliance" },
    ["Tel'Athir"] = { zone = "Stormwind City", x = 46.40, y = 79.00, faction = "Alliance" },
    ["Cyndra Kindwhisper"] = { zone = "Teldrassil", x = 57.60, y = 60.60, faction = "Alliance" },

    ["Miao'zan"] = { zone = "Durotar", x = 55.40, y = 74.00, faction = "Horde" },
    ["Serge Hinott"] = { zone = "Hillsbrad Foothills", x = 61.60, y = 19.20, faction = "Horde" },
    ["Whuut"] = { zone = "Orgrimmar", x = 55.80, y = 33.20, faction = "Horde" },
    ["Yelmak"] = { zone = "Orgrimmar", x = 56.60, y = 33.20, faction = "Horde" },
    ["Rogvar"] = { zone = "Swamp of Sorrows", x = 48.40, y = 55.60, faction = "Horde" },
    ["Bena Winterhoof"] = { zone = "Thunder Bluff", x = 46.80, y = 33.60, faction = "Horde" },
    ["Kray"] = { zone = "Thunder Bluff", x = 47.00, y = 34.20, faction = "Horde" },
    ["Carolai Anise"] = { zone = "Tirisfal Glades", x = 59.40, y = 52.20, faction = "Horde" },
    ["Doctor Herbert Halsey"] = { zone = "Undercity", x = 47.60, y = 73.00, faction = "Horde" },
    ["Doctor Marsh"] = { zone = "Undercity", x = 51.40, y = 74.20, faction = "Horde" },
    ["Doctor Martin Felben"] = { zone = "Undercity", x = 46.60, y = 74.40, faction = "Horde" },

    ["Jaxin Chong"] = { zone = "Stranglethorn Vale", x = 28.00, y = 78.00, faction = "Neutral" },

}

function WL.IsAlchemyTrainer(npcName)
    if not npcName then return false end
    return WL.AlchemyTrainers[npcName] ~= nil
end

function WL.GetAlchemyTrainerInfo(npcName)
    return WL.AlchemyTrainers[npcName]
end

function WL.GetFactionAlchemyTrainers()
    local faction = UnitFactionGroup("player")
    local list = {}
    for name, info in pairs(WL.AlchemyTrainers) do
        if info.faction == faction or info.faction == "Neutral" then
            list[name] = info
        end
    end
    return list
end
