# Test protocol: ForeverCollect 0.12.0

What the automated tests (`tests/*_test.lua`) cannot cover: the look of the window, runtime
fallbacks of the client API and the way from the game to the website. Run each check on
**Forever** and on **Classic Era** and tick the column. Write deviations under "Findings" with
a screenshot.

Reference designs: Paper file "ForeverDB", artboards "ForeverCollect Addon – …",
"ForeverCollect Setup – 1/2/3" and "ForeverCollect Popup – …".

## Preparation

- Install the addon build of this branch. Copy only `ForeverCollect`, not `ForeverCollect_CacheIDs`
  (that one is tested in section 7).
- Have the ForeverDB Uploader running and linked to your account.
- Have one **new character** (never logged in with ForeverCollect) and one **existing character**
  (logged in with 0.11.x, with Armory on).
- If something fails, `/console scriptErrors 1` shows Lua errors in the game.

## 1. Setup

| # | Step | Expected | Forever | Classic Era |
|---|---|---|---|---|
| 1.1 | Log in with the new character | The setup opens about 2 s after login, step 1 "Welcome, <name>" with 8 kind chips, all on | ☐ | ☐ |
| 1.2 | Click a chip twice | It turns off (no check, quiet outline) and on again | ☐ | ☐ |
| 1.3 | Next | Step 2: "Upload this character" off, its two sub-rows dimmed; combat log on, "Also in the open world" off | ☐ | ☐ |
| 1.4 | Switch "Upload this character" on | "Show on the public Armory" and "Additional private data" become switchable | ☐ | ☐ |
| 1.5 | Turn on upload and private data, leave "public" off, Next | Step 3 lists "Collecting all 8 kinds", "Upload <name>", "Additional private data, only for you", "Combat log in dungeons and raids"; no "Skip setup" | ☐ | ☐ |
| 1.6 | Click into the field "foreverdb.app/uploader", Ctrl+C, paste into chat | The URL is copied; typing into the field does not change it | ☐ | ☐ |
| 1.7 | Start collecting | The setup closes; the Character tab (`/fc`) shows the same choices | ☐ | ☐ |
| 1.8 | `/reload` | The setup does not come back | ☐ | ☐ |
| 1.9 | Log in with the existing character | The setup opens prefilled: upload on and private data as before | ☐ | ☐ |
| 1.10 | Skip setup | Nothing changes (Character tab as before); after `/reload` no setup | ☐ | ☐ |
| 1.11 | `/fc setup`, then Escape | The setup closes, nothing is applied | ☐ | ☐ |
| 1.12 | Enter combat during the first login of another new character | The setup only opens once combat ends | ☐ | ☐ |

## 2. Window

| # | Step | Expected | Forever | Classic Era |
|---|---|---|---|---|
| 2.1 | `/fc` | The window opens; header with "ForeverCollect", name, "Level N Class · Faction" and the "Collecting" pill | ☐ | ☐ |
| 2.2 | Compare each tab with Paper | Colours, spacing, fonts (Friz for text, Arial Narrow for times and numbers) | ☐ | ☐ |
| 2.3 | Look at the switches | Round ends and a round knob (square means the circle mask is missing; please report) | ☐ | ☐ |
| 2.4 | Drag the header, `/reload`, `/fc` | The window opens at the new position | ☐ | ☐ |
| 2.5 | Escape, then `/fc` twice | Escape closes it; a bare `/fc` opens and closes it | ☐ | ☐ |
| 2.6 | Options → AddOns → ForeverCollect → "Open ForeverCollect" | The settings close and the window opens | ☐ | ☐ |
| 2.7 | `/fc` in combat | Chat: "The window cannot be opened in combat." | ☐ | ☐ |

## 3. Session tab and saving

| # | Step | Expected | Forever | Classic Era |
|---|---|---|---|---|
| 3.1 | Right after `/reload` | "Everything is saved", "Reload UI to save" greyed out, "Nothing captured since the last save." | ☐ | ☐ |
| 3.2 | Accept a quest, turn one in | Rows with the "!" icon: quest title, "Quest offered · NPC · place", "Quest turned in · place", time | ☐ | ☐ |
| 3.3 | Loot a creature | Row "creature name", "Loot · N items · item names" | ☐ | ☐ |
| 3.4 | Mine, herb or skin | Row with kind gathering: "Mining · Copper Ore … · place" | ☐ | ☐ |
| 3.5 | Open a merchant, a trainer, a flight master | Rows "Merchant · N goods with prices", "Trainer · N services", "Flight master · place" | ☐ | ☐ |
| 3.6 | Click a filter chip, then "All N" | The list shows only that kind, then everything again; the counts match | ☐ | ☐ |
| 3.7 | More than 6 rows: scroll with the mouse wheel | The list scrolls | ☐ | ☐ |
| 3.8 | "Reload UI to save" | The UI reloads; afterwards "Everything is saved" | ☐ | ☐ |
| 3.9 | Wait 30 min or capture 50 finds without saving | Notice at the top: "N finds waiting to be saved", "Later" / "Reload UI to save" | ☐ | ☐ |
| 3.10 | "Reload UI to save" in the notice while in combat | No reload; chat: "Cannot reload right now …" | ☐ | ☐ |

