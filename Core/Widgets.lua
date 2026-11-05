local _, addon = ...

-- Small building blocks for the window, the popups and the setup, drawn with colour
-- textures only (no texture files ship with the addon). Layout stays with the callers:
-- every widget returns its frame and leaves the anchoring to them.

local Theme = addon.Theme
local Widgets = {}
addon.Widgets = Widgets

-- Surfaces -------------------------------------------------------------------------------

function Widgets.Fill(frame, color, alpha, layer)
    local texture = frame:CreateTexture(nil, layer or "BACKGROUND")
    texture:SetAllPoints()
    texture:SetColorTexture(Theme.Color(color, alpha))
    return texture
end

-- A one-pixel outline in `color` around `frame`.
function Widgets.Outline(frame, color, alpha)
    local edges = {}
    local function edge(point1, point2, horizontal)
        local line = frame:CreateTexture(nil, "BORDER")
        line:SetColorTexture(Theme.Color(color, alpha))
        line:SetPoint(point1)
        line:SetPoint(point2)
        if horizontal then
            line:SetHeight(1)
        else
            line:SetWidth(1)
        end
        edges[#edges + 1] = line
    end
    edge("TOPLEFT", "TOPRIGHT", true)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    edge("TOPLEFT", "BOTTOMLEFT", false)
    edge("TOPRIGHT", "BOTTOMRIGHT", false)
    function edges.SetColor(_, newColor, newAlpha)
        for _, line in ipairs(edges) do
            line:SetColorTexture(Theme.Color(newColor, newAlpha))
        end
    end
    return edges
end

-- A horizontal hairline under `frame` (or at its top with `atTop`).
function Widgets.Hairline(frame, atTop)
    local line = frame:CreateTexture(nil, "BORDER")
    line:SetColorTexture(Theme.Color("hairline"))
    line:SetHeight(1)
    line:SetPoint(atTop and "TOPLEFT" or "BOTTOMLEFT")
    line:SetPoint(atTop and "TOPRIGHT" or "BOTTOMRIGHT")
    return line
end

function Widgets.Card(parent, color, outline)
    local card = CreateFrame("Frame", nil, parent)
    Widgets.Fill(card, color or "card")
    card.outline = Widgets.Outline(card, outline or "hairline")
    return card
end

-- Text -----------------------------------------------------------------------------------

function Widgets.Text(parent, font, color, justify)
    local text = parent:CreateFontString(nil, "OVERLAY")
    text:SetFontObject(Theme.Font(font or "body"))
    text:SetTextColor(Theme.Color(color or "foreground"))
    text:SetJustifyH(justify or "LEFT")
    text:SetWordWrap(false)
    return text
end

-- Small caps section label in gold, like the game's GameFontNormal headers.
function Widgets.SectionLabel(parent, label)
    local text = Widgets.Text(parent, "caption", "primary")
    text:SetText(string.upper(label))
    if text.SetSpacing then
        text:SetSpacing(0)
    end
    return text
end

-- Round shapes ---------------------------------------------------------------------------

local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- Rounds a texture with the game's circle mask; without mask support it stays square.
local function makeRound(frame, texture)
    if not frame.CreateMaskTexture then
        return
    end
    pcall(function()
        local mask = frame:CreateMaskTexture()
        mask:SetAllPoints(texture)
        mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        texture:AddMaskTexture(mask)
    end)
end

local function dot(frame, size, color)
    local holder = CreateFrame("Frame", nil, frame)
    holder:SetSize(size, size)
    local texture = holder:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints()
    texture:SetColorTexture(Theme.Color(color))
    makeRound(holder, texture)
    holder.texture = texture
    return holder
end
Widgets.Dot = dot

-- Toggle ---------------------------------------------------------------------------------

-- A switch: a track with round ends and a knob. `large` for the head of a card.
-- toggle:SetOn(bool), toggle:SetActive(bool) (disabled when false), toggle.onChange(on).
function Widgets.Toggle(parent, large)
    local width, height = large and 40 or 36, large and 22 or 20
    local knobSize = height - 6
    local toggle = CreateFrame("Button", nil, parent)
    toggle:SetSize(width, height)

    local left = dot(toggle, height, "secondary")
    left:SetPoint("LEFT")
    local right = dot(toggle, height, "secondary")
    right:SetPoint("RIGHT")
    local middle = toggle:CreateTexture(nil, "ARTWORK")
    middle:SetPoint("TOPLEFT", height / 2, 0)
    middle:SetPoint("BOTTOMRIGHT", -height / 2, 0)
    local knob = dot(toggle, knobSize, "mutedForeground")
    knob:SetFrameLevel(toggle:GetFrameLevel() + 2)

    local on, active = false, true
    local function paint()
        local track = on and "primary" or "secondary"
        left.texture:SetColorTexture(Theme.Color(track))
        right.texture:SetColorTexture(Theme.Color(track))
        middle:SetColorTexture(Theme.Color(track))
        knob.texture:SetColorTexture(Theme.Color(on and "primaryForeground" or "mutedForeground"))
        knob:ClearAllPoints()
        knob:SetPoint(on and "RIGHT" or "LEFT", on and -3 or 3, 0)
        toggle:SetAlpha(active and 1 or 0.4)
    end

    function toggle:SetOn(value)
        on = value and true or false
        paint()
    end
    function toggle:IsOn()
        return on
    end
    function toggle:SetActive(value)
        active = value and true or false
        self:EnableMouse(active)
        paint()
    end
    toggle:SetScript("OnClick", function(self)
        if not active then
            return
        end
        self:SetOn(not on)
        if self.onChange then
            self.onChange(on)
        end
    end)
    paint()
    return toggle
end

-- Buttons --------------------------------------------------------------------------------

local BUTTON_STYLES = {
    primary = { fill = "primary", text = "primaryForeground" },
    secondary = { fill = "secondary", text = "foreground", outline = "border" },
    ghost = { text = "mutedForeground" },
}

-- A text button sized to its label; `icon` is an optional texture path shown before it.
function Widgets.Button(parent, label, style, onClick)
    local spec = BUTTON_STYLES[style or "secondary"]
    local button = CreateFrame("Button", nil, parent)
    if spec.fill then
        button.fill = Widgets.Fill(button, spec.fill)
    end
    if spec.outline then
        Widgets.Outline(button, spec.outline)
    end
    local text = Widgets.Text(button, "body", spec.text, "CENTER")
    text:SetPoint("CENTER")
    button.label = text
    function button:SetLabel(value)
        text:SetText(value)
        self:SetSize(math.floor(text:GetStringWidth() + 0.5) + 32, 32)
    end
    button:SetLabel(label)
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.06)
    button:SetScript("OnClick", function()
        if onClick then
            onClick()
        end
    end)
    function button:SetActive(value)
        self:SetEnabled(value and true or false)
        self:SetAlpha(value and 1 or 0.4)
    end
    return button
