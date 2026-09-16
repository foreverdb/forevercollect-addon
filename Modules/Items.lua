local _, addon = ...

local printMessage = addon.PrintMessage
local readTooltipLines = addon.ReadTooltipLines
local getItemIDFromLink = addon.GetItemIDFromLink
local addUniqueLocation = addon.AddUniqueLocation
local getClientInfo = addon.GetClientInfo
local getOrCreateCatalog = addon.GetOrCreateCatalog
local getLatestCatalog = addon.GetLatestCatalog

local LOOT_LOCATION_CAP = 20

-- Items whose details are still being requested from the server, keyed by
-- item ID (only used by the GET_ITEM_INFO_RECEIVED fallback).
local pendingItems = {}

local function getSourceKey(source)
    if source.type == "merchant" then
        return "merchant:" .. tostring(source.npcID or source.name or "Unknown")
    elseif source.type == "quest" then
        return "quest:" .. tostring(source.questID)
    elseif source.type == "loot" then
        return string.format("loot:%s:%s", tostring(source.sourceType), tostring(source.sourceID))
    elseif source.type == "recipe" then
        return "recipe:" .. tostring(source.skillName)
    end
    return tostring(source.type)
end

local function getItemTooltipLines(link)
    return readTooltipLines(function(tooltip)
        tooltip:SetHyperlink(link)
    end)
end

local function getItemStats(link)
    if C_Item and C_Item.GetItemStats then
        return C_Item.GetItemStats(link)
    elseif GetItemStats then
        return GetItemStats(link)
    end
    return nil
end

local function getItemSpell(itemID)
    local spellName, spellID
    if C_Item and C_Item.GetItemSpell then
        spellName, spellID = C_Item.GetItemSpell(itemID)
    elseif GetItemSpell then
        spellName, spellID = GetItemSpell(itemID)
    end
    if spellName or spellID then
        return { name = spellName, spellID = spellID }
    end
    return nil
end

-- Fills `item` from the client's item cache. Returns false when the item is
-- not cached yet.
local function fillItemDetails(item)
    local name, link, quality, itemLevel, requiredLevel, itemType, itemSubType,
        stackCount, equipLoc, texture, sellPrice, classID, subclassID, bindType,
        expansionID, setID, isCraftingReagent = GetItemInfo(item.link or item.itemID)
    if not name then
        return false
    end

    item.name = name
    item.link = item.link or link
    item.quality = quality
    item.itemLevel = itemLevel
    item.requiredLevel = requiredLevel
    item.itemType = itemType
    item.itemSubType = itemSubType
    item.stackCount = stackCount
    item.equipLoc = equipLoc
    item.texture = texture
    item.sellPrice = sellPrice
    item.classID = classID
    item.subclassID = subclassID
    item.bindType = bindType
    item.expansionID = expansionID
    item.setID = setID
    item.isCraftingReagent = isCraftingReagent and true or false
    item.spell = getItemSpell(item.itemID)
    item.stats = getItemStats(item.link)
    item.tooltipLines = getItemTooltipLines(item.link)
    item.detailsLoaded = true
    item.updatedAt = time()
    return true
end

local function requestItemDetails(item)
    if fillItemDetails(item) then
        return
    end

    if Item and Item.CreateFromItemID then
        local itemObject = Item:CreateFromItemID(item.itemID)
        if not itemObject:IsItemEmpty() then
            itemObject:ContinueOnItemLoad(function()
                fillItemDetails(item)
            end)
        end
        return
    end

    pendingItems[item.itemID] = item
end

addon:RegisterEvent("GET_ITEM_INFO_RECEIVED", function(itemID, success)
    local item = pendingItems[itemID]
    if not item then
        return
    end
    if success == false or fillItemDetails(item) then
        pendingItems[itemID] = nil
    end
end)

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
            detailsLoaded = false,
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

    if not item.detailsLoaded then
        requestItemDetails(item)
    end
    catalog.itemsUpdatedAt = now
    return item
end
addon.RecordItem = recordItem

local function countItems(catalog)
    local total, loaded = 0, 0
    for _, item in pairs(catalog.items or {}) do
        total = total + 1
        if item.detailsLoaded then
            loaded = loaded + 1
        end
    end
    return total, loaded
end
addon.CountItems = countItems

addon:RegisterCommand("items", function()
    local catalog = getLatestCatalog()
    if not catalog then
        printMessage("No catalog found. Interact with a merchant, quest giver or loot first.")
        return
    end
    local total, loaded = countItems(catalog)
    printMessage(string.format("Item catalog contains %d items (%d with details).", total, loaded))
end, "Anzahl erfasster Items anzeigen")
