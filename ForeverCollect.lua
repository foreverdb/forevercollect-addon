local addonName, addon = ...

addon.name = addonName

local printMessage = addon.PrintMessage
local getLatestCatalog = addon.GetLatestCatalog

-- Forever's talent trees and their tooltips come from the client data (importer);
-- only Classic Era's talent API is scanned.
local function scanAll(options)
    addon.ScanTalentCatalog(options)
end

addon:RegisterEvent("ADDON_LOADED", function(loadedAddonName)
    if loadedAddonName ~= addonName then
        return
    end
    addon.InitializeDatabase()
    addon.MigrateNPCData()
    local getMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    local version = getMetadata and getMetadata(addonName, "Version")
    printMessage((version and ("v" .. version .. " ") or "") .. "loaded. Use /fc help.")
end)

addon:RegisterEvent("PLAYER_LOGIN", function()
    if addon.IsCapturing("talents") then
        scanAll({ silent = true })
    end
end)

addon:RegisterCommand("help", function()
    local names = {}
    for _, name in ipairs(addon:GetCommandNames()) do
        if name ~= "help" then
            names[#names + 1] = "/fc " .. name
        end
    end
    printMessage("Commands: " .. table.concat(names, ", "))
end, "Show this help")

addon:RegisterCommand("verbose", function()
    addon.SetVerbose(not addon.IsVerbose())
end, "Toggle notices for every capture")

addon:RegisterCommand("scan", function()
    scanAll()
end, "Scan talents (Classic Era)")

-- Catalog context and capture counts, for /fc status and the settings page.
function addon.StatusLines()
    local lines = {}
    local catalog = getLatestCatalog()
    if not catalog then
        lines[1] = "No catalog stored yet. Open a quest or use /fc scan."
    else
        lines[#lines + 1] = string.format(
            "Catalog: %s, build %s, interface %d, project %s.",
            catalog.version,
            catalog.build,
            catalog.interfaceVersion,
            tostring(catalog.projectID)
        )
        lines[#lines + 1] = string.format(
            "Season: %s (ID %d), locale: %s.",
            catalog.seasonName or "Unknown",
            catalog.seasonID or 0,
            catalog.locale
        )
        lines[#lines + 1] = string.format(
            "Character context: %s (%s), race: %s (%s), faction: %s.",
            catalog.className or catalog.classFile or "Unknown",
            catalog.classFile or "Unknown",
            catalog.raceName or catalog.raceFile or "Unknown",
            catalog.raceFile or "Unknown",
            catalog.factionName or catalog.factionFile or "Unknown"
        )

        local itemCount = addon.CountItems(catalog)
        local merchantCount = 0
        for _ in pairs(catalog.merchantSnapshots or {}) do
            merchantCount = merchantCount + 1
        end
        local lootSourceCount, lootItemCount = addon.CountLoot(catalog)
        lines[#lines + 1] = string.format(
            "Items: %d, merchants: %d, loot sources: %d (%d items).",
            itemCount,
            merchantCount,
            lootSourceCount,
            lootItemCount
        )
    end
    local paused = addon.PausedLabels()
    if #paused > 0 then
        lines[#lines + 1] = "Capture paused: " .. table.concat(paused, ", ") .. " (/fc resume)."
    end
    local unsaved, seconds = addon.UnsavedCaptures()
    lines[#lines + 1] = string.format(
        "Unsaved captures: %d (%d min since the last save; /fc save writes them).",
        unsaved,
        math.floor(seconds / 60)
    )
    return lines
end

addon:RegisterCommand("status", function()
    for _, line in ipairs(addon.StatusLines()) do
        printMessage(line)
    end
end, "Show catalog context and scan status")

SLASH_FOREVERCOLLECT1 = "/forevercollect"
SLASH_FOREVERCOLLECT2 = "/fc"
SlashCmdList.FOREVERCOLLECT = function(message)
    addon:HandleSlashCommand(message)
end
