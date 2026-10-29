local _, addon = ...

-- Addons get no combat data (hostile GUIDs are secret in dungeons and raids, and
-- casts are hidden everywhere), but the game's own combat log file
-- (Logs/WoWCombatLog*.txt) keeps it. The addon turns logging on, and the uploader
-- reads which creatures died during each encounter and which spells creatures
-- used. Logging the addon started is stopped again where it is no longer wanted;
-- logging started by the player or another addon is left alone.
-- Per character, on by default (ForeverCollectCharacterSettings.combatLog), in
-- dungeons and raids only unless combatLogScope is "everywhere".

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

local function scope()
    local settings = ForeverCollectCharacterSettings
    return settings and settings.combatLogScope == "everywhere" and "everywhere" or "instances"
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
    if not isEnabled() or (scope() ~= "everywhere" and not inGroupInstance()) then
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
addon.CombatLogScope = scope

local function describe()
    if not isEnabled() then
        return "Combat log is off. /fc combatlog on logs dungeons and raids for bosses and creature abilities."
    end
    if scope() == "everywhere" then
        return "Combat log is on everywhere: bosses and creature abilities are logged. "
            .. "/fc combatlog instances limits it to dungeons and raids, /fc combatlog off stops it."
    end
    return "Combat log is on in dungeons and raids: bosses and creature abilities are logged. "
        .. "/fc combatlog everywhere also logs outside, /fc combatlog off stops it."
end

function addon.SetCombatLog(enabled)
    ForeverCollectCharacterSettings.combatLog = enabled
    update()
    printMessage(describe())
end

function addon.SetCombatLogScope(value)
    ForeverCollectCharacterSettings.combatLogScope = value == "everywhere" and "everywhere" or nil
    update()
    printMessage(describe())
end

addon:RegisterEvent("PLAYER_ENTERING_WORLD", update)
addon:RegisterEvent("ZONE_CHANGED_NEW_AREA", update)

addon:RegisterCommand("combatlog", function(argument)
    if argument == "on" or argument == "off" then
        addon.SetCombatLog(argument == "on")
    elseif argument == "instances" or argument == "everywhere" then
        addon.SetCombatLogScope(argument)
    else
        printMessage(describe())
    end
end, "Combat log for bosses and creature abilities: /fc combatlog on, off, instances (default) or everywhere")
