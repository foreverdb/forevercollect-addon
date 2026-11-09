local _, addon = ...

-- Asks the server for every ID of a generated list (Data/*IDs.lua) at a throttled rate, so the
-- client stores each answer in one of its cache files, which the importer reads. Nothing is
-- saved here except the crawl position per build and list, so a /reload or logout continues where
-- it stopped and a new list starts over. Modules/QuestCache.lua and Modules/ItemCache.lua are the
-- cache crawls; Modules/SpellTooltips.lua reads each answer itself (config.onResult).

local printMessage = addon.PrintMessage

local REQUESTS_PER_TICK = 5
local TICK_SECONDS = 0.25 -- 20 requests per second
local REPORT_EVERY = 500

-- config: command (/fc <command>), label ("Quest cache"), unit ("quest"), cacheFile,
-- settingsKey (in ForeverCollectSettings), ids() (the list, nil when missing), request(id),
-- resultEvent (an event whose arguments are the ID and the success flag), isSupported(),
-- unsupported (message), help (for /fc help). Optional: onResult(id, success), called for every
-- result event, also one that arrives after the last request; doneHint, the next step after the
-- crawl (default: log out so the client writes cacheFile). Returns the status function for the
-- settings page.
function addon.NewCacheCrawl(config)
    local label, units = config.label, config.unit .. "s"
    local ticker
    local loaded, failed = 0, 0

    -- Which list a position belongs to; a table only changes with a /reload or login.
    local keyedList, listKey
    local function getListKey()
        local ids = config.ids()
        if ids ~= keyedList then
            keyedList, listKey = ids, 0
            for _, id in ipairs(ids or {}) do
                listKey = (listKey * 31 + id) % 2147483647
            end
        end
        return listKey
    end

    local function getState()
        local settings = ForeverCollectSettings
        local build = select(2, GetBuildInfo())
        local state = settings[config.settingsKey]
        local list = getListKey()
        if not state or state.build ~= build or state.list ~= list then
            state = { build = build, list = list, nextIndex = 1 }
            settings[config.settingsKey] = state
        end
        return state
    end

    -- Clients without the request API may not know its result event either (Classic Era has
    -- no QUEST_DATA_LOAD_RESULT), and registering an unknown event throws. Checked first, so
    -- the client does not report it; pcall covers clients without C_EventUtils.
    local eventKnown

    -- The uploader writes the lists only for approved crawlers, with the build they are for;
    -- a list of another build waits for the uploader's next one. Lists without a build (older
    -- uploaders, the importer) still count.
    local function isSupported()
        if not (eventKnown and config.isSupported() and config.ids() ~= nil) then
            return false
        end
        local listBuild = ForeverCollectCacheIDs and ForeverCollectCacheIDs.build
        return listBuild == nil or tostring(listBuild) == tostring(select(2, GetBuildInfo()))
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
        local ids = config.ids()
        local state = getState()
        for _ = 1, REQUESTS_PER_TICK do
            local id = ids[state.nextIndex]
            if not id then
                stop(string.format(
                    "%s: all %d %s requested (%d answered, %d unknown to the server). %s",
                    label, #ids, units, loaded, failed,
                    config.doneHint or string.format(
                        "Log out or exit so the client writes %s, then run the importer.", config.cacheFile
                    )
                ))
                return
            end
            state.nextIndex = state.nextIndex + 1
            config.request(id)
            if state.nextIndex % REPORT_EVERY == 0 then
                printMessage(string.format("%s: %d/%d requested.", label, state.nextIndex, #ids))
            end
        end
    end

    local valid = not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(config.resultEvent)
    eventKnown = valid and pcall(addon.RegisterEvent, addon, config.resultEvent, function(id, success)
        if config.onResult then
            config.onResult(id, success)
        end
        if not ticker then
            return
        end
        if success then
            loaded = loaded + 1
        else
            failed = failed + 1
        end
    end)

    local function statusText(state, total)
        return string.format(
            "%s: %d/%d requested for build %s%s.",
            label, math.min(state.nextIndex - 1, total), total, state.build, ticker and " (running)" or ""
        )
    end

    addon:RegisterCommand(config.command, function(argument)
        if not isSupported() then
            printMessage(config.unsupported)
            return
        end
        local state = getState()
        local total = #config.ids()
        if argument == "stop" then
            stop(string.format("%s: stopped at %d/%d.", label, state.nextIndex - 1, total))
        elseif argument == "reset" then
            stop()
            state.nextIndex = 1
            printMessage(string.format(
                "%s: position reset, /fc %s starts from the first %s.", label, config.command, config.unit
            ))
        elseif argument == "status" then
            printMessage(statusText(state, total))
        elseif ticker then
            printMessage(string.format("%s: already running (/fc %s stop).", label, config.command))
        else
            loaded, failed = 0, 0
            printMessage(string.format(
                "%s: requesting %s %d-%d from the server (about %d min).",
                label, units, state.nextIndex, total,
                math.ceil((total - state.nextIndex + 1) / (REQUESTS_PER_TICK / TICK_SECONDS) / 60)
            ))
            ticker = C_Timer.NewTicker(TICK_SECONDS, tick)
        end
    end, config.help, isSupported)

    -- For the window: nil when the client cannot crawl, else the status line, whether it
    -- runs, and how many of how many IDs were requested.
    return function()
        if not isSupported() then
            return nil
        end
        local state, total = getState(), #config.ids()
        return statusText(state, total), ticker ~= nil, math.min(state.nextIndex - 1, total), total
    end
end
