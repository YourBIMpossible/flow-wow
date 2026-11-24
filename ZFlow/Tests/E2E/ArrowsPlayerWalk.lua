local _, ns = ...
-- Lead section 413: the two arrows and the profession step, from the
-- player's side, on the whole add-on loaded on a fake client. Owner, on the
-- installed build: "There is no second arrow and I cannot do anything with
-- the profession arrow. It's not giving me the correct next step." and
-- "Only having a profession arrow every time I need to train makes NO
-- SENSE."
--
-- Nothing of the profession is put in the saved data here: the character
-- starts with empty saved tables, and what the add-on knows it learns the
-- way the game gives it: the profession window opening (TRADE_SKILL_SHOW,
-- TRADE_SKILL_LIST_UPDATE) and the bags. The two places a test saves ahead
-- say so: an anvil seen earlier (case 1) and trainers seen earlier (case 2).
--
-- The four cases held:
--   1. a quest step and a profession below its cap: both arrows show at
--      once and do not stand on each other;
--   2. the profession arrow names the next thing for a skill point: the
--      smelt before the craft, the craft the player knows before any
--      buying, the trainer only when one is needed, never one on another
--      continent;
--   3. after that step is done the arrow moves to the next one, with no gap
--      until the next training level;
--   4. with no trainer ever opened the player still gets a step.
-- Made-up recipes, items and places. Offline only: not tested in game.
local tests = {}
local N = ns.Nav

local ORE, BAR, BELT_ITEM = 1, 2, 50
local HERE, AWAY = 1411, 1453

-- opts: bags, profs, skill (the skill lines), account (saved ahead), char
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setScreen(1024, 768); c.setZone(1, HERE); c.setFacing(0); c.setFaction("Horde")
    c.setPosition(HERE, 0.5, 0.5); c.setMapSize(HERE, 1000, 500)
    c.setMapCont(HERE, 1); c.setMapCont(AWAY, 0)
    c.setItemInfo({ [ORE] = { name = "Test Ore" }, [BAR] = { name = "Test Bar" }, [BELT_ITEM] = { name = "Test Belt" } })
    c.setBagItems(opts.bags or {})
    c.setProfessions(opts.profs or { "Blacksmithing" })
    c.setSkillRanks({ Blacksmithing = { rank = opts.skill or 50, max = 75 }, Mining = { rank = 60, max = 75 } })
    -- The quest step: one quest in the log, its place from a stand-in for
    -- the player's own Questie.
    local db = {}
    function db.GetQuest(id) if id == 303 then return { ObjectiveData = { { Type = "monster", Id = 9002 } } } end end
    function db.GetNPC(id) if id == 9002 then return { name = "Far Wolf", spawns = { [12] = { { 50, 30 } } } } end end
    local zones = {}
    function zones.GetUiMapIdByAreaId(a) return ({ [12] = HERE })[a] end
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    c.setQuestLog({ { id = 303, title = "Wolves", objectives = { { text = "Wolves slain: 0/4" } } } })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon, addon.problems:count()
end

-- The player opens a profession window (or it changes after a craft).
local function window(c, prof, skill, recipes)
    local rows = {}
    for i, r in ipairs(recipes) do
        rows[i] = { id = r.id, name = r.name, learned = true, difficulty = r.colour }
        c.setRecipeSchematic(r.id, { makes = r.makes, yield = 1, mats = r.mats })
    end
    c.setRecipes({ profession = prof == "Mining" and 186 or 164, name = prof, skill = skill, max = 75, recipes = rows })
    c.fire("TRADE_SKILL_SHOW"); c.fire("TRADE_SKILL_LIST_UPDATE")
    c.advance(2, 8)
end

local function close(c)
    c.setRecipes(nil)
    c.fire("TRADE_SKILL_CLOSE")
    c.advance(1, 4)
end

local function bags(c, list)
    c.setBagItems(list)
    c.fire("BAG_UPDATE_DELAYED")
    c.advance(2, 8)
end

local function belt(colour)
    return { id = 901, name = "Test Belt", colour = colour or "optimal", makes = BELT_ITEM, mats = { [BAR] = 2 } }
end
local SMELT = { id = 902, name = "Test Smelt", colour = "easy", makes = BAR, mats = { [ORE] = 1 } }

local function quest(c) return c.arrows[1] end
local function prof(c) return c.arrows[2] end
local function said(h) return table.concat(h and h.lines or {}, " | ") end
local function has(text, part) return text:find(part, 1, true) ~= nil end

-- Case 1 ---------------------------------------------------------------

