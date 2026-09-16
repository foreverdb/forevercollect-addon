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

-- Appends `location` to `locations` unless a location on the same map within
-- ~0.1% of the same coordinates is already listed. Returns true when added.
function addon.AddUniqueLocation(locations, location, cap)
    if not location or not location.uiMapID or not location.x or not location.y then
        return false
    end
    local key = string.format(
        "%d:%d:%d",
        location.uiMapID,
        math.floor(location.x * 1000 + 0.5),
        math.floor(location.y * 1000 + 0.5)
    )
    for _, existing in ipairs(locations) do
        if existing.uiMapID and existing.x and existing.y then
            local existingKey = string.format(
                "%d:%d:%d",
                existing.uiMapID,
                math.floor(existing.x * 1000 + 0.5),
                math.floor(existing.y * 1000 + 0.5)
            )
            if existingKey == key then
                return false
            end
        end
    end
    if cap and #locations >= cap then
        return false
    end
    locations[#locations + 1] = location
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

-- Fills the scanning tooltip via `populate(tooltip)` and returns its text lines.
function addon.ReadTooltipLines(populate)
    scanningTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanningTooltip:ClearLines()
    populate(scanningTooltip)

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
    return lines
end
