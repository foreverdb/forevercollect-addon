local _, addon = ...

local printMessage = addon.PrintMessage
local getItemIDFromLink = addon.GetItemIDFromLink
local addUniqueLocation = addon.AddUniqueLocation
local getPlayerLocation = addon.GetPlayerLocation
local parseGUID = addon.ParseGUID
local getClientInfo = addon.GetClientInfo
local getOrCreateCatalog = addon.GetOrCreateCatalog
local getLatestCatalog = addon.GetLatestCatalog
local recordItem = addon.RecordItem

local LOOT_SLOT_ITEM = LOOT_SLOT_ITEM or 1
local LOOT_SLOT_MONEY = LOOT_SLOT_MONEY or 2
local SOURCE_LOCATION_CAP = 100
local ITEM_LOCATION_CAP = 20

-- Loot containers (corpses, nodes) already counted this session, so that
-- reopening the same loot window does not inflate the counters.
local seenLootGUIDs = {}

local function getSourceKey(sourceType, sourceID)
    if sourceID then
        return string.format("%s:%d", sourceType, sourceID)
    end
    return sourceType
end

local function moneyPattern(globalString)
    return "^" .. string.gsub(globalString or "", "%%d", "(%%d+)") .. "$"
end

local function parseMoneyText(text)
    local total = 0
    for _, part in ipairs({ strsplit("\n", text or "") }) do
        local gold = tonumber(string.match(part, moneyPattern(GOLD_AMOUNT)))
        local silver = tonumber(string.match(part, moneyPattern(SILVER_AMOUNT)))
        local copper = tonumber(string.match(part, moneyPattern(COPPER_AMOUNT)))
        total = total + (gold or 0) * 10000 + (silver or 0) * 100 + (copper or 0)
    end
    return total
end

-- Returns the GUIDs the loot in `slot` came from. Falls back to the dead
-- target when the client does not report loot sources.
local function getSlotSourceGUIDs(slot)
    local guids = {}
    if GetLootSourceInfo then
        local sources = { GetLootSourceInfo(slot) }
        for index = 1, #sources, 2 do
            guids[#guids + 1] = sources[index]
        end
    end
    if #guids == 0 and UnitGUID("target") and UnitIsDead and UnitIsDead("target") then
        guids[1] = UnitGUID("target")
    end
    return guids
end

local function describeSource(guid)
    if IsFishingLoot and IsFishingLoot() then
        return "Fishing", nil, nil
    end
    local sourceType, sourceID = parseGUID(guid)
    local name
    if guid and UnitGUID("target") == guid then
        name = UnitName("target")
    end
    return sourceType or "Unknown", sourceID, name
end

local function getOrCreateSource(catalog, sourceType, sourceID, name, now)
    local key = getSourceKey(sourceType, sourceID)
    local source = catalog.lootSources[key]
    if not source then
        source = {
            sourceType = sourceType,
            sourceID = sourceID,
            firstSeenAt = now,
            lootCount = 0,
            locations = {},
            items = {},
            money = { timesSeen = 0, total = 0 },
        }
        catalog.lootSources[key] = source
    end
    source.name = name or source.name
    source.lastSeenAt = now
    return source
end

-- GetLootSlotInfo returns `currencyID` as fourth value on newer clients only;
-- detect the signature by the type of the fifth value (`locked` is boolean).
local function getLootSlotInfo(slot)
    local _, name, quantity, value4, value5, value6, value7, value8 = GetLootSlotInfo(slot)
    if type(value5) == "boolean" then
        return name, quantity, value4, value6, value7
    end
    return name, quantity, value5, value7, value8
end

local function scanLoot()
    if not GetNumLootItems or not GetLootSlotInfo or not GetLootSlotLink then
        return
    end
    local numSlots = GetNumLootItems()
    if numSlots == 0 then
        return
    end

    local catalog = getOrCreateCatalog(getClientInfo())
    local now = time()
    local location = getPlayerLocation()
    local countedSources = {}

    for slot = 1, numSlots do
        local slotType = GetLootSlotType and GetLootSlotType(slot) or LOOT_SLOT_ITEM
        local name, quantity, quality, isQuestItem, questID = getLootSlotInfo(slot)
        local link = slotType == LOOT_SLOT_ITEM and GetLootSlotLink(slot) or nil

        local guids = getSlotSourceGUIDs(slot)
        if #guids == 0 then
            guids[1] = false
        end
        for _, guid in ipairs(guids) do
            if guid and seenLootGUIDs[guid] then
                -- already counted this container
            else
                local sourceType, sourceID, sourceName = describeSource(guid or nil)
                local source = getOrCreateSource(catalog, sourceType, sourceID, sourceName, now)
                local sourceKey = getSourceKey(sourceType, sourceID)
                if not countedSources[sourceKey] then
                    countedSources[sourceKey] = true
                    source.lootCount = source.lootCount + 1
                    addUniqueLocation(source.locations, location, SOURCE_LOCATION_CAP)
                end

                if slotType == LOOT_SLOT_MONEY then
                    source.money.timesSeen = source.money.timesSeen + 1
                    source.money.total = source.money.total + parseMoneyText(name)
                elseif link then
                    local itemID = getItemIDFromLink(link)
                    if itemID then
                        local item = source.items[itemID]
                        if not item then
                            item = {
                                itemID = itemID,
                                timesSeen = 0,
                                quantityTotal = 0,
                                locations = {},
                            }
                            source.items[itemID] = item
                        end
                        item.name = name
                        item.link = link
                        item.quality = quality
                        item.isQuestItem = isQuestItem and true or false
                        item.questID = questID and questID ~= 0 and questID or item.questID
                        item.timesSeen = item.timesSeen + 1
                        item.quantityTotal = item.quantityTotal + (quantity or 1)
                        item.lastSeenAt = now
                        addUniqueLocation(item.locations, location, ITEM_LOCATION_CAP)

                        recordItem(link, {
                            type = "loot",
                            sourceType = sourceType,
                            sourceID = sourceID,
                            name = source.name,
                            location = location,
                        })
                    end
                end
            end
        end
    end

    for slot = 1, numSlots do
        for _, guid in ipairs(getSlotSourceGUIDs(slot)) do
            seenLootGUIDs[guid] = true
        end
    end
    catalog.lootUpdatedAt = now
end

addon:RegisterEvent("LOOT_OPENED", function()
    local ok, err = pcall(scanLoot)
    if not ok then
        printMessage("Loot scan failed: " .. tostring(err))
    end
end)

local function countLoot(catalog)
    local sourceCount, itemCount = 0, 0
    for _, source in pairs(catalog.lootSources or {}) do
        sourceCount = sourceCount + 1
        for _ in pairs(source.items) do
            itemCount = itemCount + 1
        end
    end
    return sourceCount, itemCount
end
addon.CountLoot = countLoot

addon:RegisterCommand("loot", function()
    local catalog = getLatestCatalog()
    if not catalog then
        printMessage("No catalog found. Loot something first.")
        return
    end
    local sourceCount, itemCount = countLoot(catalog)
    printMessage(string.format(
        "Loot catalog contains %d sources with %d distinct items.",
        sourceCount,
        itemCount
    ))
end, "Loot-Quellen und -Items anzeigen")
