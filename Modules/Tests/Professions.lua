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
-- P2 PR 7: the reservation ledger for money and bag slots (Modules/Reserve.lua).
-- Pure: the snapshot is always made up here, the game is never read.
-------------------------------------------------------------------------------

-- grants -> { [step key] = grant }
local function grantsByStep(grants)
    local by = {}
    for _, g in ipairs(grants) do by[g.claim.step] = g end
    return by
end
-- grants -> "res:step=got/short ..." in the order they were resolved
local function grantLine(grants)
    local parts = {}
    for _, g in ipairs(grants) do
        parts[#parts + 1] = string.format("%s:%s=%s/%s%s", g.claim.res, tostring(g.claim.step), tostring(g.got),
            tostring(g.short), g.unknown and ("?" .. g.unknown) or "")
    end
    return table.concat(parts, " ")
end
local function snap(money, general, all)
    return { money = money, slots = general and { general = general, all = all or general } or nil }
end

ns:Register("test", "reserve: the selected step's money and slot claims come first", function(t)
    local R = ns.reserve
    local claims = {
        { activity = "quest", step = "train:class", res = "money", n = 800, milestone = true },
        { activity = "professions", step = "train:Mining", res = "money", n = 500 },
        { activity = "quest", step = "buy:1", res = "slots", n = 2 },
        { activity = "professions", step = "buy:2", res = "slots", n = 2 },
    }
    local ranks = { quest = 1, professions = 2 }
    local plain = grantsByStep(R.Resolve(snap(1000, 3), claims, { priority = ranks }))
    t:eq(plain["train:class"].got, 800, "nothing picked: the milestone is paid first")
    t:eq(plain["train:Mining"].got, 0, "and the profession tier waits")
    t:eq(plain["train:Mining"].short, 500, "500 short")
    t:eq(plain["train:Mining"].before, 800, "with 800 held ahead of it")
    t:eq(plain["buy:1"].got, 2, "slots: the quest's claim first")
    t:eq(plain["buy:2"].got, 1, "the other gets what's left")
    t:eq(plain["buy:2"].short, 1, "and is one short")
    local picked = grantsByStep(R.Resolve(snap(1000, 3), claims, { priority = ranks, selected = { professions = "train:Mining" } }))
    t:eq(picked["train:Mining"].got, 500, "picked: the profession tier is paid first, before a milestone")
    t:eq(picked["train:class"].got, 0, "and class training waits")
    t:eq(picked["buy:1"].got, 2, "a pick moves only its own step: the slot claims stay as they were")
    local slotPick = grantsByStep(R.Resolve(snap(1000, 3), claims, { priority = ranks, selected = { professions = "buy:2" } }))
    t:eq(slotPick["buy:2"].got, 2, "a picked step's slot claim comes first")
    t:eq(slotPick["buy:1"].got, 1, "the quest's then gets the rest")
    local other = grantsByStep(R.Resolve(snap(1000, 3), claims, { priority = ranks, selected = { quest = "train:Mining" } }))
    t:eq(other["train:Mining"].got, 0, "the same key picked in another activity is not this step")
end)

ns:Register("test", "reserve: required before optional, then priority, then the step key", function(t)
    local R = ns.reserve
    local defs = { priority = { quest = 1, professions = 2 } }
    local g = R.Resolve(snap(nil, 4), {
        { activity = "quest", step = "a:optional", res = "slots", n = 1, required = false },
        { activity = "professions", step = "b:required", res = "slots", n = 1 },
        { activity = "professions", step = "c:forQuest", res = "slots", n = 1, priority = 1 },
        { activity = "quest", step = "d:required", res = "slots", n = 1, required = true },
        { activity = "professions", step = "a:required", res = "slots", n = 1 },
    }, defs)
    t:eq(grantLine(g), "slots:c:forQuest=1/0 slots:d:required=1/0 slots:a:required=1/0 slots:b:required=1/0 slots:a:optional=0/1",
        "required first; a claim's own priority beats its activity's; then the key; the optional one last, and short")
    -- Money: milestone, then required, then priority, then the cheaper, then the key.
    local m = R.Resolve(snap(10000), {
        { activity = "professions", step = "z", res = "money", n = 10 },
        { activity = "professions", step = "y", res = "money", n = 10 },
        { activity = "professions", step = "x", res = "money", n = 5 },
        { activity = "quest", step = "w", res = "money", n = 900 },
        { activity = "quest", step = "v", res = "money", n = 1, required = false },
        { activity = "professions", step = "u", res = "money", n = 2000, milestone = true },
    }, defs)
    t:eq(grantLine(m), "money:u=2000/0 money:w=900/0 money:x=5/0 money:y=10/0 money:z=10/0 money:v=1/0",
        "milestone, the quest's (priority) before the cheaper profession ones, cheaper first, key, optional last")
    t:eq(m.committed.money, 2926, "all of it fits")
    t:eq(m.left.money, 7074, "and the rest is free")
    -- No priorities given: every activity ranks the same.
    local flat = R.Resolve(snap(100), {
        { activity = "professions", step = "b", res = "money", n = 60 },
        { activity = "quest", step = "a", res = "money", n = 70 },
    })
    t:eq(grantLine(flat), "money:b=60/0 money:a=0/70", "without priorities the cheaper goes first")
end)

