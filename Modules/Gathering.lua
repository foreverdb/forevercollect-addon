local _, addon = ...

local readable = addon.Readable

-- Tags the next loot window with the gathering profession whose cast just
-- succeeded (herbalism, mining, skinning, fishing) so the Loot module can
-- record nodes and skins as profession finds with their location. Game objects
-- are neither targetable nor listed in the client's data tables, so their
-- names come from the cast's target name (UNIT_SPELLCAST_SENT, also for chests
-- opened with "Opening"), else from the tooltip shown while hovering them.

-- Cast spells per profession; higher ranks not listed here are matched by name.
local GATHER_SPELLS = {
    Herbalism = { 2366, 2368, 3570, 11993, 28695, 50300, 74519 },
    Mining = { 2575, 2576, 3564, 10248, 29354, 50310, 74517 },
    Skinning = { 8613, 8617, 8618, 10768, 32678, 50305, 74522 },
    Fishing = { 7620, 7731, 7732, 18248, 33095, 51294, 88868 },
}

-- Opening a locked chest or quest object casts "Opening" (3365 and same-named
-- variants); its target name is the object's name.
local OPENING_SPELL_ID = 3365

local PENDING_TIMEOUT = 5 -- seconds between the cast and the loot window
local TOOLTIP_TIMEOUT = 4 -- seconds a hovered node name stays usable
local TOOLTIP_MAX_LINES = 2 -- node tooltips: name, optionally a skill requirement

local professionBySpellID = {}
local professionBySpellName = {}
local pendingGather
local pendingObject
local lastWorldTooltip
local lastCastTarget

local function getSpellName(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        return info and info.name
    end
    if GetSpellInfo then
        return (GetSpellInfo(spellID))
    end
    return nil
end

for profession, spellIDs in pairs(GATHER_SPELLS) do
    for _, spellID in ipairs(spellIDs) do
        professionBySpellID[spellID] = profession
        local name = getSpellName(spellID)
        if name and name ~= "" then
            professionBySpellName[name] = profession
        end
    end
end

local openingName = getSpellName(OPENING_SPELL_ID)

local function isOpeningSpell(spellID)
    if spellID == OPENING_SPELL_ID then
        return true
    end
    return openingName ~= nil and openingName ~= "" and getSpellName(spellID) == openingName
end

local function professionForSpell(spellID)
    if not spellID then
        return nil
    end
    local profession = professionBySpellID[spellID]
    if profession then
        return profession
    end
    local name = getSpellName(spellID)
    return name and professionBySpellName[name] or nil
end

-- Remember the title of tooltips that do not belong to a unit: those are world
-- objects such as herb and mineral nodes. Clients on the mainline engine (12.x,
-- Forever) hand world-cursor text to addons as "secret" values that cannot be
-- read or compared; those are skipped and the Loot module falls back to the
-- gathered item's name.
local function readTooltipTitle(tooltip)
    -- UI tooltips (buttons, profession links) are longer or explanatory; world
    -- object tooltips carry just the name and maybe a requirement line.
    if tooltip:NumLines() > TOOLTIP_MAX_LINES then
        return nil
    end
    -- World objects use the default anchor on UIParent; UI widgets own their
    -- tooltip themselves, and item or spell tooltips are never objects.
    local owner = tooltip.GetOwner and tooltip:GetOwner()
    if owner and UIParent and owner ~= UIParent then
        return nil
    end
    if (tooltip.GetItem and tooltip:GetItem()) or (tooltip.GetSpell and tooltip:GetSpell()) then
        return nil
    end
    local line = _G[tooltip:GetName() .. "TextLeft1"]
    local text = readable(line and line:GetText())
    if type(text) ~= "string" or text == "" then
        return nil
    end
    return text
end

if GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnShow", function(tooltip)
        if UnitExists and UnitExists("mouseover") then
            return
        end
        local ok, text = pcall(readTooltipTitle, tooltip)
        if ok and text then
            lastWorldTooltip = { text = text, at = GetTime() }
        end
    end)
end

local function recentTooltipTitle()
    if lastWorldTooltip and GetTime() - lastWorldTooltip.at <= TOOLTIP_TIMEOUT then
        return lastWorldTooltip.text
    end
    return nil
end

-- The target name of the cast, as the client sent it (an object or unit name;
-- empty for untargeted casts). Secret names are skipped.
addon:RegisterEvent("UNIT_SPELLCAST_SENT", function(unit, target, castGUID, spellID)
    if unit ~= "player" then
        return
    end
    local name = readable(target)
    lastCastTarget = nil
    if type(name) == "string" and name ~= "" then
        lastCastTarget = { name = name, castGUID = readable(castGUID), spellID = readable(spellID) }
    end
end)

local function castTargetName(castGUID, spellID)
    local sent = lastCastTarget
    if not sent then
        return nil
    end
    if sent.castGUID and castGUID then
        return sent.castGUID == castGUID and sent.name or nil
    end
    return sent.spellID == spellID and sent.name or nil
end

addon:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(unit, castGUID, spellID)
    if unit ~= "player" then
        return
    end
    castGUID, spellID = readable(castGUID), readable(spellID)
    if isOpeningSpell(spellID) then
        local name = castTargetName(castGUID, spellID) or recentTooltipTitle()
        pendingObject = name and { name = name, at = GetTime() } or nil
        return
    end
    local profession = professionForSpell(spellID)
    if not profession then
        return
    end
    local nodeName
    if profession == "Herbalism" or profession == "Mining" then
        nodeName = castTargetName(castGUID, spellID) or recentTooltipTitle()
    end
    pendingGather = {
        profession = profession,
        spellID = spellID,
        nodeName = nodeName,
        at = GetTime(),
    }
end)

-- Returns and clears the gather cast that preceded the current loot window.
function addon.ConsumePendingGather()
    local gather = pendingGather
    pendingGather = nil
    if gather and GetTime() - gather.at <= PENDING_TIMEOUT then
        return gather
    end
    return nil
end

-- Returns and clears the name of the game object the current loot window
-- belongs to: the target of a preceding "Opening" cast, else the tooltip of
-- the object hovered just before (chests that open without a cast).
function addon.ConsumeObjectName()
    local object = pendingObject
    pendingObject = nil
    if object and GetTime() - object.at <= PENDING_TIMEOUT then
        return object.name
    end
    return recentTooltipTitle()
end
