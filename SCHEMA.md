# ForeverCollectDB – Schema Version 9

Dieses Dokument beschreibt vollständig die Struktur der SavedVariable `ForeverCollectDB`, wie sie von ForeverCollect mit `DATABASE_SCHEMA_VERSION = 9` (`Core/Database.lua`) geschrieben wird. Es ist die Referenz für Konsumenten, die die Datei `WTF/Account/<ACCOUNT>/SavedVariables/ForeverCollect.lua` einlesen.

## Konventionen

- **Typen**: `string`, `number` (Lua-Double; IDs und Zeitstempel sind ganzzahlig), `boolean`, `table`. Listen sind Tabellen mit fortlaufenden Integer-Schlüsseln ab 1 (`T[]`); Maps sind mit `map<K, V>` notiert.
- **Pflicht/Optional**: Spalte „Opt.“ – `–` = immer vorhanden, `✓` = kann fehlen. Ein fehlendes Feld ist in Lua `nil` und erscheint **nicht** in der serialisierten Datei. Leere Tabellen werden als `{}` geschrieben.
- **Zeitstempel** (`…At`) sind Unix-Sekunden (`time()`), UTC.
- **Lokalisierte Texte** (Namen, Beschreibungen, Tooltips) liegen in der Sprache des Clients (`catalog.locale`).
- **Koordinaten**: `x`/`y` sind auf 0–1 normierte Kartenkoordinaten der `uiMapID`; `worldX`/`worldY` sind Weltkoordinaten des Kontinents `worldContinentID`.
- Die Datei wird vom Client nur bei `/reload`, Logout oder Beenden geschrieben.

---

## 1. Wurzel: `ForeverCollectDB`

| Feld | Typ | Opt. | Beschreibung |
|---|---|---|---|
| `schemaVersion` | number | – | Schema-Version der Datei; wird beim Laden auf mindestens 9 angehoben. |
| `settings` | table | ✓ | Addon-Einstellungen, z. B. `verbose` (Chat-Meldungen je Erfassung, Standard `true`). Vom Server ignoriert. |
| `latestCatalogKey` | string | ✓ | Schlüssel des zuletzt verwendeten Katalogs in `catalogs`. Fehlt, bis ein Katalog angelegt wurde. |
| `catalogs` | map<string, Catalog> | – | Alle Kataloge, Schlüssel siehe unten. |

### Katalogschlüssel

```
<projectID>:<interfaceVersion>:<seasonID>:<locale>:<classID>:<raceID>:<factionFile>
```

Beispiel: `2:11509:2:enUS:5:8:Horde`. Ein Katalog ist also je Client-Projekt, Interface-Version, Saison, Sprache, Klasse, Rasse und Fraktion getrennt. Mehrere Charaktere mit gleicher Kombination teilen sich einen Katalog.

---

## 2. `Catalog`

### 2.1 Metadaten

| Feld | Typ | Opt. | Beschreibung |
|---|---|---|---|
| `schemaVersion` | number | – | Schema-Version, mit der der Katalog zuletzt geöffnet wurde (9). |
| `projectID` | number | – | `WOW_PROJECT_ID`; Classic Era = 2. |
| `version` | string | – | Client-Version, z. B. `"1.15.9"`. |
| `build` | string | – | Build-Nummer, z. B. `"69722"`. |
| `buildDate` | string | – | Build-Datum, z. B. `"Sep  4 2026"`. |
| `interfaceVersion` | number | – | Interface-Version, z. B. `11509`. |
| `locale` | string | – | Client-Sprache, z. B. `"enUS"`, `"deDE"`. |
| `classID` | number | – | Klassen-ID des Charakters. |
| `className` | string | – | Lokalisierter Klassenname. |
| `classFile` | string | – | Klassen-Token, z. B. `"PRIEST"`. |
| `raceID` | number | – | Rassen-ID. |
| `raceName` | string | – | Lokalisierter Rassenname. |
| `raceFile` | string | – | Rassen-Token, z. B. `"Troll"`. |
| `factionName` | string | – | Lokalisierter Fraktionsname. |
| `factionFile` | string | – | `"Alliance"` oder `"Horde"`. |
| `seasonID` | number | – | `C_Seasons.GetActiveSeason()`, 0 ohne Saison. |
| `seasonName` | string | – | `NoSeason` (0), `SeasonOfMastery` (1), `SeasonOfDiscovery` (2), `Hardcore` (3), `Fresh` (11), `FreshHardcore` (12), sonst `Unknown`. |
| `scannedAt` | number | – | Zeitpunkt der Katalog-Anlage bzw. des letzten Talent-Scans. |
| `questScanUpdatedAt` | number | ✓ | Letzte Quest-Beobachtung. |
| `npcScanUpdatedAt` | number | ✓ | Letzte NPC-Interaktion. |
| `trainerScanUpdatedAt` | number | ✓ | Letzter Trainer-Scan. |
| `itemsUpdatedAt` | number | ✓ | Letzte Änderung am Item-Katalog. |
| `merchantScanUpdatedAt` | number | ✓ | Letzter Händler-Scan. |
| `lootUpdatedAt` | number | ✓ | Letzte Loot-Beobachtung. |

