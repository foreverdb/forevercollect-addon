local _, addon = ...

local printMessage = addon.PrintMessage
local getItemIDFromLink = addon.GetItemIDFromLink
local initializeDatabase = addon.InitializeDatabase
local copyTable = addon.CopyTable
local getCharacterKey = addon.GetCharacterKey

-- The private part of the Armory snapshot, for Companion on ForeverDB: bags, bank and
-- known recipes. It goes up with the character snapshot but only its owner sees it.
-- Opt-in on top of Armory (/fc private on, ForeverCollectCharacterSettings.private).
--
-- The uploader empties ForeverCollectDB after each upload, while the bank and the
-- recipe lists can only be read with their window open. So the last bank scan and the
-- recipe lists are also kept in ForeverCollectCharacterSettings.privateCache (the
-- character's own file, never uploaded) and copied into every new snapshot with their
-- original scan times.
--
-- Completed quests come along for the dungeon and quest pages: the full list on login and
-- each turn-in added on top, kept in privateCache like the bank (a set) with the time of
-- the newest change.

-- Profession lists arrive in several updates after the window opens; one scan per burst.
local RECIPE_SCAN_DELAY = 1
-- A stack moved or split changes several containers at once.
local CONTAINER_SCAN_DELAY = 0.5

local bankOpen = false
local recipeScanPending
local scanningRecipes
local lastRecipeSignature

local function call(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local results = { pcall(fn, ...) }
    if not results[1] then
        return nil
    end
    return unpack(results, 2)
end

local function isEnabled()
    local settings = ForeverCollectCharacterSettings
    return settings and settings.armory == true and settings.private == true or false
end

-- The capture pause covers the private part: while everything is paused, nothing new is read.
local function isScanning()
    return isEnabled() and not addon.IsPaused("all")
end

local function getCache()
    local settings = ForeverCollectCharacterSettings
    settings.privateCache = settings.privateCache or {}
    settings.privateCache.recipes = settings.privateCache.recipes or {}
    return settings.privateCache
end

local function scheduleCapture()
    if addon.ScheduleCharacterCapture then
        addon.ScheduleCharacterCapture()
    end
end

-- Containers ---------------------------------------------------------------------------

local function numSlots(bag)
    local api = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
    return tonumber(call(api, bag)) or 0
end

local function slotItem(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = call(C_Container.GetContainerItemInfo, bag, slot)
        if type(info) == "table" then
            return info.itemID or getItemIDFromLink(info.hyperlink), info.stackCount
        end
        return nil
    end
    if GetContainerItemInfo then
        local _, count, _, _, _, _, link, _, _, itemID = call(GetContainerItemInfo, bag, slot)
        return itemID or getItemIDFromLink(link), count
    end
    return nil
end

local function countContainers(bags)
    local counts = {}
    for _, bag in ipairs(bags) do
        for slot = 1, numSlots(bag) do
            local itemID, count = slotItem(bag, slot)
            if itemID then
                counts[itemID] = (counts[itemID] or 0) + (count or 1)
            end
        end
    end
    return counts
end

local function bagIndex()
    return Enum and Enum.BagIndex
end

-- Backpack and equipped bags; mainline-engine clients add a reagent bag.
local function bagIDs()
    local ids = {}
    for bag = 0, NUM_BAG_SLOTS or 4 do
        ids[#ids + 1] = bag
    end
    -- Classic Era may share the enum, but there container 5 is the first bank bag.
    local index = bagIndex()
    if index and index.ReagentBag and WOW_PROJECT_ID ~= WOW_PROJECT_CLASSIC then
        ids[#ids + 1] = index.ReagentBag
    end
    return ids
end

-- Bank slots plus bank bags. Mainline-engine clients name their bank containers in
-- Enum.BagIndex (bank bags, or character bank tabs on newer builds, and the reagent bank);
-- their numbers no longer follow NUM_BAG_SLOTS, since the reagent bag sits in between.
-- The account bank is shared by all characters and left out.
local function bankIDs()
    local ids, seen = {}, {}
    local function add(id)
        if id and not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    local index = bagIndex()
    add(BANK_CONTAINER or (index and index.Bank) or -1)
    local named = false
    if index then
        for key, id in pairs(index) do
            if string.match(key, "^BankBag_%d+$") or string.match(key, "^CharacterBankTab_%d+$")
                or key == "Reagentbank"
            then
                add(id)
                named = true
            end
        end
    end
    if not named then
        local first = (NUM_BAG_SLOTS or 4) + 1
        for bag = first, first + (NUM_BANKBAGSLOTS or 6) - 1 do
            add(bag)
        end
    end
    table.sort(ids)
    return ids
end

local function scanBank()
    if not bankOpen or not isScanning() then
        return
    end
    local ids = bankIDs()
    local slots = 0
    for _, id in ipairs(ids) do
        slots = slots + numSlots(id)
    end
    -- A closed or not yet loaded bank reports no slots; that is no empty bank.
    if slots == 0 then
        return
    end
    local cache = getCache()
    cache.bank = countContainers(ids)
    cache.bankScannedAt = time()
    scheduleCapture()
end

addon:RegisterEvent("BANKFRAME_OPENED", function()
    bankOpen = true
    scanBank()
end)
addon:RegisterEvent("BANKFRAME_CLOSED", function()
    bankOpen = false
end)
-- BAG_UPDATE fires once per changed container, on every client; BAG_UPDATE_DELAYED
-- does not reach Classic Era. One scan per burst: bank bags change with the bank open,
-- the bags themselves are read at capture time.
local containerScanPending
local function scanContainers()
    containerScanPending = nil
    if not isScanning() then
        return
    end
    scanBank()
    scheduleCapture()
end

local function scheduleContainerScan()
    if containerScanPending or not isScanning() then
        return
    end
    containerScanPending = true
    C_Timer.After(CONTAINER_SCAN_DELAY, scanContainers)
end

for _, event in ipairs({ "BAG_UPDATE", "BAG_UPDATE_DELAYED", "PLAYERBANKSLOTS_CHANGED" }) do
    pcall(addon.RegisterEvent, addon, event, scheduleContainerScan)
end

-- Recipes ------------------------------------------------------------------------------

-- Another player's linked profession, a guild list or an NPC crafting order shows
-- recipes this character does not know.
local function isForeignView()
    local ui = C_TradeSkillUI
    if ui then
        for _, name in ipairs({ "IsTradeSkillLinked", "IsTradeSkillGuild", "IsNPCCrafting" }) do
            if call(ui[name]) then
                return true
            end
        end
    end
    return call(IsTradeSkillLinked) and true or false
end

local function hasModernTradeSkillAPI()
    local ui = C_TradeSkillUI
    return ui and ui.GetAllRecipeIDs and ui.GetRecipeInfo and ui.GetBaseProfessionInfo and true or false
end

-- Mainline-engine profession window: every recipe of the profession, learned or not,
-- regardless of the window's filters; the recipe ID is the craft's spell ID.
local function readModernRecipes()
    local ui = C_TradeSkillUI
    local base = call(ui.GetBaseProfessionInfo)
    local skillLineID = base and base.professionID
    if not skillLineID or skillLineID == 0 then
        return nil
    end
    local recipeIDs = call(ui.GetAllRecipeIDs) or {}
    if #recipeIDs == 0 then
        return nil -- not loaded yet; the list update that follows scans again
    end
    local spellIDs = {}
    for _, recipeID in ipairs(recipeIDs) do
        local info = call(ui.GetRecipeInfo, recipeID)
        if info and info.learned then
            spellIDs[#spellIDs + 1] = recipeID
        end
    end
    return { skillLineID = skillLineID, name = base.professionName, spellIDs = spellIDs }
end

-- Classic profession windows: the trade skill window for most professions and the craft
-- window for enchanting (and beast training, which is no profession and skipped).
local WINDOWS = {
    {
        name = "tradeSkill",
        isAvailable = function()
            return GetTradeSkillLine and GetNumTradeSkills and GetTradeSkillInfo and true or false
        end,
        getSkillLine = function()
            return call(GetTradeSkillLine)
        end,
        getNum = function()
            return call(GetNumTradeSkills) or 0
        end,
        getInfo = function(index)
            local name, difficulty, _, isExpanded = call(GetTradeSkillInfo, index)
            return name, difficulty, isExpanded
        end,
        getRecipeLink = function(index)
            return call(GetTradeSkillRecipeLink, index)
        end,
        getItemLink = function(index)
            return call(GetTradeSkillItemLink, index)
        end,
        expandAll = function()
            call(ExpandTradeSkillSubClass, 0)
        end,
        collapse = function(index)
            call(CollapseTradeSkillSubClass, index)
        end,
    },
    {
        name = "craft",
        isAvailable = function()
            return GetNumCrafts and GetCraftInfo and true or false
        end,
        getSkillLine = function()
            local name, rank, maxRank = call(GetCraftDisplaySkillLine)
            if name then
                return name, rank, maxRank
            end
            return call(GetCraftName)
        end,
        getNum = function()
            return call(GetNumCrafts) or 0
        end,
        getInfo = function(index)
            local name, _, difficulty, _, isExpanded = call(GetCraftInfo, index)
            return name, difficulty, isExpanded
        end,
        getRecipeLink = function(index)
            return call(GetCraftRecipeLink, index)
        end,
        getItemLink = function(index)
            return call(GetCraftItemLink, index)
        end,
        expandAll = function()
            call(ExpandCraftSkillLine, 0)
        end,
        collapse = function(index)
            call(CollapseCraftSkillLine, index)
        end,
    },
}

local function openWindow()
    for _, window in ipairs(WINDOWS) do
        if window.isAvailable() then
            local skillName = window.getSkillLine()
            if skillName and skillName ~= "" and skillName ~= "UNKNOWN" and window.getNum() > 0 then
                return window, skillName
            end
        end
    end
    return nil
end

local function windowSignature(window)
    local parts = {}
    for index = 1, window.getNum() do
        local name, difficulty = window.getInfo(index)
        parts[index] = (name or "") .. ":" .. (difficulty or "")
    end
    return window.name .. "|" .. table.concat(parts, "|")
end

-- Index of the one selected filter entry, or 0 when all (or none) are selected.
local function selectedFilter(getEntries, getFilter)
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

-- Clears the window's filters and expands every header so all known recipes are
-- listed, runs `callback` and puts the window back as the player left it.
local function withAllRecipesVisible(window, callback)
    local restore = {}
    if window.name == "tradeSkill" then
        if TradeSkillOnlyShowMakeable then
            local checkButton = TradeSkillFrameAvailableFilterCheckButton
            restore.onlyMakeable = checkButton and checkButton:GetChecked() and true or false
            TradeSkillOnlyShowMakeable(false)
        end
        if GetTradeSkillSubClasses and GetTradeSkillSubClassFilter and SetTradeSkillSubClassFilter then
            restore.subClass = selectedFilter(GetTradeSkillSubClasses, GetTradeSkillSubClassFilter)
            SetTradeSkillSubClassFilter(0, 1, 1)
        end
        if GetTradeSkillInvSlots and GetTradeSkillInvSlotFilter and SetTradeSkillInvSlotFilter then
            restore.invSlot = selectedFilter(GetTradeSkillInvSlots, GetTradeSkillInvSlotFilter)
            SetTradeSkillInvSlotFilter(0, 1, 1)
        end
        if GetTradeSkillItemNameFilter and SetTradeSkillItemNameFilter then
            restore.nameFilter = GetTradeSkillItemNameFilter()
            SetTradeSkillItemNameFilter("")
        end
    elseif CraftOnlyShowMakeable then
        local checkButton = CraftFrameAvailableFilterCheckButton
        restore.onlyMakeable = checkButton and checkButton:GetChecked() and true or false
        CraftOnlyShowMakeable(false)
    end

    local collapsed = {}
    for index = 1, window.getNum() do
        local name, difficulty, isExpanded = window.getInfo(index)
        if difficulty == "header" and name and not isExpanded then
            collapsed[name] = true
        end
    end
    window.expandAll()

    local ok, result = pcall(callback)

    for index = window.getNum(), 1, -1 do
        local name, difficulty = window.getInfo(index)
        if difficulty == "header" and name and collapsed[name] then
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

local function spellIDFromLink(link)
    return link and (tonumber(string.match(link, "enchant:(%d+)")) or tonumber(string.match(link, "spell:(%d+)")))
end

-- Spell IDs from the recipe links; recipes without one are named by the item they make
-- instead. Classic Era's trade skill window gives no recipe link at all (only the craft
-- window, enchanting, has spell IDs), so there the server maps items to spells.
local function readWindowRecipes(window)
    local spellIDs, itemIDs = {}, {}
    for index = 1, window.getNum() do
        local name, difficulty = window.getInfo(index)
        if name and difficulty ~= "header" then
            local itemLink = window.getItemLink(index)
            local spellID = spellIDFromLink(window.getRecipeLink(index)) or spellIDFromLink(itemLink)
            local itemID = getItemIDFromLink(itemLink)
            if spellID then
                spellIDs[#spellIDs + 1] = spellID
            elseif itemID then
                itemIDs[#itemIDs + 1] = itemID
            end
        end
    end
    return { spellIDs = spellIDs, itemIDs = itemIDs }
end

local function readClassicRecipes()
    local window, skillName = openWindow()
    if not window then
        return nil
    end
    scanningRecipes = true
    local ok, recipes = pcall(withAllRecipesVisible, window, function()
        return readWindowRecipes(window)
    end)
    lastRecipeSignature = windowSignature(window)
    scanningRecipes = nil
    if not ok then
        printMessage("Recipe scan failed: " .. tostring(recipes))
        return nil
    end
    local itemIDs = recipes.itemIDs
    return { name = skillName, spellIDs = recipes.spellIDs, itemIDs = #itemIDs > 0 and itemIDs or nil }
end

local function scanRecipes()
    recipeScanPending = nil
    if not isScanning() or isForeignView() then
        return
    end
    local result
    if hasModernTradeSkillAPI() then
        result = readModernRecipes()
    else
        result = readClassicRecipes()
    end
    if not result or (#result.spellIDs == 0 and not result.itemIDs) then
        return
    end
    table.sort(result.spellIDs)
    if result.itemIDs then
        table.sort(result.itemIDs)
    end
    result.scannedAt = time()
    getCache().recipes[result.skillLineID or result.name] = result
    scheduleCapture()
end

local function scheduleRecipeScan()
    if recipeScanPending or scanningRecipes or not isScanning() then
        return
    end
    recipeScanPending = true
    C_Timer.After(RECIPE_SCAN_DELAY, scanRecipes)
end

for _, event in ipairs({ "TRADE_SKILL_SHOW", "CRAFT_SHOW", "TRADE_SKILL_DATA_SOURCE_CHANGED" }) do
    pcall(addon.RegisterEvent, addon, event, function()
        lastRecipeSignature = nil
        scheduleRecipeScan()
    end)
end
-- New recipes, and on mainline-engine clients the list arriving after the window opened.
-- Classic windows also fire these for the scan's own filter changes, which leave the
-- list as it was.
for _, event in ipairs({ "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_UPDATE", "CRAFT_UPDATE" }) do
    pcall(addon.RegisterEvent, addon, event, function()
        if scanningRecipes then
            return
        end
        if not hasModernTradeSkillAPI() then
            local window = openWindow()
            if not window or windowSignature(window) == lastRecipeSignature then
                return
            end
        end
        scheduleRecipeScan()
    end)
end

-- Completed quests ---------------------------------------------------------------------

-- Forever has C_QuestLog.GetAllCompletedQuestIDs (a list); Classic Era GetQuestsCompleted
-- (a map of quest ID to true). nil when the client has neither.
local function readCompletedQuests()
    local list = call(C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs)
    if type(list) == "table" then
        local quests = {}
        for _, questID in ipairs(list) do
            quests[questID] = true
        end
        return quests
    end
    local map = call(GetQuestsCompleted)
    if type(map) == "table" then
        local quests = {}
        for questID, done in pairs(map) do
            if done then
                quests[questID] = true
            end
        end
        return quests
    end
    return nil
end

local function sameSet(a, b)
    for key in pairs(a or {}) do
        if not b[key] then
            return false
        end
    end
    for key in pairs(b) do
        if not (a and a[key]) then
            return false
        end
    end
    return true
end

local function scanCompletedQuests()
    if not isScanning() then
        return
    end
    local quests = readCompletedQuests()
    if not quests then
        return
    end
    local cache = getCache()
    -- An unchanged list keeps its time, so a login alone makes no new snapshot.
    if cache.questsScannedAt and sameSet(cache.completedQuests, quests) then
        return
    end
    cache.completedQuests = quests
    cache.questsScannedAt = time()
    scheduleCapture()
end

addon.ScanCompletedQuests = scanCompletedQuests

addon:RegisterEvent("QUEST_TURNED_IN", function(questID)
    if not isScanning() or type(questID) ~= "number" then
        return
    end
    local cache = getCache()
    -- Without a full list a single ID would claim the character completed nothing else.
    if not cache.completedQuests then
        return
    end
    if cache.completedQuests[questID] then
        return
    end
    cache.completedQuests[questID] = true
    cache.questsScannedAt = time()
    scheduleCapture()
end)

local function completedQuestList(set)
    local list = {}
    for questID in pairs(set or {}) do
        list[#list + 1] = questID
    end
    table.sort(list)
    return list
end

-- Snapshot -----------------------------------------------------------------------------

-- The private section for a new snapshot: bags read now, bank and recipes from the cache.
-- While capture is paused the previous section is kept as it was.
function addon.BuildCharacterPrivate(previous)
    if not isEnabled() then
        return nil
    end
    if addon.IsPaused("all") then
        return previous and copyTable(previous.private) or nil
    end
    local cache = getCache()
    return {
        bags = countContainers(bagIDs()),
        bank = copyTable(cache.bank),
        bankScannedAt = cache.bankScannedAt,
        recipes = copyTable(cache.recipes),
        completedQuests = cache.questsScannedAt and completedQuestList(cache.completedQuests) or nil,
        questsScannedAt = cache.questsScannedAt,
    }
end

-- Opt-in -------------------------------------------------------------------------------

local function removePrivate()
    local key = getCharacterKey()
    local removed = 0
    for _, catalog in pairs(ForeverCollectDB.catalogs or {}) do
        local snapshot = catalog.characters and catalog.characters[key]
        if snapshot and snapshot.private then
            snapshot.private = nil
            removed = removed + 1
        end
    end
    return removed
end

addon.IsCharacterPrivateEnabled = isEnabled

function addon.SetCharacterPrivate(enabled)
    initializeDatabase()
    local settings = ForeverCollectCharacterSettings
    if enabled then
        if settings.armory ~= true then
            printMessage("Bags, bank and recipes go up with the Armory snapshot. Turn it on first: /fc armory on.")
            return false
        end
        settings.private = true
        scanCompletedQuests()
        printMessage("Bags, bank and recipes on: they go up with your character for Companion on ForeverDB, "
            .. "only you can see them. Open your bank and each profession window once so they are included. "
            .. "/fc private off removes them.")
        scheduleCapture()
        return true
    end
    settings.private = false
    settings.privateCache = nil
    local removed = removePrivate()
    addon.NoteCapture("Companion: bags, bank and recipes removed.")
    printMessage(string.format(
        "Bags, bank and recipes off for this character: removed from %d stored snapshot(s); the public profile stays. "
            .. "/reload or log out so the file is written without them.",
        removed
    ))
    return true
end

-- Armory switched off removes the whole snapshot; the private part and its cache go with it.
function addon.ClearCharacterPrivate()
    local settings = ForeverCollectCharacterSettings
    settings.private = nil
    settings.privateCache = nil
end

local function statusLines()
    local settings = ForeverCollectCharacterSettings or {}
    if settings.armory ~= true then
        return { "Bags, bank and recipes are off: they need Armory (/fc armory on), then /fc private on." }
    end
    if settings.private ~= true then
        return { "Bags, bank and recipes are off for this character. /fc private on sends them for Companion (only you can see them)." }
    end
    local lines = { "Bags, bank and recipes are on for this character. /fc private off removes them." }
    local cache = settings.privateCache or {}
    if cache.bankScannedAt then
        lines[#lines + 1] = "Bank: last scanned " .. date("%Y-%m-%d %H:%M", cache.bankScannedAt) .. "."
    else
        lines[#lines + 1] = "Bank: not scanned yet, open your bank once."
    end
    local professions = {}
    for _, entry in pairs(cache.recipes or {}) do
        professions[#professions + 1] = string.format(
            "%s (%d)",
            tostring(entry.name or entry.skillLineID),
            #(entry.spellIDs or {}) + #(entry.itemIDs or {})
        )
    end
    table.sort(professions)
    lines[#lines + 1] = #professions > 0
        and ("Recipes: " .. table.concat(professions, ", ") .. ".")
        or "Recipes: none yet, open each profession window once."
    local quests = 0
    for _ in pairs(cache.completedQuests or {}) do
        quests = quests + 1
    end
    lines[#lines + 1] = cache.questsScannedAt
        and string.format("Completed quests: %d, last read %s.", quests, date("%Y-%m-%d %H:%M", cache.questsScannedAt))
        or "Completed quests: not read yet, they are read on login."
    lines[#lines + 1] = "Profession window API: "
        .. (hasModernTradeSkillAPI() and "C_TradeSkillUI." or "Classic trade skill/craft window.")
    return lines
end

addon:RegisterCommand("private", function(argument)
    if argument == "on" or argument == "off" then
        addon.SetCharacterPrivate(argument == "on")
        return
    end
    for _, line in ipairs(statusLines()) do
        printMessage(line)
    end
end, "Bags, bank and recipes for Companion (only you see them): /fc private on or off")

-- Characters that opted into Armory before this part existed send nothing private
-- until the player allows it; they are told once.
addon:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    scanCompletedQuests()
    local settings = ForeverCollectCharacterSettings
    if settings and settings.armory == true and settings.private == nil and not settings.privateNoticeShown then
        settings.privateNoticeShown = true
        printMessage("Armory can now also send your bags, bank and known recipes for Companion. "
            .. "Only you can see them. /fc private on to allow it.")
    end
end)
