local _, addon = ...

-- Asks the server for every quest the client knows (ForeverCollectCacheIDs.quests from the local
-- addon ForeverCollect_CacheIDs, which `foreverdb-import quest-ids` writes into the installation
-- from QuestV2.db2; not part of the release). The client stores each answer in
-- Cache/WDB/<locale>/questcache.wdb, which the importer reads.

addon.QuestCacheStatus = addon.NewCacheCrawl({
    command = "questcache",
    label = "Quest cache",
    unit = "quest",
    cacheFile = "questcache.wdb",
    settingsKey = "questCacheCrawl",
    ids = function()
        return ForeverCollectCacheIDs and ForeverCollectCacheIDs.quests
    end,
    request = function(questID)
        C_QuestLog.RequestLoadQuestByID(questID)
    end,
    resultEvent = "QUEST_DATA_LOAD_RESULT",
    isSupported = function()
        return C_QuestLog and C_QuestLog.RequestLoadQuestByID ~= nil
    end,
    unsupported = "Quest cache: this client has no C_QuestLog.RequestLoadQuestByID or no ForeverCollect_CacheIDs addon (foreverdb-import quest-ids).",
    help = "Query all quests from the server so questcache.wdb contains them (stop, status, reset)",
})
