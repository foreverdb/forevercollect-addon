local _, addon = ...

local printMessage = addon.PrintMessage
local formatTimestamp = addon.FormatTimestamp
local getClientInfo = addon.GetClientInfo
local getOrCreateCatalog = addon.GetOrCreateCatalog
local getLatestCatalog = addon.GetLatestCatalog
local getCharacterContext = addon.GetCharacterContext
local getCharacterKey = addon.GetCharacterKey
local initializeDatabase = addon.InitializeDatabase
local isSupportedClient = addon.IsSupportedClient

local isScanningSkillLines

-- Returns the number of real skill lines and the number of category headers.
local function countSkillLines(snapshot)
    local skillCount, headerCount = 0, 0
    for _, skill in ipairs(snapshot.skillLines) do
        if skill.isHeader then
            headerCount = headerCount + 1
        else
            skillCount = skillCount + 1
        end
    end
    return skillCount, headerCount
end
addon.CountSkillLines = countSkillLines

local function scanSkillLines(silent)
    if isScanningSkillLines then
        return nil
    end
    isScanningSkillLines = true
    initializeDatabase()

    local client = getClientInfo()
    if not isSupportedClient(client) then
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

    if not silent then
        local skillCount, headerCount = countSkillLines(snapshot)
        printMessage(string.format(
            "Scanned %d skill lines in %d categories. Use /reload to save the snapshot.",
            skillCount,
            headerCount
        ))
    end
    isScanningSkillLines = nil
    return snapshot
end
addon.ScanSkillLines = scanSkillLines

addon:RegisterEvent("SKILL_LINES_CHANGED", function()
    scanSkillLines(true)
end)

addon:RegisterCommand("skills", function()
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

    local skillCount, categoryCount = countSkillLines(snapshot)
    printMessage(string.format(
        "Skill snapshot contains %d skill lines in %d categories (captured at %s).",
        skillCount,
        categoryCount,
        formatTimestamp(snapshot.scannedAt)
    ))
end, "Skill-Snapshot des aktuellen Charakters anzeigen")