ns:Register("test", "reserve: money keeps CommitCosts' order", function(t)
    local R, N = ns.reserve, ns.nav
    local oldSnap, oldGrants = R.snapshot, R.grants
    -- The cases of "route: steps that cost money are paid for together", through the ledger.
    local function same(list, money, what)
        local over, total = N.CommitCosts(list, money)
        R.Begin({ money = money })
        local grants = R.Finish(list)
        local mine = {}
        for _, g in ipairs(grants) do
            if g.short and g.short > 0 then mine[g.claim.step] = g.before end
        end
        t:eq(grants.committed.money, total, what .. ": the same total")
        t:eq(R.Committed("money"), total, what .. ": R.Committed says it too")
        for k, v in pairs(over) do t:eq(mine[k], v, what .. ": " .. k .. " is over, with the same amount ahead of it") end
        for k in pairs(mine) do t:ok(over[k] ~= nil, what .. ": " .. k .. " is over in both") end
    end
    local train = { key = "train:class", cost = 800, milestone = true }
    local riding = { key = "mount:riding", cost = 600 }
    local cheap = { key = "train:Cooking", cost = 100 }
    same({ riding, cheap, train }, 1000, "three steps, 10s")
    same({ riding, cheap, train }, 5000, "enough for all")
    same({ { key = "x", cost = 900, blockedBy = "needs Mining" }, cheap }, 200, "a held step")
    same({ { key = "a", cost = 700 }, { key = "b", cost = 700 } }, 1000, "two the same price")
    same({ { key = "big", cost = 900 }, { key = "small", cost = 50 }, { key = "mid", cost = 400 } }, 500, "a later one fits after one that didn't")
    same({ { key = "free", cost = 0 }, { key = "odd", cost = -5 }, cheap }, 100, "no cost and a negative cost")
    same({}, 100, "no steps")
    R.snapshot, R.grants = oldSnap, oldGrants
end)

ns:Register("test", "reserve: a unit is granted once", function(t)
    local R = ns.reserve
    -- Made-up claims from a fixed sequence (no math.random: the same every run).
    local seed = 12345
    local function rnd(n)
        seed = (seed * 1103 + 12347) % 65536
        return math.floor(seed / 7) % n
    end
    local acts, bad = { "quest", "professions", "other" }, 0
    for round = 1, 60 do
        local claims = {}
        for i = 1, 1 + rnd(12) do
            local res = rnd(2) == 0 and "money" or "slots"
            local c = { activity = acts[1 + rnd(3)], step = "s" .. rnd(8), res = res }
            if res == "money" then c.n = rnd(900) else c.n = rnd(5) end
            if rnd(4) == 0 then c.required = false end
            if rnd(5) == 0 then c.milestone = true end
            if rnd(7) == 0 then c.unknown = true end
            if rnd(9) == 0 then c.n = -c.n - 1 end
            if rnd(6) == 0 then c.priority = rnd(3) end
            claims[i] = c
        end
        local money, general = rnd(2000), rnd(8)
        local g = R.Resolve(snap(money, general, general + 4), claims,
            { priority = { quest = 1, professions = 2 }, selected = { quest = "s" .. rnd(8) } })
        local sum = { money = 0, slots = 0 }
        for _, x in ipairs(g) do
            sum[x.claim.res] = sum[x.claim.res] + (x.got or 0)
            if x.unknown then
                if x.got ~= nil or x.short ~= nil then bad = bad + 1 end
            elseif x.invalid then
                if x.got ~= 0 or x.short ~= 0 then bad = bad + 1 end
            elseif x.got < 0 or x.short < 0 or x.got + x.short ~= x.claim.n then
                bad = bad + 1
            end
        end
        if #g ~= #claims then bad = bad + 1 end
        if sum.money > money or sum.slots > general then bad = bad + 1 end
        if sum.money ~= g.committed.money or sum.slots ~= g.committed.slots then bad = bad + 1 end
        if g.left.money ~= money - sum.money or g.left.slots ~= general - sum.slots then bad = bad + 1 end
    end
    t:eq(bad, 0, "60 made-up sets: never more granted than there is, every claim answered once, got + short = asked")
end)

