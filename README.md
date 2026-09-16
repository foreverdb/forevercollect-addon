# ForeverCollect

ForeverCollect katalogisiert beobachtete Daten aus World of Warcraft Classic Era. Die Daten werden in der SavedVariable `ForeverCollectDB` gespeichert.

## Verwendung

```text
/fc scan      Talente, Fertigkeitslinien, Zauber und Runen scannen
/fc talents   Talentdaten des aktuellen Katalogs anzeigen
/fc skills    Skill-Snapshot des aktuellen Charakters anzeigen
/fc trainer   Trainerdienste scannen und Anzahl erfasster Daten anzeigen
/fc spells    Zauberbuch-Snapshot anzeigen
/fc runes     Runen-Snapshot anzeigen
/fc quests    Anzahl erfasster Quests und Beobachtungen anzeigen
/fc status    Katalogkontext und Scanstatus anzeigen
```

WoW schreibt die Daten nach `/reload`, Logout oder Beenden in:

```text
WTF/Account/<ACCOUNT>/SavedVariables/ForeverCollect.lua
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
    skillSnapshots = {},
    abilitySnapshots = {},
    trainerSnapshots = {},
    quests = {},
    npcs = {},
}
```

`scannedAt`, `questScanUpdatedAt`, `skillsScannedAt` und `trainerScanUpdatedAt` enthalten Unix-Zeitstempel.

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

## Fertigkeitslinien

`skillSnapshots` enthält den zuletzt erfassten Stand pro Charakter. Der Schlüssel ist normalerweise die Charakter-GUID:

```lua
skillSnapshots = {
    ["Player-1234-..."] = {
        scannedAt = 0,
        character = {
            name = "Character",
            realm = "Realm",
            level = 25,
            className = "Priest",
            classFile = "PRIEST",
            classID = 8,
            raceName = "Dwarf",
            raceFile = "Dwarf",
            raceID = 3,
            factionName = "Alliance",
            factionFile = "Alliance",
            sex = 2,
        },
        skillLines = {},
    },
}
```

`skillLines` enthält sowohl Kategorien/Header als auch einzelne Fertigkeitslinien:

| Feld | Beschreibung |
| --- | --- |
| `index` | Position in `GetNumSkillLines()`/`GetSkillLineInfo()`. |
| `name` | Lokalisierter Name der Kategorie oder Fertigkeit. |
| `category` | Zugehöriger Kategorie-Header. |
| `isHeader` | `true` bei einer Kategorie. |
| `isExpanded` | Zustand des Headers während des Scans. |
| `rank` | Aktueller Rang. |
| `temporaryPoints` | Temporäre Punkte. |
| `modifier` | Bonus oder Malus auf den Rang. |
| `maxRank` | Maximaler Rang; `1` kennzeichnet typischerweise eine Proficiency. |
| `isAbandonable` | Ob die Fertigkeit verlernt werden kann. |
| `isLearnable` | Ob die Fertigkeit erlernt werden kann. |
| `isTrainable` | Ob die Fertigkeit trainiert werden kann. |
| `minLevel` | Erforderliches Level. |
| `costType` | Clientinterner Kostentyp. |
| `description` | Lokalisierte Beschreibung. |

Beim Scannen werden Kategorien vorübergehend vollständig aufgeklappt. Der vorherige UI-Zustand wird danach wiederhergestellt.

## Trainer-Skills

`trainerSnapshots` wird automatisch aktualisiert, sobald ein Trainer geöffnet wird. Der Schlüssel ist die NPC-GUID; falls diese nicht verfügbar ist, wird die NPC-ID zusammen mit dem Namen verwendet.

```lua
trainerSnapshots = {
    ["Creature-0-..."] = {
        capturedAt = 0,
        character = {},
        trainerNPC = {},
        services = {
            {
                index = 1,
                name = "Example Spell",
                rank = "Rank 1",
                category = "available",
                isExpanded = false,
                isAvailable = true,
                skillLine = "Alchemy",
                icon = 123456,
                tooltipLines = {},
            },
        },
    },
}
```

Die Einträge in `services` entsprechen den aktuell vom Trainer angezeigten Diensten. Enthalten sind unter anderem Name, Rang, Kategorie, Verfügbarkeit, zugehörige Fertigkeitslinie, Icon und lokalisierte Tooltip-Zeilen. Ein erneutes Öffnen desselben Trainers ersetzt den bisherigen Snapshot.

## Zauber und Runen

`abilitySnapshots` enthält den aktuellen Fähigkeitenstand pro Charakter:

```lua
abilitySnapshots = {
    ["Player-GUID"] = {
        scannedAt = 0,
        character = {},
        spells = {
            {
                slot = 1,
                tabIndex = 1,
                tabName = "General",
                type = "SPELL",
                spellID = 12345,
                name = "Balefire Bolt",
                subtext = "",
                icon = 123456,
                link = "spell:12345",
                isPassive = false,
                isHidden = false,
                tooltipLines = {},
            },
        },
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

`spells` wird aus allen Einträgen des Spieler-Zauberbuchs aufgebaut. `runes` enthält alle entdeckten SoD-Runen, nicht nur aktuell ausgerüstete Runen. `isEquipped` kennzeichnet den momentanen Ausrüstungszustand. Dadurch bleibt beispielsweise `Balefire Bolt` auch nach dem Wechsel auf eine andere Rune im Katalog erhalten.

Zauber-Tooltips werden als `tooltipLines` mit `leftText` und `rightText` gespeichert. Runen enthalten ihre `learnedAbilitySpellIDs` und unter `abilities` zusätzlich die aufgelösten Namen, Icons und Beschreibungen der gewährten Fähigkeiten.

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
