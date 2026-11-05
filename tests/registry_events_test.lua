-- Run: luajit tests/registry_events_test.lua (or lua5.1)
-- A failing event handler must not skip the other handlers of the same event.
local onEvent
local frame = setmetatable({
    SetScript = function(_, name, script)
        if name == "OnEvent" then
            onEvent = script
        end
    end,
}, { __index = function() return function() end end })
CreateFrame = function() return frame end

local printed = {}
local addon = {
    PrintMessage = function(message)
        printed[#printed + 1] = message
    end,
}

local chunk = assert(loadfile("Core/Registry.lua"))
chunk("ForeverCollect", addon)

local function check(name, condition)
    if not condition then
        error("FAIL: " .. name, 2)
    end
    print("ok - " .. name)
end

local calls = {}
addon:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    calls[#calls + 1] = "first"
end)
addon:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    error("boom")
end)
addon:RegisterEvent("PLAYER_ENTERING_WORLD", function(isLogin)
    calls[#calls + 1] = isLogin and "last with argument" or "last"
end)

-- Without the game's error handler, the error goes to the chat.
onEvent(frame, "PLAYER_ENTERING_WORLD", true)
check("handlers after a failing one still run", #calls == 2 and calls[2] == "last with argument")
check("the error is reported with its event", printed[1] and printed[1]:find("PLAYER_ENTERING_WORLD", 1, true)
    and printed[1]:find("boom", 1, true))

-- With it, the error goes there (script errors, BugSack) instead of the chat.
local reported = {}
geterrorhandler = function()
    return function(message)
        reported[#reported + 1] = message
    end
end
calls, printed = {}, {}
onEvent(frame, "PLAYER_ENTERING_WORLD", false)
check("the game's error handler gets the error", #reported == 1 and reported[1]:find("boom", 1, true) ~= nil)
check("nothing in the chat then", #printed == 0)
check("all other handlers ran", #calls == 2 and calls[2] == "last")
