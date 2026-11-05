-- Run: luajit tests/window_smoke_test.lua (or lua5.1)
-- Builds the window, the popups and the setup against a stubbed frame API and walks every
-- tab and step once, so typos and nil calls show up before anyone logs in.

local function check(name, condition)
    if not condition then
        error("FAIL: " .. name, 2)
    end
    print("ok - " .. name)
end

-- A widget stub: unknown methods do nothing and return nil; the few whose results the code
-- computes with return plausible values. Scripts are kept so tests can click.
local widgetMethods = {}
local function newWidget(kind)
    local widget = { kind = kind, scripts = {}, shown = true, width = 100, height = 20, text = "" }
    return setmetatable(widget, { __index = function(_, key)
        return widgetMethods[key] or function() end
    end })
end
function widgetMethods.CreateTexture(self) return newWidget("Texture") end
function widgetMethods.CreateMaskTexture(self) return newWidget("MaskTexture") end
function widgetMethods.CreateFontString(self) return newWidget("FontString") end
function widgetMethods.SetScript(self, name, handler) self.scripts[name] = handler end
function widgetMethods.GetScript(self, name) return self.scripts[name] end
function widgetMethods.SetText(self, text) self.text = text end
function widgetMethods.GetText(self) return self.text end
function widgetMethods.GetStringWidth(self) return #tostring(self.text or "") * 7 end
function widgetMethods.SetWidth(self, width) self.width = width end
function widgetMethods.SetHeight(self, height) self.height = height end
function widgetMethods.SetSize(self, width, height) self.width, self.height = width, height end
function widgetMethods.GetWidth(self) return self.width end
function widgetMethods.GetHeight(self) return self.height end
function widgetMethods.GetFrameLevel() return 1 end
function widgetMethods.Show(self) self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
function widgetMethods.Hide(self) self.shown = false end
function widgetMethods.SetShown(self, shown) self.shown = shown and true or false end
function widgetMethods.IsShown(self) return self.shown end
function widgetMethods.IsVisible(self) return self.shown end
function widgetMethods.GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function widgetMethods.GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
function widgetMethods.Click(self) if self.scripts.OnClick then self.scripts.OnClick(self, "LeftButton") end end