### 2.2 Sammlungen

| Feld | Typ | Beschreibung | Abschnitt |
|---|---|---|---|
| `specializations` | Specialization[] | Talentbäume der Klasse | 4 |
| `trainerSnapshots` | map<NPCKey, TrainerSnapshot> | Dienste je Trainer-NPC | 5 |
| `items` | map<number, Item> | Item-Katalog, Schlüssel `itemID` | 6 |
| `merchantSnapshots` | map<NPCKey, MerchantSnapshot> | Sortiment je Händler-NPC | 7 |
| `lootSources` | map<string, LootSource> | Loot je Quelle | 8 |
| `quests` | map<number, Quest> | Quests, Schlüssel `questID` | 11 |
| `npcs` | NPC[] | NPC-Katalog | 12 |

Alle Sammlungen sind immer vorhanden (ggf. leer).

**`NPCKey`**: GUID des NPCs (`"Creature-0-…"`), falls keine GUID vorliegt `"<npcID>:<name>"` (`addon.GetNPCKey`).
**`CharacterKey`**: Spieler-GUID (`"Player-…"`), ersatzweise `"<Name>-<Realm>"`.

---

## 3. Gemeinsame Typen

### 3.1 `Location`

Position des Spielers zum Zeitpunkt einer Interaktion – eine Näherung an den Ort des NPCs/der Quelle.

| Feld | Typ | Opt. | Beschreibung |
|---|---|---|---|
| `source` | string | – | Immer `"playerAtInteraction"`. |
| `zone` | string | ✓ | `GetZoneText()`. |
| `subZone` | string | ✓ | `GetSubZoneText()`, kann leer sein. |
| `uiMapID` | number | ✓ | Karte des Spielers (`C_Map.GetBestMapForUnit`). |
| `mapName` | string | ✓ | Lokalisierter Kartenname. |
| `mapType` | number | ✓ | `Enum.UIMapType`. |
| `parentMapID` | number | ✓ | Übergeordnete Karte. |
| `x`, `y` | number | ✓ | Normierte Kartenkoordinaten (0–1). |
| `worldContinentID` | number | ✓ | Kontinent des Welt-Koordinatensystems. |
| `worldX`, `worldY` | number | ✓ | Weltkoordinaten. |

Alle Felder außer `source` fehlen, wenn der Client keine Kartendaten liefert (z. B. in Instanzen ohne Karte).

### 3.2 `Character`

Kontext des beobachtenden Charakters (`addon.GetCharacterContext`).

| Feld | Typ | Beschreibung |
|---|---|---|
| `name` | string | Charaktername |
| `realm` | string | Realmname |
| `level` | number | Level zum Zeitpunkt der Beobachtung |
| `race`, `raceName` | string | Lokalisierter Rassenname (beide identisch) |
| `raceFile` | string | Rassen-Token |
| `raceID` | number | Rassen-ID |
| `sex` | number | `UnitSex`: 2 = männlich, 3 = weiblich |
| `faction`, `factionFile` | string | `"Alliance"`/`"Horde"` (beide identisch) |
| `factionName` | string | Lokalisierter Fraktionsname |
| `className` | string | Lokalisierter Klassenname |
| `classFile` | string | Klassen-Token |
| `classID` | number | Klassen-ID |

### 3.3 `TooltipLine`

| Feld | Typ | Opt. | Beschreibung |
|---|---|---|---|
| `leftText` | string | ✓ | Linker Tooltip-Text der Zeile. |
| `rightText` | string | ✓ | Rechter Tooltip-Text der Zeile. |

