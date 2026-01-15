-- Wanderlust - First Aid trainer coordinates
local WL = Wanderlust

WL.FirstAidTrainers = {
    ["Dannelor"] = { zone = "Darnassus", subZone = "Craftsmen's Terrace", faction = "Alliance" },
    ["Thamner Pol"] = { zone = "Dun Morogh", subZone = "Kharanos", faction = "Alliance" },
    ["Michelle Belle"] = { zone = "Elwynn Forest", subZone = "Goldshire", faction = "Alliance" },
    ["Nissa Firestone"] = { zone = "Ironforge", subZone = "The Great Forge", faction = "Alliance" },
    ["Shaina Fuller"] = { zone = "Stormwind City", subZone = "Cathedral Square", faction = "Alliance" },
    ["Byancie"] = { zone = "Teldrassil", subZone = "Dolanaar", faction = "Alliance" },
    ["Fremal Doohickey"] = { zone = "Wetlands", subZone = "Menethil Harbor", faction = "Alliance" },
    ["Doctor Gustaf VanHowzen"] = { zone = "Dustwallow Marsh", subZone = "Theramore Isle", faction = "Alliance" },

    ["Rawrk"] = { zone = "Durotar", subZone = "Razor Hill", faction = "Horde" },
    ["Vira Younghoof"] = { zone = "Mulgore", subZone = "Bloodhoof Village", faction = "Horde" },
    ["Arnok"] = { zone = "Orgrimmar", subZone = "Valley of Spirits", faction = "Horde" },
    ["Pand Stonebinder"] = { zone = "Thunder Bluff", subZone = "Spirit Rise", faction = "Horde" },
    ["Nurse Neela"] = { zone = "Tirisfal Glades", subZone = "Brill", faction = "Horde" },
    ["Mary Edras"] = { zone = "Undercity", subZone = "The Rogues' Quarter", faction = "Horde" },
    ["Doctor Gregory Victor"] = { zone = "Arathi Highlands", subZone = "Hammerfall", faction = "Horde" },


}

function WL.IsFirstAidTrainer(npcName)
    if not npcName then
        return false
    end
    return WL.FirstAidTrainers[npcName] ~= nil
end

function WL.GetFirstAidTrainerInfo(npcName)
    return WL.FirstAidTrainers[npcName]
end

function WL.GetFactionTrainers()
    local faction = UnitFactionGroup("player")
    local trainers = {}
    for name, info in pairs(WL.FirstAidTrainers) do
        if info.faction == faction then
            trainers[name] = info
        end
    end
    return trainers
end

local trainerFrame = CreateFrame("Frame")
trainerFrame:RegisterEvent("GOSSIP_SHOW")
trainerFrame:RegisterEvent("TRAINER_SHOW")

local lastProcessedTrainer = nil
local lastProcessedTime = 0

trainerFrame:SetScript("OnEvent", function(self, event)
    local targetName = UnitName("npc")
    if not targetName then
        return
    end

    if WL.IsFirstAidTrainer(targetName) then
        local currentTime = GetTime()
        if lastProcessedTrainer == targetName and (currentTime - lastProcessedTime) < 1 then
            return
        end

        if WL.GetAnguish and WL.HealAnguishFully then
            local currentAnguish = WL.GetAnguish()
            if currentAnguish > 0 then
                WL.HealAnguishFully()
                print("|cff88CCFFWanderlust:|r " .. targetName ..
                          " tends to your wounds. |cff00FF00Anguish fully healed!|r")
                WL.Debug("Anguish fully healed by First Aid trainer: " .. targetName, "Anguish")
                if WL.GetSetting("playSoundAnguishRelief") and WL.GetSetting("AnguishEnabled") and WL.IsPlayerEligible() then
                    PlaySoundFile("Interface\\AddOns\\Wanderlust\\assets\\anguishrelief.wav", "SFX")
                end
                lastProcessedTrainer = targetName
                lastProcessedTime = currentTime
            end
        end
    end
end)
