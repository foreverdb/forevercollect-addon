local _, addon = ...

local printMessage = addon.PrintMessage
local getClientInfo = addon.GetClientInfo
local getOrCreateCatalog = addon.GetOrCreateCatalog
local getCharacterContext = addon.GetCharacterContext
local getCharacterKey = addon.GetCharacterKey
local isSupportedClient = addon.IsSupportedClient
local initializeDatabase = addon.InitializeDatabase

-- Armory: a snapshot of the own character (equipment, spent talents, professions,
-- stats) for its public profile on ForeverDB. Name and realm leave the computer
-- only with this snapshot, so it is opt-in (/fc armory on) and turning it off
-- removes every stored snapshot again.

-- Talent and trait data load lazily after login.
local CAPTURE_DELAY = 5
-- Gear swaps and talent resets fire bursts of events; one capture per burst.
local DEBOUNCE_SECONDS = 2

-- INVSLOT_AMMO (0) .. INVSLOT_TABARD (19)
local FIRST_SLOT, LAST_SLOT = 0, 19

local pending
-- Per character key: the snapshot the file held at login (false: none). A gear swap passes
-- through intermediate states; when it ends where the session started, the stored snapshot is
-- put back unchanged, so the upload deduplicates instead of adding a copy with a new time.
local savedSnapshots = {}

local function isEnabled()
    local settings = ForeverCollectDB and ForeverCollectDB.settings
    return settings and settings.armory == true or false
end

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

-- item:itemID:enchantID:gem1:gem2:gem3:gem4:suffixID:uniqueID:...
local function parseItemLink(link)
    local itemString = string.match(link, "item:([%-%d:]+)")
    if not itemString then
        return nil
    end
    -- Mainline-engine links (Forever) leave unused fields empty ("item:154::::::::11:..."),
    -- so the position counts, not the number of values.
    local fields, index = {}, 0
    for value in string.gmatch(itemString .. ":", "([^:]*):") do
        index = index + 1
        fields[index] = tonumber(value)
    end
    local function positive(value)
        return value and value ~= 0 and value or nil
    end
    return {
        itemID = fields[1],
        enchantID = positive(fields[2]),
        suffixID = positive(fields[7]),
        link = link,
    }
end

