-- Run: luajit tests/cache_crawl_test.lua (or lua5.1)
local onEvent
local frame = setmetatable({
    SetScript = function(_, _, handler)
        onEvent = handler
    end,
}, { __index = function() return function() end end })
CreateFrame = function() return frame end

local build = "70532"
GetBuildInfo = function() return "1.60.1", build end

local ticker
C_Timer = {
    NewTicker = function(_, callback)
        ticker = { callback = callback, Cancel = function() ticker = nil end }
        return ticker
    end,
}

local printed = {}
local addon = {
    PrintMessage = function(message)
        printed[#printed + 1] = message
    end,
}
ForeverCollectSettings = {}

assert(loadfile("Core/Registry.lua"))("ForeverCollect", addon)
assert(loadfile("Core/CacheCrawl.lua"))("ForeverCollect", addon)

local function check(name, condition)
    if not condition then
        error("FAIL: " .. name, 2)
    end
    print("ok - " .. name)
end

local function last()
    return printed[#printed]
end

local requested = {}
local ids = {}
for i = 1, 12 do
    ids[i] = 1000 + i
end
local status = addon.NewCacheCrawl({
    command = "itemcache",
    label = "Item cache",
    unit = "item",
    cacheFile = "DBCache.bin",
    settingsKey = "itemCacheCrawl",
    ids = function() return ids end,
    request = function(id)
        requested[#requested + 1] = id
    end,
    resultEvent = "ITEM_DATA_LOAD_RESULT",
    isSupported = function() return true end,
    unsupported = "unsupported",
})

local function tick()
    ticker.callback()
end

addon:HandleSlashCommand("itemcache")
check("start announces the range", last() == "Item cache: requesting items 1-12 from the server (about 1 min).")
check("start runs a ticker", ticker ~= nil)
addon:HandleSlashCommand("itemcache")
check("a second start is refused", last() == "Item cache: already running (/fc itemcache stop).")

tick()
check("one tick requests five ids", #requested == 5 and requested[5] == 1005)
onEvent(nil, "ITEM_DATA_LOAD_RESULT", 1001, true)
onEvent(nil, "ITEM_DATA_LOAD_RESULT", 1002, false)

addon:HandleSlashCommand("itemcache stop")
check("stop reports the position", last() == "Item cache: stopped at 5/12." and ticker == nil)
local text, running = status()
check("status for the settings page", text == "Item cache: 5/12 requested for build 70532." and running == false)

-- a /reload keeps the position: it lives in the settings
addon:HandleSlashCommand("itemcache")
check("restart continues after the last request", last() == "Item cache: requesting items 6-12 from the server (about 1 min).")
tick()
onEvent(nil, "ITEM_DATA_LOAD_RESULT", 1006, true)
tick()
check("the last ids are requested", #requested == 12 and requested[12] == 1012)
check("the end is reported with the answers of this run", last()
    == "Item cache: all 12 items requested (1 answered, 0 unknown to the server). "
    .. "Log out or exit so the client writes DBCache.bin, then run the importer.")
check("the ticker stops at the end", ticker == nil)

addon:HandleSlashCommand("itemcache reset")
check("reset starts over", last() == "Item cache: position reset, /fc itemcache starts from the first item."
    and ForeverCollectSettings.itemCacheCrawl.nextIndex == 1)

ForeverCollectSettings.itemCacheCrawl.nextIndex = 9
build = "70600"
check("a new build starts from the first id", status() == "Item cache: 0/12 requested for build 70600.")

local missing = addon.NewCacheCrawl({
    command = "questcache", label = "Quest cache", unit = "quest", cacheFile = "questcache.wdb",
    settingsKey = "questCacheCrawl", ids = function() return nil end, request = function() end,
    resultEvent = "QUEST_DATA_LOAD_RESULT", isSupported = function() return true end,
    unsupported = "Quest cache: no list",
})
addon:HandleSlashCommand("questcache")
check("without an id list the command explains why", last() == "Quest cache: no list" and missing() == nil)
