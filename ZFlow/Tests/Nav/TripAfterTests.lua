local _, ns = ...

-- Tests for G42 (P-TRIP slice 3): order constraints ("after") in
-- N.RoutePlan and the trip list, and the words of a leg to another map.
-- Pure parts only; made-up places.

local tests = {}

local N = ns.Nav
local function P() return N.Trip end

local SIZE = { w = 1000, h = 1000 }
local FROM = { map = 1, x = 0.5, y = 0.5 }
local HERE = { map = 1, x = 0.5, y = 0.5, size = { w = 1000, h = 1000 } }

local function pt(x, y, map) return { map = map or 1, x = x, y = y } end

local function stop(id, label, map, x, y, more)
    local s = { id = id, kind = "here", label = label, place = { map = map, x = x, y = y } }
    for key, v in pairs(more or {}) do s[key] = v end
    return s
end

local function labels(list)
    local out = {}
    for i, s in ipairs(list or {}) do out[i] = s.label end
    return out
end

local function indexes(route)
    local out = {}
    for i, s in ipairs(route.stops) do out[i] = s.index end
    return out
end

tests["route plan: a place that comes after another is visited after it"] = function(t)
    -- 1 is next to the player, 2 is far; 1 must come after 2.
    local places = { pt(0.55, 0.5), pt(0.9, 0.5) }
    local route = N.RoutePlan(places, 1, SIZE, FROM, nil, { [1] = { 2 } })
    t.eq(indexes(route), { 2, 1 })
end

