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
-- only with this snapshot, so it is opt-in per character (/fc armory on) and
-- turning it off removes that character's stored snapshots again.

-- Talent and trait data load lazily after login.
local CAPTURE_DELAY = 5
-- Gear swaps and talent resets fire bursts of events; one capture per burst.
local DEBOUNCE_SECONDS = 2

-- INVSLOT_AMMO (0) .. INVSLOT_TABARD (19)
local FIRST_SLOT, LAST_SLOT = 0, 19

local pending
-- A capture came while the stats were secret; it runs again when the fight ends.
local waitingForStats = false
-- Per character key: the snapshot the file held at login (false: none). A gear swap passes
-- through intermediate states; when it ends where the session started, the stored snapshot is
-- put back unchanged, so the upload deduplicates instead of adding a copy with a new time.
local savedSnapshots = {}

local function isEnabled()
    local settings = ForeverCollectCharacterSettings
    return settings and settings.armory == true or false
end

local function readableResults(ok, ...)
    if not ok then
        return nil
    end
    local count = select("#", ...)
    local values = { ... }
    for index = 1, count do
        values[index] = addon.Readable(values[index])
    end
    return unpack(values, 1, count)
end

-- A client call that may be missing, fail or hand out secret values; those come back as nil.
local function call(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    return readableResults(pcall(fn, ...))
end

local function isSecretResult(fn, ...)
    if type(fn) ~= "function" then
        return false
    end
    local ok, value = pcall(fn, ...)
    return ok and value ~= nil and addon.Readable(value) == nil
end

-- The mainline engine (Forever) keeps a unit's stats and maximum health secret in restricted
-- situations such as combat.
local function statsAreSecret()
    return isSecretResult(UnitAttackPower, "player") or isSecretResult(UnitHealthMax, "player")
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
    if not (C_Traits and C_Traits.GetConfigInfo and C_Traits.GetTreeNodes and C_Traits.GetNodeInfo) then
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

local function publicChoice()
    local settings = ForeverCollectCharacterSettings
    local choice = settings and settings.publicChoice
    if choice == true or choice == false then
        return choice
    end
    return nil
end

local function buildSnapshot(previous)
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
        -- Bags, bank and known recipes for Companion (Modules/CharacterPrivate.lua), only
        -- with /fc private on; the server keeps them apart from the public profile.
        private = addon.BuildCharacterPrivate and addon.BuildCharacterPrivate(previous) or nil,
        -- The setup's choice whether the character shows in the Armory. The server only uses
        -- it when it first creates the character; afterwards the account page decides.
        public = publicChoice(),
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
local PUBLIC_FIELDS = { "character", "equipment", "talents", "traits", "professions" }
local CONTENT_FIELDS = { "character", "equipment", "talents", "traits", "professions", "private" }

local function sameContent(a, b, fields)
    if not b then
        return false
    end
    for _, field in ipairs(fields or CONTENT_FIELDS) do
        if not deepEqual(a[field], b[field]) then
            return false
        end
    end
    return true
end

local function capture()
    pending = nil
    waitingForStats = false
    if not isEnabled() then
        return
    end
    local client = getClientInfo()
    if not isSupportedClient(client) then
        return
    end
    -- A snapshot now would replace the stored stats with empty ones until the next real change.
    if statsAreSecret() then
        waitingForStats = true
        return
    end
    -- Without max health the unit data is not loaded yet or already torn down (Forever clears
    -- gear and stats before PLAYER_LOGOUT); such a snapshot would replace the good one empty.
    if (call(UnitHealthMax, "player") or 0) <= 0 then
        return
    end
    local catalog = getOrCreateCatalog(client)
    local key = getCharacterKey()
    local previous = catalog.characters[key]
    local snapshot = buildSnapshot(previous)
    if savedSnapshots[key] == nil then
        savedSnapshots[key] = previous or false
    end
    -- The visibility choice is no content of its own: a stored snapshot just takes it over,
    -- so a choice made after the last capture still goes up with it.
    if previous then
        previous.public = snapshot.public
    end
    if sameContent(snapshot, previous) then
        return
    end
    local saved = savedSnapshots[key]
    if saved and sameContent(snapshot, saved) then
        saved.public = snapshot.public
        catalog.characters[key] = saved
        return
    end
    snapshot.capturedAt = time()
    catalog.characters[key] = snapshot
    -- Bags change all the time; such updates only go to the capture list, not the chat.
    if sameContent(snapshot, previous, PUBLIC_FIELDS) then
        addon.NoteCapture("Companion: bags, bank and recipes updated.", {
            kind = "character",
            title = tostring(snapshot.character.name),
            detail = "Private data updated",
        })
        return
    end
    addon.Announce(string.format(
        "Armory: captured %s (%d items).",
        tostring(snapshot.character.name),
        #snapshot.equipment
    ), {
        kind = "character",
        title = tostring(snapshot.character.name),
        detail = string.format("Character uploaded · %d items equipped", #snapshot.equipment),
    })
end

local function scheduleCapture(delay)
    if pending or not isEnabled() then
        return
    end
    pending = true
    C_Timer.After(delay or DEBOUNCE_SECONDS, capture)
end

addon.ScheduleCharacterCapture = function()
    scheduleCapture()
end

addon:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    if addon.ArmoryInherited then
        addon.ArmoryInherited = nil
        printMessage("Armory is now set per character and stays on for this one, as it was for the account. "
            .. "/fc armory off removes this character from the upload.")
    end
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
addon:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if waitingForStats then
        scheduleCapture()
    end
end)
-- The SavedVariables are written right after logout: flush a debounced capture that has not
-- fired yet. Everything else is already stored from the session.
addon:RegisterEvent("PLAYER_LOGOUT", function()
    if pending and isEnabled() then
        capture()
    end
end)

-- Only the own character: the others keep their Armory setting and snapshots.
local function removeSnapshots()
    local key = getCharacterKey()
    local removed = 0
    for _, catalog in pairs(ForeverCollectDB.catalogs or {}) do
        if catalog.characters and catalog.characters[key] then
            catalog.characters[key] = nil
            removed = removed + 1
        end
    end
    savedSnapshots[key] = nil
    return removed
end

addon.IsArmoryEnabled = isEnabled

-- `options.private` decides the private part for the window and the setup; the command
-- keeps turning it on for new opt-ins.
function addon.SetArmory(enabled, options)
    initializeDatabase()
    -- The account-wide flag only seeds characters until the first explicit choice;
    -- from then on characters created later start with Armory off.
    ForeverCollectSettings.armory = nil
    ForeverCollectCharacterSettings.armory = enabled
    if enabled then
        -- New opt-ins send the private part for Companion at once.
        local private = true
        if options and options.private ~= nil then
            private = options.private and true or false
        end
        ForeverCollectCharacterSettings.private = private
        printMessage("Armory on: your character (name, realm, gear, talents, professions, stats) is uploaded to ForeverDB; "
            .. "whether it shows in the Armory you decide on foreverdb.app/profile. "
            .. (private and "Bags, bank, known recipes and completed quests go along for Companion; only you can see them (/fc private off). "
                or "")
            .. "/fc armory off removes it all from the upload.")
        if addon.ScanCompletedQuests then
            addon.ScanCompletedQuests()
        end
        capture()
    else
        if addon.ClearCharacterPrivate then
            addon.ClearCharacterPrivate()
        end
        local removed = removeSnapshots()
        addon.NoteCapture("Armory: stored snapshots removed.")
        printMessage(string.format(
            "Armory off for this character: %d stored snapshot(s) removed. /reload or log out so the file is written without them.",
            removed
        ))
    end
end

addon:RegisterCommand("armory", function(argument)
    if argument == "on" or argument == "off" then
        addon.SetArmory(argument == "on")
    else
        printMessage(isEnabled()
            and "Armory is on for this character. /fc armory off stops it and removes its stored snapshots."
            or "Armory is off for this character. /fc armory on uploads it for a public profile on ForeverDB.")
    end
end, "Public profile of this character: /fc armory on or off")
