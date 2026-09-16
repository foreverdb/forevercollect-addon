local addonName, addon = ...

addon.name = addonName

local DATABASE_SCHEMA_VERSION = 8

local SEASON_NAMES = {
    [0] = "NoSeason",
    [1] = "SeasonOfMastery",
    [2] = "SeasonOfDiscovery",
    [3] = "Hardcore",
    [11] = "Fresh",
    [12] = "FreshHardcore",
}

local scanningTooltip = CreateFrame(
    "GameTooltip",
    "ForeverCollectScanningTooltip",
    nil,
    "GameTooltipTemplate"
)
scanningTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

local function printMessage(message)
    print("|cff33ff99ForeverCollect|r: " .. message)
end

local function initializeDatabase()
    ForeverCollectDB = ForeverCollectDB or {}
    if not ForeverCollectDB.schemaVersion or ForeverCollectDB.schemaVersion < DATABASE_SCHEMA_VERSION then
        ForeverCollectDB.schemaVersion = DATABASE_SCHEMA_VERSION
    end
    ForeverCollectDB.catalogs = ForeverCollectDB.catalogs or {}
end

local function getClientInfo()
    local version, build, buildDate, interfaceVersion = GetBuildInfo()
    local className, classFile, classID = UnitClass("player")
    local raceName, raceFile, raceID = UnitRace("player")
    local factionFile, factionName = UnitFactionGroup("player")
    local seasonID = 0

    if C_Seasons and C_Seasons.GetActiveSeason then
        seasonID = C_Seasons.GetActiveSeason() or 0
    end

    return {
        projectID = WOW_PROJECT_ID,
        version = version,
        build = build,
        buildDate = buildDate,
        interfaceVersion = interfaceVersion,
        locale = GetLocale(),
        classID = classID,
        className = className,
        classFile = classFile,
        raceID = raceID,
        raceName = raceName,
        raceFile = raceFile,
        factionName = factionName,
        factionFile = factionFile,
        seasonID = seasonID,
        seasonName = SEASON_NAMES[seasonID] or "Unknown",
    }
end

local function getCatalogKey(client)
    return string.format(
        "%d:%d:%d:%s:%d:%d:%s",
        client.projectID,
        client.interfaceVersion,
        client.seasonID,
        client.locale,
        client.classID,
        client.raceID,
        client.factionFile or "Unknown"
    )
end

local function getOrCreateCatalog(client)
    initializeDatabase()

    local key = getCatalogKey(client)
    local catalog = ForeverCollectDB.catalogs[key]
    if not catalog then
        catalog = {
            schemaVersion = DATABASE_SCHEMA_VERSION,
            projectID = client.projectID,
            version = client.version,
            build = client.build,
            buildDate = client.buildDate,
            interfaceVersion = client.interfaceVersion,
            locale = client.locale,
            classID = client.classID,
            className = client.className,
            classFile = client.classFile,
            raceID = client.raceID,
            raceName = client.raceName,
            raceFile = client.raceFile,
            factionName = client.factionName,
            factionFile = client.factionFile,
            seasonID = client.seasonID,
            seasonName = client.seasonName,
            scannedAt = time(),
            specializations = {},
            quests = {},
            npcs = {},
            skillSnapshots = {},
            abilitySnapshots = {},
        }
        ForeverCollectDB.catalogs[key] = catalog
    else
        catalog.schemaVersion = DATABASE_SCHEMA_VERSION
        catalog.classID = client.classID
        catalog.className = client.className
        catalog.classFile = client.classFile
        catalog.raceID = client.raceID
        catalog.raceName = client.raceName
        catalog.raceFile = client.raceFile
        catalog.factionName = client.factionName
        catalog.factionFile = client.factionFile
        catalog.quests = catalog.quests or {}
        catalog.npcs = catalog.npcs or {}
        catalog.specializations = catalog.specializations or {}
        catalog.skillSnapshots = catalog.skillSnapshots or {}
        catalog.abilitySnapshots = catalog.abilitySnapshots or {}
    end

    ForeverCollectDB.latestCatalogKey = key
    return catalog
end

local function getTalentTooltipLines(talentID, groupIndex)
    scanningTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanningTooltip:ClearLines()
    scanningTooltip:SetTalent(talentID, false, false, groupIndex)

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

