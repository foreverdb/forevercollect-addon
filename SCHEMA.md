# ForeverCollectDB – Schema Version 9

This document fully describes the structure of the SavedVariable `ForeverCollectDB` as written by ForeverCollect with `DATABASE_SCHEMA_VERSION = 9` (`Core/Database.lua`). It is the reference for consumers that read the file `WTF/Account/<ACCOUNT>/SavedVariables/ForeverCollect.lua`.

## Conventions

- **Types**: `string`, `number` (Lua double; IDs and timestamps are integers), `boolean`, `table`. Lists are tables with consecutive integer keys starting at 1 (`T[]`); maps are written as `map<K, V>`.
- **Required/optional**: column "Opt." – `–` = always present, `✓` = may be absent. A missing field is `nil` in Lua and does **not** appear in the serialized file. Empty tables are written as `{}`.
- **Timestamps** (`…At`) are Unix seconds (`time()`), UTC.
- **Localized texts** (names, descriptions, tooltips) are in the client's language (`catalog.locale`).
- **Coordinates**: `x`/`y` are map coordinates of the `uiMapID`, normalized to 0–1; `worldX`/`worldY` are world coordinates of the continent `worldContinentID`.
- The client writes the file only on `/reload`, logout or exit.

---

## 1. Root: `ForeverCollectDB`

| Field | Type | Opt. | Description |
|---|---|---|---|
| `schemaVersion` | number | – | Schema version of the file; raised to at least 9 on load. |
| `settings` | table | ✓ | Addon settings, e.g. `verbose` (chat notice per capture, default `true`) and `questCacheCrawl` (`{ build, nextIndex }`, position of `/fc questcache`). Ignored by the server. |
| `latestCatalogKey` | string | ✓ | Key of the most recently used catalog in `catalogs`. Absent until a catalog has been created. |
| `catalogs` | map<string, Catalog> | – | All catalogs; see below for the key. |

### Catalog Key

```
<projectID>:<interfaceVersion>:<seasonID>:<locale>:<classID>:<raceID>:<factionFile>
```

Example: `2:11509:2:enUS:5:8:Horde`. A catalog is thus separate per client project, interface version, season, language, class, race and faction. Several characters with the same combination share one catalog.

---

## 2. `Catalog`

### 2.1 Metadata

| Field | Type | Opt. | Description |
|---|---|---|---|
| `schemaVersion` | number | – | Schema version the catalog was last opened with (9). |
| `projectID` | number | – | `WOW_PROJECT_ID`; Classic Era = 2. |
| `version` | string | – | Client version, e.g. `"1.15.9"`. |
| `build` | string | – | Build number, e.g. `"69722"`. |
| `buildDate` | string | – | Build date, e.g. `"Sep  4 2026"`. |
| `interfaceVersion` | number | – | Interface version, e.g. `11509`. |
| `locale` | string | – | Client language, e.g. `"enUS"`, `"deDE"`. |
| `classID` | number | – | Class ID of the character. |
| `className` | string | – | Localized class name. |
| `classFile` | string | – | Class token, e.g. `"PRIEST"`. |
| `raceID` | number | – | Race ID. |
| `raceName` | string | – | Localized race name. |
| `raceFile` | string | – | Race token, e.g. `"Troll"`. |
| `factionName` | string | – | Localized faction name. |
| `factionFile` | string | – | `"Alliance"` or `"Horde"`. |
| `seasonID` | number | – | `C_Seasons.GetActiveSeason()`, 0 without a season. |
| `seasonName` | string | – | `NoSeason` (0), `SeasonOfMastery` (1), `SeasonOfDiscovery` (2), `Hardcore` (3), `Fresh` (11), `FreshHardcore` (12), otherwise `Unknown`. |
| `scannedAt` | number | – | Time the catalog was created or of the last talent scan. |
| `questScanUpdatedAt` | number | ✓ | Last quest observation. |
| `npcScanUpdatedAt` | number | ✓ | Last NPC interaction. |
| `trainerScanUpdatedAt` | number | ✓ | Last trainer scan. |
| `itemsUpdatedAt` | number | ✓ | Last change to the item catalog. |
| `merchantScanUpdatedAt` | number | ✓ | Last merchant scan. |
| `lootUpdatedAt` | number | ✓ | Last loot observation. |
| `spellTooltipsUpdatedAt` | number | ✓ | Last talent tooltip scan. |

