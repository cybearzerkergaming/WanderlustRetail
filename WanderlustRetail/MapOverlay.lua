-- Wanderlust - world map pins
local WL = Wanderlust
local ADDON_PATH = (WL and WL.ASSET_PATH) or "Interface\\AddOns\\Wanderlust\\"
local ipairs = ipairs
local type = type

local firePinPool = {}
local innPinPool = {}
local trainerPinPool = {}
local cookingPinPool = {}
local activeFirePins = {}
local activeInnPins = {}
local activeTrainerPins = {}
local activeCookingPins = {}
local MAP_PIN_SIZE = 16
local INN_PIN_SIZE = 12

local FIRE_ICON = ADDON_PATH .. "assets\fireicon"
local INN_ICON = ADDON_PATH .. "assets\exhaustionicon"
local TRAINER_ICON = ADDON_PATH .. "assets\anguishicon"
local COOKING_ICON = ADDON_PATH .. "assets\hungericon"
local PIN_COLOR_NORMAL = 0.1
local PIN_COLOR_HOVER = 1.0
local PIN_ALPHA_NORMAL = 1.0

local FACTION_ALLIANCE = "A"
local FACTION_HORDE = "H"
local FACTION_NEUTRAL = "N"

local function GetPlayerFaction()
    local faction = UnitFactionGroup("player")
    if faction == "Alliance" then
        return FACTION_ALLIANCE
    end
    if faction == "Horde" then
        return FACTION_HORDE
    end
    return FACTION_NEUTRAL
end

local function ShouldShowForFaction(locationFaction, playerFaction)
    if not locationFaction or locationFaction == FACTION_NEUTRAL then
        return true
    end
    return locationFaction == playerFaction
end

