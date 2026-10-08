local _, addon = ...

local printMessage = addon.PrintMessage
local formatTimestamp = addon.FormatTimestamp
local readTooltipLines = addon.ReadTooltipLines
local getClientInfo = addon.GetClientInfo
local getOrCreateCatalog = addon.GetOrCreateCatalog
local getLatestCatalog = addon.GetLatestCatalog
local getCharacterContext = addon.GetCharacterContext
local captureNPCInteraction = addon.CaptureNPCInteraction
local getNPCKey = addon.GetNPCKey

local SERVICE_FILTERS = { "available", "unavailable", "used" }

local isScanningTrainer
local lastListSignature
local hasAnnouncedTrainer

local function getServiceSpellID(link)
    if not link then
        return nil
    end
    return tonumber(string.match(link, "spell:(%d+)"))
        or tonumber(string.match(link, "enchant:(%d+)"))
end

-- The trainer list itself carries no rank in Classic (the subtext is empty), so
-- derive it from the spell once its ID is known.
local function getSpellRank(spellID)
    if not spellID then
        return nil
    end
    local subtext = GetSpellSubtext and GetSpellSubtext(spellID)
    if (not subtext or subtext == "") and GetSpellInfo then
        local _, rank = GetSpellInfo(spellID)
        subtext = rank
    end
    if subtext and subtext ~= "" then
        return subtext
    end
    return nil
end

-- Returns the tooltip lines and, as second value, the spell ID the tooltip
-- shows. The latter is the only source of the ID for class spells, because
-- GetTrainerServiceItemLink only returns links for items and enchants.
local function getServiceTooltipInfo(index)
    return readTooltipLines(function(tooltip)
        tooltip:SetTrainerService(index)
    end)
end

-- Mainline-engine clients (Forever 1.60+) list services flat with a category
-- name per row and no header/expand API; Classic lists headers as rows.
local function hasClassicTrainerList()
    return ExpandTrainerSkillLine ~= nil and CollapseTrainerSkillLine ~= nil
end

-- Classic returns moneyCost, talentCost, professionCost; the mainline engine
-- returns moneyCost, isProfession (a boolean), so only the money cost is kept there.
local function getServiceCost(index)
    local moneyCost, talentCost, professionCost = GetTrainerServiceCost(index)
    if not hasClassicTrainerList() then
        return moneyCost, nil, nil
    end
    return moneyCost, talentCost, professionCost
end

local function getServiceRequirements(index, reqLevel)
    local requirements = {}
    local skillName, skillRank, hasSkill = GetTrainerServiceSkillReq(index)
    if skillName then
        requirements.skill = {
            name = skillName,
            rank = skillRank,
            isMet = hasSkill and true or false,
        }
    end

    local abilities = {}
    for reqIndex = 1, GetTrainerServiceNumAbilityReq(index) or 0 do
        local abilityName, hasAbility = GetTrainerServiceAbilityReq(index, reqIndex)
        if abilityName then
            abilities[#abilities + 1] = {
                name = abilityName,
                isMet = hasAbility and true or false,
            }
        end
    end
    requirements.abilities = abilities
    if GetTrainerServiceLevelReq then
        requirements.level = GetTrainerServiceLevelReq(index)
    else
        requirements.level = reqLevel
    end
    return requirements
end

-- Cheap fingerprint of the currently listed services, used to tell real list
-- changes apart from the TRAINER_UPDATE events caused by our own filter changes.
-- Normalizes GetTrainerServiceInfo across the two client generations:
-- Classic returns name, rank, category, isExpanded; the mainline engine returns
-- name, serviceType, texture, reqLevel, subText, category (= skill line name).
local function getServiceInfo(index)
    if hasClassicTrainerList() then
        local name, rank, category, isExpanded = GetTrainerServiceInfo(index)
        return {
            name = name,
            rank = rank,
            category = category,
            isExpanded = isExpanded,
        }
    end
    local name, serviceType, texture, reqLevel, subText, skillLine = GetTrainerServiceInfo(index)
    return {
        name = name,
        rank = subText,
        category = serviceType,
        icon = texture,
        reqLevel = reqLevel,
        skillLine = skillLine ~= "" and skillLine or nil,
    }
end

local function getListSignature()
    local parts = {}
    for index = 1, GetNumTrainerServices() do
        local info = getServiceInfo(index)
        parts[index] = (info.name or "") .. ":" .. (info.category or "")
    end
    return table.concat(parts, "|")
end