### 2.2 Collections

| Field | Type | Description | Section |
|---|---|---|---|
| `specializations` | Specialization[] | Talent trees of the class | 4 |
| `trainerSnapshots` | map<NPCKey, TrainerSnapshot> | Services per trainer NPC | 5 |
| `items` | map<number, Item> | Item catalog, keyed by `itemID` | 6 |
| `merchantSnapshots` | map<NPCKey, MerchantSnapshot> | Inventory per merchant NPC | 7 |
| `lootSources` | map<string, LootSource> | Loot per source | 8 |
| `encounters` | map<number, Encounter> | Boss encounters, keyed by `encounterID` | 15 |
| `quests` | map<number, Quest> | Quests, keyed by `questID` | 11 |
| `npcs` | NPC[] | NPC catalog | 12 |
| `spellTooltips` | map<number, SpellTooltip> | Tooltips of the class's talent rank spells, keyed by `spellID` | 14 |

All collections are always present (possibly empty); `spellTooltips` and `encounters` were added without a version bump and are missing in older catalogs.

**`NPCKey`**: GUID of the NPC (`"Creature-0-…"`); if no GUID is available, `"<npcID>:<name>"` (`addon.GetNPCKey`).
**`CharacterKey`**: Player GUID (`"Player-…"`), alternatively `"<Name>-<Realm>"`.

---

## 3. Common Types

### 3.1 `Location`

Position of the player at the time of an interaction – an approximation of the location of the NPC/source.

| Field | Type | Opt. | Description |
|---|---|---|---|
| `source` | string | – | Always `"playerAtInteraction"`. |
| `zone` | string | ✓ | `GetZoneText()`. |
| `subZone` | string | ✓ | `GetSubZoneText()`, can be empty. |
| `uiMapID` | number | ✓ | Map of the player (`C_Map.GetBestMapForUnit`). |
| `mapName` | string | ✓ | Localized map name. |
| `mapType` | number | ✓ | `Enum.UIMapType`. |
| `parentMapID` | number | ✓ | Parent map. |
| `x`, `y` | number | ✓ | Normalized map coordinates (0–1). |
| `worldContinentID` | number | ✓ | Continent of the world coordinate system. |
| `worldX`, `worldY` | number | ✓ | World coordinates. |

All fields except `source` are absent if the client provides no map data (e.g. in instances without a map).

#### 3.1.1 `CountedLocation`

`Location` with a hit count, used for profession finds (`lootSources[*].locations` and `lootSources[*].items[*].locations` when `profession` is set). Hits at the same spot (same `uiMapID`, `x`/`y` rounded to 0.001) are merged instead of discarded.

| Field | Type | Opt. | Description |
|---|---|---|---|
| *(all fields of `Location`)* | | | |
| `count` | number | – | Number of gathers at this spot. |
| `firstSeenAt` | number | – | First gather. |
| `lastSeenAt` | number | – | Last gather. |
| `times` | number[] | – | Timestamps of the last 20 gathers at most, ascending. |

### 3.2 `Character`

Context of the observing character (`addon.GetCharacterContext`).

| Field | Type | Description |
|---|---|---|
| `name` | string | Character name |
| `realm` | string | Realm name |
| `level` | number | Level at the time of the observation |
| `race`, `raceName` | string | Localized race name (both identical) |
| `raceFile` | string | Race token |
| `raceID` | number | Race ID |
| `sex` | number | `UnitSex`: 2 = male, 3 = female |
| `faction`, `factionFile` | string | `"Alliance"`/`"Horde"` (both identical) |
| `factionName` | string | Localized faction name |
| `className` | string | Localized class name |
| `classFile` | string | Class token |
| `classID` | number | Class ID |