Mindestens eines der beiden Felder ist gesetzt; Zeilen ohne Text werden ausgelassen.

### 3.4 `NPC`

| Feld | Typ | Opt. | Beschreibung |
|---|---|---|---|
| `role` | string | – | Rolle bei der ersten Beobachtung: `giver`, `progress`, `turnIn` (Quest), `merchant`, `trainer`, `banker`, `flightMaster`, `innkeeper`. |
| `guid` | string | ✓ | Unit-GUID. |
| `objectType` | string | ✓ | Erstes GUID-Segment, z. B. `"Creature"`, `"GameObject"`. |
| `objectID`, `npcID` | number | ✓ | Creature-ID (beide identisch). |
| `name` | string | ✓ | Lokalisierter Name. |
| `interactionTypes` | string[] | – | Alle beobachteten Interaktionen: `questGiver`, `merchant`, `trainer`, `banker`, `flightMaster`, `innkeeper`. |
| `creatureType` | string | – | `UnitCreatureType`, sonst `"Unknown"`. |
| `classification` | string | – | `UnitClassification` (`normal`, `elite`, `rare`, …), sonst `"unknown"`. |
| `location` | Location | – | Standort (siehe 3.1). |

---

## 4. `Specialization` (Talentbäume)

`catalog.specializations` wird bei jedem Talent-Scan vollständig ersetzt.

| Feld | Typ | Opt. | Beschreibung |
|---|---|---|---|
| `index` | number | – | Baum-Index (1–3). |
| `id` | number | ✓ | Spezialisierungs-ID. |
| `name` | string | ✓ | Lokalisierter Name. |
| `description` | string | ✓ | Beschreibung. |
| `icon` | number/string | ✓ | Icon (FileDataID oder Pfad). |
| `talents` | Talent[] | – | Talente des Baums. |

### `Talent`

| Feld | Typ | Opt. | Beschreibung |
|---|---|---|---|
| `index` | number | – | Talent-Index im Baum. |
| `talentID` | number | – | Talent-ID. |
| `spellID` | number | ✓ | Spell-ID des aktuellen Rangs. |
| `name` | string | – | Name. |
| `icon` | number/string | ✓ | Icon. |
| `tier` | number | – | Zeile im Baum. |
| `column` | number | – | Spalte im Baum. |
| `maxRank` | number | – | Maximaler Rang. |
| `tooltipLines` | TooltipLine[] | – | Tooltip des Talents. |

---

## 5. `TrainerSnapshot`

Wird beim Öffnen eines Trainers und bei Änderungen der Liste (`TRAINER_UPDATE`) ersetzt. Beim Scan sind alle Filter (`available`, `unavailable`, `used`) aktiv und alle Kategorien aufgeklappt, sodass die Liste vollständig ist.

Auf Clients der Mainline-Engine (Forever 1.60+) liefert die Trainer-API keine Header-Zeilen: `services` enthält dann nur Dienste (`isHeader = false`), `skillLine` stammt aus dem Kategorienamen der API, `link` und `description` fehlen, `requirements.level` kommt direkt aus `GetTrainerServiceInfo`.

| Feld | Typ | Opt. | Beschreibung |
|---|---|---|---|
| `capturedAt` | number | – | Zeitpunkt. |
| `character` | Character | – | Beobachtender Charakter (relevant für `category`). |
| `trainerNPC` | NPC | – | Der Trainer (inkl. `location`). |
| `greeting` | string | ✓ | `GetTrainerGreetingText()`. |
| `isTradeskillTrainer` | boolean | – | Berufstrainer. |
| `services` | TrainerService[] | – | Alle Listeneinträge inkl. Kategorie-Überschriften. |

### `TrainerService`

| Feld | Typ | Opt. | Beschreibung |
|---|---|---|---|
| `index` | number | – | Listenindex beim Scan. |
| `name` | string | – | Name des Dienstes bzw. der Überschrift. |
| `rank` | string | ✓ | Rang des Dienstes, z. B. `"Rank 2"`. Vom Client-Untertext, sonst über die Spell-ID (`GetSpellSubtext`/`GetSpellInfo`). Fehlt bei Headern und ranglosen Zaubern. |
| `category` | string | – | `header`, `available`, `unavailable` oder `used` (bereits gelernt). Abhängig vom Charakter. |
| `isHeader` | boolean | – | `category == "header"`. |
| `isExpanded` | boolean | – | Aufgeklappt-Zustand beim Scan (Header). |
| `isAvailable` | boolean | – | `category == "available"`. |
| `isKnown` | boolean | – | `category == "used"`. |
| `skillLine` | string | ✓ | Name der zuletzt gelesenen Überschrift. |

