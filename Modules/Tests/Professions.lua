-- Lane W4 self-tests: professions, crafting goals, acquisition.
-- Same harness as Modules/Tests.lua (ns:Register("test", ...)); they stand in
-- only for Flow's own functions, never for the game's, and put back what they
-- change.

local _, ns = ...

local function with(tbl, key, value, fn)
    local old = tbl[key]
    tbl[key] = value
    local ok, err = pcall(fn)
    tbl[key] = old
    if not ok then error(err, 0) end
end

-------------------------------------------------------------------------------
-- F-081: Professions off still keeps the skill a quest asks for.
-------------------------------------------------------------------------------

local QUEST_LOG = { { title = "Bleeding Hearts", objectives = {
    { text = "Raise your first aid skill to 40", finished = false } } } }
local function profsOff(_, kind) return kind ~= "professions" end

ns:Register("test", "professions: off, a quest's skill keeps its target and nothing else does", function(t)
    local SP = ns.skillPlan
    with(ns.nav, "Includes", profsOff, function()
    with(ns.quests, "LogEntries", function() return QUEST_LOG end, function()
    with(ns, "ProfessionPlan", function() return { { name = "Herbalism" } } end, function()
        local targets = SP:Targets()
        local fa = targets["First Aid"]
        t:ok(fa ~= nil, "the quest's skill keeps its target")
        t:eq(fa and fa.target, 40, "to the skill the quest asks for")
        t:eq(fa and fa.quest, "Bleeding Hearts", "named for its quest")
        t:ok(fa and fa.required, "and required, not optional")
        t:eq(targets.Herbalism, nil, "a planned profession behind your level gets nothing while off")
    end) end) end)
end)

