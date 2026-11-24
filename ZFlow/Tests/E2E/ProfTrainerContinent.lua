local _, ns = ...
-- Lead section 400 item 4 and section 402 item 3. No training trip to
-- another continent: when the only trainer this character has seen is on
-- another continent, the plan gives the plain line ("at a trainer", no
-- place), never that trainer. With trainers on this continent, the nearest
-- one is named, not the first by name. Through the real planner entry
-- (addon.profPlan.plan) on the whole add-on and a fake client; made-up names
-- and places. Not tested in game.
local tests = {}

local HERE, AWAY = 1411, 1453
-- Names sort so that the first by name is the wrong pick.
local NPCS = {
    ["Aaron Away"] = { map = AWAY, x = 0.5, y = 0.5 },
    ["Bel Far"] = { map = HERE, x = 0.9, y = 0.9 },
    ["Cor Close"] = { map = HERE, x = 0.55, y = 0.5 },
}

local function list(npc, rows)
    return { profession = "Blacksmithing", npc = npc, rows = rows or {} }
end

-- opts: skill, max, trainers (names), rows (Aaron Away's rows), book
local function start(opts)
    local lists = {}
    for i, npc in ipairs(opts.trainers) do
        lists["t" .. i] = list(npc, npc == "Aaron Away" and opts.rows or nil)
    end
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { learned = { places = { npcs = NPCS } } })
    c.setSaved(ns.id.charDB, { learned = {
        facts = { profSkill = { Blacksmithing = { skill = opts.skill, max = opts.max } },
                  recipeBook = opts.book or {} },
        recipeColors = {},
        trainerLists = lists,
    } })
    c.setZone(1, HERE); c.setFaction("Horde"); c.setFacing(0)
    c.setPosition(HERE, 0.5, 0.5); c.setMapSize(HERE, 1000, 500)
    c.setMapCont(HERE, 1); c.setMapCont(AWAY, 0)
    c.setBagItems({})
    c.setProfessions({ "Blacksmithing" })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function first(addon)
    local steps = addon.profPlan.plan("Blacksmithing")
    return steps and steps[1] or {}
end

tests["trainer continent e2e: next rank, only trainer on another continent: plain line, no trip"] = function(t)
    local _, addon = start({ skill = 75, max = 75, trainers = { "Aaron Away" } })
    local s = first(addon)
    t.eq(s.kind, "train_tier")
    t.eq(s.text, "Train the next Blacksmithing rank at a trainer (75 of 75)")
    t.eq(s.npc, nil, "the far trainer is not named")
    t.eq(s.target, nil, "no place on another continent")
end

tests["trainer continent e2e: next rank: the nearest trainer on this continent, not the first by name"] = function(t)
    local _, addon = start({ skill = 75, max = 75, trainers = { "Aaron Away", "Bel Far", "Cor Close" } })
    local s = first(addon)
    t.eq(s.npc, "Cor Close")
    t.eq(s.target, { map = HERE, x = 0.55, y = 0.5 })
end

tests["trainer continent e2e: empty book, only trainer on another continent: plain learn line"] = function(t)
    local _, addon = start({ skill = 10, max = 75, trainers = { "Aaron Away" } })
    local s = first(addon)
    t.eq(s.kind, "learn_recipe")
    t.eq(s.text, "Learn a Blacksmithing recipe at a trainer (Blacksmithing 10 of 75)")
    t.eq(s.target, nil)
end

tests["trainer continent e2e: a recipe only the far trainer teaches is no trip"] = function(t)
    local _, addon = start({ skill = 10, max = 75, trainers = { "Aaron Away" },
        rows = { { name = "Test Spike", state = "available", skill = 1 } } })
    local s = first(addon)
    t.ok(s.npc ~= "Aaron Away", "the far trainer is not the step")
    t.eq(s.target, nil)
end

tests["trainer continent e2e: empty book: the nearest trainer on this continent"] = function(t)
    local _, addon = start({ skill = 10, max = 75, trainers = { "Aaron Away", "Bel Far", "Cor Close" } })
    local s = first(addon)
    t.eq(s.kind, "learn_recipe")
    t.eq(s.npc, "Cor Close")
    t.eq(s.text, "Learn a Blacksmithing recipe at Cor Close (Blacksmithing 10 of 75)")
end

return tests
