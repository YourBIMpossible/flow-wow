local _, ns = ...
-- Bearing tests: direction and distance between two { cont, zone, x, y }
-- places, and unknown where the places cannot be related.
local N = ns.Nav

local PI = math.pi
local function near(t, got, want, msg)
    t.ok(type(got) == "number" and math.abs(got - want) < 1e-9, msg .. " (got " .. tostring(got) .. ")")
end
local function place(zone, x, y, cont)
    return { cont = cont or 1, zone = zone, x = x, y = y }
end

local T = {}

T["same zone: the four compass directions and a diagonal"] = function(t)
    local here = place(10, 100, 100)
    local cases = {
        { "north", place(10, 100, 50), 0, 50 },
        { "east", place(10, 130, 100), PI / 2, 30 },
        { "south", place(10, 100, 170), PI, 70 },
        { "west", place(10, 60, 100), 3 * PI / 2, 40 },
        { "north-east", place(10, 103, 97), PI / 4, math.sqrt(18) },
        { "north-west", place(10, 97, 97), 7 * PI / 4, math.sqrt(18) },
    }
    for _, c in ipairs(cases) do
        local b = N.Bearing(here, c[2])
        t.eq(b.known, true, c[1] .. ": known")
        near(t, b.bearing, c[3], c[1] .. ": bearing")
        near(t, b.distance, c[4], c[1] .. ": distance")
        t.ok(b.bearing >= 0 and b.bearing < 2 * PI, c[1] .. ": in [0, 2pi)")
    end
    local b = N.Bearing(here, place(10, 103, 104))
    near(t, b.distance, 5, "3-4-5 distance")
    near(t, b.east, 3, "east offset"); near(t, b.south, 4, "south offset")
end

T["same spot: distance 0 and no bearing"] = function(t)
    local b = N.Bearing(place(10, 5, 5), place(10, 5, 5))
    t.eq(b.known, true, "known")
    t.eq(b.distance, 0, "distance 0")
    t.eq(b.bearing, nil, "no bearing")
end

T["zones differ and no link: unknown, with no numbers"] = function(t)
    local b = N.Bearing(place(10, 5, 5), place(11, 9, 9))
    t.eq(b.known, false, "unknown")
    t.eq(b.reason, "zone", "reason")
    t.eq(b.distance, nil, "no distance"); t.eq(b.bearing, nil, "no bearing")
    -- A zone that is not known is not assumed to be the same zone.
    local c = N.Bearing({ cont = 1, x = 5, y = 5 }, place(11, 9, 9))
    t.eq(c.known, false, "unknown zone: unknown"); t.eq(c.reason, "zone", "reason")
    local d = N.Bearing({ cont = 1, x = 5, y = 5 }, { cont = 1, x = 9, y = 9 })
    t.eq(d.known, false, "both zones unknown: unknown")
end

T["zones differ with a link: related through the zones' origins"] = function(t)
    local link = { [10] = { x = 0, y = 0 }, [11] = { x = 1000, y = 0 } }
    -- Zone 11 lies 1000 yd east of zone 10. 100 in zone 10 to 50 in zone 11: 950 east.
    local b = N.Bearing(place(10, 100, 20), place(11, 50, 20), link)
    t.eq(b.known, true, "known")
    near(t, b.distance, 950, "distance")
    near(t, b.bearing, PI / 2, "due east")
    -- And back: due west, same distance.
    local back = N.Bearing(place(11, 50, 20), place(10, 100, 20), link)
    near(t, back.distance, 950, "distance back"); near(t, back.bearing, 3 * PI / 2, "due west")
    -- The link does not cover one of the zones: unknown.
    local miss = N.Bearing(place(10, 100, 20), place(12, 50, 20), link)
    t.eq(miss.known, false, "zone not in the link"); t.eq(miss.reason, "zone", "reason")
    -- A link entry that cannot be used is no link.
    local bad = N.Bearing(place(10, 1, 1), place(11, 2, 2), { [10] = { x = 0, y = 0 }, [11] = { x = "a" } })
    t.eq(bad.known, false, "bad link entry")
    -- The same zone ignores the link.
    local same = N.Bearing(place(11, 0, 0), place(11, 0, 10), link)
    near(t, same.distance, 10, "same zone, link ignored"); near(t, same.bearing, PI, "south")
end

T["continents differ: unknown even with a link"] = function(t)
    local link = { [10] = { x = 0, y = 0 }, [20] = { x = 50, y = 50 } }
    local b = N.Bearing(place(10, 1, 1, 1), place(20, 2, 2, 2), link)
    t.eq(b.known, false, "unknown"); t.eq(b.reason, "continent", "reason")
    t.eq(b.distance, nil, "no distance")
    -- A continent that is not known does not block a same-zone answer.
    local c = N.Bearing({ zone = 10, x = 0, y = 0 }, place(10, 0, 10, 1))
    t.eq(c.known, true, "continent unknown, same zone: known")
end

T["unusable places: unknown, never an error"] = function(t)
    local good = place(10, 1, 1)
    local nan = 0 / 0
    local bads = { false, "x", {}, { zone = 10, x = 1 }, { zone = 10, x = "1", y = 2 },
                   { zone = 10, x = nan, y = 2 }, { zone = 10, x = math.huge, y = 2 } }
    for i, bad in ipairs(bads) do
        local a = N.Bearing(bad or nil, good)
        t.eq(a.known, false, "bad from " .. i); t.eq(a.reason, "place", "reason " .. i)
        local b = N.Bearing(good, bad or nil)
        t.eq(b.known, false, "bad to " .. i)
    end
    t.eq(N.Bearing(nil, nil).known, false, "nothing at all")
end

T["the places and the link are not changed"] = function(t)
    local a, b = place(10, 1, 2), place(11, 3, 4)
    local link = { [10] = { x = 5, y = 6 }, [11] = { x = 7, y = 8 } }
    N.Bearing(a, b, link)
    t.eq(a, place(10, 1, 2), "from untouched"); t.eq(b, place(11, 3, 4), "to untouched")
    t.eq(link, { [10] = { x = 5, y = 6 }, [11] = { x = 7, y = 8 } }, "link untouched")
end

T["arrow turn: -(bearing + facing), wrapped; unknown stays unknown"] = function(t)
    near(t, N.ArrowTurn(0, 0), 0, "facing north, target north: straight up")
    -- Target due east, facing north: a quarter turn clockwise.
    near(t, N.ArrowTurn(PI / 2, 0), -PI / 2, "target east")
    -- Facing east (client facing 3pi/2 anticlockwise from north), target east: straight up.
    near(t, N.ArrowTurn(PI / 2, 3 * PI / 2), 0, "facing the target")
    -- Target behind.
    near(t, N.ArrowTurn(PI, 0), PI, "target behind")
    -- Facing west (pi/2), target north: a quarter turn clockwise.
    near(t, N.ArrowTurn(0, PI / 2), -PI / 2, "facing west, target north")
    for _, pair in ipairs({ { 6, 6 }, { 0.1, 6.2 }, { 5, 0 }, { 3, 3.2 } }) do
        local turn = N.ArrowTurn(pair[1], pair[2])
        t.ok(turn > -PI - 1e-12 and turn <= PI + 1e-12, "wrapped into (-pi, pi]")
    end
    t.eq(N.ArrowTurn(nil, 1), nil, "bearing unknown")
    t.eq(N.ArrowTurn(1, nil), nil, "facing unknown")
    t.eq(N.ArrowTurn(0 / 0, 1), nil, "not a number")
end

return T