local function scanTalentCatalog()
    initializeDatabase()

    local client = getClientInfo()
    if client.projectID ~= WOW_PROJECT_CLASSIC then
        printMessage("Unsupported WoW project. Classic Era is required.")
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

    local totalTalents = 0
    for _, specialization in ipairs(catalog.specializations) do
        totalTalents = totalTalents + #specialization.talents
    end

    printMessage(string.format(
        "Scanned %d talent trees and %d talents. Use /reload to save the catalog.",
        #catalog.specializations,
        totalTalents
    ))

    return catalog
end

local activeQuestPhase

local function getCharacterContext()
    local raceName, raceFile, raceID = UnitRace("player")
    local sex = UnitSex("player")
    local level = UnitLevel("player")
    local factionFile, factionName = UnitFactionGroup("player")
    local className, classFile, classID = UnitClass("player")

    return {
        name = UnitName("player"),
        realm = GetRealmName(),
        level = level,
        race = raceName,
        raceName = raceName,
        raceFile = raceFile,
        raceID = raceID,
        sex = sex,
        faction = factionFile,
        factionName = factionName,
        factionFile = factionFile,
        className = className,
        classID = classID,
        classFile = classFile,
    }
end

local function getCharacterKey()
    return UnitGUID("player") or string.format(
        "%s-%s",
        UnitName("player") or "Unknown",
        GetRealmName() or "Unknown"
    )
end

local function getNPC(unitToken, interactionType, role)
    local guid = UnitGUID and UnitGUID(unitToken) or nil
    local name = UnitName and UnitName(unitToken) or nil
    local creatureID = UnitCreatureID and UnitCreatureID(unitToken) or nil
    local objectType = guid and string.match(guid, "^([^-]+)") or nil
    local location = {
        source = "playerAtInteraction",
        zone = GetZoneText and GetZoneText() or nil,
        subZone = GetSubZoneText and GetSubZoneText() or nil,
    }

    if C_Map and C_Map.GetBestMapForUnit then
        local uiMapID = C_Map.GetBestMapForUnit("player")
        if uiMapID then
            location.uiMapID = uiMapID
            local mapInfo = C_Map.GetMapInfo and C_Map.GetMapInfo(uiMapID)
            if mapInfo then
                location.mapName = mapInfo.name
                location.mapType = mapInfo.mapType
                location.parentMapID = mapInfo.parentMapID
            end

            if C_Map.GetPlayerMapPosition then
                local position = C_Map.GetPlayerMapPosition(uiMapID, "player")
                if position and position.GetXY then
                    location.x, location.y = position:GetXY()

                    if C_Map.GetWorldPosFromMapPos then
                        local continentID, worldPosition =
                            C_Map.GetWorldPosFromMapPos(uiMapID, position)
                        if continentID and worldPosition and worldPosition.GetXY then
                            location.worldContinentID = continentID
                            location.worldX, location.worldY = worldPosition:GetXY()
                        end
                    end
                end
            end
        end
    end

    local npc = {
        role = role,
        guid = guid,
        objectType = objectType,
        objectID = creatureID,
        npcID = creatureID,
        name = name,
        interactionTypes = { interactionType },
        creatureType = UnitCreatureType and UnitCreatureType(unitToken) or nil,
        classification = UnitClassification and UnitClassification(unitToken) or nil,
        location = location,
    }

    return npc
end

local function getQuestNPC(role)
    return getNPC("questnpc", "questGiver", role)
end

local function npcMatches(left, right)
    if left.guid and right.guid then
        return left.guid == right.guid
    end
    if left.npcID and right.npcID then
        return left.npcID == right.npcID
            and (not left.name or not right.name or left.name == right.name)
    end
    return left.name and right.name and left.name == right.name
end

local function addUniqueValue(values, value)
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

local function normalizeNPC(npc)
    if not npc then
        return nil
    end
    npc.interactionTypes = npc.interactionTypes or {}
    if #npc.interactionTypes == 0 then
        if npc.role == "giver" or npc.role == "progress" or npc.role == "turnIn" then
            npc.interactionTypes[1] = "questGiver"
        elseif npc.role == "merchant" or npc.role == "trainer"
            or npc.role == "banker" or npc.role == "flightMaster"
            or npc.role == "innkeeper"
        then
            npc.interactionTypes[1] = npc.role
        end
    end
    npc.location = npc.location or { source = "playerAtInteraction" }
    npc.location.source = npc.location.source or "playerAtInteraction"
    npc.creatureType = npc.creatureType or "Unknown"
    npc.classification = npc.classification or "unknown"
    return npc
