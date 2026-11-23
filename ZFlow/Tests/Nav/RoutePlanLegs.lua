-- Tests for the fifth argument of N.RoutePlan (S34, lead section 169 A):
-- the player's own trip times, legs(a, b, d) -> yards, how. Every existing
-- RoutePlan test stays as it was (RoutePlanTests.lua): without legs the
-- planner is unchanged. Made-up places and times, test only.
-- Not tested in game.
local _, ns = ...

local N = ns.Nav
local tests = {}

local MAP = 1411
local SQUARE = { w = 1000, h = 1000 }

local function near(a, b)
    return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-6
end

local function at(x, y) return { map = MAP, x = x, y = y } end

local function order(route)
    local out = {}
    for i = 1, #route.stops do out[i] = route.stops[i].index end
    return out
end

-- A key for a leg from yards a to yards b, rounded to whole yards.
local function key(a, b)
    return ("%d,%d>%d,%d"):format(math.floor(a.x + 0.5), math.floor(a.y + 0.5),
        math.floor(b.x + 0.5), math.floor(b.y + 0.5))
end

-- legs from a table { [key] = { yards, how } }; asked counts each key.
local function legsOf(known)
    local asked = {}
    local function legs(a, b, d)
        local k = key(a, b)
        asked[k] = (asked[k] or 0) + 1
        local e = known[k]
        if not e then return nil end
        return e[1], e[2]
    end
    return legs, asked
end

-- The start S (125, 500), A (250, 500) and B (375, 500), in yards.
local S, A, B = at(0.125, 0.5), at(0.25, 0.5), at(0.375, 0.5)
local SY, AY, BY = { x = 125, y = 500 }, { x = 250, y = 500 }, { x = 375, y = 500 }

tests["route legs: the words for a route measured by the player's trips"] = function(t)
    t.eq(N.ROUTE_LEARNED, "your own trip times where known, straight lines elsewhere")
    t.eq(N.ROUTE_STRAIGHT, "straight lines, not paths")
end

tests["route legs: legs that know nothing give the same route as none"] = function(t)
    local places = { at(0.875, 0.5), at(0.25, 0.5), at(0.625, 0.5) }
    local plain = N.RoutePlan(places, MAP, SQUARE, S)
    local legs = legsOf({})
    local route = N.RoutePlan(places, MAP, SQUARE, S, legs)
    t.eq(order(route), order(plain))
    t.eq(route.straight, true)
    t.eq(route.label, N.ROUTE_STRAIGHT)
    for i = 1, #route.stops do
        t.ok(near(route.stops[i].leg, plain.stops[i].leg), "leg " .. i)
        t.eq(route.stops[i].how, nil)
    end
    t.ok(near(route.total, plain.total))
end

tests["route legs: a trip known to be long changes the order"] = function(t)
    -- A river between S and A: 2000 yards as the player went; S to B 300.
    local legs = legsOf({ [key(SY, AY)] = { 2000, "exact" }, [key(SY, BY)] = { 300, "exact" } })
    local route = N.RoutePlan({ A, B }, MAP, SQUARE, S, legs)
    t.eq(order(route), { 2, 1 }, "B first, then A")
    t.ok(near(route.stops[1].leg, 300))
    t.eq(route.stops[1].how, "exact")
    t.ok(near(route.stops[2].leg, 125), "B to A: no trip known, the straight line")
    t.eq(route.stops[2].how, nil)
    t.ok(near(route.total, 425))
    t.eq(route.straight, false)
    t.eq(route.label, N.ROUTE_LEARNED)
    local plain = N.RoutePlan({ A, B }, MAP, SQUARE, S)
    t.eq(order(plain), { 1, 2 }, "by the straight line A is first")
end

tests["route legs: an exact trip is taken as it is, quicker than the line too"] = function(t)
    local legs = legsOf({ [key(SY, AY)] = { 50, "exact" } })
    local route = N.RoutePlan({ A }, MAP, SQUARE, S, legs)
    t.ok(near(route.stops[1].leg, 50), "a flight")
    t.eq(route.stops[1].how, "exact")
end

tests["route legs: an area answer only stretches the line"] = function(t)
    local route = N.RoutePlan({ A }, MAP, SQUARE, S, (legsOf({ [key(SY, AY)] = { 300, "area" } })))
    t.ok(near(route.stops[1].leg, 300))
    t.eq(route.stops[1].how, "area")
    route = N.RoutePlan({ A }, MAP, SQUARE, S, (legsOf({ [key(SY, AY)] = { 60, "area" } })))
    t.ok(near(route.stops[1].leg, 125), "never shorter than the straight line")
    t.eq(route.stops[1].how, "area")
end

tests["route legs: an answer that is no measure is the straight line"] = function(t)
    for _, e in ipairs({ { 300, "guess" }, { 300 }, { 0, "exact" }, { -5, "exact" },
                         { 0 / 0, "exact" }, { math.huge, "exact" }, { "300", "exact" } }) do
        local route = N.RoutePlan({ A }, MAP, SQUARE, S, (legsOf({ [key(SY, AY)] = e })))
        t.ok(near(route.stops[1].leg, 125), tostring(e[1]) .. " " .. tostring(e[2]))
        t.eq(route.stops[1].how, nil)
        t.eq(route.straight, true)
    end
end

tests["route legs: legs that raise give the straight line, and no error"] = function(t)
    local route, why = N.RoutePlan({ A, B }, MAP, SQUARE, S, function() error("broken") end)
    t.eq(why, nil)
    t.eq(order(route), { 1, 2 })
    t.ok(near(route.total, 250))
    t.eq(route.straight, true)
end

tests["route legs: asked with yards on the map and the straight distance, once a pair"] = function(t)
    local seen = {}
    local function legs(a, b, d)
        seen[#seen + 1] = { a = { x = a.x, y = a.y }, b = { x = b.x, y = b.y }, d = d }
        return nil
    end
    N.RoutePlan({ A }, MAP, SQUARE, S, legs)
    t.eq(#seen, 1)
    t.eq(seen[1].a, SY)
    t.eq(seen[1].b, AY)
    t.ok(near(seen[1].d, 125))

    local counted, asked = legsOf({})
    N.RoutePlan({ at(0.875, 0.5), at(0.25, 0.5), at(0.625, 0.5), at(0.5, 0.25) }, MAP, SQUARE, S, counted)
    for k, n in pairs(asked) do t.eq(n, 1, k) end
end

tests["route legs: each way is asked for itself"] = function(t)
    -- From A to B is known; B to A is not. Start not known: the first place
    -- of the list starts the route.
    local legs, asked = legsOf({ [key(AY, BY)] = { 900, "exact" } })
    local route = N.RoutePlan({ A, B }, MAP, SQUARE, nil, legs)
    t.eq(order(route), { 2, 1 }, "B to A by the line (125) beats A to B as travelled (900)")
    t.eq(route.stops[1].leg, nil)
    t.ok(near(route.stops[2].leg, 125))
    t.eq(route.straight, true, "the leg used was not measured")
    t.ok(asked[key(AY, BY)] == 1 and asked[key(BY, AY)] == 1)
end

tests["route legs: not a function is no legs"] = function(t)
    local route = N.RoutePlan({ A }, MAP, SQUARE, S, { 1, 2 })
    t.ok(near(route.stops[1].leg, 125))
    t.eq(route.straight, true)
end

return tests