local INN_LOCATIONS = {
    ["Arathi Highlands"] = {{
        {
            x = 73.80,
            y = 32.60,
            name = "Innkeeper Adegwa",
            subZone = "Hammerfall",
            f = "H"
        }
    }},
    ["Ashenvale"] = {{
        {
            x = 74.00,
            y = 60.60,
            name = "Innkeeper Kaylisk",
            subZone = "",
            f = "H"
        },
        {
            x = 37.00,
            y = 49.20,
            name = "Innkeeper Kimlya",
            subZone = "",
            f = "A"
        }
    }},
    ["Badlands"] = {{
        {
            x = 2.80,
            y = 45.80,
            name = "Innkeeper Shul'kar",
            subZone = "",
            f = "H"
        }
    }},
    ["Darkshore"] = {{
        {
            x = 37.00,
            y = 44.00,
            name = "Innkeeper Shaussiy",
            subZone = "",
            f = "A"
        }
    }},
    ["Darnassus"] = {{
        {
            x = 67.20,
            y = 15.80,
            name = "Innkeeper Saelienne",
            subZone = "Craftsmen's Terrace",
            f = "A"
        }
    }},
    ["Desolace"] = {{
        {
            x = 66.20,
            y = 6.60,
            name = "Innkeeper Lyshaerya",
            subZone = "",
            f = "A"
        },
        {
            x = 24.00,
            y = 68.20,
            name = "Innkeeper Sikewa",
            subZone = "",
            f = "H"
        }
    }},
    ["Dun Morogh"] = {{
        {
            x = 47.40,
            y = 52.40,
            name = "Innkeeper Belm",
            subZone = "",
            f = "A"
        }
    }},
    ["Durotar"] = {{
        {
            x = 51.60,
            y = 41.60,
            name = "Innkeeper Grosk",
            subZone = "Razor Hill",
            f = "H"
        }
    }},
    ["Duskwood"] = {{
        {
            x = 73.80,
            y = 44.40,
            name = "Innkeeper Trelayne",
            subZone = "",
            f = "A"
        }
    }},
    ["Dustwallow Marsh"] = {{
        {
            x = 66.60,
            y = 45.20,
            name = "Innkeeper Janene",
            subZone = "",
            f = "A"
        }
    }},
    ["Elwynn Forest"] = {{
        {
            x = 43.80,
            y = 65.80,
            name = "Innkeeper Farley",
            subZone = "Goldshire",
            f = "A"
        }
    }},
    ["Feralas"] = {{
        {
            x = 74.80,
            y = 45.00,
            name = "Innkeeper Greul",
            subZone = "",
            f = "H"
        },
        {
            x = 31.00,
            y = 43.40,
            name = "Innkeeper Shyria",
            subZone = "",
            f = "A"
        }
    }},
    ["Hillsbrad Foothills"] = {{
        {
            x = 51.20,
            y = 58.80,
            name = "Innkeeper Anderson",
            subZone = "",
            f = "A"
        },
        {
            x = 62.60,
            y = 19.00,
            name = "Innkeeper Shay",
            subZone = "Tarren Mill",
            f = "H"
        }
    }},
    ["Ironforge"] = {{
        {
            x = 18.60,
            y = 51.40,
            name = "Innkeeper Firebrew",
            subZone = "The Commons",
            f = "A"
        }
    }},
    ["Loch Modan"] = {{
        {
            x = 35.40,
            y = 48.40,
            name = "Innkeeper Hearthstove",
            subZone = "",
            f = "A"
        }
    }},
    ["Mulgore"] = {{
        {
            x = 46.60,
            y = 61.00,
            name = "Innkeeper Kauth",
            subZone = "",
            f = "H"
        }
    }},
    ["Orgrimmar"] = {{
        {
            x = 54.00,
            y = 68.60,
            name = "Innkeeper Gryshka",
            subZone = "Valley of Strength",
            f = "H"
        }
    }},
    ["Redridge Mountains"] = {{
        {
            x = 26.80,
            y = 44.60,
            name = "Innkeeper Brianna",
            subZone = "Lakeshire",
            f = "A"
        }
    }},
    ["Silithus"] = {{
        {
            x = 51.80,
            y = 39.00,
            name = "Calandrath",
            subZone = "Cenarion Hold",
            f = "N"
        }
    }},
    ["Silverpine Forest"] = {{
        {
            x = 43.20,
            y = 41.20,
            name = "Innkeeper Bates",
            subZone = "",
            f = "H"
        }
    }},
    ["Stonetalon Mountains"] = {{
        {
            x = 35.60,
            y = 5.80,
            name = "Innkeeper Faralia",
            subZone = "",
            f = "A"
        },
        {
            x = 47.40,
            y = 62.00,
            name = "Innkeeper Jayka",
            subZone = "Sun Rock Retreat",
            f = "H"
        }
    }},
    ["Stormwind City"] = {{
        {
            x = 52.60,
            y = 65.60,
            name = "Innkeeper Allison",
            subZone = "Trade District",
            f = "A"
        }
    }},
    ["Stranglethorn Vale"] = {{
        {
            x = 27.00,
            y = 77.20,
            name = "Innkeeper Skindle",
            subZone = "",
            f = "N"
        },
        {
            x = 31.40,
            y = 29.60,
            name = "Innkeeper Thulbek",
            subZone = "Grom'gol Base Camp",
            f = "H"
        }
    }},
    ["Swamp of Sorrows"] = {{
        {
            x = 45.00,
            y = 56.60,
            name = "Innkeeper Karakul",
            subZone = "",
            f = "H"
        }
    }},
    ["Tanaris"] = {{
        {
            x = 52.40,
            y = 27.80,
            name = "Innkeeper Fizzgrimble",
            subZone = "Gadgetzan",
            f = "N"
        }
    }},
    ["Teldrassil"] = {{
        {
            x = 55.60,
            y = 59.80,
            name = "Innkeeper Keldamyr",
            subZone = "Dolanaar",
            f = "A"
        }
    }},
    ["The Barrens"] = {{
        {
            x = 52.00,
            y = 29.80,
            name = "Innkeeper Boorand Plainswind",
            subZone = "Camp Taurajo",
            f = "H"
        },
        {
            x = 45.60,
            y = 59.00,
            name = "Innkeeper Byula",
            subZone = "",
            f = "H"
        },
        {
            x = 62.00,
            y = 39.40,
            name = "Innkeeper Wiley",
            subZone = "",
            f = "N"
        }
    }},
    ["The Hinterlands"] = {{
        {
            x = 13.80,
            y = 41.60,
            name = "Innkeeper Thulfram",
            subZone = "",
            f = "A"
        },
        {
            x = 78.20,
            y = 81.20,
            name = "Lard",
            subZone = "",
            f = "H"
        }
    }},
    ["Thousand Needles"] = {{
        {
            x = 46.00,
            y = 51.40,
            name = "Innkeeper Abeqwa",
            subZone = "Freewind Post",
            f = "H"
        }
    }},
    ["Thunder Bluff"] = {{
        {
            x = 45.80,
            y = 64.40,
            name = "Innkeeper Pala",
            subZone = "Middle Rise",
            f = "H"
        }
    }},
    ["Tirisfal Glades"] = {{
        {
            x = 61.60,
            y = 52.00,
            name = "Innkeeper Renee",
            subZone = "Brill",
            f = "H"
        }
    }},
    ["Undercity"] = {{
        {
            x = 67.60,
            y = 38.20,
            name = "Innkeeper Norman",
            subZone = "Trade Quarter",
            f = "H"
        }
    }},
    ["Westfall"] = {{
        {
            x = 52.80,
            y = 53.60,
            name = "Innkeeper Heather",
            subZone = "",
            f = "A"
        }
    }},
    ["Wetlands"] = {{
        {
            x = 10.60,
            y = 60.80,
            name = "Innkeeper Helbrek",
            subZone = "",
            f = "A"
        }
    }},
    ["Winterspring"] = {{
        {
            x = 61.20,
            y = 38.80,
            name = "Innkeeper Vizzie",
            subZone = "",
            f = "N"
        }
    }},

}

