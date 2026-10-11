-- Run: luajit tests/npc_merge_test.lua (or lua5.1)
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
load("Modules/NPCs.lua")

local function check(name, condition)
    if not condition then
        error("FAIL: " .. name, 2)
    end
    print("ok - " .. name)
end

-- a quest observation's NPC enters the catalog as a copy
local catalog = { npcs = {} }
local questNPC = { npcID = 7, name = "Marshal", location = { uiMapID = 1, x = 0.1, y = 0.2 } }
local stored = addon.MergeNPC(catalog, questNPC)
check("stored entry is not the caller's table", stored ~= questNPC)
check("nested location is not shared", stored.location ~= questNPC.location)

-- a later interaction updates the catalog entry only
addon.MergeNPC(catalog, { npcID = 7, name = "Marshal", subtitle = "Guard", location = { uiMapID = 1, x = 0.9, y = 0.9 } })
check("catalog entry updated", catalog.npcs[1].location.x == 0.9 and catalog.npcs[1].subtitle == "Guard")
check("observation location unchanged", questNPC.location.x == 0.1)
check("observation subtitle unchanged", questNPC.subtitle == nil)
check("one catalog entry", #catalog.npcs == 1)