tests["player walk 1: a quest step and a craft at an anvil: two arrows, one over the other"] = function(t)
    -- Saved ahead: an anvil this player used earlier.
    local c, addon, before = boot({ bags = { { item = BAR, count = 6 } },
        account = { learned = { keyStations = { { kind = "anvil", map = HERE, x = 0.6, y = 0.5 } } } } })
    window(c, "Blacksmithing", 50, { belt() })
    close(c)
    local q, p = quest(c), prof(c)
    t.eq(q.shown, true, "the quest arrow")
    t.eq(p.shown, true, "the profession arrow, at the same time")
    t.ok(has(said(q), "Wolves"), said(q))
    t.ok(has(said(p), "anvil"), said(p))
    t.ok(q.drawn.body ~= 0, "the quest arrow is drawn")
    t.ok(p.drawn.body ~= 0, "the profession needle is drawn")
    t.eq(p.lookIs, "needle", "its own look")
    t.eq(p.point[3], q.point[3], "same column")
    t.eq(p.point[4] - q.point[4], 56 + N.NeedleClearance(56) + N.STACK_GAP,
        "one arrow, the needle's turning room and a gap higher: they do not touch")
    t.eq(q.textPoint[1], "TOP", "the quest text hangs under its arrow")
    t.eq(p.textPoint[1], "BOTTOM", "the profession text stands over its arrow")
    t.eq(addon.problems:count(), before)
end

tests["player walk 1: a step in words only: its line stands over the quest arrow, the quest text under"] = function(t)
    local c, addon, before = boot({ bags = { { item = BAR, count = 6 } } })
    window(c, "Blacksmithing", 50, { belt() })
    close(c)
    local q, p = quest(c), prof(c)
    t.eq(q.shown, true)
    t.eq(p.shown, true)
    t.eq(p.drawn.body, 0, "no place known: no needle is drawn over the quest arrow")
    t.ok(q.drawn.body ~= 0, "the quest arrow is the one arrow drawn there")
    t.eq(said(p), "Make 1 Test Belt at an anvil (Blacksmithing 50 of 75)")
    t.eq(p.textPoint[1], "BOTTOM", "the profession line is over the arrow")
    t.eq(q.textPoint[1], "TOP", "the quest text is under it")
    t.eq(addon.problems:count(), before)
end

-- Case 2 ---------------------------------------------------------------

-- Fails before the change: nothing saved the window's colours, so the plan
-- named no craft and the arrow kept saying "Open your ... window once".
tests["player walk 2: the window opened once: the arrow names the craft, not the window again"] = function(t)
    local c, addon, before = boot({ bags = { { item = BAR, count = 6 } } })
    t.ok(has(said(prof(c)), "Open your Blacksmithing window once"), said(prof(c)))
    window(c, "Blacksmithing", 50, { belt() })
    t.eq(said(prof(c)), "Make 1 Test Belt at an anvil (Blacksmithing 50 of 75)")
    close(c)
    t.eq(said(prof(c)), "Make 1 Test Belt at an anvil (Blacksmithing 50 of 75)", "closing the window keeps the step")
    t.eq(addon.problems:count(), before)
end

