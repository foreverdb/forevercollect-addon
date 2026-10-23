local _, addon = ...

local printMessage = addon.PrintMessage

-- Settings page under Options -> AddOns, also opened by a bare /fc. It is a plain canvas
-- frame: the canvas API is the same on every Classic build, the vertical-layout helpers
-- are not. The values are read again on every show, so changes made through /fc commands
-- appear here too. The page holds the settings, the actions behind the /fc commands, the
-- catalog status and what was captured since the last save; it scrolls when the window
-- is too small for all of it.

local PADDING = 16
local TEXT_WIDTH = 560
local STATUS_REFRESH_SECONDS = 1

local panel = CreateFrame("Frame", "ForeverCollectOptionsPanel")
panel.name = "ForeverCollect"

local scroll = CreateFrame("ScrollFrame", "ForeverCollectOptionsScroll", panel, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 0, -4)
scroll:SetPoint("BOTTOMRIGHT", -28, 4)
-- Every control lives on this frame; the page itself only holds the scroll frame.
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(TEXT_WIDTH + 2 * PADDING, 1)
scroll:SetScrollChild(content)

local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", PADDING, -PADDING)
title:SetText("ForeverCollect")

local subtitle = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
subtitle:SetWidth(TEXT_WIDTH)
subtitle:SetJustifyH("LEFT")
subtitle:SetText("Collects game data for ForeverDB. The ForeverDB Uploader sends it after you log out.")

local function createCheckbox(anchor, label, description, onClick)
    local checkbox = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    checkbox:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -16)
    local text = checkbox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    text:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
    text:SetText(label)
    local hint = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", checkbox, "BOTTOMLEFT", 30, -2)
    hint:SetWidth(TEXT_WIDTH - 30)
    hint:SetJustifyH("LEFT")
    hint:SetText(description)
    checkbox:SetScript("OnClick", function(self)
        onClick(self:GetChecked() and true or false)
    end)
    -- The next control anchors below the hint, but at the checkbox's left edge.
    local bottom = CreateFrame("Frame", nil, content)
    bottom:SetSize(1, 1)
    bottom:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", -30, 0)
    return checkbox, bottom
end

local verbose, afterVerbose = createCheckbox(
    subtitle,
    "Capture notices",
    "Print a chat line for every capture (quest, loot, merchant, trainer, ...). Same as /fc verbose.",
    function(enabled)
        addon.SetVerbose(enabled)
    end
)

local armory, afterArmory = createCheckbox(
    afterVerbose,
    "Armory (public profile of this character)",
    "Uploads this character (name, realm, gear, talents, professions, stats) for a public profile on ForeverDB. "
        .. "Set per character; turning it off removes this character's stored snapshots. Same as /fc armory on/off.",
    function(enabled)
        addon.SetArmory(enabled)
    end
)

local combatLog, afterCombatLog = createCheckbox(
    afterArmory,
    "Combat log in dungeons and raids",
    "Turns on the game's combat log inside instances, so the uploader can tell which creatures are an encounter's bosses "
        .. "(their IDs are hidden from addons there). Only logging started by ForeverCollect is stopped again. "
        .. "Set per character. Same as /fc combatlog on/off.",
    function(enabled)
        addon.SetCombatLog(enabled)
    end
)

local function createHeading(anchor, text)
    local heading = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -24)
    heading:SetText(text)
    return heading
end

local function createButton(text, width, onClick)
    local button = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    button:SetSize(width, 24)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

local function createNote(anchor, offset)
    local note = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offset or -6)
    note:SetWidth(TEXT_WIDTH)
    note:SetJustifyH("LEFT")
    return note
end

local refreshStatus

-- Runs a /fc command, so the page and the chat do exactly the same.
local function runCommand(command)
    addon:HandleSlashCommand(command)
    refreshStatus()
end

-- Pausing: one master switch, then one box per kind (checked = captured). The kind
-- boxes are disabled while everything is paused, since their state then has no effect.
local captureHeading = createHeading(afterCombatLog, "Capture (this character)")
local refreshCapture

local pauseAll, afterCapture = createCheckbox(
    captureHeading,
    "Pause all capture",
    "Stops every automatic capture on this character until resumed; login and /reload remind you while it is on. "
        .. "Same as /fc pause and /fc resume.",
    function(enabled)
        addon.SetPaused("all", enabled)
        refreshCapture()
    end
)

local kindBoxes = {}
for _, kind in ipairs(addon.CAPTURE_KINDS) do
    local checkbox
    checkbox, afterCapture = createCheckbox(
        afterCapture,
        kind.label,
        kind.hint .. " Same as /fc pause " .. kind.key .. " and /fc resume " .. kind.key .. ".",
        function(enabled)
            addon.SetPaused(kind.key, not enabled)
        end
    )
    kindBoxes[kind.key] = checkbox
end

refreshCapture = function()
    local allPaused = addon.IsPaused("all")
    pauseAll:SetChecked(allPaused)
    for key, checkbox in pairs(kindBoxes) do
        checkbox:SetChecked(not addon.IsPaused(key))
        checkbox:SetEnabled(not allPaused)
    end
end

local saveHeading = createHeading(afterCapture, "Save")
local saveButton = createButton("Save now (reload UI)", 180, function()
    addon.Save(false)
end)
saveButton:SetPoint("TOPLEFT", saveHeading, "BOTTOMLEFT", 0, -10)

local saveHint = createNote(saveButton)
saveHint:SetText("The game writes addon data only on logout or /reload. Same as /fc save.")