local TRAINER_LOCATIONS = {
    ["Darnassus"] = {{
        {
            x = 51.60,
            y = 12.60,
            name = "Dannelor",
            subZone = "Craftsmen's Terrace",
            f = "A"
        }
    }},
    ["Dun Morogh"] = {{
        {
            x = 47.20,
            y = 52.65,
            name = "Thamner Pol",
            subZone = "Kharanos",
            f = "A"
        }
    }},
    ["Durotar"] = {{
        {
            x = 54.00,
            y = 42.00,
            name = "Rawrk",
            subZone = "Razor Hill",
            f = "H"
        }
    }},
    ["Dustwallow Marsh"] = {{
        {
            x = 67.76,
            y = 48.97,
            name = "Doctor Gustaf VanHowzen",
            subZone = "Theramore Isle",
            f = "A"
        }
    }},
    ["Arathi Highlands"] = {{
        {
            x = 73.41,
            y = 36.89,
            name = "Doctor Gregory Victor",
            subZone = "Hammerfall",
            f = "H"
        }
    }},
    ["Elwynn Forest"] = {{
        {
            x = 43.40,
            y = 65.65,
            name = "Michelle Belle",
            subZone = "Goldshire",
            f = "A"
        }
    }},
    ["Ironforge"] = {{
        {
            x = 54.80,
            y = 58.60,
            name = "Nissa Firestone",
            subZone = "The Great Forge",
            f = "A"
        }
    }},
    ["Mulgore"] = {{
        {
            x = 46.80,
            y = 60.80,
            name = "Vira Younghoof",
            subZone = "Bloodhoof Village",
            f = "H"
        }
    }},
    ["Orgrimmar"] = {{
        {
            x = 34.00,
            y = 84.40,
            name = "Arnok",
            subZone = "Valley of Spirits",
            f = "H"
        }
    }},
    ["Stormwind City"] = {{
        {
            x = 42.80,
            y = 26.40,
            name = "Shaina Fuller",
            subZone = "Cathedral Square",
            f = "A"
        }
    }},
    ["Teldrassil"] = {{
        {
            x = 55.20,
            y = 56.80,
            name = "Byancie",
            subZone = "Dolanaar",
            f = "A"
        }
    }},
    ["Thunder Bluff"] = {{
        {
            x = 29.40,
            y = 21.40,
            name = "Pand Stonebinder",
            subZone = "Spirit Rise",
            f = "H"
        }
    }},
    ["Tirisfal Glades"] = {{
        {
            x = 61.80,
            y = 52.80,
            name = "Nurse Neela",
            subZone = "Brill",
            f = "H"
        }
    }},
    ["Undercity"] = {{
        {
            x = 73.40,
            y = 55.60,
            name = "Mary Edras",
            subZone = "The Rogues' Quarter",
            f = "H"
        }
    }},
    ["Wetlands"] = {{
        {
            x = 10.80,
            y = 61.20,
            name = "Fremal Doohickey",
            subZone = "Menethil Harbor",
            f = "A"
        }
    }},

}

