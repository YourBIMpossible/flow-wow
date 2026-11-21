-- Lane W2 self-tests: quests, routes, dungeons, party, navigation state.
-- Same harness as Modules/Tests.lua (ns:Register("test", ...), t:ok / t:eq /
-- t:near); Flow's own logic on made-up inputs, saved data put back.

local _, ns = ...

-- A need kind only these tests use (never on a step): answers by its argument.
local function testNeedKind()
    if not ns:Get("need", "w2test") then
        ns:Register("need", "w2test", {
            met = function(arg)
                if arg == "err" then error("check broke") end
                if arg == "nil" then return nil end
                return arg == "yes"
            end,
        })
    end
end

-------------------------------------------------------------------------------
-- F-025: a need Flow can't check is never met.
-------------------------------------------------------------------------------

ns:Register("test", "needs: an unknown need or a failing check is not met, and the step says why", function(t)
    local N = ns.nav
    testNeedKind()
    local s, why = N.NeedState("nosuchkind:Teleport")
    t:eq(s, "unknown", "a kind nobody registered: unknown")
    t:ok(why ~= nil, "with a reason")
    t:eq(N.NeedMet("nosuchkind:Teleport"), false, "and not met")
    t:eq((N.NeedState("w2test:err")), "unknown", "a check that errors: unknown")
    t:eq(N.NeedMet("w2test:err"), false, "and not met")
    t:eq((N.NeedState("w2test:nil")), "unknown", "a check that can't tell (nil): unknown")
    t:eq((N.NeedState("w2test:yes")), "yes", "a check that says yes: met")
    t:eq((N.NeedState("w2test:no")), "no", "a check that says no: not met")
    t:eq(N.NeedMet("not a token"), false, "not even a token: not met")
    -- Through ResolveNeeds, with Flow's own NeedState: held, with the reason.
    local g = { key = "w2:port", needs = { "w2test:err" } }
    N.ResolveNeeds({ g }, nil, function(tok) return (tok:gsub("^%w+:", "")) end)
    t:ok(g.blockedBy ~= nil, "a hard need Flow can't check holds the step")
    t:ok(g.blockedBy and g.blockedBy:find("couldn't check", 1, true) ~= nil, "and the reason says Flow couldn't check it")
    t:eq(g.blockedShort, "can't check err", "short reason for the lock")
    local soft = { key = "w2:soft", needs = { { "w2test:nil", soft = true } } }
    N.ResolveNeeds({ soft }, nil, nil)
    t:eq(soft.blockedBy, nil, "a soft need still only orders, unknown or not")
    -- A provider on the route still orders an unknown need, never blocks it.
    local p = { key = "w2:prov", provides = { "w2test:nil" } }
    local h = { key = "w2:hard", needs = { "w2test:nil" } }
    N.ResolveNeeds({ p, h }, nil, nil)
    t:eq(h.deps and h.deps[1], "w2:prov", "unknown with a provider on the route: after it")
    t:eq(h.blockedBy, nil, "not blocked while the provider is on the route")
end)

ns:Register("test", "needs: a spell need wants the spell known, not just its name resolving", function(t)
    local N = ns.nav
    t:eq(N.SpellNeedMet("Teleport: Moonglade", { Wrath = true }, nil), false, "spellbook read, spell not in it: not met")
    t:eq(N.SpellNeedMet("Wrath", { Wrath = true }, nil), true, "in the spellbook: met")
    t:eq(N.SpellNeedMet("Teleport: Moonglade", { Wrath = true }, false), false, "the game says not known: not met")
    t:eq(N.SpellNeedMet("Aquatic Form", { Wrath = true }, true), true, "the game says known (a passive the spellbook list skips): met")
    t:eq(N.SpellNeedMet("Teleport: Moonglade", {}, nil), nil, "spellbook not read and the game can't be asked: unknown")
    t:eq(N.SpellNeedMet("Teleport: Moonglade", nil, nil), nil, "no spellbook at all: unknown")
end)

