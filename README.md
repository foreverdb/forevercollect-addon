# ForeverCollect

ForeverCollect katalogisiert beobachtete Daten aus World of Warcraft Classic Era und Forever (1.60+). Die Daten werden in der SavedVariable `ForeverCollectDB` gespeichert. Die vollständige Feldreferenz des aktuellen Schemas (Version 9) steht in [SCHEMA.md](SCHEMA.md).

## Installation

Das Zip des neuesten [GitHub-Releases](https://github.com/foreverdb/forevercollect-addon/releases) nach `Interface/AddOns/` des jeweiligen Clients entpacken (es enthält den Ordner `ForeverCollect/`). Für die Entwicklung kopiert `./deploy.sh` das Arbeitsverzeichnis direkt in die installierten Clients.

## Release

Die Version steht in `ForeverCollect.toc` (`## Version:`). Wird sie auf `main` erhöht, prüft der Workflow `.github/workflows/release.yml` die Lua-Syntax, packt `ForeverCollect-vX.Y.Z.zip` und legt Tag und Release `vX.Y.Z` mit automatischen Release-Notes an. Ein Push ohne Versionsänderung oder mit bereits vorhandenem Tag erzeugt kein Release. `check.yml` prüft bei jedem Push und Pull Request die Syntax und ob alle in der TOC gelisteten Dateien existieren.

## Verwendung

```text
/fc scan      Talente scannen (Forever: Talent-Tooltips)
/fc talents   Talentdaten des aktuellen Katalogs anzeigen
/fc traits    Trait-Bäume des Clients diagnostizieren (Forever)
/fc trainer   Trainerdienste scannen und Anzahl erfasster Daten anzeigen
/fc items     Anzahl erfasster Items anzeigen
/fc merchants Händler-Sortimente anzeigen
/fc loot      Loot-Quellen und -Items anzeigen
/fc quests    Anzahl erfasster Quests und Beobachtungen anzeigen
/fc questcache Alle Quests beim Server abfragen (stop, status, reset)
/fc status    Katalogkontext und Scanstatus anzeigen
/fc verbose   Meldungen bei jeder Erfassung ein-/ausschalten (Standard: an)
/fc save      Gesammelte Daten jetzt sichern (lädt das UI neu)
/fc autosave  Automatisch sichern: /fc autosave 30 (Minuten) oder /fc autosave off
```

Jede Erfassung (Quest-Dialog, Abgabe, Loot, Händler, Trainer, Bankier, Flugmeister) wird im Chat gemeldet; `/fc verbose` schaltet diese Meldungen aus und wieder ein (Einstellung in `ForeverCollectDB.settings`, nicht Teil der Uploads).

**Quest-Typ:** Bei jeder Annahme und Abgabe wird der Quest-Typ aus dem Questlog mitgeschrieben (`tag`: Dungeon, Raid, Elite, PvP …, plus `suggestedGroup`). Bereits erfasste Quests bekommen den Typ, sobald sie erneut angenommen oder abgegeben werden.

**Quest-Katalog:** Die Questdaten der Website kommen aus dem Client (`QuestV2.db2` und dem Quest-Cache `Cache/WDB/<locale>/questcache.wdb`); die Beobachtungen ergänzen NPCs, Fortschritts- und Abgabetexte. Der Cache enthält nur Quests, die der Client schon beim Server abgefragt hat. `/fc questcache` fragt alle IDs aus `Data/QuestIDs.lua` gedrosselt ab (20/s, gut 5 Minuten, fortsetzbar); danach ausloggen, damit der Client den Cache schreibt, und `foreverdb-import all` ausführen.

**Speichern:** WoW schreibt Addon-Daten nur beim Ausloggen, Beenden oder `/reload` auf die Platte – alles seit dem letzten Speichern lebt nur im Speicher und geht bei einem Absturz oder abgeschossenen Prozess verloren. Das Addon zählt deshalb die Erfassungen seit dem letzten Speichern, erinnert nach 50 Erfassungen bzw. 30 Minuten mit einem Popup („Save now“ lädt das UI neu, „Later“ verschiebt) und im Chat an `/fc save` (ein UI-Reload, nie im Kampf, beim Zaubern oder mit offenem Dialog) und kann mit `/fc autosave <Minuten>` selbstständig neu laden, sobald gerade nichts läuft. `/fc status` zeigt die ungesicherten Erfassungen.

WoW schreibt die Daten nach `/reload`, Logout oder Beenden in:

```text
WTF/Account/<ACCOUNT>/SavedVariables/ForeverCollect.lua
```

## Skripte

```sh
./deploy.sh           # kopiert das Addon in _classic_era_ und _classic_beta_ (Forever)
```

Hochgeladen wird über den ForeverDB-Client (`foreverdb-client`): Der Ingress nimmt nur noch den fertigen JSON-Snapshot entgegen, die Umwandlung der SavedVariables passiert im Client. Das frühere `upload.sh` konnte das nicht leisten und ist entfallen.

## Projektstruktur

Die Dateien werden in der Reihenfolge aus `ForeverCollect.toc` geladen und teilen sich die Addon-Tabelle (`local _, addon = ...`). Module hängen nur das an `addon`, was andere Dateien brauchen, und registrieren ihre Events und Slash-Subcommands selbst über `addon:RegisterEvent(event, handler)` bzw. `addon:RegisterCommand(name, handler, help)`.

```text
Core/Util.lua           Chat-Ausgabe, Tooltip-Scanner, kleine Helfer
Core/Database.lua       ForeverCollectDB, Client-/Charakterkontext, Katalogverwaltung
Core/Registry.lua       Event-Frame und Dispatcher für Events und Slash-Commands
Modules/NPCs.lua        NPC-Erfassung und -Zusammenführung (Händler, Trainer, Bank, Flugmeister)
Core/Autosave.lua       Ungesicherte Erfassungen, /fc save, /fc autosave
Modules/Items.lua       Item-Katalog mit Quellen und Koordinaten (/fc items)
Modules/Merchants.lua   Händler-Sortimente (/fc merchants)
Modules/Gathering.lua   Erkennt Sammel-Zauber (Kräuter, Erz, Kürschnern, Angeln) und Knotennamen per Tooltip
Modules/Loot.lua        Loot-Quellen und Drop-Orte (/fc loot)
Modules/Talents.lua     Talentbäume über die Classic-API (/fc talents)
Modules/Traits.lua      Talent-Tooltips über das Trait-System auf Forever (/fc traits)
Modules/Trainers.lua    Trainerdienste (/fc trainer)
Modules/Quests.lua      Questdialoge und Abgaben (/fc quests)
Modules/QuestCache.lua  Fragt alle Quests aus Data/QuestIDs.lua beim Server ab (/fc questcache)
Data/QuestIDs.lua       Quest-IDs aus QuestV2.db2, erzeugt mit `foreverdb-import quest-ids`
ForeverCollect.lua      Einstieg: Laden, Login-Scan, /fc help, /fc scan, /fc status
```

## Chat-Feedback

Wenn neue Daten erfolgreich erfasst wurden, erscheint eine Meldung mit dem Präfix `New data captured` im Chat. Wiederholte automatische Aktualisierungen ohne neue Einträge bleiben still, um Chatspam zu vermeiden. Manuelle Scans zeigen weiterhin ihre zusammenfassende Scanmeldung.

## Oberste Ebene

```lua
ForeverCollectDB = {
    schemaVersion = 9,
    latestCatalogKey = "...",
    catalogs = {
        [catalogKey] = catalog,
    },
}
```

| Feld | Typ | Beschreibung |
| --- | --- | --- |
| `schemaVersion` | number | Aktuelle Datenbankschema-Version. Zurzeit `9`. |
| `latestCatalogKey` | string | Schlüssel des zuletzt verwendeten Katalogs. |
| `catalogs` | table | Kataloge, nach Client- und Charakterkontext gruppiert. |

## Katalogschlüssel

Jeder Katalog wird unter folgendem Schlüssel gespeichert:

```text
projectID:interfaceVersion:seasonID:locale:classID:raceID:factionFile
```

Beispiel:

```text
2:11509:2:enUS:8:3:Alliance
```

Der Schlüssel trennt Talentdaten für unterschiedliche Klassen, Rassen und Fraktionen. Die Locale bleibt ebenfalls Teil des Schlüssels, weil Namen, Beschreibungen und Tooltip-Texte lokalisiert sind.

## Katalog-Metadaten

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

`scannedAt`, `questScanUpdatedAt`, `trainerScanUpdatedAt`, `itemsUpdatedAt`, `merchantScanUpdatedAt` und `lootUpdatedAt` enthalten Unix-Zeitstempel.

## Talente

`specializations` ist ein Array der Talentbäume, gelesen über die Tab/Tier-API von Classic Era (`Modules/Talents.lua`). Forever (1.60+) baut seine Talente auf dem Trait-System (`C_Traits`) auf; dort bleibt `specializations` leer – Baumstruktur, Ränge und Voraussetzungen kommen aus den Trait-Tabellen des Clients (`TraitNode`, `TraitEdge`), die der Importer einliest. Was nur das Spiel kennt, sind die Tooltip-Texte mit ihren Werten: `Modules/Traits.lua` läuft beim Login (5 s verzögert) und bei `/fc scan` über die aktive Trait-Konfiguration und legt je Talent-Spell die Tooltips aller Ränge in `spellTooltips` ab. `/fc traits` zeigt, was der Client liefert. Automatische Scans melden sich nur einmal pro Sitzung; warum auf Forever keine Bäume gescannt werden, erklärt nur `/fc scan`.

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

| Feld | Beschreibung |
| --- | --- |
| `specializations[].index` | Position des Talentbaums im Client. |
| `specializations[].id` | ID des Talentbaums beziehungsweise der Spezialisierung. |
| `talents[].talentID` | Eindeutige Talent-ID. |
| `talents[].spellID` | Zugehörige Zauber-ID. |
| `talents[].tier`, `column` | Position im Talentbaum. |
| `talents[].maxRank` | Maximale Rangstufe. |
| `tooltipLines` | Lokalisierte Tooltip-Zeilen als linke und rechte Textspalte. |

Die Talentdaten beschreiben den verfügbaren Baum. Der aktuelle Charakterkontext wird durch den Katalogschlüssel festgelegt.

## Trainer-Skills

`trainerSnapshots` wird automatisch aktualisiert, sobald ein Trainer geöffnet wird (`TRAINER_SHOW`) oder sich die Trainerliste ändert (`TRAINER_UPDATE`, z. B. nach dem Erlernen). Der Schlüssel ist die NPC-GUID; falls diese nicht verfügbar ist, wird die NPC-ID zusammen mit dem Namen verwendet.

Beim Scannen werden vorübergehend alle Filter (`available`, `unavailable`, `used`) aktiviert und alle Kategorien aufgeklappt, sodass auch bereits gelernte und noch nicht verfügbare Dienste erfasst werden. Der vorherige UI-Zustand wird danach wiederhergestellt.

Das Modul unterstützt beide API-Generationen: die Classic-Liste mit Header-Zeilen (`ExpandTrainerSkillLine`) und die flache Mainline-Liste von Forever 1.60+ (`GetTrainerServiceInfo` liefert dort `name, serviceType, texture, reqLevel, subText, category`).

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

`category` ist `header`, `available`, `unavailable` oder `used` (bereits gelernt). `skillLine` ist der Name der zuletzt gelesenen Kategorie-Überschrift. `spellID` wird aus `link` gelesen (`spell:` oder `enchant:`). `requirements.skill` und `requirements.level` fehlen, wenn der Dienst keine entsprechende Voraussetzung hat. Ein erneutes Öffnen desselben Trainers ersetzt den bisherigen Snapshot.

## Items

`items` ist ein deduplizierter Katalog aller beobachteten Items, Schlüssel ist die `itemID`. Er wird ausschließlich über Quellen befüllt (Händler, Quests, Loot, Rezepte); Taschen- oder Ausrüstungsinhalte werden nicht erfasst.

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

Das Addon erfasst nur, **wo** ein Item gesehen wurde. Statische Item-Daten (Name, Qualität, Stats, Verkaufspreis, Bindung …) kommen aus den DB2-Tabellen des Clients (`Item`, `ItemSparse`, `ItemSearchName`) über den Server-Importer und werden nicht mehr im Spiel gelesen.

`sources` verknüpft jedes Item mit seinen Fundorten. Händler- und Quest-Quellen tragen die `location` des NPCs (Format wie unter „Quest-NPC und Ort“), Loot-Quellen eine Liste `locations` mit den Spielerpositionen beim Plündern (dedupliziert auf ca. 0,1 % Kartenauflösung, maximal 20 Einträge). Rezept-Quellen haben keine Weltkoordinate.

## Händler

Händlerdaten werden über `GetMerchantItemInfo` gelesen, auf Forever 1.60+ über `C_MerchantFrame.GetItemInfo`.

`merchantSnapshots` wird beim Öffnen eines Händlers (`MERCHANT_SHOW`) und bei Änderungen des Sortiments (`MERCHANT_UPDATE`) aktualisiert. Der Schlüssel ist die NPC-GUID, sonst `npcID:name`. Ein erneutes Öffnen ersetzt den Snapshot.

```lua
merchantSnapshots = {
    ["Creature-0-..."] = {
        capturedAt = 0,
        character = {},
        merchantNPC = {},          -- NPC-Objekt inkl. location
        canRepair = false,
        items = {
            {
                index = 1,
                itemID = 12345,
                name = "Example Item",
                link = "...",
                texture = 123456,
                price = 250,          -- Kupfer
                stackCount = 1,
                maxStack = 5,
                numAvailable = -1,    -- -1 = unbegrenzt
                isPurchasable = true,
                isUsable = true,
                hasExtendedCost = false,
                extendedCost = {      -- nur bei hasExtendedCost
                    { itemID = 1, name = "Token", link = "...", texture = 1, count = 3 },
                },
            },
        },
    },
}
```

## Loot

`lootSources` aggregiert Loot-Beobachtungen pro Quelle (`LOOT_OPENED`). Der Schlüssel ist `<sourceType>:<sourceID>` aus der Quell-GUID (`Creature`, `GameObject`), `Fishing` beim Angeln. In Instanzen sind die GUIDs feindlicher Einheiten geheim; solcher Loot landet unter `Instance:<instanceID>` mit dem Instanznamen als `name`. Derselbe Loot-Container zählt pro Sitzung nur einmal (ohne GUID, also bei `Instance`, lässt sich das nicht erkennen).

```lua
lootSources = {
    ["Creature:456"] = {
        sourceType = "Creature",
        sourceID = 456,
        name = "Mob",              -- falls die Quelle das aktuelle Ziel war
        lootCount = 3,             -- geöffnete Loot-Fenster
        firstSeenAt = 0,
        lastSeenAt = 0,
        locations = { {} },        -- Spielerposition je Loot-Vorgang, max. 100
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
                locations = { {} },  -- Drop-Orte dieses Items, max. 20
            },
        },
        money = { timesSeen = 3, total = 1234 },  -- Kupfer
    },
}
```

## Berufe

Rezepte werden nicht mehr im Spiel gelesen. Rezept↔Beruf, Reagenzien, Werkzeuge, Cooldowns und Lernquellen kommen aus den DB2-Tabellen (`SkillLineAbility`, `SpellReagents`, `SpellTotems`, `SpellCooldowns`, `SpellCastingRequirements`, `ItemEffect`) über den Server-Importer.

## Quests

`quests` wird nach Quest-ID indiziert:

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

### Quest-Phasen

| Phase | Erfasste Daten |
| --- | --- |
| `QUEST_DETAIL` | Titel, Annahmetext, Ziele und angebotene Belohnungen. |
| `QUEST_PROGRESS` | Fortschrittstext, benötigte Items und benötigtes Geld. |
| `QUEST_COMPLETE` | Abschlusstext und finale Belohnungen. |
| `QUEST_ITEM_UPDATE` | Aktualisiert Itemdaten im zuletzt aktiven Dialog, wenn sie verzögert geladen wurden. |
| `QUEST_TURNED_IN` | Tatsächlich gewährte XP und Geldbelohnung. |

### Quest-NPC und Ort

Jede direkte Dialogbeobachtung enthält ein optionales `questNPC`-Objekt. Die Rolle ist `giver` für `QUEST_DETAIL`, `progress` für `QUEST_PROGRESS` und `turnIn` für `QUEST_COMPLETE`.

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

`guid` ist eine Zeichenkette. `objectID` und `npcID` sind numerische Client-IDs, sofern der Client sie liefert; `uiMapID`, `mapType` und `parentMapID` sind numerische Kartenwerte. `name`, `mapName`, `zone` und `subZone` sind lokalisierte Texte. `x` und `y` sind normalisierte Kartenkoordinaten des Spielers beim Öffnen des Dialogs. `worldX` und `worldY` werden mit `C_Map.GetWorldPosFromMapPos()` berechnet; `worldContinentID` identifiziert das zugehörige Welt-/Kontinent-Koordinatensystem. Alle Koordinaten sind daher eine Näherung an die NPC-Position und können fehlen, wenn der Client keine Kartendaten liefert. `QUEST_ITEM_UPDATE` erzeugt keine neue Beobachtung und ersetzt den bereits gespeicherten NPC-Ort nicht.

### NPC-Katalog

`npcs` enthält alle erkannten NPCs aus Questdialogen sowie aus Händler-, Trainer-, Bank-, Flugmeister- und Gastwirt-Interaktionen. Das Sortiment eines Händlers liegt in `merchantSnapshots`, die Dienste eines Trainers in `trainerSnapshots`. Ein NPC kann mehrere `interactionTypes` haben. Unterstützte Werte sind `questGiver`, `merchant`, `trainer`, `banker`, `flightMaster` und `innkeeper`.

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

Beim Laden werden bestehende `questNPC`-Einträge auf dieses gemeinsame Format normalisiert und in den NPC-Katalog übernommen. Fehlende Informationen aus älteren Beobachtungen können dabei nicht rückwirkend ergänzt werden.
Wenn der Client keinen Kreaturentyp oder keine Klassifizierung liefert, werden dafür `"Unknown"` beziehungsweise `"unknown"` gespeichert.

### Belohnungen

Ein `rewards`-Objekt enthält:

```lua
rewards = {
    items = {},
    choices = {},
    spells = {},
    money = 0,
    xp = 0,
}
```

Item-Einträge enthalten unter anderem `itemID`, `name`, `link`, `texture`, `quantity`, `quality` und `isUsable`; die Items werden zusätzlich im Item-Katalog `items` mit der Quelle `quest:<questID>` und dem Standort des Quest-NPCs eingetragen. Zauber-Einträge enthalten `spellID`, `name`, `texture`, `isTradeskill` und `isSpellLearned`.

## Kontext und Varianten

Questdaten werden mit dem Charakterkontext der Beobachtung gespeichert, da Questtexte und Belohnungen von Klasse, Rasse, Fraktion, Level oder Charakterfortschritt abhängen können. Talentdaten werden dagegen durch den Katalogschlüssel nach Klasse, Rasse und Fraktion getrennt.

Die Quelldaten sind beobachtete Clientdaten. Der Client bietet keinen vollständigen globalen Questkatalog; eine Quest wird erst gespeichert, wenn der entsprechende Dialog geöffnet wurde.
