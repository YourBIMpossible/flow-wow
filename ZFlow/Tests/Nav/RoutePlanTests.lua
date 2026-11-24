-- Tests for ZFlow/Nav/RoutePlan.lua (G42, L-E): the pure route planner.
-- Straight lines on one map, said to be so. Made-up places, test only.
-- Not tested in game.
local _, ns = ...

local N = ns.Nav
local tests = {}

local MAP = 1411
local SQUARE = { w = 1000, h = 1000 }

local function near(a, b)
    return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-6
end

local function at(x, y, map)
    return { map = map or MAP, x = x, y = y }
end

local function order(route)
    local out = {}
    for i = 1, #route.stops do out[i] = route.stops[i].index end
    return out
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for key, value in pairs(v) do out[key] = copy(value) end
    return out
end

tests["route: the words and the limit are the ones agreed"] = function(t)
    t.eq(N.ROUTE_STRAIGHT, "straight lines, not paths")
    t.eq(N.ROUTE_MAX, 40)
end

tests["route: every route says it is straight lines"] = function(t)
    local route, why = N.RoutePlan({ at(0.5, 0.5) }, MAP, SQUARE, at(0.25, 0.5))
    t.eq(why, nil)
    t.eq(route.straight, true)
    t.eq(route.label, N.ROUTE_STRAIGHT)
    t.eq(route.map, MAP)
end

tests["route: places on a line are visited in the order they lie"] = function(t)
    local places = { at(0.875, 0.5), at(0.25, 0.5), at(0.625, 0.5) }
    local route = N.RoutePlan(places, MAP, SQUARE, at(0.125, 0.5))
    t.eq(order(route), { 2, 3, 1 })
    t.eq(route.fromKnown, true)
    t.ok(near(route.stops[1].leg, 125), "from the start to the first")
    t.ok(near(route.stops[2].leg, 375))
    t.ok(near(route.stops[3].leg, 250))
    t.ok(near(route.total, 750), "the legs added up")
end

tests["route: each stop is the place itself, with where it was in the list"] = function(t)
    local places = { at(0.875, 0.5), at(0.25, 0.5) }
    places[1].name = "Far"
    places[2].name = "Close"
    local route = N.RoutePlan(places, MAP, SQUARE, at(0.125, 0.5))
    t.ok(route.stops[1].place == places[2], "not a copy")
    t.eq(route.stops[1].index, 2)
    t.ok(route.stops[2].place == places[1])
    t.eq(route.stops[2].place.name, "Far")
end

tests["route: the list handed in is not changed"] = function(t)
    local places = { at(0.875, 0.5), at(0.25, 0.5), at(0.625, 0.5), "junk", at(0.5, 0.5, 9) }
    local before = copy(places)
    local from, size = at(0.125, 0.5), { w = 1000, h = 1000 }
    N.RoutePlan(places, MAP, size, from)
    t.eq(places, before)
    t.eq(from, at(0.125, 0.5))
    t.eq(size, { w = 1000, h = 1000 })
end

-- Nearest-next alone goes east, further east, then all the way back west
-- (620 yards). Going to the lone western place first is 490.
tests["route: shorter than taking the nearest place each time"] = function(t)
    local places = { at(0.625, 0.5), at(0.75, 0.5), at(0.375, 0.5) }
    places[1].x, places[3].x = 0.6, 0.38
    local route = N.RoutePlan(places, MAP, SQUARE, at(0.5, 0.5))
    t.eq(order(route), { 3, 1, 2 })
    t.ok(near(route.total, 120 + 220 + 150), "490 yards, not 620")
end

tests["route: the start not known: no first leg, never a 0"] = function(t)
    local places = { at(0.5, 0.5), at(0.2, 0.5), at(0.9, 0.5) }
    local route, why = N.RoutePlan(places, MAP, SQUARE)
    t.eq(why, nil)
    t.eq(route.fromKnown, false)
    t.eq(order(route), { 2, 1, 3 }, "the middle place is not left for last")
    t.eq(route.stops[1].leg, nil, "not known is not 0")
    t.ok(near(route.stops[2].leg, 300))
    t.ok(near(route.stops[3].leg, 400))
    t.ok(near(route.total, 700), "only the legs that are known")
end

