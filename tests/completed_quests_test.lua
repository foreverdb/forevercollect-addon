-- Run: luajit tests/completed_quests_test.lua (or lua5.1)
-- Completed quests in the private part, and the setup's visibility choice in the snapshot.
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
local function cache()
    return ForeverCollectCharacterSettings.privateCache or {}
end

ForeverCollectDB = nil
ForeverCollectSettings = { verbose = false }
ForeverCollectCharacterSettings = {}
addon.InitializeDatabase()
containers[0] = { slots = 16, { itemID = 100, stackCount = 1 } }

-- Classic Era: GetQuestsCompleted returns a map.
local completed = { [176] = true, [7] = true }
GetQuestsCompleted = function() return completed end

fire("PLAYER_ENTERING_WORLD")
check("nothing is read without the opt-in", cache().completedQuests == nil)

addon.SetArmory(true)
check("the opt-in reads the completed quests", cache().completedQuests and cache().completedQuests[176]
    and cache().questsScannedAt == 1000)
local private = snapshot().private
check("the snapshot carries them sorted", private.completedQuests[1] == 7 and private.completedQuests[2] == 176
    and private.questsScannedAt == 1000)

now = 2000
fire("PLAYER_ENTERING_WORLD")
check("an unchanged list keeps its time", cache().questsScannedAt == 1000)

fire("QUEST_TURNED_IN", 33, 0, 0)
check("a turn-in adds the quest", cache().completedQuests[33] and cache().questsScannedAt == 2000)
check("the snapshot follows the turn-in", snapshot().private.completedQuests[2] == 33)

-- Forever: C_QuestLog.GetAllCompletedQuestIDs returns a list and wins.
C_QuestLog = { GetAllCompletedQuestIDs = function() return { 5, 7, 33, 176 } end }
now = 3000
fire("PLAYER_ENTERING_WORLD")
check("the list API is read", cache().completedQuests[5] and cache().questsScannedAt == 3000)

-- The quest log: headers and hidden entries are no quests, an unchanged log keeps its time.
local logEntries = {
    { isHeader = true, title = "Undercity" },
    { questID = 5725 },
    { questID = 99, isHidden = true },
    { questID = 7 },
}
C_QuestLog.GetNumQuestLogEntries = function() return #logEntries, #logEntries end
C_QuestLog.GetInfo = function(index) return logEntries[index] end
now = 3100
fire("QUEST_LOG_UPDATE")
check("the log is read", cache().activeQuests[5725] and cache().activeQuests[7] and not cache().activeQuests[99]
    and cache().activeQuestsScannedAt == 3100)
check("the snapshot carries the log sorted", snapshot().private.activeQuests[1] == 7
    and snapshot().private.activeQuests[2] == 5725 and snapshot().private.activeQuestsScannedAt == 3100)
now = 3200
fire("QUEST_LOG_UPDATE")
check("an unchanged log keeps its time", cache().activeQuestsScannedAt == 3100)
logEntries = {}
fire("QUEST_LOG_UPDATE")
check("an emptied log is sent as empty", cache().activeQuestsScannedAt == 3200
    and #snapshot().private.activeQuests == 0)
C_QuestLog = nil

-- Classic Era has no C_QuestLog.GetInfo.
GetNumQuestLogEntries = function() return 2 end
GetQuestLogTitle = function(index)
    if index == 1 then
        return "Barrens", nil, nil, true
    end
    return "Quest", 16, 0, false, false, false, 1, 5725
end
now = 3300
fire("QUEST_LOG_UPDATE")
check("the Classic log is read", cache().activeQuests[5725] and cache().activeQuestsScannedAt == 3300)
GetNumQuestLogEntries, GetQuestLogTitle = nil, nil

-- Paused: nothing new is read.
paused = true
completed[999] = true
fire("PLAYER_ENTERING_WORLD")
fire("QUEST_TURNED_IN", 1000, 0, 0)
check("paused reads nothing", not cache().completedQuests[999] and not cache().completedQuests[1000])
paused = false

-- Without a full list a turn-in is not stored alone.
ForeverCollectCharacterSettings.privateCache.completedQuests = nil
ForeverCollectCharacterSettings.privateCache.questsScannedAt = nil
GetQuestsCompleted = nil
fire("QUEST_TURNED_IN", 42, 0, 0)
check("a single turn-in is no list", cache().completedQuests == nil)
fire("BAG_UPDATE", 0)
check("no list, no quests in the snapshot", snapshot().private.completedQuests == nil)

-- Off removes them with the rest of the private part.
GetQuestsCompleted = function() return completed end
fire("PLAYER_ENTERING_WORLD")
check("read again", cache().completedQuests ~= nil)
commands.private("off")
check("off clears the quests", ForeverCollectCharacterSettings.privateCache == nil and snapshot().private == nil)

-- The setup's visibility choice goes up with the snapshot, without being content.
check("no choice, no field", snapshot().public == nil)
local before = snapshot()
ForeverCollectCharacterSettings.publicChoice = true
addon.ScheduleCharacterCapture()
check("a choice made later reaches the stored snapshot", snapshot().public == true)
check("the choice alone makes no new snapshot", snapshot() == before)
ForeverCollectCharacterSettings.publicChoice = false
addon.ScheduleCharacterCapture()
check("false is sent too", snapshot().public == false)