tests["route plan: shortening never moves a stop before what it follows"] = function(t)
    -- Shortest is 1, 2, 3 in a line; 2 must come after 3.
    local places = { pt(0.6, 0.5), pt(0.7, 0.5), pt(0.8, 0.5) }
    local route = N.RoutePlan(places, 1, SIZE, FROM, nil, { [2] = { 3 } })
    local seen = {}
    for i, s in ipairs(route.stops) do seen[s.index] = i end
    t.ok(seen[3] < seen[2], "3 before 2: " .. table.concat(indexes(route), ","))
    t.eq(#route.stops, 3)
end

tests["route plan: no after, the order is as before"] = function(t)
    local places = { pt(0.9, 0.5), pt(0.6, 0.5) }
    t.eq(indexes(N.RoutePlan(places, 1, SIZE, FROM)), indexes(N.RoutePlan(places, 1, SIZE, FROM, nil, {})))
end

tests["route plan: an after naming a place not on the route is let go"] = function(t)
    local places = { pt(0.6, 0.5), pt(0.5, 0.5, 2) }
    local route = N.RoutePlan(places, 1, SIZE, FROM, nil, { [1] = { 2 } })
    t.eq(indexes(route), { 1 })
end

tests["route plan: a circle of afters is refused and named"] = function(t)
    local places = { pt(0.6, 0.5), pt(0.7, 0.5), pt(0.8, 0.5) }
    local route, why, ring = N.RoutePlan(places, 1, SIZE, FROM, nil, { [1] = { 2 }, [2] = { 3 }, [3] = { 1 } })
    t.eq(route, nil)
    t.eq(why, "circle")
    t.eq(type(ring) == "table" and #ring, 3)
end

tests["route cycle: none in a line, the stops of one when there is"] = function(t)
    t.eq(N.RouteCycle(3, { [2] = { 1 }, [3] = { 2 } }), nil)
    local ring = N.RouteCycle(2, { [1] = { 2 }, [2] = { 1 } })
    t.ok(type(ring) == "table" and #ring == 2, "two stops")
end

tests["trip after: a stop is set after another; a circle is refused with one line naming the stops"] = function(t)
    local list = {}
    P().Add(list, stop(nil, "Camp", 1, 0.6, 0.5))
    P().Add(list, stop(nil, "Mail", 1, 0.9, 0.5))
    t.ok(list[1].id ~= nil and list[2].id ~= nil and list[1].id ~= list[2].id, "each stop has its own id")
    local ok, line = P().After(list, 1, 2)
    t.eq(ok, true)
    t.eq(line, P().AFTER_SET:format(1, "Camp", 2, "Mail"))
    local bad, why = P().After(list, 2, 1)
    t.eq(bad, false)
    t.ok(type(why) == "string" and why:find("Camp", 1, true) ~= nil and why:find("Mail", 1, true) ~= nil, tostring(why))
    t.eq(list[2].after, nil, "the refused after is not kept")
    local none, why2 = P().After(list, 1, 1)
    t.eq(none, false)
    t.ok(type(why2) == "string" and why2 ~= "", tostring(why2))
    t.eq(P().After(list, 1, 9), false)
end

tests["trip after: the order obeys it on one map"] = function(t)
    local list = {}
    P().Add(list, stop(nil, "Camp", 1, 0.6, 0.5))
    P().Add(list, stop(nil, "Mail", 1, 0.9, 0.5))
    P().After(list, 1, 2)
    t.eq(labels(P().Order(list, HERE)), { "Mail", "Camp" })
end

tests["trip after: a stop here after a stop on another map waits for it"] = function(t)
    local list = {}
    P().Add(list, stop(nil, "Camp", 1, 0.6, 0.5))
    P().Add(list, stop(nil, "Inn", 1, 0.7, 0.5))
    P().Add(list, stop(nil, "Mail", 2, 0.5, 0.5))
    P().After(list, 1, 3)
    t.eq(labels(P().Order(list, HERE)), { "Inn", "Mail", "Camp" })
end

tests["trip after: removing a stop lets go of the afters that named it"] = function(t)
    local list = {}
    P().Add(list, stop(nil, "Camp", 1, 0.6, 0.5))
    P().Add(list, stop(nil, "Mail", 1, 0.9, 0.5))
    P().After(list, 1, 2)
    P().Remove(list, 2)
    t.eq(list[1].after, nil)
end

tests["trip after: a quest's hand-in comes after its objectives on the route"] = function(t)
    local list = {
        stop(1, "Hand in: Boars", 1, 0.55, 0.5, { kind = "giver", quest = 5 }),
        stop(2, "Boars slain", 1, 0.9, 0.5, { quest = 5, objective = 1 }),
    }
    t.eq(labels(P().Order(list, HERE)), { "Boars slain", "Hand in: Boars" })
end

tests["trip after: a dungeon's entrance comes after the pick-up givers of that dungeon"] = function(t)
    local list = {
        stop(1, "Deadmines", 1, 0.55, 0.5, { kind = "dungeon", quests = { 7 } }),
        stop(2, "Pick up: Red Silk", 1, 0.9, 0.5, { quest = 7, pickUp = true }),
        stop(3, "Pick up: Other", 1, 0.3, 0.5, { quest = 8, pickUp = true }),
    }
    local order = labels(P().Order(list, HERE))
    t.eq(order[1], "Pick up: Red Silk")
    t.eq(order[2], "Deadmines")
end

tests["trip after: a circle makes no order and says which stops"] = function(t)
    local list = { stop(1, "A", 1, 0.6, 0.5, { after = { 2 } }), stop(2, "B", 1, 0.7, 0.5, { after = { 1 } }) }
    local ordered, why = P().Order(list, HERE)
    t.eq(ordered, nil)
    t.ok(type(why) == "string" and why:find("A", 1, true) ~= nil and why:find("B", 1, true) ~= nil, tostring(why))
end

tests["trip via: the words of a leg to another map"] = function(t)
    t.eq(P().ViaText({ label = "Boat to Tirisfal dock", via = "crossing" }), "via Boat to Tirisfal dock")
    t.eq(P().ViaText({ label = "Mail" }), nil, "no travel step: no words")
    t.eq(P().ViaText(nil), nil)
    t.eq(P().ViaText({ via = "far", label = "Mail" }), N.Travel.FAR)
end

tests["trip via: the list says how a stop on another map is reached"] = function(t)
    local list = { stop(1, "Camp", 1, 0.6, 0.5), stop(2, "Mail", 2, 0.5, 0.5) }
    local lines = P().Lines(list, HERE, { [2] = "via Boat to Tirisfal dock" })
    t.eq(lines[2], "1. Camp - 100 yd")
    t.eq(lines[3], "2. Mail - " .. P().OTHER_MAP .. " - via Boat to Tirisfal dock")
end

return tests