tests["route: a start on another map, or with no place, is not known"] = function(t)
    local places = { at(0.5, 0.5), at(0.2, 0.5), at(0.9, 0.5) }
    local route = N.RoutePlan(places, MAP, SQUARE, at(0.9, 0.5, 9))
    t.eq(route.fromKnown, false)
    t.eq(route.stops[1].leg, nil)
    t.eq(order(route), { 2, 1, 3 })
    route = N.RoutePlan(places, MAP, SQUARE, { map = MAP })
    t.eq(route.fromKnown, false)
    route = N.RoutePlan(places, MAP, SQUARE, { map = MAP, x = 1.5, y = 0.5 })
    t.eq(route.fromKnown, false)
    route = N.RoutePlan(places, MAP, SQUARE, "here")
    t.eq(route.fromKnown, false)
end

tests["route: distances are yards, not shares of the map"] = function(t)
    -- On a map twice as wide as it is high, 0.25 across is further than
    -- 0.4 down.
    local places = { at(0.75, 0.5), at(0.5, 0.9) }
    local route = N.RoutePlan(places, MAP, { w = 1000, h = 500 }, at(0.5, 0.5))
    t.eq(order(route), { 2, 1 })
    t.ok(near(route.stops[1].leg, 200))
    t.ok(near(route.stops[2].leg, math.sqrt(250 * 250 + 200 * 200)))
end

tests["route: one place is a route of one stop"] = function(t)
    local route = N.RoutePlan({ at(0.5, 0.75) }, MAP, SQUARE, at(0.5, 0.5))
    t.eq(order(route), { 1 })
    t.ok(near(route.stops[1].leg, 250))
    t.ok(near(route.total, 250))
    route = N.RoutePlan({ at(0.5, 0.75) }, MAP, SQUARE)
    t.eq(order(route), { 1 })
    t.eq(route.stops[1].leg, nil)
    t.eq(route.total, 0, "no leg is known, so none is added")
end

tests["route: two places on one spot are both stops, a real 0 apart"] = function(t)
    local route = N.RoutePlan({ at(0.5, 0.75), at(0.5, 0.75) }, MAP, SQUARE, at(0.5, 0.5))
    t.eq(order(route), { 1, 2 }, "the earlier in the list first")
    t.eq(route.stops[2].leg, 0)
end

tests["route: places that cannot be placed are left out, each with the reason"] = function(t)
    local places = {
        at(0.25, 0.5),
        at(0.5, 0.5, 9),
        { map = MAP, x = 0.5 },
        "junk",
        { map = MAP, x = 0.5, y = 1.5 },
        at(0.75, 0.5),
        { x = 0.5, y = 0.5 },
    }
    local route = N.RoutePlan(places, MAP, SQUARE, at(0.125, 0.5))
    t.eq(order(route), { 1, 6 })
    t.eq(route.left, {
        { index = 2, reason = "other map" },
        { index = 3, reason = "no place" },
        { index = 4, reason = "no place" },
        { index = 5, reason = "no place" },
        { index = 7, reason = "other map" },
    })
end

tests["route: nothing left out is an empty list"] = function(t)
    local route = N.RoutePlan({ at(0.25, 0.5) }, MAP, SQUARE)
    t.eq(route.left, {})
end

tests["route: no map, no size, no places: no route and the reason"] = function(t)
    local places = { at(0.25, 0.5) }
    local route, why = N.RoutePlan(places, nil, SQUARE)
    t.eq(route, nil)
    t.eq(why, "no map")
    route, why = N.RoutePlan(places, MAP, nil)
    t.eq(route, nil)
    t.eq(why, "size unknown")
    t.eq(select(2, N.RoutePlan(places, MAP, { w = 1000 })), "size unknown")
    t.eq(select(2, N.RoutePlan(places, MAP, { w = 0, h = 500 })), "size unknown")
    t.eq(select(2, N.RoutePlan(places, MAP, { w = 1000, h = 0 / 0 })), "size unknown")
    t.eq(select(2, N.RoutePlan(nil, MAP, SQUARE)), "no places")
    t.eq(select(2, N.RoutePlan({}, MAP, SQUARE)), "no places")
    t.eq(select(2, N.RoutePlan({ at(0.5, 0.5, 9), "junk" }, MAP, SQUARE)), "no places")
    t.eq(select(2, N.RoutePlan(nil, nil, nil)), "no map", "the first that holds")
end

