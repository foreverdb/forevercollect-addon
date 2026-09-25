local _, addon = ...

local printMessage = addon.PrintMessage
local announce = addon.Announce
local formatMoney = addon.FormatMoney
local getItemIDFromLink = addon.GetItemIDFromLink
local getClientInfo = addon.GetClientInfo
local getOrCreateCatalog = addon.GetOrCreateCatalog
local getLatestCatalog = addon.GetLatestCatalog
local getCharacterContext = addon.GetCharacterContext
local getNPC = addon.GetNPC
local mergeNPC = addon.MergeNPC
local recordItem = addon.RecordItem

local activeQuestPhase

local function getQuestNPC(role)
    return getNPC("questnpc", "questGiver", role)
end

local function scanQuestItems(itemType, count, source)
    local items = {}
    for index = 1, count or 0 do
        local name, texture, quantity, quality, isUsable = GetQuestItemInfo(itemType, index)
        local link = GetQuestItemLink(itemType, index)
        if link and source then
            recordItem(link, source)
        end
        items[#items + 1] = {
            index = index,
            itemID = getItemIDFromLink(link),
            name = name,
            link = link,
            texture = texture,
            quantity = quantity,
            quality = quality,
            isUsable = isUsable,
        }
    end
    return items
end

local function scanQuestSpells(questID)
    local spells = {}
    if C_QuestInfoSystem and C_QuestInfoSystem.GetQuestRewardSpells then
        local spellIDs = C_QuestInfoSystem.GetQuestRewardSpells(questID) or {}
        for _, spellID in ipairs(spellIDs) do
            local info = C_QuestInfoSystem.GetQuestRewardSpellInfo(questID, spellID)
            spells[#spells + 1] = {
                spellID = spellID,
                name = info and info.name,
                texture = info and info.texture,
                isTradeskill = info and info.isTradeskill,
                isSpellLearned = info and info.isSpellLearned,
            }
        end
    elseif GetRewardSpell then
        local texture, name, isTradeskill, isSpellLearned = GetRewardSpell()
        if name then
            spells[1] = {
                name = name,
                texture = texture,
                isTradeskill = isTradeskill,
                isSpellLearned = isSpellLearned,
            }
        end
    end
    return spells
end

local function getQuestItemSource(questID, observation)
    return {
        type = "quest",
        questID = questID,
        location = observation and observation.questNPC and observation.questNPC.location or nil,
    }
end

local function scanQuestRewards(questID, observation)
    local source = getQuestItemSource(questID, observation)
    local rewards = {
        items = scanQuestItems("reward", GetNumQuestRewards(), source),
        choices = scanQuestItems("choice", GetNumQuestChoices(), source),
        spells = scanQuestSpells(questID),
        money = GetRewardMoney and GetRewardMoney() or nil,
        xp = GetRewardXP and GetRewardXP() or nil,
    }
    return rewards
end

local function scanQuestProgress(questID, observation)
    return {
        requiredItems = scanQuestItems(
            "required",
            GetNumQuestItems(),
            getQuestItemSource(questID, observation)
        ),
        requiredMoney = GetQuestMoneyToGet and GetQuestMoneyToGet() or nil,
    }
end

-- The quest type the client shows as a tag in the quest log (81 Dungeon, 62 Raid, 1 Elite,
-- 41 PvP, 21 Class, ...); the ids match the QuestInfo table.
local function getQuestTag(questID)
    if C_QuestLog and C_QuestLog.GetQuestTagInfo then
        local info = C_QuestLog.GetQuestTagInfo(questID)
        if info and info.tagID then
            return { id = info.tagID, name = info.tagName }
        end
        return nil
    end
    if GetQuestTagInfo then
        local tagID, tagName = GetQuestTagInfo(questID)
        if tagID then
            return { id = tagID, name = tagName }
        end
    end
    return nil
end

local function getSuggestedGroup()
    local size = GetSuggestedGroupSize and GetSuggestedGroupSize()
    if size and size > 0 then
        return size
    end
    return nil
end

