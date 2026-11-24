local _, ns = ...

-- Tests for P-TRIP slice 2: the route the arrow walks, shown in the quest
-- arrow's tooltip (Nav/Trip.lua P.TipLines, UI/ArrowMenu.lua M.Tip). Pure
-- parts only; made-up places.

local tests = {}

local function P() return ns.Nav.Trip end

local HERE = { map = 1, x = 0.5, y = 0.5, size = { w = 1000, h = 1000 } }

local function st(label, map, x, y)
    return { label = label, place = { map = map, x = x, y = y } }
end

tests["trip tip: the current stop is marked and the distance left is added up"] = function(t)
    local cur = { kind = "run", label = "Trip", stops = { st("Near", 1, 0.6, 0.5), st("Far", 1, 0.9, 0.5) } }
    local lines = P().TipLines(cur, HERE)
    t.eq(lines[1], P().TIP_HEADER:format(2, "400 yd"))
    t.eq(lines[2], P().TIP_NOW .. "Near - 100 yd")
    t.eq(lines[3], P().TIP_NEXT .. "Far - 300 yd")
    t.eq(#lines, 3)
end

tests["trip tip: a stop on another map leaves the total not known"] = function(t)
    local cur = { stops = { st("Near", 1, 0.6, 0.5), st("Away", 2, 0.5, 0.5) } }
    local lines = P().TipLines(cur, HERE)
    t.eq(lines[1], P().TIP_HEADER:format(2, P().NO_DISTANCE))
    t.eq(lines[3], P().TIP_NEXT .. "Away - " .. P().OTHER_MAP)
end

tests["trip tip: long routes are cut with a count"] = function(t)
    local stops = {}
    for i = 1, P().TIP_MAX + 3 do stops[i] = st("S" .. i, 1, 0.5, 0.5 + i / 100) end
    local lines = P().TipLines({ stops = stops }, HERE)
    t.eq(#lines, P().TIP_MAX + 2)
    t.eq(lines[#lines], P().TIP_MORE:format(3))
end

tests["trip tip: no route, no lines"] = function(t)
    t.eq(P().TipLines(nil, HERE), nil)
    t.eq(P().TipLines({ stops = {} }, HERE), nil)
end

tests["trip tip: the quest arrow's tooltip carries the route before how to use it"] = function(t)
    local M = ns.ArrowMenu
    local out = M.Tip({ key = "quest", lines = { quest = { "Inn: Inna" } }, route = { "Route: 1", "> Inn" } })
    t.eq(out[2], "Inn: Inna")
    t.eq(out[3], "Route: 1")
    t.eq(out[4], "> Inn")
    t.ok(out[5]:find("Right-click", 1, true) ~= nil, tostring(out[5]))
    local prof = M.Tip({ key = "prof", lines = { prof = { "Train" } }, route = { "Route: 1" } })
    for _, line in ipairs(prof) do t.ok(line ~= "Route: 1", "not on the profession arrow") end
end

return tests
