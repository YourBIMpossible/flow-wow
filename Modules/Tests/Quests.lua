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
