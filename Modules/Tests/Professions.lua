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
-- W4c: the skill-up plan is worked out (SP.Score), not a fixed path: from the
-- colour the profession window showed, what its materials cost, and what's in
-- your bags. W4d: no colour thresholds of Flow's own; only the window's colour
-- at the skill Flow saw it at counts.
-------------------------------------------------------------------------------

local MAT_A, MAT_B, FISH = 990001, 990002, 6289   -- (6289: Raw Longjaw Mud Snapper, fished)
local function step(name, mats) return { recipe = name, mats = mats } end
local function priced(list) return function(id) return list[id] end end
-- The profession window seen at `rank`, each recipe at the colour given.
local function seenAt(rank, diffs, fn)
    local known = {}
    for name, diff in pairs(diffs) do known[name] = { diff = diff, reagents = {} } end
    with(ns.recipes, "Known", function(_, prof) if prof == "X__test" then return known, rank end end, fn)
end

ns:Register("test", "professions: SP.Score rates a step by skill per copper, else per material", function(t)
    local SP = ns.skillPlan
    local s = step("A__test", { [MAT_A] = 2 })
    seenAt(10, { A__test = "optimal" }, function()
        local v, c, isPriced = SP.Score(s, 10, { prof = "X__test", prefer = "cheap", costOf = priced({ [MAT_A] = 50 }) })
        t:near(v, 1 / 100, 1e-12, "orange, 100c a craft: 1 point per 100c")
        t:eq(c, 1, "orange: a point every craft"); t:ok(isPriced, "priced")
        v, _, isPriced = SP.Score(s, 10, { prof = "X__test", prefer = "cheap", costOf = priced({}) })
        t:near(v, 1 / 2, 1e-12, "no price: per material"); t:ok(not isPriced, "and says it isn't priced")
        t:eq((SP.Score(s, 11, { prof = "X__test" })), 0, "not seen at 11: colour unknown, not a choice")
    end)
    seenAt(55, { A__test = "medium" }, function()
        local v, c = SP.Score(s, 55, { prof = "X__test", prefer = "cheap", costOf = priced({ [MAT_A] = 50 }) })
        t:near(v, 0.6 / 100, 1e-12, "yellow: 0.6 of a point per 100c"); t:eq(c, 0.6, "yellow chance")
    end)
    seenAt(70, { A__test = "trivial" }, function()
        t:eq((SP.Score(s, 70, { prof = "X__test" })), 0, "grey in the window: not a choice")
    end)
    t:eq((SP.Score(s, 10, { prof = "X__test" })), 0, "never seen in the window: not a choice")
end)

ns:Register("test", "professions: no step carries a colour threshold; chance is the window's alone", function(t)
    for prof, g in ns:Each("profGuide") do
        for _, s in ipairs(g.steps or {}) do
            t:ok(s.yellow == nil and s.green == nil and s.grey == nil, prof .. ": " .. s.recipe .. " has no colour thresholds")
        end
        for _, nd in ipairs(g.nodes or {}) do
            t:ok(nd.yellow == nil and nd.green == nil and nd.grey == nil, prof .. ": node " .. nd.item .. " has no colour thresholds")
        end
    end
end)

-------------------------------------------------------------------------------
-- W4e (prov-guides-2): nothing a guide or site listed. What a recipe is
-- learned at, a vein's skill, prices, drops and tier levels come from what
-- the game showed this character, and are unknown until it has.
-------------------------------------------------------------------------------

-- ns.db.prof with `fields` set, put back after.
local function withProf(fields, fn)
    local made = ns.db.prof == nil
    if made then ns.db.prof = {} end
    local old = {}
    for k, v in pairs(fields) do old[k] = ns.db.prof[k]; ns.db.prof[k] = v end
    local ok, err = pcall(fn)
    for k in pairs(fields) do ns.db.prof[k] = old[k] end
    if made then ns.db.prof = nil end
    if not ok then error(err, 0) end
end