Nur für Nicht-Header (`isHeader == false`):

| Feld | Typ | Opt. | Beschreibung |
|---|---|---|---|
| `link` | string | ✓ | Spell-/Enchant-Link. |
| `spellID` | number | ✓ | Aus `link` (`spell:` oder `enchant:`), sonst aus dem Tooltip des Dienstes (`GetTooltipSpellID`). Fehlt nur, wenn der Client für den Dienst keinen Spell liefert. |
| `icon` | number/string | ✓ | Icon. |
| `description` | string | ✓ | Beschreibung. |
| `moneyCost` | number | ✓ | Kosten in Kupfer. |
| `talentCost` | number | ✓ | Talentpunkte. |
| `professionCost` | number | ✓ | Berufspunkte. |
| `requirements` | TrainerRequirements | – | Voraussetzungen. |
| `tooltipLines` | TooltipLine[] | – | Tooltip des Dienstes. |

### `TrainerRequirements`

| Feld | Typ | Opt. | Beschreibung |
|---|---|---|---|
| `level` | number | ✓ | Benötigtes Level. |
| `skill` | table | ✓ | `{ name: string, rank: number, isMet: boolean }` – benötigte Fertigkeit. |
| `abilities` | table[] | – | Je `{ name: string, isMet: boolean }` – benötigte Fähigkeiten (kann leer sein). `name` bezeichnet den **vorausgesetzten** Zauber inkl. Rang-Suffix (i. d. R. den Vorgänger-Rang, z. B. `"Power Word: Fortitude (Rank 1)"` für den Dienst Rang 2), nicht den Dienst selbst. |

---

## 6. `Item` (Item-Katalog)

`catalog.items[itemID]`. Einträge werden nur über Quellen angelegt (Händler, Quests, Loot, Rezepte) und nie gelöscht.

| Feld | Typ | Opt. | Beschreibung |
|---|---|---|---|
| `itemID` | number | – | Item-ID. |
| `link` | string | ✓ | Erster gesehener Item-Link (kann Suffix/Zufallsverzauberung enthalten). |
| `firstSeenAt` | number | – | Erste Beobachtung. |
| `lastSeenAt` | number | – | Letzte Beobachtung. |
| `sources` | map<string, ItemSource> | – | Fundorte, Schlüssel siehe 6.2. |

Statische Item-Daten (Name, Qualität, Level, Stats, Preis, Bindung, Icon …) stammen aus den DB2-Tabellen `Item`/`ItemSparse`/`ItemSearchName` (wow.export → Server-Importer) und werden nicht mehr im Spiel gelesen.

### 6.2 `ItemSource`

Schlüssel: `merchant:<npcID>`, `quest:<questID>`, `loot:<sourceType>:<sourceID>`, bei Berufsfunden `loot:<profession>:<sourceType>:<sourceID>`.

| Feld | Typ | Opt. | Beschreibung |
|---|---|---|---|
| `type` | string | – | `merchant`, `quest`, `loot`. |
| `npcID` | number | ✓ | Nur `merchant`. |
| `questID` | number | ✓ | Nur `quest`. |
| `sourceType` | string | ✓ | Nur `loot`: `Creature`, `GameObject`, `Fishing`, … |
| `sourceID` | number | ✓ | Nur `loot`: Creature-/Objekt-ID; fehlt bei `Fishing`. |
| `profession` | string | ✓ | Nur `loot` aus Berufsaktionen: `Herbalism`, `Mining`, `Skinning`, `Fishing`. |
| `name` | string | ✓ | Name des NPCs/der Quelle. |
| `firstSeenAt` | number | – | Erste Beobachtung dieser Quelle. |
| `lastSeenAt` | number | – | Letzte Beobachtung. |
| `timesSeen` | number | – | Anzahl Beobachtungen. |
| `location` | Location | ✓ | `merchant`/`quest`: NPC-Standort der ersten Beobachtung. |
| `locations` | Location[] | ✓ | `loot`: Drop-Orte, dedupliziert (gleiche `uiMapID`, `x`/`y` auf 0,001 gerundet), max. 20. |

