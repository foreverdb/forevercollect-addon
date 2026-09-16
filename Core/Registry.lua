local _, addon = ...

local printMessage = addon.PrintMessage

local eventHandlers = {}
local commands = {}
local commandOrder = {}

local eventFrame = CreateFrame("Frame")
addon.eventFrame = eventFrame

function addon:RegisterEvent(event, handler)
    local handlers = eventHandlers[event]
    if not handlers then
        handlers = {}
        eventHandlers[event] = handlers
        eventFrame:RegisterEvent(event)
    end
    handlers[#handlers + 1] = handler
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local handlers = eventHandlers[event]
    if not handlers then
        return
    end
    for _, handler in ipairs(handlers) do
        handler(...)
    end
end)

function addon:RegisterCommand(name, handler, help)
    if not commands[name] then
        commandOrder[#commandOrder + 1] = name
    end
    commands[name] = { handler = handler, help = help }
end

function addon:GetCommandNames()
    return commandOrder
end

function addon:HandleSlashCommand(message)
    local command = string.lower(string.gsub(message or "", "^%s*(.-)%s*$", "%1"))
    if command == "" then
        command = "help"
    end

    local entry = commands[command]
    if entry then
        entry.handler()
    else
        printMessage("Unknown command. Use /fc help.")
    end
end