end

-- A pill: a filter chip (`selected` fills it) or a small badge with an optional icon.
function Widgets.Chip(parent, label, onClick)
    local chip = CreateFrame("Button", nil, parent)
    local fill = Widgets.Fill(chip, "secondary")
    local text = Widgets.Text(chip, "caption", "mutedForeground", "CENTER")
    text:SetPoint("CENTER")
    function chip:SetLabel(value)
        text:SetText(value)
        self:SetSize(math.floor(text:GetStringWidth() + 0.5) + 20, 24)
    end
    function chip:SetSelected(selected)
        fill:SetShown(selected)
        text:SetTextColor(Theme.Color(selected and "foreground" or "mutedForeground"))
    end
    chip:SetLabel(label)
    chip:SetSelected(false)
    chip:SetScript("OnClick", function()
        if onClick then
            onClick()
        end
    end)
    return chip
end

function Widgets.Badge(parent, label)
    local badge = CreateFrame("Frame", nil, parent)
    Widgets.Fill(badge, "secondary")
    local text = Widgets.Text(badge, "caption", "mutedForeground", "CENTER")
    text:SetPoint("CENTER")
    text:SetText(label)
    badge:SetSize(math.floor(text:GetStringWidth() + 0.5) + 16, 20)
    return badge
end

-- A pill with a coloured dot: "Collecting" (success) or "Paused" (warning).
function Widgets.StatePill(parent)
    local pill = CreateFrame("Frame", nil, parent)
    local fill = Widgets.Fill(pill, "success", 0.12)
    local outline = Widgets.Outline(pill, "success", 0.3)
    local mark = dot(pill, 7, "success")
    mark:SetPoint("LEFT", 9, 0)
    local text = Widgets.Text(pill, "caption", "success")
    text:SetPoint("LEFT", mark, "RIGHT", 7, 0)
    function pill:SetState(label, color)
        fill:SetColorTexture(Theme.Color(color, 0.12))
        outline:SetColor(color, 0.3)
        mark.texture:SetColorTexture(Theme.Color(color))
        text:SetTextColor(Theme.Color(color))
        text:SetText(label)
        self:SetSize(math.floor(text:GetStringWidth() + 0.5) + 30, 24)
    end
    pill:SetState("Collecting", "success")
    return pill
end

-- Progress -------------------------------------------------------------------------------

