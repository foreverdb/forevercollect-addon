local _, addon = ...

local addUniqueValue = addon.AddUniqueValue
local getClientInfo = addon.GetClientInfo
local getOrCreateCatalog = addon.GetOrCreateCatalog
local initializeDatabase = addon.InitializeDatabase
local readTooltipLines = addon.ReadTooltipLines

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

-- Turns a level format string like "Level %s" into a pattern matching the
-- start of the tooltip's level line, independent of the client locale.
local function levelLinePattern(format)
    if type(format) ~= "string" or format == "" then
        return nil
    end
    local marked = string.gsub(format, "%%[%d%$]*[sd]", "\001")
    local escaped = string.gsub(marked, "([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
    return "^" .. (string.gsub(escaped, "\001", ".-"))
end

local levelLinePatterns = {}
for _, format in ipairs({
    TOOLTIP_UNIT_LEVEL,
    TOOLTIP_UNIT_LEVEL_TYPE,
    TOOLTIP_UNIT_LEVEL_CLASS,
    UNIT_LEVEL_TEMPLATE,
}) do
    local pattern = levelLinePattern(format)
    if pattern then
        levelLinePatterns[#levelLinePatterns + 1] = pattern
    end
end

-- Returns the NPC title shown below its name, e.g. "Warrior Trainer". The
-- client has no API for it, so it is read from the unit tooltip: the second
-- line, unless that already is the level line.
local function getNPCSubtitle(unitToken)
    if not readTooltipLines then
        return nil
    end
    local ok, lines = pcall(readTooltipLines, function(tooltip)
        tooltip:SetUnit(unitToken)
    end)
    local text = ok and lines and lines[2] and lines[2].leftText
    if not text or text == "" then
        return nil
    end
    for _, pattern in ipairs(levelLinePatterns) do
        if string.match(text, pattern) then
            return nil
        end
    end
    return (string.gsub(text, "^<(.*)>$", "%1"))
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
        subtitle = getNPCSubtitle(unitToken),
        reaction = UnitReaction and UnitReaction(unitToken, "player") or nil,
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
            or npc.role == "innkeeper" or npc.role == "auctioneer"
            or npc.role == "stableMaster" or npc.role == "guildMaster"
            or npc.role == "tabardVendor" or npc.role == "battlemaster"
            or npc.role == "spiritHealer" or npc.role == "gossip"
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

local function announceNPC(interactionType, details)
    local npc = captureNPCInteraction(interactionType)
    if npc then
        for key, value in pairs(details or {}) do
            npc[key] = value
        end
        addon.Announce(string.format(
            "NPC captured: %s (%s) as %s.",
            npc.name or "unknown",
            tostring(npc.npcID or "?"),
            interactionType
        ))
    end
end

local function questTitles(entries)
    local quests = {}
    for _, entry in ipairs(entries or {}) do
        quests[#quests + 1] = { questID = entry.questID, title = entry.title }
    end
    return quests
end

-- Gossip window contents; for NPCs without a usable service (e.g. a trainer
-- of another class) this is the only thing the client shows.
local function getGossip()
    local gossip = { capturedAt = time(), options = {} }
    if C_GossipInfo and C_GossipInfo.GetText then
        gossip.text = C_GossipInfo.GetText()
        for _, option in ipairs(C_GossipInfo.GetOptions and C_GossipInfo.GetOptions() or {}) do
            gossip.options[#gossip.options + 1] = {
                name = option.name,
                icon = option.icon,
                gossipOptionID = option.gossipOptionID,
            }
        end
        gossip.availableQuests = questTitles(C_GossipInfo.GetAvailableQuests
            and C_GossipInfo.GetAvailableQuests())
        gossip.activeQuests = questTitles(C_GossipInfo.GetActiveQuests
            and C_GossipInfo.GetActiveQuests())
    elseif GetGossipText then
        gossip.text = GetGossipText()
        local values = { GetGossipOptions and GetGossipOptions() }
        for index = 1, #values, 2 do
            gossip.options[#gossip.options + 1] = { name = values[index], type = values[index + 1] }
        end
    end
    return gossip
end

-- Quest greeting: an NPC offering several quests without a gossip window.
local function getQuestGreeting()
    local gossip = {
        capturedAt = time(),
        text = GetGreetingText and GetGreetingText() or nil,
        options = {},
        availableQuests = {},
        activeQuests = {},
    }
    for index = 1, GetNumAvailableQuests and GetNumAvailableQuests() or 0 do
        gossip.availableQuests[index] = { title = GetAvailableTitle(index) }
    end
    for index = 1, GetNumActiveQuests and GetNumActiveQuests() or 0 do
        gossip.activeQuests[index] = { title = GetActiveTitle(index) }
    end
    return gossip
end

-- Registering an event the client does not know raises an error, and the
-- service frames differ between client generations.
local function isEventValid(event)
    if C_EventUtils and C_EventUtils.IsEventValid then
        return C_EventUtils.IsEventValid(event)
    end
    local probe = CreateFrame("Frame")
    local ok = pcall(probe.RegisterEvent, probe, event)
    probe:UnregisterAllEvents()
    return ok
end

addon:RegisterEvent("BANKFRAME_OPENED", function()
    announceNPC("banker")
end)
addon:RegisterEvent("TAXIMAP_OPENED", function()
    announceNPC("flightMaster")
end)
addon:RegisterEvent("GOSSIP_SHOW", function()
    announceNPC("gossip", { gossip = getGossip() })
end)
addon:RegisterEvent("QUEST_GREETING", function()
    announceNPC("gossip", { gossip = getQuestGreeting() })
end)

for event, interactionType in pairs({
    AUCTION_HOUSE_SHOW = "auctioneer",
    PET_STABLE_SHOW = "stableMaster",
    GUILDREGISTRAR_SHOW = "guildMaster",
    PETITION_VENDOR_SHOW = "guildMaster",
    OPEN_TABARD_FRAME = "tabardVendor",
    BATTLEFIELDS_SHOW = "battlemaster",
    -- Innkeepers have no frame of their own; binding the hearthstone is the
    -- one interaction that identifies them.
    CONFIRM_BINDER = "innkeeper",
    CONFIRM_XP_LOSS = "spiritHealer",
}) do
    if isEventValid(event) then
        addon:RegisterEvent(event, function()
            announceNPC(interactionType)
        end)
    end
end
