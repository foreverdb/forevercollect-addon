local addonName, addon = ...

addon.name = addonName

local printMessage = addon.PrintMessage
local getLatestCatalog = addon.GetLatestCatalog

local function scanAll(silent)
    addon.ScanTalentCatalog()
    addon.ScanAbilityCatalog(silent)
end

addon:RegisterEvent("ADDON_LOADED", function(loadedAddonName)
    if loadedAddonName ~= addonName then
        return
    end
    addon.InitializeDatabase()
    addon.MigrateNPCData()
    printMessage("loaded. Use /fc help.")
end)

addon:RegisterEvent("PLAYER_LOGIN", function()
    scanAll(true)
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
    scanAll(false)
end, "Talente und Runen scannen")

addon:RegisterCommand("status", function()
    local catalog = getLatestCatalog()
    if not catalog then
        printMessage("No catalog stored yet. Open a quest or use /fc scan.")
        return
    end

    printMessage(string.format(
        "Catalog: %s, build %s, interface %d.",
        catalog.version,
        catalog.build,
        catalog.interfaceVersion
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

    local abilitySnapshot = addon.GetAbilitySnapshot()
    if abilitySnapshot then
        printMessage(string.format("Runes: %d.", #abilitySnapshot.runes))
    end
end, "Katalogkontext und Scanstatus anzeigen")

SLASH_FOREVERCOLLECT1 = "/forevercollect"
SLASH_FOREVERCOLLECT2 = "/fc"
SlashCmdList.FOREVERCOLLECT = function(message)
    addon:HandleSlashCommand(message)
end
