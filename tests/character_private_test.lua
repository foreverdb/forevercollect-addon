-- Run: luajit tests/character_private_test.lua (or lua5.1)
-- The private part of the Armory snapshot: bags, bank and known recipes (Companion).
unpack = unpack or table.unpack
local stubFrame = setmetatable({}, { __index = function() return function() end end })
CreateFrame = function() return stubFrame end
WorldFrame = {}
C_Timer = { After = function(_, callback) callback() end }

local now = 1000
time = function() return now end
date = os.date

WOW_PROJECT_ID, WOW_PROJECT_CLASSIC = 2, 2
NUM_BAG_SLOTS, NUM_BANKBAGSLOTS, BANK_CONTAINER = 4, 6, -1
GetBuildInfo = function() return "1.15.7", "60000", "Jan 1 2026", 11507 end
GetLocale = function() return "enUS" end
UnitClass = function() return "Mage", "MAGE", 8 end
UnitRace = function() return "Gnome", "Gnome", 7 end
UnitFactionGroup = function() return "Alliance", "Alliance" end
UnitSex = function() return 2 end
UnitLevel = function() return 60 end
UnitName = function() return "Tester" end
UnitGUID = function() return "Player-1-00000001" end
GetRealmName = function() return "Forever" end
UnitHealthMax = function() return 3000 end
GetInventoryItemLink = function() return nil end

-- Containers: containers[bag] = { slots = n, [slot] = { itemID, stackCount } }
local containers = {}
C_Container = {
    GetContainerNumSlots = function(bag)
        return containers[bag] and containers[bag].slots or 0
    end,
    GetContainerItemInfo = function(bag, slot)
        return containers[bag] and containers[bag][slot]
    end,
}

local printed = {}
local handlers, commands = {}, {}
local paused = false
local addon = {}
function addon:RegisterEvent(event, handler)
    handlers[event] = handlers[event] or {}
    table.insert(handlers[event], handler)
end
function addon:RegisterCommand(name, handler)
    commands[name] = handler
end

local function load(path)
    local chunk = assert(loadfile(path))
    chunk("ForeverCollect", addon)