local COOKING_LOCATIONS = {
    ["Darnassus"] = {{
        {
            x = 49.00,
            y = 21.20,
            name = "Alegorn",
            subZone = "Craftsmen's Terrace",
            f = "A"
        }
    }},
    ["Dun Morogh"] = {{
        {
            x = 68.40,
            y = 54.40,
            name = "Cook Ghilm",
            subZone = "",
            f = "A"
        },
        {
            x = 47.60,
            y = 52.40,
            name = "Gremlock Pilsnor",
            subZone = "Kharanos",
            f = "A"
        }
    }},
    ["Ironforge"] = {{
        {
            x = 60.00,
            y = 36.80,
            name = "Daryl Riknussun",
            subZone = "The Great Forge",
            f = "A"
        }
    }},
    ["Orgrimmar"] = {{
        {
            x = 57.40,
            y = 53.60,
            name = "Zamja",
            subZone = "Valley of Honor",
            f = "H"
        }
    }},
    ["Redridge Mountains"] = {{
        {
            x = 22.80,
            y = 43.60,
            name = "Crystal Boughman",
            subZone = "Lakeshire",
            f = "A"
        }
    }},
    ["Stormwind City"] = {{
        {
            x = 75.60,
            y = 37.00,
            name = "Stephen Ryback",
            subZone = "Trade District",
            f = "A"
        }
    }},
    ["Thunder Bluff"] = {{
        {
            x = 51.00,
            y = 52.80,
            name = "Aska Mistrunner",
            subZone = "Middle Rise",
            f = "H"
        }
    }},
    ["Undercity"] = {{
        {
            x = 62.20,
            y = 44.60,
            name = "Eunice Burch",
            subZone = "Trade Quarter",
            f = "H"
        }
    }},

}

local function CreateFirePin()
    local pin = CreateFrame("Frame", nil, WorldMapFrame:GetCanvas())
    pin:SetSize(MAP_PIN_SIZE, MAP_PIN_SIZE)
    pin:SetFrameStrata("HIGH")
    pin:SetFrameLevel(2000)
    pin:SetHitRectInsets(4, 4, 4, 4)

    local icon = pin:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(FIRE_ICON)
    icon:SetVertexColor(PIN_COLOR_NORMAL, PIN_COLOR_NORMAL, PIN_COLOR_NORMAL, PIN_ALPHA_NORMAL)
    pin.icon = icon

    local glow = pin:CreateTexture(nil, "BACKGROUND")
    glow:SetSize(MAP_PIN_SIZE + 8, MAP_PIN_SIZE + 8)
    glow:SetPoint("CENTER")
    glow:SetTexture("Interface\\GLUES\\Models\\UI_MainMenu\\swordglow")
    glow:SetVertexColor(1.0, 0.5, 0.1, 0.3)
    glow:SetBlendMode("ADD")
    pin.glow = glow

    pin:EnableMouse(true)
    pin:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Campfire", 1, 0.6, 0.2)
        if self.pinData then
            if self.pinData.subZone and self.pinData.subZone ~= "" then
                GameTooltip:AddLine(self.pinData.subZone, 1, 1, 1)
            end
            if self.pinData.description and self.pinData.description ~= "" and self.pinData.description ~= "fire" then
                GameTooltip:AddLine(self.pinData.description, 0.7, 0.7, 0.7)
            end
            if self.pinData.noMount then
                GameTooltip:AddLine("Indoor/No Mount", 0.8, 0.4, 0.4)
            end
        end
        GameTooltip:Show()
        self.icon:SetVertexColor(PIN_COLOR_HOVER, PIN_COLOR_HOVER, PIN_COLOR_HOVER, 1.0)
    end)
    pin:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        self.icon:SetVertexColor(PIN_COLOR_NORMAL, PIN_COLOR_NORMAL, PIN_COLOR_NORMAL, PIN_ALPHA_NORMAL)
    end)

    pin:Hide()
    return pin
