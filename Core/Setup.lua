local _, addon = ...

-- The setup: three steps every character sees once (ForeverCollectCharacterSettings.setupDone),
-- prefilled with its current settings. "Start collecting" applies the choices through the
-- usual setters; "Skip setup" changes nothing and only marks the setup as done. /fc setup
-- opens it again. A pause reminder waits until the setup is closed.

local Theme, W = addon.Theme, addon.Widgets

local WIDTH = 560
local PAD = 32
local CONTENT = WIDTH - 2 * PAD
local LOGIN_DELAY = 2

local frame
local step = 1
local draft
local pending = false
local steps = {}

local function settings()
    return ForeverCollectCharacterSettings or {}
end

function addon.IsSetupPending()
    return pending
end

-- The choices as the character has them now.
local function currentChoices()
    local kinds = {}
    for _, kind in ipairs(addon.CAPTURE_KINDS) do
        kinds[kind.key] = not addon.IsPaused(kind.key)
    end
    local armory = addon.IsArmoryEnabled()
    return {
        kinds = kinds,
        armory = armory,
        public = settings().publicChoice == true,
        private = armory and addon.IsCharacterPrivateEnabled() or false,
        combatLog = addon.IsCombatLogEnabled(),
        everywhere = addon.CombatLogScope() == "everywhere",
    }
end

-- Applies the draft through the setters, only where it differs, so the chat gets one line
-- per real change.
local function apply(choices)
    local before = currentChoices()
    if addon.IsPaused("all") then
        addon.SetPaused("all", false)
    end
    for _, kind in ipairs(addon.CAPTURE_KINDS) do
        local wanted = choices.kinds[kind.key]
        if wanted ~= (not addon.IsPaused(kind.key)) then
            addon.SetPaused(kind.key, not wanted)
        end
    end
    if choices.armory ~= before.armory then
        addon.SetArmory(choices.armory, { private = choices.private })
    elseif choices.armory and choices.private ~= before.private then
        addon.SetCharacterPrivate(choices.private)
    end
    -- Only a starting value: the server uses it when it first creates the character.
    ForeverCollectCharacterSettings.publicChoice = choices.armory and choices.public or nil
    if choices.combatLog ~= before.combatLog then
        addon.SetCombatLog(choices.combatLog)
    end
    if choices.combatLog and choices.everywhere ~= before.everywhere then
        addon.SetCombatLogScope(choices.everywhere and "everywhere" or "instances")
    end
end
addon.ApplySetup = apply

local function finish(applyChoices)
    if applyChoices then
        apply(draft)
    end
    ForeverCollectCharacterSettings.setupDone = true
    pending = false
    frame:Hide()
    if addon.RefreshWindow then
        addon.RefreshWindow()
    end
    if addon.RemindPaused then
        addon.RemindPaused()
    end
end

-- Chips ------------------------------------------------------------------------------------

-- A kind chip: gold outline and check when on, a quiet outline when off.
local function kindChip(parent, label, onClick)
    local chip = CreateFrame("Button", nil, parent)
    local fill = W.Fill(chip, "primary", 0.12)
    local outline = W.Outline(chip, "primary", 0.4)
    local check = chip:CreateTexture(nil, "ARTWORK")
    check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    check:SetSize(14, 14)
    check:SetPoint("LEFT", 10, 0)
    local text = W.Text(chip, "body", "foreground")
    text:SetPoint("LEFT", check, "RIGHT", 6, 0)
    text:SetText(label)
    chip:SetSize(math.floor(text:GetStringWidth() + 0.5) + 44, 34)
    function chip:SetOn(on)
        fill:SetShown(on)
        outline:SetColor(on and "primary" or "hairline", on and 0.4 or nil)
        check:SetShown(on)
        text:SetTextColor(Theme.Color(on and "foreground" or "mutedForeground"))
    end
    chip:SetScript("OnClick", onClick)
    return chip
end

-- Lays chips out in lines of `width`; returns the height used.
local function wrap(parent, chips, width, gap)
    local x, y, lineHeight = 0, 0, 0
    for _, chip in ipairs(chips) do
        local chipWidth, chipHeight = chip:GetWidth(), chip:GetHeight()
        if x > 0 and x + chipWidth > width then
            x, y = 0, y + lineHeight + gap
        end
        chip:ClearAllPoints()
        chip:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
        x = x + chipWidth + gap
        lineHeight = math.max(lineHeight, chipHeight)
    end
    return y + lineHeight
end

-- Steps ------------------------------------------------------------------------------------

local function intro(page, heading, lead)
    local title = W.Text(page, "heading", "primary")
    title:SetText(heading)
    local text = W.Text(page, "body", "mutedForeground")
    text:SetText(lead)
    local block = CreateFrame("Frame", nil, page)
    title:SetParent(block)
    text:SetParent(block)
    title:SetPoint("TOPLEFT")
    text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    block:SetHeight(36 + 10 + 18)
    page.heading = title
    return block
end