end
load("Core/Util.lua")
load("Core/Database.lua")
addon.PrintMessage = function(message) printed[#printed + 1] = message end
addon.NoteCapture = function() end
addon.IsPaused = function() return paused end
addon.HasClassicTalentAPI = function() return false end
load("Modules/Character.lua")
load("Modules/CharacterPrivate.lua")

local function fire(event, ...)
    for _, handler in ipairs(handlers[event] or {}) do
        handler(...)
    end
end

local function check(name, condition)
    if not condition then
        error("FAIL: " .. name, 2)
    end
    print("ok - " .. name)
end

local KEY = "Player-1-00000001"
local function snapshot()
    local catalog = addon.GetLatestCatalog()
    return catalog and catalog.characters[KEY]
end

-- An Armory opt-in from before this version: nothing private until the player allows it.
ForeverCollectDB = nil
ForeverCollectSettings = { verbose = false }
ForeverCollectCharacterSettings = { armory = true }
addon.InitializeDatabase()
containers[0] = { slots = 16, { itemID = 100, stackCount = 5 }, { itemID = 100, stackCount = 3 } }
containers[1] = { slots = 6, { itemID = 200, stackCount = 1 } }
fire("PLAYER_ENTERING_WORLD")
check("old opt-in is told once", #printed == 1 and printed[1]:find("/fc private on", 1, true) ~= nil)
check("the notice is remembered", ForeverCollectCharacterSettings.privateNoticeShown == true)
check("old opt-in gets a public snapshot", snapshot() ~= nil)
check("old opt-in sends no private part", snapshot().private == nil)
fire("PLAYER_ENTERING_WORLD")
check("no second notice", #printed == 1)

-- Private needs Armory.
ForeverCollectCharacterSettings.armory = false
check("private on without Armory is refused", addon.SetCharacterPrivate(true) == false
    and ForeverCollectCharacterSettings.private == nil)
ForeverCollectCharacterSettings.armory = true

commands.private("on")
local private = snapshot().private
check("private part is captured", private ~= nil)
check("stacks of one item are summed", private.bags[100] == 8 and private.bags[200] == 1)
check("no bank before the first visit", private.bank == nil and private.bankScannedAt == nil)

-- Bank: only read while open and loaded.
containers[-1] = { slots = 24, { itemID = 300, stackCount = 20 } }
fire("PLAYERBANKSLOTS_CHANGED")
check("a closed bank is not read", ForeverCollectCharacterSettings.privateCache.bank == nil)
local bankSlots = containers[-1].slots
containers[-1].slots = 0
fire("BANKFRAME_OPENED")
check("a bank without slots is no empty bank", ForeverCollectCharacterSettings.privateCache.bank == nil)
containers[-1].slots = bankSlots
now = 2000
fire("PLAYERBANKSLOTS_CHANGED")
fire("BANKFRAME_CLOSED")
check("the bank without bank bags is scanned", snapshot().private.bank[300] == 20)
check("the bank scan has its time", snapshot().private.bankScannedAt == 2000)

-- Recipes through C_TradeSkillUI: only learned ones, and not another player's list.
local linked = false
C_TradeSkillUI = {
    GetBaseProfessionInfo = function() return { professionID = 171, professionName = "Alchemy" } end,
    GetAllRecipeIDs = function() return { 3, 1, 2 } end,
    GetRecipeInfo = function(id) return { learned = id ~= 2 } end,
    IsTradeSkillLinked = function() return linked end,
}
linked = true
fire("TRADE_SKILL_SHOW")
check("a linked profession is not stored", next(ForeverCollectCharacterSettings.privateCache.recipes) == nil)
linked = false
fire("TRADE_SKILL_SHOW")
local alchemy = snapshot().private.recipes[171]
check("learned recipes are stored sorted", alchemy and alchemy.spellIDs[1] == 1 and alchemy.spellIDs[2] == 3
    and #alchemy.spellIDs == 2)
check("the profession is named", alchemy.name == "Alchemy" and alchemy.scannedAt == 2000)
C_TradeSkillUI = nil

-- Classic window: a filtered list is read in full and the filter is put back.
local nameFilter = "flask"
GetTradeSkillLine = function() return "Tailoring", 150, 225 end
GetNumTradeSkills = function() return nameFilter == "" and 3 or 1 end
GetTradeSkillInfo = function(index)
    if nameFilter ~= "" then
        return "Bolt of Linen Cloth", "trivial"
    end
    return ({ { "Cloth", "header", 0, true }, { "Bolt of Linen Cloth", "trivial" }, { "Linen Bag", "easy" } })[index][1],
        ({ "header", "trivial", "easy" })[index], 0, index == 1
end
GetTradeSkillRecipeLink = function(index)
    return nameFilter == "" and ("|Henchant:" .. (2962 + index) .. "|h[x]|h") or "|Henchant:2964|h[x]|h"
end
GetTradeSkillItemLink = function() return nil end
GetTradeSkillItemNameFilter = function() return nameFilter end
SetTradeSkillItemNameFilter = function(text) nameFilter = text end
fire("TRADE_SKILL_SHOW")
local tailoring = snapshot().private.recipes.Tailoring
check("a filtered classic window yields every recipe", tailoring and #tailoring.spellIDs == 2
    and tailoring.spellIDs[1] == 2964 and tailoring.spellIDs[2] == 2965)
check("the name filter is put back", nameFilter == "flask")
GetTradeSkillLine, GetNumTradeSkills, GetTradeSkillInfo = nil, nil, nil

-- The uploader empties ForeverCollectDB; bank and recipes come back from the cache.
ForeverCollectDB = nil
now = 3000
fire("BAG_UPDATE", 0)
private = snapshot().private
check("bank survives the upload", private.bank and private.bank[300] == 20 and private.bankScannedAt == 2000)
check("recipes survive the upload", private.recipes[171] and private.recipes[171].scannedAt == 2000)

-- Paused: nothing new is read.
paused = true
containers[0] = { slots = 16, { itemID = 100, stackCount = 1 } }
containers[-1] = { slots = 24, { itemID = 400, stackCount = 1 } }
fire("BANKFRAME_OPENED")
fire("BAG_UPDATE", 0)
fire("BANKFRAME_CLOSED")
check("a paused bank is not read", ForeverCollectCharacterSettings.privateCache.bank[400] == nil)
check("paused bags keep the last state", snapshot().private.bags[100] == 8)
paused = false

-- Empty bags.
containers[0], containers[1] = { slots = 16 }, { slots = 6 }
fire("BAG_UPDATE", 0)
check("empty bags are an empty map", next(snapshot().private.bags) == nil)

-- Off: the private part goes, the public profile stays.
local other = { characters = { [KEY] = { character = {}, private = { bags = {} } } } }
ForeverCollectDB.catalogs.other = other
commands.private("off")
check("private is removed from every catalog", snapshot().private == nil and other.characters[KEY].private == nil)
check("the public snapshot stays", snapshot() ~= nil and other.characters[KEY] ~= nil)
check("the cache is cleared", ForeverCollectCharacterSettings.privateCache == nil)
check("off is stored", ForeverCollectCharacterSettings.private == false)
fire("BAG_UPDATE", 0)
check("nothing private after off", snapshot().private == nil)

-- New opt-ins send the private part at once; Armory off drops both.
addon.SetArmory(false)
check("Armory off clears the private choice", ForeverCollectCharacterSettings.private == nil)
addon.SetArmory(true)
check("new opt-in turns private on", ForeverCollectCharacterSettings.private == true and snapshot().private ~= nil)
