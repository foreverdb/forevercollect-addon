local _, addon = ...

local printMessage = addon.PrintMessage
local readTooltipLines = addon.ReadTooltipLines
local readable = addon.Readable
local getClientInfo = addon.GetClientInfo
local getOrCreateCatalog = addon.GetOrCreateCatalog
local getLatestCatalog = addon.GetLatestCatalog
local initializeDatabase = addon.InitializeDatabase
local isSupportedClient = addon.IsSupportedClient

-- Talent tooltips on Forever (1.60+): the client builds its trees on the trait
-- system (C_Traits). Tree layout, ranks and arrows come from the client's
-- trait tables (imported on the server); what only the game knows are the
-- tooltip texts with their values, so this scan walks the active trait
-- configuration and stores one tooltip per rank of every talent's spell.

-- Spell and trait data load lazily after login.
local LOGIN_SCAN_DELAY = 5

local hasAnnouncedTraits

local function hasTraitAPI()
    return C_Traits
        and C_Traits.GetConfigInfo
        and C_Traits.GetTreeNodes
        and C_Traits.GetNodeInfo
        and C_Traits.GetEntryInfo
        and C_Traits.GetDefinitionInfo
        and true or false
end
addon.HasTraitAPI = hasTraitAPI

local function call(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, result = pcall(fn, ...)
    if ok then
        return result
    end
    return nil
end

local function activeConfigID()
    local configID = C_ClassTalents and call(C_ClassTalents.GetActiveConfigID)
    if configID then
        return configID
    end
    -- Older trait clients expose the class config through the traits system id.
    if C_Traits.GetConfigIDBySystemID and Enum and Enum.TraitSystemID then
        return call(C_Traits.GetConfigIDBySystemID, Enum.TraitSystemID.Class)
    end
    return nil
end

local function spellName(spellID)
    if C_Spell and C_Spell.GetSpellName then
        return call(C_Spell.GetSpellName, spellID)
    end
    if GetSpellInfo then
        return (GetSpellInfo(spellID))
    end
    return nil
end

local function cleanLines(lines)
    local cleaned = {}
    for _, line in ipairs(lines or {}) do
        local leftText = readable(line.leftText)
        local rightText = readable(line.rightText)
        if leftText or rightText then
            cleaned[#cleaned + 1] = { leftText = leftText, rightText = rightText }
        end
    end
    return cleaned
end

-- Tooltip of one rank: the trait tooltip when the client offers it, otherwise
-- the spell tooltip.
local function traitTooltipLines(entryID, rank, spellID)
    local lines
    if entryID then
        local ok, result = pcall(readTooltipLines, function(tooltip)
            tooltip:SetTraitEntry(entryID, rank)
        end)
        if ok and result and #result > 0 then
            lines = result
        end
    end
    if not lines and spellID then
        local ok, result = pcall(readTooltipLines, function(tooltip)
            tooltip:SetSpellByID(spellID)
        end)
        if ok then
            lines = result
        end
    end
    return cleanLines(lines)
end

-- Every node of the configuration with its entry, ranks and spell.
local function collectNodes(configID)
    local configInfo = call(C_Traits.GetConfigInfo, configID)
    local treeIDs = configInfo and configInfo.treeIDs or {}
    local nodes = {}
    for _, treeID in ipairs(treeIDs) do
        for _, nodeID in ipairs(call(C_Traits.GetTreeNodes, treeID) or {}) do
            local info = call(C_Traits.GetNodeInfo, configID, nodeID)
            local entryID = info and info.entryIDs and info.entryIDs[1]
            local entry = entryID and call(C_Traits.GetEntryInfo, configID, entryID)
            local definition = entry and entry.definitionID
                and call(C_Traits.GetDefinitionInfo, entry.definitionID)
            local spellID = definition and definition.spellID
            if spellID then
                nodes[#nodes + 1] = {
                    nodeID = nodeID,
                    entryID = entryID,
                    spellID = spellID,
                    maxRank = math.max(1, info.maxRanks or (entry and entry.maxRanks) or 1),
                    name = definition.overrideName or spellName(spellID),
                }
            end
        end
    end
    return nodes, treeIDs
end

local function scanTraitCatalog(options)
    options = options or {}
    initializeDatabase()

    local client = getClientInfo()
    if not isSupportedClient(client) or not hasTraitAPI() then
        return nil
    end
    local configID = activeConfigID()
    if not configID then
        if not options.silent then
            printMessage("No active trait configuration yet. Open the talent frame once and try /fc scan again.")
        end
        return nil
    end

    local ok, nodes = pcall(collectNodes, configID)
    if not ok then
        printMessage("Trait scan failed: " .. tostring(nodes))
        return nil
    end
    if #nodes == 0 then
        if not options.silent then
            printMessage("The trait trees returned no talents yet; try /fc scan again after opening the talent frame.")
        end
        return nil
    end

    local catalog = getOrCreateCatalog(client)
    catalog.spellTooltips = catalog.spellTooltips or {}
    local captured, pending = 0, 0
    for _, node in ipairs(nodes) do
        local ranks = {}
        for rank = 1, node.maxRank do
            ranks[rank] = {
                rank = rank,
                tooltipLines = traitTooltipLines(node.entryID, rank, node.spellID),
            }
        end
        -- A single line is just the name: the spell data is not loaded yet.
        if #ranks[1].tooltipLines >= 2 then
            catalog.spellTooltips[node.spellID] = {
                name = node.name or ranks[1].tooltipLines[1].leftText,
                lines = ranks[1].tooltipLines,
                ranks = ranks,
                capturedAt = time(),
            }
            captured = captured + 1
        elseif not catalog.spellTooltips[node.spellID] then
            pending = pending + 1
        end
    end
    if captured > 0 then
        catalog.spellTooltipsUpdatedAt = time()
    end

    if not options.silent or not hasAnnouncedTraits then
        hasAnnouncedTraits = true
        addon.Announce(string.format(
            "Captured tooltips of %d talents%s. Use /reload to save the catalog.",
            captured,
            pending > 0
                and string.format(" (%d not loaded yet, /fc scan reads them later)", pending)
                or ""
        ))
    end
    return catalog
end
addon.ScanTraitCatalog = scanTraitCatalog

if hasTraitAPI() then
    addon:RegisterEvent("PLAYER_LOGIN", function()
        C_Timer.After(LOGIN_SCAN_DELAY, function()
            scanTraitCatalog({ silent = true })
        end)
    end)
end

-- Diagnostics: what this client exposes through the trait API.
addon:RegisterCommand("traits", function()
    if not hasTraitAPI() then
        printMessage("This client has no trait API (C_Traits).")
        return
    end
    local configID = activeConfigID()
    printMessage("Trait config: " .. tostring(configID))
    if not configID then
        return
    end
    local ok, nodes, treeIDs = pcall(collectNodes, configID)
    if not ok then
        printMessage("Trait scan failed: " .. tostring(nodes))
        return
    end
    printMessage(string.format("Trees: %d (%s), %d talents with spells, e.g. %s",
        #treeIDs, table.concat(treeIDs, ", "), #nodes,
        nodes[1] and string.format("%s (spell %d, %d ranks)", tostring(nodes[1].name), nodes[1].spellID, nodes[1].maxRank) or "-"))
    local catalog = getLatestCatalog()
    local count = 0
    for _ in pairs(catalog and catalog.spellTooltips or {}) do
        count = count + 1
    end
    printMessage(string.format("Catalog holds tooltips of %d talents.", count))
end, "Diagnose the client's trait trees (Forever)")