local created = {}
CreateFrame = function(kind, name)
    local frame = newWidget(kind)
    created[#created + 1] = frame
    if name then
        _G[name] = frame
    end
    return frame
end
CreateFont = function() return newWidget("Font") end
UIParent = newWidget("Frame")
GameFontNormal = newWidget("Font")
NumberFontNormal = newWidget("Font")
UISpecialFrames = {}
StaticPopupDialogs = {}
StaticPopup_Show = function() end
StaticPopup_Visible = function() return false end
InCombatLockdown = function() return false end
UnitAffectingCombat = function() return false end
UnitCastingInfo = function() return nil end
UnitChannelInfo = function() return nil end
UnitIsDeadOrGhost = function() return false end
local reloads = 0
C_UI = { Reload = function() reloads = reloads + 1 end }
C_Timer = { After = function(_, callback) callback() end, NewTicker = function() return { Cancel = function() end } end }
time = function() return 100000 end
date = os.date
GetBuildInfo = function() return "1.15.9", "70003", "Nov 1 2026", 11509 end
GetLocale = function() return "enUS" end
UnitName = function() return "Thaldrin" end
UnitClass = function() return "Paladin", "PALADIN", 2 end
UnitLevel = function() return 34 end
UnitFactionGroup = function() return "Alliance", "Alliance" end
GetSubZoneText = function() return "Sentinel Hill" end
GetRealZoneText = function() return "Westfall" end

ForeverCollectSettings = { verbose = false }
ForeverCollectCharacterSettings = {}

local printed = {}
local addon = { name = "ForeverCollect" }
local function load(path)
    assert(loadfile(path))("ForeverCollect", addon)
end
load("Core/Util.lua")
addon.PrintMessage = function(message) printed[#printed + 1] = message end
load("Core/Theme.lua")
load("Core/Widgets.lua")
load("Core/Registry.lua")
load("Core/SaveReminder.lua")
load("Core/Pause.lua")

-- What the window reads from modules this test does not load.
local state = { armory = false, private = false, combatLog = true, scope = "instances" }
addon.IsArmoryEnabled = function() return state.armory end
addon.IsCharacterPrivateEnabled = function() return state.private end
addon.IsCombatLogEnabled = function() return state.combatLog end
addon.CombatLogScope = function() return state.scope end
addon.SetArmory = function(enabled, options)
    state.armory = enabled
    state.private = enabled and options and options.private or false
end
addon.SetCharacterPrivate = function(enabled) state.private = enabled end
addon.SetCombatLog = function(enabled) state.combatLog = enabled end
addon.SetCombatLogScope = function(scope) state.scope = scope end
addon.HasClassicTalentAPI = function() return true end
addon.GetLatestCatalog = function() return { seasonName = "Forever" } end
addon.QuestCacheStatus = function() return "Quest cache", false, 4812, 7760 end

load("Core/Window.lua")
load("Core/Setup.lua")
local function fire(event, ...)
    addon.eventFrame.scripts.OnEvent(addon.eventFrame, event, ...)
end

-- The setup comes on a character's first login and holds the pause reminder back.
fire("PLAYER_LOGIN")
local setup = _G.ForeverCollectSetup
check("the setup opens on the first login", setup ~= nil and setup:IsShown() and addon.IsSetupPending())
local before = { armory = state.armory, combatLog = state.combatLog }
setup.next:Click()
setup.next:Click()
check("the last step offers Start collecting", setup.next.label:GetText() == "Start collecting")
setup.back:Click()
setup.skip:Click()
check("Skip marks the setup as done", ForeverCollectCharacterSettings.setupDone == true and not setup:IsShown()
    and not addon.IsSetupPending())
check("Skip changes nothing", state.armory == before.armory and state.combatLog == before.combatLog
    and ForeverCollectCharacterSettings.publicChoice == nil and ForeverCollectCharacterSettings.paused == nil)
fire("PLAYER_LOGIN")
check("the setup does not come back", not setup:IsShown())

-- The opening cinematic of a new character closes the setup; it comes back when that ends.
ForeverCollectCharacterSettings.setupDone = nil
fire("PLAYER_LOGIN")
check("the setup opens before the cinematic", setup:IsShown())
setup:Hide()
setup.scripts.OnHide(setup)
check("the cinematic closed the setup", not setup:IsShown() and not addon.IsSetupPending())
fire("CINEMATIC_STOP")
check("the setup returns after the cinematic", setup:IsShown() and addon.IsSetupPending()
    and ForeverCollectCharacterSettings.setupDone == nil)
setup.skip:Click()
fire("CINEMATIC_STOP")
check("a finished setup stays closed after a cinematic", not setup:IsShown())

-- Start collecting applies the choices, only where they changed.
local kinds = {}
for _, kind in ipairs(addon.CAPTURE_KINDS) do
    kinds[kind.key] = kind.key ~= "gathering"
end
addon.ApplySetup({ kinds = kinds, armory = true, public = true, private = false, combatLog = true, everywhere = true })
check("the upload is on without private data", state.armory and not state.private)
check("the visibility choice is kept", ForeverCollectCharacterSettings.publicChoice == true)
check("an unticked kind is paused", addon.IsPaused("gathering") and not addon.IsPaused("quests"))
check("the combat log scope follows", state.scope == "everywhere")
addon.ApplySetup({ kinds = kinds, armory = false, public = true, private = false, combatLog = true, everywhere = true })
check("without upload there is no visibility choice", ForeverCollectCharacterSettings.publicChoice == nil)
ForeverCollectCharacterSettings.paused = nil

addon.Announce("Quest captured.", { kind = "quests", title = "The Defias Brotherhood", detail = "Quest turned in · Westfall" })
addon.Announce("Loot captured.", { kind = "loot", title = "Defias Pillager", detail = "Loot · 3 items" })

addon:HandleSlashCommand("")
local window = _G.ForeverCollectWindow
check("a bare /fc opens the window", window ~= nil and window:IsShown())
for tab = 1, 4 do
    addon.OpenWindow(tab)
    check("tab " .. tab .. " builds and refreshes", window:GetHeight() > 100)
end

-- Clicking every toggle and button of the window runs its handler without errors.
local clicked = 0
for _, frame in ipairs(created) do
    if frame.scripts.OnClick then
        frame.scripts.OnClick(frame, "LeftButton")
        clicked = clicked + 1
    end
end
check("every control of the window can be clicked (" .. clicked .. ")", clicked > 20)
check("Reload UI to save reloads", reloads == 1)

-- A notice's action runs while the notice is still up, as in the game's own popups.
local shownDuringAction
local orderNotice = addon.ShowNotice("order", {
    primary = { label = "Act", onClick = function() shownDuringAction = addon.IsNoticeShown("order") end },
})
orderNotice.primary:Click()
check("a notice runs its action before it hides", shownDuringAction == true and not addon.IsNoticeShown("order"))
addon.RefreshWindow()
check("the window refreshes after the clicks", true)

if addon.OpenSetup then
    addon.OpenSetup()
    local before = #created
    for _, frame in ipairs(created) do
        if frame.scripts.OnClick then
            frame.scripts.OnClick(frame, "LeftButton")
        end
    end
    check("the setup builds and every control can be clicked", #created >= before)
end
