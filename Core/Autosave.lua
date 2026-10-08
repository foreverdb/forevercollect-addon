local _, addon = ...

-- WoW writes SavedVariables only on logout, exit or /reload. Everything captured
-- since then lives in memory and dies with a crash or a killed process, so this
-- module counts captures since the last save, reminds the player to /reload, and
-- can reload on its own (opt-in: /fc autosave <minutes>).

local printMessage = addon.PrintMessage

local REMIND_AFTER_CAPTURES = 50
local REMIND_AFTER_MINUTES = 30
local TICK_SECONDS = 60

local unsavedCaptures = 0
local sessionStartedAt = time()
local lastReminderAt = nil
local lastReminderCaptures = 0

function addon.NoteCapture()
    unsavedCaptures = unsavedCaptures + 1
end

function addon.UnsavedCaptures()
    return unsavedCaptures, time() - sessionStartedAt
end

local function reloadUI()
    if C_UI and C_UI.Reload then
        C_UI.Reload()
    else
        ReloadUI()
    end
end

-- A reload freezes the screen for a moment and must not interrupt a fight, a cast,
-- an open loot window or a merchant/quest dialog.
local function canReloadNow()
    if InCombatLockdown() or UnitAffectingCombat("player") then
        return false
    end
    if UnitCastingInfo("player") or UnitChannelInfo("player") then
        return false
    end
    if (LootFrame and LootFrame:IsShown())
        or (MerchantFrame and MerchantFrame:IsShown())
        or (QuestFrame and QuestFrame:IsShown())
        or (GossipFrame and GossipFrame:IsShown())
        or (TradeFrame and TradeFrame:IsShown()) then
        return false
    end
    if UnitIsDeadOrGhost("player") then
        return false
    end
    return true
end

local function save(force)
    if unsavedCaptures == 0 and not force then
        printMessage("Nothing to save: no captures since the last save.")
        return
    end
    if not canReloadNow() then
        printMessage("Cannot reload right now (combat, casting or an open dialog). Try again in a moment.")
        return
    end
    printMessage(string.format("Saving %d capture(s) by reloading the UI...", unsavedCaptures))
    reloadUI()
end

-- The reminder is a standard game popup: "Save now" reloads the UI, "Later" snoozes it.
local POPUP = "FOREVERCOLLECT_SAVE_REMINDER"
StaticPopupDialogs[POPUP] = {
    text = "ForeverCollect: %d capture(s) are not saved yet (%d min since the last save).\n\n"
        .. "The game writes addon data only on logout or /reload; a crash loses everything since.",
    button1 = "Save now (reload UI)",
    button2 = "Later",
    OnAccept = function()
        if canReloadNow() then
            reloadUI()
        else
            printMessage("Cannot reload right now (combat, casting or an open dialog). Use /fc save in a moment.")
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3, -- keep the first popup slots free for the game's own dialogs
}

local function autosaveMinutes()
    local settings = ForeverCollectDB and ForeverCollectDB.settings
    return settings and tonumber(settings.autosaveMinutes) or 0
end

local function tick()
    if unsavedCaptures == 0 then
        return
    end
    local now = time()
    local minutes = math.floor((now - (lastReminderAt or sessionStartedAt)) / 60)
    local auto = autosaveMinutes()
    if auto > 0 and (now - sessionStartedAt) >= auto * 60 and canReloadNow() then
        printMessage(string.format(
            "Autosave: %d capture(s) in the last %d min, reloading the UI.",
            unsavedCaptures, math.floor((now - sessionStartedAt) / 60)
        ))
        reloadUI()
        return
    end
    local dueByCount = unsavedCaptures - lastReminderCaptures >= REMIND_AFTER_CAPTURES
    local dueByTime = minutes >= REMIND_AFTER_MINUTES
    if dueByCount or dueByTime then
        local sinceSave = math.floor((now - sessionStartedAt) / 60)
        printMessage(string.format(
            "|cffffcc00%d capture(s) are not saved yet|r (%d min since the last save) - /fc save, or /fc autosave 30 to reload automatically.",
            unsavedCaptures, sinceSave
        ))
        if not StaticPopup_Visible(POPUP) then
            StaticPopup_Show(POPUP, unsavedCaptures, sinceSave)
        end
        lastReminderAt = now
        lastReminderCaptures = unsavedCaptures
    end
end

addon:RegisterEvent("PLAYER_LOGIN", function()
    sessionStartedAt = time()
    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(TICK_SECONDS, tick)
    end
    local auto = autosaveMinutes()
    if auto > 0 then
        printMessage(string.format("Autosave every %d min is on (/fc autosave off to disable).", auto))
    end
end)

addon:RegisterCommand("save", function()
    save(false)
end, "Save collected data now (reloads the UI)")

addon:RegisterCommand("autosave", function(argument)
    local settings = ForeverCollectDB.settings
    local current = autosaveMinutes()
    if argument == "off" or argument == "0" then
        settings.autosaveMinutes = nil
        printMessage("Autosave disabled. /fc save still reloads on demand.")
        return
    end
    local minutes = tonumber(argument)
    if not minutes then
        if current > 0 then
            printMessage(string.format("Autosave every %d min. Use /fc autosave <minutes> or /fc autosave off.", current))
        else
            printMessage("Autosave is off. Use /fc autosave <minutes> (e.g. 30) to reload automatically.")
        end
        return
    end
    minutes = math.max(5, math.floor(minutes))
    settings.autosaveMinutes = minutes
    printMessage(string.format("Autosave every %d min: the UI reloads when nothing is in progress.", minutes))
end, "Save automatically: /fc autosave <minutes> or off")
