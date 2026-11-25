local _, ns = ...

-- Flight masters you do not have yet on the world map (FLOW-PARITY B-08,
-- lead section 557; Flow's Modules/Nav/MapFlights.lua light blue rings).
-- With "Show my flight paths on the world map" on, a flight master one of
-- your characters has seen, whose path this character has not learned, is
-- a "new" pin beside the paths you have. The masters are the ones
-- Nav/FlightPaths.lua already works out from this account's own saved
-- places: none ships. Whole add-on on a fake client; made-up places. Look
-- only: nothing takes a flight or talks to anyone. Not tested in game.
-- Red on aa3dd5a8: the map gets no "new" pin, and there is no MF.Masters.

local tests = {}
local MF = ns.MapFlights

-- World yards: map 1411 is x 0..1000, y 0..500; map 1499 is x 2000..3000,
-- y 0..1000; the continent's world map 1414 spans x 0..10000, y 0..1000.
local HOME_POST = "Home Post"
local CORNERS_1499 = { cont = 1, ox = 2000, oy = 0, ex = 3000, ey = 0, sx = 2000, sy = 1000 }

local function master(map, x, y, faction)
    return { map = map, x = x, y = y, roles = { flight = true }, factions = { [faction or "Horde"] = true }, seen = 5 }
end

-- opts: late (true: the map of Late Master has no corners yet)
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { learned = { places = { npcs = {
        ["New Master"] = master(1411, 0.8, 0.5),
        -- Stands at Home Post, a path this character has: its master, not one to learn.
        ["Home Keeper"] = master(1411, 0.52, 0.5),
        ["Enemy Master"] = master(1411, 0.3, 0.5, "Alliance"),
        ["Late Master"] = master(1499, 0.5, 0.5),
    } } } })
    c.setSaved(ns.id.charDB, { learned = { flights = { nodes = { [HOME_POST] = { cont = 1, wx = 520, wy = 250 } } } } })
    c.setZone(1, 1411); c.setPosition(1411, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(1411, 1000, 500); c.setMapCont(1411, 1)
    c.setMapCorners(1411, { cont = 1, ox = 0, oy = 0, ex = 1000, ey = 0, sx = 0, sy = 500 })
    c.setMapCorners(1414, { cont = 1, ox = 0, oy = 0, ex = 10000, ey = 0, sx = 0, sy = 1000 })
    if not opts.late then c.setMapCorners(1499, CORNERS_1499) end
    c.setClass("WARRIOR"); c.setFaction("Horde"); c.setLevel(20)
    c.setQuestLog({})
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    addon.settings:set(MF.SETTING, true)
    c.setWorldMap(1414)
    c.advance(2, 8)
    return c, addon, addon.problems:count()
end

local function pin(c, name)
    local h = c.mapPinSets and c.mapPinSets[1]
    for _, p in ipairs(h and h.pins or {}) do
        if p.name == name then return p end
    end
    return nil
end

local function near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-6 end

-- Red on aa3dd5a8: there is no pin for New Master.
tests["map flights new: a seen flight master whose path you do not have is a new pin, where they stand"] = function(t)
    local c, addon, base = start()
    local p = pin(c, "New Master")
    t.ok(p ~= nil, "a pin for the master not learned yet")
    t.eq(p and p.kind, "new")
    -- (0.8, 0.5) of map 1411 is world (800, 250): (0.08, 0.25) of the continent's map.
    t.ok(p ~= nil and near(p.x, 0.08) and near(p.y, 0.25), "where they stand")
    local home = pin(c, HOME_POST)
    t.eq(home and home.kind, "have", "the path you have is still a pin of its own kind")
    t.eq(pin(c, "Home Keeper"), nil, "the master of a path you have is not one to learn")
    t.eq(pin(c, "Enemy Master"), nil, "a master only the other faction saw is no pin")
    t.eq(addon.problems:count(), base, "no new problem")
end

tests["map flights new: no new pins with the flight path advice off, or the map setting off"] = function(t)
    local c, addon = start()
    t.ok(pin(c, "New Master") ~= nil, "shown first")
    addon.settings:set(ns.FlightPaths.SETTING, false)
    c.advance(2, 8)
    t.eq(pin(c, "New Master"), nil, "the flight path advice off: no master to learn is shown")
    t.ok(pin(c, HOME_POST) ~= nil, "the paths you have stay")
    addon.settings:set(ns.FlightPaths.SETTING, true)
    addon.settings:set(MF.SETTING, false)
    c.advance(2, 8)
    t.eq(pin(c, "New Master"), nil, "the map setting off: nothing is drawn")
end

-- Section 236: data arriving late; a read that raises, then recovers.
tests["map flights new: a master on a map with no corners yet has no pin, then one once they are read"] = function(t)
    local c, addon, base = start({ late = true })
    t.eq(pin(c, "Late Master"), nil, "no place is guessed")
    t.ok(pin(c, "New Master") ~= nil, "the others are drawn")
    c.setMapCorners(1499, CORNERS_1499)
    c.advance(2, 8)
    local p = pin(c, "Late Master")
    t.ok(p ~= nil and p.kind == "new", "drawn once its map is known")
    t.ok(p ~= nil and near(p.x, 0.25) and near(p.y, 0.5), "at world (2500, 500)")
    local flights = addon.use("flightPaths")
    local real = flights.Goals
    flights.Goals = function() error("no goals (test)") end
    c.advance(2, 8)
    t.eq(pin(c, "New Master"), nil, "the masters list raises: no new pins")
    t.ok(pin(c, HOME_POST) ~= nil, "the paths you have are still drawn")
    flights.Goals = real
    c.advance(2, 8)
    t.ok(pin(c, "New Master") ~= nil, "back once it answers")
    t.eq(addon.problems:count(), base, "no new problem")
end

-- Red on aa3dd5a8: there is no MF.Masters (the call raises).
tests["map flights new: goals to masters, pure"] = function(t)
    local corners = { [7] = { cont = 1, ox = 0, oy = 0, ex = 1000, ey = 0, sx = 0, sy = 500 } }
    local function cornersOf(map) return corners[map] end
    local goals = {
        { name = "A", place = { map = 7, x = 0.8, y = 0.5 } },
        { name = "No Corners", place = { map = 8, x = 0.5, y = 0.5 } },
        { name = "No Place" },
        { place = { map = 7, x = 0.1, y = 0.1 } },
        "not a goal",
    }
    t.eq(MF.Masters(goals, cornersOf), { { name = "A", cont = 1, wx = 800, wy = 250, map = 7, x = 0.8, y = 0.5 } })
    t.eq(MF.Masters(nil, cornersOf), {})
    t.eq(MF.Masters(goals, nil), {})
    t.eq(MF.Masters(goals, function() error("no corners (test)") end), {}, "a corners read that raises: none")
end

return tests
