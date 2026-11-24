local _, ns = ...

-- Tests for G43 (P-TRIP): the route tracker window's parts (UI/RouteTracker.lua
-- RT.Children) and the rows it is given (Nav/Trip.lua P.TrackRows). Pure
-- parts only; made-up places.

local tests = {}

local function RT() return ns.RouteTracker end
local function P() return ns.Nav.Trip end

local HERE = { map = 1, x = 0.5, y = 0.5, size = { w = 1000, h = 1000 } }

local function current()
    return { kind = "run", label = "Trip", stops = {
        { label = "Inn", detail = "Inna", place = { map = 1, x = 0.5, y = 0.6 } },
        { label = "Vendor", place = { map = 1, x = 0.8, y = 0.6 } },
        { label = "Mail", place = { map = 2, x = 0.5, y = 0.5 } },
    } }
end

local function byKey(children, key)
    for _, part in ipairs(children) do
        if part.key == key then return part end
        for _, kid in ipairs(part.children or {}) do
            if kid.key == key then return kid end
        end
    end
    return nil
end

tests["track rows: each stop with its distance from the one before"] = function(t)
    local rows = P().TrackRows(current(), HERE)
    t.eq(#rows, 3)
    t.eq(rows[1], { label = "Inn", detail = "Inna", dist = "100 yd" })
    t.eq(rows[2], { label = "Vendor", dist = "300 yd" })
    t.eq(rows[3], { label = "Mail", dist = P().OTHER_MAP })
    t.eq(P().TrackRows(nil, HERE), nil)
end

tests["tracker parts: the current stop is marked, the rest follow with distances"] = function(t)
    local kids = RT().Children(P().TrackRows(current(), HERE))
    t.eq(kids[1].kind, "header")
    local now = byKey(kids, "current")
    t.eq(now and now.text, "Inn")
    t.eq(now and now.tone, RT().TONE_NOW)
    t.eq(now and now.right, "100 yd")
    t.eq(now and now.sub, "Inna")
    local nextOne = byKey(kids, "next1")
    t.eq(nextOne and nextOne.text, "Vendor")
    t.eq(nextOne and nextOne.tone, nil)
    t.ok(byKey(kids, "footer") ~= nil, "a footer with the skip button")
    t.ok(ns.Kit.Window({ id = RT().ID, title = "x", children = kids }) ~= nil, "the kit takes the parts")
end

tests["tracker parts: no route is the empty state"] = function(t)
    local kids = RT().Children(nil)
    local e = byKey(kids, "empty")
    t.eq(e and e.kind, "empty")
    t.eq(e and e.text, RT().EMPTY[1])
    t.eq(e and e.how, RT().EMPTY[2])
    t.eq(byKey(kids, "current"), nil)
    t.ok(ns.Kit.Window({ id = RT().ID, title = "x", children = kids }) ~= nil, "the kit takes the parts")
end

tests["tracker parts: no more than RT.MAX stops are listed"] = function(t)
    local rows = {}
    for i = 1, RT().MAX + 3 do rows[i] = { label = "S" .. i, dist = "1 yd" } end
    local kids = RT().Children(rows)
    t.ok(byKey(kids, "next" .. (RT().MAX - 1)) ~= nil, "the last shown")
    t.eq(byKey(kids, "next" .. RT().MAX), nil)
    t.ok(byKey(kids, "more") ~= nil, "says how many more")
end

return tests