### 3.3 `TooltipLine`

| Field | Type | Opt. | Description |
|---|---|---|---|
| `leftText` | string | ✓ | Left tooltip text of the line. |
| `rightText` | string | ✓ | Right tooltip text of the line. |

At least one of the two fields is set; lines without text are omitted.

### 3.4 `NPC`

| Field | Type | Opt. | Description |
|---|---|---|---|
| `role` | string | – | Role at the first observation: `giver`, `progress`, `turnIn` (quest), otherwise the interaction type. |
| `guid` | string | ✓ | Unit GUID. |
| `objectType` | string | ✓ | First GUID segment, e.g. `"Creature"`, `"GameObject"`. |
| `objectID`, `npcID` | number | ✓ | Creature ID (both identical). |
| `name` | string | ✓ | Localized name. |
| `subtitle` | string | ✓ | Title below the name from the unit tooltip, e.g. `"Warrior Trainer"`. |
| `reaction` | number | ✓ | `UnitReaction(unit, "player")` (1 hated … 8 exalted). |
| `interactionTypes` | string[] | – | All observed interactions: `questGiver`, `merchant`, `trainer`, `banker`, `flightMaster`, `innkeeper`, `auctioneer`, `stableMaster`, `guildMaster`, `tabardVendor`, `battlemaster`, `spiritHealer`, `gossip`. `gossip` means only the gossip window or quest greeting was seen, e.g. a trainer of another class. |
| `gossip` | Gossip | ✓ | Last seen gossip window (see below). |
| `creatureType` | string | – | `UnitCreatureType`, otherwise `"Unknown"`. |
| `classification` | string | – | `UnitClassification` (`normal`, `elite`, `rare`, …), otherwise `"unknown"`. |
| `location` | Location | – | Location (see 3.1). |

`Gossip`, from `GOSSIP_SHOW` (`C_GossipInfo`) or `QUEST_GREETING`; overwritten on every visit:

| Field | Type | Opt. | Description |
|---|---|---|---|
| `capturedAt` | number | – | Unix timestamp. |
| `text` | string | ✓ | Gossip or greeting text. |
| `options` | object[] | – | `{name, icon?, gossipOptionID?}` (legacy clients: `{name, type}`). |
| `availableQuests`, `activeQuests` | object[] | ✓ | `{questID?, title}`. |

---

## 4. `Specialization` (Talent Trees)

`catalog.specializations` is replaced completely on every talent scan (Classic Era tab/tier API). On Forever it stays empty; there the client provides the trees (trait tables, imported server-side) and the addon only the tooltips (section 14).

| Field | Type | Opt. | Description |
|---|---|---|---|
| `index` | number | – | Tree index (1–3). |
| `id` | number | ✓ | Specialization ID. |
| `name` | string | ✓ | Localized name. |
| `description` | string | ✓ | Description. |
| `icon` | number/string | ✓ | Icon (FileDataID or path). |
| `talents` | Talent[] | – | Talents of the tree. |

### `Talent`

| Field | Type | Opt. | Description |
|---|---|---|---|
| `index` | number | – | Talent index in the tree. |
| `talentID` | number | – | Talent ID. |
| `spellID` | number | ✓ | Spell ID of the current rank. |
| `name` | string | – | Name. |
| `icon` | number/string | ✓ | Icon. |
| `tier` | number | – | Row in the tree. |
| `column` | number | – | Column in the tree. |
| `maxRank` | number | – | Maximum rank. |
| `tooltipLines` | TooltipLine[] | – | Tooltip of the talent (rank 1). |
| `prerequisites` | { talentID: number, rank: number }[] | ✓ | Required talents of the same tree (arrows in game) with the required rank; absent without prerequisites. |

