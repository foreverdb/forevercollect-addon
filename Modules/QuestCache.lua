local _, addon = ...

-- Asks the server for every quest the client knows (Data/QuestIDs.lua, generated from
-- QuestV2.db2 by `foreverdb-import quest-ids`). The client stores each answer in
-- Cache/WDB/<locale>/questcache.wdb, which the importer reads.

addon.QuestCacheStatus = addon.NewCacheCrawl({
    command = "questcache",
    label = "Quest cache",
    unit = "quest",
    cacheFile = "questcache.wdb",
    settingsKey = "questCacheCrawl",
    ids = function()
        return addon.QuestIDs
    end,
    request = function(questID)
        C_QuestLog.RequestLoadQuestByID(questID)
    end,
    resultEvent = "QUEST_DATA_LOAD_RESULT",
    isSupported = function()
        return C_QuestLog and C_QuestLog.RequestLoadQuestByID ~= nil
    end,
    unsupported = "Quest cache: this client has no C_QuestLog.RequestLoadQuestByID or no Data/QuestIDs.lua.",
    help = "Query all quests from the server so questcache.wdb contains them (stop, status, reset)",
})