function Widgets.ProgressBar(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(6)
    Widgets.Fill(bar, "secondary")
    local value = bar:CreateTexture(nil, "ARTWORK")
    value:SetPoint("TOPLEFT")
    value:SetPoint("BOTTOMLEFT")
    value:SetColorTexture(Theme.Color("primary"))
    local share = 0
    local function paint()
        value:SetShown(share > 0)
        value:SetWidth(math.max(1, bar:GetWidth() * share))
    end
    function bar:SetShare(newShare)
        share = math.max(0, math.min(1, newShare or 0))
        paint()
    end
    -- the width is only known once the bar is laid out
    bar:SetScript("OnSizeChanged", paint)
    paint()
    return bar
end

-- Copy field -----------------------------------------------------------------------------

-- A read-only field whose text is selected on focus, so Ctrl+C copies it (addons cannot
-- write the clipboard). Typing puts the text back.
function Widgets.CopyField(parent, value)
    local field = CreateFrame("EditBox", nil, parent)
    field:SetAutoFocus(false)
    field:SetFontObject(Theme.Font("number"))
    field:SetTextColor(Theme.Color("primary"))
    field:SetTextInsets(10, 10, 0, 0)
    field:SetHeight(30)
    Widgets.Fill(field, "sidebar")
    Widgets.Outline(field, "input")
    field:SetText(value)
    field:SetCursorPosition(0)
    -- Arial Narrow at 14 px is about 7 px per character
    field:SetWidth(#value * 7 + 24)
    field:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)
    field:SetScript("OnEditFocusLost", function(self)
        self:HighlightText(0, 0)
        self:SetCursorPosition(0)
    end)
    field:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(value)
            self:HighlightText()
        end
    end)
    field:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    field:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    return field
end

-- Tabs -----------------------------------------------------------------------------------

-- A row of text tabs with a gold underline under the selected one. onSelect(index).
function Widgets.Tabs(parent, labels, onSelect)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(42)
    Widgets.Hairline(row)
    local tabs = {}
    local previous
    for index, label in ipairs(labels) do
        local tab = CreateFrame("Button", nil, row)
        local text = Widgets.Text(tab, "body", "mutedForeground", "CENTER")
        text:SetPoint("TOP", 0, -14)
        text:SetText(label)
        tab:SetSize(math.floor(text:GetStringWidth() + 0.5), 42)
        local underline = tab:CreateTexture(nil, "ARTWORK")
        underline:SetColorTexture(Theme.Color("primary"))
        underline:SetHeight(2)
        underline:SetPoint("BOTTOMLEFT")
        underline:SetPoint("BOTTOMRIGHT")
        tab.text, tab.underline = text, underline
        if previous then
            tab:SetPoint("LEFT", previous, "RIGHT", 24, 0)
        else
            tab:SetPoint("LEFT", 20, 0)
        end
        tab:SetScript("OnClick", function()
            row:Select(index)
        end)
        tabs[index] = tab
        previous = tab
    end
    function row:Select(selected)
        for index, tab in ipairs(tabs) do
            local active = index == selected
            tab.text:SetTextColor(Theme.Color(active and "foreground" or "mutedForeground"))
            tab.underline:SetShown(active)
        end
        self.selected = selected
        if onSelect then
            onSelect(selected)
        end
    end
    return row
end

-- Cards ---------------------------------------------------------------------------------

-- A head row of a card: big title, subline and a large toggle.
function Widgets.CardHead(card, title, detail)
    local head = CreateFrame("Frame", nil, card)
    head:SetHeight(76)
    head.title = Widgets.Text(head, "title", "foreground")
    head.title:SetPoint("TOPLEFT", 20, -18)
    head.title:SetText(title)
    head.detail = Widgets.Text(head, "small", "mutedForeground")
    head.detail:SetPoint("TOPLEFT", head.title, "BOTTOMLEFT", 0, -5)
    head.detail:SetText(detail or "")
    head.toggle = Widgets.Toggle(head, true)
    head.toggle:SetPoint("RIGHT", -20, 0)
    return head
end

-- An indented row inside a card (a sub-option), with a hairline above it.
function Widgets.CardSubRow(card, title, detail)
    local row = CreateFrame("Frame", nil, card)
    row:SetHeight(detail and 64 or 50)
    Widgets.Fill(row, "background", 0.4)
    Widgets.Hairline(row, true)
    row.title = Widgets.Text(row, "body", "foreground")
    row.title:SetPoint("TOPLEFT", 72, detail and -14 or -17)
    row.title:SetText(title)
    if detail then
        row.detail = Widgets.Text(row, "small", "mutedForeground")
        row.detail:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -4)
        row.detail:SetText(detail)
    end
    return row
end

