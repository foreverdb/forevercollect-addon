local _, addon = ...

local scanningTooltip = CreateFrame(
    "GameTooltip",
    "ForeverCollectScanningTooltip",
    nil,
    "GameTooltipTemplate"
)
scanningTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

function addon.PrintMessage(message)
    print("|cff33ff99ForeverCollect|r: " .. message)
end

-- Capture notices ("Quest captured: ...") can be silenced with /fc verbose;
-- the flag lives outside the catalogs so uploads never carry it.
function addon.IsVerbose()
    local settings = ForeverCollectDB and ForeverCollectDB.settings
    return not settings or settings.verbose ~= false
end

-- Every module announces a successful capture through here, which also feeds the
-- unsaved-captures counter in Core/Autosave.lua.
function addon.Announce(message)
    if addon.NoteCapture then
        addon.NoteCapture()
    end
    if addon.IsVerbose() then
        addon.PrintMessage(message)
    end
end

-- Formats copper as "1g 2s 3c" for chat notices.
function addon.FormatMoney(copper)
    copper = tonumber(copper) or 0
    local gold = math.floor(copper / 10000)
    local silver = math.floor(copper / 100) % 100
    local rest = copper % 100
    local parts = {}
    if gold > 0 then
        parts[#parts + 1] = gold .. "g"
    end
    if silver > 0 or gold > 0 then
        parts[#parts + 1] = silver .. "s"
    end
    parts[#parts + 1] = rest .. "c"
    return table.concat(parts, " ")
end

function addon.AddUniqueValue(values, value)
    if not value then
        return
    end
    for _, existing in ipairs(values) do
        if existing == value then
            return
        end
    end
    values[#values + 1] = value
end

local function locationKey(location)
    return string.format(
        "%d:%d:%d",
        location.uiMapID,
        math.floor(location.x * 1000 + 0.5),
        math.floor(location.y * 1000 + 0.5)
    )
end

local function findLocation(locations, key)
    for _, existing in ipairs(locations) do
        if existing.uiMapID and existing.x and existing.y and locationKey(existing) == key then
            return existing
        end
    end
    return nil
end

-- Appends `location` to `locations` unless a location on the same map within
-- ~0.1% of the same coordinates is already listed. Returns true when added.
function addon.AddUniqueLocation(locations, location, cap)
    if not location or not location.uiMapID or not location.x or not location.y then
        return false
    end
    if findLocation(locations, locationKey(location)) then
        return false
    end
    if cap and #locations >= cap then
        return false
    end
    locations[#locations + 1] = location
    return true
end

-- Like AddUniqueLocation, but every hit on a spot is counted: the entry (a copy
-- of `location`) carries `count`, `firstSeenAt`, `lastSeenAt` and the newest
-- `timesCap` timestamps in `times`. Gathering uses it so spawn points and the
-- pace between gathers can be told apart from a single visit.
function addon.CountLocation(locations, location, cap, now, timesCap)
    if not location or not location.uiMapID or not location.x or not location.y then
        return false
    end
    local entry = findLocation(locations, locationKey(location))
    if not entry then
        if cap and #locations >= cap then
            return false
        end
        entry = {}
        for field, value in pairs(location) do
            entry[field] = value
        end
        entry.count = 0
        entry.firstSeenAt = now
        entry.times = {}
        locations[#locations + 1] = entry
    end
    entry.count = (entry.count or 0) + 1
    entry.lastSeenAt = now
    entry.times = entry.times or {}
    entry.times[#entry.times + 1] = now
    while timesCap and #entry.times > timesCap do
        table.remove(entry.times, 1)
    end
    return true
end

function addon.GetItemIDFromLink(link)
    if not link then
        return nil
    end
    return tonumber(string.match(link, "item:(%d+)"))
end

function addon.FormatTimestamp(timestamp)
    return date("!%Y-%m-%d %H:%M:%S", timestamp)
end

-- Nil for values the client hands out as "secret" (mainline engine, e.g. Forever:
-- hostile units in instanced content, world cursor text): they cannot be
-- compared, matched, concatenated or used as table keys.
function addon.Readable(value)
    if value == nil then
        return nil
    end
    if issecretvalue and issecretvalue(value) then
        return nil
    end
    if canaccessvalue and not canaccessvalue(value) then
        return nil
    end
    return value
end

-- Returns the current instance's ID (GetInstanceInfo's instanceID, the map ID)
-- and name, or nil outside instanced content.
function addon.GetInstance()
    if not IsInInstance or not GetInstanceInfo or not addon.Readable(IsInInstance()) then
        return nil
    end
    local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    instanceID = addon.Readable(instanceID)
    if type(instanceID) ~= "number" or instanceID <= 0 then
        return nil
    end
    return instanceID, addon.Readable(name)
end

local function firstPositiveNumber(...)
    for argIndex = 1, select("#", ...) do
        local value = select(argIndex, ...)
        if type(value) == "number" and value > 0 then
            return value
        end
    end
    return nil
end

-- Returns the ID of the spell currently shown in `tooltip`, trying the APIs of
-- the different client generations in turn. Needed where the client offers no
-- spell link, e.g. for class spells in the trainer window.
function addon.GetTooltipSpellID(tooltip)
    if TooltipUtil and TooltipUtil.GetDisplayedSpell then
        local ok, a, b, c = pcall(TooltipUtil.GetDisplayedSpell, tooltip)
        local spellID = ok and firstPositiveNumber(a, b, c)
        if spellID then
            return spellID
        end
    end
    if tooltip.GetSpell then
        local ok, a, b, c = pcall(tooltip.GetSpell, tooltip)
        local spellID = ok and firstPositiveNumber(a, b, c)
        if spellID then
            return spellID
        end
    end
    if tooltip.GetTooltipData then
        local ok, data = pcall(tooltip.GetTooltipData, tooltip)
        if ok and type(data) == "table" and type(data.id) == "number" and data.id > 0
            and (not Enum or not Enum.TooltipDataType or data.type == Enum.TooltipDataType.Spell)
        then
            return data.id
        end
    end
    return nil
end

-- Fills the scanning tooltip via `populate(tooltip)` and returns its text lines
-- plus the ID of the displayed spell, if the tooltip shows one.
function addon.ReadTooltipLines(populate)
    scanningTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanningTooltip:ClearLines()
    populate(scanningTooltip)
    local spellID = addon.GetTooltipSpellID(scanningTooltip)

    local lines = {}
    for lineIndex = 1, scanningTooltip:NumLines() do
        local leftLine = _G["ForeverCollectScanningTooltipTextLeft" .. lineIndex]
        local rightLine = _G["ForeverCollectScanningTooltipTextRight" .. lineIndex]
        local leftText = leftLine and leftLine:GetText()
        local rightText = rightLine and rightLine:GetText()

        if leftText or rightText then
            lines[#lines + 1] = {
                leftText = leftText,
                rightText = rightText,
            }
        end
    end

    scanningTooltip:Hide()
    return lines, spellID
end