---

## 5. `TrainerSnapshot`

Replaced when a trainer is opened and when the list changes (`TRAINER_UPDATE`). During the scan, all filters (`available`, `unavailable`, `used`) are active and all categories expanded, so the list is complete.

On clients with the mainline engine (Forever 1.60+), the trainer API provides no header rows: `services` then contains only services (`isHeader = false`), `skillLine` comes from the API's category name, `link` and `description` are absent, and `requirements.level` comes directly from `GetTrainerServiceInfo`.

| Field | Type | Opt. | Description |
|---|---|---|---|
| `capturedAt` | number | – | Timestamp. |
| `character` | Character | – | Observing character (relevant for `category`). |
| `trainerNPC` | NPC | – | The trainer (incl. `location`). |
| `greeting` | string | ✓ | `GetTrainerGreetingText()`. |
| `isTradeskillTrainer` | boolean | – | Profession trainer. |
| `services` | TrainerService[] | – | All list entries incl. category headers. |

### `TrainerService`

| Field | Type | Opt. | Description |
|---|---|---|---|
| `index` | number | – | List index during the scan. |
| `name` | string | – | Name of the service or header. |
| `rank` | string | ✓ | Rank of the service, e.g. `"Rank 2"`. From the client subtext, otherwise via the spell ID (`GetSpellSubtext`/`GetSpellInfo`). Absent for headers and rankless spells. |
| `category` | string | – | `header`, `available`, `unavailable` or `used` (already learned). Depends on the character. |
| `isHeader` | boolean | – | `category == "header"`. |
| `isExpanded` | boolean | – | Expanded state during the scan (headers). |
| `isAvailable` | boolean | – | `category == "available"`. |
| `isKnown` | boolean | – | `category == "used"`. |
| `skillLine` | string | ✓ | Name of the most recently read header. |

Only for non-headers (`isHeader == false`):

| Field | Type | Opt. | Description |
|---|---|---|---|
| `link` | string | ✓ | Spell/enchant link. |
| `spellID` | number | ✓ | From `link` (`spell:` or `enchant:`), otherwise from the service's tooltip (`GetTooltipSpellID`). Absent only if the client provides no spell for the service. |
| `icon` | number/string | ✓ | Icon. |
| `description` | string | ✓ | Description. |
| `moneyCost` | number | ✓ | Cost in copper. |
| `talentCost` | number | ✓ | Talent points. |
| `professionCost` | number | ✓ | Profession points. |
| `requirements` | TrainerRequirements | – | Requirements. |
| `tooltipLines` | TooltipLine[] | – | Tooltip of the service. |

### `TrainerRequirements`

| Field | Type | Opt. | Description |
|---|---|---|---|
| `level` | number | ✓ | Required level. |
| `skill` | table | ✓ | `{ name: string, rank: number, isMet: boolean }` – required skill. |
| `abilities` | table[] | – | Each `{ name: string, isMet: boolean }` – required abilities (can be empty). `name` refers to the **required** spell incl. rank suffix (usually the previous rank, e.g. `"Power Word: Fortitude (Rank 1)"` for the rank 2 service), not the service itself. |

---

## 6. `Item` (Item Catalog)

`catalog.items[itemID]`. Entries are only created through sources (merchants, quests, loot, recipes) and never deleted.

| Field | Type | Opt. | Description |
|---|---|---|---|
| `itemID` | number | – | Item ID. |
| `link` | string | ✓ | First item link seen (can contain a suffix/random enchantment). |
| `firstSeenAt` | number | – | First observation. |
| `lastSeenAt` | number | – | Last observation. |
| `sources` | map<string, ItemSource> | – | Where the item was found; see 6.2 for the key. |

Static item data (name, quality, level, stats, price, binding, icon …) comes from the DB2 tables `Item`/`ItemSparse`/`ItemSearchName` (wow.export → server importer) and is no longer read in game.

