local _, ns = ...

-- N43 (P-TRIP route display): the whole route on the world map. Every stop
-- still to walk on the shown map is a pin, numbered in route order, the
-- current one in the route's own role (as before) and the rest in the
-- "next" role; lines join stops that follow each other on that map. Pure
-- part (RT.Pins); made-up places. Not tested in game.

local tests = {}

local function RT() return ns.RouteTracker end

local function current()
    return { kind = "run", label = "Trip", stops = {
        { label = "Inn", place = { map = 1, x = 0.5, y = 0.6 } },
        { label = "Vendor", place = { map = 1, x = 0.8, y = 0.6 } },
        { label = "Mail", place = { map = 2, x = 0.5, y = 0.5 } },
        { label = "Bank", place = { map = 1, x = 0.2, y = 0.2 } },
    } }
end

tests["route map: each stop on the shown map is a pin, in order, the current one distinct"] = function(t)
    local pins, lines = RT().Pins(current(), 1)
    t.eq(#pins, 3, "the stop on another map is left out")
    t.eq(pins[1], { name = "Inn", kind = RT().PIN_KIND, role = RT().PIN_ROLE, order = 1, x = 0.5, y = 0.6 })
    t.eq(pins[2], { name = "2. Vendor", kind = RT().PIN_NEXT_KIND, role = RT().PIN_NEXT_ROLE, order = 2,
                    x = 0.8, y = 0.6 })
    t.eq(pins[3].order, 4, "numbered by its place in the route")
    t.eq(pins[3].name, "4. Bank")
    t.ok(RT().PIN_NEXT_ROLE ~= RT().PIN_ROLE, "the current one looks different")
    t.eq(#lines, 1, "only stops that follow each other on this map are joined")
    t.eq(lines[1], { from = 1, to = 2, ax = 0.5, ay = 0.6, bx = 0.8, by = 0.6 })
end

tests["route map: the current stop on another map leaves only the rest"] = function(t)
    local pins = RT().Pins(current(), 2)
    t.eq(#pins, 1)
    t.eq(pins[1].name, "3. Mail")
    t.eq(pins[1].role, RT().PIN_NEXT_ROLE)
end

tests["route map: no route or no map draws nothing"] = function(t)
    local pins, lines = RT().Pins(nil, 1)
    t.eq(pins, {})
    t.eq(lines, {})
    pins = RT().Pins(current(), nil)
    t.eq(pins, {})
end

tests["route map: with the whole route off, only the current stop"] = function(t)
    local pins, lines = RT().Pins(current(), 1, true)
    t.eq(#pins, 1)
    t.eq(pins[1].name, "Inn")
    t.eq(lines, {})
end

return tests
