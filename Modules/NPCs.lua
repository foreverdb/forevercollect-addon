local _, addon = ...

local addUniqueValue = addon.AddUniqueValue
local getClientInfo = addon.GetClientInfo
local getOrCreateCatalog = addon.GetOrCreateCatalog
local initializeDatabase = addon.InitializeDatabase

-- Returns the player's current position; used as an approximation of the
-- position of whatever the player is interacting with.
local function getPlayerLocation()
    local location = {
        source = "playerAtInteraction",
        zone = GetZoneText and GetZoneText() or nil,
        subZone = GetSubZoneText and GetSubZoneText() or nil,
    }

    if C_Map and C_Map.GetBestMapForUnit then
        local uiMapID = C_Map.GetBestMapForUnit("player")
        if uiMapID then
            location.uiMapID = uiMapID
            local mapInfo = C_Map.GetMapInfo and C_Map.GetMapInfo(uiMapID)
            if mapInfo then
                location.mapName = mapInfo.name
                location.mapType = mapInfo.mapType
                location.parentMapID = mapInfo.parentMapID
            end

            if C_Map.GetPlayerMapPosition then
                local position = C_Map.GetPlayerMapPosition(uiMapID, "player")
                if position and position.GetXY then
                    location.x, location.y = position:GetXY()

                    if C_Map.GetWorldPosFromMapPos then
                        local continentID, worldPosition =
                            C_Map.GetWorldPosFromMapPos(uiMapID, position)
                        if continentID and worldPosition and worldPosition.GetXY then
                            location.worldContinentID = continentID
                            location.worldX, location.worldY = worldPosition:GetXY()
                        end
                    end
                end
            end
        end
    end

    return location
end
addon.GetPlayerLocation = getPlayerLocation

-- Splits a unit GUID like "Creature-0-1234-0-5-6018-0000ABCDEF" into its
-- object type and object ID.
function addon.ParseGUID(guid)
    if not guid then
        return nil, nil
    end
    local objectType, objectID = string.match(guid, "^(%a+)%-0%-%d+%-%d+%-%d+%-(%d+)%-")
    if not objectType then
        objectType = string.match(guid, "^([^-]+)")
    end
    return objectType, tonumber(objectID)
end

function addon.GetNPCKey(npc)
    if npc.guid then
        return npc.guid
    end
    return string.format("%s:%s", tostring(npc.npcID or "Unknown"), npc.name or "Unknown")
end

local function getNPC(unitToken, interactionType, role)
    local guid = UnitGUID and UnitGUID(unitToken) or nil
    local name = UnitName and UnitName(unitToken) or nil
    local creatureID = UnitCreatureID and UnitCreatureID(unitToken) or nil
    local objectType = guid and string.match(guid, "^([^-]+)") or nil
    local location = getPlayerLocation()

    local npc = {
        role = role,
        guid = guid,
        objectType = objectType,
        objectID = creatureID,
        npcID = creatureID,
        name = name,
        interactionTypes = { interactionType },
        creatureType = UnitCreatureType and UnitCreatureType(unitToken) or nil,
        classification = UnitClassification and UnitClassification(unitToken) or nil,
        location = location,
    }

    return npc
end
addon.GetNPC = getNPC

local function npcMatches(left, right)
    if left.guid and right.guid then
        return left.guid == right.guid
    end
    if left.npcID and right.npcID then
        return left.npcID == right.npcID
            and (not left.name or not right.name or left.name == right.name)
    end
    return left.name and right.name and left.name == right.name
end

local function normalizeNPC(npc)
    if not npc then
        return nil
    end
    npc.interactionTypes = npc.interactionTypes or {}
    if #npc.interactionTypes == 0 then
        if npc.role == "giver" or npc.role == "progress" or npc.role == "turnIn" then
            npc.interactionTypes[1] = "questGiver"
        elseif npc.role == "merchant" or npc.role == "trainer"
            or npc.role == "banker" or npc.role == "flightMaster"
            or npc.role == "innkeeper"
        then
            npc.interactionTypes[1] = npc.role
        end
    end
    npc.location = npc.location or { source = "playerAtInteraction" }
    npc.location.source = npc.location.source or "playerAtInteraction"
    npc.creatureType = npc.creatureType or "Unknown"
    npc.classification = npc.classification or "unknown"
    return npc
end

local function mergeNPC(catalog, npc)
    normalizeNPC(npc)
    for _, existing in ipairs(catalog.npcs) do
        if npcMatches(existing, npc) then
            existing.interactionTypes = existing.interactionTypes or {}
            for _, interactionType in ipairs(npc.interactionTypes) do
                addUniqueValue(existing.interactionTypes, interactionType)
            end
            for key, value in pairs(npc) do
                if value ~= nil and key ~= "interactionTypes"
                    and (key ~= "role" or existing.role == nil)
                then
                    existing[key] = value
                end
            end
            return existing
        end
    end
    catalog.npcs[#catalog.npcs + 1] = npc
    return npc
end
addon.MergeNPC = mergeNPC

function addon.MigrateNPCData()
    initializeDatabase()
    for _, catalog in pairs(ForeverCollectDB.catalogs) do
        catalog.npcs = catalog.npcs or {}
        for _, quest in pairs(catalog.quests or {}) do
            for _, observation in ipairs(quest.observations or {}) do
                local npc = normalizeNPC(observation.questNPC)
                if npc then
                    mergeNPC(catalog, npc)
                end
            end
        end
        for _, npc in ipairs(catalog.npcs) do
            normalizeNPC(npc)
        end
    end
end

local function captureNPCInteraction(interactionType, role)
    local catalog = getOrCreateCatalog(getClientInfo())
    local unitToken = "npc"
    if not UnitGUID(unitToken) and UnitGUID("target")
        and (not UnitIsPlayer or not UnitIsPlayer("target"))
    then
        unitToken = "target"
    end
    local npc = getNPC(unitToken, interactionType, role or interactionType)
    if not npc.guid and not npc.npcID and not npc.name then
        return
    end
    local merged = mergeNPC(catalog, npc)
    catalog.npcScanUpdatedAt = time()
    return merged
end
addon.CaptureNPCInteraction = captureNPCInteraction

addon:RegisterEvent("BANKFRAME_OPENED", function()
    captureNPCInteraction("banker")
end)
addon:RegisterEvent("TAXIMAP_OPENED", function()
    captureNPCInteraction("flightMaster")
end)
--addon:RegisterEvent("INNKEEPER_SHOW", function()
--    captureNPCInteraction("innkeeper")
--end)