ns:Register("test", "route: a soft need's step hidden or across the sea holds nothing", function(t)
    local N = ns.nav
    local quest = { key = "9201:done", text = "Turn in: Teacher" }
    local train = { key = "train:class", text = "Class training", deps = { "9201:done" }, softDeps = { ["9201:done"] = true } }
    local hard = { key = "x:hard", text = "Hard", deps = { "9201:done" } }
    local kept, held = N.HoldForHidden({ train, hard }, { quest })
    local keptKeys, heldKeys = {}, {}
    for _, g in ipairs(kept) do keptKeys[g.key] = true end
    for _, g in ipairs(held) do heldKeys[g.key] = true end
    t:ok(keptKeys["train:class"], "hidden: a soft dep doesn't hold training")
    t:ok(heldKeys["x:hard"], "hidden: a hard dep holds")
    local function away(g) return g.key == "9201:done" and 2 or nil end
    local function words() return "across the sea", "away" end
    local k2, h2 = N.HoldForAway({ quest, train, hard }, away, words)
    local k2Keys, h2Keys = {}, {}
    for _, g in ipairs(k2) do k2Keys[g.key] = true end
    for _, g in ipairs(h2) do h2Keys[g.key] = true end
    t:ok(k2Keys["train:class"], "away: a soft dep doesn't hold training")
    t:ok(h2Keys["x:hard"], "away: a hard dep holds")
end)

-------------------------------------------------------------------------------
-- F-030: a loop in the steps' deps is found, broken the same way each time,
-- and any dep the order breaks is flagged.
-------------------------------------------------------------------------------

local function planGoal(key, x, extra)
    local g = { key = key, text = key, points = { { cont = 0, wx = x, wy = 0 } } }
    for k, v in pairs(extra or {}) do g[k] = v end
    return g
end

