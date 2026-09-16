# ForeverCollect

ForeverCollect katalogisiert beobachtete Daten aus World of Warcraft Classic Era. Die Daten werden in der SavedVariable `ForeverCollectDB` gespeichert.

## Verwendung

```text
/fc scan      Talente und Runen scannen
/fc talents   Talentdaten des aktuellen Katalogs anzeigen
/fc trainer   Trainerdienste scannen und Anzahl erfasster Daten anzeigen
/fc runes     Runen-Snapshot anzeigen
/fc quests    Anzahl erfasster Quests und Beobachtungen anzeigen
/fc status    Katalogkontext und Scanstatus anzeigen
```

WoW schreibt die Daten nach `/reload`, Logout oder Beenden in:

```text
WTF/Account/<ACCOUNT>/SavedVariables/ForeverCollect.lua
```

## Projektstruktur

Die Dateien werden in der Reihenfolge aus `ForeverCollect.toc` geladen und teilen sich die Addon-Tabelle (`local _, addon = ...`). Module hängen nur das an `addon`, was andere Dateien brauchen, und registrieren ihre Events und Slash-Subcommands selbst über `addon:RegisterEvent(event, handler)` bzw. `addon:RegisterCommand(name, handler, help)`.

```text
Core/Util.lua           Chat-Ausgabe, Tooltip-Scanner, kleine Helfer
Core/Database.lua       ForeverCollectDB, Client-/Charakterkontext, Katalogverwaltung
Core/Registry.lua       Event-Frame und Dispatcher für Events und Slash-Commands
Modules/NPCs.lua        NPC-Erfassung und -Zusammenführung (Händler, Trainer, Bank, Flugmeister)
Modules/Talents.lua     Talentbäume (/fc talents)
Modules/Trainers.lua    Trainerdienste (/fc trainer)
Modules/Abilities.lua   Runen (/fc runes)
Modules/Quests.lua      Questdialoge und Abgaben (/fc quests)
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
    abilitySnapshots = {},
    trainerSnapshots = {},
    quests = {},
    npcs = {},
}
```

`scannedAt`, `questScanUpdatedAt`, `abilitiesScannedAt` und `trainerScanUpdatedAt` enthalten Unix-Zeitstempel.

## Talente

`specializations` ist ein Array der Talentbäume des aktuellen Classic-Clients:

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

## Runen

`abilitySnapshots` enthält die entdeckten SoD-Runen pro Charakter. Gelernte Zauber werden nicht mehr aus dem Zauberbuch gelesen; sie sind über `trainerSnapshots` mit `category = "used"` abgebildet.

```lua
abilitySnapshots = {
    ["Player-GUID"] = {
        scannedAt = 0,
        character = {},
        runes = {
            {
                category = 16,
                skillLineAbilityID = 123,
                itemEnchantmentID = 456,
                name = "...",
                icon = 123456,
                equipmentSlot = 1,
                level = 25,
                isEquipped = true,
                learnedAbilitySpellIDs = { 12345 },
                abilities = {
                    {
                        spellID = 12345,
                        name = "Balefire Bolt",
                        rank = "",
                        icon = 123456,
                        description = "...",
                    },
                },
            },
        },
    },
}
```

`runes` enthält alle entdeckten SoD-Runen, nicht nur aktuell ausgerüstete Runen. `isEquipped` kennzeichnet den momentanen Ausrüstungszustand. Dadurch bleibt beispielsweise `Balefire Bolt` auch nach dem Wechsel auf eine andere Rune im Katalog erhalten.

Runen enthalten ihre `learnedAbilitySpellIDs` und unter `abilities` zusätzlich die aufgelösten Namen, Icons und Beschreibungen der gewährten Fähigkeiten.

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

`npcs` enthält alle erkannten NPCs aus Questdialogen sowie aus Händler-, Trainer-, Bank-, Flugmeister- und Gastwirt-Interaktionen. Ein NPC kann mehrere `interactionTypes` haben. Unterstützte Werte sind `questGiver`, `merchant`, `trainer`, `banker`, `flightMaster` und `innkeeper`.

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

Item-Einträge enthalten unter anderem `itemID`, `name`, `link`, `texture`, `quantity`, `quality` und `isUsable`. Zauber-Einträge enthalten `spellID`, `name`, `texture`, `isTradeskill` und `isSpellLearned`.

## Kontext und Varianten

Questdaten werden mit dem Charakterkontext der Beobachtung gespeichert, da Questtexte und Belohnungen von Klasse, Rasse, Fraktion, Level oder Charakterfortschritt abhängen können. Talentdaten werden dagegen durch den Katalogschlüssel nach Klasse, Rasse und Fraktion getrennt.

Die Quelldaten sind beobachtete Clientdaten. Der Client bietet keinen vollständigen globalen Questkatalog; eine Quest wird erst gespeichert, wenn der entsprechende Dialog geöffnet wurde.