local function buildWelcome(page)
    local head = intro(page, "Welcome", "Your adventures help map Azeroth for everyone.")
    local label = CreateFrame("Frame", nil, page)
    label:SetHeight(14)
    W.SectionLabel(label, "Collect on this character"):SetPoint("LEFT")
    local holder = CreateFrame("Frame", nil, page)
    local chips = {}
    for _, kind in ipairs(addon.CAPTURE_KINDS) do
        local chip
        chip = kindChip(holder, kind.label, function()
            draft.kinds[kind.key] = not draft.kinds[kind.key]
            chip:SetOn(draft.kinds[kind.key])
        end)
        chip.key = kind.key
        chips[#chips + 1] = chip
    end
    holder:SetHeight(wrap(holder, chips, CONTENT, 8))
    function page.Refresh()
        page.heading:SetText("Welcome, " .. (UnitName("player") or ""))
        for _, chip in ipairs(chips) do
            chip:SetOn(draft.kinds[chip.key])
        end
    end
    page.height = W.Stack(page, { head, label, holder }, 28)
end

local function buildCharacter(page)
    local head = intro(page, "Your character, your call", "Upload as much or as little as you like.")

    local upload = W.Card(page)
    local uploadHead = W.CardHead(upload, "Upload this character", "Gear, talents, professions and stats")
    local icon = W.KindIcon(uploadHead, 36)
    icon:SetKind("character")
    icon:SetPoint("LEFT", 20, 0)
    uploadHead.title:SetPoint("TOPLEFT", 72, -18)
    local public = W.CardSubRow(upload, "Show on the public Armory")
    local everyone = W.Badge(public, "Everyone")
    everyone:SetPoint("LEFT", public.title, "RIGHT", 8, 0)
    public.toggle = W.Toggle(public)
    public.toggle:SetPoint("RIGHT", -20, 0)
    local private = W.CardSubRow(upload, "Additional private data", "Bags, bank, recipes and completed quests")
    local onlyYou = W.Badge(private, "Only you")
    onlyYou:SetPoint("LEFT", private.title, "RIGHT", 8, 0)
    private.toggle = W.Toggle(private)
    private.toggle:SetPoint("RIGHT", -20, 0)
    upload:SetHeight(W.Stack(upload, { uploadHead, public, private }))

    local combat = W.Card(page)
    local combatHead = W.CardHead(combat, "Combat log in dungeons and raids", "Bosses and creature abilities")
    local combatIcon = W.KindIcon(combatHead, 36)
    combatIcon:SetKind("encounters")
    combatIcon:SetPoint("LEFT", 20, 0)
    combatHead.title:SetPoint("TOPLEFT", 72, -18)
    local everywhere = W.CardSubRow(combat, "Also in the open world")
    everywhere.toggle = W.Toggle(everywhere)
    everywhere.toggle:SetPoint("RIGHT", -20, 0)
    combat:SetHeight(W.Stack(combat, { combatHead, everywhere }))

    function page.Refresh()
        uploadHead.toggle:SetOn(draft.armory)
        public.toggle:SetOn(draft.public)
        private.toggle:SetOn(draft.private)
        for _, row in ipairs({ public, private }) do
            row.toggle:SetActive(draft.armory)
            row:SetAlpha(draft.armory and 1 or 0.4)
        end
        combatHead.toggle:SetOn(draft.combatLog)
        everywhere.toggle:SetOn(draft.everywhere)
        everywhere.toggle:SetActive(draft.combatLog)
        everywhere:SetAlpha(draft.combatLog and 1 or 0.4)
    end
    local function bind(toggle, field)
        toggle.onChange = function(on)
            draft[field] = on
            page.Refresh()
        end
    end
    bind(uploadHead.toggle, "armory")
    bind(public.toggle, "public")
    bind(private.toggle, "private")
    bind(combatHead.toggle, "combatLog")
    bind(everywhere.toggle, "everywhere")

    page.height = W.Stack(page, { head, upload, combat }, 16)
end

local function buildReady(page)
    local head = intro(page, "Your discoveries start now", "One more thing: the Uploader brings them to ForeverDB.")
    local summary = CreateFrame("Frame", nil, page)
    W.Hairline(summary, true)
    local lines = {}
    for index = 1, 4 do
        local line = CreateFrame("Frame", nil, summary)
        line:SetHeight(43)
        W.Hairline(line)
        local check = line:CreateTexture(nil, "ARTWORK")
        check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        check:SetSize(16, 16)
        check:SetPoint("LEFT", 2, 0)
        line.text = W.Text(line, "body", "foreground")
        line.text:SetPoint("LEFT", check, "RIGHT", 12, 0)
        lines[index] = line
    end

    local uploader = W.Card(page, "card", "primary")
    uploader.outline:SetColor("primary", 0.28)
    uploader:SetHeight(70)
    local icon = W.KindIcon(uploader, 36)
    icon:SetKind("character")
    icon:SetPoint("LEFT", 18, 0)
    local name = W.Text(uploader, "title", "foreground")
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 16, 2)
    name:SetText("ForeverDB Uploader")
    local link = W.CopyField(uploader, "foreverdb.app/uploader")
    link:SetPoint("RIGHT", -18, 0)

    function page.Refresh()
        local texts = {}
        local on = 0
        for _, kind in ipairs(addon.CAPTURE_KINDS) do
            if draft.kinds[kind.key] then
                on = on + 1
            end
        end
        texts[#texts + 1] = on == #addon.CAPTURE_KINDS and ("Collecting all " .. on .. " kinds")
            or string.format("Collecting %d of %d kinds", on, #addon.CAPTURE_KINDS)
        if draft.armory then
            local name = UnitName("player") or "this character"
            texts[#texts + 1] = draft.public and ("Upload " .. name .. ", shown on the public Armory") or ("Upload " .. name)
            if draft.private then
                texts[#texts + 1] = "Additional private data, only for you"
            end
        end
        if draft.combatLog then
            texts[#texts + 1] = draft.everywhere and "Combat log everywhere" or "Combat log in dungeons and raids"
        end
        for index, line in ipairs(lines) do
            line:SetShown(texts[index] ~= nil)
            line.text:SetText(texts[index] or "")
        end
        summary:SetHeight(W.Stack(summary, lines) + 1)
        page.height = W.Stack(page, { head, summary, uploader }, 24)
        page:SetHeight(page.height)
    end
    page.height = 0
end

-- Frame ------------------------------------------------------------------------------------

local BUILDERS = { buildWelcome, buildCharacter, buildReady }

local function show(index)
    step = index
    for stepIndex, page in ipairs(steps) do
        page:SetShown(stepIndex == index)
        frame.bars[stepIndex]:SetColorTexture(Theme.Color(stepIndex <= index and "primary" or "secondary"))
    end
    local page = steps[index]
    page.Refresh()
    page:SetHeight(page.height)
    frame:SetHeight(58 + 36 + page.height + 32 + 66)
    frame.skip:SetShown(index < #steps)
    frame.back:SetShown(index > 1)
    frame.next:SetLabel(index < #steps and "Next" or "Start collecting")
end

local function build()
    frame = CreateFrame("Frame", "ForeverCollectSetup", UIParent)
    frame:SetWidth(WIDTH)
    frame:SetPoint("CENTER", 0, 40)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    W.Fill(frame, "background")
    W.Outline(frame, "border")
    table.insert(UISpecialFrames, "ForeverCollectSetup")

    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(58)
    W.Fill(header, "sidebar")
    W.Hairline(header)
    local wordmark = W.Text(header, "wordmark", "primary")
    wordmark:SetPoint("LEFT", 24, 0)
    wordmark:SetText("ForeverCollect")
    frame.bars = {}
    for index = 3, 1, -1 do
        local bar = header:CreateTexture(nil, "ARTWORK")
        bar:SetSize(28, 4)
        bar:SetPoint("RIGHT", -24 - (3 - index) * 34, 0)
        frame.bars[index] = bar
    end

    for index, builder in ipairs(BUILDERS) do
        local page = CreateFrame("Frame", nil, frame)
        page:SetPoint("TOPLEFT", header, "BOTTOMLEFT", PAD, -36)
        page:SetWidth(CONTENT)
        builder(page)
        steps[index] = page
    end

    local footer = CreateFrame("Frame", nil, frame)
    footer:SetPoint("BOTTOMLEFT")
    footer:SetPoint("BOTTOMRIGHT")
    footer:SetHeight(66)
    W.Hairline(footer, true)
    frame.skip = W.Button(footer, "Skip setup", "ghost", function()
        finish(false)
    end)
    frame.skip:SetPoint("LEFT", 12, 0)
    frame.next = W.Button(footer, "Next", "primary", function()
        if step < #steps then
            show(step + 1)
        else
            finish(true)
        end
    end)
    frame.next:SetPoint("RIGHT", -24, 0)
    frame.back = W.Button(footer, "Back", "ghost", function()
        show(step - 1)
    end)
    frame.back:SetPoint("RIGHT", frame.next, "LEFT", -8, 0)

    -- Closed with Escape: nothing is applied and the setup comes back on the next login.
    frame:SetScript("OnHide", function()
        if pending then
            pending = false
            if addon.RemindPaused then
                addon.RemindPaused()
            end
        end
    end)
    frame:Hide()
end

function addon.OpenSetup()
    if InCombatLockdown() then
        addon.PrintMessage("The setup cannot be opened in combat.")
        return
    end
    if not frame then
        build()
    end
    draft = currentChoices()
    pending = true
    frame:Show()
    show(1)
end

addon:RegisterCommand("setup", function()
    addon.OpenSetup()
end, "Open the setup again")

-- Every character sees the setup once; after combat if it was in combat at login.
local function openIfDue()
    if settings().setupDone or (frame and frame:IsShown()) then
        return
    end
    if InCombatLockdown() then
        addon:RegisterEvent("PLAYER_REGEN_ENABLED", function()
            if not settings().setupDone and not (frame and frame:IsShown()) and not InCombatLockdown() then
                addon.OpenSetup()
            end
        end)
        return
    end
    addon.OpenSetup()
end

addon:RegisterEvent("PLAYER_LOGIN", function()
    if settings().setupDone then
        return
    end
    -- the pause reminder waits for the setup
    pending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(LOGIN_DELAY, openIfDue)
    else
        openIfDue()
    end
end)