end

local function CreateInnPin()
    local pin = CreateFrame("Frame", nil, WorldMapFrame:GetCanvas())
    pin:SetSize(INN_PIN_SIZE, INN_PIN_SIZE)
    pin:SetFrameStrata("HIGH")
    pin:SetFrameLevel(2001)
    pin:SetHitRectInsets(3, 3, 3, 3)

    local icon = pin:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(INN_ICON)
    icon:SetVertexColor(PIN_COLOR_NORMAL, PIN_COLOR_NORMAL, PIN_COLOR_NORMAL, PIN_ALPHA_NORMAL)
    pin.icon = icon

    local glow = pin:CreateTexture(nil, "BACKGROUND")
    glow:SetSize(INN_PIN_SIZE + 6, INN_PIN_SIZE + 6)
    glow:SetPoint("CENTER")
    glow:SetTexture("Interface\\GLUES\\Models\\UI_MainMenu\\swordglow")
    glow:SetVertexColor(0.9, 0.3, 0.3, 0.3)
    glow:SetBlendMode("ADD")
    pin.glow = glow

    pin:EnableMouse(true)
    pin:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Innkeeper", 0.9, 0.3, 0.3)
        if self.pinData then
            GameTooltip:AddLine(self.pinData.name, 1, 1, 1)
            if self.pinData.subZone and self.pinData.subZone ~= "" then
                GameTooltip:AddLine(self.pinData.subZone, 0.7, 0.7, 0.7)
            end
        end
        GameTooltip:AddLine("Heals Anguish", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Reduces Hunger", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Reduces Thirst", 0.7, 0.7, 0.7)
        GameTooltip:Show()
        self.icon:SetVertexColor(PIN_COLOR_HOVER, PIN_COLOR_HOVER, PIN_COLOR_HOVER, 1.0)
    end)
    pin:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        self.icon:SetVertexColor(PIN_COLOR_NORMAL, PIN_COLOR_NORMAL, PIN_COLOR_NORMAL, PIN_ALPHA_NORMAL)
    end)

    pin:Hide()
    return pin
end