tests["player walk 2: ore but no bars: the smelt first, then the craft"] = function(t)
    local c, addon, before = boot({ bags = { { item = ORE, count = 4 } }, profs = { "Blacksmithing", "Mining" } })
    window(c, "Mining", 60, { SMELT })
    close(c)
    window(c, "Blacksmithing", 50, { belt() })
    close(c)
    t.eq(said(prof(c)), "Smelt 2 Test Bar at a forge, for Test Belt")
    local steps = addon.profPlan.plan("Blacksmithing")
    local kinds = {}
    for i, s in ipairs(steps or {}) do kinds[i] = s.kind end
    t.eq(kinds[1], "make_part", "the smelt is first")
    t.eq(kinds[#kinds], "craft", "the craft is last")
    -- The player smelts: bars in the bags, less ore.
    bags(c, { { item = ORE, count = 2 }, { item = BAR, count = 2 } })
    t.eq(said(prof(c)), "Make 1 Test Belt at an anvil (Blacksmithing 50 of 75)", "smelted: now the craft")
    t.eq(addon.problems:count(), before)
end

tests["player walk 2: a known recipe short of bars names its bars; no buying for a recipe not known"] = function(t)
    local c, addon, before = boot({})
    window(c, "Blacksmithing", 50, { belt() })
    close(c)
    local line = said(prof(c))
    t.ok(has(line, "Test Bar"), line)
    t.ok(not has(line, "train"), "no trainer while a known recipe gives a point")
    local steps = addon.profPlan.plan("Blacksmithing")
    for _, s in ipairs(steps or {}) do
        t.eq(s.recipe == nil or s.recipe == "Test Belt", true, "only for the recipe in the book")
    end
    t.eq(addon.problems:count(), before)
end

tests["player walk 2: below the cap with a craft that gives a point: no trainer is named"] = function(t)
    -- Saved ahead: a trainer seen earlier, close by.
    local c, addon, before = boot({ bags = { { item = BAR, count = 6 } },
        account = { learned = { places = { npcs = { ["Cor Close"] = { map = HERE, x = 0.55, y = 0.5 } } } } },
        char = { learned = { trainerLists = { t1 = { profession = "Blacksmithing", npc = "Cor Close", rows = {} } } } } })
    window(c, "Blacksmithing", 50, { belt() })
    close(c)
    local line = said(prof(c))
    t.ok(has(line, "Make 1 Test Belt"), line)
    t.ok(not has(line, "Cor Close") and not has(line:lower(), "train"), "the trainer is not the step")
    t.eq(addon.problems:count(), before)
end

tests["player walk 2: at the cap the trainer is the step; one on another continent is never the trip"] = function(t)
    -- Saved ahead: the only trainer seen is on another continent.
    local c, addon, before = boot({ bags = { { item = BAR, count = 6 } },
        account = { learned = { places = { npcs = { ["Aaron Away"] = { map = AWAY, x = 0.5, y = 0.5 } } } } },
        char = { learned = { trainerLists = { t1 = { profession = "Blacksmithing", npc = "Aaron Away", rows = {} } } } } })
    window(c, "Blacksmithing", 75, { belt("medium") })
    close(c)
    local p = prof(c)
    t.eq(p.shown, true, "a step is still said")
    t.ok(has(said(p):lower(), "train"), said(p))
    t.ok(not has(said(p), "Aaron Away"), "the far trainer is not named")
    t.eq(p.drawn.body, 0, "and no needle points across the sea")
    local s = (addon.profPlan.plan("Blacksmithing") or {})[1] or {}
    t.eq(s.kind, "train_tier")
    t.eq(s.target, nil, "no place on another continent")
    t.eq(addon.problems:count(), before)
end

-- Case 3 ---------------------------------------------------------------

-- Fails before the change: no craft was ever named between two trainings.
tests["player walk 3: every point from 50 to the cap has a craft step; the trainer only at the cap"] = function(t)
    local c, addon, before = boot({ bags = { { item = BAR, count = 200 } } })
    local left = 200
    for skill = 50, 74 do
        -- As the game gives it: the open window's list changes after the
        -- craft that gave the point. Sure to 60, maybe after.
        window(c, "Blacksmithing", skill, { belt(skill <= 60 and "optimal" or "medium") })
        local line = said(prof(c))
        t.ok(has(line, "Make ") and has(line, "Test Belt"), skill .. ": " .. line)
        t.ok(has(line, "(Blacksmithing " .. skill .. " of 75)"), skill .. ": " .. line)
        t.ok(not has(line, "Open your") and not has(line:lower(), "train"), skill .. ": " .. line)
        left = left - 2
        c.setBagItems({ { item = BAR, count = left } })
    end
    window(c, "Blacksmithing", 75, { belt("medium") })
    close(c)
    local line = said(prof(c))
    t.ok(not has(line, "Make "), "at the cap no craft is named: " .. line)
    t.ok(has(line:lower(), "train"), "the trainer is the step now: " .. line)
    t.eq(addon.problems:count(), before)
end

tests["player walk 3: the bars run out mid-way: the step is the bars, then the craft again"] = function(t)
    local c, addon, before = boot({ bags = { { item = BAR, count = 2 } } })
    window(c, "Blacksmithing", 50, { belt() })
    t.ok(has(said(prof(c)), "Make 1 Test Belt"), said(prof(c)))
    c.setBagItems({})
    window(c, "Blacksmithing", 51, { belt() })
    close(c)
    local line = said(prof(c))
    t.ok(has(line, "Test Bar"), "the bars are the step: " .. line)
    t.ok(not has(line, "Open your") and not has(line:lower(), "train"), line)
    bags(c, { { item = BAR, count = 2 } })
    t.eq(said(prof(c)), "Make 1 Test Belt at an anvil (Blacksmithing 51 of 75)")
    t.eq(addon.problems:count(), before)
end

-- Case 4 ---------------------------------------------------------------

tests["player walk 4: no trainer ever opened, nothing saved: a step from the first login to the cap"] = function(t)
    local c, addon, before = boot({ bags = { { item = BAR, count = 6 } } })
    local p = prof(c)
    t.eq(p.shown, true, "a profession step at the first login")
    t.eq(said(p), "Open your Blacksmithing window once to read your skill")
    window(c, "Blacksmithing", 50, { belt() })
    close(c)
    t.eq(said(prof(c)), "Make 1 Test Belt at an anvil (Blacksmithing 50 of 75)", "then the craft")
    window(c, "Blacksmithing", 75, { belt("medium") })
    close(c)
    t.eq(prof(c).shown, true, "and at the cap")
    t.ok(has(said(prof(c)), "Blacksmithing trainer"), said(prof(c)))
    t.eq(addon.problems:count(), before)
end

tests["player walk: the window's colours are saved from the game's own events, nothing else"] = function(t)
    local c, addon, before = boot({})
    t.eq(addon.store:get("char", "learned.recipeColors"), nil, "nothing before a window")
    window(c, "Blacksmithing", 50, { belt() })
    t.eq(addon.store:get("char", "learned.recipeColors"), { ["Test Belt"] = { optimal = { lo = 50, hi = 50 } } })
    window(c, "Blacksmithing", 52, { belt("medium") })
    t.eq(addon.store:get("char", "learned.recipeColors"),
        { ["Test Belt"] = { optimal = { lo = 50, hi = 50 }, medium = { lo = 52, hi = 52 } } })
    t.eq(addon.problems:count(), before)
end

return tests
