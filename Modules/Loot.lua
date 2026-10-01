local _, addon = ...

local printMessage = addon.PrintMessage
local announce = addon.Announce
local formatMoney = addon.FormatMoney
local getItemIDFromLink = addon.GetItemIDFromLink
local addUniqueLocation = addon.AddUniqueLocation
local countLocation = addon.CountLocation
local getPlayerLocation = addon.GetPlayerLocation
local parseGUID = addon.ParseGUID
local getClientInfo = addon.GetClientInfo
local getOrCreateCatalog = addon.GetOrCreateCatalog
local getLatestCatalog = addon.GetLatestCatalog
local recordItem = addon.RecordItem
local consumePendingGather = addon.ConsumePendingGather
local readable = addon.Readable
local getInstance = addon.GetInstance

local LOOT_SLOT_ITEM = LOOT_SLOT_ITEM or 1
local LOOT_SLOT_MONEY = LOOT_SLOT_MONEY or 2
local SOURCE_LOCATION_CAP = 100
local ITEM_LOCATION_CAP = 20
-- Profession finds keep more spots, each with a hit count and timestamps, so
-- spawn points and gathering pace can be derived (where farming pays off).
local GATHER_SOURCE_LOCATION_CAP = 500
local GATHER_ITEM_LOCATION_CAP = 100
local GATHER_LOCATION_TIMES_CAP = 20

-- Loot containers (corpses, nodes) already counted this session, so that
-- reopening the same loot window does not inflate the counters.
local seenLootGUIDs = {}

