local _, addon = ...

-- Asks the server for every item the client has no data for (ForeverCollectCacheIDs.items from the
-- local addon ForeverCollect_CacheIDs, which `foreverdb-import item-ids` writes into the
-- installation: Item.db2 rows whose ItemSparse row sits in an encrypted section). Players do not
-- need the list, so it is not part of the release.
-- The server answers with the item's rows, which the client keeps in
-- Cache/ADB/<locale>/DBCache.bin; the importer's db2 step merges them like hotfixes.

addon.ItemCacheStatus = addon.NewCacheCrawl({
    command = "itemcache",
    label = "Item cache",
    unit = "item",
    cacheFile = "DBCache.bin",
    settingsKey = "itemCacheCrawl",
    ids = function()
        return ForeverCollectCacheIDs and ForeverCollectCacheIDs.items
    end,
    request = function(itemID)
        C_Item.RequestLoadItemDataByID(itemID)
    end,
    resultEvent = "ITEM_DATA_LOAD_RESULT",
    isSupported = function()
        return C_Item and C_Item.RequestLoadItemDataByID ~= nil
    end,
    unsupported = "Item cache: this client has no C_Item.RequestLoadItemDataByID or no ForeverCollect_CacheIDs addon (foreverdb-import item-ids).",
    help = "Query all items without client data from the server so DBCache.bin contains them (stop, status, reset)",
})