### 6.2 `ItemSource`

Key: `merchant:<npcID>`, `quest:<questID>`, `loot:<sourceType>:<sourceID>`, for profession finds `loot:<profession>:<sourceType>:<sourceID>`.

| Field | Type | Opt. | Description |
|---|---|---|---|
| `type` | string | – | `merchant`, `quest`, `loot`. |
| `npcID` | number | ✓ | Only `merchant`. |
| `questID` | number | ✓ | Only `quest`. |
| `sourceType` | string | ✓ | Only `loot`: `Creature`, `GameObject`, `Fishing`, … |
| `sourceID` | number | ✓ | Only `loot`: creature/object ID; absent for `Fishing`. |
| `profession` | string | ✓ | Only `loot` from profession actions: `Herbalism`, `Mining`, `Skinning`, `Fishing`. |
| `name` | string | ✓ | Name of the NPC/source. |
| `firstSeenAt` | number | – | First observation of this source. |
| `lastSeenAt` | number | – | Last observation. |
| `timesSeen` | number | – | Number of observations. |
| `location` | Location | ✓ | `merchant`/`quest`: NPC location of the first observation. |
| `locations` | Location[] | ✓ | `loot`: drop locations, deduplicated (same `uiMapID`, `x`/`y` rounded to 0.001), max. 20. |

---

## 7. `MerchantSnapshot`

Replaced when a merchant is opened and on `MERCHANT_UPDATE`.

| Field | Type | Opt. | Description |
|---|---|---|---|
| `capturedAt` | number | – | Timestamp. |
| `character` | Character | – | Observing character (relevant for `isUsable`, `isPurchasable`). |
| `merchantNPC` | NPC | – | The merchant (incl. `location`). |
| `canRepair` | boolean | – | Merchant can repair. |
| `items` | MerchantItem[] | – | Inventory. |

### `MerchantItem`

| Field | Type | Opt. | Description |
|---|---|---|---|
| `index` | number | – | Position in the inventory. |
| `itemID` | number | ✓ | From `link`. |
| `name` | string | ✓ | Name. |
| `link` | string | ✓ | Item link. |
| `texture` | number/string | ✓ | Icon. |
| `price` | number | – | Price in copper (0 for pure extended cost). |
| `stackCount` | number | – | Quantity sold per purchase. |
| `maxStack` | number | ✓ | Maximum purchase quantity. |
| `numAvailable` | number | – | Available stock; `-1` = unlimited. |
| `isPurchasable` | boolean | – | Purchasable by the character. |
| `isUsable` | boolean | – | Usable by the character. |
| `hasExtendedCost` | boolean | – | Additional costs (items/tokens). |
| `extendedCost` | MerchantCost[] | ✓ | Only with `hasExtendedCost`. |

### `MerchantCost`

| Field | Type | Opt. | Description |
|---|---|---|---|
| `itemID` | number | ✓ | From `link`. |
| `name` | string | ✓ | Name. |
| `link` | string | ✓ | Item link. |
| `texture` | number/string | ✓ | Icon. |
| `count` | number | – | Required quantity. |

---

## 8. `LootSource`

`catalog.lootSources[key]`, keyed by `<sourceType>:<sourceID>`, or just `<sourceType>` without an ID (e.g. `Fishing`). Aggregated over all loot events; the same loot container (GUID) counts only once per session. With shared loot in a group (every loot method except Personal Loot), the addon reports opened corpse GUIDs to the group via addon message (prefix `ForeverCollect`, `L1:<guid>,<guid>…`); the other addons no longer count these corpses, so a kill is only counted by whoever opens it first. Profession finds (herbs, ore, skinning, fishing) get the profession name as a prefix: `Herbalism:GameObject:1617`, `Skinning:Creature:705`, `Fishing` – detected from the preceding gathering spell (`UNIT_SPELLCAST_SUCCEEDED`); skinning loot bypasses the container deduplication.