ns:Register("test", "professions: the guides list no learn skill, for recipes or veins", function(t)
    local steps, nodes = 0, 0
    for prof, g in ns:Each("profGuide") do
        for _, s in ipairs(g.steps or {}) do
            steps = steps + 1
            t:eq(s.learn, nil, prof .. ": " .. tostring(s.recipe) .. " lists no learn skill")
        end
        for _, nd in ipairs(g.nodes or {}) do
            nodes = nodes + 1
            t:eq(nd.learn, nil, prof .. ": node " .. tostring(nd.item) .. " lists no skill")
        end
    end
    t:ok(steps > 0 and nodes > 0, "the guides are still there to check")
end)

ns:Register("test", "professions: SP.VeinsHere is the veins on this map, with no skill pick", function(t)
    local SP = ns.skillPlan
    local where = { [1] = { { { x = 1 } }, true, "Vein A" }, [2] = { { { x = 2 }, { x = 3 } }, false, "Vein B" },
                    [3] = { { { x = 4 } }, true, "Vein C" }, [4] = { {}, true, "Vein D" } }
    local pts, names = SP.VeinsHere({ { item = 1 }, { item = 2 }, { item = 3 }, { item = 4 }, { item = 5 } },
        function(item) local w = where[item]; if w then return w[1], w[2], w[3] end end)
    t:eq(#pts, 2, "only the spots on this map")
    t:eq(table.concat(names, ","), "Vein A,Vein C", "every vein here, in the guide's order: none picked by skill")
    pts, names = SP.VeinsHere(nil, function() end)
    t:eq(#pts + #names, 0, "no nodes: nothing")
    t:eq(SP.BestNode, nil, "the pick by a listed vein skill is gone")
end)

ns:Register("test", "professions: item sources list no skill, yield, rate, mobs or price", function(t)
    local n, looted = 0, 0
    for id, s in ns:Each("itemSource") do
        n = n + 1
        local what = tostring(s.name or id)
        t:eq(s.skill, nil, what .. ": no node skill"); t:eq(s.yield, nil, what .. ": no yield")
        t:eq(s.rate, nil, what .. ": no drop rate"); t:eq(s.price, nil, what .. ": no price")
        t:eq(s.drops, nil, what .. ": no mob names")
        if s.smelt then t:eq(s.smelt.skill, nil, what .. ": no smelting skill") end
        if s.looted then looted = looted + 1 end
    end
    t:ok(n > 0 and looted > 0, "the sources are still there to check")
end)

ns:Register("test", "professions: a price is only what a vendor's window showed", function(t)
    local SP = ns.skillPlan
    local saved = ns.db.prices
    ns.db.prices = nil
    t:eq(SP.Price(2678), nil, "never seen at a vendor: unknown")
    ns.db.prices = { [2678] = 12, [2692] = "x" }
    t:eq(SP.Price(2678), 12, "seen at a vendor: that price")
    t:eq(SP.Price(2692), nil, "not a number: unknown")
    t:eq(SP.Price(999999001), nil, "an item Flow never saw sold: unknown")
    ns.db.prices = saved
end)

ns:Register("test", "professions: kills and node counts are said only when your own loot gives them", function(t)
    local SP = ns.skillPlan
    t:eq(SP.KillsFor(10, { 0.5 }), 20, "half of your kills dropped one: 20 kills for 10")
    t:eq(SP.KillsFor(10, { 0.5, 0.25 }), 27, "two materials that both do: their mean")
    t:eq(SP.KillsFor(10, { 0.5, false }), nil, "one of them never seen to drop: unknown")
    t:eq(SP.KillsFor(10, {}), nil, "nothing seen: unknown"); t:eq(SP.KillsFor(10, nil), nil, "no rates: unknown")
    t:eq(SP.FarmText("Meat", "0/5", 20), "Loot Meat 0/5 (about 20 kills)", "known: said as about")
    t:eq(SP.FarmText("Meat", "0/5", nil), "Loot Meat 0/5", "unknown: no number made up")
    local d = SP.FarmDetails(nil, 5, {})
    t:ok(d[1]:find("unknown", 1, true) ~= nil, "kills unknown: said so")
    t:ok(d[2]:find("unknown to Flow", 1, true) ~= nil, "mobs unknown: said so")
    d = SP.FarmDetails(20, 5, { "A__test", "B__test" })
    t:ok(d[1]:find("About 20 kills for 5", 1, true) ~= nil, "known kills: about, from your own loot")
    t:eq(d[2], "Drops from: A__test, B__test.", "known mobs: named")
    t:eq(SP.GatherText("Mining", "Vein__test", { "4 Ore", "2 Stone" }), "Mine Vein__test for 4 Ore, 2 Stone", "no node count in a gather step")
    t:eq(SP.GatherText("Herbalism", "Herb__test", { "1 Leaf" }), "Gather Herb__test for 1 Leaf", "nor for herbs")
    t:ok(SP.GATHER_UNKNOWN:find("unknown to Flow", 1, true) ~= nil, "and the step says what Flow doesn't know")
end)

ns:Register("test", "professions: Flow's own Fishing estimate is said as about", function(t)
    local SP = ns.skillPlan
    t:ok(SP.PaceIsEstimate("Fishing"), "Fishing's pace is Flow's own estimate")
    t:ok(not SP.PaceIsEstimate("Mining"), "Mining aims for a tier cap, not an estimate")
    t:ok(not SP.PaceIsEstimate(nil), "no profession: no estimate")
    t:eq(SP.AimText("Fishing", 75), "about 75", "an estimate: about")
    t:eq(SP.AimText("Mining", 150), "150", "a cap: the number")
    t:eq(SP.AimText("Fishing", 75, 20), "about 75 at level 20 (Flow's own estimate)", "and named as Flow's estimate")
    t:eq(SP.AimText("Mining", 150, 20), "150 at level 20 (the highest cap you can train)", "a cap is named as a cap")
    for id, s in ns:Each("itemSource") do
        if s.share ~= nil then t:ok(s.fished == true and s.share > 0 and s.share <= 1, tostring(s.name or id) .. ": a share is only on a fished item, a part of 1") end
    end
end)

ns:Register("test", "professions: Places lists no trainer names, NPC IDs or spots of its own", function(t)
    for _, key in ipairs({ "alliance-elwynn", "druid", "horde" }) do
        t:eq(ns:Get("trainerNames", key), nil, "trainerNames " .. key .. ": gone")
    end
    for _, key in ipairs({ "alliance-elwynn", "druid", "horde-cities" }) do
        t:eq(ns:Get("npcIds", key), nil, "npcIds " .. key .. ": gone")
    end
    t:eq(ns:Get("skillSpots", "alliance-elwynn"), nil, "skillSpots alliance-elwynn: gone")
    t:eq(#ns.places:SpotsFor("Fishing"), 0, "no fishing spot of Flow's own")
    -- A list another module registers is still used.
    local P = ns.places
    with(ns, "Each", function(_, kind)
        if kind == "trainerNames" then return pairs({ t__test = { ["Test__test"] = { "Somebody__test" } } }) end
        return pairs({})
    end, function()
        with(ns.db, "places", {}, function()
            with(ns, "services", nil, function()
                local names = P:TrainersFor("Test__test")
                t:eq(#names, 1, "a registered list is read"); t:eq(names[1], "Somebody__test", "its name")
                t:eq(#P:TrainersFor("Other__test"), 0, "nothing registered, trained with or titled: none")
            end)
        end)
    end)
end)

ns:Register("test", "professions: the map card lists no zone levels or fishing skills of Flow's own", function(t)
    local ZL = ns.mapZoneLevels
    if not ZL then t:ok(false, "MapZoneLevels.lua not loaded") return end
    t:eq(ZL.ZONES, nil, "no zone table")
    local none = function() return nil end
    for _, id in ipairs({ 1436, 1434, 1453, 1418 }) do
        local c = ZL.Card(id, "Zone__test", 30, none)
        t:eq(c.level, "Level unknown", id .. ": the game gave no range: unknown, no number")
        t:eq(c.fish, nil, id .. ": no fishing skill line")
        t:ok(c.r == c.g and c.g == c.b, id .. ": unknown is grey, not a difficulty colour")
    end
    t:eq(ZL.Levels(1436, function() return 10, 20, 0, 0 end), 10, "the client's range is read as given")
    t:eq(select(2, ZL.Levels(1436, function() return 10, 20 end)), 20, "both ends")
    t:eq(ZL.Levels(1436, function() return 0, 0 end), nil, "0-0 is no range: unknown")
    t:eq(ZL.Levels(1436, function() return 20, 10 end), nil, "an upside-down range: unknown")
    t:eq(ZL.Levels(1436, function() error("no such map") end), nil, "the call failing: unknown")
    t:eq(ZL.Levels(nil, function() return 10, 20 end), nil, "no zone: unknown")
    t:eq(ZL.Card(1436, "Zone__test", 12, function() return 12, 12 end).level, "Level 12", "one level: said once")
    with(ZL, "FISH", { [1436] = { 20, { 6358, 60, "Fish__test" } } }, function()
        t:eq(ZL.Card(1436, "Zone__test", 12, none).fish, "Fishing", "catch records: a fishing line (for the Shift list), still no skill")
        t:eq(ZL.Card(1429, "Zone__test", 12, none).fish, nil, "none for a zone without records")
    end)
end)

ns:Register("test", "professions: a tier's level is only what a trainer's window said", function(t)
    local SP, P = ns.skillPlan, ns.professions
    t:eq(SP.TIER_LEVEL, nil, "no list of tier levels");
    local tier = SP.Tier("Mining", 60, 75, 3)
    t:eq(tier.level, nil, "never read at a trainer: the level is unknown")
    t:eq(tier.skill, 50, "25 below the cap"); t:ok(tier.ready, "unknown holds nothing back: go and see the trainer")
    t:eq(SP.TierNeeds(SP.Tier("Mining", 40, 75, 3)), "needs skill 50; level unknown: check the trainer", "and the step says it is unknown")
    for _, cap in ipairs({ 75, 150, 225 }) do
        t:eq(SP.Tier("Mining", cap - 30, cap, 60).level, nil, cap .. ": no level of Flow's own")
    end
    local seen = { cap = 75, level = 10, skill = 50 }
    tier = SP.Tier("Mining", 60, 75, 8, seen)
    t:eq(tier.level, 10, "read at the trainer: that level"); t:ok(not tier.ready, "level 8 of 10: not yet")
    t:eq(SP.TierNeeds(tier), "needs level 10 and skill 50", "said as the trainer said it")
    t:ok(SP.Tier("Mining", 60, 75, 10, seen).ready, "at 10: ready")
    tier = SP.Tier("Mining", 40, 75, 1, { cap = 75, level = 0, skill = 50 })
    t:eq(tier.level, 0, "the trainer asked no level: 0, known"); t:eq(SP.TierNeeds(tier), "needs skill 50", "so none is named")
    t:eq(SP.TierBlock("Journeyman Mining", SP.Tier("Mining", 75, 75, 8, seen), 8), "Journeyman Mining needs level 10", "capped, level short: says the level read")
    t:eq(SP.TierBlock("Artisan Cooking", { skill = 225 }, 60), "Artisan Cooking: needs skill 225; level unknown: check the trainer", "no level read: unknown, no number")
    t:eq(SP.TierBlock("X", { skill = 50, level = 0, wait = "it was red at the trainer" }, 5), "X: it was red at the trainer", "a wait is said as it is")
    t:ok(P.TierReady("Mining", 60, 75, 3), "P.TierReady: no level known, nothing held back")
    t:ok(not P.TierReady("Mining", 60, 75, 8, function() return seen end), "the trainer's level holds it back")
    t:ok(not P.TierReady("Mining", 40, 75, 60), "below 25 under the cap: not yet")
end)

ns:Register("test", "professions: a trainer's window is where a recipe's learn skill comes from", function(t)
    local TR, SP = ns.trainer, ns.skillPlan
    local into = {}
    t:ok(TR.RecordLearn(into, "A__test", "available", 50), "a number the game gave: kept")
    t:eq(into.A__test, 50, "under the name the trainer showed")
    t:ok(TR.RecordLearn(into, "A__test", "used", 55), "read again: the newer read wins")
    t:eq(into.A__test, 55, "the newer value")
    t:ok(not TR.RecordLearn(into, "B__test", "header", 10), "a header: not a recipe")
    t:ok(not TR.RecordLearn(into, "C__test", "available", nil), "no number from the game: nothing kept")
    t:ok(not TR.RecordLearn(into, "", "available", 10) and not TR.RecordLearn(into, nil, "available", 10), "no name: nothing kept")
    t:ok(not TR.RecordLearn(nil, "D__test", "available", 10), "nowhere to keep it: no error")
    t:eq(into.B__test, nil, "the header left nothing"); t:eq(into.C__test, nil, "the unread row left nothing")

    local s = { recipe = "A__test", mats = {} }
    withProf({ recipeLearn = { X__test = { A__test = 55 } } }, function()
        t:eq(SP.LearnSkill("X__test", s), 55, "SP.LearnSkill: what the trainer asked")
        t:eq(SP.LearnSkill("Y__test", s), nil, "another profession: unknown")
        t:eq(SP.LearnSkill("X__test", { recipe = "Never__test", mats = {} }), nil, "not seen at a trainer: unknown, not a guess")
    end)
    withProf({ recipeLearn = false }, function()
        t:eq(SP.LearnSkill("X__test", s), nil, "nothing saved: unknown")
    end)
    t:eq(SP.LearnSkill("X__test", nil), nil, "no step: unknown")
end)

ns:Register("test", "professions: a recipe item's own Requires line gives its learn skill", function(t)
    local SP = ns.skillPlan
    -- (The pattern Actions.lua builds from the game's ITEM_MIN_SKILL on an
    -- English client, as its comment gives it; the game's own text isn't stood in for.)
    local pattern = "^Requires (.-) %((%d+)%)$"
    local lines = { { left = "Recipe: Test__test" }, { left = "Requires Cooking (50)" }, { left = "Use: Teaches you..." } }
    t:eq(SP.LearnFromLines("Cooking", lines, pattern), 50, "Requires Cooking (50): 50")
    t:eq(SP.LearnFromLines("Tailoring", lines, pattern), nil, "another profession's line: unknown")
    t:eq(SP.LearnFromLines("Cooking", { { left = "Requires Level 20" }, { left = 5 }, "x" }, pattern), nil, "no such line: unknown")
    t:eq(SP.LearnFromLines("Cooking", nil, pattern), nil, "no tooltip: unknown")
    t:eq(SP.LearnFromLines("Cooking", lines, nil), nil, "no pattern: unknown")
end)

ns:Register("test", "professions: unknown learn skill holds nothing back and says so", function(t)
    local SP = ns.skillPlan
    t:eq(SP.TrainNow(nil, 10), true, "unknown: go and see the trainer")
    t:eq(SP.TrainNow(50, 49), false, "the trainer asked 50, you have 49: not yet")
    t:eq(SP.TrainNow(50, 50), true, "at 50: now")
    t:eq(SP.TrainNow(50, nil), false, "asked 50, skill not known: not yet")
    t:eq(SP.LEARN_UNKNOWN, "learn skill unknown: check the trainer", "the words the step shows")
    t:eq(SP.RecipeDue(nil, 10), true, "a bought recipe with no known skill isn't held back")
    t:eq(SP.RecipeWait(true, false, false, "Recipe__test", "X__test", nil, 10), "use the recipe in your bags first",
        "in your bags, skill unknown: no made-up number in the wait")
end)

ns:Register("test", "professions: window reads bound a recipe's colour between two skills", function(t)
    local R, SP = ns.recipes, ns.skillPlan
    local h = R.Observe(nil, { A__test = { diff = "optimal" }, B__test = { diff = "medium" } }, 10)
    t:eq(h.A__test.optimal[1], 10, "first read: from 10"); t:eq(h.A__test.optimal[2], 10, "to 10")
    t:eq(R.Observe(h, { A__test = { diff = "optimal" }, B__test = { diff = "easy" } }, 20.7), h, "the same history, added to")
    t:eq(h.A__test.optimal[2], 20, "orange again at 20: seen from 10 to 20")
    t:eq(h.B__test.medium[2], 10, "yellow only at 10"); t:eq(h.B__test.easy[1], 20, "green from 20")
    R.Observe(h, { A__test = { diff = "optimal" } }, 5)
    t:eq(h.A__test.optimal[1], 5, "a lower read widens it down")
    R.Observe(h, { A__test = { diff = "trivial" } }, nil)
    t:eq(h.A__test.trivial, nil, "no skill with the read: nothing kept")
    R.Observe(h, { C__test = { reagents = {} } }, 30)
    t:eq(h.C__test, nil, "no colour in the read: nothing kept")

    t:eq(R.ColourAt(h, "A__test", 15), "optimal", "between two orange reads: orange")
    t:eq(R.ColourAt(h, "A__test", 5), "optimal", "at a read: that colour")
    t:eq(R.ColourAt(h, "A__test", 21), nil, "past the highest read: unknown, never carried on")
    t:eq(R.ColourAt(h, "A__test", 4), nil, "below the lowest read: unknown")
    t:eq(R.ColourAt(h, "B__test", 15), nil, "between yellow at 10 and green at 20: unknown")
    t:eq(R.ColourAt(h, "Never__test", 15), nil, "never read: unknown")
    t:eq(R.ColourAt(nil, "A__test", 15), nil, "no history: unknown")

    -- chance() reads it: the window was last seen at 20, the plan asks about 15.
    local s = step("A__test", { [MAT_A] = 1 })
    with(R, "History", function(_, prof) if prof == "X__test" then return h end end, function()
        seenAt(20, { A__test = "optimal", B__test = "easy" }, function()
            local _, c = SP.Score(s, 15, { prof = "X__test" })
            t:eq(c, 1, "15, between orange reads at 5 and 20: a point a craft")
            t:eq((SP.Score(s, 21, { prof = "X__test" })), 0, "21, past every read: unknown, not a choice")
            t:eq((SP.Score(step("B__test", { [MAT_A] = 1 }), 15, { prof = "X__test" })), 0, "between two colours: not a choice")
        end)
    end)
end)

ns:Register("test", "professions: materials stand in only when the window showed both at one colour", function(t)
    local SP = ns.skillPlan
    local DROP_A, DROP_B = 2672, 769   -- wolf and boar meat: dropped, in Flow's item sources
    local steps = { step("A__test", { [DROP_A] = 1 }), step("B__test", { [DROP_B] = 1 }) }
    seenAt(5, { A__test = "easy", B__test = "easy" }, function()
        local ids = SP.Alternatives(steps, DROP_A, "X__test", 5)
        t:eq(ids[1], DROP_A, "itself first"); t:eq(ids[2], DROP_B, "both green at 5: the other stands in")
        t:eq(#SP.Alternatives(steps, DROP_A, "X__test", 6), 1, "at 6 their colours are unknown: just itself")
    end)
    seenAt(5, { A__test = "easy", B__test = "optimal" }, function()
        t:eq(#SP.Alternatives(steps, DROP_A, "X__test", 5), 1, "different colours: just itself")
    end)
    t:eq(#SP.Alternatives(steps, DROP_A), 1, "no profession or skill: just itself")
end)

ns:Register("test", "professions: cheap goes by price, and by materials while one has no price", function(t)
    local SP = ns.skillPlan
    local a, b = step("A__test", { [MAT_A] = 1 }), step("B__test", { [MAT_B] = 3 })
    seenAt(1, { A__test = "optimal", B__test = "optimal" }, function()
        local cheap = { prefer = "cheap", costOf = priced({ [MAT_A] = 100, [MAT_B] = 10 }) }
        local _, order, reaches, _, reached = SP._simulate("X__test", { a, b }, 1, 20, {}, cheap)
        t:eq(order[1], b, "B costs 30c a point, A 100c: B")
        t:ok(not reaches, "past the skill Flow saw the colours: stops"); t:eq(reached, 2, "at 2")
        _, order = SP._simulate("X__test", { a, b }, 1, 20, {}, { prefer = "materials" })
        t:eq(order[1], a, "by materials: A (one each)")
        _, order = SP._simulate("X__test", { a, b }, 1, 20, {}, { prefer = "cheap", costOf = priced({ [MAT_B] = 10 }) })
        t:eq(order[1], a, "A unpriced: copper and counts don't compare, so by materials")
    end)
end)

ns:Register("test", "professions: use-bags makes what you carry first", function(t)
    local SP = ns.skillPlan
    local a, b = step("A__test", { [MAT_A] = 1 }), step("B__test", { [MAT_B] = 3 })
    seenAt(1, { A__test = "easy", B__test = "easy" }, function()
        local crafts, order = SP._simulate("X__test", { a, b }, 1, 20, { [MAT_B] = 6 }, { prefer = "use-bags" })
        t:eq(order[1], b, "B's materials are in your bags: B first")
        t:eq(crafts[b], 2, "as many as your bags make (6 / 3)")
        t:eq(order[2], a, "then the one with fewest materials")
    end)
end)

ns:Register("test", "professions: a fish recipe counts only while you carry the fish", function(t)
    local SP = ns.skillPlan
    local f, a = step("Fish__test", { [FISH] = 1 }), step("A__test", { [MAT_A] = 2 })
    seenAt(1, { Fish__test = "easy", A__test = "easy" }, function()
        local _, order = SP._simulate("X__test", { f, a }, 1, 5, {})
        for _, s in ipairs(order) do t:ok(s ~= f, "no fish in your bags: no fish recipe") end
        t:eq(order[1], a, "the other recipe instead")
        local crafts
        crafts, order = SP._simulate("X__test", { f, a }, 1, 5, { [FISH] = 2 })
        t:eq(order[1], f, "fish in your bags: the fish recipe")
        t:eq(crafts[f], 2, "as many as you carry")
    end)
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

-------------------------------------------------------------------------------
-- W4d: the skill to aim for at your level is a tier cap, from the level each
-- tier asks as trainers showed Flow; no level-by-level curve from a guide.
-------------------------------------------------------------------------------

ns:Register("test", "professions: the level target is the highest tier cap the trainers' levels allow", function(t)
    local PT = ns.api.ProfessionTarget
    local target, unknown = PT(30, {})
    t:eq(target, 75, "nothing read at a trainer: Apprentice's cap")
    t:eq(unknown, 75, "and what's past 75 is unknown")
    local seen = { Herbalism = { cap = 75, level = 0 }, Mining = { cap = 150, level = 20 } }
    target, unknown = PT(10, seen)
    t:eq(target, 150, "Journeyman asks no level: 150 at 10")
    t:eq(unknown, nil, "Expert's level is known (20), just not met")
    target, unknown = PT(25, seen)
    t:eq(target, 225, "Expert asks 20: 225 at 25")
    t:eq(unknown, 225, "Artisan's level never read: unknown past 225")
    t:eq((PT(25, { Mining = { cap = 150, level = 20 } })), 75, "Journeyman's level unknown: no climb past 75")
    t:eq((PT(60, { A = { cap = 75, level = 0 }, B = { cap = 150, level = 20 }, C = { cap = 225, level = 35 } })), 300, "all read and met: 300")
    t:eq((PT(60, { A = { cap = 75 } })), 75, "a read with no level is not a level")
end)


ns:Register("test", "professions: a material is outgrown only once the window showed its recipe grey", function(t)
    local D = ns.disposition
    local guide = { steps = { { recipe = "Lin__test", mats = { [MAT_A] = 1 } }, { recipe = "Wool__test", mats = { [MAT_B] = 1 } } } }
    local seen = { Lin__test = { diff = "trivial" }, Wool__test = { diff = "easy" } }
    t:eq(D.OutgrownBy(MAT_A, 80, guide, seen, 80), "Lin__test", "grey in the window at 80: past it")
    t:eq(D.OutgrownBy(MAT_A, 79, guide, seen, 80), nil, "below the skill it was seen grey at: not known")
    t:eq(D.OutgrownBy(MAT_B, 80, guide, seen, 80), nil, "green: still wanted")
    t:eq(D.OutgrownBy(MAT_A, 300, guide), nil, "no window seen: never outgrown")
    t:ok(not D.StepPast({ recipe = "Lin__test", use = { 1, 40 }, grey = 60 }, 300), "a fixed range or grey level is not read")
end)