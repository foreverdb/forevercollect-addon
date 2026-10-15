local _, addon = ...

local printMessage = addon.PrintMessage

-- Settings page under Options -> AddOns. It is a plain canvas frame: the canvas API is
-- the same on every Classic build, the vertical-layout helpers are not. The values are
-- read again on every show, so changes made through /fc commands appear here too.
-- Below the settings, the page lists what was captured since the last save.

local PADDING = 16
local TEXT_WIDTH = 560

local panel = CreateFrame("Frame", "ForeverCollectOptionsPanel")
panel.name = "ForeverCollect"

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", PADDING, -PADDING)
title:SetText("ForeverCollect")

local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
subtitle:SetWidth(TEXT_WIDTH)
subtitle:SetJustifyH("LEFT")
subtitle:SetText("Collects game data for ForeverDB. The ForeverDB Uploader sends it after you log out.")

local function createCheckbox(anchor, label, description, onClick)
    local checkbox = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    checkbox:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -16)
    local text = checkbox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    text:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
    text:SetText(label)
    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", checkbox, "BOTTOMLEFT", 30, -2)
    hint:SetWidth(TEXT_WIDTH - 30)
    hint:SetJustifyH("LEFT")
    hint:SetText(description)
    checkbox:SetScript("OnClick", function(self)
        onClick(self:GetChecked() and true or false)
    end)
    -- The next control anchors below the hint, but at the checkbox's left edge.
    local bottom = CreateFrame("Frame", nil, panel)
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
    "Armory (public character profile)",
    "Uploads your character (name, realm, gear, talents, professions, stats) for a public profile on ForeverDB. "
        .. "Turning it off removes every stored snapshot. Same as /fc armory on/off.",
    function(enabled)
        addon.SetArmory(enabled)
    end
)

local saveButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
saveButton:SetPoint("TOPLEFT", afterArmory, "BOTTOMLEFT", 0, -20)
saveButton:SetSize(180, 24)
saveButton:SetText("Save now (reload UI)")
saveButton:SetScript("OnClick", function()
    addon.Save(false)
end)

local saveHint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
saveHint:SetPoint("TOPLEFT", saveButton, "BOTTOMLEFT", 0, -6)
saveHint:SetWidth(TEXT_WIDTH)
saveHint:SetJustifyH("LEFT")
saveHint:SetText("The game writes addon data only on logout or /reload. Same as /fc save.")

local listTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
listTitle:SetPoint("TOPLEFT", saveHint, "BOTTOMLEFT", 0, -20)

local list = CreateFrame("ScrollingMessageFrame", nil, panel)
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

panel:SetScript("OnShow", function()
    verbose:SetChecked(addon.IsVerbose())
    armory:SetChecked(addon.IsArmoryEnabled())
    fillList()
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
