-- Run: luajit tests/disenchant_test.lua (or lua5.1)
-- A disenchant files its loot window under the disenchanted bag item
-- ("Enchanting:Item:<itemID>"); the item comes from the bag click (or item
-- lock) that targeted the cast.
local stubFrame = setmetatable({}, { __index = function() return function() end end })
CreateFrame = function() return stubFrame end
WorldFrame = {}
UIParent = {}
IsInInstance = function() return false end
UnitIsDead = function() return false end
UnitExists = function() return false end
UnitGUID = function() return nil end
UnitName = function() return nil end
IsFishingLoot = function() return false end
time = os.time
local now = 100
GetTime = function() return now end
local spellNames = { [13262] = "Disenchant", [3365] = "Opening", [2366] = "Herb Gathering" }
GetSpellInfo = function(spellID) return spellNames[spellID] end

-- Bags: bag -> slot -> { link, locked }
local bags = {
    [0] = {
        [1] = { link = "|cff1eff00|Hitem:2632:::::|h[Curved Dagger]|h|r" },
        [2] = { link = "|cff0070dd|Hitem:6320:::::|h[Commander's Crest]|h|r" },
        [3] = { link = "|cff1eff00|Hitem:2632:::::|h[Curved Dagger]|h|r" },
    },
}
local hooks = {}
hooksecurefunc = function(target, name, hook)
    if type(target) == "string" then
        target, name, hook = _G, target, name
    end
    local original = target[name]
    target[name] = function(...)
        local results = { original(...) }
        hook(...)
        return unpack(results)
    end
    hooks[name] = true
end
C_Container = {
    GetContainerItemLink = function(bag, slot)
        local item = bags[bag] and bags[bag][slot]
        return item and item.link
    end,
    GetContainerItemInfo = function(bag, slot)
        local item = bags[bag] and bags[bag][slot]
        return item and { hyperlink = item.link, isLocked = item.locked or false }
    end,
    PickupContainerItem = function() end,
    UseContainerItem = function() end,
}