ns:Register("test", "professions: off, the route keeps a step a quest needs and drops a plain skill-up", function(t)
    local N = ns.nav
    local function inc(kind) return profsOff(nil, kind) end
    local list = {
        { key = "skillplan:First Aid", provider = "skillplan", forQuest = "Bleeding Hearts", points = {} },
        { key = "skillplan:Herbalism", provider = "skillplan", points = {} },
    }
    local kept = N.FilterKinds(list, inc, 20)
    t:eq(#kept, 1, "one step kept")
    t:eq(kept[1] and kept[1].key, "skillplan:First Aid", "the quest's one")
    t:eq(kept[1] and kept[1].routeKind, "quests", "counted as the quest's step")
    t:eq(list[2].routeKind, "professions", "the plain skill-up is still a profession stop")
end)

ns:Register("test", "professions: a quest's skill step reads 'needed for quest' and names it", function(t)
    local SP = ns.skillPlan
    with(ns.api, "Skill", function(name) if name == "First Aid" then return 10, 75 end end, function()
        local out = {}
        local ok, err = pcall(SP._planProfession, "First Aid",
            { target = 40, quest = "Bleeding Hearts", required = true }, out)
        t:ok(ok, "planning it runs: " .. tostring(err))
        t:ok(#out > 0, "it has at least one step")
        local g = out[1]
        t:eq(g and g.forQuest, "Bleeding Hearts", "the step says which quest needs it")
        local first = g and g.details and g.details[1] or ""
        t:ok(first:find("needed for quest Bleeding Hearts", 1, true) ~= nil, "its reason reads 'needed for quest': " .. first)
        out = {}
        pcall(SP._planProfession, "First Aid", { target = 40, optional = true }, out)
        t:eq(out[1] and out[1].forQuest, nil, "a skill-up for your level isn't marked for a quest")
    end)
end)

-------------------------------------------------------------------------------
-- F-079: a Skinning guide, from the game's level rule (no mob or zone data).
-------------------------------------------------------------------------------

ns:Register("test", "professions: Skinning has a guide, shaped like the other gathering guides", function(t)
    local g = ns:Get("profGuide", "Skinning")
    t:ok(g ~= nil, "Skinning is registered")
    t:eq(g and g.kind, "gather", "a gathering profession")
    t:eq(g and g.tool, 7005, "the Skinning Knife is its tool")
    t:ok(g and g.skin == true, "planned from the beasts you kill, not from spots")
    t:eq(ns.disposition and ns.disposition.ToolProfession and ns.disposition:ToolProfession(7005) or "Skinning",
        "Skinning", "the knife is the one the bags already treat as Skinning's")
end)

ns:Register("test", "professions: the skill a beast's level needs to skin, and back", function(t)
    local SP = ns.skillPlan
    t:eq(SP.SkinSkill(5), 1, "level 5: anyone with Skinning")
    t:eq(SP.SkinSkill(10), 1, "level 10: still 1")
    t:eq(SP.SkinSkill(15), 50, "level 15: 50")
    t:eq(SP.SkinSkill(20), 100, "level 20: 100")
    t:eq(SP.SkinSkill(21), 105, "level 21: 105")
    t:eq(SP.SkinSkill(60), 300, "level 60: 300")
    t:eq(SP.SkinMaxLevel(1), 10, "skill 1: up to level 10")
    t:eq(SP.SkinMaxLevel(55), 15, "skill 55: up to 15")
    t:eq(SP.SkinMaxLevel(100), 20, "skill 100: up to 20")
    t:eq(SP.SkinMaxLevel(104), 20, "skill 104: not yet 21")
    t:eq(SP.SkinMaxLevel(300), 60, "skill 300: up to 60")
    for level = 1, 60 do
        local need = SP.SkinSkill(level)
        if SP.SkinMaxLevel(need) < level then t:ok(false, "level " .. level .. " can't be skinned at its own need") end
    end
end)

ns:Register("test", "professions: Skinning behind your beasts' level gets an optional target", function(t)
    local SP = ns.skillPlan
    local want = math.min(SP.SkinSkill(UnitLevel("player")), 300)
    with(ns.nav, "Includes", function() return true end, function()
    with(ns.quests, "LogEntries", function() return {} end, function()
    with(ns, "ProfessionPlan", function() return { { name = "Skinning" } } end, function()
    with(ns.api, "Skill", function(name) if name == "Skinning" then return 0, 75 end end, function()
        local s = SP:Targets().Skinning
        t:ok(s ~= nil, "a target to skin beasts of your level")
        t:eq(s and s.target, want, "the skill your level's beasts need")
        t:ok(s and s.optional == true, "optional: done on the way, behind your quests")
    end) end) end) end)
    with(ns.nav, "Includes", function() return true end, function()
    with(ns.quests, "LogEntries", function() return {} end, function()
    with(ns, "ProfessionPlan", function() return { { name = "Skinning" } } end, function()
    with(ns.api, "Skill", function(name) if name == "Skinning" then return want, 300 end end, function()
        t:eq(SP:Targets().Skinning, nil, "already there: nothing to plan")
    end) end) end) end)
end)

ns:Register("test", "professions: the Skinning step is along the way, never a detour", function(t)
    local SP = ns.skillPlan
    with(ns.api, "Skill", function(name) if name == "Skinning" then return 55, 75 end end, function()
        local out = {}
        local ok, err = pcall(SP._planProfession, "Skinning", { target = 100, optional = true }, out)
        t:ok(ok, "planning it runs: " .. tostring(err))
        local step
        for _, g in ipairs(out) do if g.key == "skill:Skinning" then step = g end end
        t:ok(step ~= nil, "a Skinning step")
        t:ok(step and step.along == true, "listed along the way, not routed")
        t:ok(step and (step.text or ""):find("up to level 15", 1, true) ~= nil, "names the beasts you can skin: " .. tostring(step and step.text))
        for _, g in ipairs(out) do
            t:ok(g.key ~= "skillplan:Skinning", "no 'no levelling data' step any more")
        end
    end)
end)

-------------------------------------------------------------------------------
-- F-085: Expert and Artisan steps say what they cost, or that it's unknown.
-------------------------------------------------------------------------------

local function coins(c) return c .. "c" end
local function hasLine(details, pat)
    for _, d in ipairs(details or {}) do
        if type(d) == "string" and d:find(pat, 1, true) then return true end
    end
    return false
end
-- Mining 130 of 150 at level 25: Expert, from the Mining trainer.
local function expertStep(tierSeen, fn)
    local SP = ns.skillPlan
    local made = ns.db.prof == nil
    if made then ns.db.prof = {} end
    local ok, err = pcall(with, ns.db.prof, "tierSeen", tierSeen, function()
    with(ns.quests, "NPCsByName", false, function()
    with(ns.api, "Skill", function(name) if name == "Mining" then return 130, 150 end end, function()
    with(ns.places, "TrainersFor", function() return { "Test Trainer" } end, function()
    with(ns.places, "Points", function() return {} end, function()
        fn(SP.TierGoal("Mining", 25, false))
    end) end) end) end) end)
    if made then ns.db.prof = nil end
    if not ok then error(err, 0) end
end

ns:Register("test", "professions: an Expert tier nobody has priced says so and waits on no price", function(t)
    expertStep({}, function(g)
        t:ok(g ~= nil, "the Expert step is built")
        t:eq(g and g.cost, nil, "no made-up price to wait for")
        t:ok(g and g.costUnknown, "marked as price unknown")
        t:eq(g and g.costEstimate, nil, "and no estimate without a recorded source")
        t:ok(g and hasLine(g.details, "Price unknown"), "the step says: price unknown, check the trainer")
    end)
end)

ns:Register("test", "professions: an Expert price read at a trainer is the step's cost, with its source", function(t)
    expertStep({ Mining = { cap = 150, cost = 50000 } }, function(g)
        t:eq(g and g.cost, 50000, "the trainer's price")
        t:eq(g and g.costUnknown, nil, "not unknown")
        t:ok(g and hasLine(g.details, "the Mining trainer's price"), "says where the price came from")
    end)
end)

ns:Register("test", "professions: an Expert step with a recorded estimate carries it, and the route doesn't wait on it", function(t)
    with(ns.skillPlan, "TIER_ESTIMATE", { [150] = { cost = 10000, source = "test record" } }, function()
        expertStep({}, function(g)
            t:eq(g and g.cost, nil, "no certain cost")
            t:eq(g and g.costEstimate, 10000, "carried as an estimate")
            t:ok(g and hasLine(g.details, "about"), "and shown as 'about'")
        end)
    end)
end)

ns:Register("test", "professions: a tier estimate needs a recorded source and is never a certain cost", function(t)
    local SP = ns.skillPlan
    local text, est = SP.TierPriceLine(150, nil, nil, coins)
    t:eq(est, nil, "nothing recorded: no estimate")
    t:ok(text:find("Price unknown", 1, true), "price unknown")
    with(SP, "TIER_ESTIMATE", { [150] = { cost = 10000 } }, function()
        local _, e = SP.TierPriceLine(150, nil, nil, coins)
        t:eq(e, nil, "an estimate without a source is ignored")
    end)
    with(SP, "TIER_ESTIMATE", { [150] = { cost = 10000, source = "test record" } }, function()
        local line, e = SP.TierPriceLine(150, nil, nil, coins)
        t:eq(e, 10000, "a recorded estimate")
        t:ok(line:find("about 10000c (test record)", 1, true), "labelled 'about', with its source")
    end)
    local line = SP.TierPriceLine(150, 50000, "the Mining trainer's price", coins)
    t:eq(line, "Costs 50000c (the Mining trainer's price).", "a seen price is stated plainly")
    local cost, source = SP.TierCost("Mining", 150, { Mining = { cap = 150, cost = 50000 } })
    t:eq(cost, 50000, "Expert from its own trainer")
    t:eq(source, "the Mining trainer's price", "named as such")
    cost, source = SP.TierCost("Mining", 75, nil)
    t:eq(cost, 500, "Journeyman keeps its recorded price")
    t:ok(source and source:find("2026-11-13", 1, true), "with where and when it was read")
end)

-------------------------------------------------------------------------------
-- F-086: skill boosters by item ID, with provenance; unknown stays unknown.
-------------------------------------------------------------------------------

local GERMAN = { { left = "Benutzen: Erh9582ht Eure Fertigkeit in Bergbau um 2." } }
local ENGLISH = { { left = "Use: Increases your Mining skill by 2, up to a maximum of 15." } }

ns:Register("test", "professions: a registered skill booster is found by item ID on any client", function(t)
    local SB = ns.skillBoosters
    local entry = { skill = "Mining", amount = 2, cap = 15, source = "test record", seen = "2026-11-21" }
    local get = function(id) return id == 999001 and entry or nil end
    local b = SB.Find(999001, GERMAN, get)
    t:eq(b and b.skill, "Mining", "found by ID though the tooltip isn't English")
    t:eq(b and b.amount, 2, "its bonus")
    t:eq(b and b.cap, 15, "and its cap")
    local bare = { skill = "Mining", amount = 2 }
    t:eq(SB.Known(999002, function() return bare end), nil, "an entry without where and when it was read is ignored")
end)

ns:Register("test", "professions: an unknown skill booster stays unknown; an English tooltip is an observation", function(t)
    local SB = ns.skillBoosters
    local none = function() return nil end
    t:eq(SB.Find(999003, GERMAN, none), nil, "not registered, not English: unknown, so no bonus")
    t:eq(SB.Observed()[999003], nil, "and nothing observed")
    local b = SB.Find(999004, ENGLISH, none)
    t:eq(b and b.amount, 2, "read from the English tooltip")
    t:eq(b and b.cap, 15, "with its cap")
    local o = SB.Observed()[999004]
    t:eq(o and o.source, "English tooltip", "kept as an observation, with its source")
    t:ok(o and type(o.seen) == "string", "and when it was read")
    SB.Observed()[999004] = nil
end)

-------------------------------------------------------------------------------
-- W4c: the skill-up plan is worked out (SP.Score), not a fixed path: from a
-- recipe's colours, what its materials cost, and what's in your bags.
-------------------------------------------------------------------------------

local MAT_A, MAT_B, FISH = 990001, 990002, 6289   -- (6289: Raw Longjaw Mud Snapper, fished)
local function step(name, mats) return { recipe = name, learn = 1, yellow = 50, green = 60, grey = 70, mats = mats } end
local function priced(list) return function(id) return list[id] end end

ns:Register("test", "professions: SP.Score rates a step by skill per copper, else per material", function(t)
    local SP = ns.skillPlan
    local s = step("A__test", { [MAT_A] = 2 })
    local v, c, isPriced = SP.Score(s, 10, { prof = "X__test", prefer = "cheap", costOf = priced({ [MAT_A] = 50 }) })
    t:near(v, 1 / 100, 1e-12, "orange, 100c a craft: 1 point per 100c")
    t:eq(c, 1, "orange: a point every craft"); t:ok(isPriced, "priced")
    v, c = SP.Score(s, 55, { prof = "X__test", prefer = "cheap", costOf = priced({ [MAT_A] = 50 }) })
    t:near(v, 0.6 / 100, 1e-12, "yellow: 0.6 of a point per 100c"); t:eq(c, 0.6, "yellow chance")
    v, _, isPriced = SP.Score(s, 10, { prof = "X__test", prefer = "cheap", costOf = priced({}) })
    t:near(v, 1 / 2, 1e-12, "no price: per material"); t:ok(not isPriced, "and says it isn't priced")
    t:eq((SP.Score(s, 70, { prof = "X__test" })), 0, "grey: not a choice")
    t:eq((SP.Score({ recipe = "Seen__test", mats = { [MAT_A] = 1 } }, 10, { prof = "X__test" })), 0,
        "no colours and not seen at this skill: not a choice")
end)

ns:Register("test", "professions: cheap goes by price, and by materials while one has no price", function(t)
    local SP = ns.skillPlan
    local a, b = step("A__test", { [MAT_A] = 1 }), step("B__test", { [MAT_B] = 3 })
    local cheap = { prefer = "cheap", costOf = priced({ [MAT_A] = 100, [MAT_B] = 10 }) }
    local _, order, reaches = SP._simulate("X__test", { a, b }, 1, 20, {}, cheap)
    t:eq(order[1], b, "B costs 30c a point, A 100c: B"); t:ok(reaches, "1 -> 20 reaches")
    _, order = SP._simulate("X__test", { a, b }, 1, 20, {}, { prefer = "materials" })
    t:eq(order[1], a, "by materials: A (one each)")
    _, order = SP._simulate("X__test", { a, b }, 1, 20, {}, { prefer = "cheap", costOf = priced({ [MAT_B] = 10 }) })
    t:eq(order[1], a, "A unpriced: copper and counts don't compare, so by materials")
end)

ns:Register("test", "professions: use-bags makes what you carry first", function(t)
    local SP = ns.skillPlan
    local a, b = step("A__test", { [MAT_A] = 1 }), step("B__test", { [MAT_B] = 3 })
    local crafts, order = SP._simulate("X__test", { a, b }, 1, 20, { [MAT_B] = 30 }, { prefer = "use-bags" })
    t:eq(order[1], b, "B's materials are in your bags: B first")
    t:eq(crafts[b], 10, "as many as your bags make (30 / 3)")
    t:eq(order[2], a, "then the one with fewest materials")
end)

ns:Register("test", "professions: a fish recipe counts only while you carry the fish", function(t)
    local SP = ns.skillPlan
    local f, a = step("Fish__test", { [FISH] = 1 }), step("A__test", { [MAT_A] = 2 })
    local _, order = SP._simulate("X__test", { f, a }, 1, 5, {})
    for _, s in ipairs(order) do t:ok(s ~= f, "no fish in your bags: no fish recipe") end
    t:eq(order[1], a, "the other recipe instead")
    local crafts
    crafts, order = SP._simulate("X__test", { f, a }, 1, 5, { [FISH] = 2 })
    t:eq(order[1], f, "fish in your bags: the fish recipe")
    t:eq(crafts[f], 2, "as many as you carry")
end)

ns:Register("test", "professions: the window's recipes join the steps, sorted, whole ones only", function(t)
    local SP = ns.skillPlan
    local a = step("A__test", { [MAT_A] = 1 })
    local known = {
        ["A__test"] = { diff = "optimal", reagents = { [MAT_A] = 1 } },
        ["Zeta__test"] = { diff = "optimal", item = 7, reagents = { [MAT_B] = 1 } },
        ["Alpha__test"] = { diff = "medium", reagents = { [MAT_A] = 2 } },
        ["Part__test"] = { diff = "optimal", reagents = { [MAT_A] = 1 }, partial = true },
        ["Empty__test"] = { diff = "optimal", reagents = {} },
    }
    local out = SP.Candidates("Blacksmithing", { a }, known)
    t:eq(#out, 3, "the step, then two whole window recipes")
    t:eq(out[1], a, "the profession's own step first, once")
    t:eq(out[2].recipe, "Alpha__test", "then by name"); t:eq(out[3].recipe, "Zeta__test", "")
    t:ok(out[3].observed, "marked as seen in the window"); t:eq(out[3].item, 7, "with its item")
    t:eq(out[3].mats[MAT_B], 1, "and its materials"); t:eq(out[3].station, "anvil", "and the profession's station")
    t:eq(#SP.Candidates("X__test", nil, nil), 0, "nothing known: nothing")
end)

ns:Register("test", "professions: a recipe seen only in the window plans from the skill Flow saw it at", function(t)
    local SP = ns.skillPlan
    local known = { ["Obs__test"] = { diff = "optimal", reagents = { [MAT_A] = 1 } } }
    with(ns.recipes, "Known", function(_, prof) if prof == "X__test" then return known, 50 end end, function()
        local list = SP.Candidates("X__test", {}, known)
        local crafts, order, reaches, _, reached = SP._simulate("X__test", list, 50, 60, {})
        t:eq(order[1] and order[1].recipe, "Obs__test", "planned at the skill it was seen at")
        t:eq(crafts[order[1]], 1, "for that point: past it Flow doesn't know its colour")
        t:ok(not reaches, "so the plan stops"); t:eq(reached, 51, "at 51")
        local _, none = SP._simulate("X__test", list, 52, 60, {})
        t:eq(#none, 0, "not seen at 52: not planned")
    end)
    local _, order, reaches, _, reached = SP._simulate("X__test", {}, 10, 20, {})
    t:eq(#order, 0, "no recipes: nothing to make"); t:ok(not reaches, "doesn't reach"); t:eq(reached, 10, "stays at 10")
end)