local function CreateTrainerPin()
    local pin = CreateFrame("Frame", nil, WorldMapFrame:GetCanvas())
    pin:SetSize(MAP_PIN_SIZE, MAP_PIN_SIZE)
    pin:SetFrameStrata("HIGH")
    pin:SetFrameLevel(2002)
    pin:SetHitRectInsets(4, 4, 4, 4)

    local icon = pin:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(TRAINER_ICON)
    icon:SetVertexColor(PIN_COLOR_NORMAL, PIN_COLOR_NORMAL, PIN_COLOR_NORMAL, PIN_ALPHA_NORMAL)
    pin.icon = icon

    local glow = pin:CreateTexture(nil, "BACKGROUND")
    glow:SetSize(MAP_PIN_SIZE + 8, MAP_PIN_SIZE + 8)
    glow:SetPoint("CENTER")
    glow:SetTexture("Interface\\GLUES\\Models\\UI_MainMenu\\swordglow")
    glow:SetVertexColor(0.8, 0.2, 0.2, 0.3)
    glow:SetBlendMode("ADD")
    pin.glow = glow

    pin:EnableMouse(true)
    pin:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("First Aid Trainer", 0.8, 0.2, 0.2)
        if self.pinData then
            GameTooltip:AddLine(self.pinData.name, 1, 1, 1)
            if self.pinData.subZone and self.pinData.subZone ~= "" then
                GameTooltip:AddLine(self.pinData.subZone, 0.7, 0.7, 0.7)
            end
        end
        GameTooltip:Show()
        self.icon:SetVertexColor(PIN_COLOR_HOVER, PIN_COLOR_HOVER, PIN_COLOR_HOVER, 1.0)
    end)
    pin:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        self.icon:SetVertexColor(PIN_COLOR_NORMAL, PIN_COLOR_NORMAL, PIN_COLOR_NORMAL, PIN_ALPHA_NORMAL)
    end)

    pin:Hide()
    return pin
end

local function CreateCookingPin()
    local pin = CreateFrame("Frame", nil, WorldMapFrame:GetCanvas())
    pin:SetSize(MAP_PIN_SIZE, MAP_PIN_SIZE)
    pin:SetFrameStrata("HIGH")
    pin:SetFrameLevel(2003)
    pin:SetHitRectInsets(4, 4, 4, 4)

    local icon = pin:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(COOKING_ICON)
    icon:SetVertexColor(PIN_COLOR_NORMAL, PIN_COLOR_NORMAL, PIN_COLOR_NORMAL, PIN_ALPHA_NORMAL)
    pin.icon = icon

    local glow = pin:CreateTexture(nil, "BACKGROUND")
    glow:SetSize(MAP_PIN_SIZE + 8, MAP_PIN_SIZE + 8)
    glow:SetPoint("CENTER")
    glow:SetTexture("Interface\\GLUES\\Models\\UI_MainMenu\\swordglow")
    glow:SetVertexColor(0.9, 0.6, 0.2, 0.3)
    glow:SetBlendMode("ADD")
    pin.glow = glow

    pin:EnableMouse(true)
    pin:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Cooking Trainer", 0.9, 0.6, 0.2)
        if self.pinData then
            GameTooltip:AddLine(self.pinData.name, 1, 1, 1)
            if self.pinData.subZone and self.pinData.subZone ~= "" then
                GameTooltip:AddLine(self.pinData.subZone, 0.7, 0.7, 0.7)
            end
        end
        GameTooltip:AddLine("Reduces Hunger", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Reduces Thirst", 0.7, 0.7, 0.7)
        GameTooltip:Show()
        self.icon:SetVertexColor(PIN_COLOR_HOVER, PIN_COLOR_HOVER, PIN_COLOR_HOVER, 1.0)
    end)
    pin:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        self.icon:SetVertexColor(PIN_COLOR_NORMAL, PIN_COLOR_NORMAL, PIN_COLOR_NORMAL, PIN_ALPHA_NORMAL)
    end)

    pin:Hide()
    return pin
end

local function ResetPinAppearance(pin)
    if pin and pin.icon then
        pin.icon:SetVertexColor(PIN_COLOR_NORMAL, PIN_COLOR_NORMAL, PIN_COLOR_NORMAL, PIN_ALPHA_NORMAL)
    end
end

local function AcquireFirePin()
    local pin = table.remove(firePinPool)
    if not pin then
        pin = CreateFirePin()
    end
    ResetPinAppearance(pin)
    return pin
end

local function ReleaseFirePin(pin)
    pin:Hide()
    pin:ClearAllPoints()
    table.insert(firePinPool, pin)
end

local function AcquireInnPin()
    local pin = table.remove(innPinPool)
    if not pin then
        pin = CreateInnPin()
    end
    ResetPinAppearance(pin)
    return pin
end