---

## 7. `MerchantSnapshot`

Wird beim Öffnen eines Händlers und bei `MERCHANT_UPDATE` ersetzt.

| Feld | Typ | Opt. | Beschreibung |
|---|---|---|---|
| `capturedAt` | number | – | Zeitpunkt. |
| `character` | Character | – | Beobachtender Charakter (relevant für `isUsable`, `isPurchasable`). |
| `merchantNPC` | NPC | – | Der Händler (inkl. `location`). |
| `canRepair` | boolean | – | Händler repariert. |
| `items` | MerchantItem[] | – | Sortiment. |

### `MerchantItem`

| Feld | Typ | Opt. | Beschreibung |
|---|---|---|---|
| `index` | number | – | Position im Sortiment. |
| `itemID` | number | ✓ | Aus `link`. |
| `name` | string | ✓ | Name. |
| `link` | string | ✓ | Item-Link. |
| `texture` | number/string | ✓ | Icon. |
| `price` | number | – | Preis in Kupfer (0 bei reinem Extended Cost). |
| `stackCount` | number | – | Verkaufte Menge pro Kauf. |
| `maxStack` | number | ✓ | Maximale Kaufmenge. |
| `numAvailable` | number | – | Verfügbarer Vorrat; `-1` = unbegrenzt. |
| `isPurchasable` | boolean | – | Kaufbar für den Charakter. |
| `isUsable` | boolean | – | Benutzbar durch den Charakter. |
| `hasExtendedCost` | boolean | – | Zusatzkosten (Items/Marken). |
| `extendedCost` | MerchantCost[] | ✓ | Nur bei `hasExtendedCost`. |

### `MerchantCost`

| Feld | Typ | Opt. | Beschreibung |
|---|---|---|---|
| `itemID` | number | ✓ | Aus `link`. |
| `name` | string | ✓ | Name. |
| `link` | string | ✓ | Item-Link. |
| `texture` | number/string | ✓ | Icon. |
| `count` | number | – | Benötigte Anzahl. |

---

## 8. `LootSource`

`catalog.lootSources[key]`, Schlüssel `<sourceType>:<sourceID>` bzw. nur `<sourceType>` ohne ID (z. B. `Fishing`). Aggregiert über alle Loot-Vorgänge; derselbe Loot-Container (GUID) zählt pro Sitzung nur einmal. Berufsfunde (Kräuter, Erz, Kürschnern, Angeln) erhalten den Berufsnamen als Präfix: `Herbalism:GameObject:1617`, `Skinning:Creature:705`, `Fishing` – erkannt am vorangegangenen Sammel-Zauber (`UNIT_SPELLCAST_SUCCEEDED`), Kürschner-Loot umgeht dabei die Container-Deduplizierung.

| Feld | Typ | Opt. | Beschreibung |
|---|---|---|---|
| `sourceType` | string | – | `Creature`, `GameObject`, `Fishing`, `Item` (Behälter aus dem Inventar), `Unknown`. |
| `profession` | string | ✓ | `Herbalism`, `Mining`, `Skinning` oder `Fishing`, wenn der Loot aus einer Berufsaktion stammt. |
| `gatherSpellID` | number | ✓ | Spell-ID des Sammel-Zaubers (z. B. 2366 Herb Gathering). |
| `sourceID` | number | ✓ | Creature-/GameObject-ID aus der GUID. Fehlt bei `Fishing`, `Item` und `Unknown`. |
| `name` | string | ✓ | Name der Quelle, falls sie beim Plündern das Ziel war; bei Kräuter-/Erzknoten der zuletzt angezeigte Tooltip-Titel des Knotens. |
| `firstSeenAt` | number | – | Erste Beobachtung. |
| `lastSeenAt` | number | – | Letzte Beobachtung. |
| `lootCount` | number | – | Anzahl geöffneter Loot-Fenster. |
| `locations` | Location[] | – | Spielerposition je Loot-Vorgang, dedupliziert, max. 100. |
| `items` | map<number, LootItem> | – | Schlüssel `itemID`. |
| `money` | table | – | `{ timesSeen: number, total: number }` – Geld-Drops, `total` in Kupfer. |

### `LootItem`

