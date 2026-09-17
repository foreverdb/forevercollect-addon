local addonName, addon = ...

addon.name = addonName

local printMessage = addon.PrintMessage
local getLatestCatalog = addon.GetLatestCatalog

local function scanAll()
    addon.ScanTalentCatalog()
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
    scanAll()
end)

addon:RegisterCommand("help", function()
    local names = {}
    for _, name in ipairs(addon:GetCommandNames()) do
        if name ~= "help" then
            names[#names + 1] = "/fc " .. name
        end
    end
    printMessage("Commands: " .. table.concat(names, ", "))
end, "Diese Hilfe anzeigen")

addon:RegisterCommand("scan", function()
    scanAll()
end, "Talente scannen")

addon:RegisterCommand("status", function()
    local catalog = getLatestCatalog()
    if not catalog then
        printMessage("No catalog stored yet. Open a quest or use /fc scan.")
        return
    end

    printMessage(string.format(
        "Catalog: %s, build %s, interface %d, project %s.",
        catalog.version,
        catalog.build,
        catalog.interfaceVersion,
        tostring(catalog.projectID)
    ))
    printMessage(string.format(
        "Season: %s (ID %d), locale: %s.",
        catalog.seasonName or "Unknown",
        catalog.seasonID or 0,
        catalog.locale
    ))
    printMessage(string.format(
        "Character context: %s (%s), race: %s (%s), faction: %s.",
        catalog.className or catalog.classFile or "Unknown",
        catalog.classFile or "Unknown",
        catalog.raceName or catalog.raceFile or "Unknown",
        catalog.raceFile or "Unknown",
        catalog.factionName or catalog.factionFile or "Unknown"
    ))

    local itemCount = addon.CountItems(catalog)
    local merchantCount = 0
    for _ in pairs(catalog.merchantSnapshots or {}) do
        merchantCount = merchantCount + 1
    end
    local lootSourceCount, lootItemCount = addon.CountLoot(catalog)
    printMessage(string.format(
        "Items: %d, merchants: %d, loot sources: %d (%d items).",
        itemCount,
        merchantCount,
        lootSourceCount,
        lootItemCount
    ))
end, "Katalogkontext und Scanstatus anzeigen")

SLASH_FOREVERCOLLECT1 = "/forevercollect"
SLASH_FOREVERCOLLECT2 = "/fc"
SlashCmdList.FOREVERCOLLECT = function(message)
    addon:HandleSlashCommand(message)
end
