local _, addon = ...

local printMessage = addon.PrintMessage
local getItemIDFromLink = addon.GetItemIDFromLink
local getClientInfo = addon.GetClientInfo
local getOrCreateCatalog = addon.GetOrCreateCatalog
local getLatestCatalog = addon.GetLatestCatalog
local getCharacterContext = addon.GetCharacterContext
local recordItem = addon.RecordItem

local isScanning
local lastSignature = {}
local hasAnnounced = {}

local function getRecipeKey(recipeLink, name)
    local spellID = recipeLink and (
        tonumber(string.match(recipeLink, "enchant:(%d+)"))
        or tonumber(string.match(recipeLink, "spell:(%d+)"))
    )
    return spellID or name, spellID
end

local function readReagents(count, getInfo, getLink, source)
    local reagents = {}
    for reagentIndex = 1, count or 0 do
        local name, texture, needed = getInfo(reagentIndex)
        local link = getLink(reagentIndex)
        if name or link then
            reagents[#reagents + 1] = {
                itemID = getItemIDFromLink(link),
                name = name,
                link = link,
                texture = texture,
                count = needed,
            }
            if link then
                recordItem(link, source)
            end
        end
    end
    return reagents
end

-- Classic uses two windows with parallel APIs: the trade skill window for
-- most professions and the craft window for enchanting and beast training.
-- Each accessor set below describes one window.
local WINDOWS = {
    tradeSkill = {
        name = "tradeSkill",
        getSkillLine = function()
            return GetTradeSkillLine()
        end,
        getNum = function()
            return GetNumTradeSkills()
        end,
        getInfo = function(index)
            local name, difficulty, numAvailable, isExpanded, altVerb = GetTradeSkillInfo(index)
            return name, difficulty, numAvailable, isExpanded, { altVerb = altVerb }
        end,
        getItemLink = GetTradeSkillItemLink,
        getRecipeLink = GetTradeSkillRecipeLink,
        getNumReagents = GetTradeSkillNumReagents,
        getReagentInfo = GetTradeSkillReagentInfo,
        getReagentLink = GetTradeSkillReagentItemLink,
        getExtra = function(index)
            local minMade, maxMade = GetTradeSkillNumMade(index)
            return {
                numMadeMin = minMade,
                numMadeMax = maxMade,
                tools = GetTradeSkillTools and { GetTradeSkillTools(index) } or nil,
                cooldown = GetTradeSkillCooldown and GetTradeSkillCooldown(index) or nil,
                description = GetTradeSkillDescription and GetTradeSkillDescription(index) or nil,
            }
        end,
        expandAll = function() ExpandTradeSkillSubClass(0) end,
        collapse = function(index) CollapseTradeSkillSubClass(index) end,
        showEvent = "TRADE_SKILL_SHOW",
        updateEvent = "TRADE_SKILL_UPDATE",
        closeEvent = "TRADE_SKILL_CLOSE",
        isAvailable = function()
            return GetTradeSkillLine and GetNumTradeSkills and GetTradeSkillInfo
                and ExpandTradeSkillSubClass and CollapseTradeSkillSubClass
        end,
    },
    craft = {
        name = "craft",
        getSkillLine = function()
            if GetCraftDisplaySkillLine then
                local name, rank, maxRank = GetCraftDisplaySkillLine()
                if name then
                    return name, rank, maxRank
                end
            end
            return GetCraftName and GetCraftName() or nil, nil, nil
        end,
        getNum = function()
            return GetNumCrafts()
        end,
        getInfo = function(index)
            local name, subSpellName, difficulty, numAvailable, isExpanded,
                trainingPointCost, requiredLevel = GetCraftInfo(index)
            return name, difficulty, numAvailable, isExpanded, {
                subSpellName = subSpellName,
                trainingPointCost = trainingPointCost,
                requiredLevel = requiredLevel,
            }
        end,
        getItemLink = GetCraftItemLink,
        getRecipeLink = GetCraftRecipeLink,
        getNumReagents = GetCraftNumReagents,
        getReagentInfo = GetCraftReagentInfo,
        getReagentLink = GetCraftReagentItemLink,
        getExtra = function(index)
            return {
                description = GetCraftDescription and GetCraftDescription(index) or nil,
                cooldown = GetCraftCooldown and GetCraftCooldown(index) or nil,
                spellFocus = GetCraftSpellFocus and GetCraftSpellFocus(index) or nil,
            }
        end,
        expandAll = function() ExpandCraftSkillLine(0) end,
        collapse = function(index) CollapseCraftSkillLine(index) end,
        showEvent = "CRAFT_SHOW",
        updateEvent = "CRAFT_UPDATE",
        closeEvent = "CRAFT_CLOSE",
        isAvailable = function()
            return GetNumCrafts and GetCraftInfo and ExpandCraftSkillLine and CollapseCraftSkillLine
        end,
    },
}