| Feld | Typ | Opt. | Beschreibung |
|---|---|---|---|
| `itemID` | number | – | Item-ID. |
| `name` | string | ✓ | Name. |
| `link` | string | – | Item-Link der letzten Beobachtung. |
| `quality` | number | ✓ | Qualität. |
| `isQuestItem` | boolean | – | Questgegenstand. |
| `questID` | number | ✓ | Zugehörige Quest, falls vom Client geliefert. |
| `timesSeen` | number | – | Anzahl Drops. |
| `quantityTotal` | number | – | Summe der gedroppten Menge. |
| `lastSeenAt` | number | – | Letzte Beobachtung. |
| `locations` | Location[] | – | Drop-Orte dieses Items, dedupliziert, max. 20. |

---

## 9. `TradeSkill` (entfallen)

Wird nicht mehr geschrieben (siehe Abschnitt 13). Rezepte, Reagenzien, Werkzeuge und Cooldowns kommen aus DB2-Exporten (wow.export) über den Server-Importer.

---

## 10. `AbilitySnapshot` (entfallen)

Wird seit Schema 9.1 nicht mehr geschrieben (siehe Abschnitt 13). Der statische Zauberkatalog kommt aus DB2-Exporten (wow.export) über den Server-Importer; das Addon liefert nur noch Beobachtungen (Trainer, Talente, Quests).

---

## 11. `Quest`

`catalog.quests[questID]`.

| Feld | Typ | Opt. | Beschreibung |
|---|---|---|---|
| `questID` | number | – | Quest-ID. |
| `title` | string | ✓ | Titel (aus dem zuletzt geöffneten Dialog). |
| `observations` | QuestObservation[] | – | Dialogbeobachtungen in zeitlicher Reihenfolge. |
| `turnIn` | table | ✓ | `{ capturedAt, xp: number?, money: number?, character: Character }` – tatsächliche Abgabe (`QUEST_TURNED_IN`). |

### `QuestObservation`

| Feld | Typ | Opt. | Beschreibung |
|---|---|---|---|
| `phase` | string | – | `QUEST_DETAIL` (Annahme), `QUEST_PROGRESS` (Fortschritt), `QUEST_COMPLETE` (Abgabe). |
| `capturedAt` | number | – | Zeitpunkt. |
| `character` | Character | – | Charakter (Questtexte können von Klasse/Rasse/Level abhängen). |
| `questNPC` | NPC | – | Dialogpartner mit `role` `giver`/`progress`/`turnIn` und `location`. |
| `description` | string | ✓ | Nur `QUEST_DETAIL`: Questtext. |
| `objectives` | string | ✓ | Nur `QUEST_DETAIL`: Zieltext. |
| `text` | string | ✓ | `QUEST_PROGRESS`: Fortschrittstext; `QUEST_COMPLETE`: Abgabetext. |
| `rewards` | QuestRewards | ✓ | `QUEST_DETAIL` und `QUEST_COMPLETE`. |
| `progress` | table | ✓ | Nur `QUEST_PROGRESS`: `{ requiredItems: QuestItem[], requiredMoney: number? }`. |
| `tag` | table | ✓ | `QUEST_DETAIL`/`QUEST_COMPLETE`: `{ id: number, name: string? }` – Quest-Typ wie im Questlog (81 Dungeon, 62 Raid, 1 Elite, 41 PvP, 21 Klasse …; IDs wie `QuestInfo`). Fehlt bei Quests ohne Tag. |
| `suggestedGroup` | number | ✓ | `QUEST_DETAIL`/`QUEST_COMPLETE`: empfohlene Gruppengröße (`GetSuggestedGroupSize`), nur wenn > 0. |

### `QuestRewards`

| Feld | Typ | Opt. | Beschreibung |
|---|---|---|---|
| `items` | QuestItem[] | – | Feste Belohnungen. |
| `choices` | QuestItem[] | – | Wahlbelohnungen. |
| `spells` | QuestSpell[] | – | Zauberbelohnungen. |
| `money` | number | ✓ | Geld in Kupfer. |
| `xp` | number | ✓ | Erfahrung (levelabhängig). |

### `QuestItem`

