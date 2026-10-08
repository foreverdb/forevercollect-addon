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

-- Classic Era exposes the tab/tier talent API; Forever (1.60+) builds its trees
-- on the trait system, which Modules/Traits.lua scans instead.
local function hasClassicTalentAPI()
    return C_SpecializationInfo
        and C_SpecializationInfo.GetTalentInfo
        and C_SpecializationInfo.GetSpecializationInfo
        and C_SpecializationInfo.IsInitialized
        and GetNumTalentTabs
        and GetNumTalents
        and true or false
end
addon.HasClassicTalentAPI = hasClassicTalentAPI

-- Prerequisite arrows: GetTalentPrereqs names the required talent by tier and
-- column; a prerequisite must be maxed, so its maxRank is the required rank.
local function attachPrerequisites(specialization, specializationIndex, groupIndex)
    if not GetTalentPrereqs then
        return
    end
    local byCell = {}
    for _, talent in ipairs(specialization.talents) do
        byCell[talent.tier .. ":" .. talent.column] = talent
    end
    for _, talent in ipairs(specialization.talents) do
        local ok, results = pcall(function()
            return { GetTalentPrereqs(specializationIndex, talent.index, false, false, groupIndex) }
        end)
        if ok then
            -- Triples of tier, column, isLearnable per prerequisite.
            for offset = 1, #results, 3 do
                local prerequisite = byCell[tostring(results[offset]) .. ":" .. tostring(results[offset + 1])]
                if prerequisite then
                    talent.prerequisites = talent.prerequisites or {}
                    table.insert(talent.prerequisites, {
                        talentID = prerequisite.talentID,
                        rank = prerequisite.maxRank,
                    })
                end
            end
        end
    end
end

-- `options.silent` marks automatic scans (login, talent events): they never
-- explain why nothing was scanned, only /fc scan does.
local function scanTalentCatalog(options)
    options = options or {}
    initializeDatabase()

    local client = getClientInfo()
    if not isSupportedClient(client) then
        if not options.silent then
            printMessage("Unsupported WoW project. Classic Era or Forever is required.")
        end
        return nil
    end

    if not hasClassicTalentAPI() then
        if not options.silent then
            printMessage("This client has no Classic talent API; the talent trees come from the client data, /fc scan reads their tooltips (see /fc traits).")
        end
        return nil
    end

    if not C_SpecializationInfo.IsInitialized() then
        if not options.silent then
            printMessage("Talent data is not initialized yet. Try /fc scan again.")
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

        attachPrerequisites(specialization, specializationIndex, groupIndex)
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

if hasClassicTalentAPI() then
    addon:RegisterEvent("PLAYER_TALENT_UPDATE", function()
        scanTalentCatalog({ silent = true })
    end)
end

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
end, "Show talent data of the current catalog")