ns:Register("test", "planner: a dependency loop is found, broken the same way each time, and flagged", function(t)
    local P = ns.planner
    local function stop(key, deps) return { key = key, goal = { key = key, deps = deps } } end
    local broken, loops = P.FindCycles({ stop("b", { "a" }), stop("a", { "b" }), stop("c", { "a" }) })
    t:eq(#loops, 1, "one loop")
    t:ok(broken and broken.b and broken.b.a, "broken at the dep that closes it (a > b > a: b's dep on a)")
    local broken2 = P.FindCycles({ stop("a", { "b" }), stop("c", { "a" }), stop("b", { "a" }) })
    t:ok(broken2 and broken2.b and broken2.b.a, "the same break whatever order the steps come in")
    local none, l0 = P.FindCycles({ stop("1:done", { "1:1" }), stop("1:1") })
    t:eq(none, nil, "a plain chain: no loop")
    t:eq(#l0, 0, "and none listed")
    local selfB = P.FindCycles({ stop("x", { "x" }) })
    t:ok(selfB and selfB.x and selfB.x.x, "a step that waits for itself: broken too")
    -- Through the planner: it finishes, keeps every step, and says what it broke.
    local p = { cont = 0, wx = 0, wy = 0 }
    local plan = P:Plan(p, { planGoal("a", 100, { deps = { "b" } }), planGoal("b", 20, { deps = { "a" } }), planGoal("c", 200, { deps = { "a" } }) }, { areaFirst = false })
    t:eq(plan and #plan, 3, "all three steps planned")
    t:ok(plan and plan.loops and #plan.loops == 1, "the loop is on the plan")
    local pos = {}
    for i, e in ipairs(plan or {}) do pos[e.goal.key] = i end
    t:ok(pos.a and pos.c and pos.a < pos.c, "the dep that isn't in the loop is still kept (a before c)")
    local flagged = plan and plan.outOfOrder or {}
    t:eq(#flagged, 1, "exactly one dep broken, and it's flagged")
    t:eq(flagged[1] and flagged[1].why, "loop", "as a loop")
    t:ok(flagged[1] and flagged[1].text:find("waits for", 1, true) ~= nil, "with words for the step list")
    local plan2 = P:Plan(p, { planGoal("c", 200, { deps = { "a" } }), planGoal("b", 20, { deps = { "a" } }), planGoal("a", 100, { deps = { "b" } }) }, { areaFirst = false })
    local o1, o2 = {}, {}
    for _, e in ipairs(plan or {}) do o1[#o1 + 1] = e.goal.key end
    for _, e in ipairs(plan2 or {}) do o2[#o2 + 1] = e.goal.key end
    t:eq(table.concat(o2, ","), table.concat(o1, ","), "the same order whatever order the goals come in")
end)

ns:Register("test", "planner: your chosen step first, though it waits for another: planned and flagged", function(t)
    local P = ns.planner
    local p = { cont = 0, wx = 0, wy = 0 }
    local plan = P:Plan(p, { planGoal("1:done", 50, { deps = { "1:1" } }), planGoal("1:1", 300) }, { first = "1:done", areaFirst = false })
    t:eq(plan and plan[1] and plan[1].goal.key, "1:done", "your pick goes first")
    local o = plan and plan.outOfOrder and plan.outOfOrder[1]
    t:eq(o and o.why, "forced", "and the dep it breaks is flagged, as your pick")
    t:ok(plan and plan[1].outOfOrder and plan[1].outOfOrder[1] == "1:1", "on its entry too")
    local ok = P:Plan(p, { planGoal("1:done", 50, { deps = { "1:1" } }), planGoal("1:1", 300) }, { areaFirst = false })
    t:eq(ok and ok.outOfOrder, nil, "a legal order: nothing flagged")
end)

-------------------------------------------------------------------------------
-- F-026: a quest Flow can't tell is offered to you is "unknown", never a
-- confident pickup: kept, ranked after the sure ones, with its reason.
-------------------------------------------------------------------------------

ns:Register("test", "dungeons: a quest Flow can't check is unknown, kept, and ranked after the sure ones", function(t)
    local D = ns.dungeons
    local q = { Id = 9001, name = "Maybe", level = 20 }
    t:eq((D.Check(q, function() return true end)), "yes", "a check that says yes: yes")
    local s, why = D.Check(q, function() return false, "for another class" end)
    t:eq(s, "no", "a check that says no: no")
    t:eq(why, "for another class", "with its reason")
    s, why = D.Check(q, function() return nil, "Flow can't check your reputation" end)
    t:eq(s, "unknown", "a check that can't tell: unknown, not yes")
    t:eq(why, "Flow can't check your reputation", "with its reason")
    s, why = D.Check(q, function() error("module broke") end)
    t:eq(s, "unknown", "a check that errors: unknown, not yes")
    t:ok(why ~= nil, "with a reason")
    -- On the route: weighted after the sure pickups, and it says why.
    local g = D.Unsure({ key = "pickup:9001", weight = 0.9, text = "Accept: Maybe", details = { "Level 20 quest." } }, why)
    t:ok(g.weight > 0.9, "ranked after a sure pickup of the same kind")
    t:ok(g.text:find("may not be offered", 1, true) ~= nil, "the step says it may not be offered")
    t:eq(g.details[#g.details], "May not be offered to you: " .. why .. ".", "and why, in its details")
    -- Through the planner: two givers the same way off, the sure one first.
    local p = { cont = 0, wx = 0, wy = 0 }
    local sure = { key = "pickup:1", text = "Accept: Sure", weight = 0.9, points = { { cont = 0, wx = 100, wy = 0 } } }
    local maybe = D.Unsure({ key = "pickup:2", text = "Accept: Maybe", weight = 0.9, points = { { cont = 0, wx = 90, wy = 0 } } }, why)
    local plan = ns.planner:Plan(p, { maybe, sure }, { areaFirst = false })
    t:eq(plan and plan[1] and plan[1].goal.key, "pickup:1", "the sure giver comes first, though the other is on the way")
    -- A dungeon quest's state: only a definite no rules it out.
    local ctx
    ctx = {
        get = function() return nil end, done = {}, log = {}, level = 20,
        eligible = function() return nil, "Flow can't check your professions" end,
    }
    t:ok(D.State({ Id = 9002, name = "Skill quest", level = 18 }, ctx) ~= "notforyou", "can't tell: not ruled out as not for you")
    ctx.eligible = function() return false, "needs Mining" end
    t:eq(D.State({ Id = 9003, name = "Mining quest", level = 18 }, ctx), "notforyou", "a definite no: not for you")
end)

-------------------------------------------------------------------------------
-- F-046: a member ready to hand in is told to, though you have the quest too.
-------------------------------------------------------------------------------

ns:Register("test", "party quests: a member ready to hand in keeps their turn-in, though you're not ready", function(t)
    local H = ns.partyHelp
    local mineNotReady = { [86] = { complete = false, objectives = { { finished = false } } } }
    local mineReady = { [86] = { complete = true, objectives = { { finished = true } } } }
    local theirsReady = { complete = true, objectives = { { finished = true } } }
    local theirsNot = { complete = false, objectives = { { finished = false } } }
    t:ok(not H.Skip("help:86:done", mineNotReady, theirsReady), "they're ready, you aren't: their turn-in stays")
    t:ok(H.Skip("help:86:done", mineReady, theirsReady), "both ready: your own turn-in covers the trip")
    t:ok(H.Skip("help:86:done", mineNotReady, theirsNot), "neither ready: your own turn-in covers it")
    t:ok(not H.Skip("help:90:done", mineNotReady, theirsReady), "a quest only they have: theirs stays")
end)

-------------------------------------------------------------------------------
-- F-056: costs are paid for together, not each against all your money.
-------------------------------------------------------------------------------

ns:Register("test", "route: steps that cost money are paid for together, not each on its own", function(t)
    local N = ns.nav
    local train = { key = "train:class", cost = 800, milestone = true }
    local riding = { key = "mount:riding", cost = 600 }
    local cheap = { key = "train:Cooking", cost = 100 }
    local over, total = N.CommitCosts({ riding, cheap, train }, 1000)
    t:eq(over["train:class"], nil, "class training first: it fits")
    t:eq(over["train:Cooking"], nil, "then the cheaper one: still fits")
    t:eq(over["mount:riding"], 900, "riding doesn't fit after them (900 set aside)")
    t:eq(total, 900, "900 committed")
    local o2 = N.CommitCosts({ riding, cheap, train }, 5000)
    t:eq(next(o2), nil, "enough for all: nothing over")
    local held = { key = "x", cost = 900, blockedBy = "needs Mining" }
    local o3, t3 = N.CommitCosts({ held, cheap }, 200)
    t:eq(o3.x, nil, "a step already held doesn't take money")
    t:eq(t3, 100, "only the step you can do counts")
    local o4 = N.CommitCosts({ { key = "a", cost = 700 }, { key = "b", cost = 700 } }, 1000)
    t:ok(o4.a == nil and o4.b == 700, "two the same price: the same one wins every time (by key)")
end)

-------------------------------------------------------------------------------
-- F-055: a trip learned riding doesn't time it for a character who can't
-- ride, and a best that's old gives way.
-------------------------------------------------------------------------------

ns:Register("test", "legs: a character without a mount isn't timed by a trip made riding, and old bests age out", function(t)
    local L = ns.legs
    local store = {}
    local leg = { cont = 1, ax = 10, ay = 10, bx = 610, by = 10, sec = 200, d = 600, mode = "foot" }
    L.Keep(store, leg, 1000)
    leg.sec, leg.mode = 80, "mount"
    local e, best = L.Keep(store, leg, 2000)
    t:ok(best and e.s == 80 and e.m == "mount", "riding was quicker: the best")
    t:eq(e.f, 200, "the quickest on foot is kept beside it")
    local a, b = { wx = 20, wy = 20 }, { wx = 600, wy = 20 }
    local rider = L.Lookup(store, {}, a, b, 580, { ride = true })
    local walker = L.Lookup(store, {}, a, b, 580, { ride = false })
    t:near(rider, L.YardsOf({ s = 80, d = 600 }, 580), 0.01, "a character who rides: the riding time")
    t:near(walker, L.YardsOf({ s = 200, d = 600 }, 580), 0.01, "one who can't: the time on foot")
    t:ok(walker > rider, "and it's the longer")
    -- Only ever ridden: nothing exact for a character who can't ride.
    local only = {}
    L.Keep(only, { cont = 1, ax = 10, ay = 10, bx = 610, by = 10, sec = 80, d = 600, mode = "mount" }, 1000)
    t:eq(L.Lookup(only, {}, a, b, 580, { ride = false }), nil, "a trip only made riding: not used for a walker")
    t:ok(L.Lookup(only, {}, a, b, 580) ~= nil, "can't tell whether you ride: as before")
    -- Age: an old best isn't planned by, and the next trip replaces it.
    t:eq(L.Lookup(only, {}, a, b, 580, { now = 1000 + L.AGE + 1 }), nil, "a best older than L.AGE: not planned by")
    local e2, best2 = L.Keep(only, { cont = 1, ax = 10, ay = 10, bx = 610, by = 10, sec = 150, d = 600, mode = "foot" }, 1000 + L.AGE + 1)
    t:ok(best2 and e2.s == 150, "and a slower trip after it replaces it")
    t:ok(L.Lookup(only, {}, a, b, 580, { now = 1000 + L.AGE + 2 }) ~= nil, "planned by again")
end)

-------------------------------------------------------------------------------
-- F-029: a hand-in the route holds isn't handed in for you at the NPC.
-------------------------------------------------------------------------------

ns:Register("test", "quests: a hand-in your route holds isn't turned in for you, the next finished one is", function(t)
    local AT = ns.autoTurnIn
    local blocked = {
        { key = "22:done", title = "Held Quest", blockedBy = "first: Kill Boars (not on your route)" },
        { key = "44:done", title = "Theirs", blockedBy = "needs level 20 first", helping = "Ann" },
        { key = "55:obj:1", title = "An objective", blockedBy = "needs level 20 first" },
        { key = "66:done", title = "Not blocked" },
    }
    local held = AT.Held(blocked)
    t:eq(held.ids[22], "first: Kill Boars (not on your route)", "a held hand-in, with its reason")
    t:eq(held.ids[44], nil, "a party member's hand-in: not yours to hold")
    t:eq(held.ids[55], nil, "an objective: not a hand-in")
    t:eq(held.ids[66], nil, "a hand-in on the route: not held")
    local list = { { id = 22, qid = 22, complete = true, title = "Held Quest" },
                   { id = 33, qid = 33, complete = true, title = "Ready Quest" } }
    local i, id = AT.PickFinished(list, held)
    t:eq(i, 2, "the held one is passed over")
    t:eq(id, 33, "the next finished one is opened")
    t:eq(AT.PickFinished({ list[1] }, held), nil, "only the held one: nothing opened")
    -- Older clients and plain quest lists give a position, not the quest id: by title.
    t:eq(AT.PickFinished({ { id = 1, complete = true, title = "Held Quest" } }, held), nil, "no quest id: matched by title")
    t:eq(AT.HeldWhy({ qid = 22 }, held), "first: Kill Boars (not on your route)", "the reason the NPC page says")
    t:eq(AT.HeldWhy({ qid = 33, title = "Ready Quest" }, held), nil, "a ready one: handed in")
    t:eq(AT.PickFinished(list), 1, "no route (nothing held): as before")
end)

-------------------------------------------------------------------------------
-- F-047: Flow doesn't know your attunements, keys or the instance limit; the
-- entrance step says so instead of implying you can go in.
-------------------------------------------------------------------------------

ns:Register("test", "dungeons: the entrance step says Flow can't check attunements, keys or the instance limit", function(t)
    local D = ns.dungeons
    local lines = D.EntranceDetails({ count = 3 }, 2, { "Gerald" })
    t:eq(lines[1], "3 quests for this run.", "the run's quests")
    t:eq(lines[2], "After the 2 pickups.", "after its pickups")
    t:eq(lines[3], "Not on the map (find the giver yourself): Gerald.", "an unplaced giver")
    t:eq(lines[#lines], D.ENTRY_UNKNOWN, "and what Flow can't check, last")
    t:ok(D.ENTRY_UNKNOWN:find("keys") ~= nil, "it names keys")
    t:eq(#D.EntranceDetails({ count = 1 }, 0, {}), 2, "no pickups, all placed: the count and the warning")
end)

-------------------------------------------------------------------------------
-- F-032 / F-033 / F-048: one travel cost for pruning, the shown yards, the
-- profession route and the dungeon prep detour.
-------------------------------------------------------------------------------

ns:Register("test", "route: an optional detour a flight makes cheap is kept, and the shown yards are the travel yards", function(t)
    local P = ns.planner
    local p = { cont = 0, wx = 0, wy = 0 }
    local A = { key = "w2:a", text = "a", points = { { cont = 0, wx = 100, wy = 0 } } }
    local O = { key = "w2:o", text = "o", optional = true, points = { { cont = 0, wx = 3000, wy = 0 } } }
    local oPt = O.points[1]
    local air = function(a, b) if a == oPt or b == oPt then return 50 end end
    local plan = P:Plan(p, { A, O }, { groups = false })
    t:eq(plan and #plan, 1, "no flights: the far optional step is dropped")
    t:eq(plan and plan.dropped and plan.dropped[1], "o", "and named as dropped")
    plan = P:Plan(p, { A, O }, { groups = false, air = air })
    t:eq(plan and #plan, 2, "a flight makes it a short detour: kept (prune counts the planner's own yards)")
    -- The shown yards: the travel yards the order was chosen by; leg stays straight.
    local flyTo = { cont = 0, wx = 3000, wy = 0 }
    local forge = { key = "w2:smelt", text = "smelt", points = { flyTo } }
    plan = P:Plan(p, { forge }, { groups = false, air = function(_, b) if b == flyTo then return 500 end end })
    t:eq(plan and math.floor(plan[1].trip + 0.5), 500, "trip: the flight's yards")
    t:eq(plan and math.floor(plan[1].tripCum + 0.5), 500, "tripCum adds them up")
    t:eq(plan and math.floor(plan[1].leg + 0.5), 3000, "leg: still the straight line")
    -- One public answer for other panels, same as the optimiser's.
    t:eq(P.TravelYards(p, flyTo, { air = function() return 500 end }), 500, "TravelYards: the planner's far()")
    t:eq(P.TravelYards(p, flyTo, { air = function() error("x") end }), 3000, "a failing lookup: the straight line")
    t:eq(P.TravelYards(p, flyTo, nil), 3000, "no options: the straight line")
end)

ns:Register("test", "route: the travel options are one table for every route, the quest route's extras on top", function(t)
    local N = ns.nav
    local o = N.TravelOptions()
    t:eq(type(o), "table", "a table")
    t:eq(o.first, nil, "no quest-route fields in the shared part")
    t:eq(o.tour, nil, "(no tour)")
end)

ns:Register("test", "dungeons: the prep detour is charged by the travel cost given, and the run's worth includes it", function(t)
    local D = ns.dungeons
    local from = { cont = 1, wx = 0, wy = 0 }
    local stops = { { cont = 1, wx = 3000, wy = 0 } }
    local entrance = { cont = 1, wx = 3000, wy = 0 }
    local straight = D.GatherMinutes(from, stops, entrance)
    local flown = D.GatherMinutes(from, stops, entrance, function(a) return a == from and 300 or 0 end)
    t:ok(flown < straight, "a flight shortens the gathering")
    t:near(flown, D.STOP_MINUTES + 300 / D.RUN_SPEED / 60, 1e-6, "by exactly the travel yards given")
    t:near(D.GatherMinutes(from, stops, entrance, function() error("x") end), straight, 1e-6, "a failing cost: the straight line")
    local far = D.GatherMinutes(from, { { cont = 2, wx = 0, wy = 0 } }, nil, function() return 1 end)
    t:near(far, D.STOP_MINUTES + 1500 / D.RUN_SPEED / 60, 1e-6, "another continent stays a long trip")
    local run = { quests = {}, levels = {}, leadIns = {} }
    local w = D.Worth(run, { level = 20, rate = 1000, runMinutes = 30, gatherMinutes = 10, estimate = function() return 0 end, share = function() return 1 end })
    t:eq(w.minutes, 40, "worth: the gathering minutes are part of the run's time")
end)

-------------------------------------------------------------------------------
-- F-027: the Compat wrappers say when they can't tell.
-------------------------------------------------------------------------------

ns:Register("test", "compat: a bag count the client can't give is unknown, and an item need on it is never met", function(t)
    local A = ns.api
    local keep = A.ItemCount
    local ok, err = pcall(function()
        A.ItemCount = function() return 3 end
        local n, known = A.Count(123)
        t:eq(n, 3, "a count: the number")
        t:eq(known, true, "and known")
        A.ItemCount = function() error("client broke") end
        n, known = A.Count(123)
        t:eq(n, 0, "a failing count: 0 for old callers")
        t:eq(known, false, "but not known")
        A.ItemCount = function() return nil end
        t:eq(select(2, A.Count(123)), false, "no answer: not known")
        A.ItemCount = nil
        t:eq(select(2, A.Count(123)), false, "no API: not known")
        t:eq(select(2, A.Count(nil)), false, "no item: not known")
        A.ItemCount = function() error("client broke") end
        t:eq((ns.nav.NeedState("item:123")), "unknown", "an item need Flow can't count: unknown")
        t:eq(ns.nav.NeedMet("item:123"), false, "and not met")
        A.ItemCount = function() return 1 end
        t:eq((ns.nav.NeedState("item:123")), "yes", "counted and carried: met")
    end)
    A.ItemCount = keep
    t:ok(ok, "ran: " .. tostring(err))
end)

-------------------------------------------------------------------------------
-- F-035 / F-036: the route labels don't promise a best order; near-first says
-- when it can't change your route.
-------------------------------------------------------------------------------

ns:Register("test", "route labels: Shortest and Most XP describe a quick plan, not a guaranteed best", function(t)
    local short, xp = ns:Get("routeObjective", "distance"), ns:Get("routeObjective", "xp")
    t:ok(short and short.tip:find("not a guaranteed", 1, true) ~= nil, "Shortest's tip says it's a quick plan")
    t:ok(short and short.tip:find("Shortest path", 1, true) == nil, "and doesn't claim the shortest path")
    t:ok(xp and xp.tip:find("not a guaranteed", 1, true) ~= nil, "Most XP's tip too")
    t:eq(ns.xpValue.DEFAULT, "distance", "the default the header names: Shortest")
end)

ns:Register("test", "near-first: on the default Shortest route it says it does nothing, and why", function(t)
    local F = ns.nearFirst
    t:ok(F.Note("distance", true) ~= nil, "Shortest: a note")
    t:ok(F.Note("distance", true):find("Most XP", 1, true) ~= nil, "naming where it does apply")
    t:eq(F.Note("xp", true), nil, "Most XP: it applies, no note")
    t:eq(F.Note("distance", false), nil, "off: nothing to explain")
    t:eq(F.Applies("distance"), false, "(and it really doesn't apply to Shortest)")
end)

-------------------------------------------------------------------------------
-- F-037 / F-040 / F-042: quest availability says why, refreshes, and retries.
-------------------------------------------------------------------------------

ns:Register("test", "quests: a quest skipped as not offered says why and can be cleared", function(t)
    local Q = ns.quests
    local keep = ns.db.quests.notOffered
    local ok, err = pcall(function()
        ns.db.quests.notOffered = {}
        local now = 100000
        t:eq(Q.NotOfferedReason(999301, now), nil, "never judged: no reason")
        Q.NoteOffer(999301, false, now)
        local why = Q.NotOfferedReason(999301, now + 60)
        t:ok(why and why:find("last talked", 1, true) ~= nil, "one visit: the ten-minute skip, said")
        ns.db.quests.notOffered[999301].firstAt = now - 3600
        Q.NoteOffer(999301, false, now)
        why = Q.NotOfferedReason(999301, now + 3600)
        t:ok(why and why:find("two visits", 1, true) ~= nil, "two visits: the day's skip, said")
        t:ok(why and why:find("23 more hour", 1, true) ~= nil, "with the time left")
        ns.db.quests.notOffered[999302] = { firstAt = now }
        t:eq(Q.ClearNotOffered(999301), 1, "clear one: one cleared")
        t:eq(ns.db.quests.notOffered[999301], nil, "its record gone")
        t:ok(ns.db.quests.notOffered[999302] ~= nil, "the other kept")
        t:eq(Q.ClearNotOffered(), 1, "clear all: the rest")
        t:eq(next(ns.db.quests.notOffered), nil, "none left")
        t:ok(type(ns.commands.notoffered) == "function", "/flow notoffered exists")
    end)
    ns.db.quests.notOffered = keep
    t:ok(ok, "ran: " .. tostring(err))
end)

ns:Register("test", "quests: the holiday list is re-read on a new day and the active events every time", function(t)
    local Q = ns.quests
    local keep = Q.EventModule
    local ok, err = pcall(function()
        local QE = { eventQuests = { { "Hallow", 999311 } }, activeQuests = {} }
        Q.EventModule = function() return QE end
        local set, active = Q.Events("2026-10-17")
        t:ok(set and set[999311], "an event quest")
        t:ok(not active[999311], "its event is off")
        QE.activeQuests = { [999311] = true }   -- (the event starts: a new table)
        active = select(2, Q.Events("2026-10-17"))
        t:ok(active[999311], "same day, event on: seen at once")
        QE.eventQuests = { { "Winter", 999312 } }
        set = Q.Events("2026-10-17")
        t:ok(set[999311] and not set[999312], "the event list is kept for the day")
        set = Q.Events("2026-10-18")
        t:ok(set[999312] and not set[999311], "a new day: read again")
        Q.EventModule = function() return nil end
        t:eq(Q.Events("2026-10-18"), nil, "no Questie: nothing")
    end)
    Q.EventModule = keep
    t:ok(ok, "ran: " .. tostring(err))
end)

ns:Register("test", "quests: a failed quest scan is shown as failed and a retry is scheduled", function(t)
    local Q = ns.quests
    local keep = Q.scanStats
    local ok, err = pcall(function()
        local waited, fn
        Q._ScanFailed("boom", function(s, f) waited, fn = s, f end)
        t:eq(Q.scanStats.failed, "boom", "the reason is kept")
        t:eq(Q:MissedState(), "failed", "state: failed (not 'still checking')")
        t:eq(waited, Q.SCAN_RETRY, "a retry is scheduled")
        t:eq(type(fn), "function", "with something to run")
        Q.scanStats = { scanned = 1 }
        t:ok(Q:MissedState() ~= "failed", "a good scan clears it")
    end)
    Q.scanStats = keep
    t:ok(ok, "ran: " .. tostring(err))
end)

-------------------------------------------------------------------------------
-- F-038 / F-039: custom (Focus) lines say what's missing and survive a sorter switch.
-------------------------------------------------------------------------------

ns:Register("test", "focus: a prerequisite the quest data lacks is listed as missing, not skipped silently", function(t)
    local F = ns.focus
    local data = {
        [999401] = { id = 999401, raw = { preQuestGroup = { 999402, 999499 } } },   -- 999499: not in the data
        [999402] = { id = 999402, raw = {} },
    }
    local get = function(id) return data[id] end
    local isDone = function() return false end
    local before = F.Before(999401, get, isDone)
    t:eq(#before, 1, "the known prerequisite is in the line")
    t:eq(before[1], 999402, "(that one)")
    local missing = F.Missing(999401, get, isDone)
    t:eq(#missing, 1, "the unknown one is reported")
    t:eq(missing[1], 999499, "(that one)")
    t:eq(#F.Missing(999401, get, function() return true end), 0, "all done: nothing missing")
end)

ns:Register("test", "focus: choosing Shortest keeps the custom lines, and Custom route brings them back", function(t)
    local F, X, db = ns.focus, ns.xpValue, ns.db.nav
    local saved = { focus = db.focus, sorter = db.sorter, base = db.baseSorter, sel = ns.nav.selection }
    local ok, err = pcall(function()
        db.focus = { { key = "w2:focus-step", title = "A Test Step" } }
        db.sorter = "distance"
        t:eq(#F.Filter({ { key = "bank" } }, true), 1, "off Custom: the route isn't cut down")
        t:eq(#db.focus, 1, "the lines wait, not wiped")
        t:ok(not F.Active(), "and aren't in force")
        X:SetMode("custom")
        t:eq(db.sorter, "custom", "Custom route with lines waiting: back on")
        t:ok(F.Active(), "the lines in force again")
        db.sorter = "distance"
        F.AddKey("w2:other-step", "Other")
        t:eq(#db.focus, 1, "a new pick off Custom starts a new custom route")
        t:eq(db.focus[1].key, "w2:other-step", "(with just the new pick)")
        db.focus, db.sorter = {}, "distance"
        X:SetMode("custom")
        t:eq(db.sorter, "distance", "nothing waiting: the radio alone still can't start one")
    end)
    db.focus, db.sorter, db.baseSorter, ns.nav.selection = saved.focus, saved.sorter, saved.base, saved.sel
    t:ok(ok, "ran: " .. tostring(err))
end)

ns:Register("test", "focus: the Flow Router's Custom route radio ungreys with lines waiting, and its click brings them back", function(t)
    local f = _G.FlowMapRoute
    local rb
    for _, b in ipairs(f and f.sorts or {}) do if b.mode == "custom" then rb = b end end
    if not rb then t:ok(true, "(Flow Router not built yet)") return end
    local db = ns.db.nav
    local saved = { sorter = db.sorter, focus = db.focus, shown = f:IsShown() }
    local ok, err = pcall(function()
        db.focus = { { key = "w2:focus-step", title = "A Test Step" } }
        db.sorter = "distance"
        ns.mapOverlay._updateList()
        if f:IsShown() then
            t:ok(rb:IsEnabled(), "lines waiting: the radio can be clicked")
            rb:Click()
            t:eq(db.sorter, "custom", "its click: Custom route again")
        end
    end)
    db.sorter, db.focus = saved.sorter, saved.focus
    pcall(ns.mapOverlay._updateList)
    if not saved.shown then f:Hide() end
    t:ok(ok, "ran: " .. tostring(err))
end)

-------------------------------------------------------------------------------
-- F-050 / F-051: the dungeon index says when it failed and tries again; an
-- unfiltered route inside a dungeon says so.
-------------------------------------------------------------------------------

ns:Register("test", "dungeons: a failed read of Questie's dungeons says failed, and is tried again", function(t)
    local D = ns.dungeons
    if not (D and D.IndexState and D._IndexFailed) then t:ok(false, "no index state") return end
    local savedRetry = D.INDEX_RETRY
    local ok, err = pcall(function()
        D._IndexFailed("test error")
        local state, why, wait = D.IndexState()
        t:eq(state, "failed", "shown as failed")
        t:eq(why, "test error", "with why")
        t:ok(wait and wait > 0 and wait <= D.INDEX_RETRY, "and when it tries again")
        if not D:Available() then
            t:ok(true, "(no Questie: /flow dungeons says so instead)")
        elseif D:Runs() == nil then
            local lines = D.Lines()
            t:ok(lines[1]:find("failed", 1, true) ~= nil, "/flow dungeons says it failed, not still reading")
        end
        D.INDEX_RETRY = 0
        D:Runs()
        t:ok((D.IndexState()) ~= "failed", "after the wait, it reads again")
    end)
    D.INDEX_RETRY = savedRetry
    t:ok(ok, "ran: " .. tostring(err))
end)

ns:Register("test", "dungeons: outside a dungeon the route isn't cut, and there is no inside note", function(t)
    local D = ns.dungeons
    local list = { { key = "100:1" }, { key = "user:wp" } }
    if IsInInstance and select(2, IsInInstance()) == "party" then
        t:ok(true, "(inside a dungeon: the note is the in-game check)")
        return
    end
    t:eq(#D:FilterInside(list), 2, "the whole route")
    t:eq(D.InsideNote(), nil, "nothing to explain")
end)
