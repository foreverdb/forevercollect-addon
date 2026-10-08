# ForeverCollect

ForeverCollect catalogs observed data from World of Warcraft Classic Era and Forever (1.60+). The data is stored in the SavedVariable `ForeverCollectDB`. The complete field reference for the current schema (version 9) is in [SCHEMA.md](SCHEMA.md).

## Installation

Extract the zip of the latest [GitHub release](https://github.com/foreverdb/forevercollect-addon/releases) into the client's `Interface/AddOns/` folder (it contains the `ForeverCollect/` folder).

## Release

The version is set in `ForeverCollect.toc` (`## Version:`). When it is bumped on `main`, the workflow `.github/workflows/release.yml` checks the Lua syntax, packages `ForeverCollect-vX.Y.Z.zip` and creates the tag and release `vX.Y.Z` with automatic release notes. A push without a version change, or with a tag that already exists, does not create a release. `check.yml` checks the syntax on every push and pull request, and verifies that all files listed in the TOC exist.

## Usage

```text
/fc scan      Scan talents (Forever: talent tooltips)
/fc talents   Show talent data of the current catalog
/fc traits    Diagnose the client's trait trees (Forever)
/fc trainer   Scan trainer services and show number of captured entries
/fc items     Show number of captured items
/fc merchants Show merchant inventories
/fc loot      Show loot sources and items
/fc quests    Show number of captured quests and observations
/fc questcache Query all quests from the server (stop, status, reset)
/fc status    Show catalog context and scan status
/fc verbose   Toggle notices for every capture (default: on)
/fc save      Save collected data now (reloads the UI)
/fc autosave  Save automatically: /fc autosave 30 (minutes) or /fc autosave off
```

Every capture (quest dialog, turn-in, loot, merchant, trainer, banker, flight master) is announced in chat; `/fc verbose` turns these notices off and on again (setting in `ForeverCollectDB.settings`, not part of uploads).

**Quest type:** On every accept and turn-in, the quest type from the quest log is recorded (`tag`: Dungeon, Raid, Elite, PvP …, plus `suggestedGroup`). Quests captured earlier get their type as soon as they are accepted or turned in again.

**Quest catalog:** The website's quest data comes from the client (`QuestV2.db2` and the quest cache `Cache/WDB/<locale>/questcache.wdb`); the observations add NPCs, progress and turn-in texts. The cache only contains quests the client has already queried from the server. `/fc questcache` queries all IDs from `Data/QuestIDs.lua` at a throttled rate (20/s, a bit over 5 minutes, resumable); afterwards, log out so the client writes the cache, then run `foreverdb-import all`.

**Saving:** WoW only writes addon data to disk on logout, exit or `/reload`. Everything since the last save lives only in memory and is lost on a crash or a killed process. The addon therefore counts captures since the last save and, after 50 captures or 30 minutes, reminds you to run `/fc save` with a popup ("Save now" reloads the UI, "Later" postpones) and in chat. `/fc save` is a UI reload and never happens in combat, while casting or with a dialog open. With `/fc autosave <minutes>`, the addon reloads on its own whenever nothing is going on. `/fc status` shows the unsaved captures.

After `/reload`, logout or exit, WoW writes the data to:

```text
WTF/Account/<ACCOUNT>/SavedVariables/ForeverCollect.lua
```

## Uploading

Uploads go through the ForeverDB Uploader (`foreverdb-client`, binary `foreverdb-uploader`): the ingress only accepts the finished JSON snapshot, and the uploader converts the SavedVariables. The former `upload.sh` could not do this and has been removed.

## Project Structure

Files are loaded in the order given in `ForeverCollect.toc` and share the addon table (`local _, addon = ...`). Modules attach to `addon` only what other files need, and register their own events and slash subcommands via `addon:RegisterEvent(event, handler)` and `addon:RegisterCommand(name, handler, help)`.

```text
Core/Util.lua           Chat output, tooltip scanner, small helpers
Core/Database.lua       ForeverCollectDB, client/character context, catalog management
Core/Registry.lua       Event frame and dispatcher for events and slash commands
Modules/NPCs.lua        NPC capture and merging (merchants, trainers, bankers, flight masters)
Core/Autosave.lua       Unsaved captures, /fc save, /fc autosave
Modules/Items.lua       Item catalog with sources and coordinates (/fc items)
Modules/Merchants.lua   Merchant inventories (/fc merchants)
Modules/Gathering.lua   Detects gathering spells (herbs, ore, skinning, fishing) and node names via tooltip
Modules/Loot.lua        Loot sources and drop locations (/fc loot)
Modules/Talents.lua     Talent trees via the Classic API (/fc talents)
Modules/Traits.lua      Talent tooltips via the trait system on Forever (/fc traits)
Modules/Trainers.lua    Trainer services (/fc trainer)
Modules/Quests.lua      Quest dialogs and turn-ins (/fc quests)
Modules/QuestCache.lua  Queries all quests from Data/QuestIDs.lua from the server (/fc questcache)
Data/QuestIDs.lua       Quest IDs from QuestV2.db2, generated with `foreverdb-import quest-ids`
ForeverCollect.lua      Entry point: loading, login scan, /fc help, /fc scan, /fc status
```

## Chat Feedback

When new data has been captured successfully, a message with the prefix `New data captured` appears in chat. Repeated automatic updates without new entries stay silent to avoid chat spam. Manual scans still show their summary scan message.

## Top Level

```lua
ForeverCollectDB = {
    schemaVersion = 9,
    latestCatalogKey = "...",
    catalogs = {
        [catalogKey] = catalog,
    },
}
```

| Field | Type | Description |
| --- | --- | --- |
| `schemaVersion` | number | Current database schema version. Currently `9`. |
| `latestCatalogKey` | string | Key of the most recently used catalog. |
| `catalogs` | table | Catalogs, grouped by client and character context. |

## Catalog Key

Each catalog is stored under the following key:

```text
projectID:interfaceVersion:build:seasonID:locale:classID:raceID:factionFile
```

Example:

```text
2:11509:61987:2:enUS:8:3:Alliance
```

The key separates talent data for different classes, races and factions. The locale is also part of the key because names, descriptions and tooltip texts are localized.

## Catalog Metadata

```lua
catalog = {
    schemaVersion = 9,
    projectID = 2,
    version = "1.15.9",
    build = "...",
    buildDate = "...",
    interfaceVersion = 11509,
    locale = "enUS",

    classID = 8,
    className = "Priest",
    classFile = "PRIEST",
    raceID = 3,
    raceName = "Dwarf",
    raceFile = "Dwarf",
    factionName = "Alliance",
    factionFile = "Alliance",

    seasonID = 2,
    seasonName = "SeasonOfDiscovery",
    scannedAt = 0,
    specializations = {},
    trainerSnapshots = {},
    items = {},
    merchantSnapshots = {},
    lootSources = {},
    quests = {},
    npcs = {},
}
```

`scannedAt`, `questScanUpdatedAt`, `trainerScanUpdatedAt`, `itemsUpdatedAt`, `merchantScanUpdatedAt` and `lootUpdatedAt` contain Unix timestamps.

## Talents

`specializations` is an array of talent trees, read via the Classic Era tab/tier API (`Modules/Talents.lua`). Forever (1.60+) builds its talents on the trait system (`C_Traits`); there `specializations` stays empty. Tree structure, ranks and prerequisites come from the client's trait tables (`TraitNode`, `TraitEdge`), which the importer reads. What only the game knows are the tooltip texts with their values: `Modules/Traits.lua` runs at login (delayed by 5 s) and on `/fc scan`, walks the active trait configuration and stores the tooltips of all ranks for each talent spell in `spellTooltips`. `/fc traits` shows what the client provides. Automatic scans report only once per session; only `/fc scan` explains why no trees are scanned on Forever.

```lua
specializations = {
    {
        index = 1,
        id = 256,
        name = "Discipline",
        description = "...",
        icon = 135940,
        talents = {
            {
                index = 1,
                talentID = 123,
                spellID = 456,
                name = "...",
                icon = 135845,
                tier = 1,
                column = 1,
                maxRank = 5,
                tooltipLines = {
                    {
                        leftText = "...",
                        rightText = "...",
                    },
                },
            },
        },
    },
}
```

| Field | Description |
| --- | --- |
| `specializations[].index` | Position of the talent tree in the client. |
| `specializations[].id` | ID of the talent tree or specialization. |
| `talents[].talentID` | Unique talent ID. |
| `talents[].spellID` | Associated spell ID. |
| `talents[].tier`, `column` | Position in the talent tree. |
| `talents[].maxRank` | Maximum rank. |
| `tooltipLines` | Localized tooltip lines as left and right text columns. |

The talent data describes the available tree. The current character context is determined by the catalog key.

## Trainer Skills

`trainerSnapshots` is updated automatically when a trainer is opened (`TRAINER_SHOW`) or the trainer list changes (`TRAINER_UPDATE`, e.g. after learning). The key is the NPC GUID; if it is not available, the NPC ID combined with the name is used.

During the scan, all filters (`available`, `unavailable`, `used`) are temporarily enabled and all categories expanded, so already learned and not yet available services are captured as well. The previous UI state is restored afterwards.

The module supports both API generations: the Classic list with header rows (`ExpandTrainerSkillLine`) and the flat mainline list of Forever 1.60+ (where `GetTrainerServiceInfo` returns `name, serviceType, texture, reqLevel, subText, category`).

```lua
trainerSnapshots = {
    ["Creature-0-..."] = {
        capturedAt = 0,
        character = {},
        trainerNPC = {},
        greeting = "Greetings, friend.",
        isTradeskillTrainer = false,
        services = {
            {
                index = 1,
                name = "Alchemy",
                category = "header",
                isHeader = true,
                isExpanded = true,
                isAvailable = false,
                isKnown = false,
                skillLine = "Alchemy",
            },
            {
                index = 2,
                name = "Example Spell",
                rank = "Rank 1",
                category = "available",
                isHeader = false,
                isExpanded = false,
                isAvailable = true,
                isKnown = false,
                skillLine = "Alchemy",
                link = "|cff71d5ff|Hspell:1234|h[Example Spell]|h|r",
                spellID = 1234,
                icon = 123456,
                description = "...",
                moneyCost = 100,
                talentCost = 0,
                professionCost = 0,
                requirements = {
                    level = 10,
                    skill = { name = "Alchemy", rank = 50, isMet = true },
                    abilities = { { name = "Other Spell", isMet = false } },
                },
                tooltipLines = {},
            },
        },
    },
}
```

`category` is `header`, `available`, `unavailable` or `used` (already learned). `skillLine` is the name of the most recently read category header. `spellID` is read from `link` (`spell:` or `enchant:`). `requirements.skill` and `requirements.level` are absent if the service has no such requirement. Opening the same trainer again replaces the previous snapshot.

## Items

`items` is a deduplicated catalog of all observed items, keyed by `itemID`. It is filled exclusively through sources (merchants, quests, loot, recipes); bag or equipment contents are not captured.

```lua
items = {
    [12345] = {
        itemID = 12345,
        link = "|cffffffff|Hitem:12345:...|h[Example Item]|h|r",
        firstSeenAt = 0,
        lastSeenAt = 0,
        sources = {
            ["merchant:6018"] = {
                type = "merchant", npcID = 6018, name = "Vendor",
                location = {}, timesSeen = 2, firstSeenAt = 0, lastSeenAt = 0,
            },
            ["quest:123"] = { type = "quest", questID = 123, location = {}, timesSeen = 1 },
            ["loot:Creature:456"] = {
                type = "loot", sourceType = "Creature", sourceID = 456, name = "Mob",
                locations = { {}, {} }, timesSeen = 5,
            },
        },
    },
}
```

The addon only records **where** an item was seen. Static item data (name, quality, stats, sell price, binding …) comes from the client's DB2 tables (`Item`, `ItemSparse`, `ItemSearchName`) via the server importer and is no longer read in game.

`sources` links each item to where it was found. Merchant and quest sources carry the NPC's `location` (format as under "Quest NPC and Location"), loot sources a `locations` list with the player positions while looting (deduplicated to about 0.1% map resolution, at most 20 entries). Recipe sources have no world coordinate.

## Merchants

Merchant data is read via `GetMerchantItemInfo`, on Forever 1.60+ via `C_MerchantFrame.GetItemInfo`.

`merchantSnapshots` is updated when a merchant is opened (`MERCHANT_SHOW`) and when the inventory changes (`MERCHANT_UPDATE`). The key is the NPC GUID, otherwise `npcID:name`. Opening the merchant again replaces the snapshot.

```lua
merchantSnapshots = {
    ["Creature-0-..."] = {
        capturedAt = 0,
        character = {},
        merchantNPC = {},          -- NPC object incl. location
        canRepair = false,
        items = {
            {
                index = 1,
                itemID = 12345,
                name = "Example Item",
                link = "...",
                texture = 123456,
                price = 250,          -- copper
                stackCount = 1,
                maxStack = 5,
                numAvailable = -1,    -- -1 = unlimited
                isPurchasable = true,
                isUsable = true,
                hasExtendedCost = false,
                extendedCost = {      -- only with hasExtendedCost
                    { itemID = 1, name = "Token", link = "...", texture = 1, count = 3 },
                },
            },
        },
    },
}
```

## Loot

`lootSources` aggregates loot observations per source (`LOOT_OPENED`). The key is `<sourceType>:<sourceID>` from the source GUID (`Creature`, `GameObject`), or `Fishing` when fishing. Inside instances, the GUIDs of hostile units are secret; such loot is stored under `Instance:<instanceID>` with the instance name as `name`. The same loot container counts only once per session (without a GUID, i.e. for `Instance`, this cannot be detected).

```lua
lootSources = {
    ["Creature:456"] = {
        sourceType = "Creature",
        sourceID = 456,
        name = "Mob",              -- if the source was the current target
        lootCount = 3,             -- loot windows opened
        firstSeenAt = 0,
        lastSeenAt = 0,
        locations = { {} },        -- player position per loot, max. 100
        items = {
            [12345] = {
                itemID = 12345,
                name = "Example Item",
                link = "...",
                quality = 1,
                isQuestItem = false,
                questID = nil,
                timesSeen = 2,
                quantityTotal = 3,
                lastSeenAt = 0,
                locations = { {} },  -- drop locations of this item, max. 20
            },
        },
        money = { timesSeen = 3, total = 1234 },  -- copper
    },
}
```

## Professions

Recipes are no longer read in game. Recipe↔profession, reagents, tools, cooldowns and learning sources come from the DB2 tables (`SkillLineAbility`, `SpellReagents`, `SpellTotems`, `SpellCooldowns`, `SpellCastingRequirements`, `ItemEffect`) via the server importer.

## Quests

`quests` is indexed by quest ID:

```lua
quests = {
    [12345] = {
        questID = 12345,
        title = "Quest title",
        observations = {
            {
                phase = "QUEST_DETAIL",
                capturedAt = 0,
                character = {},
                questNPC = {},
                description = "...",
                objectives = "...",
                rewards = {},
            },
            {
                phase = "QUEST_PROGRESS",
                capturedAt = 0,
                character = {},
                questNPC = {},
                text = "...",
                progress = {},
            },
            {
                phase = "QUEST_COMPLETE",
                capturedAt = 0,
                character = {},
                questNPC = {},
                text = "...",
                rewards = {},
            },
        },
        turnIn = {
            capturedAt = 0,
            xp = 100,
            money = 500,
            character = {},
        },
    },
}
```

### Quest Phases

| Phase | Captured data |
| --- | --- |
| `QUEST_DETAIL` | Title, accept text, objectives and offered rewards. |
| `QUEST_PROGRESS` | Progress text, required items and required money. |
| `QUEST_COMPLETE` | Completion text and final rewards. |
| `QUEST_ITEM_UPDATE` | Updates item data in the most recently active dialog when it loaded late. |
| `QUEST_TURNED_IN` | XP and money actually awarded. |

### Quest NPC and Location

Every direct dialog observation contains an optional `questNPC` object. The role is `giver` for `QUEST_DETAIL`, `progress` for `QUEST_PROGRESS` and `turnIn` for `QUEST_COMPLETE`.

```lua
questNPC = {
    role = "giver",
    guid = "Creature-0-...",
    objectType = "Creature",
    objectID = 12345,
    npcID = 12345,
    name = "Quest NPC",
    location = {
        source = "playerAtInteraction",
        uiMapID = 1454,
        mapName = "Orgrimmar",
        mapType = 3,
        parentMapID = 1414,
        zone = "Orgrimmar",
        subZone = "Valley of Spirits",
        x = 0.3712,
        y = 0.8421,
        worldContinentID = 1,
        worldX = 1234.5,
        worldY = 678.9,
    },
}
```

`guid` is a string. `objectID` and `npcID` are numeric client IDs, if the client provides them; `uiMapID`, `mapType` and `parentMapID` are numeric map values. `name`, `mapName`, `zone` and `subZone` are localized texts. `x` and `y` are the player's normalized map coordinates when the dialog was opened. `worldX` and `worldY` are calculated with `C_Map.GetWorldPosFromMapPos()`; `worldContinentID` identifies the corresponding world/continent coordinate system. All coordinates are therefore an approximation of the NPC position and can be missing if the client provides no map data. `QUEST_ITEM_UPDATE` does not create a new observation and does not replace the NPC location already stored.

### NPC Catalog

`npcs` contains all detected NPCs from quest dialogs as well as from merchant, trainer, banker, flight master and innkeeper interactions. A merchant's inventory is in `merchantSnapshots`, a trainer's services in `trainerSnapshots`. An NPC can have several `interactionTypes`. Supported values are `questGiver`, `merchant`, `trainer`, `banker`, `flightMaster` and `innkeeper`.

```lua
npcs = {
    {
        role = "merchant",
        guid = "Creature-0-...",
        objectType = "Creature",
        objectID = 12345,
        npcID = 12345,
        name = "Merchant",
        interactionTypes = { "merchant" },
        creatureType = "Humanoid",
        classification = "normal",
        location = {},
    },
}
```

On load, existing `questNPC` entries are normalized to this common format and added to the NPC catalog. Information missing from older observations cannot be filled in retroactively.
If the client provides no creature type or classification, `"Unknown"` or `"unknown"` is stored respectively.

### Rewards

A `rewards` object contains:

```lua
rewards = {
    items = {},
    choices = {},
    spells = {},
    money = 0,
    xp = 0,
}
```

Item entries contain, among others, `itemID`, `name`, `link`, `texture`, `quantity`, `quality` and `isUsable`; the items are also added to the item catalog `items` with the source `quest:<questID>` and the quest NPC's location. Spell entries contain `spellID`, `name`, `texture`, `isTradeskill` and `isSpellLearned`.

## Context and Variants

Quest data is stored with the character context of the observation, since quest texts and rewards can depend on class, race, faction, level or character progress. Talent data, on the other hand, is separated by class, race and faction through the catalog key.

The source data is observed client data. The client offers no complete global quest catalog; a quest is only stored once the corresponding dialog has been opened.
