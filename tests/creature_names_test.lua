-- Run: luajit tests/creature_names_test.lua (or lua5.1)
local stubFrame = setmetatable({}, { __index = function() return function() end end })
CreateFrame = function() return stubFrame end
WorldFrame = {}
UNKNOWNOBJECT = "Unknown"

local SECRET = {}
issecretvalue = function(value)
    return value == SECRET
end

local cache = {}
local failing = false
C_TooltipInfo = {
    GetHyperlink = function(link)
        if failing then
            error("hyperlink failed")
        end
        local npcID = tonumber(string.match(link, "^unit:Creature%-0%-0%-0%-0%-(%d+)%-"))
        local name = cache[npcID]
        return name and { lines = { { leftText = name } } } or { lines = {} }
    end,
}

local addon = {}
function addon:RegisterEvent() end
function addon:RegisterCommand() end

local function load(path)
    local chunk = assert(loadfile(path))
    chunk("ForeverCollect", addon)
end
load("Core/Util.lua")
load("Core/Database.lua")
load("Modules/Loot.lua")

local function check(name, condition)
    if not condition then
        error("FAIL: " .. name, 2)
    end
    print("ok - " .. name)
end

cache[639] = "  Edwin VanCleef "
cache[1716] = SECRET
cache[3640] = "Unknown"
cache[448] = "Hogger (cache)"
cache[705] = "Ragged Young Wolf"
check("cached name is read and trimmed", addon.GetCreatureName(639) == "Edwin VanCleef")
check("secret name is no name", addon.GetCreatureName(1716) == nil)
check("placeholder name is no name", addon.GetCreatureName(3640) == nil)
check("uncached creature has no name", addon.GetCreatureName(1) == nil)
check("invalid npcID has no name", addon.GetCreatureName(nil) == nil)

local catalog = {
    lootSources = {
        ["Creature:639"] = { sourceType = "Creature", sourceID = 639 },
        ["Creature:1716"] = { sourceType = "Creature", sourceID = 1716 },
        ["Creature:448"] = { sourceType = "Creature", sourceID = 448, name = "Hogger" },
        ["Skinning:Creature:705"] = { sourceType = "Creature", sourceID = 705, profession = "Skinning" },
        ["GameObject:639"] = { sourceType = "GameObject", sourceID = 639 },
        ["Fishing"] = { sourceType = "Fishing" },
    },
}
check("one creature gets a name", addon.FillCreatureNames(catalog) == 1)
check("unnamed creature is named", catalog.lootSources["Creature:639"].name == "Edwin VanCleef")
check("secret stays unnamed", catalog.lootSources["Creature:1716"].name == nil)
check("observed name is kept", catalog.lootSources["Creature:448"].name == "Hogger")
check("profession finds are left alone", catalog.lootSources["Skinning:Creature:705"].name == nil)
check("other source types are left alone", catalog.lootSources["GameObject:639"].name == nil)

failing = true
local ok, name = pcall(addon.GetCreatureName, 639)
check("a failing tooltip API does not throw", ok and name == nil)