end

local function mergeNPC(catalog, npc)
    normalizeNPC(npc)
    for _, existing in ipairs(catalog.npcs) do
        if npcMatches(existing, npc) then
            existing.interactionTypes = existing.interactionTypes or {}
            for _, interactionType in ipairs(npc.interactionTypes) do
                addUniqueValue(existing.interactionTypes, interactionType)
            end
            for key, value in pairs(npc) do
                if value ~= nil and key ~= "interactionTypes"
                    and (key ~= "role" or existing.role == nil)
                then
                    existing[key] = value
                end
            end
            return existing
        end
    end
    catalog.npcs[#catalog.npcs + 1] = npc
    return npc
end

local function migrateNPCData()
    initializeDatabase()
    for _, catalog in pairs(ForeverCollectDB.catalogs) do
        catalog.npcs = catalog.npcs or {}
        for _, quest in pairs(catalog.quests or {}) do
            for _, observation in ipairs(quest.observations or {}) do
                local npc = normalizeNPC(observation.questNPC)
                if npc then
                    mergeNPC(catalog, npc)
                end
            end
        end
        for _, npc in ipairs(catalog.npcs) do
            normalizeNPC(npc)
        end
    end
end

local function captureNPCInteraction(interactionType, role)
    local catalog = getOrCreateCatalog(getClientInfo())
    local unitToken = "npc"
    if not UnitGUID(unitToken) and UnitGUID("target")
        and (not UnitIsPlayer or not UnitIsPlayer("target"))
    then
        unitToken = "target"
    end
    local npc = getNPC(unitToken, interactionType, role or interactionType)
    if not npc.guid and not npc.npcID and not npc.name then
        return
    end
    mergeNPC(catalog, npc)
    catalog.npcScanUpdatedAt = time()
end

local isScanningSkillLines

local function scanSkillLines(silent)
    if isScanningSkillLines then
        return nil
    end
    isScanningSkillLines = true
    initializeDatabase()

    local client = getClientInfo()
    if client.projectID ~= WOW_PROJECT_CLASSIC then
        printMessage("Unsupported WoW project. Classic Era is required.")
        isScanningSkillLines = nil
        return nil
    end

    if not GetNumSkillLines or not GetSkillLineInfo
        or not ExpandSkillHeader or not CollapseSkillHeader
    then
        printMessage("This client does not provide the Classic skill line API.")
        isScanningSkillLines = nil
        return nil
    end

    local expandedHeaders = {}
    for index = 1, GetNumSkillLines() do
        local skillName, header, isExpanded = GetSkillLineInfo(index)
        if header and skillName then
            expandedHeaders[skillName] = isExpanded and true or false
        end
    end

    ExpandSkillHeader(0)

    local snapshot = {
        scannedAt = time(),
        character = getCharacterContext(),
        skillLines = {},
    }
    local category
    for index = 1, GetNumSkillLines() do
        local skillName, header, isExpanded, skillRank, numTempPoints,
            skillModifier, skillMaxRank, isAbandonable, stepCost, rankCost,
            minLevel, skillCostType, skillDescription = GetSkillLineInfo(index)

        if skillName and skillName ~= "" then
            if header then
                category = skillName
            end

            snapshot.skillLines[#snapshot.skillLines + 1] = {
                index = index,
                name = skillName,
                category = category,
                isHeader = header and true or false,
                isExpanded = isExpanded and true or false,
                rank = skillRank,
                temporaryPoints = numTempPoints,
                modifier = skillModifier,
                maxRank = skillMaxRank,
                isAbandonable = isAbandonable and true or false,
                isLearnable = stepCost and true or false,
                isTrainable = rankCost and true or false,
                minLevel = minLevel,
                costType = skillCostType,
                description = skillDescription,
            }
        end
    end

    for index = GetNumSkillLines(), 1, -1 do
        local skillName, header = GetSkillLineInfo(index)
        if header and skillName and expandedHeaders[skillName] == false then
            CollapseSkillHeader(index)
        end
    end

    if #snapshot.skillLines == 0 then
        printMessage("No skill lines were returned; skill snapshot was not overwritten.")
        isScanningSkillLines = nil
        return nil
    end

    local catalog = getOrCreateCatalog(client)
    catalog.skillSnapshots[getCharacterKey()] = snapshot
    catalog.skillsScannedAt = snapshot.scannedAt

    local skillCount = 0
    for _, skill in ipairs(snapshot.skillLines) do
        if not skill.isHeader then
            skillCount = skillCount + 1
        end
    end

    if not silent then
        printMessage(string.format(
            "Scanned %d skill lines in %d categories. Use /reload to save the snapshot.",
            skillCount,
            #snapshot.skillLines - skillCount
        ))
    end
    isScanningSkillLines = nil
    return snapshot
end

local function getSpellTooltipLines(slot, bookType)
    scanningTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanningTooltip:ClearLines()
    scanningTooltip:SetSpellBookItem(slot, bookType)

    local lines = {}
    for lineIndex = 1, scanningTooltip:NumLines() do
        local leftLine = _G["ForeverCollectScanningTooltipTextLeft" .. lineIndex]
        local rightLine = _G["ForeverCollectScanningTooltipTextRight" .. lineIndex]
        local leftText = leftLine and leftLine:GetText()
        local rightText = rightLine and rightLine:GetText()
        if leftText or rightText then
            lines[#lines + 1] = { leftText = leftText, rightText = rightText }
        end
    end
    scanningTooltip:Hide()
    return lines
end

local function scanSpellbook()
    local spells = {}
    if not GetNumSpellTabs or not GetSpellTabInfo or not GetSpellBookItemInfo then
        return spells
    end

    for tabIndex = 1, GetNumSpellTabs() do
        local tabName, _, offset, numSlots = GetSpellTabInfo(tabIndex)
        for slot = offset + 1, offset + numSlots do
            local spellType, spellID = GetSpellBookItemInfo(slot, BOOKTYPE_SPELL)
            local name, subtext = GetSpellBookItemName(slot, BOOKTYPE_SPELL)
            if spellType and (name or spellID) then
                spells[#spells + 1] = {
                    slot = slot,
                    tabIndex = tabIndex,
                    tabName = tabName,
                    type = spellType,
                    spellID = spellID,
                    name = name,
                    subtext = subtext,
                    icon = GetSpellTexture and GetSpellTexture(slot, BOOKTYPE_SPELL) or nil,
                    link = GetSpellLink and GetSpellLink(slot, BOOKTYPE_SPELL) or nil,
                    isPassive = IsPassiveSpell and IsPassiveSpell(slot, BOOKTYPE_SPELL) or false,
                    isHidden = IsSpellHidden and IsSpellHidden(slot, BOOKTYPE_SPELL) or false,
                    tooltipLines = getSpellTooltipLines(slot, BOOKTYPE_SPELL),
                }
            end
        end
    end
    return spells
end

local function scanRunes()
    local runes = {}
    if not C_Engraving or not C_Engraving.GetRuneCategories
        or not C_Engraving.GetRunesForCategory
    then
        return runes
    end

    local seen = {}
    for _, category in ipairs(C_Engraving.GetRuneCategories(false, true) or {}) do
        for _, rune in ipairs(C_Engraving.GetRunesForCategory(category, true) or {}) do
            if not seen[rune.skillLineAbilityID] then
                seen[rune.skillLineAbilityID] = true
                local abilities = {}
                for _, spellID in ipairs(rune.learnedAbilitySpellIDs or {}) do
                    local spellName, spellRank, spellIcon = GetSpellInfo and GetSpellInfo(spellID)
                    if C_Spell and C_Spell.GetSpellInfo then
                        local spellInfo = C_Spell.GetSpellInfo(spellID)
                        spellName = spellName or (spellInfo and spellInfo.name)
                        spellIcon = spellIcon or (spellInfo and spellInfo.iconID)
                    end
                    abilities[#abilities + 1] = {
                        spellID = spellID,
                        name = spellName,
                        rank = spellRank,
                        icon = spellIcon,
                        description = C_Spell and C_Spell.GetSpellDescription
                            and C_Spell.GetSpellDescription(spellID)
                            or nil,
                    }
                end
                runes[#runes + 1] = {
                    category = category,
                    skillLineAbilityID = rune.skillLineAbilityID,
                    itemEnchantmentID = rune.itemEnchantmentID,
                    name = rune.name,
                    icon = rune.iconTexture,
                    equipmentSlot = rune.equipmentSlot,
                    level = rune.level,
                    isEquipped = C_Engraving.IsRuneEquipped
                        and C_Engraving.IsRuneEquipped(rune.skillLineAbilityID)
                        or false,
                    learnedAbilitySpellIDs = rune.learnedAbilitySpellIDs or {},
                    abilities = abilities,
                }
            end
        end
    end
    return runes
end

local function scanAbilityCatalog(silent)
    local client = getClientInfo()
    if client.projectID ~= WOW_PROJECT_CLASSIC then
        return nil
    end

    local snapshot = {
        scannedAt = time(),
        character = getCharacterContext(),
        spells = scanSpellbook(),
        runes = scanRunes(),
    }
    local catalog = getOrCreateCatalog(client)
    catalog.abilitySnapshots[getCharacterKey()] = snapshot
    catalog.abilitiesScannedAt = snapshot.scannedAt

    if not silent then
        printMessage(string.format(
            "Scanned %d spellbook entries and %d runes. Use /reload to save the snapshot.",
            #snapshot.spells,
            #snapshot.runes
        ))
    end
    return snapshot
end

local function getItemIDFromLink(link)
    if not link then
        return nil
    end
    return tonumber(string.match(link, "item:(%d+)"))
end

local function scanQuestItems(itemType, count)
    local items = {}
    for index = 1, count or 0 do
        local name, texture, quantity, quality, isUsable = GetQuestItemInfo(itemType, index)
        local link = GetQuestItemLink(itemType, index)
        items[#items + 1] = {
            index = index,
            itemID = getItemIDFromLink(link),
            name = name,
            link = link,
            texture = texture,
            quantity = quantity,
            quality = quality,
            isUsable = isUsable,
        }
    end
    return items
end

local function scanQuestSpells(questID)
    local spells = {}
    if C_QuestInfoSystem and C_QuestInfoSystem.GetQuestRewardSpells then
        local spellIDs = C_QuestInfoSystem.GetQuestRewardSpells(questID) or {}
        for _, spellID in ipairs(spellIDs) do
            local info = C_QuestInfoSystem.GetQuestRewardSpellInfo(questID, spellID)
            spells[#spells + 1] = {
                spellID = spellID,
                name = info and info.name,
                texture = info and info.texture,
                isTradeskill = info and info.isTradeskill,
                isSpellLearned = info and info.isSpellLearned,
            }
        end
    elseif GetRewardSpell then
        local texture, name, isTradeskill, isSpellLearned = GetRewardSpell()
        if name then
            spells[1] = {
                name = name,
                texture = texture,
                isTradeskill = isTradeskill,
                isSpellLearned = isSpellLearned,
            }
        end
    end
    return spells
end

local function scanQuestRewards(questID)
    local rewards = {
        items = scanQuestItems("reward", GetNumQuestRewards()),
        choices = scanQuestItems("choice", GetNumQuestChoices()),
        spells = scanQuestSpells(questID),
        money = GetRewardMoney and GetRewardMoney() or nil,
        xp = GetRewardXP and GetRewardXP() or nil,
    }
    return rewards
end

local function scanQuestProgress()
    return {
        requiredItems = scanQuestItems("required", GetNumQuestItems()),
        requiredMoney = GetQuestMoneyToGet and GetQuestMoneyToGet() or nil,
    }
end

local function captureQuest(event)
    if event == "QUEST_ITEM_UPDATE" and not activeQuestPhase then
        return
    end

    local questID = GetQuestID and GetQuestID()
    if not questID or questID == 0 then
        return
    end

    local client = getClientInfo()
    local catalog = getOrCreateCatalog(client)
    local quest = catalog.quests[questID] or {
        questID = questID,
        observations = {},
    }
    local observation = quest.observations[#quest.observations]
    local phase = event == "QUEST_ITEM_UPDATE" and activeQuestPhase or event
    if not observation or observation.phase ~= phase then
        local role = "giver"
        if event == "QUEST_PROGRESS" then
            role = "progress"
        elseif event == "QUEST_COMPLETE" then
            role = "turnIn"
        end
        observation = {
            phase = phase,
            capturedAt = time(),
            character = getCharacterContext(),
            questNPC = getQuestNPC(role),
        }
        mergeNPC(catalog, observation.questNPC)
        quest.observations[#quest.observations + 1] = observation
    end

    quest.title = GetTitleText and GetTitleText() or quest.title
    if event == "QUEST_DETAIL" then
        observation.description = GetQuestText and GetQuestText() or nil
        observation.objectives = GetObjectiveText and GetObjectiveText() or nil
        observation.rewards = scanQuestRewards(questID)
    elseif event == "QUEST_PROGRESS" then
        observation.text = GetProgressText and GetProgressText() or nil
        observation.progress = scanQuestProgress()
    elseif event == "QUEST_COMPLETE" then
        observation.text = GetRewardText and GetRewardText() or nil
        observation.rewards = scanQuestRewards(questID)
    elseif event == "QUEST_ITEM_UPDATE" then
        if activeQuestPhase == "QUEST_DETAIL" or activeQuestPhase == "QUEST_COMPLETE" then
            observation.rewards = scanQuestRewards(questID)
        elseif activeQuestPhase == "QUEST_PROGRESS" then
            observation.progress = scanQuestProgress()
        end
    end

    catalog.quests[questID] = quest
    catalog.questScanUpdatedAt = time()
    if event ~= "QUEST_ITEM_UPDATE" then
        activeQuestPhase = event
    end
end

local function recordQuestTurnIn(questID, xpReward, moneyReward)
    if not questID or questID == 0 then
        return
    end
    local catalog = getOrCreateCatalog(getClientInfo())
    local quest = catalog.quests[questID] or { questID = questID, observations = {} }
    quest.turnIn = {
        capturedAt = time(),
        xp = xpReward,
        money = moneyReward,
        character = getCharacterContext(),
    }
    catalog.quests[questID] = quest
    catalog.questScanUpdatedAt = time()
end

local function countCapturedQuestPhases(catalog)
    local questCount, observationCount = 0, 0
    for _, quest in pairs(catalog.quests or {}) do
        questCount = questCount + 1
        observationCount = observationCount + #(quest.observations or {})
    end
    return questCount, observationCount
end

local function getLatestCatalog()
    initializeDatabase()
    return ForeverCollectDB.catalogs[ForeverCollectDB.latestCatalogKey]
end

local function handleSlashCommand(message)
    local command = string.lower(string.gsub(message or "", "^%s*(.-)%s*$", "%1"))

    if command == "" or command == "help" then
        printMessage("Commands: /fc scan, /fc talents, /fc skills, /fc spells, /fc runes, /fc quests, /fc status")
    elseif command == "scan" then
        scanTalentCatalog()
        scanSkillLines()
        scanAbilityCatalog()
    elseif command == "talents" then
        local catalog = getLatestCatalog()
        if not catalog then
            printMessage("No catalog found. Use /fc scan first.")
            return
        end

        local specializationCount = #catalog.specializations
        local talentCount = 0
        for _, specialization in ipairs(catalog.specializations) do
            talentCount = talentCount + #specialization.talents
        end

        printMessage(string.format(
            "Catalog contains %d talent trees and %d talents from client %s.",
            specializationCount,
            talentCount,
            catalog.version
        ))
    elseif command == "quests" then
        local catalog = getLatestCatalog()
        if not catalog then
            printMessage("No catalog found. Open a quest dialog first.")
            return
        end

        local questCount, observationCount = countCapturedQuestPhases(catalog)
        printMessage(string.format(
            "Quest catalog contains %d quests and %d observations from client %s.",
            questCount,
            observationCount,
            catalog.version
        ))
    elseif command == "skills" then
        local catalog = getLatestCatalog()
        if not catalog then
            printMessage("No catalog found. Use /fc scan first.")
            return
        end

        local snapshot = catalog.skillSnapshots
            and catalog.skillSnapshots[getCharacterKey()]
        if not snapshot then
            printMessage("No skill snapshot found. Use /fc scan first.")
            return
        end

        local categoryCount, skillCount = 0, 0
        for _, skill in ipairs(snapshot.skillLines) do
            if skill.isHeader then
                categoryCount = categoryCount + 1
            else
                skillCount = skillCount + 1
            end
        end
        printMessage(string.format(
            "Skill snapshot contains %d skill lines in %d categories (captured at %s).",
            skillCount,
            categoryCount,
            date("!%Y-%m-%d %H:%M:%S", snapshot.scannedAt)
        ))
    elseif command == "spells" or command == "runes" then
        local catalog = getLatestCatalog()
        local snapshot = catalog and catalog.abilitySnapshots
            and catalog.abilitySnapshots[getCharacterKey()]
        if not snapshot then
            printMessage("No ability snapshot found. Use /fc scan first.")
            return
        end
        local entries = command == "spells" and snapshot.spells or snapshot.runes
        printMessage(string.format(
            "%s snapshot contains %d entries (captured at %s).",
            command == "spells" and "Spellbook" or "Rune",
            #entries,
            date("!%Y-%m-%d %H:%M:%S", snapshot.scannedAt)
        ))
    elseif command == "status" then
        local catalog = getLatestCatalog()
        if catalog then
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
            local snapshot = catalog.skillSnapshots
                and catalog.skillSnapshots[getCharacterKey()]
            if snapshot then
                local skillCount = 0
                for _, skill in ipairs(snapshot.skillLines) do
                    if not skill.isHeader then
                        skillCount = skillCount + 1
                    end
                end
                printMessage(string.format(
                    "Skills: %d lines, captured at %s.",
                    skillCount,
                    date("!%Y-%m-%d %H:%M:%S", snapshot.scannedAt)
                ))
            end
            local abilitySnapshot = catalog.abilitySnapshots
                and catalog.abilitySnapshots[getCharacterKey()]
            if abilitySnapshot then
                printMessage(string.format(
                    "Abilities: %d spellbook entries, %d runes.",
                    #abilitySnapshot.spells,
                    #abilitySnapshot.runes
                ))
            end
        else
            printMessage("No catalog stored yet. Open a quest or use /fc scan.")
        end
    else
        printMessage("Unknown command. Use /fc help.")
    end
end

SLASH_FOREVERCOLLECT1 = "/forevercollect"
SLASH_FOREVERCOLLECT2 = "/fc"
SlashCmdList.FOREVERCOLLECT = handleSlashCommand

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
eventFrame:RegisterEvent("SKILL_LINES_CHANGED")
eventFrame:RegisterEvent("SPELLS_CHANGED")
eventFrame:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE")
eventFrame:RegisterEvent("RUNE_UPDATED")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("NEW_RECIPE_LEARNED")
eventFrame:RegisterEvent("QUEST_DETAIL")
eventFrame:RegisterEvent("QUEST_PROGRESS")
eventFrame:RegisterEvent("QUEST_COMPLETE")
eventFrame:RegisterEvent("QUEST_ITEM_UPDATE")
eventFrame:RegisterEvent("QUEST_FINISHED")
eventFrame:RegisterEvent("QUEST_TURNED_IN")
eventFrame:RegisterEvent("MERCHANT_SHOW")
eventFrame:RegisterEvent("TRAINER_SHOW")
eventFrame:RegisterEvent("BANKFRAME_OPENED")
eventFrame:RegisterEvent("TAXIMAP_OPENED")
--eventFrame:RegisterEvent("INNKEEPER_SHOW")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    local loadedAddonName = ...
    if event == "ADDON_LOADED" and loadedAddonName == addonName then
        initializeDatabase()
        migrateNPCData()
        printMessage("loaded. Use /fc help.")
    elseif event == "PLAYER_LOGIN" then
        scanTalentCatalog()
        scanSkillLines(true)
        scanAbilityCatalog(true)
    elseif event == "PLAYER_TALENT_UPDATE" then
        scanTalentCatalog()
    elseif event == "SKILL_LINES_CHANGED" then
        scanSkillLines(true)
    elseif event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_SKILL_LINE"
        or event == "RUNE_UPDATED" or event == "PLAYER_EQUIPMENT_CHANGED"
        or event == "NEW_RECIPE_LEARNED"
    then
        scanAbilityCatalog(true)
    elseif event == "QUEST_DETAIL" or event == "QUEST_PROGRESS" or event == "QUEST_COMPLETE" then
        captureQuest(event)
    elseif event == "QUEST_ITEM_UPDATE" then
        captureQuest(event)
    elseif event == "QUEST_TURNED_IN" then
        local questID, xpReward, moneyReward = ...
        recordQuestTurnIn(questID, xpReward, moneyReward)
    elseif event == "MERCHANT_SHOW" then
        captureNPCInteraction("merchant")
    elseif event == "TRAINER_SHOW" then
        captureNPCInteraction("trainer")
    elseif event == "BANKFRAME_OPENED" then
        captureNPCInteraction("banker")
    elseif event == "TAXIMAP_OPENED" then
        captureNPCInteraction("flightMaster")
    elseif event == "INNKEEPER_SHOW" then
        captureNPCInteraction("innkeeper")
    elseif event == "QUEST_FINISHED" then
        activeQuestPhase = nil
    else
        return
    end
end)
