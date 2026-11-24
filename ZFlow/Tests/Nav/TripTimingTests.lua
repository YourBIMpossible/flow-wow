local _, ns = ...

-- Tests for trip timing (S34, lead dispatch section 395 item 2): each route
-- leg's seconds (its yards at a run, N.Legs.RUN; a leg the player timed,
-- flight or boat wait included, already comes in those yards from
-- N.Legs.YardsOf) and the time said on the step. Pure parts; made-up places.

local tests = {}

local function T() return ns.Nav.TripRoute end

local HERE = { map = 1, x = 0.5, y = 0.5, size = { w = 1000, h = 1000 } }

local function row(id, title)
    return { id = id, title = title, complete = false, failed = false,
             objectives = { { text = title .. ": 0/1", done = false } } }
end

local function at(x)
    return { objectives = { [1] = { points = { { map = 1, x = x, y = 0.5 } } } } }
end

tests["trip timing: seconds are run yards over the run speed"] = function(t)
    t.eq(T().Seconds(70), 70 / ns.Nav.Legs.RUN)
    t.eq(T().Seconds(nil), nil, "no leg, no seconds")
    t.eq(T().Seconds(0 / 0), nil, "not a number, no seconds")
    t.eq(T().Seconds(-5), nil, "below nothing, no seconds")
end

tests["trip timing: the words for a leg's time"] = function(t)
    t.eq(T().TimeWords(20), "under a minute")
    t.eq(T().TimeWords(65), "about 1 minute")
    t.eq(T().TimeWords(120), "about 2 minutes")
    t.eq(T().TimeWords(150), "about 3 minutes", "rounded to the nearest minute")
    t.eq(T().TimeWords(nil), nil, "unknown says nothing")
    t.eq(T().TimeWords(1 / 0), nil, "endless says nothing")
end

tests["trip timing: a leg the player timed slow loses to a longer quick one"] = function(t)
    local rows = { row(1, "Near"), row(2, "Far") }
    local places = { [1] = at(0.55), [2] = at(0.3) }
    -- From the start (500, 500) to Near (550, 500): 50 yards straight, but
    -- the player's own trip took 200 seconds (a cliff): 1400 run yards.
    local function legs(a, b)
        local xs = { math.floor(a.x + 0.5), math.floor(b.x + 0.5) }
        table.sort(xs)
        if xs[1] == 500 and xs[2] == 550 then return 1400, "exact" end
        return nil
    end
    local plain = T().Plan(rows, places, HERE)
    t.eq(plain and plain.stops[1].label, "Near", "without timed legs the nearest comes first")
    local route, why = T().Plan(rows, places, HERE, legs)
    t.ok(route ~= nil, tostring(why))
    local order = {}
    for i, s in ipairs(route and route.stops or {}) do order[i] = s.label end
    t.eq(order, { "Far", "Near" }, "the quicker leg wins")
    t.eq(route and math.floor(route.stops[1].secs + 0.5), math.floor(200 / ns.Nav.Legs.RUN + 0.5))
    t.ok(route and T().Lines(route, 1)[2]:find("under a minute", 1, true) ~= nil, tostring(route and T().Lines(route, 1)[2]))
end

tests["trip timing: the step line says the time after the yards"] = function(t)
    local route = { kind = "quests", yards = true, label = "x",
                    stops = { { label = "Boars", leg = 840, secs = 120 } } }
    t.eq(T().Lines(route, 1)[2], "> 1. Boars - 840 yd - about 2 minutes")
end

tests["trip timing: an unknown map size says no time"] = function(t)
    local here = { map = 1, x = 0.5, y = 0.5 }
    local route = T().Plan({ row(1, "Boars") }, { [1] = at(0.6) }, here)
    t.ok(route ~= nil, "planned")
    t.eq(route and route.stops[1].secs, nil)
    local line = route and T().Lines(route, 1)[2] or ""
    t.ok(line:find("minute", 1, true) == nil, line)
    t.ok(line:find(T().NO_DISTANCE, 1, true) ~= nil, line)
end

return tests
