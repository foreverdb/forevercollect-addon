-- Run: luajit tests/object_names_test.lua (or lua5.1)
-- Chests and other game objects are named from the target of the "Opening"
-- cast (UNIT_SPELLCAST_SENT), else from the object tooltip hovered just before.
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
local spellNames = { [3365] = "Opening", [6477] = "Opening", [2366] = "Herb Gathering", [133] = "Fireball" }
GetSpellInfo = function(spellID) return spellNames[spellID] end

-- GameTooltip stub: one title line, an owner, and the OnShow hook.
local tooltipText, tooltipOwner, onShow
GameTooltipTextLeft1 = { GetText = function() return tooltipText end }
GameTooltip = {
    GetName = function() return "GameTooltip" end,
    NumLines = function() return 1 end,
    GetOwner = function() return tooltipOwner end,
    GetItem = function() return nil end,
    GetSpell = function() return nil end,
    HookScript = function(_, _, handler) onShow = handler end,
}
local function hover(text, owner)
    tooltipText, tooltipOwner = text, owner or UIParent
    onShow(GameTooltip)
end

local slots = {}
GetNumLootItems = function() return #slots end
GetLootSlotType = function() return 1 end
GetLootSlotInfo = function(slot) return nil, slots[slot].name, 1, nil, 1, false, false, nil end
GetLootSlotLink = function(slot) return slots[slot].link end
GetLootSourceInfo = function(slot) return slots[slot].guid, 1 end

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
    local sourceType, id = string.match(guid or "", "^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    return sourceType, tonumber(id)
end
addon.GetClientInfo = function() return {} end
addon.GetOrCreateCatalog = function() return catalog end
addon.GetLatestCatalog = function() return catalog end
addon.RecordItem = function() end
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

local function loot(guid, itemID)
    slots = { { name = "Item " .. itemID, link = "|Hitem:" .. itemID .. ":::::|h[Item]|h", guid = guid } }
    fire("LOOT_READY", true)
    fire("LOOT_CLOSED")
end

-- A locked chest: the Opening cast names it, even without a usable tooltip.
fire("UNIT_SPELLCAST_SENT", "player", "Battered Chest", "Cast-1", 6477)
now = now + 2 -- cast time
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 6477)
loot("GameObject-0-1-0-1-106318-0000000001", 4540)
check("chest is named after the Opening target", catalog.lootSources["GameObject:106318"].name == "Battered Chest")

-- An unlocked chest opens without a cast: the hovered tooltip names it.
now = now + 30
hover("Food Crate")
now = now + 1
loot("GameObject-0-1-0-1-3719-0000000002", 4541)
check("castless object is named from its tooltip", catalog.lootSources["GameObject:3719"].name == "Food Crate")

-- Stale or foreign names are not used.
now = now + 30
hover("Backpack", {}) -- a UI widget owns this tooltip
fire("UNIT_SPELLCAST_SENT", "player", "Kobold Vermin", "Cast-2", 133)
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 133)
loot("GameObject-0-1-0-1-2843-0000000003", 4542)
check("UI tooltips and other casts do not name objects", catalog.lootSources["GameObject:2843"].name == nil)

hover("Battered Chest")
now = now + 10
loot("GameObject-0-1-0-1-2844-0000000004", 4543)
check("an old tooltip does not name an object", catalog.lootSources["GameObject:2844"].name == nil)

fire("UNIT_SPELLCAST_SENT", "player", "Battered Chest", "Cast-3", 3365)
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3", 3365)
loot("Creature-0-1-0-1-299-0000000005", 2672)
check("an object name never lands on a creature", catalog.lootSources["Creature:299"].name == nil)
loot("GameObject-0-1-0-1-2845-0000000006", 4544)
check("the Opening name is used for one window only", catalog.lootSources["GameObject:2845"].name == nil)

-- Herb nodes prefer the gather cast's target over the tooltip.
now = now + 30
hover("Copper Vein")
fire("UNIT_SPELLCAST_SENT", "player", "Peacebloom", "Cast-4", 2366)
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-4", 2366)
loot("GameObject-0-1-0-1-1617-0000000007", 2447)
check("herb node is named after the gather target", catalog.lootSources["Herbalism:GameObject:1617"].name == "Peacebloom")
check("no scan errors", #errors == 0)
