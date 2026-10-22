local _, addon = ...

local printMessage = addon.PrintMessage
local announce = addon.Announce
local parseGUID = addon.ParseGUID
local getClientInfo = addon.GetClientInfo
local getOrCreateCatalog = addon.GetOrCreateCatalog
local getInstance = addon.GetInstance
local readable = addon.Readable

local MAX_BOSS_UNITS = 8
-- Creatures looted this long after a kill in the same instance are kept as raw
-- candidates for the encounter's boss (the server decides, the addon does not).
local LOOT_AFTER_KILL_SECONDS = 300

-- The encounter in progress: its ID and the creatures seen as its boss units
-- (boss1..bossN), which is what ties a DungeonEncounter row to the creatures
-- whose loot is recorded under Creature:<npcID>.
local current

-- The last successful kill, for the loot that follows it.
local lastKill

local function isSecret(value)
    return value ~= nil and issecretvalue ~= nil and issecretvalue(value) and true or false
end

local function addBossUnit(unit)
    local guid = UnitGUID(unit)
    current.probe.bossUnits = current.probe.bossUnits + 1
    if isSecret(guid) then
        current.probe.bossGUIDSecret = true
    end
    local sourceType, npcID = parseGUID(readable(guid))
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
    current.probe.bossUnits = 0
    for index = 1, MAX_BOSS_UNITS do
        local unit = "boss" .. index
        if UnitExists(unit) then
            addBossUnit(unit)
        end
    end
    current.probe.maxBossUnits = math.max(current.probe.maxBossUnits, current.probe.bossUnits)
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
        probe = { bossUnits = 0, maxBossUnits = 0, bossGUIDSecret = false },
    }
    scanBossUnits()
end)

addon:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT", scanBossUnits)

local function getEncounter(catalog, encounterID, now)
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
    encounter.lastSeenAt = now
    return encounter
end

local function recordEncounter(encounterID, success)
    local catalog = getOrCreateCatalog(getClientInfo())
    local now = time()
    local encounter = getEncounter(catalog, encounterID, now)
    encounter.name = current.name or encounter.name
    encounter.difficultyID = current.difficultyID or encounter.difficultyID
    encounter.instanceID = getInstance() or encounter.instanceID
    encounter.pulls = encounter.pulls + 1
    if success then
        encounter.kills = encounter.kills + 1
    end

    -- Boss units are the reliable link; without any, a dead creature still
    -- targeted when the fight ends is the next best guess and marked as such.
    local targetGUID = UnitGUID("target")
    if success and next(current.npcs) == nil and UnitIsDead("target") then
        local sourceType, npcID = parseGUID(readable(targetGUID))
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

    -- What the client let the addon see on the last pull: inside instances the
    -- boss and target GUIDs are secret on the mainline engine.
    encounter.probe = {
        capturedAt = now,
        success = success,
        bossUnits = current.probe.maxBossUnits,
        bossGUIDSecret = current.probe.bossGUIDSecret,
        targetGUIDSecret = isSecret(targetGUID),
        combatLog = addon.CombatLogState and addon.CombatLogState() or nil,
    }

    if success then
        lastKill = { encounterID = encounterID, instanceID = encounter.instanceID, at = now }
    end
    return encounter
end

-- Called by the loot scan for every creature looted (Modules/Loot.lua). Within
-- LOOT_AFTER_KILL_SECONDS of a kill in the same instance the creature is kept
-- on the encounter with the shortest delay seen.
function addon.NoteCreatureLooted(npcID, now)
    if not lastKill or not npcID or now - lastKill.at > LOOT_AFTER_KILL_SECONDS then
        return
    end
    if not addon.IsCapturing("encounters") or getInstance() ~= lastKill.instanceID then
        return
    end
    local catalog = getOrCreateCatalog(getClientInfo())
    local encounter = catalog.encounters[lastKill.encounterID]
    if not encounter then
        return
    end
    encounter.lootedAfterKill = encounter.lootedAfterKill or {}
    local delay = now - lastKill.at
    for _, entry in ipairs(encounter.lootedAfterKill) do
        if entry.npcID == npcID then
            entry.count = entry.count + 1
            entry.minDelay = math.min(entry.minDelay, delay)
            return
        end
    end
    encounter.lootedAfterKill[#encounter.lootedAfterKill + 1] = { npcID = npcID, count = 1, minDelay = delay }
end

-- Encounter loot the client hands out with the encounter ID (personal and
-- group loot rolls on the mainline engine); a link without the creature.
pcall(addon.RegisterEvent, addon, "ENCOUNTER_LOOT_RECEIVED", function(encounterID, itemID)
    encounterID = readable(encounterID)
    itemID = readable(itemID)
    if type(encounterID) ~= "number" or type(itemID) ~= "number" or not addon.IsCapturing("encounters") then
        return
    end
    local catalog = getOrCreateCatalog(getClientInfo())
    local encounter = getEncounter(catalog, encounterID, time())
    encounter.lootReceived = encounter.lootReceived or {}
    for _, entry in ipairs(encounter.lootReceived) do
        if entry.itemID == itemID then
            entry.count = entry.count + 1
            return
        end
    end
    encounter.lootReceived[#encounter.lootReceived + 1] = { itemID = itemID, count = 1 }
end)

addon:RegisterEvent("ENCOUNTER_END", function(encounterID, _, _, _, success)
    encounterID = readable(encounterID)
    if not current or current.encounterID ~= encounterID or not addon.IsCapturing("encounters") then
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
            #names > 0 and table.concat(names, ", ") or "boss from the combat log"
        ))
    end
    current = nil
end)
