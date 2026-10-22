local _, addon = ...

-- Capture can be paused as a whole or per kind, per character. The flags live in
-- ForeverCollectCharacterSettings.paused (`all` plus one key per kind), so they
-- survive reloads and uploads. Only automatic captures check them: explicit actions
-- (/fc scan, /fc merchants, the quest cache, Armory) still run.

local printMessage = addon.PrintMessage

addon.CAPTURE_KINDS = {
    { key = "quests", label = "Quests", hint = "Quest dialogs and turn-ins." },
    { key = "npcs", label = "NPC services", hint = "Gossip, banker, flight master, innkeeper and other services." },
    { key = "merchants", label = "Merchants", hint = "Merchant inventories and prices." },
    { key = "trainers", label = "Trainers", hint = "Trainer services and costs." },
    { key = "loot", label = "Loot", hint = "Creatures, chests and other containers." },
    { key = "gathering", label = "Gathering", hint = "Herbalism, mining, skinning and fishing finds." },
    { key = "encounters", label = "Boss encounters", hint = "Encounter pulls, kills and boss units." },
    { key = "talents", label = "Talents", hint = "Automatic talent scans on login and talent changes." },
}

local kindsByKey = {}
for _, kind in ipairs(addon.CAPTURE_KINDS) do
    kindsByKey[kind.key] = kind
end

local function getPaused()
    local settings = ForeverCollectCharacterSettings
    return settings and settings.paused or {}
end

function addon.IsCapturing(kind)
    local paused = getPaused()
    return not paused.all and not paused[kind]
end

function addon.IsPaused(kind)
    return getPaused()[kind] == true
end

-- Paused kinds by label; "everything" when all capture is paused.
function addon.PausedLabels()
    local paused = getPaused()
    if paused.all then
        return { "everything" }
    end
    local labels = {}
    for _, kind in ipairs(addon.CAPTURE_KINDS) do
        if paused[kind.key] then
            labels[#labels + 1] = kind.label
        end
    end
    return labels
end

-- `kind` is a capture kind or "all". Resuming "all" also resumes every kind,
-- so /fc resume always means capture is fully on again.
function addon.SetPaused(kind, paused)
    local settings = ForeverCollectCharacterSettings
    settings.paused = settings.paused or {}
    local flags = settings.paused
    if kind == "all" and not paused then
        for key in pairs(flags) do
            flags[key] = nil
        end
    else
        flags[kind] = paused or nil
    end
    if next(flags) == nil then
        settings.paused = nil
    end
    local label = kind == "all" and "All capture" or (kindsByKey[kind].label .. " capture")
    printMessage(label .. (paused and " paused." or " resumed."))
end

local function kindKeys()
    local keys = {}
    for _, kind in ipairs(addon.CAPTURE_KINDS) do
        keys[#keys + 1] = kind.key
    end
    return table.concat(keys, ", ")
end

local function setPausedCommand(argument, paused)
    local kind = argument or "all"
    if kind ~= "all" and not kindsByKey[kind] then
        printMessage("Unknown capture kind. Use one of: all, " .. kindKeys() .. ".")
        return
    end
    addon.SetPaused(kind, paused)
end

addon:RegisterCommand("pause", function(argument)
    setPausedCommand(argument, true)
end, "Pause capture: /fc pause (all) or /fc pause <kind>")

addon:RegisterCommand("resume", function(argument)
    setPausedCommand(argument, false)
end, "Resume capture: /fc resume (all) or /fc resume <kind>")

-- A pause outlives the session, so every login and /reload reminds of it in
-- chat and with a popup that resumes everything in one click.
local LOGIN_REMINDER_DELAY = 2
local POPUP = "FOREVERCOLLECT_CAPTURE_PAUSED"
StaticPopupDialogs[POPUP] = {
    text = "ForeverCollect: capture is paused on this character for %s.",
    button1 = "Resume all",
    button2 = "Keep paused",
    OnAccept = function()
        addon.SetPaused("all", false)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3, -- keep the first popup slots free for the game's own dialogs
}

local function remindPaused()
    local labels = addon.PausedLabels()
    if #labels == 0 then
        return
    end
    local text = table.concat(labels, ", ")
    printMessage(string.format("|cffffcc00Capture is paused on this character for %s.|r /fc resume turns it back on.", text))
    if not InCombatLockdown() and not StaticPopup_Visible(POPUP) then
        StaticPopup_Show(POPUP, text)
    end
end

addon:RegisterEvent("PLAYER_LOGIN", function()
    if C_Timer and C_Timer.After then
        C_Timer.After(LOGIN_REMINDER_DELAY, remindPaused)
    else
        remindPaused()
    end
end)