-- Quest texts arrive with the game's placeholders already filled in ($N name, $C class,
-- $R race). The name is personal data and the texts should be comparable between players,
-- so whole-word occurrences are turned back into the placeholders before anything is stored.
local function escapePattern(text)
    return (text:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

local function replaceWord(text, word, placeholder)
    if not word or word == "" then
        return text
    end
    return (text:gsub("%f[%w]" .. escapePattern(word) .. "%f[%W]", placeholder))
end

local function scrubPlayer(text)
    if type(text) ~= "string" or text == "" then
        return text
    end
    local name = UnitName("player")
    local className = UnitClass("player")
    local raceName = UnitRace("player")
    text = replaceWord(text, name, "$N")
    text = replaceWord(text, className, "$C")
    text = replaceWord(text, className and className:lower(), "$c")
    text = replaceWord(text, raceName, "$R")
    text = replaceWord(text, raceName and raceName:lower(), "$r")
    return text
end
addon.ScrubPlayer = scrubPlayer

local function captureQuest(event)
    if event == "QUEST_ITEM_UPDATE" and not activeQuestPhase then
        return
    end

    local questID = GetQuestID and GetQuestID()
    if not questID or questID == 0 then
        return
    end

    local client = getClientInfo()
    local catalog = getOrCreateCatalog(client)
    local quest = catalog.quests[questID] or {
        questID = questID,
        observations = {},
    }
    local observation = quest.observations[#quest.observations]
    local phase = event == "QUEST_ITEM_UPDATE" and activeQuestPhase or event
    if not observation or observation.phase ~= phase then
        local role = "giver"
        if event == "QUEST_PROGRESS" then
            role = "progress"
        elseif event == "QUEST_COMPLETE" then
            role = "turnIn"
        end
        observation = {
            phase = phase,
            capturedAt = time(),
            character = getCharacterContext(),
            questNPC = getQuestNPC(role),
        }
        mergeNPC(catalog, observation.questNPC)
        quest.observations[#quest.observations + 1] = observation
    end

    quest.title = GetTitleText and GetTitleText() or quest.title
    if event == "QUEST_DETAIL" or event == "QUEST_COMPLETE" then
        observation.tag = getQuestTag(questID) or observation.tag
        observation.suggestedGroup = getSuggestedGroup() or observation.suggestedGroup
    end
    if event == "QUEST_DETAIL" then
        observation.description = scrubPlayer(GetQuestText and GetQuestText() or nil)
        observation.objectives = scrubPlayer(GetObjectiveText and GetObjectiveText() or nil)
        observation.rewards = scanQuestRewards(questID, observation)
    elseif event == "QUEST_PROGRESS" then
        observation.text = scrubPlayer(GetProgressText and GetProgressText() or nil)
        observation.progress = scanQuestProgress(questID, observation)
    elseif event == "QUEST_COMPLETE" then
        observation.text = scrubPlayer(GetRewardText and GetRewardText() or nil)
        observation.rewards = scanQuestRewards(questID, observation)
    elseif event == "QUEST_ITEM_UPDATE" then
        if activeQuestPhase == "QUEST_DETAIL" or activeQuestPhase == "QUEST_COMPLETE" then
            observation.rewards = scanQuestRewards(questID, observation)
        elseif activeQuestPhase == "QUEST_PROGRESS" then
            observation.progress = scanQuestProgress(questID, observation)
        end
    end

    catalog.quests[questID] = quest
    catalog.questScanUpdatedAt = time()
    if event ~= "QUEST_ITEM_UPDATE" then
        activeQuestPhase = event
        local phaseLabel = ({
            QUEST_DETAIL = "offered",
            QUEST_PROGRESS = "in progress",
            QUEST_COMPLETE = "ready to turn in",
        })[event] or event
        announce(string.format(
            "Quest captured: %s (%d), %s, NPC %s.",
            quest.title or "?",
            questID,
            phaseLabel,
            observation.questNPC and observation.questNPC.name or "unknown"
        ))
    end
end
addon.CaptureQuest = captureQuest

local function recordQuestTurnIn(questID, xpReward, moneyReward)
    if not questID or questID == 0 then
        return
    end
    local catalog = getOrCreateCatalog(getClientInfo())
    local quest = catalog.quests[questID] or { questID = questID, observations = {} }
    -- Auto-accepted quests (e.g. in instances) never open a quest frame, so the
    -- turn-in may be the only chance to learn the title.
    if not quest.title and C_QuestLog and C_QuestLog.GetTitleForQuestID then
        quest.title = addon.Readable(C_QuestLog.GetTitleForQuestID(questID))
    end
    quest.turnIn = {
        capturedAt = time(),
        xp = xpReward,
        money = moneyReward,
        character = getCharacterContext(),
    }
    catalog.quests[questID] = quest
    catalog.questScanUpdatedAt = time()
    announce(string.format(
        "Quest turned in: %s (%d), %d XP, %s.",
        quest.title or "?",
        questID,
        tonumber(xpReward) or 0,
        formatMoney(moneyReward)
    ))
end
addon.RecordQuestTurnIn = recordQuestTurnIn

local function countCapturedQuestPhases(catalog)
    local questCount, observationCount = 0, 0
    for _, quest in pairs(catalog.quests or {}) do
        questCount = questCount + 1
        observationCount = observationCount + #(quest.observations or {})
    end
    return questCount, observationCount
end
addon.CountCapturedQuestPhases = countCapturedQuestPhases

for _, event in ipairs({
    "QUEST_DETAIL",
    "QUEST_PROGRESS",
    "QUEST_COMPLETE",
    "QUEST_ITEM_UPDATE",
}) do
    addon:RegisterEvent(event, function()
        captureQuest(event)
    end)
end

addon:RegisterEvent("QUEST_TURNED_IN", function(questID, xpReward, moneyReward)
    recordQuestTurnIn(questID, xpReward, moneyReward)
end)

addon:RegisterEvent("QUEST_FINISHED", function()
    activeQuestPhase = nil
end)

addon:RegisterCommand("quests", function()
    local catalog = getLatestCatalog()
    if not catalog then
        printMessage("No catalog found. Open a quest dialog first.")
        return
    end

    local questCount, observationCount = countCapturedQuestPhases(catalog)
    printMessage(string.format(
        "Quest catalog contains %d quests and %d observations from client %s.",
        questCount,
        observationCount,
        catalog.version
    ))
end, "Anzahl erfasster Quests und Beobachtungen anzeigen")
