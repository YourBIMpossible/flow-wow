-- Tests for the optional stops of ZFlow/Nav/RoutePlan.lua (lead section 375
-- item 6, TN-2): an optional place stays on the route only when it is on
-- the way (at most N.DETOUR extra yards at its cheapest place), else it is
-- left out, said so. Made-up places, test only. Not tested in game.
local _, ns = ...

local N = ns.Nav
local tests = {}

local MAP = 1411
local SQUARE = { w = 1000, h = 1000 }
local FROM = { map = MAP, x = 0, y = 0.5 }

local function at(x, y)
    return { map = MAP, x = x, y = y }
end

local function order(route)
    local out = {}
    for i = 1, #route.stops do out[i] = route.stops[i].index end
    return out
end

local function leftOf(route, index)
    for _, l in ipairs(route.left) do
        if l.index == index then return l end
    end
    return nil
end

tests["route optional: the detour allowed is 250 yards, by name"] = function(t)
    t.eq(N.DETOUR, 250)
    t.eq(N.OFF_THE_WAY, "off the way")
end

tests["route optional: a place on the way is kept, between its neighbours"] = function(t)
    local places = { at(0.2, 0.5), at(0.8, 0.5), at(0.5, 0.6) }
    local route = N.RoutePlan(places, MAP, SQUARE, FROM, nil, nil, { [3] = true })
    t.eq(order(route), { 1, 3, 2 })
    t.eq(route.stops[2].optional, true)
    t.eq(route.stops[1].optional, nil)
    t.eq(#route.left, 0)
end

tests["route optional: a place far off the way is left out and says so"] = function(t)
    local places = { at(0.2, 0.5), at(0.8, 0.5), at(0.5, 0.9) }
    local route = N.RoutePlan(places, MAP, SQUARE, FROM, nil, nil, { [3] = true })
    t.eq(order(route), { 1, 2 })
    local l = leftOf(route, 3)
    t.ok(l ~= nil, "in left")
    t.eq(l and l.reason, N.OFF_THE_WAY)
    t.ok(l and math.abs(l.detour - 400) < 1e-6, tostring(l and l.detour))
end

tests["route optional: the cheapest place on the route is chosen"] = function(t)
    -- Past the last stop costs 50 yards; between the two costs 100.
    local places = { at(0.2, 0.5), at(0.8, 0.5), at(0.85, 0.5) }
    local route = N.RoutePlan(places, MAP, SQUARE, FROM, nil, nil, { [3] = true })
    t.eq(order(route), { 1, 2, 3 })
    t.ok(math.abs(route.total - 850) < 1e-6, tostring(route.total))
end

tests["route optional: several optionals, each kept or left on its own"] = function(t)
    local places = { at(0.2, 0.5), at(0.8, 0.5), at(0.5, 0.55), at(0.5, 0.95), at(0.25, 0.5) }
    local route = N.RoutePlan(places, MAP, SQUARE, FROM, nil, nil, { [3] = true, [4] = true, [5] = true })
    t.eq(order(route), { 1, 5, 3, 2 })
    t.eq(#route.left, 1)
    t.eq(route.left[1].index, 4)
end

tests["route optional: none optional is the route as before"] = function(t)
    local places = { at(0.2, 0.5), at(0.8, 0.5), at(0.5, 0.9) }
    local plain = N.RoutePlan(places, MAP, SQUARE, FROM)
    local none = N.RoutePlan(places, MAP, SQUARE, FROM, nil, nil, {})
    t.eq(order(none), order(plain))
    t.eq(#none.left, 0)
end

tests["trip: trip optional <n> marks a stop optional and back"] = function(t)
    local P = N.Trip
    local list = {}
    P.Add(list, { kind = "here", label = "A", place = at(0.2, 0.5) })
    local ok, line = P.Optional(list, 1)
    t.eq(ok, true)
    t.eq(list[1].optional, true)
    t.eq(line, P.OPTIONAL_ON:format(1, "A"))
    ok = P.Optional(list, 1)
    t.eq(ok, true)
    t.eq(list[1].optional, nil)
    local bad, why = P.Optional(list, 9)
    t.eq(bad, false)
    t.eq(why, P.BAD_NUMBER:format("9"))
end

tests["trip: an optional stop off the way is skipped and listed under the route"] = function(t)
    local P = N.Trip
    local here = { map = MAP, x = 0, y = 0.5, size = SQUARE }
    local list = {}
    P.Add(list, { kind = "here", label = "A", place = at(0.2, 0.5) })
    P.Add(list, { kind = "here", label = "B", place = at(0.8, 0.5) })
    P.Add(list, { kind = "here", label = "Far", place = at(0.5, 0.9) })
    P.Add(list, { kind = "here", label = "Near", place = at(0.5, 0.6) })
    P.Optional(list, 3)
    P.Optional(list, 4)
    local ordered, label, skipped = P.Order(list, here)
    t.eq(label, N.ROUTE_STRAIGHT)
    t.eq({ ordered[1].label, ordered[2].label, ordered[3].label }, { "A", "Near", "B" })
    t.eq(#ordered, 3)
    t.eq(#skipped, 1)
    t.eq(skipped[1].label, "Far")
    local run = P.Run(ordered, label, skipped)
    t.eq(#run.steps, 3)
    t.eq(run.left[1].label, "Far")
    t.eq(run.left[1].why, P.SKIPPED)
    t.eq(P.SKIPPED, "skipped: more than 250 yd off the way")
end

return tests
