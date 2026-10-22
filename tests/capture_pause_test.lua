-- Run: luajit tests/capture_pause_test.lua (or lua5.1)
local stubFrame = setmetatable({}, { __index = function() return function() end end })
CreateFrame = function() return stubFrame end
StaticPopupDialogs = {}
InCombatLockdown = function() return false end
StaticPopup_Visible = function() return false end
local popups = {}
StaticPopup_Show = function(name, text)
    popups[#popups + 1] = { name = name, text = text }
end

local printed = {}
local loginHandlers = {}
local addon = {
    PrintMessage = function(message)
        printed[#printed + 1] = message
    end,
}

local function load(path)
    local chunk = assert(loadfile(path))
    chunk("ForeverCollect", addon)
end
load("Core/Registry.lua")
local registerEvent = addon.RegisterEvent
function addon:RegisterEvent(event, handler)
    if event == "PLAYER_LOGIN" then
        loginHandlers[#loginHandlers + 1] = handler
    else
        registerEvent(self, event, handler)
    end
end
load("Core/Pause.lua")

local function check(name, condition)
    if not condition then
        error("FAIL: " .. name, 2)
    end
    print("ok - " .. name)
end

local function login()
    popups = {}
    for _, handler in ipairs(loginHandlers) do
        handler()
    end
end

ForeverCollectCharacterSettings = nil
check("captures without settings", addon.IsCapturing("loot"))

ForeverCollectCharacterSettings = {}
check("captures by default", addon.IsCapturing("loot") and addon.IsCapturing("quests"))
login()
check("no reminder while nothing is paused", #popups == 0)

addon:HandleSlashCommand("pause loot")
check("a paused kind stops", not addon.IsCapturing("loot"))
check("other kinds keep capturing", addon.IsCapturing("gathering"))
check("status lists the paused kind", addon.PausedLabels()[1] == "Loot")
login()
check("login reminds with a popup", #popups == 1 and popups[1].text == "Loot")

addon:HandleSlashCommand("pause")
check("bare pause stops everything", not addon.IsCapturing("quests"))
check("everything is reported", addon.PausedLabels()[1] == "everything")

addon:HandleSlashCommand("resume loot")
check("a kind resume does not override pause all", not addon.IsCapturing("loot"))

addon:HandleSlashCommand("pause trainers")
addon:HandleSlashCommand("resume")
check("bare resume clears every pause", addon.IsCapturing("loot") and addon.IsCapturing("trainers"))
check("empty pause table is removed", ForeverCollectCharacterSettings.paused == nil)

addon:HandleSlashCommand("pause foo")
check("unknown kind is reported", string.find(printed[#printed], "Unknown capture kind", 1, true) ~= nil)
check("unknown kind pauses nothing", ForeverCollectCharacterSettings.paused == nil)

addon:HandleSlashCommand("pause gathering")
StaticPopupDialogs.FOREVERCOLLECT_CAPTURE_PAUSED.OnAccept()
check("popup resume clears every pause", ForeverCollectCharacterSettings.paused == nil)
