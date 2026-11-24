local _, ns = ...
-- Lead section 416 item 1: for every primary and secondary profession, walk
-- skill 1 to 300 through the real planner entry (addon.profPlan.plan) in
-- every state a player can be in, and record each skill value where the
-- line the arrow shows names no next step (no step, or a step with no
-- text). Each state's gap list is pinned here, so this file is the coverage
-- table. A gap pinned below is missing recipe data, never code:
--   fresh:           window opened once; nothing learned or seen
--   ladder, mats:    a learned recipe sure at every skill, materials in bags
--   ladder, none:    the same recipes, nothing in the bags
--   outgrown:        one learned recipe, grey past 24; no trainer list seen
--   trainer partial: as outgrown, with a trainer list seen holding recipes
--                    not learned yet
--   trainer done:    as outgrown, every recipe on the seen list known
--   trainer away:    as trainer partial, the trainer on another continent
--   no colours:      recipes learned, their colours never read
-- At 300 the plan says the top rank is reached; that is the walk's end, not
-- a gap. Ranks end at 75, 150, 225 and 300. Every recipe, item, trainer,
-- place and skill span is made up (section 406: no recipe data from
-- anywhere). Loaded the way the game loads it (ns.offline.addon) on a fake
-- client. Not tested in game.
local tests = {}

local CRAFT = { "Alchemy", "Blacksmithing", "Cooking", "Enchanting", "Engineering",
    "First Aid", "Leatherworking", "Tailoring" }
local GATHER = { "Fishing", "Herbalism", "Mining", "Skinning" }
local STATES = { "fresh", "ladder, mats", "ladder, none", "outgrown", "trainer partial",
    "trainer done", "trainer away", "no colours" }
local CAP = 300
local MAT = 9001
local NPC = "Test Trainer"
local HOME, FAR = 1411, 1453

local function rankMax(skill)
    for _, top in ipairs({ 75, 150, 225, 300 }) do
        if skill <= top then return top end
    end
    return CAP
end

local OUTGROWN_STATES = { outgrown = true, ["trainer partial"] = true, ["trainer done"] = true,
    ["trainer away"] = true }

-- A made-up recipe sure from each multiple of 25 for 25 points; the
-- outgrown states keep only the first.
local function book(prof, state)
    local b, colours = {}, {}
    if state == "fresh" then return b, colours end
    for lo = 1, CAP - 1, 25 do
        local name = string.format("Test %s %d", prof, lo)
        b[name] = { profession = prof, makes = 9100 + lo, mats = { [MAT] = 1 } }
        colours[name] = { optimal = { lo = lo, hi = lo + 24 } }
        if OUTGROWN_STATES[state] then break end
    end
    return b, colours
end

-- The seen trainer list: the learned recipe known; in the partial and away
-- states, one made-up recipe not learned per 50 points.
local function trainerList(prof, state, b)
    local rows = {}
    for name in pairs(b) do rows[#rows + 1] = { name = name, skill = 1, state = "known" } end
    if state ~= "trainer done" then
        for lo = 1, CAP - 1, 50 do
            rows[#rows + 1] = { name = string.format("Test %s new %d", prof, lo), skill = lo }
        end
    end
    return { [NPC] = { profession = prof, npc = NPC, rows = rows } }
end

local function start(prof, state)
    local b, colours = book(prof, state)
    local learned = { facts = { recipeBook = b }, recipeColors = colours }
    if state == "no colours" then learned.recipeColors = {} end
    if state == "trainer partial" or state == "trainer done" or state == "trainer away" then
        learned.trainerLists = trainerList(prof, state, b)
    end
    local account = {}
    if state == "trainer away" then
        account = { learned = { places = { npcs = { [NPC] = { map = FAR, x = 0.5, y = 0.5 } } } } }
    end
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, account)
    c.setSaved(ns.id.charDB, { learned = learned })
    c.setZone(1, HOME); c.setFaction("Horde"); c.setLevel(20)
    c.setPosition(HOME, 0.5, 0.5); c.setMapSize(HOME, 1000, 500)
    c.setMapCont(HOME, 1); c.setMapCont(FAR, 0)
    c.setBagItems(state ~= "ladder, none" and { { item = MAT, count = 999 } } or {})
    c.setProfessions({ prof })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return addon
end

-- "a-b" ranges of a sorted skill list.
local function ranges(list)
    local out, from, last = {}, nil, nil
    local function close()
        if from then out[#out + 1] = from == last and tostring(from) or (from .. "-" .. last) end
    end
    for _, s in ipairs(list) do
        if last and s == last + 1 then last = s else close(); from, last = s, s end
    end
    close()
    return out
end

local function named(steps)
    local s = type(steps) == "table" and steps[1] or nil
    return type(s) == "table" and type(s.text) == "string" and s.text ~= ""
end

-- { [reason] = { "a-b", ... } } of the skill values 1 to 299 with no named
-- step, and the reason the plan gives at 300.
local function walk(prof, state)
    local addon = start(prof, state)
    local plan = addon.profPlan and addon.profPlan.plan
    if type(plan) ~= "function" then return { ["no plan"] = { "1-299" } }, nil end
    local gaps = {}
    for skill = 1, CAP - 1 do
        addon.store:set("char", "learned.facts.profSkill", { [prof] = { skill = skill, max = rankMax(skill) } })
        local ok, steps, reason = pcall(plan, prof)
        if not ok or not named(steps) then
            local why = not ok and "error" or (type(steps) == "table" and steps[1] ~= nil and "no text")
                or tostring(reason)
            gaps[why] = gaps[why] or {}
            table.insert(gaps[why], skill)
        end
    end
    addon.store:set("char", "learned.facts.profSkill", { [prof] = { skill = CAP, max = CAP } })
    local ok, _, top = pcall(plan, prof)
    local out = {}
    for why, list in pairs(gaps) do out[why] = ranges(list) end
    return out, ok and top or "error"
end

-- Craft gaps per state. Gathering professions have none in any state.
-- Lead section 418 item 5: "trainer done" names a known recipe that may
-- give a point, so no state has a gap.
local CRAFT_GAPS = {}

for _, state in ipairs(STATES) do
    for _, prof in ipairs(CRAFT) do
        tests["prof cover: " .. prof .. ", " .. state] = function(t)
            local gaps, top = walk(prof, state)
            t.eq(gaps, CRAFT_GAPS[state] or {}, prof .. ", " .. state)
            t.eq(top, "at the top", "300 is the end")
        end
    end
    for _, prof in ipairs(GATHER) do
        tests["prof cover: " .. prof .. ", " .. state] = function(t)
            local gaps, top = walk(prof, state)
            t.eq(gaps, {}, prof .. ", " .. state)
            t.eq(top, "at the top", "300 is the end")
        end
    end
end

-- The code gap this item fixed: a trainer seen only on another continent
-- left every outgrown skill with no step. It is a recipe at a trainer here,
-- with no trip named.
tests["prof cover: a trainer seen only on another continent: a recipe at a trainer here"] = function(t)
    local addon = start("Tailoring", "trainer away")
    addon.store:set("char", "learned.facts.profSkill", { Tailoring = { skill = 40, max = 75 } })
    local steps = addon.profPlan.plan("Tailoring")
    t.eq(steps[1] and steps[1].kind, "learn_recipe")
    t.eq(steps[1] and steps[1].npc, nil, "the far trainer is not named")
end

return tests
