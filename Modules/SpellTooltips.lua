local _, addon = ...

-- Scans the tooltips of the spells the website cannot fill in (ForeverCollectCacheIDs.spells,
-- written by the uploader for crawlers: descriptions that keep an "X" from the client data).
-- Their effects sit in encrypted DB2 sections whose keys the client only holds in memory, so no
-- cache upload carries them; the tooltip does show the values, for any class
-- (forevercollect-addon#3). The lines go into catalog.spellTooltips and up with the next upload;
-- the website uses them only where its own computation leaves an "X".

-- A single line is just the name: the spell data is not loaded yet.
local MIN_LINES = 2

-- Spells this crawl asked for: the result event also fires for spells other addons load.
local pending = {}

local function readableLines(lines)
    local cleaned = {}
    for _, line in ipairs(lines or {}) do
        local leftText = addon.Readable(line.leftText)
        local rightText = addon.Readable(line.rightText)
        if leftText or rightText then
            cleaned[#cleaned + 1] = { leftText = leftText, rightText = rightText }
        end
    end
    return cleaned
end

function addon.ScanSpellTooltip(spellID)
    local ok, lines = pcall(addon.ReadTooltipLines, function(tooltip)
        tooltip:SetSpellByID(spellID)
    end)
    lines = ok and readableLines(lines) or {}
    if #lines < MIN_LINES then
        return false
    end
    local catalog = addon.GetOrCreateCatalog(addon.GetClientInfo())
    catalog.spellTooltips = catalog.spellTooltips or {}
    catalog.spellTooltips[spellID] = {
        name = lines[1].leftText,
        lines = lines,
        capturedAt = time(),
    }
    catalog.spellTooltipsUpdatedAt = time()
    return true
end

local function scan(spellID)
    pending[spellID] = nil
    addon.ScanSpellTooltip(spellID)
end

addon.SpellTooltipStatus = addon.NewCacheCrawl({
    command = "spelltooltips",
    label = "Spell tooltips",
    unit = "spell",
    cacheFile = "SavedVariables",
    settingsKey = "spellTooltipCrawl",
    ids = function()
        return ForeverCollectCacheIDs and ForeverCollectCacheIDs.spells
    end,
    request = function(spellID)
        if C_Spell.IsSpellDataCached and C_Spell.IsSpellDataCached(spellID) then
            scan(spellID)
        else
            pending[spellID] = true
            C_Spell.RequestLoadSpellData(spellID)
        end
    end,
    resultEvent = "SPELL_DATA_LOAD_RESULT",
    onResult = function(spellID, success)
        if pending[spellID] then
            if success then
                scan(spellID)
            else
                pending[spellID] = nil
            end
        end
    end,
    doneHint = "Use /fc save or log out, so the uploader sends the tooltips.",
    isSupported = function()
        return C_Spell ~= nil and C_Spell.RequestLoadSpellData ~= nil
    end,
    unsupported = "Spell tooltips: this client has no C_Spell.RequestLoadSpellData or no spell list from the uploader (crawlers only).",
    help = "Scan the tooltips of the spells whose values the website lacks (stop, status, reset)",
})