| Field | Type | Opt. | Description |
|---|---|---|---|
| `sourceType` | string | – | `Creature`, `GameObject`, `Fishing`, `Item` (container from the inventory), `Instance` (loot without a readable source GUID inside an instance, e.g. from hostile units whose GUIDs are secret there), `Unknown`. |
| `profession` | string | ✓ | `Herbalism`, `Mining`, `Skinning` or `Fishing` if the loot comes from a profession action. |
| `gatherSpellID` | number | ✓ | Spell ID of the gathering spell (e.g. 2366 Herb Gathering). |
| `sourceID` | number | ✓ | Creature/GameObject ID from the GUID; for `Instance` the instance ID from `GetInstanceInfo()`. Absent for `Fishing`, `Item` and `Unknown`. |
| `name` | string | ✓ | Name of the source if it was the target while looting; for herb/ore nodes the most recently shown tooltip title of the node. |
| `instanceID` | number | ✓ | Instance ID (`GetInstanceInfo()`, = map ID) of the last observation inside an instance. There `C_Map` provides no position and `locations` stays empty; the instance assigns the source to its dungeon. |
| `firstSeenAt` | number | – | First observation. |
| `lastSeenAt` | number | – | Last observation. |
| `lootCount` | number | – | Number of loot windows opened. |
| `locations` | Location[] \| CountedLocation[] | – | Player position per loot event, deduplicated, max. 100. For profession finds `CountedLocation` (3.1.1), max. 500. |
| `items` | map<number, LootItem> | – | Keyed by `itemID`. |
| `money` | table | – | `{ timesSeen: number, total: number }` – money drops, `total` in copper. |

### `LootItem`

| Field | Type | Opt. | Description |
|---|---|---|---|
| `itemID` | number | – | Item ID. |
| `name` | string | ✓ | Name. |
| `link` | string | – | Item link of the last observation. |
| `quality` | number | ✓ | Quality. |
| `isQuestItem` | boolean | – | Quest item. |
| `questID` | number | ✓ | Associated quest, if provided by the client. |
| `timesSeen` | number | – | Number of drops. |
| `quantityTotal` | number | – | Total quantity dropped. |
| `lastSeenAt` | number | – | Last observation. |
| `locations` | Location[] \| CountedLocation[] | – | Drop locations of this item, deduplicated, max. 20. For profession finds `CountedLocation` (3.1.1), max. 100. |

---

## 9. `TradeSkill` (removed)

No longer written (see section 13). Recipes, reagents, tools and cooldowns come from DB2 exports (wow.export) via the server importer.

---

## 10. `AbilitySnapshot` (removed)

No longer written since schema 9.1 (see section 13). The static spell catalog comes from DB2 exports (wow.export) via the server importer; the addon now only provides observations (trainers, talents, quests).

---

## 11. `Quest`

`catalog.quests[questID]`.

| Field | Type | Opt. | Description |
|---|---|---|---|
| `questID` | number | – | Quest ID. |
| `title` | string | ✓ | Title (from the most recently opened dialog). |
| `observations` | QuestObservation[] | – | Dialog observations in chronological order. |
| `turnIn` | table | ✓ | `{ capturedAt, xp: number?, money: number?, character: Character }` – actual turn-in (`QUEST_TURNED_IN`). |

### `QuestObservation`

