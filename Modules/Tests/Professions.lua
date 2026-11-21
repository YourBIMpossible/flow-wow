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
