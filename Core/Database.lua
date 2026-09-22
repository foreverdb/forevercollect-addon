local _, addon = ...

local DATABASE_SCHEMA_VERSION = 9

local SEASON_NAMES = {
    [0] = "NoSeason",
    [1] = "SeasonOfMastery",
    [2] = "SeasonOfDiscovery",
    [3] = "Hardcore",
    [11] = "Fresh",
    [12] = "FreshHardcore",
}

local function initializeDatabase()
    ForeverCollectDB = ForeverCollectDB or {}
    ForeverCollectDB.settings = ForeverCollectDB.settings or {}
    if not ForeverCollectDB.schemaVersion or ForeverCollectDB.schemaVersion < DATABASE_SCHEMA_VERSION then
        ForeverCollectDB.schemaVersion = DATABASE_SCHEMA_VERSION
    end
    ForeverCollectDB.catalogs = ForeverCollectDB.catalogs or {}
end
addon.InitializeDatabase = initializeDatabase

function addon.GetClientInfo()
    local version, build, buildDate, interfaceVersion = GetBuildInfo()
    local className, classFile, classID = UnitClass("player")
    local raceName, raceFile, raceID = UnitRace("player")
    local factionFile, factionName = UnitFactionGroup("player")
    local seasonID = 0

    if C_Seasons and C_Seasons.GetActiveSeason then
        seasonID = C_Seasons.GetActiveSeason() or 0
    end

    return {
        projectID = WOW_PROJECT_ID,
        version = version,
        build = build,
        buildDate = buildDate,
        interfaceVersion = interfaceVersion,
        locale = GetLocale(),
        classID = classID,
        className = className,
        classFile = classFile,
        raceID = raceID,
        raceName = raceName,
        raceFile = raceFile,
        factionName = factionName,
        factionFile = factionFile,
        seasonID = seasonID,
        seasonName = SEASON_NAMES[seasonID] or "Unknown",
    }
end

-- Classic Era reports WOW_PROJECT_CLASSIC; Forever (1.60+) runs on the mainline
-- engine and reports that engine's project id, so it is recognised by its
-- interface version instead (1.x content = 10000..19999).
function addon.IsSupportedClient(client)
    if client.projectID == WOW_PROJECT_CLASSIC then
        return true
    end
    local interfaceVersion = tonumber(client.interfaceVersion) or 0
    return interfaceVersion >= 10000 and interfaceVersion < 20000
end

local function getCatalogKey(client)
    return string.format(
        "%d:%d:%d:%s:%d:%d:%s",
        client.projectID,
        client.interfaceVersion,
        client.seasonID,
        client.locale,
        client.classID,
        client.raceID,
        client.factionFile or "Unknown"
    )
end

function addon.GetOrCreateCatalog(client)
    initializeDatabase()

    local key = getCatalogKey(client)
    local catalog = ForeverCollectDB.catalogs[key]
    if not catalog then
        catalog = {
            schemaVersion = DATABASE_SCHEMA_VERSION,
            projectID = client.projectID,
            version = client.version,
            build = client.build,
            buildDate = client.buildDate,
            interfaceVersion = client.interfaceVersion,
            locale = client.locale,
            classID = client.classID,
            className = client.className,
            classFile = client.classFile,
            raceID = client.raceID,
            raceName = client.raceName,
            raceFile = client.raceFile,
            factionName = client.factionName,
            factionFile = client.factionFile,
            seasonID = client.seasonID,
            seasonName = client.seasonName,
            scannedAt = time(),
            specializations = {},
            quests = {},
            npcs = {},
            trainerSnapshots = {},
            items = {},
            merchantSnapshots = {},
            lootSources = {},
            spellTooltips = {},
        }
        ForeverCollectDB.catalogs[key] = catalog
    else
        catalog.schemaVersion = DATABASE_SCHEMA_VERSION
        catalog.classID = client.classID
        catalog.className = client.className
        catalog.classFile = client.classFile
        catalog.raceID = client.raceID
        catalog.raceName = client.raceName
        catalog.raceFile = client.raceFile
        catalog.factionName = client.factionName
        catalog.factionFile = client.factionFile
        catalog.quests = catalog.quests or {}
        catalog.npcs = catalog.npcs or {}
        catalog.specializations = catalog.specializations or {}
        catalog.trainerSnapshots = catalog.trainerSnapshots or {}
        catalog.items = catalog.items or {}
        catalog.merchantSnapshots = catalog.merchantSnapshots or {}
        catalog.lootSources = catalog.lootSources or {}
        catalog.spellTooltips = catalog.spellTooltips or {}
    end

    ForeverCollectDB.latestCatalogKey = key
    return catalog
end

function addon.GetLatestCatalog()
    initializeDatabase()
    return ForeverCollectDB.catalogs[ForeverCollectDB.latestCatalogKey]
end

function addon.GetCharacterContext()
    local raceName, raceFile, raceID = UnitRace("player")
    local sex = UnitSex("player")
    local level = UnitLevel("player")
    local factionFile, factionName = UnitFactionGroup("player")
    local className, classFile, classID = UnitClass("player")

    return {
        name = UnitName("player"),
        realm = GetRealmName(),
        level = level,
        race = raceName,
        raceName = raceName,
        raceFile = raceFile,
        raceID = raceID,
        sex = sex,
        faction = factionFile,
        factionName = factionName,
        factionFile = factionFile,
        className = className,
        classID = classID,
        classFile = classFile,
    }
end

function addon.GetCharacterKey()
    return UnitGUID("player") or string.format(
        "%s-%s",
        UnitName("player") or "Unknown",
        GetRealmName() or "Unknown"
    )
end