ns:Register("test", "reserve: the same claims in another order give the same grants", function(t)
    local R = ns.reserve
    local function claims()
        return {
            { activity = "quest", step = "train:class", res = "money", n = 800, milestone = true },
            { activity = "professions", step = "train:Mining", res = "money", n = 300 },
            { activity = "professions", step = "train:Herbalism", res = "money", n = 300 },
            { activity = "professions", step = "recipe:1", res = "money", n = 300, required = false },
            { activity = "professions", step = "train:Cooking", res = "money", unknown = true },
            { activity = "quest", step = "buy:9", res = "slots", n = 2 },
            { activity = "professions", step = "buy:2320", res = "slots", n = 2 },
            { activity = "professions", step = "buy:2321", res = "slots", n = 2, required = false },
        }
    end
    local defs = { priority = { quest = 1, professions = 2 } }
    local want = grantLine(R.Resolve(snap(1500, 3), claims(), defs))
    t:eq(want, "money:train:class=800/0 money:train:Herbalism=300/0 money:train:Mining=300/0 money:train:Cooking=nil/nil?price"
        .. " money:recipe:1=0/300 slots:buy:9=2/0 slots:buy:2320=1/1 slots:buy:2321=0/2", "the grants, in order")
    -- Reversed, and every rotation of the list.
    local list = claims()
    local reversed = {}
    for i = #list, 1, -1 do reversed[#reversed + 1] = list[i] end
    t:eq(grantLine(R.Resolve(snap(1500, 3), reversed, defs)), want, "the list reversed: the same")
    local differ = 0
    for shift = 1, #list - 1 do
        local turned = {}
        for i = 1, #list do turned[i] = list[(i + shift - 1) % #list + 1] end
        if grantLine(R.Resolve(snap(1500, 3), turned, defs)) ~= want then differ = differ + 1 end
    end
    t:eq(differ, 0, "every rotation of the list: the same")
    t:eq(grantLine(R.Resolve(snap(1500, 3), claims(), defs)), want, "and the same again on a second run")
end)

ns:Register("test", "reserve: equal claims keep the order they came in", function(t)
    local R = ns.reserve
    local a = { activity = "quest", step = "same", res = "money", n = 60, tag = "first" }
    local b = { activity = "quest", step = "same", res = "money", n = 60, tag = "second" }
    local c = { activity = "quest", step = "same", res = "money", n = 60, tag = "third" }
    local g = R.Resolve(snap(100), { a, b, c })
    t:eq(g[1].claim.tag .. "," .. g[2].claim.tag .. "," .. g[3].claim.tag, "first,second,third", "a tie keeps the list's order")
    t:eq(g[1].got, 60, "the first is paid")
    t:eq(g[2].got + g[3].got, 0, "the others are not: 60 is granted once")
    -- The same step key in two activities: the activity's name decides, not the list.
    local q = { activity = "quest", step = "k", res = "slots", n = 1 }
    local p = { activity = "professions", step = "k", res = "slots", n = 1 }
    t:eq(R.Resolve(snap(nil, 1), { q, p })[1].claim.activity, "professions", "same key, no priorities: by the activity's name")
    t:eq(R.Resolve(snap(nil, 1), { p, q })[1].claim.activity, "professions", "whichever came first")
end)