local scanHeading = createHeading(saveHint, "Talents")
local scanButton = createButton("Scan talents", 180, function()
    runCommand("scan")
end)
scanButton:SetPoint("TOPLEFT", scanHeading, "BOTTOMLEFT", 0, -10)

local scanHint = createNote(scanButton)
scanHint:SetText("Captures the talents of your class; happens on every login as well. Same as /fc scan.")

-- Start/Stop/Reset plus progress for one of the cache crawls (Core/CacheCrawl.lua).
local function createCrawlSection(anchor, title, command, units, status, hint)
    local heading = createHeading(anchor, title)
    local start = createButton("Start", 100, function()
        runCommand(command .. " start")
    end)
    start:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -10)
    local stop = createButton("Stop", 100, function()
        runCommand(command .. " stop")
    end)
    stop:SetPoint("LEFT", start, "RIGHT", 8, 0)
    local reset = createButton("Reset", 100, function()
        runCommand(command .. " reset")
    end)
    reset:SetPoint("LEFT", stop, "RIGHT", 8, 0)

    local statusNote = createNote(start)
    local hintNote = createNote(statusNote, -4)
    hintNote:SetText(hint)

    local section = { last = hintNote }
    function section.refresh()
        local text, running = status()
        local supported = text ~= nil
        statusNote:SetText(text or ("This client cannot query " .. units .. " from the server."))
        start:SetEnabled(supported and not running)
        stop:SetEnabled(supported and running)
        reset:SetEnabled(supported)
    end
    return section
end

local questCache = createCrawlSection(scanHint, "Quest cache", "questcache", "quests", addon.QuestCacheStatus,
    "Asks the server for every quest of this client so its quest cache holds them all; "
        .. "continues after a reload. Same as /fc questcache (stop, reset).")
local itemCache = createCrawlSection(questCache.last, "Item cache", "itemcache", "items", addon.ItemCacheStatus,
    "Asks the server for every item this client has no data for, so DBCache.bin holds them; "
        .. "continues after a reload. Same as /fc itemcache (stop, reset).")

local statusHeading = createHeading(itemCache.last, "Status")
local statusText = createNote(statusHeading, -10)

local listTitle = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
listTitle:SetPoint("TOPLEFT", statusText, "BOTTOMLEFT", 0, -20)

local list = CreateFrame("ScrollingMessageFrame", nil, content)
list:SetPoint("TOPLEFT", listTitle, "BOTTOMLEFT", 0, -6)
list:SetSize(TEXT_WIDTH, 260)
list:SetFontObject(GameFontHighlightSmall)
list:SetJustifyH("LEFT")
list:SetFading(false)
list:SetMaxLines(500)
list:EnableMouseWheel(true)
list:SetScript("OnMouseWheel", function(self, delta)
    if delta > 0 then
        self:ScrollUp()
    else
        self:ScrollDown()
    end
end)
local listBackground = list:CreateTexture(nil, "BACKGROUND")
listBackground:SetPoint("TOPLEFT", -4, 4)
listBackground:SetPoint("BOTTOMRIGHT", 4, -4)
listBackground:SetColorTexture(0, 0, 0, 0.3)

local function updateListTitle()
    local count, seconds = addon.UnsavedCaptures()
    listTitle:SetText(string.format(
        "Unsaved captures: %d (%d min since the last save)",
        count,
        math.floor(seconds / 60)
    ))
end

local function addCaptureLine(entry)
    list:AddMessage(date("%H:%M", entry.at) .. "  " .. tostring(entry.text))
end

local function fillList()
    list:Clear()
    local captures = addon.GetCaptures()
    if #captures == 0 then
        list:AddMessage("Nothing captured since the last save.")
    end
    for _, entry in ipairs(captures) do
        addCaptureLine(entry)
    end
    updateListTitle()
end

addon.OnCapture = function(entry)
    if not panel:IsVisible() then
        return
    end
    if #addon.GetCaptures() == 1 then
        fillList()
    else
        addCaptureLine(entry)
        updateListTitle()
    end
end

refreshStatus = function()
    local lines = addon.StatusLines and addon.StatusLines() or {}
    -- The last line is the unsaved-captures count, which the list title shows.
    lines[#lines] = nil
    statusText:SetText(table.concat(lines, "\n"))

    questCache.refresh()
    itemCache.refresh()
    -- /fc pause and the login popup change the pause state while the page is open.
    refreshCapture()
    updateListTitle()
    -- The scroll range follows the laid-out text; positions are unknown before the first draw.
    local top, bottom = content:GetTop(), list:GetBottom()
    if top and bottom then
        content:SetHeight(top - bottom + PADDING)
    end
end

-- The quest cache counts up while it runs; follow it while the page is open.
local sinceRefresh = 0
panel:SetScript("OnUpdate", function(_, elapsed)
    sinceRefresh = sinceRefresh + elapsed
    if sinceRefresh >= STATUS_REFRESH_SECONDS then
        sinceRefresh = 0
        refreshStatus()
    end
end)

panel:SetScript("OnShow", function()
    verbose:SetChecked(addon.IsVerbose())
    armory:SetChecked(addon.IsArmoryEnabled())
    combatLog:SetChecked(addon.IsCombatLogEnabled())
    fillList()
    refreshStatus()
end)


local category
if Settings and Settings.RegisterCanvasLayoutCategory then
    category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
end

addon:RegisterCommand("options", function()
    if InCombatLockdown() then
        printMessage("The options cannot be opened in combat.")
        return
    end
    if category then
        Settings.OpenToCategory(category:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        -- The legacy frame only scrolls to an addon page on the second call.
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end, "Open the settings page")
