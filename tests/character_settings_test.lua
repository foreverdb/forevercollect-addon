-- Run: luajit tests/character_settings_test.lua (or lua5.1)
-- Pause and Armory are per character (ForeverCollectCharacterSettings).
local stubFrame = setmetatable({}, { __index = function() return function() end end })
CreateFrame = function() return stubFrame end
WorldFrame = {}
C_Timer = { After = function() end }
UnitGUID = function() return "Player-1-00000001" end

local printed = {}
local addon = {}
function addon:RegisterEvent() end
function addon:RegisterCommand() end

local function load(path)
    local chunk = assert(loadfile(path))
    chunk("ForeverCollect", addon)
end
load("Core/Util.lua")
load("Core/Database.lua")
addon.PrintMessage = function(message) printed[#printed + 1] = message end
addon.NoteCapture = function() end
load("Modules/Character.lua")

local function check(name, condition)
    if not condition then
        error("FAIL: " .. name, 2)
    end
    print("ok - " .. name)
end

-- First login of a character after the account-wide opt-in.
ForeverCollectDB = nil
ForeverCollectSettings = { armory = true, paused = { all = true } }
ForeverCollectCharacterSettings = nil
addon.InitializeDatabase()
check("account-wide Armory carries over", ForeverCollectCharacterSettings.armory == true)
check("the carry-over is announced", addon.ArmoryInherited == true)
check("account-wide pause is dropped", ForeverCollectSettings.paused == nil)
check("Armory counts as on", addon.IsArmoryEnabled())

-- A character that already chose keeps its choice.
addon.ArmoryInherited = nil
ForeverCollectCharacterSettings = { armory = false }
addon.InitializeDatabase()
check("an explicit off is kept", ForeverCollectCharacterSettings.armory == false)
check("nothing to announce", addon.ArmoryInherited == nil)

-- Turning Armory off removes only the own snapshots and ends the account-wide seed.
ForeverCollectCharacterSettings = { armory = true }
ForeverCollectDB.catalogs = {
    a = { characters = { ["Player-1-00000001"] = {}, ["Player-1-00000002"] = {} } },
    b = { characters = { ["Player-1-00000001"] = {} } },
}
addon.SetArmory(false)
check("own snapshots are removed", ForeverCollectDB.catalogs.a.characters["Player-1-00000001"] == nil
    and ForeverCollectDB.catalogs.b.characters["Player-1-00000001"] == nil)
check("other characters keep theirs", ForeverCollectDB.catalogs.a.characters["Player-1-00000002"] ~= nil)
check("off is stored for this character", ForeverCollectCharacterSettings.armory == false)
check("account-wide seed is cleared", ForeverCollectSettings.armory == nil)

ForeverCollectCharacterSettings = nil
addon.InitializeDatabase()
check("characters after the first choice start off", not addon.IsArmoryEnabled())
