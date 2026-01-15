-- Wanderlust - cooking trainer coordinates
local WL = Wanderlust

WL.CookingTrainers = {
    ["Alegorn"] = { zone = "Darnassus", subZone = "Craftsmen's Terrace", faction = "Alliance" },
    ["Cook Ghilm"] = { zone = "Dun Morogh", subZone = "", faction = "Alliance" },
    ["Gremlock Pilsnor"] = { zone = "Dun Morogh", subZone = "Kharanos", faction = "Alliance" },
    ["Daryl Riknussun"] = { zone = "Ironforge", subZone = "The Great Forge", faction = "Alliance" },
    ["Crystal Boughman"] = { zone = "Redridge Mountains", subZone = "Lakeshire", faction = "Alliance" },
    ["Stephen Ryback"] = { zone = "Stormwind City", subZone = "Trade District", faction = "Alliance" },

    ["Zamja"] = { zone = "Orgrimmar", subZone = "Valley of Honor", faction = "Horde" },
    ["Aska Mistrunner"] = { zone = "Thunder Bluff", subZone = "Middle Rise", faction = "Horde" },
    ["Eunice Burch"] = { zone = "Undercity", subZone = "Trade Quarter", faction = "Horde" },


}

function WL.IsCookingTrainer(npcName)
    if not npcName then return false end
    return WL.CookingTrainers[npcName] ~= nil
end

function WL.GetCookingTrainerInfo(npcName)
    return WL.CookingTrainers[npcName]
end

function WL.GetFactionCookingTrainers()
    local faction = UnitFactionGroup("player")
    local trainers = {}
    for name, info in pairs(WL.CookingTrainers) do
        if info.faction == faction or info.faction == "Neutral" then
            trainers[name] = info
        end
    end
    return trainers
end

local cookingFrame = CreateFrame("Frame")
cookingFrame:RegisterEvent("GOSSIP_SHOW")
cookingFrame:RegisterEvent("TRAINER_SHOW")

cookingFrame:SetScript("OnEvent", function(self, event)
    local targetName = UnitName("npc")
    if not targetName then return end

    if WL.IsCookingTrainer(targetName) then
        local messages = {}

        if WL.GetHunger and WL.ResetHungerFromTrainer then
            local currentHunger = WL.GetHunger()
            if currentHunger > 0 then
                WL.ResetHungerFromTrainer()
                table.insert(messages, "|cff00FF00Hunger fully satisfied!|r")
                WL.Debug("Hunger reset by Cooking trainer: " .. targetName, "hunger")
                if WL.GetSetting("playSoundHungerRelief") and WL.GetSetting("hungerEnabled") and WL.IsPlayerEligible() then
                    PlaySoundFile("Interface\\AddOns\\Wanderlust\\assets\\hungerrelief.wav", "SFX")
                end
            end
        end

        if WL.GetThirst and WL.ResetThirstFromTrainer then
            local currentThirst = WL.GetThirst()
            if currentThirst > 0 then
                WL.ResetThirstFromTrainer()
                table.insert(messages, "|cff66CCFFThirst quenched!|r")
                WL.Debug("Thirst reset by Cooking trainer: " .. targetName, "thirst")
                if WL.GetSetting("playSoundThirstRelief") and WL.GetSetting("thirstEnabled") and WL.IsPlayerEligible() then
                    PlaySoundFile("Interface\\AddOns\\Wanderlust\\assets\\hungerrelief.wav", "SFX")
                end
            end
        end

        if #messages > 0 then
            print("|cff88CCFFWanderlust:|r " .. targetName .. " shares a hearty meal with you. " .. table.concat(messages, " "))
        end
    end
end)
