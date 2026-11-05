-- Run: luajit tests/character_secret_stats_test.lua (or lua5.1)
-- Forever keeps unit stats secret in combat: a capture then waits for the end of the fight
-- instead of failing or storing a snapshot with empty stats.
unpack = unpack or table.unpack
local stubFrame = setmetatable({}, { __index = function() return function() end end })
CreateFrame = function() return stubFrame end
WorldFrame = {}
C_Timer = { After = function(_, callback) callback() end }

time = function() return 1000 end
date = os.date

-- Arithmetic on a plain table raises an error, like on a real secret value.
local SECRET = {}
issecretvalue = function(value) return value == SECRET end

local secretStats = true
local secretPower = false
local level = 60

WOW_PROJECT_ID, WOW_PROJECT_CLASSIC = 2, 2
GetBuildInfo = function() return "1.15.7", "60000", "Jan 1 2026", 11507 end
GetLocale = function() return "enUS" end
UnitClass = function() return "Mage", "MAGE", 8 end
UnitRace = function() return "Gnome", "Gnome", 7 end
UnitFactionGroup = function() return "Alliance", "Alliance" end
UnitSex = function() return 2 end
UnitLevel = function() return level end
UnitName = function() return "Tester" end
UnitGUID = function() return "Player-1-00000001" end
GetRealmName = function() return "Forever" end
GetInventoryItemLink = function() return nil end
UnitHealthMax = function() return 3000 end
UnitPowerMax = function()
    if secretPower then
        return SECRET
    end
    return 2000
end
UnitAttackPower = function()
    if secretStats then
        return SECRET, SECRET, SECRET
    end
    return 100, 50, -10
end
UnitStat = function()
    if secretStats then
        return SECRET, SECRET
    end
    return 40, 55
end

local handlers = {}
local addon = {}
function addon:RegisterEvent(event, handler)
    handlers[event] = handlers[event] or {}
    table.insert(handlers[event], handler)
end
function addon:RegisterCommand() end

local function load(path)
    assert(loadfile(path))("ForeverCollect", addon)
end
load("Core/Util.lua")
load("Core/Database.lua")
addon.PrintMessage = function() end
addon.NoteCapture = function() end
addon.IsPaused = function() return false end
addon.HasClassicTalentAPI = function() return false end
load("Modules/Character.lua")

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

local function snapshot()
    for _, catalog in pairs(ForeverCollectDB.catalogs) do
        for _, stored in pairs(catalog.characters or {}) do
            return stored
        end
    end
end

ForeverCollectDB, ForeverCollectSettings, ForeverCollectCharacterSettings = nil, nil, nil
addon.InitializeDatabase()

addon.SetArmory(true, { private = false })
check("no snapshot while the stats are secret", snapshot() == nil)
fire("PLAYER_REGEN_ENABLED")
check("still none when they stay secret after the fight", snapshot() == nil)

secretStats = false
fire("PLAYER_REGEN_ENABLED")
local stored = snapshot()
check("the capture follows when the stats are readable", stored ~= nil)
check("attack power adds up", stored.stats.attackPower == 140)
check("primary stats are stored", stored.stats.primary[1].effective == 55)
check("health is stored", stored.stats.health == 3000)

-- A capture on a later change must not lose what the fight delayed, and a single secret
-- value only leaves that one field empty.
secretPower = true
level = 61
fire("PLAYER_LEVEL_UP")
stored = snapshot()
check("a new snapshot is taken", stored.character.level == 61)
check("a single secret value stays out", stored.stats.power == nil)
check("the other stats stay", stored.stats.attackPower == 140)

-- Without a waiting capture the end of a fight changes nothing.
secretPower = false
local before = snapshot()
fire("PLAYER_REGEN_ENABLED")
check("the end of a fight alone takes no snapshot", snapshot() == before and before.stats.power == nil)
