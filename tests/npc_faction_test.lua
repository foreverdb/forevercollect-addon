-- Run: luajit tests/npc_faction_test.lua (or lua5.1)
local stubFrame = setmetatable({}, { __index = function() return function() end end })
CreateFrame = function() return stubFrame end
WorldFrame = {}

local addon = {}
function addon:RegisterEvent() end

local function load(path)
    local chunk = assert(loadfile(path))
    chunk("ForeverCollect", addon)
end
load("Core/Util.lua")
load("Core/Database.lua")
load("Modules/NPCs.lua")

local function check(name, condition)
    if not condition then
        error("FAIL: " .. name, 2)
    end
    print("ok - " .. name)
end

local group
UnitGUID = function() return "Creature-0-0-0-0-248196-0" end
UnitName = function() return "Apothecary Durelle" end
UnitCreatureID = function() return 248196 end
UnitFactionGroup = function() return group, group end

group = "Horde"
check("Horde NPC", addon.GetNPC("npc", "merchant", "merchant").factionGroup == "Horde")
group = "Alliance"
check("Alliance NPC", addon.GetNPC("npc", "merchant", "merchant").factionGroup == "Alliance")
group = nil
check("neutral NPC", addon.GetNPC("npc", "merchant", "merchant").factionGroup == "Neutral")
UnitFactionGroup = nil
check("no API, no field", addon.GetNPC("npc", "merchant", "merchant").factionGroup == nil)
