local _, addon = ...

-- Asks the server for every ID of a generated list (Data/*IDs.lua) at a throttled rate, so the
-- client stores each answer in one of its cache files, which the importer reads. Nothing is
-- saved here except the crawl position per build, so a /reload or logout continues where it
-- stopped. Modules/QuestCache.lua and Modules/ItemCache.lua are the two crawls.

local printMessage = addon.PrintMessage

local REQUESTS_PER_TICK = 5
local TICK_SECONDS = 0.25 -- 20 requests per second
local REPORT_EVERY = 500

-- config: command (/fc <command>), label ("Quest cache"), unit ("quest"), cacheFile,
-- settingsKey (in ForeverCollectSettings), ids() (the list, nil when missing), request(id),
-- resultEvent (an event whose second argument is the success flag), isSupported(), unsupported
-- (message), help (for /fc help). Returns the status function for the settings page.
function addon.NewCacheCrawl(config)
    local label, units = config.label, config.unit .. "s"
    local ticker
    local loaded, failed = 0, 0

    local function getState()
        local settings = ForeverCollectSettings
        local build = select(2, GetBuildInfo())
        local state = settings[config.settingsKey]
        if not state or state.build ~= build then
            state = { build = build, nextIndex = 1 }
            settings[config.settingsKey] = state
        end
        return state
    end

    local function isSupported()
        return config.isSupported() and config.ids() ~= nil
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
                    "%s: all %d %s requested (%d answered, %d unknown to the server). "
                        .. "Log out or exit so the client writes %s, then run the importer.",
                    label, #ids, units, loaded, failed, config.cacheFile
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

    addon:RegisterEvent(config.resultEvent, function(_, success)
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
    end, config.help)

    -- For the settings page: nil when the client cannot crawl.
    return function()
        if not isSupported() then
            return nil
        end
        return statusText(getState(), #config.ids()), ticker ~= nil
    end
end
