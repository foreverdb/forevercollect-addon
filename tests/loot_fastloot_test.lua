-- Run: luajit tests/loot_fastloot_test.lua (or lua5.1)
-- Fast-autoloot addons (Leatrix Plus) loot every slot on LOOT_READY, so the
-- slots are empty by LOOT_OPENED; loot must be captured on LOOT_READY.
local stubFrame = setmetatable({}, { __index = function() return function() end end })
CreateFrame = function() return stubFrame end
WorldFrame = {}
UNKNOWNOBJECT = "Unknown"
IsInInstance = function() return false end
UnitIsDead = function() return false end
UnitGUID = function() return nil end
UnitName = function() return nil end
time = os.time

local fishing = false
IsFishingLoot = function() return fishing end

-- Each slot: { name, link, guid }
local slots = {}
GetNumLootItems = function() return #slots end
GetLootSlotType = function() return 1 end
GetLootSlotInfo = function(slot) return nil, slots[slot].name, 1, nil, 1, false, false, nil end
GetLootSlotLink = function(slot) return slots[slot].link end
GetLootSourceInfo = function(slot)
    if slots[slot].guid then
        return slots[slot].guid, 1
    end
end

local handlers = {}
local addon = {}
function addon:RegisterEvent(event, handler)
    handlers[event] = handlers[event] or {}
    table.insert(handlers[event], handler)
end
function addon:RegisterCommand() end
local function fire(event, ...)
    for _, handler in ipairs(handlers[event] or {}) do
        handler(...)
    end
end

local function load(path)
    local chunk = assert(loadfile(path))
    chunk("ForeverCollect", addon)
end
StaticPopupDialogs = {}
load("Core/Util.lua")

local catalog = { lootSources = {} }
local errors = {}
addon.PrintMessage = function(message) errors[#errors + 1] = message end
addon.Announce = function() end
addon.GetPlayerLocation = function() return { zone = "Elwynn Forest" } end
addon.ParseGUID = function(guid)
    local sourceType, npcID = string.match(guid or "", "^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    return sourceType, tonumber(npcID)
end
addon.GetClientInfo = function() return {} end
addon.GetOrCreateCatalog = function() return catalog end
addon.GetLatestCatalog = function() return catalog end
addon.RecordItem = function() end
local pendingGather
addon.ConsumePendingGather = function()
    local gather = pendingGather
    pendingGather = nil
    return gather
end
ForeverCollectCharacterSettings = {}
load("Core/Pause.lua")
load("Modules/Loot.lua")

local function check(name, condition)
    if not condition then
        error("FAIL: " .. name, 2)
    end
    print("ok - " .. name)
end

local function item(itemID, guid)
    return { name = "Item " .. itemID, link = "|Hitem:" .. itemID .. ":::::|h[Item]|h", guid = guid }
end

local wolf = "Creature-0-1-0-1-299-0000000001"
slots = { item(2672, wolf), item(750, wolf) }
fire("LOOT_READY", true)
slots = {} -- Leatrix Plus looted everything before LOOT_OPENED
fire("LOOT_OPENED", true)
fire("LOOT_CLOSED")
local source = catalog.lootSources["Creature:299"]
check("loot is captured on LOOT_READY", source and source.items[2672] and source.items[750])
check("corpse is counted once", source.lootCount == 1)
check("no scan errors", #errors == 0)

fishing = true
slots = { item(6303) }
fire("LOOT_READY", true)
fire("LOOT_OPENED", true)
check("GUID-less loot is counted once per window", catalog.lootSources["Fishing"].lootCount == 1)
check("GUID-less item is counted once per window", catalog.lootSources["Fishing"].items[6303].timesSeen == 1)

fire("LOOT_CLOSED")
fire("LOOT_READY", true)
check("next window is counted again", catalog.lootSources["Fishing"].lootCount == 2)
fire("LOOT_CLOSED")
fishing = false

local boar = "Creature-0-1-0-1-113-0000000002"
slots = {}
fire("LOOT_READY", true)
slots = { item(769, boar) }
fire("LOOT_OPENED", true)
fire("LOOT_CLOSED")
check("LOOT_OPENED scans when LOOT_READY saw no slots", catalog.lootSources["Creature:113"].items[769])
check("still no scan errors", #errors == 0)

-- Paused kinds record nothing; a paused gather is not recorded as loot either.
local deer = "Creature-0-1-0-1-883-0000000003"
ForeverCollectCharacterSettings.paused = { loot = true }
slots = { item(2672, deer) }
fire("LOOT_READY", true)
fire("LOOT_OPENED", true)
fire("LOOT_CLOSED")
check("paused loot is not recorded", catalog.lootSources["Creature:883"] == nil)

fishing = true
slots = { item(6358) }
pendingGather = { profession = "Fishing", spellID = 7620 }
fire("LOOT_READY", true)
fire("LOOT_CLOSED")
check("gathering still records while loot is paused", catalog.lootSources["Fishing"].items[6358])

ForeverCollectCharacterSettings.paused = { gathering = true }
slots = { item(6359) }
pendingGather = { profession = "Fishing", spellID = 7620 }
fire("LOOT_READY", true)
fire("LOOT_OPENED", true)
fire("LOOT_CLOSED")
check("paused gather is not recorded", catalog.lootSources["Fishing"].items[6359] == nil)
fishing = false
ForeverCollectCharacterSettings.paused = nil
check("no scan errors while paused", #errors == 0)