local function ReleaseInnPin(pin)
    pin:Hide()
    pin:ClearAllPoints()
    table.insert(innPinPool, pin)
end

local function AcquireTrainerPin()
    local pin = table.remove(trainerPinPool)
    if not pin then
        pin = CreateTrainerPin()
    end
    ResetPinAppearance(pin)
    return pin
end

local function ReleaseTrainerPin(pin)
    pin:Hide()
    pin:ClearAllPoints()
    table.insert(trainerPinPool, pin)
end

local function AcquireCookingPin()
    local pin = table.remove(cookingPinPool)
    if not pin then
        pin = CreateCookingPin()
    end
    ResetPinAppearance(pin)
    return pin
end

local function ReleaseCookingPin(pin)
    pin:Hide()
    pin:ClearAllPoints()
    table.insert(cookingPinPool, pin)
end

local function ClearAllPins()
    for _, pin in ipairs(activeFirePins) do
        ReleaseFirePin(pin)
    end
    activeFirePins = {}

    for _, pin in ipairs(activeInnPins) do
        ReleaseInnPin(pin)
    end
    activeInnPins = {}

    for _, pin in ipairs(activeTrainerPins) do
        ReleaseTrainerPin(pin)
    end
    activeTrainerPins = {}

    for _, pin in ipairs(activeCookingPins) do
        ReleaseCookingPin(pin)
    end
    activeCookingPins = {}
end

local function GetNormalizedCoord(coord)
    if type(coord) ~= "number" then
        return nil
    end
    return coord / 100
end

local function AddPinsForLocations(locations, acquireFunc, releaseFunc, activeList, canvas, canvasWidth, canvasHeight, playerFaction)
    if not locations then
        return
    end
    for _, entry in ipairs(locations) do
        if entry and entry.x and entry.y then
            if ShouldShowForFaction(entry.f, playerFaction) then
                local pin = acquireFunc()
                pin.pinData = entry
                local fx = entry.x * 0.01
                local fy = entry.y * 0.01
                if fx and fy then
                    pin:SetParent(canvas)
                    pin:SetPoint("CENTER", canvas, "TOPLEFT", fx * canvasWidth, -fy * canvasHeight)
                    pin:Show()
                    activeList[#activeList + 1] = pin
                else
                    releaseFunc(pin)
                end
            end
        elseif type(entry) == "table" and entry[1] and entry[1].x and entry[1].y then
            for _, nested in ipairs(entry) do
                if nested and nested.x and nested.y and ShouldShowForFaction(nested.f, playerFaction) then
                    local pin = acquireFunc()
                    pin.pinData = nested
                    local fx = nested.x * 0.01
                    local fy = nested.y * 0.01
                    if fx and fy then
                        pin:SetParent(canvas)
                        pin:SetPoint("CENTER", canvas, "TOPLEFT", fx * canvasWidth, -fy * canvasHeight)
                        pin:Show()
                        activeList[#activeList + 1] = pin
                    else
                        releaseFunc(pin)
                    end
                end
            end
        end
    end
end


local function UpdateMapPins()
    ClearAllPins()

    if not WL.GetSetting("showSurvivalIcons") then
        return
    end

    if not WorldMapFrame:IsShown() then
        return
    end

    local mapID = WorldMapFrame:GetMapID()
    if not mapID then
        return
    end

    local mapInfo = C_Map.GetMapInfo(mapID)
    if not mapInfo then
        return
    end

    local zoneName = mapInfo.name
    if not zoneName then
        return
    end

    local canvas = WorldMapFrame:GetCanvas()
    local canvasWidth = canvas:GetWidth()
    local canvasHeight = canvas:GetHeight()

    if WL.GetFireLocations then
        local fires = WL.GetFireLocations(zoneName)
        if fires then
            for _, fire in ipairs(fires) do
                local pin = AcquireFirePin()
                pin.pinData = fire
                local fx = GetNormalizedCoord(fire.x)
                local fy = GetNormalizedCoord(fire.y)
                if fx and fy then
                    pin:SetParent(canvas)
                    pin:SetPoint("CENTER", canvas, "TOPLEFT", fx * canvasWidth, -fy * canvasHeight)
                    pin:Show()
                    activeFirePins[#activeFirePins + 1] = pin
                else
                    ReleaseFirePin(pin)
                end
            end
        end
    end

    local totalPins = #activeFirePins
    if totalPins > 0 and WL.GetSetting("debugEnabled") then
        WL.Debug("Showing " .. totalPins .. " survival pins for " .. zoneName .. " (Fires: " .. #activeFirePins .. ")",
            "general")
    end
end

local mapCheckbox = nil
local UpdateCheckboxVisibility
local function UpdateCheckboxAnchor()
    if not mapCheckbox then
        return
    end
    local anchor = WorldMapFrame and WorldMapFrame.BorderFrame
    if not anchor or not anchor:IsShown() then
        anchor = WorldMapFrame
    end
    if not anchor then
        return
    end
    mapCheckbox:ClearAllPoints()
    mapCheckbox:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -60, -2)
end

local function CreateMapCheckbox()
    if mapCheckbox then
        return
    end

    mapCheckbox = CreateFrame("CheckButton", "WanderlustSurvivalIconsCheckbox", WorldMapFrame,
        "UICheckButtonTemplate")
    mapCheckbox:SetSize(24, 24)
    mapCheckbox:SetFrameStrata("HIGH")
    mapCheckbox:SetFrameLevel(9999)
    mapCheckbox:EnableMouse(true)
    UpdateCheckboxAnchor()

    mapCheckbox.text = mapCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mapCheckbox.text:SetPoint("RIGHT", mapCheckbox, "LEFT", -2, 0)
    mapCheckbox.text:SetText("Survival Icons")
    mapCheckbox.text:SetTextColor(0.9, 0.7, 0.4)

    mapCheckbox:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        WL.SetSetting("showSurvivalIcons", checked)
        UpdateMapPins()
    end)

    mapCheckbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Survival Icons", 1, 0.8, 0.4)
        GameTooltip:AddLine("Toggle display of campfires on the map.", 1, 1, 1, true)
        GameTooltip:Show()
    end)

    mapCheckbox:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    if UpdateCheckboxVisibility then
        UpdateCheckboxVisibility()
    end