local function getListSignature(window)
    local parts = {}
    for index = 1, window.getNum() do
        local name, difficulty = window.getInfo(index)
        parts[index] = (name or "") .. ":" .. (difficulty or "")
    end
    return table.concat(parts, "|")
end

-- Returns the index of the exclusively selected filter entry, or 0 when all
-- entries are enabled. Used for the trade skill subclass/inventory slot
-- dropdowns.
local function getSelectedFilter(getEntries, getFilter)
    local entries = { getEntries() }
    local selected, selectedCount = 0, 0
    for index = 1, #entries do
        if getFilter(index) then
            selected = index
            selectedCount = selectedCount + 1
        end
    end
    if selectedCount == #entries or selectedCount == 0 then
        return 0
    end
    return selected
end

-- Clears the trade skill window's filters so every known recipe is listed,
-- runs `callback` and restores the filters afterwards.
local function withAllRecipesVisible(window, callback)
    local restore = {}

    if window.name == "tradeSkill" then
        if TradeSkillOnlyShowMakeable then
            local checkButton = TradeSkillFrameAvailableFilterCheckButton
            restore.onlyMakeable = checkButton and checkButton:GetChecked() and true or false
            TradeSkillOnlyShowMakeable(false)
        end
        if GetTradeSkillSubClasses and GetTradeSkillSubClassFilter and SetTradeSkillSubClassFilter then
            restore.subClass = getSelectedFilter(GetTradeSkillSubClasses, GetTradeSkillSubClassFilter)
            SetTradeSkillSubClassFilter(0, 1, 1)
        end
        if GetTradeSkillInvSlots and GetTradeSkillInvSlotFilter and SetTradeSkillInvSlotFilter then
            restore.invSlot = getSelectedFilter(GetTradeSkillInvSlots, GetTradeSkillInvSlotFilter)
            SetTradeSkillInvSlotFilter(0, 1, 1)
        end
        if GetTradeSkillItemNameFilter and SetTradeSkillItemNameFilter then
            restore.nameFilter = GetTradeSkillItemNameFilter()
            SetTradeSkillItemNameFilter("")
        end
    elseif window.name == "craft" and CraftOnlyShowMakeable then
        local checkButton = CraftFrameAvailableFilterCheckButton
        restore.onlyMakeable = checkButton and checkButton:GetChecked() and true or false
        CraftOnlyShowMakeable(false)
    end

    local collapsedHeaders = {}
    for index = 1, window.getNum() do
        local name, difficulty, _, isExpanded = window.getInfo(index)
        if difficulty == "header" and name and not isExpanded then
            collapsedHeaders[name] = true
        end
    end
    window.expandAll()

    local ok, result = pcall(callback)

    for index = window.getNum(), 1, -1 do
        local name, difficulty = window.getInfo(index)
        if difficulty == "header" and name and collapsedHeaders[name] then
            window.collapse(index)
        end
    end
    if restore.nameFilter and restore.nameFilter ~= "" then
        SetTradeSkillItemNameFilter(restore.nameFilter)
    end
    if restore.invSlot and restore.invSlot ~= 0 then
        SetTradeSkillInvSlotFilter(restore.invSlot, 1, 1)
    end
    if restore.subClass and restore.subClass ~= 0 then
        SetTradeSkillSubClassFilter(restore.subClass, 1, 1)
    end
    if restore.onlyMakeable then
        if window.name == "tradeSkill" then
            TradeSkillOnlyShowMakeable(true)
        else
            CraftOnlyShowMakeable(true)
        end
    end

    if not ok then
        error(result, 0)
    end
    return result
end