tests["route: more places than the limit: no route, none dropped quietly"] = function(t)
    local places = {}
    for i = 1, N.ROUTE_MAX do places[i] = at(i / 64, 0.5) end
    local route, why = N.RoutePlan(places, MAP, SQUARE, at(0, 0.5))
    t.eq(why, nil)
    t.eq(#route.stops, N.ROUTE_MAX, "the limit itself is taken")
    places[#places + 1] = at(0.75, 0.75)
    route, why = N.RoutePlan(places, MAP, SQUARE, at(0, 0.5))
    t.eq(route, nil)
    t.eq(why, "too many places")
    -- Places left out do not count toward the limit.
    places[#places] = at(0.75, 0.75, 9)
    route = N.RoutePlan(places, MAP, SQUARE, at(0, 0.5))
    t.eq(#route.stops, N.ROUTE_MAX)
    t.eq(#route.left, 1)
end

tests["route: the same places always give the same order"] = function(t)
    local places = { at(0.2, 0.2), at(0.8, 0.2), at(0.8, 0.8), at(0.2, 0.8), at(0.5, 0.5) }
    local a = order(N.RoutePlan(places, MAP, SQUARE, at(0.1, 0.1)))
    local b = order(N.RoutePlan(places, MAP, SQUARE, at(0.1, 0.1)))
    t.eq(a, b)
    t.eq(#a, 5)
    local seen = {}
    for i = 1, #a do seen[a[i]] = true end
    for i = 1, 5 do t.ok(seen[i], "each place once") end
end

tests["route: no route is longer than the list in the order it was handed in"] = function(t)
    local places = { at(0.9, 0.1), at(0.1, 0.9), at(0.9, 0.9), at(0.1, 0.2), at(0.5, 0.5), at(0.3, 0.7) }
    local from = at(0.1, 0.1)
    local route = N.RoutePlan(places, MAP, SQUARE, from)
    local asGiven, last = 0, from
    for i = 1, #places do
        local dx, dy = (places[i].x - last.x) * 1000, (places[i].y - last.y) * 1000
        asGiven = asGiven + math.sqrt(dx * dx + dy * dy)
        last = places[i]
    end
    t.ok(route.total <= asGiven + 1e-6, "not longer than doing nothing")
    local sum = 0
    for i = 1, #route.stops do sum = sum + route.stops[i].leg end
    t.ok(near(sum, route.total), "the total is the legs")
end

-- Lead section 547 (slice 7 data): each stop says why it is where it is.
tests["route why: the nearest next, then the last one left"] = function(t)
    local route = N.RoutePlan({ at(0.3, 0.5), at(0.1, 0.5) }, MAP, SQUARE, at(0, 0.5))
    t.eq(route.stops[1].index, 2)
    t.eq(route.stops[1].why, "nearest")
    t.eq(route.stops[2].why, "nearest")
end

tests["route why: no start known, the first stop is the start"] = function(t)
    local route = N.RoutePlan({ at(0.1, 0.5), at(0.3, 0.5) }, MAP, SQUARE)
    t.eq(route.stops[1].why, "start")
    t.eq(route.stops[2].why, "nearest")
end

tests["route why: a nearer stop that must wait says after"] = function(t)
    -- place 1 is nearer but must come after place 2
    local route = N.RoutePlan({ at(0.1, 0.5), at(0.5, 0.5) }, MAP, SQUARE, at(0, 0.5), nil, { [1] = { 2 } })
    t.eq(route.stops[1].index, 2)
    t.eq(route.stops[1].why, "after")
    t.eq(#route.stops[1].after, 1)
    t.eq(route.stops[1].after[1], 1)
    t.eq(route.stops[2].why, "nearest")
end

tests["route why: an optional stop on the way says its extra yards"] = function(t)
    local route = N.RoutePlan({ at(0.1, 0.5), at(0.5, 0.5), at(0.3, 0.51) }, MAP, SQUARE, at(0, 0.5),
        nil, nil, { [3] = true })
    t.eq(route.stops[2].index, 3)
    t.eq(route.stops[2].why, "onTheWay")
    t.ok(near(route.stops[2].extra, 2 * math.sqrt(200 * 200 + 10 * 10) - 400), "extra yards")
    t.eq(route.stops[1].extra, nil)
end

tests["route why: every reason has its words"] = function(t)
    for _, key in ipairs({ "onTheWay", "start", "nearest", "after", "shorter" }) do
        t.eq(type(N.ROUTE_WHY[key]), "string", key)
    end
end

return tests