| Field | Type | Opt. | Description |
|---|---|---|---|
| `phase` | string | – | `QUEST_DETAIL` (accept), `QUEST_PROGRESS` (progress), `QUEST_COMPLETE` (turn-in). |
| `capturedAt` | number | – | Timestamp. |
| `character` | Character | – | Character (quest texts can depend on class/race/level). |
| `questNPC` | NPC | – | Dialog partner with `role` `giver`/`progress`/`turnIn` and `location`. |
| `description` | string | ✓ | Only `QUEST_DETAIL`: quest text. The player's name, class and race are replaced back with the placeholders `$N`, `$C`/`$c`, `$R`/`$r`. |
| `objectives` | string | ✓ | Only `QUEST_DETAIL`: objective text (placeholders as in `description`). |
| `text` | string | ✓ | `QUEST_PROGRESS`: progress text; `QUEST_COMPLETE`: turn-in text (placeholders as in `description`). |
| `rewards` | QuestRewards | ✓ | `QUEST_DETAIL` and `QUEST_COMPLETE`. |
| `progress` | table | ✓ | Only `QUEST_PROGRESS`: `{ requiredItems: QuestItem[], requiredMoney: number? }`. |
| `tag` | table | ✓ | `QUEST_DETAIL`/`QUEST_COMPLETE`: `{ id: number, name: string? }` – quest type as in the quest log (81 Dungeon, 62 Raid, 1 Elite, 41 PvP, 21 Class …; IDs as in `QuestInfo`). Absent for quests without a tag. |
| `suggestedGroup` | number | ✓ | `QUEST_DETAIL`/`QUEST_COMPLETE`: suggested group size (`GetSuggestedGroupSize`), only if > 0. |

### `QuestRewards`

| Field | Type | Opt. | Description |
|---|---|---|---|
| `items` | QuestItem[] | – | Fixed rewards. |
| `choices` | QuestItem[] | – | Choice rewards. |
| `spells` | QuestSpell[] | – | Spell rewards. |
| `money` | number | ✓ | Money in copper. |
| `xp` | number | ✓ | Experience (level-dependent). |

### `QuestItem`

| Field | Type | Opt. | Description |
|---|---|---|---|
| `index` | number | – | Position. |
| `itemID` | number | ✓ | From `link`. |
| `name` | string | ✓ | Name. |
| `link` | string | ✓ | Item link. |
| `texture` | number/string | ✓ | Icon. |
| `quantity` | number | ✓ | Quantity. |
| `quality` | number | ✓ | Quality. |
| `isUsable` | boolean | ✓ | Usable by the character. |

Every `QuestItem` is also listed in the item catalog (section 6) with source `quest:<questID>`.

### `QuestSpell`

| Field | Type | Opt. | Description |
|---|---|---|---|
| `spellID` | number | ✓ | Spell ID (absent on the legacy API path). |
| `name` | string | ✓ | Name. |
| `texture` | number/string | ✓ | Icon. |
| `isTradeskill` | boolean | ✓ | Profession spell. |
| `isSpellLearned` | boolean | ✓ | Already known. |

---

## 12. `npcs`

List of `NPC` (section 3.4). An NPC appears exactly once; merging is done via `guid`, otherwise `npcID` + `name`, otherwise just `name`. `interactionTypes` collects all roles, `role` keeps the first. Merchant inventories and trainer services are not stored here but in `merchantSnapshots` and `trainerSnapshots` respectively (linked via the `NPCKey`).

---

## 14. `spellTooltips`

Map `spellID → SpellTooltip`. On Forever (trait system), the addon reads the tooltips of all ranks of every talent spell in the active trait configuration at login (delayed) and on `/fc scan`, via `GameTooltip:SetTraitEntry` (fallback `SetSpellByID`). The tree structure itself does not come from the addon but from the client's trait tables; the tooltips add the values ("Increases … by 2%") that the client only knows as placeholders. An entry is only written if the tooltip provides more than the name line (spell data loads late); existing entries are replaced on every scan.

### `SpellTooltip`

| Field | Type | Opt. | Description |
|---|---|---|---|
| `name` | string | ✓ | Spell name. |
| `lines` | TooltipLine[] | | Tooltip of rank 1 including the name line (section 3.3). |
| `ranks` | { rank: number, tooltipLines: TooltipLine[] }[] | ✓ | Tooltip per rank. |
| `capturedAt` | number | | Time of the scan. |

## 15. `encounters`

