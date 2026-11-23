-- Tests for ZFlow/Nav/Flights.lua (lead DISPATCH section 182 item 2;
-- RESEARCH-S45.md section 3, RESEARCH-FLIGHTS.md sections 4 and 6): the
-- flight points this character knows, saved from the open flight map, and
-- the module "flights" whose Way(place) Nav/Travel.lua asks for. Fake
-- client, made-up places. Not tested in game. Look only: nothing takes a
-- flight, selects a node or clicks for the player.
local _, ns = ...

local N, A = ns.Nav, ns.Arrow
local F = N.Flights
local T = N.Travel
local tests = {}

-- World yards: map 1411 is 1000 by 500 from (0, 0); map 1420 lies south of
-- it from (0, 5000); 1414 is the flight map, 10000 yards square from (0, 0).
local CORNERS = {
    [1411] = { cont = 1, ox = 0, oy = 0, ex = 1000, ey = 0, sx = 0, sy = 500 },
    [1420] = { cont = 1, ox = 0, oy = 5000, ex = 1000, ey = 5000, sx = 0, sy = 5500 },
    [1414] = { cont = 1, ox = 0, oy = 0, ex = 10000, ey = 0, sx = 0, sy = 10000 },
    [1415] = { cont = 0, ox = 0, oy = 0, ex = 1000, ey = 0, sx = 0, sy = 1000 },
}

-- Razor Hill stands on the player's map (0.6, 0.5); Crossroads by the target.
local function known()
    return {
        ["Razor Hill"] = { cont = 1, wx = 600, wy = 250 },
        ["Crossroads"] = { cont = 1, wx = 400, wy = 5000 },
    }
end

local function target() return { map = 1420, x = 0.4, y = 0.6 } end
local function step() return { label = "Kill wolves", place = target() } end

local function near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-6 end

-- A warrior at the middle of 1411. opts.nodes: the character's saved
-- flight points (nil: none); opts.char: the whole char table; arrow: the
-- arrows run too, with the map pin on 1420.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or { layout = { arrowIntroSeen = true } })
    local char = opts.char or {}
    if opts.nodes then char.learned = { flights = { nodes = opts.nodes } } end
    c.setSaved(ns.id.charDB, char)
    c.setScreen(1024, 768)
    c.setZone(1, 1411)
    c.setFacing(0)
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    c.setClass("WARRIOR")
    c.setFaction("Horde")
    for map, corners in pairs(CORNERS) do c.setMapCorners(map, corners) end
    if opts.arrow then c.setWaypoint(1420, 0.4, 0.6) end
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    if opts.arrow then A.Start(k, d) end
    local api = F.Declare(k, d)
    local travel = opts.travel and T.Declare(k, d) or nil
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api, travel
end

local function savedNodes(c)
    local s = c.saved(ns.id.charDB)
    local learned = type(s) == "table" and s.learned or nil
    local flights = type(learned) == "table" and learned.flights or nil
    return type(flights) == "table" and flights.nodes or nil
end

-- The open flight map 1414: where the player stands, one to fly to, one
-- out of reach, and one the client gave no state for.
local function read()
    return { map = 1414, here = "Razor Hill", nodes = {
        { name = "Razor Hill", x = 0.06, y = 0.025, state = "current" },
        { name = "Crossroads", x = 0.04, y = 0.5, state = "reachable" },
        { name = "Far Away", x = 0.2, y = 0.2, state = "unreachable" },
        { name = "Maybe", x = 0.09, y = 0.09 },
    } }
end

-- ---------------------------------------------------------------- pure

tests["flights: a map share to world yards and back"] = function(t)
    local cont, wx, wy = F.ToWorld(CORNERS[1411], 0.6, 0.5)
    t.eq({ cont, wx, wy }, { 1, 600, 250 })
    local x, y = F.ToShare(CORNERS[1411], 600, 250)
    t.eq({ x, y }, { 0.6, 0.5 })
    t.eq(F.ToWorld(nil, 0.5, 0.5), nil, "no corners: not known")
    t.eq(F.ToWorld(CORNERS[1411], "x", 0.5), nil)
    t.eq(F.ToShare({ cont = 1, ox = 0, oy = 0, ex = 0, ey = 0, sx = 0, sy = 0 }, 1, 1), nil, "a map of no size")
