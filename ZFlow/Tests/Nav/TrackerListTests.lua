local _, ns = ...

-- Tests for ZFlow/Nav/TrackerList.lua (FLOW-PARITY A2-18, the logic half):
-- what the tracker window lists for each step, after legacy Flow's tracker
-- (Modules/Nav/RouteTracker.lua): what the step is, its count, its distance,
-- held steps with why. Pure. Made-up quests and places.

local tests = {}

local function TL() return ns.Nav.TrackerList end

local HERE = { map = 1, x = 0.5, y = 0.5, size = { w = 1000, h = 1000 } }

local function view(stops) return { kind = "quests", label = "straight", stops = stops, left = {} } end

tests["tracker list: what each step is"] = function(t)
    t.eq(TL().Kind({ quest = 1, objective = 1 }), "objective")
    t.eq(TL().Kind({ quest = 1, turnIn = true }), "turnin")
    t.eq(TL().Kind({ quest = 2, kind = "pickup" }), "pickup")
    t.eq(TL().Kind({ kind = "sell" }), "town")
    t.eq(TL().Kind({ kind = "repair" }), "town")
    t.eq(TL().Kind({ kind = "entrance" }), "run")
    t.eq(TL().Kind(nil), nil)
end

tests["tracker list: the count is the log's own, never made up"] = function(t)
    t.eq(TL().Count({ detail = "Boars slain: 2/8" }), "2/8")
    t.eq(TL().Count({ detail = "3/10 Kobold Vermin slain" }), "3/10")
    t.eq(TL().Count({ detail = "Turn in at Smith" }), nil)
    t.eq(TL().Count({}), nil)
end

