-- Wanderlust - fire logging tool
WanderlustLoggedFires = WanderlustLoggedFires or {}

local OVERLAP_YARDS = 3
local OVERLAP_MAP_UNITS = OVERLAP_YARDS * 0.001
local overlapCheckEnabled = true

local function CanPlayerMount()
    if IsIndoors() then
        return false
    end
    if IsSwimming() then
        return false
    end
    return true
end

local function LogFire(desc, noMount)
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then
        print("|cffFF0000Wanderlust:|r No map ID.")
        return
    end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then
        print("|cffFF0000Wanderlust:|r No position.")
        return
    end

    local zone = GetZoneText()
    local subZone = GetSubZoneText()

    local actualDesc = desc
    if noMount then
        actualDesc = desc
    end
    actualDesc = (actualDesc and actualDesc ~= "") and actualDesc or ((subZone ~= "") and subZone or "fire")

    local newX = pos.x * 100
    local newY = pos.y * 100

    if overlapCheckEnabled and WanderlustLoggedFires[zone] then
        for _, existing in ipairs(WanderlustLoggedFires[zone]) do
            local dx = (existing.x - newX) / 100
            local dy = (existing.y - newY) / 100
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < OVERLAP_MAP_UNITS then
                local distYards = dist / 0.001
                print(string.format("|cffFFAA00Wanderlust:|r Fire already logged %.1f yards away.", distYards))
                return
            end
        end
    end

    local entry = {
        zone = zone,
        subZone = subZone,
        x = math.floor(newX * 100) / 100,
        y = math.floor(newY * 100) / 100,
        description = actualDesc,
        timestamp = date("%Y-%m-%d %H:%M:%S")
    }

    if noMount then
        entry.noMount = true
    end

    if not WanderlustLoggedFires[zone] then
        WanderlustLoggedFires[zone] = {}
    end
    table.insert(WanderlustLoggedFires[zone], entry)

    local mountStatus = ""
    if noMount then
        mountStatus = " |cffFF6600[NO MOUNT]|r"
    elseif not CanPlayerMount() then
        mountStatus = " |cffFFFF00(can't mount here)|r"
    end

    print("|cff00FF00Wanderlust:|r Fire logged!" .. mountStatus)
    print(string.format("  %s (%.2f, %.2f) - %s", zone, entry.x, entry.y, actualDesc))
    print("|cff888888Use /logfire export to view all. /reload to save.|r")
end

local function Export()
    local count = 0
    local zones = {}
    for z in pairs(WanderlustLoggedFires) do
        table.insert(zones, z)
    end
    table.sort(zones)
    print("|cff88CCFF=== Wanderlust Fire Export ===|r")
    print("-- Copy this to FireDB.lua --")
    for _, z in ipairs(zones) do
        local fires = WanderlustLoggedFires[z]
        if #fires > 0 then
            print(string.format('    ["%s"] = {', z))
            for _, f in ipairs(fires) do
                if f.noMount then
                    print(string.format('        { x = %.2f, y = %.2f, description = "%s", noMount = true },', f.x, f.y,
                        f.description or "fire"))
                else
                    print(string.format('        { x = %.2f, y = %.2f, description = "%s" },', f.x, f.y,
                        f.description or "fire"))
                end
                count = count + 1
            end
            print('    },')
        end
    end
    print(string.format("|cff00FF00Total: %d fires|r", count))
end

SLASH_LOGFIRE1 = "/logfire"

SlashCmdList["LOGFIRE"] = function(msg)
    msg = msg or ""
    local cmd = msg:match("^(%S*)") or ""
    local rest = msg:match("^%S*%s*(.*)") or ""
    cmd = string.lower(cmd)

    if cmd == "export" then
        Export()
    elseif cmd == "clear" then
        WanderlustLoggedFires = {}
        print("|cff88CCFFWanderlust:|r Fire log cleared.")
    elseif cmd == "count" then
        local c = 0
        for _, fires in pairs(WanderlustLoggedFires) do
            c = c + #fires
        end
        print(string.format("|cff88CCFFWanderlust:|r %d fires logged.", c))
    elseif cmd == "help" then
        print("|cff88CCFF=== Fire Logger Commands ===|r")
        print("|cffffff00/logfire|r - Log fire at current position")
        print("|cffffff00/logfire <desc>|r - Log with description")
        print("|cffffff00/logfire nomount|r - Log fire as no-mount spot")
        print("|cffffff00/logfire nomount <desc>|r - Log no-mount with description")
        print("|cffffff00/logfire export|r - Show all logged fires")
        print("|cffffff00/logfire count|r - Show fire count")
        print("|cffffff00/logfire clear|r - Clear all logged fires")
        print("|cffffff00/logfire overlap|r - Toggle overlap checking (currently " ..
                  (overlapCheckEnabled and "ON" or "OFF") .. ")")
    elseif cmd == "overlap" then
        overlapCheckEnabled = not overlapCheckEnabled
        print("|cff88CCFFWanderlust:|r Overlap checking " ..
                  (overlapCheckEnabled and "|cff00FF00ON|r" or "|cffFF6600OFF|r"))
    elseif cmd == "nomount" then
        LogFire(rest, true)
    else
        LogFire(msg, false)
    end
end
