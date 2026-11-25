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

tests["tracker list: rows in route order, the first not held is now, held ones say why"] = function(t)
    local rows = TL().Rows(view({
        { label = "Bandages", quest = 3, turnIn = true, held = "not complete yet", place = { map = 1, x = 0.55, y = 0.5 } },
        { label = "Boars", quest = 1, objective = 1, detail = "Boars slain: 2/8", place = { map = 1, x = 0.6, y = 0.5 } },
        { label = "Pick up: Lost Pages", quest = 9, kind = "pickup", place = { map = 1, x = 0.7, y = 0.5 } },
    }), HERE)
    t.eq(#rows, 3)
    t.eq(rows[1].held, "not complete yet")
    t.eq(rows[1].current, nil, "a held step is not now")
    t.eq(rows[2].current, true, "the first not held")
    t.eq(rows[2].kind, "objective"); t.eq(rows[2].count, "2/8")
    t.eq(rows[3].kind, "pickup")
    t.ok(type(rows[2].dist) == "string", "with its distance")
end

tests["tracker list: at most max, then how many more; no route, nothing"] = function(t)
    local stops = {}
    for i = 1, 5 do stops[i] = { label = "S" .. i, quest = i, objective = 1, place = { map = 1, x = 0.5, y = 0.5 } } end
    local rows, more = TL().Rows(view(stops), HERE, 3)
    t.eq(#rows, 3)
    t.eq(more, 2)
    t.eq(TL().Rows(nil, HERE), nil)
end

return tests
