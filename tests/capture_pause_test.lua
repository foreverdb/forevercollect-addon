-- Run: luajit tests/capture_pause_test.lua (or lua5.1)
local stubFrame = setmetatable({}, { __index = function() return function() end end })
CreateFrame = function() return stubFrame end
InCombatLockdown = function() return false end
UnitName = function() return "Thaldrin" end
time = function() return 1000 end
date = os.date
local popups = {}

local printed = {}
local loginHandlers = {}
local setupPending = false
local addon = {
    PrintMessage = function(message)
        printed[#printed + 1] = message
    end,
    ShowNotice = function(key, spec)
        popups[#popups + 1] = { key = key, spec = spec }
    end,
    IsNoticeShown = function() return false end,
    IsSetupPending = function() return setupPending end,
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
check("login reminds with a notice", #popups == 1 and popups[1].spec.detail == "Loot"
    and popups[1].spec.title == "Some kinds are paused on Thaldrin")
setupPending = true
login()
check("no reminder while the setup is pending", #popups == 0)
setupPending = false

addon:HandleSlashCommand("pause")
check("bare pause stops everything", not addon.IsCapturing("quests"))
check("the pause time is kept", ForeverCollectCharacterSettings.pausedAt == 1000)
login()
check("a full pause names the character and the time", popups[1].spec.title == "Collecting is paused on Thaldrin"
    and popups[1].spec.detail == "Since " .. os.date("%b %d, %H:%M", 1000))
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
login()
popups[1].spec.primary.onClick()
check("Resume clears every pause", ForeverCollectCharacterSettings.paused == nil
    and ForeverCollectCharacterSettings.pausedAt == nil)
