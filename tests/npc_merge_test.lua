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
load("Core/Database.lua")
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

-- trainers show their gossip window first; "trainer" wins the role
local services = { npcs = {} }
addon.MergeNPC(services, { npcID = 5159, name = "Daryl", role = "gossip", interactionTypes = { "gossip" } })
addon.MergeNPC(services, { npcID = 5159, name = "Daryl", role = "trainer", interactionTypes = { "trainer" } })
check("trainer replaces gossip role", services.npcs[1].role == "trainer")
addon.MergeNPC(services, { npcID = 5159, name = "Daryl", role = "gossip", interactionTypes = { "gossip" } })
check("gossip does not replace the trainer role", services.npcs[1].role == "trainer")
addon.MergeNPC(services, { npcID = 9, name = "Marshal", role = "giver" })
addon.MergeNPC(services, { npcID = 9, name = "Marshal", role = "gossip", interactionTypes = { "gossip" } })
check("gossip does not replace a quest role", services.npcs[2].role == "giver")

-- stored entries from before are fixed on load
local stale = { npcs = {
    { npcID = 5159, name = "Daryl", role = "gossip", interactionTypes = { "gossip", "trainer" } },
    { npcID = 1573, name = "Gryth", role = "gossip", interactionTypes = { "gossip", "flightMaster" } },
} }
ForeverCollectDB = { schemaVersion = 9, catalogs = { k = stale } }
addon.MigrateNPCData()
check("migration takes trainer as role", stale.npcs[1].role == "trainer")
check("migration leaves other services alone", stale.npcs[2].role == "gossip")
addon.MergeNPC(services, { npcID = 1573, name = "Gryth", role = "gossip", interactionTypes = { "gossip" } })
addon.MergeNPC(services, { npcID = 1573, name = "Gryth", role = "flightMaster", interactionTypes = { "flightMaster" } })
check("flight master keeps the gossip role", services.npcs[3].role == "gossip")