local function captureEquipment()
    local equipment = {}
    for slot = FIRST_SLOT, LAST_SLOT do
        local link = GetInventoryItemLink("player", slot)
        local item = link and parseItemLink(link)
        if item and item.itemID then
            item.slot = slot
            equipment[#equipment + 1] = item
        end
    end
    return equipment
end

-- Classic Era: spent ranks per tab and talent index; only learned talents.
local function captureTalents()
    if not addon.HasClassicTalentAPI() then
        return nil
    end
    local talents = {}
    for tab = 1, GetNumTalentTabs(false, false) or 0 do
        for index = 1, GetNumTalents(tab) or 0 do
            local info = call(C_SpecializationInfo.GetTalentInfo, {
                specializationIndex = tab,
                talentIndex = index,
            })
            local rank, talentID = info and info.rank, info and info.talentID
            if rank == nil and GetTalentInfo then
                rank = select(5, GetTalentInfo(tab, index))
            end
            if rank and rank > 0 then
                talents[#talents + 1] = { tab = tab, index = index, talentID = talentID, rank = rank }
            end
        end
    end
    return talents
end

-- Forever: purchased ranks of the active trait configuration.
local function captureTraits()
    if not (addon.HasTraitAPI and addon.HasTraitAPI()) then
        return nil
    end
    local configID = C_ClassTalents and call(C_ClassTalents.GetActiveConfigID)
    if not configID then
        return nil
    end
    local configInfo = call(C_Traits.GetConfigInfo, configID)
    local treeIDs = configInfo and configInfo.treeIDs or {}
    local nodes = {}
    for _, treeID in ipairs(treeIDs) do
        for _, nodeID in ipairs(call(C_Traits.GetTreeNodes, treeID) or {}) do
            local info = call(C_Traits.GetNodeInfo, configID, nodeID)
            local rank = info and (info.ranksPurchased or info.currentRank) or 0
            if rank > 0 then
                nodes[#nodes + 1] = {
                    nodeID = nodeID,
                    entryID = info.activeEntry and info.activeEntry.entryID or (info.entryIDs and info.entryIDs[1]),
                    rank = rank,
                }
            end
        end
    end
    return { configID = configID, treeIDs = treeIDs, nodes = nodes }
end

-- Mainline-engine clients (Forever) name their professions with skill line IDs;
-- Classic Era only offers the skill frame's lines. Both are stored as read, the
-- server tells professions from weapon skills and languages.
local function captureProfessions()
    local professions = {}
    if GetProfessions and GetProfessionInfo then
        for _, index in ipairs({ call(GetProfessions) }) do
            local name, _, rank, maxRank, _, _, skillLineID = call(GetProfessionInfo, index)
            if name then
                professions[#professions + 1] = {
                    skillLineID = skillLineID,
                    name = name,
                    rank = rank,
                    maxRank = maxRank,
                }
            end
        end
        if #professions > 0 then
            return professions
        end
    end
    if not GetNumSkillLines or not GetSkillLineInfo then
        return nil
    end
    local header
    for index = 1, GetNumSkillLines() do
        local name, isHeader, _, rank, _, modifier, maxRank = GetSkillLineInfo(index)
        if isHeader then
            header = name
        elseif name then
            professions[#professions + 1] = {
                name = name,
                header = header,
                rank = rank,
                modifier = modifier ~= 0 and modifier or nil,
                maxRank = maxRank,
            }
        end
    end
    return professions
end

-- Values as the character sheet shows them at capture time, active buffs included.
local function captureStats()
    local stats = { primary = {}, resistances = {} }
    for index = 1, 5 do
        local base, effective = call(UnitStat, "player", index)
        stats.primary[index] = { base = base, effective = effective }
    end
    local baseArmor, effectiveArmor = call(UnitArmor, "player")
    stats.armor = { base = baseArmor, effective = effectiveArmor }
    for school = 1, 6 do
        local base, total = call(UnitResistance, "player", school)
        stats.resistances[school] = { base = base, total = total }
    end
    stats.health = call(UnitHealthMax, "player")
    stats.powerType = call(UnitPowerType, "player")
    stats.power = call(UnitPowerMax, "player")
    local apBase, apPositive, apNegative = call(UnitAttackPower, "player")
    if apBase then
        stats.attackPower = apBase + (apPositive or 0) + (apNegative or 0)
    end
    local rapBase, rapPositive, rapNegative = call(UnitRangedAttackPower, "player")
    if rapBase then
        stats.rangedAttackPower = rapBase + (rapPositive or 0) + (rapNegative or 0)
    end
    stats.critChance = call(GetCritChance)
    stats.rangedCritChance = call(GetRangedCritChance)
    stats.spellCritChance = call(GetSpellCritChance, 2) -- holy; schools differ only by talents
    stats.bonusHealing = call(GetSpellBonusHealing)
    stats.dodgeChance = call(GetDodgeChance)
    stats.parryChance = call(GetParryChance)
    stats.blockChance = call(GetBlockChance)
    return stats
end

local function buildSnapshot()
    local character = getCharacterContext()
    character.guid = UnitGUID("player")
    -- Forever has first and last names: UnitName returns the last name where other units
    -- return their realm. Classic Era returns nothing there for the own character.
    local _, surname = UnitName("player")
    character.surname = surname ~= "" and surname or nil
    local guildName, guildRank = call(GetGuildInfo, "player")
    character.guild = guildName
    character.guildRank = guildRank
    local pvpRank = call(UnitPVPRank, "player")
    character.pvpRank = pvpRank and pvpRank > 0 and pvpRank or nil
    return {
        character = character,
        equipment = captureEquipment(),
        talents = captureTalents(),
        traits = captureTraits(),
        professions = captureProfessions(),
        stats = captureStats(),
    }
end

local function deepEqual(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return a == b
    end
    for key, value in pairs(a) do
        if not deepEqual(value, b[key]) then
            return false
        end
    end
    for key in pairs(b) do
        if a[key] == nil then
            return false
        end
    end
    return true
end

-- Stats move with every buff, so they only refresh together with a real change;
-- otherwise every reload would upload a new snapshot.
local function sameContent(a, b)
    if not b then
        return false
    end
    for _, field in ipairs({ "character", "equipment", "talents", "traits", "professions" }) do
        if not deepEqual(a[field], b[field]) then
            return false
        end
    end
    return true
end

local function capture()
    pending = nil
    if not isEnabled() then
        return
    end
    local client = getClientInfo()
    if not isSupportedClient(client) then
        return
    end
    local snapshot = buildSnapshot()
    local catalog = getOrCreateCatalog(client)
    local key = getCharacterKey()
    if savedSnapshots[key] == nil then
        savedSnapshots[key] = catalog.characters[key] or false
    end
    if sameContent(snapshot, catalog.characters[key]) then
        return
    end
    local saved = savedSnapshots[key]
    if saved and sameContent(snapshot, saved) then
        catalog.characters[key] = saved
        return
    end
    snapshot.capturedAt = time()
    catalog.characters[key] = snapshot
    addon.NoteCapture()
    addon.Announce(string.format(
        "Armory: captured %s (%d items).",
        tostring(snapshot.character.name),
        #snapshot.equipment
    ))
end

local function scheduleCapture(delay)
    if pending or not isEnabled() then
        return
    end
    pending = true
    C_Timer.After(delay or DEBOUNCE_SECONDS, capture)
end

addon:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    scheduleCapture(CAPTURE_DELAY)
end)
for _, event in ipairs({
    "PLAYER_EQUIPMENT_CHANGED",
    "CHARACTER_POINTS_CHANGED",
    "PLAYER_LEVEL_UP",
    "SKILL_LINES_CHANGED",
    "PLAYER_GUILD_UPDATE",
    "TRAIT_CONFIG_UPDATED",
}) do
    -- Events the client does not know raise an error on registration.
    pcall(addon.RegisterEvent, addon, event, function()
        scheduleCapture()
    end)
end
-- The SavedVariables are written right after logout: catch the final state.
addon:RegisterEvent("PLAYER_LOGOUT", function()
    if isEnabled() then
        capture()
    end
end)

local function removeSnapshots()
    local removed = 0
    for _, catalog in pairs(ForeverCollectDB.catalogs or {}) do
        for _ in pairs(catalog.characters or {}) do
            removed = removed + 1
        end
        catalog.characters = {}
    end
    savedSnapshots = {}
    return removed
end

addon:RegisterCommand("armory", function(argument)
    initializeDatabase()
    local settings = ForeverCollectDB.settings
    if argument == "on" then
        settings.armory = true
        printMessage("Armory on: your character (name, realm, gear, talents, professions, stats) is uploaded and gets a public profile on ForeverDB. /fc armory off removes it from the upload.")
        capture()
    elseif argument == "off" then
        settings.armory = nil
        local removed = removeSnapshots()
        addon.NoteCapture()
        printMessage(string.format(
            "Armory off: %d stored character snapshot(s) removed. /reload or log out so the file is written without them.",
            removed
        ))
    else
        printMessage(isEnabled()
            and "Armory is on. /fc armory off stops it and removes the stored snapshots."
            or "Armory is off. /fc armory on uploads your character for a public profile on ForeverDB.")
    end
end, "Public character profile: /fc armory on or off")
