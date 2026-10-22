local _, addon = ...

-- Inside dungeons and raids the GUIDs of hostile units are secret to addons, but
-- the game's own combat log file (Logs/WoWCombatLog*.txt) keeps them. The addon
-- turns logging on there, and the uploader reads which creatures died during
-- each encounter. Logging the addon started is stopped again on leaving the
-- instance; logging started by the player or another addon is left alone.
-- Per character, on by default (ForeverCollectCharacterSettings.combatLog).

local printMessage = addon.PrintMessage
local readable = addon.Readable

-- "started" (by the addon), "already" (on before), "off", "blocked" (the
-- client refused), nil before the first check.
local state
local startedByAddon = false

local function isEnabled()
    local settings = ForeverCollectCharacterSettings
    return not settings or settings.combatLog ~= false
end

local function isLogging()
    return LoggingCombat and readable(LoggingCombat()) and true or false
end

local function inGroupInstance()
    if not GetInstanceInfo then
        return false
    end
    local _, instanceType = GetInstanceInfo()
    instanceType = readable(instanceType)
    return instanceType == "party" or instanceType == "raid"
end

local function stopOwnLogging()
    if startedByAddon then
        pcall(LoggingCombat, false)
        startedByAddon = false
    end
end

local function update()
    if not LoggingCombat then
        state = "blocked"
        return
    end
    if not isEnabled() or not inGroupInstance() then
        stopOwnLogging()
        state = isLogging() and "already" or "off"
        return
    end
    if startedByAddon then
        return
    end
    if isLogging() then
        state = "already"
        return
    end
    local ok = pcall(LoggingCombat, true)
    if ok and isLogging() then
        startedByAddon = true
        state = "started"
    else
        state = "blocked"
    end
end

function addon.CombatLogState()
    return state
end

addon.IsCombatLogEnabled = isEnabled

function addon.SetCombatLog(enabled)
    ForeverCollectCharacterSettings.combatLog = enabled
    update()
    printMessage(enabled
        and "Combat log on: dungeons and raids are logged so the uploader can tell which creatures are the bosses."
        or "Combat log off: the addon no longer turns on combat logging in dungeons and raids.")
end

addon:RegisterEvent("PLAYER_ENTERING_WORLD", update)
addon:RegisterEvent("ZONE_CHANGED_NEW_AREA", update)

addon:RegisterCommand("combatlog", function(argument)
    if argument == "on" or argument == "off" then
        addon.SetCombatLog(argument == "on")
    else
        printMessage(isEnabled()
            and "Combat log is on: dungeons and raids are logged for boss detection. /fc combatlog off stops it."
            or "Combat log is off. /fc combatlog on logs dungeons and raids for boss detection.")
    end
end, "Combat log in dungeons and raids for boss detection: /fc combatlog on or off")