## 4. Capture tab and pause

| # | Step | Expected | Forever | Classic Era |
|---|---|---|---|---|
| 4.1 | Switch off "Gathering" | Header text "7 of 8 kinds on"; gathering no longer appears in the session list | ☐ | ☐ |
| 4.2 | Switch off "Collect on this character" | Pill "Paused" (orange), "Paused since <date, time>", the 8 switches dimmed | ☐ | ☐ |
| 4.3 | `/reload` | Notice "Collecting is paused on <name>", "Since …"; "Resume" resumes everything | ☐ | ☐ |
| 4.4 | Switch "A chat line for every find" | Chat lines for captures appear or stop | ☐ | ☐ |

## 5. Character tab

| # | Step | Expected | Forever | Classic Era |
|---|---|---|---|---|
| 5.1 | Switch "Upload this character" off | Sub-rows dimmed; chat line about removed snapshots | ☐ | ☐ |
| 5.2 | Switch it on again | "Additional private data" stays off (it is no longer turned on together with the upload) | ☐ | ☐ |
| 5.3 | Switch "Additional private data" on, then `/fc private` | Chat contains "Completed quests: N, last read …" with N > 0 | ☐ | ☐ |
| 5.4 | Turn in a quest, `/fc private` | N goes up by one | ☐ | ☐ |
| 5.5 | Switch the combat log off and on | "Also in the open world" is dimmed while it is off | ☐ | ☐ |

If 5.3 shows "not read yet" after a login, the client has neither `C_QuestLog.GetAllCompletedQuestIDs`
nor `GetQuestsCompleted`. Please run and report:

```
/run local f=C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs; print("GetAll:", f~=nil, f and #f() or 0)
/run local n=0; if GetQuestsCompleted then for _ in pairs(GetQuestsCompleted()) do n=n+1 end end; print("GetQuestsCompleted:", GetQuestsCompleted~=nil, n)
```

## 6. Advanced tab

| # | Step | Expected | Forever | Classic Era |
|---|---|---|---|---|
| 6.1 | Open Advanced without `ForeverCollect_CacheIDs` | No "Crawler" section; client line with client, season, locale and addon v0.12.0 | ☐ | ☐ |
| 6.2 | "Talent discovery" | Classic Era: "<Class> talent trees", "Scanned at HH:MM", "Scan again" works. Forever: section absent | ☐ | ☐ |
| 6.3 | `/fc help`, `/fc questcache` | Neither `questcache` nor `itemcache` is listed; the command answers "Unknown command" | ☐ | ☐ |

## 7. Crawler (approved crawler only, Forever)

| # | Step | Expected | ✓ |
|---|---|---|---|
| 7.1 | Uploader with crawler approval, start WoW | `ForeverCollect_CacheIDs` exists in `Interface/AddOns` | ☐ |
| 7.2 | Advanced tab | "Crawler" with Quest cache and Item cache, progress and Start | ☐ |
| 7.3 | Start the quest cache | Progress counts up, the button changes to Stop; Stop holds the position | ☐ |
| 7.4 | Approval revoked (backoffice), restart the uploader and WoW | The addon is removed (needs the uploader ticket); no crawler section | ☐ |

## 8. End to end (website)

| # | Step | Expected | ✓ |
|---|---|---|---|
| 8.1 | New character from 1.5 (public off): log out, wait for the upload | On foreverdb.app/profile the character is listed as hidden | ☐ |
| 8.2 | Another new character with "Show on the public Armory" on | It appears in the Armory | ☐ |
| 8.3 | Change the visibility on the profile, play, upload again | The profile's choice stays | ☐ |
| 8.4 | Choose the character in the site menu, open a dungeon's Quests tab | Its completed quests are ticked and locked; the in-game command card is gone | ☐ |
| 8.5 | Open a completed quest's page | Badge "Completed by <name>" | ☐ |

Needs the server changes deployed (migrations `20261103120000_character_hidden_by_default`,
`20261103130000_character_completed_quests`, then API, web and worker).

## Findings

| # | Client | What happened | Screenshot |
|---|---|---|---|
| | | | |
