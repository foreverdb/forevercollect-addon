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