Map `encounterID → Encounter`. Between `ENCOUNTER_START` and `ENCOUNTER_END`, the addon collects the creature IDs of the boss units (`boss1`…`boss8`, `INSTANCE_ENCOUNTER_ENGAGE_UNIT`). They link a client `DungeonEncounter` row to the creatures whose loot is stored under `Creature:<npcID>` in `lootSources`.

### `Encounter`

| Field | Type | Opt. | Description |
|---|---|---|---|
| `encounterID` | number | – | `DungeonEncounter.db2` ID. |
| `name` | string | ✓ | Name from `ENCOUNTER_START`. |
| `difficultyID` | number | ✓ | Difficulty. |
| `instanceID` | number | ✓ | Instance ID (`GetInstanceInfo()`, = map ID). |
| `pulls` | number | – | Finished attempts. |
| `kills` | number | – | Of which successful. |
| `firstSeenAt`, `lastSeenAt` | number | – | First/last observation. |
| `npcs` | { npcID: number, name?: string, via: string }[] | – | Boss creatures; `via = "boss"` for boss units, `"target"` if no boss unit was visible and a dead creature was targeted after a win (less reliable). |

---

## 13. Legacy Data from Earlier Schema Versions

When the schema version is raised, existing data is **not** cleaned up. Catalogs created with version ≤ 8 may therefore additionally contain:

| Field | Origin | Note |
|---|---|---|
| `catalog.skillSnapshots` | ≤ 8 | Skill lines per character; no longer written. |
| `catalog.skillsScannedAt` | ≤ 8 | Corresponding timestamp. |
| `abilitySnapshots[*].spells` | ≤ 8 | Spellbook entries. Learned spells are represented via `trainerSnapshots` (`category = "used"`). |
| `abilitySnapshots`, `abilitiesScannedAt` | ≤ 9.0 | SoD runes per character; no longer written and never imported server-side. |
| `tradeSkills`, `tradeSkillsUpdatedAt` | ≤ 9.0 | Profession recipes from the profession/craft window; replaced by DB2 import (`SkillLineAbility`, `SpellReagents` …). Never imported server-side. |
| `items[*].detailsLoaded`, `name`, `quality`, `itemLevel`, `requiredLevel`, `itemType`, `itemSubType`, `stackCount`, `equipLoc`, `texture`, `sellPrice`, `classID`, `subclassID`, `bindType`, `expansionID`, `setID`, `isCraftingReagent`, `spell`, `stats`, `tooltipLines`, `updatedAt` | ≤ 9.0 | Item details from `GetItemInfo`/tooltip; replaced by DB2 import (`ItemSparse`). |
| `quests[*].observations[*].questNPC` without `interactionTypes`/`location.source` | ≤ 7 | Normalized on load (`addon.MigrateNPCData`). |

Catalogs first created with version 9 do not contain these fields.

## Changes Since Version 8

- New: `items`, `merchantSnapshots`, `lootSources`, `tradeSkills` and the timestamps `itemsUpdatedAt`, `merchantScanUpdatedAt`, `lootUpdatedAt`, `tradeSkillsUpdatedAt`.
- New: `trainerSnapshots` is actually filled (documented in 8, but empty).
- Removed: `skillSnapshots`, `skillsScannedAt`, `abilitySnapshots[*].spells` (see section 13).
- Added later (without a version bump, optional): `spellTooltips`, `spellTooltipsUpdatedAt` (section 14); `encounters` (section 15) and `lootSources[*].instanceID` (addon 0.1.10); `CountedLocation` with `count`/`firstSeenAt`/`lastSeenAt`/`times` for profession finds (addon 0.1.11).
- Removed later (without a version bump, fields were optional): `abilitySnapshots`, `abilitiesScannedAt` – rune scan dropped; `items[*]` details (`detailsLoaded` & co.) and `tradeSkills`/`tradeSkillsUpdatedAt` – static spell, item and recipe data comes from wow.export.
