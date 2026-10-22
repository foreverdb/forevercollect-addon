-- Run: luajit tests/encounters_test.lua (or lua5.1)
-- Inside instances boss and target GUIDs are secret: the encounter keeps a probe
-- of what was visible, the creatures looted after the kill and the encounter loot.
local stubFrame = setmetatable({}, { __index = function() return function() end end })
CreateFrame = function() return stubFrame end
WorldFrame = {}
StaticPopupDialogs = {}

local SECRET = {}
issecretvalue = function(value)
    return value == SECRET
end

local clock = 1000
time = function() return clock end
local units = {}
UnitExists = function(unit) return units[unit] ~= nil end
UnitGUID = function(unit) return units[unit] end
UnitName = function() return SECRET end
UnitIsDead = function(unit) return unit == "target" and units.target ~= nil end
local instanceID = 43
IsInInstance = function() return instanceID ~= nil end
GetInstanceInfo = function() return "Wailing Caverns", "party", 1, "", 5, 0, false, instanceID end

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
load("Core/Util.lua")

local catalog = { encounters = {} }
local printed = {}
addon.PrintMessage = function(message) printed[#printed + 1] = message end
addon.Announce = function() end
addon.ParseGUID = function(guid)
    local sourceType, npcID = string.match(guid or "", "^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    return sourceType, tonumber(npcID)
end
addon.GetClientInfo = function() return {} end
addon.GetOrCreateCatalog = function() return catalog end
ForeverCollectCharacterSettings = {}
load("Core/Pause.lua")
load("Modules/Encounters.lua")
addon.CombatLogState = function() return "started" end

local function check(name, condition)
    if not condition then
        error("FAIL: " .. name, 2)
    end
    print("ok - " .. name)
end

-- Secret boss unit and target: no NPC, but the probe says why.
units.boss1 = SECRET
units.target = SECRET
fire("ENCOUNTER_START", 585, "Lord Cobrahn", 1, 5)
fire("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
clock = 1060
fire("ENCOUNTER_END", 585, "Lord Cobrahn", 1, 5, 1)
local encounter = catalog.encounters[585]
check("encounter recorded", encounter and encounter.kills == 1 and encounter.pulls == 1)
check("no NPC from secret units", #encounter.npcs == 0)
check("probe counts the boss unit", encounter.probe.bossUnits == 1)
check("probe marks the boss GUID secret", encounter.probe.bossGUIDSecret == true)
check("probe marks the target GUID secret", encounter.probe.targetGUIDSecret == true)
check("probe has the combat log state", encounter.probe.combatLog == "started")
check("instance stored", encounter.instanceID == 43)

-- Loot after the kill: raw candidates with count and shortest delay.
clock = 1075
addon.NoteCreatureLooted(3669, clock)
clock = 1090
addon.NoteCreatureLooted(3669, clock)
addon.NoteCreatureLooted(3840, clock)
local looted = {}
for _, entry in ipairs(encounter.lootedAfterKill) do
    looted[entry.npcID] = entry
end
check("boss loot kept", looted[3669] and looted[3669].count == 2 and looted[3669].minDelay == 15)
check("other creature kept as well", looted[3840] and looted[3840].minDelay == 30)

-- Too late or elsewhere: ignored.
clock = 1060 + 301
addon.NoteCreatureLooted(5048, clock)
clock = 1100
instanceID = 36
addon.NoteCreatureLooted(5049, clock)
instanceID = 43
check("late and foreign loot ignored", #encounter.lootedAfterKill == 2)

-- Encounter loot is kept per item.
fire("ENCOUNTER_LOOT_RECEIVED", 585, 6460, "|Hitem:6460|h", 1, "Player", "WARRIOR")
fire("ENCOUNTER_LOOT_RECEIVED", 585, 6460, "|Hitem:6460|h", 1, "Other", "MAGE")
check("encounter loot counted", #encounter.lootReceived == 1 and encounter.lootReceived[1].count == 2)

-- Readable boss units still give the NPC directly (outside secret contexts).
units.boss1 = "Creature-0-1-2-3-3653-0000000001"
units.target = nil
fire("ENCOUNTER_START", 586, "Kresh", 1, 5)
clock = 1200
fire("ENCOUNTER_END", 586, "Kresh", 1, 5, 1)
local kresh = catalog.encounters[586]
check("readable boss unit links the NPC", #kresh.npcs == 1 and kresh.npcs[1].npcID == 3653 and kresh.npcs[1].via == "boss")
check("readable boss GUID is not secret", kresh.probe.bossGUIDSecret == false)

-- A wipe is a pull without a kill and moves no loot window.
fire("ENCOUNTER_START", 587, "Skum", 1, 5)
fire("ENCOUNTER_END", 587, "Skum", 1, 5, 0)
check("wipe counts a pull only", catalog.encounters[587].pulls == 1 and catalog.encounters[587].kills == 0)
clock = 1210
addon.NoteCreatureLooted(3674, clock)
check("loot after a wipe goes to the last kill", kresh.lootedAfterKill and kresh.lootedAfterKill[1].npcID == 3674)

-- Paused encounters capture nothing.
ForeverCollectCharacterSettings.paused = { encounters = true }
fire("ENCOUNTER_LOOT_RECEIVED", 588, 1, "", 1, "Player", "WARRIOR")
check("paused: no encounter loot", catalog.encounters[588] == nil)
check("no errors", #printed == 0)
