local _, addon = ...

local printMessage = addon.PrintMessage
local readTooltipLines = addon.ReadTooltipLines
local getClientInfo = addon.GetClientInfo
local getOrCreateCatalog = addon.GetOrCreateCatalog
local getLatestCatalog = addon.GetLatestCatalog
local initializeDatabase = addon.InitializeDatabase
local isSupportedClient = addon.IsSupportedClient

local function getTalentTooltipLines(talentID, groupIndex)
    return readTooltipLines(function(tooltip)
        tooltip:SetTalent(talentID, false, false, groupIndex)
    end)
end

local function countTalents(catalog)
    local totalTalents = 0
    for _, specialization in ipairs(catalog.specializations) do
        totalTalents = totalTalents + #specialization.talents
    end
    return totalTalents
end

local hasWarnedAboutTalentAPI

local function scanTalentCatalog()
    initializeDatabase()

    local client = getClientInfo()
    if not isSupportedClient(client) then
        printMessage("Unsupported WoW project. Classic Era or Forever is required.")
        return nil
    end

    if not C_SpecializationInfo
        or not C_SpecializationInfo.GetTalentInfo
        or not C_SpecializationInfo.GetSpecializationInfo
        or not C_SpecializationInfo.IsInitialized
    then
        printMessage("This client does not provide the Classic talent API.")
        return nil
    end

    if not C_SpecializationInfo.IsInitialized() then
        printMessage("Talent data is not initialized yet. Try /fc scan again.")
        return nil
    end
    -- Forever (1.60+) builds its talent trees on the trait system (C_Traits);
    -- the legacy tab/tier API this scan reads does not exist there.
    if not GetNumTalentTabs or not GetNumTalents then
        if not hasWarnedAboutTalentAPI then
            hasWarnedAboutTalentAPI = true
            printMessage("This client does not provide the Classic talent API; talent trees come from the static catalog.")
        end
        return nil
    end

    local catalog = getOrCreateCatalog(client)
    catalog.scannedAt = time()
    catalog.specializations = {}

    local specializationCount = GetNumTalentTabs(false, false)
    local groupIndex = C_SpecializationInfo.GetActiveSpecGroup(false, false)
    for specializationIndex = 1, specializationCount do
        local specializationID, name, description, icon =
            C_SpecializationInfo.GetSpecializationInfo(
                specializationIndex,
                false,
                false,
                nil,
                nil,
                groupIndex
            )

        local specialization = {
            index = specializationIndex,
            id = specializationID,
            name = name,
            description = description,
            icon = icon,
            talents = {},
        }

        local talentCount = GetNumTalents(specializationIndex)
        for talentIndex = 1, talentCount do
            local info = C_SpecializationInfo.GetTalentInfo({
                specializationIndex = specializationIndex,
                talentIndex = talentIndex,
                groupIndex = groupIndex,
            })

            if info then
                specialization.talents[#specialization.talents + 1] = {
                    index = talentIndex,
                    talentID = info.talentID,
                    spellID = info.spellID,
                    name = info.name,
                    icon = info.icon,
                    tier = info.tier,
                    column = info.column,
                    maxRank = info.maxRank,
                    tooltipLines = getTalentTooltipLines(
                        info.talentID,
                        groupIndex
                    ),
                }
            end
        end

        catalog.specializations[#catalog.specializations + 1] = specialization
    end

    if #catalog.specializations == 0 then
        printMessage("No talent trees were returned; catalog was not overwritten.")
        return nil
    end

    printMessage(string.format(
        "Scanned %d talent trees and %d talents. Use /reload to save the catalog.",
        #catalog.specializations,
        countTalents(catalog)
    ))

    return catalog
end
addon.ScanTalentCatalog = scanTalentCatalog

addon:RegisterEvent("PLAYER_TALENT_UPDATE", function()
    scanTalentCatalog()
end)

addon:RegisterCommand("talents", function()
    local catalog = getLatestCatalog()
    if not catalog then
        printMessage("No catalog found. Use /fc scan first.")
        return
    end

    printMessage(string.format(
        "Catalog contains %d talent trees and %d talents from client %s.",
        #catalog.specializations,
        countTalents(catalog),
        catalog.version
    ))
end, "Talentdaten des aktuellen Katalogs anzeigen")