-- Lead section 770: the route's steps first, then the held ones, then those
-- that can't be placed, as Flow's tracker lists its plan and then its
-- blocked goals (Modules/Nav/RouteTracker.lua:504-519; a held step is not
-- in Flow's plan). The distances are the walked steps' own legs.
tests["tracker list: the route's steps first, then held ones with why, the first is now"] = function(t)
    local v = view({
        { label = "Bandages", quest = 3, turnIn = true, held = "not complete yet", place = { map = 1, x = 0.55, y = 0.5 } },
        { label = "Boars", quest = 1, objective = 1, detail = "Boars slain: 2/8", place = { map = 1, x = 0.6, y = 0.5 } },
        { label = "Pick up: Lost Pages", quest = 9, kind = "pickup", place = { map = 1, x = 0.7, y = 0.5 } },
    })
    v.left = { { quest = 5, label = "Find Kurl", why = "no place known" } }
    local rows, more, nLeft = TL().Rows(v, HERE)
    t.eq(#rows, 4)
    t.eq(more, 0)
    t.eq(nLeft, 1)
    t.eq(rows[1].label, "Boars")
    t.eq(rows[1].current, true, "the first not held")
    t.eq(rows[1].kind, "objective"); t.eq(rows[1].count, "2/8")
    t.eq(rows[1].dist, "100 yd", "from where you stand, not from the held step")
    t.eq(rows[2].kind, "pickup")
    t.eq(rows[2].dist, "100 yd")
    t.eq(rows[3].label, "Bandages")
    t.eq(rows[3].held, "not complete yet")
    t.eq(rows[3].current, nil, "a held step is not now")
    t.eq(rows[3].dist, nil, "a held step is not walked")
    t.eq(rows[4].left, "no place known")
    local r2, m2 = TL().Rows(v, HERE, 2)
    t.eq(#r2, 2, "the route's steps fill the list first")
    t.eq(r2[2].held, nil)
    t.eq(m2, 1, "the held step left out is counted")
end

tests["tracker list: at most max, then how many more; no route, nothing"] = function(t)
    local stops = {}
    for i = 1, 5 do stops[i] = { label = "S" .. i, quest = i, objective = 1, place = { map = 1, x = 0.5, y = 0.5 } } end
    local rows, more = TL().Rows(view(stops), HERE, 3)
    t.eq(#rows, 3)
    t.eq(more, 2)
    t.eq(TL().Rows(nil, HERE), nil)
end

-- The steps that can't be placed (TripRoute View().left, with why) come
-- after the route's, in the rows left over, as Flow's tracker lists its
-- blocked goals after the plan (Modules/Nav/RouteTracker.lua:504-519) and
-- counts them all for the lock (:476, RT.Title :458-460).
tests["tracker list: steps that can't be placed follow the route's, with why"] = function(t)
    local v = view({ { label = "Boars", quest = 8, objective = 1, place = { map = 1, x = 0.5, y = 0.6 } } })
    v.left = { { quest = 9, label = "Find Kurl", detail = "Kurl's Map", why = "no place known" },
               { quest = 10, label = "Deliver", why = "level 12" } }
    local rows, more, nLeft = TL().Rows(v, HERE, 2)
    t.eq(#rows, 2, "the route's step, then one that can't be placed")
    t.eq(more, 0)
    t.eq(nLeft, 2, "all of them counted")
    t.eq(rows[1].label, "Boars")
    t.eq(rows[1].current, true)
    t.eq(rows[2].label, "Find Kurl")
    t.eq(rows[2].left, "no place known")
    t.eq(rows[2].detail, "Kurl's Map")
    t.eq(rows[2].current, nil, "never the current step")
    t.eq(rows[2].dist, nil, "no place, no distance")
    local full = view({ { label = "A", place = { map = 1, x = 0.5, y = 0.5 } },
                        { label = "B", place = { map = 1, x = 0.5, y = 0.5 } } })
    full.left = v.left
    local r2, _, n2 = TL().Rows(full, HERE, 2)
    t.eq(#r2, 2, "a full list leaves them out")
    t.eq(r2[2].left, nil)
    t.eq(n2, 2, "but still counts them")
    local only = view({})
    only.left = v.left
    local r3 = TL().Rows(only, HERE)
    t.eq(r3 and #r3, 2, "nothing on the route: they are still listed")
    t.eq(r3 and r3[1].current, nil)
end

-- Slice 5: the one builder also numbers the rows, merges turn-ins at
-- one place and gives each stop its own words, as the list beside the
-- quest log has always done — the tracker reads the same rows now.
tests["tracker list: numbered rows, turn-ins at one place are one row"] = function(t)
    local v = view({
        { quest = 11, objective = 1, label = "Boar Trouble", detail = "Boars slain: 2/8", place = { map = 1, x = 0.5, y = 0.6 } },
        { quest = 12, turnIn = true, label = "A Letter Home", detail = "Turn in: Marshal Dunn", place = { map = 1, x = 0.8, y = 0.6 } },
        { quest = 13, turnIn = true, label = "Lost Tools", detail = "Turn in: Marshal Dunn", place = { map = 1, x = 0.8, y = 0.6 } },
        { quest = 14, turnIn = true, label = "Old Debts", detail = "Turn in", place = { map = 2, x = 0.3, y = 0.3 } },
    })
    local rows, _, _, counts = TL().Rows(v, HERE)
    t.eq(#rows, 3, "the two turn-ins at one place are one row")
    t.eq(rows[1].n, 1); t.eq(rows[2].n, 2); t.eq(rows[3].n, 3)
    t.eq(rows[1].text, "Boars slain: 2/8")
    t.eq(rows[1].sub, "For the quest Boar Trouble")
    t.eq(rows[2].merged, 2)
    t.eq(rows[2].text, "Turn in 2 quests")
    t.eq(rows[2].sub, "A Letter Home, Lost Tools. Give them to Marshal Dunn")
    t.eq(rows[3].text, "Turn in Old Debts")
    t.eq(rows[3].merged, 1)
    t.eq(counts.stops, 3, "stops counted as the rows read them")
    t.eq(counts.waiting, 0)
end

tests["tracker list: a held reason is said in plain words"] = function(t)
    t.eq(TL().Why("not complete any more"), "this quest is not complete any more. Finish it again first.")
    t.eq(TL().Why("not on this map"), "it is in another zone. Plan a new route when you get there.")
    t.eq(TL().Why("some other reason"), "some other reason", "a reason with no plain form is shown as given")
    local v = view({ { label = "Stale Bread", quest = 16, turnIn = true, held = "not complete any more",
        place = { map = 1, x = 0.1, y = 0.1 } } })
    local rows = TL().Rows(v, HERE)
    t.eq(rows[1].held, "this quest is not complete any more. Finish it again first.")
    t.eq(rows[1].why, "not complete any more", "the route's own words are kept on the row")
end

tests["tracker list: how many stops show, and the plan line"] = function(t)
    t.eq(TL().MaxShown("5"), 5)
    t.eq(TL().MaxShown("20"), 20)
    t.eq(TL().MaxShown("All"), TL().ALL)
    t.eq(TL().MaxShown(nil), TL().ALL, "no saved value shows all")
    t.eq(TL().MaxShown(10), 10)
    t.eq(TL().Plan(nil, nil), "Today's route · Shortest first", "the defaults, in plain words")
    t.eq(TL().Plan("quests", "xp"), "My quests only · Most XP first")
    t.eq(TL().Plan("Everything", "Most XP first"), "Everything · Most XP first", "the saved labels read back")
end

tests["tracker list: rows carry their stop and its place in the route (slice 7)"] = function(t)
    local a = { label = "Boars", quest = 1, objective = 1, detail = "Boars slain: 2/8", place = { map = 1, x = 0.6, y = 0.5 } }
    local b1 = { label = "A Letter Home", quest = 2, turnIn = true, detail = "Turn in: Marshal Dunn", place = { map = 1, x = 0.8, y = 0.6 } }
    local b2 = { label = "Lost Tools", quest = 3, turnIn = true, detail = "Turn in: Marshal Dunn", place = { map = 1, x = 0.8, y = 0.6 } }
    local cStop = { label = "Wolves", quest = 4, kind = "pickup", detail = "Pick up from Guard Thom", place = { map = 2, x = 0.2, y = 0.2 } }
    local heldStop = { label = "Old Debts", quest = 5, turnIn = true, detail = "Turn in", held = "not complete any more", place = { map = 2, x = 0.3, y = 0.3 } }
    local leftStop = { quest = 6, label = "Far Away", detail = "Turn in", why = "not on this map" }
    local v = view({ a, b1, b2, cStop, heldStop })
    v.left = { leftStop }
    local rows = TL().Rows(v, HERE)
    t.eq(rows[1].stop, a, "the first row carries its stop")
    t.eq(rows[1].index, 1, "the first walked stop is 1: the next step")
    t.eq(rows[2].stop, b1, "a merged row carries its first stop")
    t.eq(rows[2].index, 2, "a merged row takes its first stop's place")
    t.eq(rows[3].index, 4, "the count runs over stops, not rows")
    t.eq(rows[4].stop, heldStop, "a held row carries its stop")
    t.eq(rows[4].index, nil, "a held row has no place on the route")
    t.eq(rows[5].stop, leftStop, "a left-behind row carries its stop")
    t.eq(rows[5].index, nil, "a left-behind row has no place either")
end

return tests