local function readServices()
    local services = {}
    local skillLine
    for index = 1, GetNumTrainerServices() do
        local info = getServiceInfo(index)
        local name, rank, category, isExpanded = info.name, info.rank, info.category, info.isExpanded
        if info.skillLine then
            skillLine = info.skillLine
        end
        if name and name ~= "" then
            local isHeader = category == "header"
            if isHeader then
                skillLine = name
            end

            local service = {
                index = index,
                name = name,
                rank = rank ~= "" and rank or nil,
                category = category,
                isHeader = isHeader,
                isExpanded = isExpanded and true or false,
                isAvailable = category == "available",
                isKnown = category == "used",
                skillLine = skillLine,
            }

            if not isHeader then
                local link = GetTrainerServiceItemLink and GetTrainerServiceItemLink(index) or nil
                local moneyCost, talentCost, professionCost = getServiceCost(index)
                local tooltipLines, tooltipSpellID = getServiceTooltipInfo(index)
                service.link = link
                service.spellID = getServiceSpellID(link) or tooltipSpellID
                service.rank = service.rank or getSpellRank(service.spellID)
                service.icon = info.icon or (GetTrainerServiceIcon and GetTrainerServiceIcon(index)) or nil
                service.description = GetTrainerServiceDescription and GetTrainerServiceDescription(index) or nil
                service.moneyCost = moneyCost
                service.talentCost = talentCost
                service.professionCost = professionCost
                service.requirements = getServiceRequirements(index, info.reqLevel)
                service.tooltipLines = tooltipLines
            end

            services[#services + 1] = service
        end
    end
    return services
end

-- The client rejects 0 as the "off" value, so use booleans and fall back to the
-- on/off strings the error message asks for.
local function setServiceFilter(filter, enabled)
    if not pcall(SetTrainerServiceTypeFilter, filter, enabled and true or false) then
        SetTrainerServiceTypeFilter(filter, enabled and "on" or "off")
    end
end

-- Enables every service filter and expands every header so all services are
-- listed, then restores the previous UI state after `callback` ran.
local function withAllServicesVisible(callback)
    local previousFilters = {}
    for _, filter in ipairs(SERVICE_FILTERS) do
        previousFilters[filter] = GetTrainerServiceTypeFilter(filter) and true or false
        if not previousFilters[filter] then
            setServiceFilter(filter, true)
        end
    end

    local collapsedHeaders = {}
    if hasClassicTrainerList() then
        for index = 1, GetNumTrainerServices() do
            local info = getServiceInfo(index)
            if info.category == "header" and info.name and not info.isExpanded then
                collapsedHeaders[info.name] = true
            end
        end
        ExpandTrainerSkillLine(0)
    end

    local result = callback()

    if hasClassicTrainerList() then
        for index = GetNumTrainerServices(), 1, -1 do
            local info = getServiceInfo(index)
            if info.category == "header" and info.name and collapsedHeaders[info.name] then
                CollapseTrainerSkillLine(index)
            end
        end
    end
    for _, filter in ipairs(SERVICE_FILTERS) do
        if not previousFilters[filter] then
            setServiceFilter(filter, false)
        end
    end

    return result
end

local function scanTrainerServices(silent)
    if isScanningTrainer then
        return nil
    end
    if not GetNumTrainerServices or not GetTrainerServiceInfo
        or not GetTrainerServiceTypeFilter or not SetTrainerServiceTypeFilter
        or not GetTrainerServiceCost or not GetTrainerServiceSkillReq
    then
        printMessage("This client does not provide the trainer API.")
        return nil
    end
    isScanningTrainer = true

    local npc = captureNPCInteraction("trainer")
    if not npc then
        isScanningTrainer = nil
        return nil
    end

    local ok, services = pcall(withAllServicesVisible, readServices)
    lastListSignature = getListSignature()
    isScanningTrainer = nil
    if not ok then
        printMessage("Trainer scan failed: " .. tostring(services))
        return nil
    end
    if #services == 0 then
        return nil
    end

    local snapshot = {
        capturedAt = time(),
        character = getCharacterContext(),
        trainerNPC = npc,
        greeting = GetTrainerGreetingText and GetTrainerGreetingText() or nil,
        isTradeskillTrainer = IsTradeskillTrainer and IsTradeskillTrainer() and true or false,
        services = services,
    }

    local catalog = getOrCreateCatalog(getClientInfo())
    catalog.trainerSnapshots = catalog.trainerSnapshots or {}
    catalog.trainerSnapshots[getNPCKey(npc)] = snapshot
    catalog.trainerScanUpdatedAt = snapshot.capturedAt

    if not silent or not hasAnnouncedTrainer then
        hasAnnouncedTrainer = true
        local serviceCount, missingSpellIDs = 0, 0
        for _, service in ipairs(snapshot.services) do
            if not service.isHeader then
                serviceCount = serviceCount + 1
                if not service.spellID then
                    missingSpellIDs = missingSpellIDs + 1
                end
            end
        end
        addon.Announce(string.format(
            "Captured %d trainer services from %s%s.",
            serviceCount,
            npc.name or "unknown trainer",
            missingSpellIDs > 0
                and string.format(" (%d without spell ID)", missingSpellIDs)
                or ""
        ))
    end
    return snapshot
end
addon.ScanTrainerServices = scanTrainerServices

addon:RegisterEvent("TRAINER_SHOW", function()
    hasAnnouncedTrainer = nil
    scanTrainerServices(false)
end)

addon:RegisterEvent("TRAINER_CLOSED", function()
    hasAnnouncedTrainer = nil
    lastListSignature = nil
end)

-- Re-scan when the list actually changes (data arriving after TRAINER_SHOW,
-- learning a skill), but not for the updates caused by our own filter changes.
addon:RegisterEvent("TRAINER_UPDATE", function()
    if isScanningTrainer or getListSignature() == lastListSignature then
        return
    end
    scanTrainerServices(true)
end)

addon:RegisterCommand("trainer", function()
    if GetNumTrainerServices and GetNumTrainerServices() > 0 then
        scanTrainerServices(false)
    end

    local catalog = getLatestCatalog()
    local snapshots = catalog and catalog.trainerSnapshots
    if not snapshots or not next(snapshots) then
        printMessage("No trainer snapshot found. Open a trainer first.")
        return
    end

    local trainerCount, serviceCount, latest = 0, 0, nil
    for _, snapshot in pairs(snapshots) do
        trainerCount = trainerCount + 1
        for _, service in ipairs(snapshot.services) do
            if not service.isHeader then
                serviceCount = serviceCount + 1
            end
        end
        if not latest or snapshot.capturedAt > latest.capturedAt then
            latest = snapshot
        end
    end
    printMessage(string.format(
        "%d trainers with %d services captured (latest: %s at %s).",
        trainerCount,
        serviceCount,
        latest.trainerNPC.name or "Unknown",
        formatTimestamp(latest.capturedAt)
    ))
end, "Scan trainer services and show number of captured entries")
