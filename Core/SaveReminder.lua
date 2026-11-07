local _, addon = ...

-- WoW writes SavedVariables only on logout, exit or /reload. Everything captured
-- since then lives in memory and dies with a crash or a killed process, so this
-- module counts captures since the last save. The reminder to /reload is opt-in
-- (Advanced tab): the game saves on logout and exit anyway, so by default it stays
-- quiet. It never reloads on its own: the game blocks reloads in many situations,
-- and an unexpected reload is more disruptive than the reminder.

local printMessage = addon.PrintMessage

local DEFAULT_REMIND_CAPTURES = 100
local MIN_REMIND_CAPTURES = 25
local MAX_REMIND_CAPTURES = 500
local REMIND_CAPTURES_STEP = 25
local DEFAULT_REMIND_MINUTES = 30
local MIN_REMIND_MINUTES = 5
local MAX_REMIND_MINUTES = 120
local REMIND_MINUTES_STEP = 5
local TICK_SECONDS = 60

addon.MIN_REMIND_CAPTURES = MIN_REMIND_CAPTURES
addon.MAX_REMIND_CAPTURES = MAX_REMIND_CAPTURES
addon.REMIND_CAPTURES_STEP = REMIND_CAPTURES_STEP
addon.MIN_REMIND_MINUTES = MIN_REMIND_MINUTES
addon.MAX_REMIND_MINUTES = MAX_REMIND_MINUTES
addon.REMIND_MINUTES_STEP = REMIND_MINUTES_STEP

local unsavedCaptures = 0
local sessionStartedAt = time()
local lastReminderAt = nil
local lastReminderCaptures = 0

local function snap(value, step, min, max)
    return math.max(min, math.min(max, math.floor(value / step + 0.5) * step))
end

-- Whether the reminder is on, account-wide (Advanced tab). Off unless switched on.
function addon.IsSaveReminderOn()
    local settings = ForeverCollectSettings
    return settings and settings.saveReminder == true or false
end

-- Switching on starts both thresholds fresh, so the finds collected so far do not
-- trigger a reminder right away.
function addon.SetSaveReminder(enabled)
    ForeverCollectSettings.saveReminder = enabled and true or false
    if enabled then
        lastReminderAt = time()
        lastReminderCaptures = unsavedCaptures
    end
end

-- How long finds may wait for a reminder.
function addon.RemindMinutes()
    local settings = ForeverCollectSettings
    return settings and settings.remindMinutes or DEFAULT_REMIND_MINUTES
end

function addon.SetRemindMinutes(minutes)
    ForeverCollectSettings.remindMinutes = snap(minutes, REMIND_MINUTES_STEP, MIN_REMIND_MINUTES, MAX_REMIND_MINUTES)
end

-- How many new finds may wait for a reminder; whichever threshold comes first wins.
function addon.RemindCaptures()
    local settings = ForeverCollectSettings
    return settings and settings.remindCaptures or DEFAULT_REMIND_CAPTURES
end

function addon.SetRemindCaptures(count)
    ForeverCollectSettings.remindCaptures = snap(count, REMIND_CAPTURES_STEP, MIN_REMIND_CAPTURES, MAX_REMIND_CAPTURES)
end

-- What was captured since the last save, for the session list of the window. Memory
-- only: after a reload everything in it is saved and the list starts empty. An entry
-- carries `kind`, `title` and `detail` where the module gave them, and always the chat
-- `text` to fall back on.
local MAX_LISTED_CAPTURES = 500
local captures = {}

function addon.NoteCapture(message, details)
    unsavedCaptures = unsavedCaptures + 1
    local entry = { at = time(), text = message }
    if type(details) == "table" then
        entry.kind, entry.title, entry.detail = details.kind, details.title, details.detail
    end
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

-- The reminder is a notice of the addon's own style (Core/Widgets.lua): "Reload UI to
-- save" reloads, "Later" snoozes it until the next reminder is due.
local NOTICE = "save"

local function showReminder(count, minutes)
    addon.ShowNotice(NOTICE, {
        icon = "character",
        title = count == 1 and "1 find waiting to be saved" or (count .. " finds waiting to be saved"),
        detail = minutes < 1 and "Last save just now" or ("Last save " .. minutes .. " min ago"),
        secondary = { label = "Later" },
        primary = {
            label = "Reload UI to save",
            onClick = function()
                if canReloadNow() then
                    reloadUI()
                else
                    printMessage("Cannot reload right now (combat, casting or an open dialog). Use /fc save in a moment.")
                end
            end,
        },
    })
end

local function tick()
    if unsavedCaptures == 0 or not addon.IsSaveReminderOn() then
        return
    end
    local now = time()
    local minutes = math.floor((now - (lastReminderAt or sessionStartedAt)) / 60)
    local dueByCount = unsavedCaptures - lastReminderCaptures >= addon.RemindCaptures()
    local dueByTime = minutes >= addon.RemindMinutes()
    if dueByCount or dueByTime then
        local sinceSave = math.floor((now - sessionStartedAt) / 60)
        printMessage(string.format(
            "|cffffcc00%d capture(s) are not saved yet|r (%d min since the last save) - /fc save to write them now.",
            unsavedCaptures, sinceSave
        ))
        if not addon.IsNoticeShown(NOTICE) and not InCombatLockdown() then
            showReminder(unsavedCaptures, sinceSave)
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
