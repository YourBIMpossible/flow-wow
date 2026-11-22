local _, ns = ...
-- S31 (LEDGER 143): flight masters on the world map, the pure parts.
-- Ported from legacy Flow's test "click: flight masters on the map: pick one
-- for where you can fly, another for the flight" (Modules/Tests.lua) and
-- Modules/Nav/MapFlights.lua's pure functions. The pins, lines and button
-- frames are not ported here (needs the client; the world-map button area is
-- Twin's UI/WindowButtons.lua).
local N = ns.Nav

local T = {}

T["one pick; the next click on any flight master clears it"] = function(t)
    local MF = N.MapFlights
    local sel = MF.Click({}, "Crossroads, The Barrens")
    t.eq(sel.from, "Crossroads, The Barrens", "the first click picks where you would fly from")
    t.eq(MF.Click(sel, "Camp Taurajo, The Barrens").from, nil, "a click on another: nothing picked")
    t.eq(MF.Click(sel, "Crossroads, The Barrens").from, nil, "the same one again: nothing picked")
    t.eq(MF.Click(nil, nil), {}, "no name: no pick")
end

T["can you fly it, and what the flight says"] = function(t)
    local MF = N.MapFlights
    local have1 = { name = "Crossroads, The Barrens", kind = "have", cont = 1 }
    local have2 = { name = "Camp Taurajo, The Barrens", kind = "have", cont = 1 }
    local new = { name = "Bragok", npc = "Bragok", kind = "new", cont = 1 }
    local away = { name = "Undercity, Tirisfal", kind = "have", cont = 0 }
    t.ok(MF.CanFly(have1, have2), "both paths yours: you can fly it")
    t.ok(not MF.CanFly(have1, new), "one not learned: not yet")
    t.ok(not MF.CanFly(have1, away), "across the sea: no flight")
    local fmt = function(s) return s .. " s" end
    local text, can = MF.FlightText(have1, have2, 78, nil, fmt)
    t.eq({ text, can }, { "Crossroads to Camp Taurajo: 78 s (your last flight)", true }, "flown before: its time")
    t.eq(MF.FlightText(have1, have2, nil, 80, fmt), "Crossroads to Camp Taurajo: about 80 s", "never flown: the estimate, labelled")
    t.eq(MF.FlightText(have1, have2, nil, nil, fmt), "Crossroads to Camp Taurajo: flight time not known yet", "unknown says so")
    text, can = MF.FlightText(have1, new, nil, nil, fmt)
    t.ok(not can and text:find("learn the flight path at Bragok", 1, true) ~= nil, "not yet: where to learn it")
    t.eq(MF.FlightText(have1, away), "Crossroads to Undercity: not on one continent", "another continent")
    t.eq(MF.Short("Crossroads, The Barrens"), "Crossroads", "short names")
end

T["pins: your paths, masters to learn, your next step's flight on top"] = function(t)
    local MF = N.MapFlights
    local known = { ["Crossroads"] = { cont = 1, wx = 0, wy = 0 }, ["Camp Taurajo"] = { cont = 1, wx = 2000, wy = 0 } }
    local masters = {
        { name = "Devrak", map = 10, x = 0.5, y = 0.5, cont = 1, wx = 20, wy = 0 },     -- by Crossroads: its master
        { name = "Bragok", map = 11, x = 0.3, y = 0.6, cont = 1, wx = 0, wy = 1500 },   -- a path to learn
        { name = "Bragok", map = 11, x = 0.3, y = 0.6, cont = 1, wx = 0, wy = 1500 },   -- the same one twice
        { name = "Talked", map = 12, x = 0.1, y = 0.1, cont = 1, wx = 900, wy = 900 },  -- you talked to them
        { name = "NoPlace", cont = 1 },                                                -- no place: not drawn
    }
    local learned = function(fm) return fm.name == "Talked" end
    local pins = MF.Pins(known, masters, learned, { Bragok = true }, { from = "Crossroads", to = "Camp Taurajo" })
    local names = {}
    for i, p in ipairs(pins) do names[i] = p.name .. ":" .. p.kind .. ":" .. tostring(p.role) end
    t.eq(names, { "Bragok:new:nil", "Camp Taurajo:have:to", "Crossroads:have:from" }, "new first, the flight's two last")
    t.eq(pins[3].npc, "Devrak", "a path you have names its master, when one stands by it")
    t.eq(pins[1].onRoute, true, "a master to learn on your route says so")
end

T["F-086: unknown places are not drawn and not guessed"] = function(t)
    local MF = N.MapFlights
    local pins = MF.Pins({ ["Lost"] = { cont = 1 } }, { { name = "NoPlace", cont = 1 } })
    t.eq(#pins, 0, "a path or master with no place gives no pin")
    t.eq(MF.Pins(nil, nil), {}, "nothing known: no pins")
end

T["tooltips and the role labels"] = function(t)
    local MF = N.MapFlights
    local title, lines = MF.TipLines({ name = "Crossroads", kind = "have", npc = "Devrak", role = "from" }, nil, "4 min")
    t.eq(title, "Crossroads")
    t.eq(lines, { "Flight master: Devrak", "You have this flight path: you can fly here.",
        "Fly from here: your next step is quicker by air, 4 min in all." })
    local _, newLines = MF.TipLines({ name = "Bragok", kind = "new", onRoute = true })
    t.eq(#newLines, 2, "a master to learn: what to do, and that it is on your route")
    t.eq(MF.RoleLabel("from"), "Fly from here")
    t.eq(MF.RoleLabel("to"), "Land here: next step")
    t.eq(MF.RoleLabel(nil), nil)
end

T["the line under the mouse"] = function(t)
    local MF = N.MapFlights
    t.eq(MF.SegDist(5, 5, 0, 0, 10, 0), 5, "straight above the middle")
    t.eq(MF.SegDist(-3, 4, 0, 0, 10, 0), 5, "past an end: to the end")
    local lines = { { name = "a", ax = 0, ay = 0, bx = 100, by = 0 }, { name = "b", ax = 0, ay = 10, bx = 100, by = 10 } }
    t.eq(MF.LineAt(lines, 50, 3, 14), "a", "the nearer line")
    t.eq(MF.LineAt(lines, 50, 60, 14), nil, "too far from both: none")
end

T["is the waypoint the one a right click set?"] = function(t)
    local MF = N.MapFlights
    local pin = { name = "Bragok", npc = "Bragok", map = 11, x = 0.3, y = 0.6 }
    t.ok(MF.WaypointOn({ note = "Bragok (flight master)" }, pin), "by its note")
    t.ok(MF.WaypointOn({ map = 11, x = 0.301, y = 0.6 }, pin, { map = 11, x = 0.3, y = 0.6 }), "by its spot")
    t.ok(not MF.WaypointOn({ map = 11, x = 0.4, y = 0.6 }, pin, { map = 11, x = 0.3, y = 0.6 }), "another spot: no")
    t.ok(not MF.WaypointOn(nil, pin), "no waypoint: no")
end

T["the setting and constants Flow used"] = function(t)
    t.eq(N.MapFlights.SETTING, "nav.mapFlights")
    t.eq(N.MapFlights.SAME, 250)
    t.eq(N.MapFlights.LINE_REACH, 14)
end

return T
