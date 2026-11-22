-- Self-tests for the activity contract (Modules/Nav/Activities.lua): whose
-- step a route step is, which lane it sits in, and that the route splits and
-- plans exactly as it did before the contract.
-- Same harness as Modules/Tests.lua (ns:Register("test", ...)); Flow's own
-- functions on made-up steps, no saved data touched, stand-ins put back.

local _, ns = ...

local function with(tbl, key, value, fn)
    local old = tbl[key]
    tbl[key] = value
    local ok, err = pcall(fn)
    tbl[key] = old
    if not ok then error(err, 0) end
end

local function goal(key, provider, x, y, extra)
    local g = { key = key, text = key, provider = provider, points = { { cont = 0, wx = x or 0, wy = y or 0 } } }
    for k, v in pairs(extra or {}) do g[k] = v end
    return g
end

-- One route, in the order its sources gave it: quest steps, class training
-- (a milestone: the quest lane's), a new quest, and four profession steps.
local function fixture()
    return {
        goal("101:1", "questie", 100, 0),
        goal("train:Mining", "errands", 55, 5),
        goal("102:1", "questie", 40, 30),
        goal("gather:Copper Vein", "skillplan", -80, 10),
        goal("102:done", "questie", 10, 0, { deps = { "102:1" } }),
        goal("train:class", "errands", 60, -20, { milestone = true }),
        goal("craft:Mining:Copper Bar", "skillplan", 20, 60, { deps = { "bank:Mining" } }),
        goal("103:1", "questie", -200, 0),
        goal("bank:Mining", "skillplan", 150, 0),
        goal("pickup:104", "pickups", -30, -40),
    }
end

local function keys(list)
    local out = {}
    for _, g in ipairs(list or {}) do out[#out + 1] = g.key end
    return table.concat(out, " | ")
end
local function planKeys(plan)
    local out = {}
    for _, s in ipairs(plan or {}) do out[#out + 1] = s.goal.key end
    return table.concat(out, " | ")
end

-- Made-up activities: { key, def } entries in the order A.Defs() would give.
local function defs(...)
    local out = {}
    for _, e in ipairs({ ... }) do out[#out + 1] = { key = e[1], def = e[2] } end
    return out
end
local function ownsProvider(name) return function(g) return g.provider == name end end
local function always() return true end

-- N.SplitProfessions as it was before it went through the activities
-- (Nav.lua at a529eea), word for word, for the "same as before" checks.
local function oldSplit(list, on)
    local N = ns.nav
    if not on then return list, {} end
    local quest, prof = {}, {}
    for _, g in ipairs(list) do
        if N.IsProfessionStop(g) then prof[#prof + 1] = g else quest[#quest + 1] = g end
    end
    if #quest == 0 then return list, {} end
    return quest, prof
end

ns:Register("test", "activity: a step goes to the first activity that owns it", function(t)
    local A = ns.activities
    local d = defs({ "craft", { order = 10, owns = ownsProvider("skillplan") } },
        { "errand", { order = 20, owns = function(g) return g.provider == "skillplan" or g.provider == "errands" end } },
        { "quest", { order = 100, owns = always } })
    t:eq(A.Of(goal("a", "skillplan"), d, {}), "craft", "two activities own it: the one asked first has it")
    t:eq(A.Of(goal("b", "errands"), d, {}), "errand", "the next one that owns it")
    t:eq(A.Of(goal("c", "questie"), d, {}), "quest", "no one else: the catch-all")
    local seen
    local d2 = defs({ "x", { order = 1, owns = function(g, ctx) seen = ctx return false end } }, { "quest", { order = 2, owns = always } })
    local ctx = { level = 12 }
    A.Of(goal("d", "questie"), d2, ctx)
    t:ok(seen == ctx, "owns is handed the collect's ctx")
    -- The two that ship, in the order they are asked.
    local real = A.Defs()
    local order = {}
    for _, e in ipairs(real) do order[#order + 1] = e.key end
    t:eq(table.concat(order, " "), "professions quest", "professions is asked before quest, the catch-all")
    t:eq(A.CatchAll(real), "quest", "quest is asked last")
    local on = { exists = { professions = true } }
    t:eq(A.Of(goal("train:Mining", "errands"), real, on), "professions", "profession training")
    t:eq(A.Of(goal("craft:x", "skillplan"), real, on), "professions", "a skill-up step")
    t:eq(A.Of(goal("train:class", "errands", 0, 0, { milestone = true }), real, on), "quest", "class training stays with the quests")
    t:eq(A.Of(goal("1:1", "questie"), real, on), "quest", "a quest objective")
    local lanes = A.Split(fixture(), real, on)
    t:eq(keys(lanes.professions), "train:Mining | gather:Copper Vein | craft:Mining:Copper Bar | bank:Mining", "one pass, the list's order kept (professions)")
    t:eq(keys(lanes.quest), "101:1 | 102:1 | 102:done | train:class | 103:1 | pickup:104", "and for the quest lane")
end)

ns:Register("test", "activity: a step falls through when the lane does not exist", function(t)
    local A = ns.activities
    local asked = 0
    local d = defs({ "craft", { order = 10, owns = ownsProvider("skillplan"), exists = function() asked = asked + 1 return false end } },
        { "quest", { order = 100, owns = always } })
    local g = goal("a", "skillplan")
    t:eq(A.Of(g, d, {}), "quest", "no lane of its own: the next owner has it")
    t:eq(A.Owner(g, d, {}), "craft", "it is still that activity's step by definition")
    t:ok(not A.Exists("craft", d, {}), "Exists says so")
    t:ok(A.Exists("quest", d, {}), "an activity without `exists` always has a lane")
    t:ok(not A.Exists("nothing", d, {}), "an activity that isn't registered has none")
    asked = 0
    local lanes = A.Split({ g, goal("b", "skillplan"), goal("c", "questie") }, d, {})
    t:eq(lanes.craft, nil, "no lane in the split")
    t:eq(keys(lanes.quest), "a | b | c", "its steps are in the next owner's lane, in order")
    t:eq(asked, 1, "whether a lane exists is asked once a split, not once a step")
    -- What the caller already decided wins over the definition's own answer.
    t:eq(A.Of(g, d, { exists = { craft = true } }), "craft", "ctx.exists: on")
    local d3 = defs({ "craft", { order = 10, owns = ownsProvider("skillplan"), exists = always } }, { "quest", { order = 100, owns = always } })
    t:eq(A.Of(g, d3, { exists = { craft = false } }), "quest", "ctx.exists: off")
    t:eq(A.Of(g, d3, {}), "craft", "nothing decided: the definition's own exists")
    -- nil from `exists` is not false: the lane is there.
    local d4 = defs({ "craft", { order = 10, owns = ownsProvider("skillplan"), exists = function() return nil end } }, { "quest", { order = 100, owns = always } })
    t:eq(A.Of(g, d4, {}), "craft", "only false takes the lane away")
    -- The shipped pair with the profession lane off: everything is the quest lane's.
    local off = A.Split(fixture(), A.Defs(), { exists = { professions = false } })
    t:eq(off.professions, nil, "the faint arrow off: no profession lane")
    t:eq(keys(off.quest), keys(fixture()), "every step on the quest lane, in order")
end)

ns:Register("test", "activity: the catch-all keeps every step no one claims", function(t)
    local A = ns.activities
    local real = A.Defs()
    local on = { exists = { professions = true } }
    local odd = {
        { key = "no provider" },
        goal("crossing:1", "crossing"), goal("hearth", "hearth"), goal("dungeon:1", "dungeon"),
        goal("party:1", "party"), goal("repair", "repair"), goal("mount", "mount", 0, 0, { milestone = true }),
        goal("train:class", "errands"), goal("skill milestone", "skillplan", 0, 0, { milestone = true }),
    }
    for _, g in ipairs(odd) do
        t:eq(A.Of(g, real, on), "quest", g.key .. ": the quest lane's")
        t:eq(A.Owner(g, real, on), "quest", g.key .. ": and its owner")
    end
    local lanes = A.Split(odd, real, on)
    t:eq(#(lanes.quest or {}), #odd, "none is lost in the split")
    t:eq(lanes.professions, nil, "and none went to the profession lane")
    -- Without a catch-all a step can be no one's; it is then in no lane.
    local d = defs({ "craft", { order = 10, owns = ownsProvider("skillplan") } })
    t:eq(A.Of(goal("q", "questie"), d, {}), nil, "no catch-all registered: no lane")
    t:eq(A.Owner(goal("q", "questie"), d, {}), nil, "and no owner")
    t:eq(A.CatchAll({}), nil, "nothing registered: no catch-all")
end)

ns:Register("test", "activity: nothing is split off when no quest step would be left", function(t)
    local N, A = ns.nav, ns.activities
    local list = { goal("train:Mining", "errands"), goal("craft:x", "skillplan"), goal("bank:Mining", "skillplan") }
    local quest, prof = N.SplitProfessions(list, true)
    t:ok(quest == list, "the whole list stays on the main arrow, the same table")
    t:eq(#prof, 0, "nothing on the faint one")
    -- One quest step is enough to split again.
    list[#list + 1] = goal("1:1", "questie")
    quest, prof = N.SplitProfessions(list, true)
    t:eq(keys(quest), "1:1", "a quest step left: it has the main arrow")
    t:eq(keys(prof), "train:Mining | craft:x | bank:Mining", "and the profession steps their own")
    -- Class training counts as a quest-lane step for this.
    quest, prof = N.SplitProfessions({ goal("train:Mining", "errands"), goal("train:class", "errands", 0, 0, { milestone = true }) }, true)
    t:ok(#quest == 1 and #prof == 1, "class training alone keeps the lanes apart")
    quest, prof = N.SplitProfessions({}, true)
    t:ok(#quest == 0 and #prof == 0, "an empty route: two empty lanes")
    -- A.Split itself has no such rule: it is the route's (N.SplitProfessions).
    local lanes = A.Split({ goal("train:Mining", "errands") }, A.Defs(), { exists = { professions = true } })
    t:eq(keys(lanes.professions), "train:Mining", "A.Split alone would split it off")
end)

ns:Register("test", "activity: blocked, hidden and along steps carry their lane", function(t)
    local N, A = ns.nav, ns.activities
    local real = A.Defs()
    local list = fixture()
    local blocked = { goal("train:Herbalism", "errands", 0, 0, { blockedBy = "needs 10 silver" }), goal("105:1", "questie", 0, 0, { blockedBy = "needs Bear Form" }) }
    local hidden = { goal("craft:Mining:Hidden", "skillplan"), goal("106:1", "questie") }
    local along = { goal("farm:2672", "skillplan", 0, 0, { along = true }), goal("107:1", "questie", 0, 0, { along = true }) }
    for _, l in ipairs({ list, blocked, hidden, along }) do A.StampOwners(l, real, {}) end
    t:eq(blocked[1].owner, "professions", "owner is set before a step is set apart")
    local quest, prof = N.SplitProfessions(list, true)
    A.StampLanes({ quest = quest, professions = prof }, { blocked, hidden, along }, real, {})
    for _, g in ipairs(quest) do t:eq(g.activity, "quest", g.key .. ": on the quest lane") end
    for _, g in ipairs(prof) do t:eq(g.activity, "professions", g.key .. ": on the profession lane") end
    t:eq(blocked[1].activity, "professions", "a blocked profession step: the profession lane")
    t:eq(blocked[2].activity, "quest", "a blocked quest step: the quest lane")
    t:eq(hidden[1].activity, "professions", "a hidden profession step")
    t:eq(hidden[2].activity, "quest", "a hidden quest step")
    t:eq(along[1].activity, "professions", "an along-the-way profession step")
    t:eq(along[2].activity, "quest", "an along-the-way quest step")
    for _, l in ipairs({ quest, prof, blocked, hidden, along }) do
        for _, g in ipairs(l) do t:ok(g.owner ~= nil and g.activity ~= nil, g.key .. ": both fields set") end
    end
    -- The faint arrow off: one lane, and the steps set apart name it.
    local b2 = { goal("train:Herbalism", "errands") }
    A.StampOwners(b2, real, {})
    local q2, p2 = N.SplitProfessions(fixture(), false)
    A.StampLanes({ quest = q2, professions = p2 }, { b2 }, real, {})
    t:eq(b2[1].activity, "quest", "no profession lane: a blocked profession step is listed with the quest lane")
    t:eq(b2[1].owner, "professions", "still a profession step by definition")
    -- The lane is on but every profession step is off the route: no lane to name.
    local b3 = { goal("train:Herbalism", "errands") }
    local q3, p3 = N.SplitProfessions({ goal("1:1", "questie") }, true)
    A.StampLanes({ quest = q3, professions = p3 }, { b3 }, real, {})
    t:eq(b3[1].owner, "professions", "a step that reached the split without an owner gets one")
    t:eq(b3[1].activity, "quest", "its lane has no step on the route: it never names an empty lane")
    A.StampLanes({ quest = {}, professions = {} }, nil, real, {})
    t:ok(true, "no lists of steps set apart: nothing to do")
end)

ns:Register("test", "activity: owner and lane differ after the fallback", function(t)
    local N, A = ns.nav, ns.activities
    local real = A.Defs()
    local list = { goal("train:Mining", "errands"), goal("craft:x", "skillplan") }
    local blocked = { goal("train:Herbalism", "errands", 0, 0, { blockedBy = "needs 10 silver" }) }
    local hidden = { goal("craft:y", "skillplan") }
    A.StampOwners(list, real, {})
    A.StampOwners(blocked, real, {})
    A.StampOwners(hidden, real, {})
    -- No quest step left: the profession steps go back to the main arrow.
    local quest, prof = N.SplitProfessions(list, true)
    A.StampLanes({ quest = quest, professions = prof }, { blocked, hidden }, real, {})
    for _, g in ipairs(list) do
        t:eq(g.owner, "professions", g.key .. ": a profession step by definition")
        t:eq(g.activity, "quest", g.key .. ": on the quest lane")
    end
    t:eq(blocked[1].owner, "professions", "the blocked one: owner")
    t:eq(blocked[1].activity, "quest", "the blocked one: lane")
    t:eq(hidden[1].owner, "professions", "the hidden one: owner")
    t:eq(hidden[1].activity, "quest", "the hidden one: lane")
    -- The owner doesn't depend on whether the lane exists.
    local g = goal("train:Mining", "errands")
    t:eq(A.Owner(g, real, { exists = { professions = false } }), "professions", "owner with the lane off")
    t:eq(A.Of(g, real, { exists = { professions = false } }), "quest", "lane with the lane off")
    -- StampOwners never changes an owner afterwards; StampLanes keeps it.
    list[1].owner = "kept"
    A.StampLanes({ quest = list }, nil, real, {})
    t:eq(list[1].owner, "kept", "an owner already set is left alone at the split")
end)

ns:Register("test", "activity: the PR 1 form splits exactly as N.SplitProfessions did", function(t)
    local N, A = ns.nav, ns.activities
    local function same(name, list)
        for _, on in ipairs({ true, false }) do
            local q1, p1 = oldSplit(list, on)
            local q2, p2 = N.SplitProfessions(list, on)
            local label = name .. (on and ", on" or ", off")
            t:eq(keys(q2), keys(q1), label .. ": the main arrow's steps")
            t:eq(keys(p2), keys(p1), label .. ": the faint arrow's steps")
            t:eq(q2 == list, q1 == list, label .. ": the list itself is handed back in the same cases")
            for i, g in ipairs(q1) do t:ok(q2[i] == g, label .. ": the same step tables (main " .. i .. ")") end
            for i, g in ipairs(p1) do t:ok(p2[i] == g, label .. ": the same step tables (faint " .. i .. ")") end
        end
    end
    same("the fixed route", fixture())
    same("only quest steps", { goal("1:1", "questie"), goal("2:1", "questie"), goal("train:class", "errands", 0, 0, { milestone = true }) })
    same("only profession steps", { goal("train:Mining", "errands"), goal("craft:x", "skillplan") })
    same("one of each", { goal("craft:x", "skillplan"), goal("1:1", "questie") })
    same("an empty route", {})
    same("a skill milestone and class training", { goal("m", "skillplan", 0, 0, { milestone = true }), goal("train:class", "errands"), goal("train:Mining", "errands") })
    same("truthy, not true", { goal("craft:x", "skillplan"), goal("1:1", "questie") })
    local q, p = N.SplitProfessions({ goal("craft:x", "skillplan"), goal("1:1", "questie") }, 1)
    t:ok(#q == 1 and #p == 1, "any truthy `on` splits, as before")
    q, p = N.SplitProfessions({ goal("craft:x", "skillplan"), goal("1:1", "questie") }, nil)
    t:ok(#q == 2 and #p == 0, "nil is off, as before")

    -- When the lane exists: the "professions" activity's `exists` against the
    -- test N:Collect made before (arrow on, and not on a custom route that is
    -- in force), for every combination.
    local def = ns:Get("activity", "professions")
    local F = ns.focus
    t:ok(def and def.exists and F ~= nil, "the professions activity has an `exists`")
    if not (def and def.exists and F) then return end
    local idleWas = F.idle
    for _, arrow in ipairs({ true, false }) do
        for _, active in ipairs({ true, false }) do
            for _, idle in ipairs({ true, false, "unset" }) do
                with(N, "ProfPointerOn", function() return arrow end, function()
                with(F, "Active", function() return active end, function()
                    if idle == "unset" then F.idle = nil else F.idle = idle end
                    local old = N:ProfPointerOn() and not (ns.focus and ns.focus.Active() and not ns.focus.idle)
                    local label = string.format("arrow %s, custom route %s, waiting %s", tostring(arrow), tostring(active), tostring(idle))
                    t:eq(def.exists({}), old and true or false, label)
                    t:eq(A.Exists("professions", A.Defs(), {}), old and true or false, label .. " (A.Exists)")
                end) end)
            end
        end
    end
    F.idle = idleWas
    -- ProfPointerOn answering nil (Professions unticked) is off, not an error.
    with(N, "ProfPointerOn", function() return nil end, function()
        t:eq(def.exists({}), false, "the arrow's own test answering nil: no lane")
    end)
    -- Without the custom-route module the lane goes by the arrow alone.
    with(ns, "focus", nil, function()
        with(N, "ProfPointerOn", function() return true end, function()
            t:eq(def.exists({}), true, "no custom-route module: the arrow decides")
        end)
    end)
end)

ns:Register("test", "activity: a crossing step is owned by the quest lane", function(t)
    local A = ns.activities
    local real = A.Defs()
    local on = { exists = { professions = true } }
    local crossing = goal("crossing:1", "crossing")
    t:eq(A.Owner(crossing, real, on), "quest", "no profession rule claims a crossing step")
    t:eq(A.Of(crossing, real, on), "quest", "so it is on the quest lane with the profession lane on")
    local lanes = A.Split({ goal("craft:x", "skillplan"), crossing, goal("1:1", "questie") }, real, on)
    t:eq(keys(lanes.quest), "crossing:1 | 1:1", "in the split too")
    t:eq(keys(lanes.professions), "craft:x", "the profession step that may wait on it keeps its own lane")
end)

-- Golden: the split and the planner's order for the fixed route above, as
-- they came out at a529eea, before the split went through the activities.
-- (Planner options {}: travel options need the client.)
ns:Register("test", "route: golden plan order", function(t)
    local N = ns.nav
    local p = { cont = 0, wx = 0, wy = 0 }
    local quest, prof = N.SplitProfessions(fixture(), true)
    t:eq(keys(quest), "101:1 | 102:1 | 102:done | train:class | 103:1 | pickup:104", "split: the quest lane")
    t:eq(keys(prof), "train:Mining | gather:Copper Vein | craft:Mining:Copper Bar | bank:Mining", "split: the profession lane")
    t:eq(planKeys(ns.planner:Plan(p, quest, {})), "102:1 | 101:1 | train:class | 102:done | pickup:104 | 103:1", "plan: the quest lane")
    t:eq(planKeys(ns.planner:Plan(p, prof, {})), "train:Mining | bank:Mining | craft:Mining:Copper Bar | gather:Copper Vein", "plan: the profession lane")
    local all, none = N.SplitProfessions(fixture(), false)
    t:eq(keys(all), keys(fixture()), "split off: one lane, the route's own order")
    t:eq(#none, 0, "split off: no profession lane")
    t:eq(planKeys(ns.planner:Plan(p, all, {})),
        "train:class | bank:Mining | 101:1 | train:Mining | 102:1 | craft:Mining:Copper Bar | 102:done | pickup:104 | gather:Copper Vein | 103:1",
        "plan: everything on the main arrow")
    -- The step fields the activities add don't move the planner.
    local A = ns.activities
    local stamped = fixture()
    A.StampOwners(stamped, A.Defs(), {})
    local q2, p2 = N.SplitProfessions(stamped, true)
    A.StampLanes({ quest = q2, professions = p2 }, nil, A.Defs(), {})
    t:eq(planKeys(ns.planner:Plan(p, q2, {})), "102:1 | 101:1 | train:class | 102:done | pickup:104 | 103:1", "plan: the quest lane, steps stamped")
    t:eq(planKeys(ns.planner:Plan(p, p2, {})), "train:Mining | bank:Mining | craft:Mining:Copper Bar | gather:Copper Vein", "plan: the profession lane, steps stamped")
end)
