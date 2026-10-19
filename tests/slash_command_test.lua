-- Run: luajit tests/slash_command_test.lua (or lua5.1)
local stubFrame = setmetatable({}, { __index = function() return function() end end })
CreateFrame = function() return stubFrame end

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
local function record(name)
    return function(argument)
        calls[#calls + 1] = { name = name, argument = argument }
    end
end
addon:RegisterCommand("options", record("options"))
addon:RegisterCommand("armory", record("armory"))

-- a bare /fc must not fail: an error leaves the text in the chat box
for _, message in ipairs({ "", "   " }) do
    calls = {}
    addon:HandleSlashCommand(message)
    check("bare command opens the options (\"" .. message .. "\")", #calls == 1 and calls[1].name == "options" and calls[1].argument == nil)
end

calls = {}
addon:HandleSlashCommand("  ARMORY  On ")
check("command and argument are trimmed and lowercased", calls[1].name == "armory" and calls[1].argument == "on")

calls = {}
addon:HandleSlashCommand("armory")
check("command without argument passes nil", calls[1].name == "armory" and calls[1].argument == nil)

addon:HandleSlashCommand("nope")
check("unknown command is reported", printed[#printed] == "Unknown command. Use /fc help.")
