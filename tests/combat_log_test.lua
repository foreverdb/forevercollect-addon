-- Run: luajit tests/combat_log_test.lua (or lua5.1)
-- Combat logging is turned on in dungeons and raids and only the addon's own
-- logging is turned off again.
local stubFrame = setmetatable({}, { __index = function() return function() end end })
CreateFrame = function() return stubFrame end
WorldFrame = {}

local logging = false
local refuse = false
LoggingCombat = function(enabled)
    if enabled ~= nil then
        if refuse then
            error("ADDON_ACTION_FORBIDDEN")
        end
        logging = enabled
    end
    return logging
end
local instanceType = "none"
GetInstanceInfo = function() return "Somewhere", instanceType end

local handlers = {}
local addon = {}
function addon:RegisterEvent(event, handler)
    handlers[event] = handlers[event] or {}
    table.insert(handlers[event], handler)
end
local commands = {}
function addon:RegisterCommand(name, handler)
    commands[name] = handler
end
local function fire(event, ...)
    for _, handler in ipairs(handlers[event] or {}) do
        handler(...)
    end
end

local function load(path)
    local chunk = assert(loadfile(path))
    chunk("ForeverCollect", addon)
end
load("Core/Util.lua")
local printed = {}
addon.PrintMessage = function(message) printed[#printed + 1] = message end
ForeverCollectCharacterSettings = {}
load("Modules/CombatLog.lua")

local function check(name, condition)
    if not condition then
        error("FAIL: " .. name, 2)
    end
    print("ok - " .. name)
end

fire("PLAYER_ENTERING_WORLD")
check("open world: not logging", logging == false and addon.CombatLogState() == "off")

instanceType = "party"
fire("PLAYER_ENTERING_WORLD")
check("dungeon: logging started", logging == true and addon.CombatLogState() == "started")

instanceType = "none"
fire("ZONE_CHANGED_NEW_AREA")
check("leaving: own logging stopped", logging == false and addon.CombatLogState() == "off")

-- Logging the player started stays on.
logging = true
instanceType = "raid"
fire("PLAYER_ENTERING_WORLD")
check("raid with manual logging: already", addon.CombatLogState() == "already")
instanceType = "none"
fire("PLAYER_ENTERING_WORLD")
check("manual logging is left on", logging == true and addon.CombatLogState() == "already")
logging = false

-- Turned off per character.
commands.combatlog("off")
instanceType = "party"
fire("PLAYER_ENTERING_WORLD")
check("off: no logging", logging == false and ForeverCollectCharacterSettings.combatLog == false)
check("off: state", addon.CombatLogState() == "off")

-- Turning it on inside an instance starts right away.
commands.combatlog("on")
check("on inside: started", logging == true and addon.CombatLogState() == "started")
commands.combatlog("off")
check("off inside: own logging stopped", logging == false)

-- The client refuses: blocked, no error.
ForeverCollectCharacterSettings.combatLog = nil
refuse = true
fire("PLAYER_ENTERING_WORLD")
check("refused: blocked", logging == false and addon.CombatLogState() == "blocked")