end

tests["flights: take saves the current and reachable points in world yards, nothing else"] = function(t)
    local into, added = F.Take(read(), CORNERS[1414], nil)
    t.eq(added, 2)
    t.ok(into["Razor Hill"].cont == 1 and near(into["Razor Hill"].wx, 600) and near(into["Razor Hill"].wy, 250))
    t.ok(into["Crossroads"].cont == 1 and near(into["Crossroads"].wx, 400) and near(into["Crossroads"].wy, 5000))
    t.eq(into["Far Away"], nil, "out of reach: not known to this character")
    t.eq(into["Maybe"], nil, "a state not known is not saved")
end

tests["flights: take keeps what was saved, and with no corners or no read takes nothing"] = function(t)
    local old = { ["Ratchet"] = { cont = 1, wx = 9000, wy = 9000 } }
    local into, added = F.Take(read(), CORNERS[1414], old)
    t.eq(added, 2)
    t.eq(into["Ratchet"], { cont = 1, wx = 9000, wy = 9000 })
    local none, n = F.Take(read(), nil, old)
    t.eq(n, 0, "no world place for the flight map: nothing guessed")
    t.eq(none["Razor Hill"], nil)
    t.eq(select(2, F.Take(nil, CORNERS[1414], nil)), 0)
end

-- ---------------------------------------------------------------- the read

tests["flights module: started, and it provides Way and Nodes"] = function(t)
    local k = start()
    t.eq((k:ModuleState(F.NAME)), "started")
    t.eq(F.NAME, "flights")
    local provided = k.use("flights")
    t.ok(type(provided.Way) == "function" and type(provided.Nodes) == "function")
end

tests["flights module: a flight map opening saves the points this character knows"] = function(t)
    local _, c = start({ nodes = { ["Ratchet"] = { cont = 1, wx = 9000, wy = 9000 } } })
    c.setTaxiNodes(read())
    c.fire("TAXIMAP_OPENED")
    local nodes = savedNodes(c)
    t.ok(near(nodes["Razor Hill"].wx, 600) and near(nodes["Crossroads"].wy, 5000))
    t.eq(nodes["Far Away"], nil)
    t.eq(nodes["Maybe"], nil)
    t.eq(nodes["Ratchet"], { cont = 1, wx = 9000, wy = 9000 }, "kept")
end

tests["flights module: an unread or closed flight map writes nothing, no table made"] = function(t)
    local _, c = start()
    c.fire("TAXIMAP_OPENED")
    t.eq((c.saved(ns.id.charDB).learned or {}).flights, nil, "no read")
    c.setTaxiNodes(read())
    c.fire("TAXIMAP_CLOSED")
    t.eq((c.saved(ns.id.charDB).learned or {}).flights, nil, "read only while the map opens")
    c.setMapCorners(1414, nil)
    c.fire("TAXIMAP_OPENED")
    t.eq((c.saved(ns.id.charDB).learned or {}).flights, nil, "the flight map not placed in the world")
end

tests["flights module: a name with a dot is one key, and the points survive the session"] = function(t)
    local _, c = start()
    c.setTaxiNodes({ map = 1414, nodes = { { name = "Mr. Smith's Post", x = 0.06, y = 0.025, state = "reachable" },
        { name = "Crossroads", x = 0.04, y = 0.5, state = "reachable" } } })
    c.fire("TAXIMAP_OPENED")
    t.ok(savedNodes(c)["Mr. Smith's Post"] ~= nil)
    local _, _, api = start({ char = c.saved(ns.id.charDB) })
    local way = api.way(target())
    t.eq(way and way.label, "Fly to Crossroads", "next session, from the saved points")
end

-- ---------------------------------------------------------------- Way

