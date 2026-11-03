-- Run: luajit tests/capture_entries_test.lua (or lua5.1)
-- Captures reach the session list with kind, title and detail; chat only with notices on.
local stubFrame = setmetatable({}, { __index = function() return function() end end })
CreateFrame = function() return stubFrame end
WorldFrame = {}
C_Timer = { After = function(_, callback) callback() end }
time = function() return 1000 end
GetSubZoneText = function() return "Sentinel Hill" end
GetRealZoneText = function() return "Westfall" end
StaticPopupDialogs = {}

local printed = {}
local addon = {}
function addon:RegisterEvent() end
function addon:RegisterCommand() end
assert(loadfile("Core/Util.lua"))("ForeverCollect", addon)
addon.PrintMessage = function(message) printed[#printed + 1] = message end
assert(loadfile("Core/SaveReminder.lua"))("ForeverCollect", addon)

local function check(name, condition)
    if not condition then
        error("FAIL: " .. name, 2)
    end
    print("ok - " .. name)
end

ForeverCollectSettings = { verbose = false }
addon.Announce("Captured 24 merchant items from Christopher Hewen.", {
    kind = "merchants",
    title = "Christopher Hewen",
    detail = addon.JoinDetail("Merchant · 24 goods with prices", addon.CurrentPlace()),
})
local entry = addon.GetCaptures()[1]
check("the entry has kind, title and detail", entry.kind == "merchants" and entry.title == "Christopher Hewen"
    and entry.detail == "Merchant · 24 goods with prices · Sentinel Hill")
check("the chat text stays as fallback", entry.text == "Captured 24 merchant items from Christopher Hewen." and entry.at == 1000)
check("no chat line with notices off", #printed == 0)
check("the capture counts as unsaved", addon.UnsavedCaptures() == 1)

ForeverCollectSettings.verbose = true
addon.AnnounceSettled("trainer", "Captured 3 trainer services from Fenwick.", nil,
    { kind = "trainers", title = "Fenwick", detail = "Trainer · 3 services" })
check("settled announcements carry the entry", addon.GetCaptures()[2].kind == "trainers")
check("notices on print the chat line", printed[1] == "Captured 3 trainer services from Fenwick.")

addon.Announce("Named 2 creature(s) looted in instances.")
check("an entry without details keeps only the text", addon.GetCaptures()[3].kind == nil
    and addon.GetCaptures()[3].text == "Named 2 creature(s) looted in instances.")

GetSubZoneText = function() return "" end
check("without a subzone the zone is the place", addon.CurrentPlace() == "Westfall")
check("empty parts are left out", addon.JoinDetail("Boss kill", nil, "", "Deadmines") == "Boss kill · Deadmines")
check("interaction types get labels", addon.InteractionLabel("flightMaster") == "Flight master"
    and addon.InteractionLabel("unknown") == "unknown")