local function readRecipes(window, skillName, now)
    local source = { type = "recipe", skillName = skillName }
    local recipes = {}
    local header
    for index = 1, window.getNum() do
        local name, difficulty, numAvailable, _, extra = window.getInfo(index)
        if difficulty == "header" then
            header = name
        elseif name then
            local recipeLink = window.getRecipeLink and window.getRecipeLink(index) or nil
            local resultLink = window.getItemLink and window.getItemLink(index) or nil
            local key, spellID = getRecipeKey(recipeLink, name)
            local recipe = {
                spellID = spellID,
                name = name,
                recipeLink = recipeLink,
                difficulty = difficulty,
                numAvailable = numAvailable,
                header = header,
                resultItemID = getItemIDFromLink(resultLink),
                resultLink = resultLink,
                reagents = readReagents(
                    window.getNumReagents(index),
                    function(reagentIndex) return window.getReagentInfo(index, reagentIndex) end,
                    function(reagentIndex) return window.getReagentLink(index, reagentIndex) end,
                    source
                ),
                capturedAt = now,
            }
            for field, value in pairs(extra or {}) do
                recipe[field] = value
            end
            for field, value in pairs(window.getExtra(index) or {}) do
                recipe[field] = value
            end
            if resultLink then
                recordItem(resultLink, source)
            end
            recipes[key] = recipe
        end
    end
    return recipes
end

local function scanWindow(window, silent)
    if isScanning then
        return nil
    end
    if not window.isAvailable() then
        printMessage("This client does not provide the " .. window.name .. " API.")
        return nil
    end
    isScanning = true

    local skillName, rank, maxRank = window.getSkillLine()
    if not skillName or skillName == "" or window.getNum() == 0 then
        lastSignature[window.name] = getListSignature(window)
        isScanning = nil
        return nil
    end

    local now = time()
    local ok, recipes = pcall(withAllRecipesVisible, window, function()
        return readRecipes(window, skillName, now)
    end)
    lastSignature[window.name] = getListSignature(window)
    isScanning = nil
    if not ok then
        printMessage("Recipe scan failed: " .. tostring(recipes))
        return nil
    end

    local catalog = getOrCreateCatalog(getClientInfo())
    local entry = catalog.tradeSkills[skillName]
    if not entry then
        entry = { skillName = skillName, recipes = {} }
        catalog.tradeSkills[skillName] = entry
    end
    entry.window = window.name
    entry.rank = rank
    entry.maxRank = maxRank
    entry.character = getCharacterContext()
    entry.updatedAt = now
    local newCount, count = 0, 0
    for key, recipe in pairs(recipes) do
        local existing = entry.recipes[key]
        if not existing then
            newCount = newCount + 1
            recipe.firstSeenAt = now
        else
            recipe.firstSeenAt = existing.firstSeenAt
        end
        entry.recipes[key] = recipe
        count = count + 1
    end
    catalog.tradeSkillsUpdatedAt = now

    if not silent or not hasAnnounced[window.name] then
        hasAnnounced[window.name] = true
        printMessage(string.format(
            "Captured %d %s recipes (%d new).",
            count,
            skillName,
            newCount
        ))
    end
    return entry
end

for _, window in pairs(WINDOWS) do
    addon:RegisterEvent(window.showEvent, function()
        hasAnnounced[window.name] = nil
        scanWindow(window, false)
    end)
    -- Re-scan when the list actually changes, but not for updates caused by
    -- our own filter and header changes.
    addon:RegisterEvent(window.updateEvent, function()
        if isScanning or not window.isAvailable() or window.getNum() == 0
            or getListSignature(window) == lastSignature[window.name]
        then
            return
        end
        scanWindow(window, true)
    end)
    addon:RegisterEvent(window.closeEvent, function()
        hasAnnounced[window.name] = nil
        lastSignature[window.name] = nil
    end)
end

local function countRecipes(catalog)
    local skillCount, recipeCount = 0, 0
    for _, entry in pairs(catalog.tradeSkills or {}) do
        skillCount = skillCount + 1
        for _ in pairs(entry.recipes) do
            recipeCount = recipeCount + 1
        end
    end
    return skillCount, recipeCount
end
addon.CountRecipes = countRecipes

addon:RegisterCommand("recipes", function()
    local catalog = getLatestCatalog()
    if not catalog then
        printMessage("No catalog found. Open a profession window first.")
        return
    end
    local skillCount, recipeCount = countRecipes(catalog)
    printMessage(string.format(
        "Recipe catalog contains %d professions with %d recipes.",
        skillCount,
        recipeCount
    ))
end, "Berufe und Rezepte anzeigen")
