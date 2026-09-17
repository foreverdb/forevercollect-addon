local _, addon = ...

local printMessage = addon.PrintMessage
local formatTimestamp = addon.FormatTimestamp
local getItemIDFromLink = addon.GetItemIDFromLink
local getClientInfo = addon.GetClientInfo
local getOrCreateCatalog = addon.GetOrCreateCatalog
local getLatestCatalog = addon.GetLatestCatalog
local getCharacterContext = addon.GetCharacterContext
local captureNPCInteraction = addon.CaptureNPCInteraction
local getNPCKey = addon.GetNPCKey
local recordItem = addon.RecordItem

local isScanningMerchant
local hasAnnouncedMerchant

local function readExtendedCost(index)
    local costs = {}
    if not GetMerchantItemCostInfo or not GetMerchantItemCostItem then
        return costs
    end
    for costIndex = 1, GetMerchantItemCostInfo(index) or 0 do
        local texture, count, link, name = GetMerchantItemCostItem(index, costIndex)
        costs[#costs + 1] = {
            itemID = getItemIDFromLink(link),
            name = name,
            link = link,
            texture = texture,
            count = count,
        }
    end
    return costs
end

-- Clients on the mainline engine (Forever 1.60+) replaced GetMerchantItemInfo
-- with C_MerchantFrame.GetItemInfo, which returns a table instead of a list.
local function getMerchantItemInfo(index)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = C_MerchantFrame.GetItemInfo(index)
        if not info then
            return nil
        end
        return info.name, info.texture, info.price, info.stackCount, info.numAvailable,
            info.isPurchasable, info.isUsable, info.hasExtendedCost
    end
    return GetMerchantItemInfo(index)
end

local function hasMerchantAPI()
    local hasItemInfo = (C_MerchantFrame and C_MerchantFrame.GetItemInfo) or GetMerchantItemInfo
    return GetMerchantNumItems and hasItemInfo and GetMerchantItemLink
end

local function readMerchantItems(source)
    local items = {}
    for index = 1, GetMerchantNumItems() do
        local name, texture, price, stackCount, numAvailable, isPurchasable,
            isUsable, extendedCost = getMerchantItemInfo(index)
        local link = GetMerchantItemLink(index)
        if name or link then
            local item = {
                index = index,
                itemID = getItemIDFromLink(link),
                name = name,
                link = link,
                texture = texture,
                price = price,
                stackCount = stackCount,
                maxStack = GetMerchantItemMaxStack and GetMerchantItemMaxStack(index) or nil,
                numAvailable = numAvailable,
                isPurchasable = isPurchasable and true or false,
                isUsable = isUsable and true or false,
                hasExtendedCost = extendedCost and true or false,
            }
            if extendedCost then
                item.extendedCost = readExtendedCost(index)
                for _, cost in ipairs(item.extendedCost) do
                    if cost.link then
                        recordItem(cost.link, source)
                    end
                end
            end
            if link then
                recordItem(link, source)
            end
            items[#items + 1] = item
        end
    end
    return items
end

local function scanMerchant(silent)
    if isScanningMerchant then
        return nil
    end
    if not hasMerchantAPI() then
        printMessage("This client does not provide the merchant API.")
        return nil
    end
    isScanningMerchant = true

    local npc = captureNPCInteraction("merchant")
    if not npc then
        isScanningMerchant = nil
        return nil
    end

    local source = {
        type = "merchant",
        npcID = npc.npcID,
        name = npc.name,
        location = npc.location,
    }
    local ok, items = pcall(readMerchantItems, source)
    isScanningMerchant = nil
    if not ok then
        printMessage("Merchant scan failed: " .. tostring(items))
        return nil
    end
    if #items == 0 then
        return nil
    end

    local snapshot = {
        capturedAt = time(),
        character = getCharacterContext(),
        merchantNPC = npc,
        canRepair = CanMerchantRepair and CanMerchantRepair() and true or false,
        items = items,
    }

    local catalog = getOrCreateCatalog(getClientInfo())
    catalog.merchantSnapshots[getNPCKey(npc)] = snapshot
    catalog.merchantScanUpdatedAt = snapshot.capturedAt

    if not silent or not hasAnnouncedMerchant then
        hasAnnouncedMerchant = true
        printMessage(string.format(
            "Captured %d merchant items from %s.",
            #items,
            npc.name or "unknown merchant"
        ))
    end
    return snapshot
end
addon.ScanMerchant = scanMerchant

addon:RegisterEvent("MERCHANT_SHOW", function()
    hasAnnouncedMerchant = nil
    scanMerchant(false)
end)

-- Fires when stock changes (e.g. after buying a limited item) and when the
-- item list arrives after MERCHANT_SHOW.
addon:RegisterEvent("MERCHANT_UPDATE", function()
    scanMerchant(true)
end)

addon:RegisterEvent("MERCHANT_CLOSED", function()
    hasAnnouncedMerchant = nil
end)

addon:RegisterCommand("merchants", function()
    if GetMerchantNumItems and GetMerchantNumItems() > 0 then
        scanMerchant(false)
    end

    local catalog = getLatestCatalog()
    local snapshots = catalog and catalog.merchantSnapshots
    if not snapshots or not next(snapshots) then
        printMessage("No merchant snapshot found. Open a merchant first.")
        return
    end

    local merchantCount, itemCount, latest = 0, 0, nil
    for _, snapshot in pairs(snapshots) do
        merchantCount = merchantCount + 1
        itemCount = itemCount + #snapshot.items
        if not latest or snapshot.capturedAt > latest.capturedAt then
            latest = snapshot
        end
    end
    printMessage(string.format(
        "%d merchants with %d items captured (latest: %s at %s).",
        merchantCount,
        itemCount,
        latest.merchantNPC.name or "Unknown",
        formatTimestamp(latest.capturedAt)
    ))
end, "Händler-Sortimente anzeigen")