tests["flights way: the step at the board point nearest you, flying to the one nearest the target"] = function(t)
    local _, _, api = start({ nodes = known() })
    t.eq(api.way(target()), { kind = "flight", label = "Fly to Crossroads",
        place = { cont = 1, map = 1411, x = 0.6, y = 0.5 }, radius = F.NEAR })
end

tests["flights way: nil with no known points"] = function(t)
    local _, _, api = start()
    t.eq(api.way(target()), nil)
end

tests["flights way: nil when no known point is on your map to board at"] = function(t)
    local nodes = known()
    nodes["Razor Hill"] = nil
    local _, _, api = start({ nodes = nodes })
    t.eq(api.way(target()), nil, "Crossroads is not on your map")
end

tests["flights way: nil when the target cannot be placed, or is on another continent"] = function(t)
    local _, c, api = start({ nodes = known() })
    t.eq(api.way({ map = 1415, x = 0.5, y = 0.5 }), nil, "another continent is a crossing's")
    c.setMapCorners(1420, nil)
    t.eq(api.way(target()), nil, "the target's map not placed in the world")
    t.eq(api.way(nil), nil)
    t.eq(api.way({ map = 1420, x = "a", y = 0.6 }), nil)
end

tests["flights way: nil when you do not know where you are"] = function(t)
    local _, c, api = start({ nodes = known() })
    c.setPosition(nil)
    t.eq(api.way(target()), nil)
    c.setPosition(1411, 0.5, 0.5)
    c.setMapCorners(1411, nil)
    t.eq(api.way(target()), nil)
end

tests["flights way: nil when the board and the target point are the same"] = function(t)
    local nodes = known()
    nodes["Crossroads"] = nil
    local _, _, api = start({ nodes = nodes })
    t.eq(api.way(target()), nil)
end

tests["flights way: nil when walking is about as quick"] = function(t)
    local _, _, api = start({ nodes = known() })
    t.eq(api.way({ map = 1411, x = 0.6, y = 0.9 }), nil, "a short walk on your own map")
    local slow = { layout = { arrowIntroSeen = true },
                   learned = { flights = { times = { ["Razor Hill>Crossroads"] = 2000 } } } }
    local _, _, api2 = start({ nodes = known(), account = slow })
    t.eq(api2.way(target()), nil, "your own time for that flight is slower than the walk")
end

-- ---------------------------------------------------------------- Travel

tests["flights with travel: a far target goes by flight; walk takes it away and back"] = function(t)
    local k, c, _, travel = start({ nodes = known(), travel = true })
    local s = step()
    local out = travel.via(s)
    t.eq(out.via, "flight")
    t.eq(out.label, "Fly to Crossroads")
    t.eq(out.detail, "Then: Kill wolves")
    t.eq(out.place, { cont = 1, map = 1411, x = 0.6, y = 0.5 })
    c.slashes[ns.id.slash](T.WORD)
    t.ok(c.printed[#c.printed]:find("you walk to this step", 1, true) ~= nil, c.printed[#c.printed])
    t.ok(travel.via(s) == s, "walking")
    c.slashes[ns.id.slash](T.WORD)
    t.eq(travel.via(s).via, "flight", "the shortcut is back")
    t.eq(k.problems:count(), 0)
end

tests["flights on the arrow: fly to the point, the step next, and how far to the board point"] = function(t)
    local k, c = start({ nodes = known(), travel = true, arrow = true })
    t.eq(c.arrows[1].lines, { "Fly to Crossroads", "Then: Waypoint", "100 yd E" })
    t.eq(k.problems:count(), 0)
end

-- ---------------------------------------------------------------- look only

tests["flights: look only - nothing takes, selects or clicks"] = function(t)
    local _, _, api = start({ nodes = known() })
    for _, tbl in ipairs({ F, api }) do
        for name in pairs(tbl) do
            local n = tostring(name):lower()
            t.ok(not (n:find("take") and n ~= "take") and not n:find("select") and not n:find("click")
                and not n:find("cast") and not n:find("secure"), "no acting function: " .. n)
        end
    end
end

return tests