| Feld | Typ | Opt. | Beschreibung |
|---|---|---|---|
| `index` | number | – | Position. |
| `itemID` | number | ✓ | Aus `link`. |
| `name` | string | ✓ | Name. |
| `link` | string | ✓ | Item-Link. |
| `texture` | number/string | ✓ | Icon. |
| `quantity` | number | ✓ | Menge. |
| `quality` | number | ✓ | Qualität. |
| `isUsable` | boolean | ✓ | Benutzbar durch den Charakter. |

Jedes `QuestItem` wird zusätzlich im Item-Katalog (Abschnitt 6) mit Quelle `quest:<questID>` geführt.

### `QuestSpell`

| Feld | Typ | Opt. | Beschreibung |
|---|---|---|---|
| `spellID` | number | ✓ | Spell-ID (fehlt beim Legacy-API-Pfad). |
| `name` | string | ✓ | Name. |
| `texture` | number/string | ✓ | Icon. |
| `isTradeskill` | boolean | ✓ | Berufszauber. |
| `isSpellLearned` | boolean | ✓ | Bereits bekannt. |

---

## 12. `npcs`

Liste von `NPC` (Abschnitt 3.4). Ein NPC erscheint genau einmal; Zusammenführung erfolgt über `guid`, sonst `npcID` + `name`, sonst nur `name`. `interactionTypes` sammelt alle Rollen, `role` behält die erste. Händler-Sortiment und Trainer-Dienste liegen nicht hier, sondern in `merchantSnapshots` bzw. `trainerSnapshots` (verknüpft über den `NPCKey`).

---

## 13. Altlasten aus früheren Schema-Versionen

Beim Anheben der Schema-Version werden vorhandene Daten **nicht** bereinigt. In Katalogen, die mit Version ≤ 8 angelegt wurden, können daher zusätzlich vorkommen:

| Feld | Herkunft | Hinweis |
|---|---|---|
| `catalog.skillSnapshots` | ≤ 8 | Fertigkeitslinien pro Charakter; wird nicht mehr geschrieben. |
| `catalog.skillsScannedAt` | ≤ 8 | Zeitstempel dazu. |
| `abilitySnapshots[*].spells` | ≤ 8 | Zauberbuch-Einträge. Gelernte Zauber sind über `trainerSnapshots` (`category = "used"`) abgebildet. |
| `abilitySnapshots`, `abilitiesScannedAt` | ≤ 9.0 | SoD-Runen je Charakter; wird nicht mehr geschrieben und serverseitig nie importiert. |
| `tradeSkills`, `tradeSkillsUpdatedAt` | ≤ 9.0 | Berufsrezepte aus Berufs-/Craft-Fenster; ersetzt durch DB2-Import (`SkillLineAbility`, `SpellReagents` …). Serverseitig nie importiert. |
| `items[*].detailsLoaded`, `name`, `quality`, `itemLevel`, `requiredLevel`, `itemType`, `itemSubType`, `stackCount`, `equipLoc`, `texture`, `sellPrice`, `classID`, `subclassID`, `bindType`, `expansionID`, `setID`, `isCraftingReagent`, `spell`, `stats`, `tooltipLines`, `updatedAt` | ≤ 9.0 | Item-Details aus `GetItemInfo`/Tooltip; ersetzt durch DB2-Import (`ItemSparse`). |
| `quests[*].observations[*].questNPC` ohne `interactionTypes`/`location.source` | ≤ 7 | Wird beim Laden normalisiert (`addon.MigrateNPCData`). |

Kataloge, die mit Version 9 erstmals angelegt werden, enthalten diese Felder nicht.

## Änderungen gegenüber Version 8

- Neu: `items`, `merchantSnapshots`, `lootSources`, `tradeSkills` und die Zeitstempel `itemsUpdatedAt`, `merchantScanUpdatedAt`, `lootUpdatedAt`, `tradeSkillsUpdatedAt`.
- Neu: `trainerSnapshots` wird tatsächlich befüllt (in 8 dokumentiert, aber leer).
- Entfernt: `skillSnapshots`, `skillsScannedAt`, `abilitySnapshots[*].spells` (siehe Abschnitt 13).
- Später entfernt (ohne Versionssprung, Felder waren optional): `abilitySnapshots`, `abilitiesScannedAt` – Runen-Scan gestrichen; `items[*]`-Details (`detailsLoaded` & Co.) und `tradeSkills`/`tradeSkillsUpdatedAt` – statische Zauber-, Item- und Rezeptdaten kommen aus wow.export.
