local _, addon = ...

local printMessage = addon.PrintMessage
local announce = addon.Announce
local parseGUID = addon.ParseGUID
local getClientInfo = addon.GetClientInfo
local getOrCreateCatalog = addon.GetOrCreateCatalog
local getInstance = addon.GetInstance
local readable = addon.Readable

local MAX_BOSS_UNITS = 8

-- The encounter in progress: its ID and the creatures seen as its boss units
-- (boss1..bossN), which is what ties a DungeonEncounter row to the creatures
-- whose loot is recorded under Creature:<npcID>.
local current

local function addBossUnit(unit)
    local sourceType, npcID = parseGUID(readable(UnitGUID(unit)))
    if sourceType ~= "Creature" and sourceType ~= "Vehicle" or not npcID then
        return
    end
    if not current.npcs[npcID] then
        current.npcs[npcID] = { npcID = npcID, name = readable(UnitName(unit)), via = "boss" }
    end
end

local function scanBossUnits()
    if not current then
        return
    end
    for index = 1, MAX_BOSS_UNITS do
        local unit = "boss" .. index
        if UnitExists(unit) then
            addBossUnit(unit)
        end
    end
end

addon:RegisterEvent("ENCOUNTER_START", function(encounterID, encounterName, difficultyID, groupSize)
    encounterID = readable(encounterID)
    if type(encounterID) ~= "number" then
        current = nil
        return
    end
    current = {
        encounterID = encounterID,
        name = readable(encounterName),
        difficultyID = readable(difficultyID),
        groupSize = readable(groupSize),
        npcs = {},
    }
    scanBossUnits()
end)

addon:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT", scanBossUnits)

local function recordEncounter(encounterID, success)
    local catalog = getOrCreateCatalog(getClientInfo())
    local now = time()
    local encounter = catalog.encounters[encounterID]
    if not encounter then
        encounter = {
            encounterID = encounterID,
            firstSeenAt = now,
            pulls = 0,
            kills = 0,
            npcs = {},
        }
        catalog.encounters[encounterID] = encounter
    end
    encounter.name = current.name or encounter.name
    encounter.difficultyID = current.difficultyID or encounter.difficultyID
    encounter.instanceID = getInstance() or encounter.instanceID
    encounter.pulls = encounter.pulls + 1
    if success then
        encounter.kills = encounter.kills + 1
    end
    encounter.lastSeenAt = now

    -- Boss units are the reliable link; without any, a dead creature still
    -- targeted when the fight ends is the next best guess and marked as such.
    if success and next(current.npcs) == nil and UnitIsDead("target") then
        local sourceType, npcID = parseGUID(readable(UnitGUID("target")))
        if sourceType == "Creature" and npcID then
            current.npcs[npcID] = { npcID = npcID, name = readable(UnitName("target")), via = "target" }
        end
    end
    for npcID, npc in pairs(current.npcs) do
        local known
        for _, existing in ipairs(encounter.npcs) do
            if existing.npcID == npcID then
                known = existing
            end
        end
        if not known then
            encounter.npcs[#encounter.npcs + 1] = npc
        elseif known.via == "target" and npc.via == "boss" then
            known.via = "boss"
            known.name = npc.name or known.name
        end
    end
    return encounter
end

addon:RegisterEvent("ENCOUNTER_END", function(encounterID, _, _, _, success)
    encounterID = readable(encounterID)
    if not current or current.encounterID ~= encounterID then
        current = nil
        return
    end
    local ok, result = pcall(recordEncounter, encounterID, readable(success) == 1)
    if not ok then
        printMessage("Encounter scan failed: " .. tostring(result))
    elseif readable(success) == 1 then
        local names = {}
        for _, npc in ipairs(result.npcs) do
            names[#names + 1] = string.format("%s (%d)", npc.name or "?", npc.npcID)
        end
        announce(string.format(
            "Encounter captured: %s, %s.",
            result.name or tostring(encounterID),
            #names > 0 and table.concat(names, ", ") or "no boss unit seen"
        ))
    end
    current = nil
end)
