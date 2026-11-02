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

-- Several modules share an event (PLAYER_ENTERING_WORLD has five handlers). A failing
-- handler must not skip the ones after it, so each runs on its own; the error still
-- goes to the game's error handler (script errors, BugSack).
local function reportError(event, message)
    local text = "ForeverCollect " .. event .. ": " .. tostring(message)
    local handler = geterrorhandler and geterrorhandler()
    if handler then
        handler(text)
    else
        printMessage(text)
    end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local handlers = eventHandlers[event]
    if not handlers then
        return
    end
    for _, handler in ipairs(handlers) do
        local ok, message = pcall(handler, ...)
        if not ok then
            reportError(event, message)
        end
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
    local trimmed = string.gsub(message or "", "^%s*(.-)%s*$", "%1")
    local command, argument = string.match(trimmed, "^(%S+)%s*(.-)$")
    command = string.lower(command or "")
    -- A bare /fc opens the settings page; /fc help lists the commands.
    if command == "" then
        command = "options"
    end

    local entry = commands[command]
    if entry then
        -- A bare "/fc" matches nothing, so argument is nil as well as "".
        entry.handler(argument and argument ~= "" and string.lower(argument) or nil)
    else
        printMessage("Unknown command. Use /fc help.")
    end
end