ns:Register("test", "reserve: an unknown price is neither granted nor refused", function(t)
    local R = ns.reserve
    local g = R.Resolve(snap(1000), {
        { activity = "professions", step = "train:Mining", res = "money", unknown = true, estimate = 400, milestone = true },
        { activity = "professions", step = "train:Cooking", res = "money", n = 900 },
        { activity = "professions", step = "train:Fishing", res = "money" },
        { activity = "professions", step = "train:Skinning", res = "money", unknown = true, n = 5000 },
    })
    local by = grantsByStep(g)
    local mining = by["train:Mining"]
    t:eq(mining.unknown, "price", "no price: the grant says the price is unknown")
    t:eq(mining.got, nil, "it is not granted")
    t:eq(mining.short, nil, "and not short either: Flow doesn't know")
    t:eq(mining.estimate, 400, "the estimate rides along for the text")
    t:eq(by["train:Cooking"].got, 900, "the estimate holds no money: a known price behind it is still paid in full")
    t:eq(g.committed.money, 900, "only the known price is committed")
    t:eq(g.left.money, 100, "what's left is counted without the estimate")
    t:eq(by["train:Fishing"].unknown, "price", "a claim with no amount at all: unknown too")
    t:eq(by["train:Skinning"].unknown, "price", "marked unknown: its number is not used")
    t:eq(by["train:Skinning"].got, nil, "so it is neither paid nor refused")
    t:eq(g.unknown, 3, "three unknown grants are counted")
    -- Money that couldn't be read: every money claim is unknown, none is refused.
    local blind = R.Resolve(snap(nil, 2), {
        { activity = "quest", step = "train:class", res = "money", n = 1 },
        { activity = "quest", step = "buy:1", res = "slots", n = 1 },
    })
    local bb = grantsByStep(blind)
    t:eq(bb["train:class"].unknown, "money", "money not read: unknown, not 'you can't pay'")
    t:eq(bb["train:class"].short, nil, "not short")
    t:eq(blind.left.money, nil, "and no number for what's free")
    t:eq(bb["buy:1"].got, 1, "the slots were read: that claim is answered")
    local noBags = R.Resolve(snap(50), { { activity = "quest", step = "buy:1", res = "slots", n = 1 } })
    t:eq(noBags[1].unknown, "slots", "bags not read: the slot claim is unknown")
    t:eq(noBags.left.slots, nil, "no number for free slots")
    t:eq(R.Resolve(nil, { { activity = "quest", step = "x", res = "money", n = 1 } })[1].unknown, "money", "no snapshot at all: unknown")
end)

