-- Run: luajit tests/spell_tooltips_test.lua (or lua5.1)
local onEvent
local frame = setmetatable({
    SetScript = function(_, _, handler)
        onEvent = handler
    end,
}, { __index = function() return function() end end })
CreateFrame = function() return frame end
GetBuildInfo = function() return "1.60.1", "70862" end
time = function() return 1794254000 end

local ticker
C_Timer = {
    NewTicker = function(_, callback)
        ticker = { callback = callback, Cancel = function() ticker = nil end }
        return ticker
    end,
}

-- what the client shows per spell; 1265831 has its data only after the request
local tooltips = {
    [1265831] = {
        "Savage Rend", "100 yd range", "Instant",
        "Slash an enemy with razor talons, causing the target to Bleed for 30 damage over 18 sec and take 5% additional damage from Bleed effects for the duration.",
    },
    [12323] = { "Piercing Howl", "Causes all enemies within 10 yds to be Dazed." },
    [99] = { "Not loaded" },
}
local cached = { [12323] = true }
local requested = {}
C_Spell = {
    IsSpellDataCached = function(id) return cached[id] == true end,
    RequestLoadSpellData = function(id) requested[#requested + 1] = id end,
}

local printed = {}
local catalog = {}
local addon = {
    PrintMessage = function(message) printed[#printed + 1] = message end,
    GetClientInfo = function() return {} end,
    GetOrCreateCatalog = function() return catalog end,
    Readable = function(value) return value end,
    ReadTooltipLines = function(populate)
        local shown
        populate({ SetSpellByID = function(_, id) shown = id end })
        local lines = {}
        for _, text in ipairs(tooltips[shown] or {}) do
            lines[#lines + 1] = { leftText = text }
        end
        return lines
    end,
}
ForeverCollectSettings = {}
ForeverCollectCacheIDs = { build = 70862, spells = { 12323, 1265831, 99 } }

assert(loadfile("Core/Registry.lua"))("ForeverCollect", addon)
assert(loadfile("Core/CacheCrawl.lua"))("ForeverCollect", addon)
assert(loadfile("Modules/SpellTooltips.lua"))("ForeverCollect", addon)

local function check(name, condition)
    if not condition then
        error("FAIL: " .. name, 2)
    end
    print("ok - " .. name)
end

addon:HandleSlashCommand("spelltooltips")
check("the crawl starts", ticker ~= nil)
ticker.callback()
check("a cached spell is scanned at once", catalog.spellTooltips[12323] ~= nil
    and catalog.spellTooltips[12323].lines[2].leftText == "Causes all enemies within 10 yds to be Dazed.")
check("the others are requested", #requested == 2 and requested[1] == 1265831 and requested[2] == 99)

-- three ids fit into one tick of five requests, so the crawl already ended
check("the end names the next step", printed[#printed]:find("Use /fc save or log out", 1, true) ~= nil
    and ticker == nil)

-- the answers arrive after the last request
onEvent(nil, "SPELL_DATA_LOAD_RESULT", 1265831, true)
onEvent(nil, "SPELL_DATA_LOAD_RESULT", 99, true)
local rend = catalog.spellTooltips[1265831]
check("a late answer is still scanned", rend ~= nil and rend.name == "Savage Rend" and #rend.lines == 4
    and rend.lines[4].leftText:find("5% additional", 1, true) ~= nil and rend.capturedAt == 1794254000)
check("a tooltip with only the name is not stored", catalog.spellTooltips[99] == nil)
check("the scan time is set", catalog.spellTooltipsUpdatedAt == 1794254000)

-- other addons load spells too; only the crawl's own requests are scanned
tooltips[555] = { "Other", "Some text" }
onEvent(nil, "SPELL_DATA_LOAD_RESULT", 555, true)
check("a spell the crawl did not ask for is ignored", catalog.spellTooltips[555] == nil)
