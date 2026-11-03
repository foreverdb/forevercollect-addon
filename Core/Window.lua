local _, addon = ...

-- The ForeverCollect window (/fc): Session (what was captured since the last save), Capture
-- (what is collected), Character (upload, private data, combat log) and Advanced (talents,
-- the cache crawls for approved crawlers, the client). Built on first open; every value is
-- read again when it is shown, so changes made through /fc commands appear here too.

local Theme, W = addon.Theme, addon.Widgets
local printMessage = addon.PrintMessage

local WIDTH = 720
local PAD = 20
local CONTENT = WIDTH - 2 * PAD
local HEADER_HEIGHT = 56
local TABS_HEIGHT = 42
local ROW_HEIGHT = 59
local VISIBLE_ROWS = 6
local REFRESH_SECONDS = 1

local window, tabs
local pages = {}
local current = 1

-- Session list: kinds in the order of the filter chips, with their labels.
local FEED_KINDS = {
    { key = "quests", label = "Quests" },
    { key = "loot", label = "Loot" },
    { key = "merchants", label = "Merchants" },
    { key = "npcs", label = "NPCs" },
    { key = "trainers", label = "Trainers" },
    { key = "gathering", label = "Gathering" },
    { key = "encounters", label = "Bosses" },
    { key = "character", label = "Character" },
}

-- Capture kinds as the window describes them (Core/Pause.lua has the keys and labels).
local KIND_HINTS = {
    quests = "Dialogs and turn-ins",
    npcs = "Banker, flight master, innkeeper",
    merchants = "Inventories and prices",
    trainers = "Services and costs",
    loot = "Creatures, chests, containers",
    gathering = "Herbs, ore, skins, fish",
    encounters = "Pulls, kills, boss units",
    talents = "On login and changes",
}

local function minutesAgo(seconds)
    local minutes = math.floor((seconds or 0) / 60)
    if minutes < 1 then
        return "just now"
    end
    return minutes == 1 and "1 min ago" or (minutes .. " min ago")
end

local function addonVersion()
    local getMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    local version = getMetadata and getMetadata(addon.name or "ForeverCollect", "Version")
    return version and ("v" .. version) or "?"
end

-- A row of a list: title and detail on the left, a control slot on the right.
local function listRow(parent, title, detail)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(detail and 61 or 46)
    W.Hairline(row)
    row.title = W.Text(row, "body", "foreground")
    row.title:SetPoint("TOPLEFT", 2, detail and -13 or -15)
    row.title:SetText(title)
    if detail then
        row.detail = W.Text(row, "small", "mutedForeground")
        row.detail:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -4)
        row.detail:SetText(detail)
    end
    return row
end

local cardHead, cardSubRow, stack = W.CardHead, W.CardSubRow, W.Stack

-- Session ---------------------------------------------------------------------------------

