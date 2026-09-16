local _, addon = ...

local printMessage = addon.PrintMessage
local getItemIDFromLink = addon.GetItemIDFromLink
local getClientInfo = addon.GetClientInfo
local getOrCreateCatalog = addon.GetOrCreateCatalog
local getLatestCatalog = addon.GetLatestCatalog
local getCharacterContext = addon.GetCharacterContext
local getNPC = addon.GetNPC
local mergeNPC = addon.MergeNPC

local activeQuestPhase

local function getQuestNPC(role)
    return getNPC("questnpc", "questGiver", role)
end

local function scanQuestItems(itemType, count)
    local items = {}
    for index = 1, count or 0 do
        local name, texture, quantity, quality, isUsable = GetQuestItemInfo(itemType, index)
        local link = GetQuestItemLink(itemType, index)
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

local function scanQuestRewards(questID)
    local rewards = {
        items = scanQuestItems("reward", GetNumQuestRewards()),
        choices = scanQuestItems("choice", GetNumQuestChoices()),
        spells = scanQuestSpells(questID),
        money = GetRewardMoney and GetRewardMoney() or nil,
        xp = GetRewardXP and GetRewardXP() or nil,
    }
    return rewards
end

local function scanQuestProgress()
    return {
        requiredItems = scanQuestItems("required", GetNumQuestItems()),
        requiredMoney = GetQuestMoneyToGet and GetQuestMoneyToGet() or nil,
    }
end

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
    if event == "QUEST_DETAIL" then
        observation.description = GetQuestText and GetQuestText() or nil
        observation.objectives = GetObjectiveText and GetObjectiveText() or nil
        observation.rewards = scanQuestRewards(questID)
    elseif event == "QUEST_PROGRESS" then
        observation.text = GetProgressText and GetProgressText() or nil
        observation.progress = scanQuestProgress()
    elseif event == "QUEST_COMPLETE" then
        observation.text = GetRewardText and GetRewardText() or nil
        observation.rewards = scanQuestRewards(questID)
    elseif event == "QUEST_ITEM_UPDATE" then
        if activeQuestPhase == "QUEST_DETAIL" or activeQuestPhase == "QUEST_COMPLETE" then
            observation.rewards = scanQuestRewards(questID)
        elseif activeQuestPhase == "QUEST_PROGRESS" then
            observation.progress = scanQuestProgress()
        end
    end

    catalog.quests[questID] = quest
    catalog.questScanUpdatedAt = time()
    if event ~= "QUEST_ITEM_UPDATE" then
        activeQuestPhase = event
    end
end
addon.CaptureQuest = captureQuest

local function recordQuestTurnIn(questID, xpReward, moneyReward)
    if not questID or questID == 0 then
        return
    end
    local catalog = getOrCreateCatalog(getClientInfo())
    local quest = catalog.quests[questID] or { questID = questID, observations = {} }
    quest.turnIn = {
        capturedAt = time(),
        xp = xpReward,
        money = moneyReward,
        character = getCharacterContext(),
    }
    catalog.quests[questID] = quest
    catalog.questScanUpdatedAt = time()
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