-- Profession finds get their own key ("Herbalism:GameObject:1617",
-- "Skinning:Creature:705") so skins never mix with a creature's regular loot.
local function getSourceKey(sourceType, sourceID, profession)
    local key = sourceType
    if sourceID then
        key = string.format("%s:%d", sourceType, sourceID)
    end
    if profession and profession ~= sourceType then
        key = profession .. ":" .. key
    end
    return key
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
-- target when the client does not report loot sources. Secret GUIDs (hostile
-- units in instanced content on the mainline engine) are left out: they can
-- neither be parsed nor used as table keys.
local function getSlotSourceGUIDs(slot)
    local guids = {}
    if GetLootSourceInfo then
        local sources = { GetLootSourceInfo(slot) }
        for index = 1, #sources, 2 do
            local guid = readable(sources[index])
            if guid then
                guids[#guids + 1] = guid
            end
        end
    end
    if #guids == 0 and UnitIsDead and UnitIsDead("target") then
        guids[1] = readable(UnitGUID("target"))
    end
    return guids
end

local function describeSource(guid, gather)
    if IsFishingLoot and IsFishingLoot() then
        return "Fishing", nil, nil
    end
    -- Loot of hostile units in instances has only secret GUIDs, so it is
    -- filed under the instance instead of an unattributable "Unknown".
    if not guid and not gather then
        local instanceID, instanceName = getInstance()
        if instanceID then
            return "Instance", instanceID, instanceName
        end
    end
    local sourceType, sourceID = parseGUID(guid)
    local name
    if guid and readable(UnitGUID("target")) == guid then
        name = readable(UnitName("target"))
    end
    return sourceType or "Unknown", sourceID, name
end

local function getOrCreateSource(catalog, sourceType, sourceID, name, now, gather)
    local profession = gather and gather.profession or nil
    local key = getSourceKey(sourceType, sourceID, profession)
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
    if gather then
        source.profession = gather.profession
        source.gatherSpellID = gather.spellID
    end
    source.name = name or source.name
    -- Positions are unavailable inside instances, so the instance ties the
    -- source (bosses and trash alike) to its dungeon.
    source.instanceID = getInstance() or source.instanceID
    source.lastSeenAt = now
    return source
end

-- GetLootSlotInfo returns `currencyID` as fourth value on newer clients only;
-- detect the signature by the type of the fifth value (`locked` is boolean).
local function getLootSlotInfo(slot)
    local _, name, quantity, value4, value5, value6, value7, value8 = GetLootSlotInfo(slot)
    local quality, isQuestItem, questID = value5, value7, value8
    if type(value5) == "boolean" then
        quality, isQuestItem, questID = value4, value6, value7
    end
    return readable(name), readable(quantity), readable(quality), readable(isQuestItem), readable(questID)
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
    local gather = consumePendingGather()
    local summary = { items = 0, money = 0, sources = {}, sourceNames = {}, itemNames = {} }

    for slot = 1, numSlots do
        local slotType = GetLootSlotType and GetLootSlotType(slot) or LOOT_SLOT_ITEM
        local name, quantity, quality, isQuestItem, questID = getLootSlotInfo(slot)
        local link = slotType == LOOT_SLOT_ITEM and GetLootSlotLink(slot) or nil

        local guids = getSlotSourceGUIDs(slot)
        if #guids == 0 then
            guids[1] = false
        end
        for _, guid in ipairs(guids) do
            -- A skinned corpse was already counted as regular loot; profession
            -- finds are recorded under their own key, so they bypass that check.
            if guid and seenLootGUIDs[guid] and not gather then
                -- already counted this container
            else
                local sourceType, sourceID, sourceName = describeSource(guid or nil, gather)
                if gather and not sourceName then
                    sourceName = gather.nodeName
                end
                local source = getOrCreateSource(catalog, sourceType, sourceID, sourceName, now, gather)
                local sourceKey = getSourceKey(sourceType, sourceID, gather and gather.profession)
                if not countedSources[sourceKey] then
                    countedSources[sourceKey] = true
                    source.lootCount = source.lootCount + 1
                    if gather then
                        countLocation(source.locations, location, GATHER_SOURCE_LOCATION_CAP, now, GATHER_LOCATION_TIMES_CAP)
                    else
                        addUniqueLocation(source.locations, location, SOURCE_LOCATION_CAP)
                    end
                    summary.sources[#summary.sources + 1] = sourceKey
                    summary.sourceNames[#summary.sourceNames + 1] = source.name or sourceKey
                end

                if slotType == LOOT_SLOT_MONEY then
                    local copper = parseMoneyText(name)
                    source.money.timesSeen = source.money.timesSeen + 1
                    source.money.total = source.money.total + copper
                    summary.money = summary.money + copper
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
                        if gather then
                            countLocation(item.locations, location, GATHER_ITEM_LOCATION_CAP, now, GATHER_LOCATION_TIMES_CAP)
                        else
                            addUniqueLocation(item.locations, location, ITEM_LOCATION_CAP)
                        end
                        summary.items = summary.items + 1
                        summary.itemNames[#summary.itemNames + 1] = string.format("%s x%d", name or "?", quantity or 1)
                        summary.firstItemName = summary.firstItemName or name

                        recordItem(link, {
                            type = "loot",
                            sourceType = sourceType,
                            sourceID = sourceID,
                            profession = gather and gather.profession or nil,
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

    -- Nodes without a readable tooltip name are named after what they yielded
    -- ("Peacebloom" node -> Peacebloom), which is how players refer to them anyway.
    if gather and summary.firstItemName then
        for _, sourceKey in ipairs(summary.sources) do
            local source = catalog.lootSources[sourceKey]
            if source and not source.name then
                source.name = summary.firstItemName
            end
        end
        for index, sourceName in ipairs(summary.sourceNames) do
            if sourceName == summary.sources[index] then
                summary.sourceNames[index] = summary.firstItemName
            end
        end
    end

    if #summary.sources > 0 then
        local moneyText = summary.money > 0 and (", " .. formatMoney(summary.money)) or ""
        if gather then
            local where = location.zone or location.mapName or "unknown zone"
            if location.subZone and location.subZone ~= "" then
                where = where .. " - " .. location.subZone
            end
            announce(string.format(
                "%s: %s from %s in %s.",
                gather.profession,
                #summary.itemNames > 0 and table.concat(summary.itemNames, ", ") or "nothing",
                table.concat(summary.sourceNames, ", "),
                where
            ))
        else
            announce(string.format(
                "Loot captured from %s: %d item(s)%s.",
                table.concat(summary.sourceNames, ", "),
                summary.items,
                moneyText
            ))
        end
    end
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
