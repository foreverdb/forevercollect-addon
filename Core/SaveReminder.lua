local _, addon = ...

-- WoW writes SavedVariables only on logout, exit or /reload. Everything captured
-- since then lives in memory and dies with a crash or a killed process, so this
-- module counts captures since the last save and reminds the player to /reload.
-- It never reloads on its own: the game blocks reloads in many situations, and an
-- unexpected reload is more disruptive than the reminder.

local printMessage = addon.PrintMessage

local REMIND_AFTER_CAPTURES = 50
local REMIND_AFTER_MINUTES = 30
local TICK_SECONDS = 60

local unsavedCaptures = 0
local sessionStartedAt = time()
local lastReminderAt = nil
local lastReminderCaptures = 0

-- What was captured since the last save, for the list on the settings page. Memory
-- only: after a reload everything in it is saved and the list starts empty.
local MAX_LISTED_CAPTURES = 500
local captures = {}

function addon.NoteCapture(message)
    unsavedCaptures = unsavedCaptures + 1
    local entry = { at = time(), text = message }
    captures[#captures + 1] = entry
    if #captures > MAX_LISTED_CAPTURES then
        table.remove(captures, 1)
    end
    if addon.OnCapture then
        addon.OnCapture(entry)
    end
end

function addon.GetCaptures()
    return captures
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

function addon.Save(force)
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

local function tick()
    if unsavedCaptures == 0 then
        return
    end
    local now = time()
    local minutes = math.floor((now - (lastReminderAt or sessionStartedAt)) / 60)
    local dueByCount = unsavedCaptures - lastReminderCaptures >= REMIND_AFTER_CAPTURES
    local dueByTime = minutes >= REMIND_AFTER_MINUTES
    if dueByCount or dueByTime then
        local sinceSave = math.floor((now - sessionStartedAt) / 60)
        printMessage(string.format(
            "|cffffcc00%d capture(s) are not saved yet|r (%d min since the last save) - /fc save to write them now.",
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
end)

addon:RegisterCommand("save", function()
    addon.Save(false)
end, "Save collected data now (reloads the UI)")
