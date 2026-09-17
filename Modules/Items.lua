local _, addon = ...

local printMessage = addon.PrintMessage
local getItemIDFromLink = addon.GetItemIDFromLink
local addUniqueLocation = addon.AddUniqueLocation
local getClientInfo = addon.GetClientInfo
local getOrCreateCatalog = addon.GetOrCreateCatalog
local getLatestCatalog = addon.GetLatestCatalog

local LOOT_LOCATION_CAP = 20

-- The catalog only records where an item was seen. Static item data (name,
-- quality, stats, sell price, ...) comes from the client's DB2 tables via the
-- server-side wow.export importer, so nothing is read from the item cache here.

local function getSourceKey(source)
    if source.type == "merchant" then
        return "merchant:" .. tostring(source.npcID or source.name or "Unknown")
    elseif source.type == "quest" then
        return "quest:" .. tostring(source.questID)
    elseif source.type == "loot" then
        return string.format("loot:%s:%s", tostring(source.sourceType), tostring(source.sourceID))
    end
    return tostring(source.type)
end

-- Records that `linkOrItemID` was seen at `source` (a table with `type` and
-- the identifying fields for that type) and returns the catalog entry.
local function recordItem(linkOrItemID, source)
    local itemID, link
    if type(linkOrItemID) == "number" then
        itemID = linkOrItemID
    else
        link = linkOrItemID
        itemID = getItemIDFromLink(link)
    end
    if not itemID then
        return nil
    end

    local catalog = getOrCreateCatalog(getClientInfo())
    local now = time()
    local item = catalog.items[itemID]
    if not item then
        item = {
            itemID = itemID,
            firstSeenAt = now,
            sources = {},
        }
        catalog.items[itemID] = item
    end
    item.link = item.link or link
    item.lastSeenAt = now

    if source and source.type then
        local key = getSourceKey(source)
        local entry = item.sources[key]
        if not entry then
            entry = {
                type = source.type,
                npcID = source.npcID,
                questID = source.questID,
                sourceType = source.sourceType,
                sourceID = source.sourceID,
                skillName = source.skillName,
                name = source.name,
                firstSeenAt = now,
                timesSeen = 0,
            }
            item.sources[key] = entry
        end
        entry.timesSeen = entry.timesSeen + 1
        entry.lastSeenAt = now
        entry.name = source.name or entry.name

        if source.location then
            if source.type == "loot" then
                entry.locations = entry.locations or {}
                addUniqueLocation(entry.locations, source.location, LOOT_LOCATION_CAP)
            elseif not entry.location then
                entry.location = source.location
            end
        end
    end

    catalog.itemsUpdatedAt = now
    return item
end
addon.RecordItem = recordItem

local function countItems(catalog)
    local total = 0
    for _ in pairs(catalog.items or {}) do
        total = total + 1
    end
    return total
end
addon.CountItems = countItems

addon:RegisterCommand("items", function()
    local catalog = getLatestCatalog()
    if not catalog then
        printMessage("No catalog found. Interact with a merchant, quest giver or loot first.")
        return
    end
    printMessage(string.format("Item catalog contains %d items.", countItems(catalog)))
end, "Anzahl erfasster Items anzeigen")