local function buildSession(page)
    local strip = W.Card(page, "card", "primary")
    strip.outline:SetColor("primary", 0.28)
    strip:SetHeight(76)
    local stripTitle = W.Text(strip, "title", "foreground")
    stripTitle:SetPoint("TOPLEFT", 20, -18)
    local stripDetail = W.Text(strip, "small", "mutedForeground")
    stripDetail:SetPoint("TOPLEFT", stripTitle, "BOTTOMLEFT", 0, -5)
    local reload = W.Button(strip, "Reload UI to save", "primary", function()
        addon.Save(false)
    end)
    reload:SetPoint("RIGHT", -16, 0)

    local filterRow = CreateFrame("Frame", nil, page)
    filterRow:SetHeight(26)
    local label = W.SectionLabel(filterRow, "This session")
    label:SetPoint("LEFT", 0, 0)

    local list = CreateFrame("Frame", nil, page)
    list:SetHeight(ROW_HEIGHT * VISIBLE_ROWS + 1)
    W.Hairline(list, true)
    local empty = W.Text(list, "body", "mutedForeground")
    empty:SetPoint("TOPLEFT", 2, -20)
    empty:SetText("Nothing captured since the last save.")

    local rows = {}
    for index = 1, VISIBLE_ROWS do
        local row = CreateFrame("Frame", nil, list)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, -1 - (index - 1) * ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", 0, -1 - (index - 1) * ROW_HEIGHT)
        W.Hairline(row)
        row.icon = W.KindIcon(row, 30)
        row.icon:SetPoint("LEFT", 4, 0)
        row.time = W.Text(row, "number", "mutedForeground", "RIGHT")
        row.time:SetPoint("RIGHT", -4, 0)
        row.time:SetWidth(44)
        row.title = W.Text(row, "body", "foreground")
        row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 14, 3)
        row.title:SetPoint("RIGHT", row.time, "LEFT", -12, 0)
        row.detail = W.Text(row, "small", "mutedForeground")
        row.detail:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -4)
        row.detail:SetPoint("RIGHT", row.time, "LEFT", -12, 0)
        rows[index] = row
    end

    local filter, offset = nil, 0
    local chips = {}

    local function visibleEntries()
        local entries = {}
        local captures = addon.GetCaptures()
        for index = #captures, 1, -1 do
            local entry = captures[index]
            if filter == nil or entry.kind == filter then
                entries[#entries + 1] = entry
            end
        end
        return entries
    end

    local function paintRows()
        local entries = visibleEntries()
        offset = math.max(0, math.min(offset, #entries - VISIBLE_ROWS))
        empty:SetShown(#entries == 0)
        for index, row in ipairs(rows) do
            local entry = entries[index + offset]
            row:SetShown(entry ~= nil)
            if entry then
                row.icon:SetKind(entry.kind)
                row.title:SetText(entry.title or entry.text or "")
                row.detail:SetText(entry.detail or "")
                row.time:SetText(date("%H:%M", entry.at))
            end
        end
    end

    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - delta
        paintRows()
    end)

    local function paintChips()
        local counts, total = {}, 0
        for _, entry in ipairs(addon.GetCaptures()) do
            total = total + 1
            if entry.kind then
                counts[entry.kind] = (counts[entry.kind] or 0) + 1
            end
        end
        local specs = { { key = nil, label = "All " .. total } }
        for _, kind in ipairs(FEED_KINDS) do
            if counts[kind.key] then
                specs[#specs + 1] = { key = kind.key, label = kind.label .. " " .. counts[kind.key] }
            end
        end
        local previous = label
        for index, spec in ipairs(specs) do
            local chip = chips[index]
            if not chip then
                chip = W.Chip(filterRow, "")
                chips[index] = chip
            end
            chip:SetLabel(spec.label)
            chip:SetSelected(spec.key == filter)
            chip:ClearAllPoints()
            chip:SetPoint("LEFT", previous, "RIGHT", index == 1 and 14 or 4, 0)
            chip:SetScript("OnClick", function()
                filter, offset = spec.key, 0
                paintChips()
                paintRows()
            end)
            chip:Show()
            previous = chip
        end
        for index = #specs + 1, #chips do
            chips[index]:Hide()
        end
    end

    function page.Refresh()
        local count, seconds = addon.UnsavedCaptures()
        if count > 0 then
            stripTitle:SetText(count == 1 and "1 find waiting to be saved" or (count .. " finds waiting to be saved"))
        else
            stripTitle:SetText("Everything is saved")
        end
        stripDetail:SetText("Last save " .. minutesAgo(seconds))
        reload:SetActive(count > 0)
        paintChips()
        paintRows()
    end

    page.height = stack(page, { strip, filterRow, list }, 22)
end

-- Capture ---------------------------------------------------------------------------------

local function buildCapture(page)
    local master = W.Card(page)
    master:SetHeight(76)
    local head = cardHead(master, "Collect on this character")
    head:SetAllPoints()
    head.toggle.onChange = function(on)
        addon.SetPaused("all", not on)
        page.Refresh()
    end

    local kindsLabel = CreateFrame("Frame", nil, page)
    kindsLabel:SetHeight(14)
    W.SectionLabel(kindsLabel, "What to collect"):SetPoint("LEFT")

    local grid = CreateFrame("Frame", nil, page)
    local columnWidth = (CONTENT - 24) / 2
    local kindRows = {}
    for index, kind in ipairs(addon.CAPTURE_KINDS) do
        local column = (index <= 4) and 0 or 1
        local line = (index - 1) % 4
        local row = listRow(grid, kind.label, KIND_HINTS[kind.key] or kind.hint)
        row:SetWidth(columnWidth)
        row:SetPoint("TOPLEFT", column * (columnWidth + 24), -1 - line * 61)
        row.toggle = W.Toggle(row)
        row.toggle:SetPoint("RIGHT", -2, 0)
        row.toggle.onChange = function(on)
            addon.SetPaused(kind.key, not on)
            page.Refresh()
        end
        kindRows[kind.key] = row
    end
    local gridTop = grid:CreateTexture(nil, "BORDER")
    gridTop:SetColorTexture(Theme.Color("hairline"))
    gridTop:SetHeight(1)
    gridTop:SetPoint("TOPLEFT")
    gridTop:SetWidth(columnWidth)
    local gridTopRight = grid:CreateTexture(nil, "BORDER")
    gridTopRight:SetColorTexture(Theme.Color("hairline"))
    gridTopRight:SetHeight(1)
    gridTopRight:SetPoint("TOPRIGHT")
    gridTopRight:SetWidth(columnWidth)
    grid:SetHeight(4 * 61 + 1)

    local chatLabel = CreateFrame("Frame", nil, page)
    chatLabel:SetHeight(14)
    W.SectionLabel(chatLabel, "Show discoveries in chat"):SetPoint("LEFT")
    local chat = listRow(page, "A chat line for every find")
    W.Hairline(chat, true)
    chat.toggle = W.Toggle(chat)
    chat.toggle:SetPoint("RIGHT", -2, 0)
    chat.toggle.onChange = function(on)
        addon.SetVerbose(on)
    end

    function page.Refresh()
        local allPaused = addon.IsPaused("all")
        head.toggle:SetOn(not allPaused)
        master.outline:SetColor(allPaused and "warning" or "hairline", allPaused and 0.32 or nil)
        local on = 0
        for _, kind in ipairs(addon.CAPTURE_KINDS) do
            local capturing = not addon.IsPaused(kind.key)
            if capturing then
                on = on + 1
            end
            local row = kindRows[kind.key]
            row.toggle:SetOn(capturing)
            row.toggle:SetActive(not allPaused)
            row.title:SetTextColor(Theme.Color((capturing and not allPaused) and "foreground" or "mutedForeground"))
            row:SetAlpha(allPaused and 0.4 or 1)
        end
        local since = addon.PausedSince()
        head.detail:SetText(allPaused and (since and ("Paused since " .. since) or "Paused")
            or string.format("%d of %d kinds on", on, #addon.CAPTURE_KINDS))
        chat.toggle:SetOn(addon.IsVerbose())
    end

    page.height = stack(page, { master, kindsLabel, grid, chatLabel, chat }, 18)
end

-- Character -------------------------------------------------------------------------------

local function buildCharacter(page)
    local upload = W.Card(page)
    local uploadHead = cardHead(upload, "Upload this character", "Gear, talents, professions and stats")
    local icon = W.KindIcon(uploadHead, 36)
    icon:SetKind("character")
    icon:SetPoint("LEFT", 20, 0)
    uploadHead.title:SetPoint("TOPLEFT", 72, -18)
    uploadHead.toggle.onChange = function(on)
        addon.SetArmory(on, { private = false })
        page.Refresh()
    end

    local private = cardSubRow(upload, "Additional private data", "Bags, bank, recipes and completed quests")
    local onlyYou = W.Badge(private, "Only you")
    onlyYou:SetPoint("LEFT", private.title, "RIGHT", 8, 0)
    private.toggle = W.Toggle(private)
    private.toggle:SetPoint("RIGHT", -20, 0)
    private.toggle.onChange = function(on)
        addon.SetCharacterPrivate(on)
        page.Refresh()
    end

    local visibility = cardSubRow(upload, "Manage your Armory visibility")
    local profile = W.CopyField(visibility, "foreverdb.app/profile")
    profile:SetPoint("RIGHT", -20, 0)

    local uploadHeight = stack(upload, { uploadHead, private, visibility })
    upload:SetHeight(uploadHeight)

    local combat = W.Card(page)
    local combatHead = cardHead(combat, "Combat log in dungeons and raids", "Bosses and creature abilities")
    local combatIcon = W.KindIcon(combatHead, 36)
    combatIcon:SetKind("encounters")
    combatIcon:SetPoint("LEFT", 20, 0)
    combatHead.title:SetPoint("TOPLEFT", 72, -18)
    combatHead.toggle.onChange = function(on)
        addon.SetCombatLog(on)
        page.Refresh()
    end
    local everywhere = cardSubRow(combat, "Also in the open world")
    everywhere.toggle = W.Toggle(everywhere)
    everywhere.toggle:SetPoint("RIGHT", -20, 0)
    everywhere.toggle.onChange = function(on)
        addon.SetCombatLogScope(on and "everywhere" or "instances")
    end
    combat:SetHeight(stack(combat, { combatHead, everywhere }))

    function page.Refresh()
        local armory = addon.IsArmoryEnabled()
        uploadHead.toggle:SetOn(armory)
        private.toggle:SetOn(addon.IsCharacterPrivateEnabled())
        private.toggle:SetActive(armory)
        private:SetAlpha(armory and 1 or 0.4)
        visibility:SetAlpha(armory and 1 or 0.4)
        local logging = addon.IsCombatLogEnabled()
        combatHead.toggle:SetOn(logging)
        everywhere.toggle:SetOn(addon.CombatLogScope() == "everywhere")
        everywhere.toggle:SetActive(logging)
        everywhere:SetAlpha(logging and 1 or 0.4)
    end

    page.height = stack(page, { upload, combat }, 24)
end

-- Advanced --------------------------------------------------------------------------------

local function crawlRow(parent, label, command, status)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(66)
    W.Hairline(row)
    local name = W.Text(row, "body", "foreground")
    name:SetPoint("TOPLEFT", 2, -16)
    name:SetText(label)
    local count = W.Text(row, "number", "mutedForeground", "RIGHT")
    count:SetPoint("TOPRIGHT", -126, -16)
    local bar = W.ProgressBar(row)
    bar:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -10)
    bar:SetPoint("RIGHT", -126, 0)
    local start = W.Button(row, "Start", "primary", function()
        addon:HandleSlashCommand(command)
        row.Refresh()
    end)
    start:SetPoint("RIGHT", -2, 0)
    local stop = W.Button(row, "Stop", "secondary", function()
        addon:HandleSlashCommand(command .. " stop")
        row.Refresh()
    end)
    stop:SetPoint("RIGHT", -2, 0)
    function row.Refresh()
        local _, running, requested, total = status()
        requested, total = requested or 0, total or 0
        count:SetText(requested > 0 and string.format("%d / %d", requested, total) or "Not started")
        bar:SetShare(total > 0 and requested / total or 0)
        start:SetShown(not running)
        stop:SetShown(running and true or false)
    end
    return row
end

local function buildAdvanced(page)
    local children = {}

    -- Only approved crawlers have the lists (ForeverCollect_CacheIDs, written by the uploader).
    local crawls = {}
    if addon.QuestCacheStatus and addon.QuestCacheStatus() then
        crawls[#crawls + 1] = crawlRow(page, "Quest cache", "questcache", addon.QuestCacheStatus)
    end
    if addon.ItemCacheStatus and addon.ItemCacheStatus() then
        crawls[#crawls + 1] = crawlRow(page, "Item cache", "itemcache", addon.ItemCacheStatus)
    end
    if #crawls > 0 then
        local crawlLabel = CreateFrame("Frame", nil, page)
        crawlLabel:SetHeight(14)
        W.SectionLabel(crawlLabel, "Crawler"):SetPoint("LEFT")
        children[#children + 1] = crawlLabel
        local list = CreateFrame("Frame", nil, page)
        W.Hairline(list, true)
        list:SetHeight(stack(list, crawls) + 1)
        children[#children + 1] = list
    end

    -- Forever's talents come from the client data; only Classic Era's API is scanned.
    local talents
    if addon.HasClassicTalentAPI and addon.HasClassicTalentAPI() then
        local talentLabel = CreateFrame("Frame", nil, page)
        talentLabel:SetHeight(14)
        W.SectionLabel(talentLabel, "Talent discovery"):SetPoint("LEFT")
        children[#children + 1] = talentLabel
        local className = UnitClass("player")
        talents = listRow(page, (className or "Class") .. " talent trees", "")
        W.Hairline(talents, true)
        local scan = W.Button(talents, "Scan again", "secondary", function()
            addon:HandleSlashCommand("scan")
            page.Refresh()
        end)
        scan:SetPoint("RIGHT", -2, 0)
        children[#children + 1] = talents
    end

    local client = W.Card(page, "sidebar", "sidebar")
    client:SetHeight(64)
    local fields = {}
    local function field(labelText, anchor, x, alignRight)
        local labelString = W.Text(client, "caption", "mutedForeground", alignRight and "RIGHT" or "LEFT")
        local value = W.Text(client, "number", "foreground", alignRight and "RIGHT" or "LEFT")
        if alignRight then
            labelString:SetPoint("TOPRIGHT", -18, -14)
        elseif anchor then
            labelString:SetPoint("TOPLEFT", anchor, "TOPRIGHT", x, 0)
        else
            labelString:SetPoint("TOPLEFT", 18, -14)
        end
        labelString:SetText(labelText)
        value:SetPoint(alignRight and "TOPRIGHT" or "TOPLEFT", labelString, alignRight and "BOTTOMRIGHT" or "BOTTOMLEFT", 0, -4)
        fields[labelText] = value
        return value
    end
    local version = field("Client")
    local season = field("Season", version, 28)
    field("Locale", season, 28)
    field("Addon", nil, nil, true)
    children[#children + 1] = client

    function page.Refresh()
        for _, row in ipairs(crawls) do
            row.Refresh()
        end
        if talents then
            talents.detail:SetText(addon.lastTalentScanAt
                and ("Scanned at " .. date("%H:%M", addon.lastTalentScanAt))
                or "Not scanned yet")
        end
        local catalog = addon.GetLatestCatalog and addon.GetLatestCatalog()
        local versionText, build = GetBuildInfo()
        fields.Client:SetText(string.format("%s.%s", versionText or "?", build or "?"))
        fields.Season:SetText(catalog and catalog.seasonName or "–")
        fields.Locale:SetText(GetLocale())
        fields.Addon:SetText(addonVersion())
    end

    page.height = stack(page, children, 18)
end

-- Window ----------------------------------------------------------------------------------

local PAGE_BUILDERS = { buildSession, buildCapture, buildCharacter, buildAdvanced }

local function layout()
    local page = pages[current]
    window:SetHeight(HEADER_HEIGHT + TABS_HEIGHT + PAD + page.height + PAD + 4)
end

local function refreshHeader()
    local name = UnitName("player")
    local className = UnitClass("player")
    local faction = UnitFactionGroup("player")
    window.name:SetText(name or "")
    window.meta:SetText(string.format("Level %d %s · %s", UnitLevel("player") or 0, className or "", faction or ""))
    if addon.IsPaused("all") then
        window.pill:SetState("Paused", "warning")
    else
        window.pill:SetState("Collecting", "success")
    end
end

local function refresh()
    if not window or not window:IsShown() then
        return
    end
    refreshHeader()
    local page = pages[current]
    if page and page.Refresh then
        page.Refresh()
    end
end
addon.RefreshWindow = refresh

local function selectPage(index)
    current = index
    for pageIndex, page in ipairs(pages) do
        page:SetShown(pageIndex == index)
    end
    layout()
    refresh()
end

local function savePosition()
    local point, _, relativePoint, x, y = window:GetPoint()
    ForeverCollectSettings.window = { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function build()
    window = CreateFrame("Frame", "ForeverCollectWindow", UIParent)
    window:SetWidth(WIDTH)
    window:SetFrameStrata("HIGH")
    window:SetToplevel(true)
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    W.Fill(window, "background")
    W.Outline(window, "border")
    local position = ForeverCollectSettings and ForeverCollectSettings.window
    if position and position.point then
        window:SetPoint(position.point, UIParent, position.relativePoint, position.x, position.y)
    else
        window:SetPoint("CENTER")
    end
    table.insert(UISpecialFrames, "ForeverCollectWindow")

    local header = CreateFrame("Frame", nil, window)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEADER_HEIGHT)
    W.Fill(header, "sidebar")
    W.Hairline(header)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        window:StartMoving()
    end)
    header:SetScript("OnDragStop", function()
        window:StopMovingOrSizing()
        savePosition()
    end)

    local wordmark = W.Text(header, "wordmark", "primary")
    wordmark:SetPoint("LEFT", PAD, 0)
    wordmark:SetText("ForeverCollect")
    local divider = header:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(Theme.Color("border"))
    divider:SetSize(1, 16)
    divider:SetPoint("LEFT", wordmark, "RIGHT", 12, 0)
    window.name = W.Text(header, "body", "foreground")
    window.name:SetPoint("LEFT", divider, "RIGHT", 12, 0)
    window.meta = W.Text(header, "small", "mutedForeground")
    window.meta:SetPoint("LEFT", window.name, "RIGHT", 10, 0)

    local close = CreateFrame("Button", nil, header)
    close:SetSize(28, 28)
    close:SetPoint("RIGHT", -14, 0)
    local closeText = W.Text(close, "title", "mutedForeground", "CENTER")
    closeText:SetPoint("CENTER")
    closeText:SetText("x")
    close:SetScript("OnEnter", function()
        closeText:SetTextColor(Theme.Color("foreground"))
    end)
    close:SetScript("OnLeave", function()
        closeText:SetTextColor(Theme.Color("mutedForeground"))
    end)
    close:SetScript("OnClick", function()
        window:Hide()
    end)
    window.pill = W.StatePill(header)
    window.pill:SetPoint("RIGHT", close, "LEFT", -12, 0)

    tabs = W.Tabs(window, { "Session", "Capture", "Character", "Advanced" }, function(index)
        if #pages == 4 then
            selectPage(index)
        end
    end)
    tabs:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
    tabs:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")

    for index, builder in ipairs(PAGE_BUILDERS) do
        local page = CreateFrame("Frame", nil, window)
        page:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", PAD, -PAD)
        page:SetWidth(CONTENT)
        page:SetHeight(1)
        builder(page)
        page:SetHeight(page.height)
        pages[index] = page
    end

    local sinceRefresh = 0
    window:SetScript("OnUpdate", function(_, elapsed)
        sinceRefresh = sinceRefresh + elapsed
        if sinceRefresh >= REFRESH_SECONDS then
            sinceRefresh = 0
            refresh()
        end
    end)
    window:SetScript("OnShow", refresh)
    window:Hide()
    tabs:Select(current)
end

function addon.OpenWindow(tab)
    if InCombatLockdown() then
        printMessage("The window cannot be opened in combat.")
        return
    end
    if not window then
        build()
    end
    window:Show()
    if tab then
        tabs:Select(tab)
    else
        refresh()
    end
end

function addon.ToggleWindow()
    if window and window:IsShown() then
        window:Hide()
    else
        addon.OpenWindow()
    end
end

-- New captures appear in the session list while it is open.
addon.OnCapture = function()
    if window and window:IsShown() and current == 1 then
        refresh()
    end
end

addon:RegisterCommand("options", function()
    addon.ToggleWindow()
end, "Open the ForeverCollect window")

-- The game's settings keep an entry that opens the window.
local panel = CreateFrame("Frame", "ForeverCollectOptionsPanel")
panel.name = "ForeverCollect"
local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
open:SetSize(200, 26)
open:SetPoint("TOPLEFT", 16, -16)
open:SetText("Open ForeverCollect")
open:SetScript("OnClick", function()
    if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then
        HideUIPanel(SettingsPanel)
    elseif InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() and HideUIPanel then
        HideUIPanel(InterfaceOptionsFrame)
    end
    addon.OpenWindow()
end)
if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
end