-- Stacks children top to bottom with gaps; returns the height used.
function Widgets.Stack(parent, children, gap)
    local y = 0
    for index, child in ipairs(children) do
        if child:IsShown() then
            child:ClearAllPoints()
            child:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
            child:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -y)
            y = y + child:GetHeight() + ((index < #children) and (gap or 0) or 0)
        end
    end
    return y
end

-- Icons ----------------------------------------------------------------------------------

-- Game icons per capture kind for the session list; tinted squares hold them.
Widgets.KIND_ICONS = {
    quests = { texture = "Interface\\GossipFrame\\AvailableQuestIcon", color = "primary" },
    loot = { texture = "Interface\\Icons\\INV_Box_01", color = "azure" },
    gathering = { texture = "Interface\\Icons\\Trade_Herbalism", color = "success" },
    merchants = { texture = "Interface\\GossipFrame\\VendorGossipIcon", color = "secondary" },
    trainers = { texture = "Interface\\GossipFrame\\TrainerGossipIcon", color = "secondary" },
    npcs = { texture = "Interface\\GossipFrame\\GossipGossipIcon", color = "secondary" },
    encounters = { texture = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull", color = "warning" },
    character = { texture = "Interface\\Icons\\INV_Misc_Book_09", color = "primary" },
}

function Widgets.KindIcon(parent, size)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(size or 30, size or 30)
    local fill = Widgets.Fill(holder, "secondary")
    local icon = holder:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("CENTER")
    icon:SetSize((size or 30) - 12, (size or 30) - 12)
    function holder:SetKind(kind)
        local spec = Widgets.KIND_ICONS[kind] or Widgets.KIND_ICONS.npcs
        local r, g, b = Theme.Color(spec.color)
        fill:SetColorTexture(r, g, b, spec.color == "secondary" and 1 or 0.16)
        icon:SetTexture(spec.texture)
        if spec.texture:find("Icons\\", 1, true) then
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        else
            icon:SetTexCoord(0, 1, 0, 1)
        end
    end
    holder:SetKind("npcs")
    return holder
end

-- Notices --------------------------------------------------------------------------------

local notices = {}
local NOTICE_KEYS = {}

-- A small dialog near the top of the screen: icon, wordmark, title, detail and up to two
-- buttons (`secondary` left of `primary`). One per `key`; showing it again updates it.
-- Escape hides it like the game's popups.
function addon.ShowNotice(key, spec)
    local notice = notices[key]
    if not notice then
        local name = "ForeverCollectNotice_" .. key
        notice = CreateFrame("Frame", name, UIParent)
        notice:SetWidth(400)
        notice:SetFrameStrata("DIALOG")
        notice:SetClampedToScreen(true)
        notice:EnableMouse(true)
        Widgets.Fill(notice, "popover")
        Widgets.Outline(notice, "border")
        notice.icon = Widgets.KindIcon(notice, 36)
        notice.icon:SetPoint("TOPLEFT", 22, -22)
        notice.wordmark = Widgets.Text(notice, "caption", "primary")
        notice.wordmark:SetPoint("TOPLEFT", notice.icon, "TOPRIGHT", 14, 0)
        notice.wordmark:SetText("ForeverCollect")
        notice.title = Widgets.Text(notice, "title", "foreground")
        notice.title:SetPoint("TOPLEFT", notice.wordmark, "BOTTOMLEFT", 0, -6)
        notice.title:SetPoint("RIGHT", -22, 0)
        notice.detail = Widgets.Text(notice, "small", "mutedForeground")
        notice.detail:SetPoint("TOPLEFT", notice.title, "BOTTOMLEFT", 0, -5)
        notice.primary = Widgets.Button(notice, "", "primary")
        notice.primary:SetPoint("BOTTOMRIGHT", -20, 20)
        notice.secondary = Widgets.Button(notice, "", "ghost")
        notice.secondary:SetPoint("RIGHT", notice.primary, "LEFT", -8, 0)
        notice:SetHeight(156)
        notices[key] = notice
        NOTICE_KEYS[#NOTICE_KEYS + 1] = key
        table.insert(UISpecialFrames, name)
    end
    notice.icon:SetKind(spec.icon or "character")
    notice.title:SetText(spec.title or "")
    notice.detail:SetText(spec.detail or "")
    local function wire(button, action)
        button:SetShown(action ~= nil)
        if action then
            button:SetLabel(action.label)
            button:SetScript("OnClick", function()
                -- The action runs first, as in the game's own popups; hiding the button
                -- beforehand is the suspected reason a reload from it was refused.
                if action.onClick then
                    action.onClick()
                end
                notice:Hide()
            end)
        end
    end
    wire(notice.primary, spec.primary)
    wire(notice.secondary, spec.secondary)
    -- Several notices stack below each other.
    local offset = 0
    for _, otherKey in ipairs(NOTICE_KEYS) do
        if otherKey == key then
            break
        end
        if notices[otherKey]:IsShown() then
            offset = offset + 168
        end
    end
    notice:ClearAllPoints()
    notice:SetPoint("TOP", UIParent, "TOP", 0, -140 - offset)
    notice:Show()
    return notice
end

function addon.IsNoticeShown(key)
    return notices[key] ~= nil and notices[key]:IsShown()
end
