local _, addon = ...

-- Asks the server for every quest the client knows (Data/QuestIDs.lua, generated from
-- QuestV2.db2 by `foreverdb-import quest-ids`). The client stores each answer in
-- Cache/WDB/<locale>/questcache.wdb, which the importer reads; nothing is saved here except the
-- crawl position, so a /reload or logout continues where it stopped.

local printMessage = addon.PrintMessage

local REQUESTS_PER_TICK = 5
local TICK_SECONDS = 0.25 -- 20 requests per second
local REPORT_EVERY = 500

local ticker
local loaded, failed = 0, 0

local function getState()
    local settings = ForeverCollectDB.settings
    local build = select(2, GetBuildInfo())
    local state = settings.questCacheCrawl
    if not state or state.build ~= build then
        state = { build = build, nextIndex = 1 }
        settings.questCacheCrawl = state
    end
    return state
end

local function isSupported()
    return C_QuestLog and C_QuestLog.RequestLoadQuestByID and addon.QuestIDs ~= nil
end

local function stop(message)
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    if message then
        printMessage(message)
    end
end

local function tick()
    local ids = addon.QuestIDs
    local state = getState()
    for _ = 1, REQUESTS_PER_TICK do
        local questID = ids[state.nextIndex]
        if not questID then
            stop(string.format(
                "Quest cache: all %d quests requested (%d answered, %d unknown to the server). "
                    .. "Log out or exit so the client writes questcache.wdb, then run the importer.",
                #ids, loaded, failed
            ))
            return
        end
        state.nextIndex = state.nextIndex + 1
        C_QuestLog.RequestLoadQuestByID(questID)
        if state.nextIndex % REPORT_EVERY == 0 then
            printMessage(string.format("Quest cache: %d/%d requested.", state.nextIndex, #ids))
        end
    end
end

addon:RegisterEvent("QUEST_DATA_LOAD_RESULT", function(_, success)
    if not ticker then
        return
    end
    if success then
        loaded = loaded + 1
    else
        failed = failed + 1
    end
end)

addon:RegisterCommand("questcache", function(argument)
    if not isSupported() then
        printMessage("Quest cache: this client has no C_QuestLog.RequestLoadQuestByID or no Data/QuestIDs.lua.")
        return
    end
    local state = getState()
    local total = #addon.QuestIDs
    if argument == "stop" then
        stop(string.format("Quest cache: stopped at %d/%d.", state.nextIndex - 1, total))
    elseif argument == "reset" then
        stop()
        state.nextIndex = 1
        printMessage("Quest cache: position reset, /fc questcache starts from the first quest.")
    elseif argument == "status" then
        printMessage(string.format(
            "Quest cache: %d/%d requested for build %s%s.",
            math.min(state.nextIndex - 1, total), total, state.build, ticker and " (running)" or ""
        ))
    elseif ticker then
        printMessage("Quest cache: already running (/fc questcache stop).")
    else
        loaded, failed = 0, 0
        printMessage(string.format(
            "Quest cache: requesting quests %d-%d from the server (about %d min).",
            state.nextIndex, total, math.ceil((total - state.nextIndex + 1) / (REQUESTS_PER_TICK / TICK_SECONDS) / 60)
        ))
        ticker = C_Timer.NewTicker(TICK_SECONDS, tick)
    end
end, "Alle Quests beim Server abfragen, damit questcache.wdb sie enthält (stop, status, reset)")