end

UpdateCheckboxVisibility = function()
    if not mapCheckbox then
        return
    end

    local showCheckbox = WL.GetSetting("temperatureEnabled") or WL.GetSetting("exhaustionEnabled")

    if showCheckbox then
        mapCheckbox:Show()
        mapCheckbox:SetChecked(WL.GetSetting("showSurvivalIcons"))
    else
        mapCheckbox:Hide()
    end
end

local overlayFrame = CreateFrame("Frame")
overlayFrame:RegisterEvent("PLAYER_LOGIN")

overlayFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        if WorldMapFrame then
            CreateMapCheckbox()

            WorldMapFrame:HookScript("OnShow", function()
                UpdateCheckboxAnchor()
                UpdateCheckboxVisibility()
                C_Timer.After(0.1, UpdateMapPins)
            end)

            WorldMapFrame:HookScript("OnHide", function()
                ClearAllPins()
            end)

            hooksecurefunc(WorldMapFrame, "OnMapChanged", function()
                UpdateCheckboxAnchor()
                C_Timer.After(0.1, UpdateMapPins)
            end)
        end
    end
end)

WL.UpdateMapPins = UpdateMapPins
WL.UpdateSurvivalIcons = UpdateMapPins
WL.ClearMapPins = ClearAllPins
WL.UpdateMapCheckboxVisibility = UpdateCheckboxVisibility

WL.RegisterCallback("SETTINGS_CHANGED", function(key)
    if key == "showSurvivalIcons" or key == "temperatureEnabled" or key == "exhaustionEnabled" or key == "enabled" or
        key == "ALL" then
        UpdateCheckboxVisibility()
        UpdateMapPins()
    end
end)
