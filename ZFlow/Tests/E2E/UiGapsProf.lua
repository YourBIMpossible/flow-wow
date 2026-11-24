local _, ns = ...
-- UI files that had no end-to-end test (CAPABILITY-RECONCILE 2026-11-24):
-- UI/ProfCard.lua and UI/ProfLearn.lua, on the whole add-on loaded on a
-- fake client. The entry is the player's own: logging in with a profession
-- at its cap, and looting a recipe. What they see is a line in the advice
-- window. Every npc, item and recipe is made up. Advice only: nothing is
-- trained, used or learned here. Not tested in game.
local tests = {}

local TRAINER = "Test Tailor Trainer"
local PATTERN, KNOWN, CLOTH = 91, 92, 93
local INFO = {
    [PATTERN] = { name = "Pattern: Test Robe", quality = 2, classID = 9 },
    [KNOWN] = { name = "Pattern: Test Belt", quality = 2, classID = 9 },
    [CLOTH] = { name = "Test Cloth", quality = 1, classID = 7 },
}

-- opts: skill, max, faction, npcFactions, lists, bag, book
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { learned = { places = { npcs = {
        [TRAINER] = { trains = { Tailoring = true }, factions = opts.npcFactions or { Horde = true } },
    } } } })
    c.setSaved(ns.id.charDB, { learned = {
        facts = {
            profSkill = { Tailoring = { skill = opts.skill or 75, max = opts.max or 75 } },
            recipeBook = opts.book,
        },
        trainerLists = opts.lists,
    } })
    c.setFaction(opts.faction or "Horde")
    c.setItemInfo(INFO)
    c.setBagItems(opts.bag or {})
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function prompt(addon, id)
    for _, p in ipairs(addon.advisor.List()) do
        if p.id == id then return p.text end
    end
    return nil
end

-- The line as the player sees it: a part of the advice window.
local function onScreen(c, text)
    local w = c.kitWindows().Advisor
    if type(w) ~= "table" or w.shown ~= true then return false end
    for _, p in ipairs(w.parts or {}) do
        if type(p.text) == "string" and p.text:find(text, 1, true) then return true end
    end
    return false
end

local CAP = "Tailoring is at its cap (75/75). Trainer seen: " .. TRAINER .. "."

tests["ui gaps prof: a profession at its cap at login names the trainer seen, in the advice window"] = function(t)
    local c, addon = start()
    t.eq(prompt(addon, ns.ProfCard.PREFIX .. "Tailoring"), CAP)
    t.ok(onScreen(c, CAP), "the line is in the advice window")
    t.eq(addon.profCard.shown(), { [ns.ProfCard.PREFIX .. "Tailoring"] = true })
end

tests["ui gaps prof: below the cap, another faction's trainer, or no faction known: no line"] = function(t)
    local _, addon = start({ skill = 60 })
    t.eq(prompt(addon, ns.ProfCard.PREFIX .. "Tailoring"), nil, "60/75")
    _, addon = start({ npcFactions = { Alliance = true } })
    t.eq(prompt(addon, ns.ProfCard.PREFIX .. "Tailoring"), nil, "the other side's trainer")
    _, addon = start({ npcFactions = {} })
    t.eq(prompt(addon, ns.ProfCard.PREFIX .. "Tailoring"), nil, "a trainer of no known side")
end

tests["ui gaps prof: the cap raised: the line leaves at the next trade window read"] = function(t)
    local c, addon = start()
    t.ok(prompt(addon, ns.ProfCard.PREFIX .. "Tailoring") ~= nil, "up first")
    addon.store:set("char", ns.ProfSeen.READINGS, { Tailoring = { skill = 75, max = 150 } })
    c.fire(ns.ProfSeen.RECIPES_EVENT)
    c.advance(1, 5)
    t.eq(prompt(addon, ns.ProfCard.PREFIX .. "Tailoring"), nil)
    t.ok(not onScreen(c, CAP), "gone from the window")
end

tests["ui gaps prof: a recipe in the bags that is not known says to use it"] = function(t)
    local c, addon = start({ skill = 10, bag = { { item = PATTERN, count = 1 }, { item = CLOTH, count = 4 } } })
    local line = "Pattern: Test Robe is in your bags: use it to learn Test Robe."
    t.eq(prompt(addon, ns.ProfLearn.PREFIX .. PATTERN), line)
    t.ok(onScreen(c, line), "the line is in the advice window")
    t.eq(prompt(addon, ns.ProfLearn.PREFIX .. CLOTH), nil, "cloth teaches nothing")
end

tests["ui gaps prof: a recipe already in the recipe book gets no line"] = function(t)
    local _, addon = start({ skill = 10, bag = { { item = KNOWN, count = 1 } },
        book = { ["Test Belt"] = { profession = "Tailoring" } } })
    t.eq(prompt(addon, ns.ProfLearn.PREFIX .. KNOWN), nil)
end

tests["ui gaps prof: looted later, the line comes at the bag update; gone again with the item"] = function(t)
    local c, addon = start({ skill = 10 })
    t.eq(prompt(addon, ns.ProfLearn.PREFIX .. PATTERN), nil, "nothing yet")
    local problems = #addon.problems:list()
    c.setBagItems({ { item = PATTERN, count = 1 } })
    c.fire("BAG_UPDATE_DELAYED")
    c.advance(1, 5)
    t.ok(prompt(addon, ns.ProfLearn.PREFIX .. PATTERN) ~= nil, "up once it is in the bags")
    c.setBagItems({})
    c.fire("BAG_UPDATE_DELAYED")
    c.advance(1, 5)
    t.eq(prompt(addon, ns.ProfLearn.PREFIX .. PATTERN), nil, "gone with the item")
    t.eq(#addon.problems:list(), problems, "no new problem line")
end

return tests
