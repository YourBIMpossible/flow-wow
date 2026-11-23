local _, ns = ...

-- Tests for ZFlow/Nav/Trip.lua (P-TRIP slice 1): the trip list. Pure parts
-- only; made-up places.

local tests = {}

local function P() return ns.Nav.Trip end

local HERE = { map = 1, x = 0.5, y = 0.5, size = { w = 1000, h = 1000 } }

local function stop(label, map, x, y)
    return { kind = "here", label = label, place = { map = map, x = x, y = y } }
end

tests["trip list: a stop is added; one with no place is not"] = function(t)
    local list = {}
    t.eq(P().Add(list, stop("Camp", 1, 0.6, 0.5)), true)
    t.eq(#list, 1)
    local ok, why = P().Add(list, { kind = "here", label = "Nowhere" })
    t.eq(ok, false)
    t.ok(type(why) == "string" and why ~= "", tostring(why))
    t.eq(#list, 1, "not added")
end

tests["trip list: the list is bounded"] = function(t)
    local list = {}
    for i = 1, P().MAX do t.eq(P().Add(list, stop("S" .. i, 1, 0.5, i / 100)), true) end
    local ok, why = P().Add(list, stop("One more", 1, 0.1, 0.1))
    t.eq(ok, false)
    t.eq(why, P().FULL)
    t.eq(#list, P().MAX)
end

tests["trip list: remove takes the nth stop; a bad number says why"] = function(t)
    local list = {}
    P().Add(list, stop("A", 1, 0.1, 0.1)); P().Add(list, stop("B", 1, 0.2, 0.2)); P().Add(list, stop("C", 1, 0.3, 0.3))
    local gone = P().Remove(list, 2)
    t.eq(gone and gone.label, "B")
    t.eq({ list[1].label, list[2].label }, { "A", "C" })
    local none, why = P().Remove(list, 7)
    t.eq(none, nil)
    t.ok(type(why) == "string" and why ~= "", tostring(why))
    t.eq(P().Remove(list, "x"), nil)
    t.eq(#list, 2)
end

tests["trip list: the order is planned on this map, other maps after in the order added"] = function(t)
    local list = { stop("Far", 1, 0.9, 0.5), stop("Away", 2, 0.5, 0.5), stop("Near", 1, 0.6, 0.5) }
    local ordered, label = P().Order(list, HERE)
    t.eq(#ordered, 3)
    t.eq({ ordered[1].label, ordered[2].label, ordered[3].label }, { "Near", "Far", "Away" })
    t.eq(label, ns.Nav.ROUTE_STRAIGHT)
    t.eq(list[1].label, "Far", "the saved list keeps the order it was added in")
end

tests["trip list: own trip times change the order and the label"] = function(t)
    local list = { stop("A", 1, 0.6, 0.5), stop("B", 1, 0.4, 0.5) }
    -- A trip to A takes long (a wall), to B is quick.
    local function legs(a, b)
        if b.x > 550 and a.x == 500 then return 900, "exact" end
        return nil
    end
    local ordered, label = P().Order(list, HERE, legs)
    t.eq(ordered[1].label, "B")
    t.eq(label, ns.Nav.ROUTE_LEARNED)
end

tests["trip list: the lines show the distance from the player"] = function(t)
    local list = { stop("Camp", 1, 0.6, 0.5), stop("Away", 2, 0.5, 0.5) }
    list[1].detail = "where you stood"
    local lines = P().Lines(list, HERE)
    t.eq(lines[1], P().HEADER:format(2))
    t.eq(lines[2], "1. Camp - where you stood - 100 yd")
    t.eq(lines[3], "2. Away - " .. P().OTHER_MAP)
    t.eq(P().Lines({}, HERE)[1], P().EMPTY)
end

tests["trip list: the run handed to the route keeps the order and the places"] = function(t)
    local run = P().Run({ stop("Near", 1, 0.6, 0.5), stop("Far", 1, 0.9, 0.5) }, "lbl")
    t.eq(#run.steps, 2)
    t.eq(run.steps[1].label, "Near")
    t.eq(run.steps[1].kind, "trip")
    t.eq(run.steps[2].place, { map = 1, x = 0.9, y = 0.5 })
    t.ok(type(run.title) == "string", "titled")
end

tests["trip list: a quest is found by id or by part of its title"] = function(t)
    local rows = { { id = 7, title = "Red Silk" }, { id = 9, title = "The Boars of Elwynn" } }
    t.eq(P().Quest(rows, "9") and P().Quest(rows, "9").id, 9)
    t.eq(P().Quest(rows, "boars") and P().Quest(rows, "boars").id, 9)
    t.eq(P().Quest(rows, "nope"), nil)
    t.eq(P().Quest(rows, ""), nil)
end

tests["trip list: a dungeon is found by part of its name"] = function(t)
    local list = { { key = 2, name = "Wailing Caverns" }, { key = 1, name = "The Deadmines" } }
    t.eq(P().Dungeon(list, "dead") and P().Dungeon(list, "dead").key, 1)
    t.eq(P().Dungeon(list, "xyz"), nil)
end

return tests
