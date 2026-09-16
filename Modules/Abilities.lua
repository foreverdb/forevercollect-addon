local _, addon = ...

local printMessage = addon.PrintMessage
local formatTimestamp = addon.FormatTimestamp
local getClientInfo = addon.GetClientInfo
local getOrCreateCatalog = addon.GetOrCreateCatalog
local getLatestCatalog = addon.GetLatestCatalog
local getCharacterContext = addon.GetCharacterContext
local getCharacterKey = addon.GetCharacterKey
local isSupportedClient = addon.IsSupportedClient

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
    if not isSupportedClient(client) then
        return nil
    end

    local snapshot = {
        scannedAt = time(),
        character = getCharacterContext(),
        runes = scanRunes(),
    }
    local catalog = getOrCreateCatalog(client)
    catalog.abilitySnapshots[getCharacterKey()] = snapshot
    catalog.abilitiesScannedAt = snapshot.scannedAt

    if not silent then
        printMessage(string.format(
            "Scanned %d runes. Use /reload to save the snapshot.",
            #snapshot.runes
        ))
    end
    return snapshot
end
addon.ScanAbilityCatalog = scanAbilityCatalog

local function getAbilitySnapshot()
    local catalog = getLatestCatalog()
    return catalog and catalog.abilitySnapshots
        and catalog.abilitySnapshots[getCharacterKey()]
end
addon.GetAbilitySnapshot = getAbilitySnapshot

for _, event in ipairs({ "RUNE_UPDATED", "PLAYER_EQUIPMENT_CHANGED" }) do
    addon:RegisterEvent(event, function()
        scanAbilityCatalog(true)
    end)
end

addon:RegisterCommand("runes", function()
    local snapshot = getAbilitySnapshot()
    if not snapshot then
        printMessage("No rune snapshot found. Use /fc scan first.")
        return
    end
    printMessage(string.format(
        "Rune snapshot contains %d entries (captured at %s).",
        #snapshot.runes,
        formatTimestamp(snapshot.scannedAt)
    ))
end, "Runen-Snapshot anzeigen")
