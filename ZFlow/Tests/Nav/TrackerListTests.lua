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

return tests