local slots = {}
GetNumLootItems = function() return #slots end
GetLootSlotType = function() return 1 end
GetLootSlotInfo = function(slot) return nil, slots[slot].name, slots[slot].quantity or 1, nil, 1, false, false, nil end
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
local announced = {}
local recorded = {}
addon.PrintMessage = function(message) errors[#errors + 1] = message end
addon.Announce = function(message) announced[#announced + 1] = message end
addon.GetPlayerLocation = function() return { zone = "Elwynn Forest", uiMapID = 1429, x = 0.5, y = 0.5 } end
addon.ParseGUID = function(guid)
    local sourceType, id = string.match(guid or "", "^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    if not sourceType then
        sourceType = string.match(guid or "", "^([^-]+)")
    end
    return sourceType, tonumber(id)
end
addon.GetClientInfo = function() return {} end
addon.GetOrCreateCatalog = function() return catalog end
addon.GetLatestCatalog = function() return catalog end
addon.RecordItem = function(link, source) recorded[#recorded + 1] = source end
ForeverCollectCharacterSettings = {}
load("Core/Pause.lua")
load("Modules/Gathering.lua")
load("Modules/Loot.lua")

local function check(name, condition)
    if not condition then
        error("FAIL: " .. name, 2)
    end
    print("ok - " .. name)
end

-- Each looted item (disenchanted or opened) has its own GUID.
local itemGUIDs = 0
local function material(itemID, name, quantity)
    itemGUIDs = itemGUIDs + 1
    local guid = string.format("Item-5826-0-40000000%08X", itemGUIDs)
    return { name = name, link = "|Hitem:" .. itemID .. ":::::|h[" .. name .. "]|h", quantity = quantity, guid = guid }
end

local castCount = 0
-- Click the bag item while the spell is targeting, cast, then loot.
local function disenchant(bag, slot, target, loot, how)
    castCount = castCount + 1
    local castGUID = "Cast-3-0-0-0-13262-" .. castCount
    if how == "lock" then
        fire("UNIT_SPELLCAST_SENT", "player", target, castGUID, 13262)
        bags[bag][slot].locked = true
        fire("ITEM_LOCK_CHANGED", bag, slot)
    else
        C_Container.PickupContainerItem(bag, slot)
        fire("UNIT_SPELLCAST_SENT", "player", target, castGUID, 13262)
    end
    now = now + 3
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", castGUID, 13262)
    bags[bag][slot].locked = nil
    slots = loot
    fire("LOOT_READY", true)
    fire("LOOT_CLOSED")
    now = now + 1
end

check("bag click functions are hooked", hooks.PickupContainerItem and hooks.UseContainerItem)

disenchant(0, 1, "Curved Dagger", { material(10940, "Strange Dust", 2) })
disenchant(0, 3, "Curved Dagger", { material(10940, "Strange Dust", 1), material(10938, "Lesser Magic Essence", 1) })
local dagger = catalog.lootSources["Enchanting:Item:2632"]
check("disenchant is keyed by the item", dagger ~= nil)
check("source fields", dagger.sourceType == "Item" and dagger.sourceID == 2632
    and dagger.profession == "Enchanting" and dagger.gatherSpellID == 13262 and dagger.name == "Curved Dagger")
check("both disenchants are counted", dagger.lootCount == 2)
check("materials of both windows", dagger.items[10940].timesSeen == 2 and dagger.items[10940].quantityTotal == 3
    and dagger.items[10938].timesSeen == 1)
check("no location for disenchants", #dagger.locations == 0 and #dagger.items[10940].locations == 0)
check("item source carries the profession, no location",
    recorded[1].profession == "Enchanting" and recorded[1].sourceID == 2632 and recorded[1].location == nil)
check("announcement names the item", announced[1] == "Disenchanted Curved Dagger: Strange Dust x2.")
check("no plain item source", catalog.lootSources["Item"] == nil)

disenchant(0, 2, "Commander's Crest", { material(10978, "Small Glimmering Shard", 1) })
check("a different item is another source", catalog.lootSources["Enchanting:Item:6320"].lootCount == 1)

-- A macro (/cast Disenchant, /use 0 2) targets without a hooked click; the item lock tells it.
disenchant(0, 2, "Commander's Crest", { material(10978, "Small Glimmering Shard", 1) }, "lock")
check("item lock identifies the target", catalog.lootSources["Enchanting:Item:6320"].lootCount == 2)

-- The clicked item does not match the cast's target: nothing is attributed.
disenchant(0, 1, "Commander's Crest", { material(10978, "Small Glimmering Shard", 1) })
check("mismatched target is not a disenchant", catalog.lootSources["Enchanting:Item:6320"].lootCount == 2
    and catalog.lootSources["Enchanting:Item:2632"].lootCount == 2)
check("it stays plain item loot", catalog.lootSources["Item"] and catalog.lootSources["Item"].lootCount == 1)

-- A container opened from the bags and a creature are not disenchants.
slots = { material(4496, "Small Brown Pouch", 1) }
fire("LOOT_READY", true)
fire("LOOT_CLOSED")
check("opened container stays plain item loot", catalog.lootSources["Item"].lootCount == 2)
slots = { { name = "Ruined Pelt", link = "|Hitem:4865:::::|h[Ruined Pelt]|h", guid = "Creature-0-1-0-1-299-0000000001" } }
fire("LOOT_READY", true)
fire("LOOT_CLOSED")
check("creature loot is not a disenchant", catalog.lootSources["Creature:299"] ~= nil)
local enchantingKeys = 0
for key in pairs(catalog.lootSources) do
    if string.sub(key, 1, 11) == "Enchanting:" then
        enchantingKeys = enchantingKeys + 1
    end
end
check("only the two disenchanted items", enchantingKeys == 2)

-- A loot window long after the disenchant is not tagged.
C_Container.PickupContainerItem(0, 1)
fire("UNIT_SPELLCAST_SENT", "player", "Curved Dagger", "Cast-late", 13262)
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-late", 13262)
now = now + 10
slots = { material(4496, "Small Brown Pouch", 1) }
fire("LOOT_READY", true)
fire("LOOT_CLOSED")
check("timed-out disenchant is not applied", catalog.lootSources["Enchanting:Item:2632"].lootCount == 2)

-- Paused gathering records no disenchant.
ForeverCollectCharacterSettings.paused = { gathering = true }
disenchant(0, 1, "Curved Dagger", { material(10940, "Strange Dust", 1) })
check("paused disenchant is not recorded", catalog.lootSources["Enchanting:Item:2632"].lootCount == 2)
ForeverCollectCharacterSettings.paused = nil

check("no scan errors", #errors == 0)