ns:Register("test", "reserve: zero, negative and broken amounts hold nothing", function(t)
    local R = ns.reserve
    local g = R.Resolve(snap(100, 2), {
        { activity = "quest", step = "zero", res = "money", n = 0 },
        { activity = "quest", step = "neg", res = "money", n = -500 },
        { activity = "quest", step = "text", res = "money", n = "12" },
        { activity = "quest", step = "nan", res = "money", n = 0 / 0 },
        { activity = "quest", step = "inf", res = "money", n = math.huge },
        { activity = "quest", step = "real", res = "money", n = 100 },
        { activity = "quest", step = "negslot", res = "slots", n = -3 },
        { activity = "quest", step = "zeroslot", res = "slots", n = 0 },
        { activity = "quest", step = "slot", res = "slots", n = 2 },
    })
    local by = grantsByStep(g)
    t:ok(by.zero.got == 0 and by.zero.short == 0 and not by.zero.invalid, "nothing asked: nothing held, nothing short")
    for _, k in ipairs({ "neg", "text", "nan", "inf", "negslot" }) do
        t:ok(by[k].invalid == true and by[k].got == 0 and by[k].short == 0, k .. ": not a count, holds nothing")
    end
    t:eq(by.real.got, 100, "a negative claim adds no money: exactly 100 is there for the real one")
    t:eq(g.committed.money, 100, "100 committed")
    t:eq(g.left.money, 0, "nothing left, and not less than nothing")
    t:eq(by.slot.got, 2, "a negative slot claim adds no room")
    t:eq(g.left.slots, 0, "no slot left")
    -- Nothing to hand out.
    local empty = R.Resolve(snap(0, 0), {
        { activity = "quest", step = "m", res = "money", n = 1 },
        { activity = "quest", step = "s", res = "slots", n = 1 },
        { activity = "quest", step = "free", res = "money", n = 0 },
    })
    local eb = grantsByStep(empty)
    t:ok(eb.m.got == 0 and eb.m.short == 1, "no money: one copper is one short")
    t:ok(eb.s.got == 0 and eb.s.short == 1, "no room: one slot is one short")
    t:ok(eb.free.got == 0 and eb.free.short == 0, "a step that costs nothing fits with no money")
    -- A snapshot that isn't a count is unknown, never a debt.
    t:eq(R.Resolve({ money = -50 }, { { activity = "quest", step = "m", res = "money", n = 1 } })[1].unknown, "money", "negative money: unknown")
    t:eq(#R.Resolve(snap(10, 1), nil), 0, "no claims: no grants")
    t:eq(#R.Resolve(snap(10, 1), {}), 0, "an empty list: no grants")
end)

ns:Register("test", "reserve: free slots by kind of bag", function(t)
    local R = ns.reserve
    local s = R.FreeSlots({
        { bag = 0, free = 4, family = 0 },
        { bag = 1, free = 6, family = 0 },
        { bag = 2, free = 10, family = 32 },     -- a bag for one kind of thing
        { bag = 3, free = 0, family = 0 },
        { bag = 4, free = 3, family = 1 },       -- another
    })
    t:eq(s.all, 23, "all: every bag, whatever it holds")
    t:eq(s.general, 10, "general: only bags that take anything")
    t:eq(s.special, 13, "special: the rest")
    t:eq(s.familiesKnown, true, "every bag said what it holds")
    local unsure = R.FreeSlots({ { bag = 0, free = 4, family = 0 }, { bag = 1, free = 8 } })
    t:eq(unsure.general, 12, "a bag with no family given counts as general, as the merchant step counts it")
    t:eq(unsure.familiesKnown, false, "and the count says it couldn't tell")
    t:eq(R.FreeSlots(nil), nil, "no bag API: unknown, not 0 and not 99")
    local none = R.FreeSlots({})
    t:ok(none.all == 0 and none.general == 0, "no bag answered: nothing free")
    local odd = R.FreeSlots({ { bag = 0, free = -2, family = 0 }, { bag = 1, free = "3", family = 0 }, { bag = 2, free = 5, family = 0 } })
    t:eq(odd.all, 5, "a count that isn't one is left out")
    -- The snapshot carries both, and money as it was read.
    local shot = R.Snapshot({ money = 1234, bags = { { bag = 0, free = 2, family = 0 }, { bag = 1, free = 9, family = 8 } } })
    t:eq(shot.money, 1234, "money")
    t:ok(shot.slots.general == 2 and shot.slots.all == 11, "both slot counts")
    local blank = R.Snapshot({})
    t:ok(blank.money == nil and blank.slots == nil, "nothing read: both unknown")
    t:eq(R.Snapshot({ money = -1 }).money, nil, "money that isn't a count: unknown")
end)

ns:Register("test", "reserve: a slot claim counts general bags only", function(t)
    local R = ns.reserve
    -- 2 free in the backpack, 12 in a herb bag.
    local shot = R.Snapshot({ money = 0, bags = { { bag = 0, free = 2, family = 0 }, { bag = 1, free = 12, family = 32 } } })
    local g = R.Resolve(shot, {
        { activity = "quest", step = "buy:a", res = "slots", n = 2 },
        { activity = "quest", step = "buy:b", res = "slots", n = 3 },
    })
    local by = grantsByStep(g)
    t:eq(by["buy:a"].got, 2, "the first claim takes the two general slots")
    t:eq(by["buy:b"].got, 0, "the herb bag's room is not promised to the second")
    t:eq(by["buy:b"].short, 3, "it is three short")
    t:eq(g.left.slots, 0, "no general slot left")
    t:eq(shot.slots.all, 14, "though 14 are free in all")
    -- A claim bigger than what's there is granted as far as it goes.
    local part = R.Resolve(shot, { { activity = "quest", step = "buy:c", res = "slots", n = 5 } })
    t:ok(part[1].got == 2 and part[1].short == 3, "5 asked, 2 there: 2 held, 3 short")
end)

ns:Register("test", "reserve: the snapshot is taken once, at Begin", function(t)
    local R = ns.reserve
    local oldSnap, oldGrants = R.snapshot, R.grants
    local raw = { money = 500, bags = { { bag = 0, free = 3, family = 0 } } }
    local shot = R.Begin(raw)
    t:eq(R.Committed("money"), nil, "nothing committed before Finish")
    -- The player's money and bags change while the steps are gathered.
    raw.money, raw.bags[1].free = 9000, 0
    local steps = {
        { key = "train:Mining", cost = 400, activity = "professions" },
        { key = "buy:2320", activity = "professions", claims = { { res = "slots", n = 2 } } },
    }
    local g = R.Finish(steps)
    t:eq(shot.money, 500, "the snapshot keeps the money it read")
    t:eq(g.left.money, 100, "Finish counts against the snapshot, not the changed bags")
    t:eq(g.left.slots, 1, "the slots too")
    t:eq(R.Committed("money"), 400, "committed money")
    t:eq(R.Committed("slots"), 2, "committed slots")
    local again = R.Finish(steps)
    t:eq(grantLine(again), grantLine(g), "resolving again gives the same: nothing was spent")
    t:eq(R.snapshot, shot, "and the snapshot is the same one")
    R.Begin({ money = 9000 })
    t:eq(R.Finish(steps).left.money, 8600, "the next Begin reads again")
    -- Finish with no Begin knows nothing; it doesn't read the game by itself.
    R.snapshot, R.grants = nil, nil
    local blind = grantsByStep(R.Finish(steps))
    t:eq(blind["train:Mining"].unknown, "money", "no Begin: money unknown")
    t:eq(blind["buy:2320"].unknown, "slots", "no Begin: slots unknown")
    R.snapshot, R.grants = oldSnap, oldGrants
end)

ns:Register("test", "reserve: claims are read from a step's cost and its own claims", function(t)
    local R = ns.reserve
    local exact = { res = "money", n = 250, required = false }
    local claims = R.ClaimsOf({
        { key = "train:class", cost = 800, milestone = true, activity = "quest" },
        { key = "train:Mining", costUnknown = true, costEstimate = 4500, owner = "professions" },
        { key = "held", cost = 900, blockedBy = "needs Mining", activity = "quest" },
        { key = "free", cost = 0, activity = "quest" },
        { key = "walk", activity = "quest" },
        { key = "recipe:7", cost = 999, activity = "professions", claims = { exact, { res = "slots", n = 1 } } },
        { key = "craft:x", activity = "professions", claims = { { res = "item", id = 2318, n = 10 } } },
    })
    local by = {}
    for _, c in ipairs(claims) do by[c.res .. ":" .. tostring(c.step)] = c end
    t:eq(#claims, 5, "five claims: a held step, one with no cost and one that costs nothing ask for nothing")
    t:ok(by["money:train:class"].n == 800 and by["money:train:class"].milestone == true, "cost and milestone carried over")
    t:eq(by["money:train:class"].activity, "quest", "the step's lane is the claim's activity")
    local mining = by["money:train:Mining"]
    t:ok(mining.unknown == true and mining.n == nil, "price unknown: a claim with no amount")
    t:eq(mining.estimate, 4500, "the estimate is carried, not counted")
    t:eq(mining.activity, "professions", "no lane yet: the owner")
    t:eq(by["money:recipe:7"].n, 250, "a step's own money claim replaces the reading of its cost")
    t:eq(by["money:recipe:7"].required, false, "with what it says about itself")
    t:eq(by["money:recipe:7"].step, "recipe:7", "and gets the step's key")
    t:eq(exact.step, nil, "the step's own table is not written to")
    t:eq(by["slots:recipe:7"].n, 1, "its slot claim too")
    -- Item claims belong to a later part of the ledger: carried, then skipped.
    local g = R.Resolve(snap(5000, 4), claims)
    t:eq(g.skipped, 1, "the item claim is skipped, not granted")
    t:eq(#g, 4, "four grants")
    local gb = grantsByStep(g)
    t:eq(gb["train:Mining"].unknown, "price", "the unknown tier price stays unknown with 50s in the bags")
    t:eq(g.committed.money, 1050, "800 + 250: the 4500 estimate is not committed")
end)

ns:Register("test", "reserve: resolving changes neither the snapshot nor the claims", function(t)
    local R = ns.reserve
    local shot = snap(300, 2, 6)
    local claims = {
        { activity = "quest", step = "b", res = "money", n = 200 },
        { activity = "quest", step = "a", res = "money", n = 200 },
        { activity = "quest", step = "s", res = "slots", n = 5 },
    }
    local g = R.Resolve(shot, claims)
    t:ok(shot.money == 300 and shot.slots.general == 2 and shot.slots.all == 6, "the snapshot is as it was")
    t:ok(claims[1].step == "b" and claims[2].step == "a" and claims[3].step == "s", "the list keeps its order")
    t:ok(claims[1].n == 200 and claims[1].got == nil, "a claim is not written to")
    t:eq(g[1].claim, claims[2], "a grant points at its claim")
end)
