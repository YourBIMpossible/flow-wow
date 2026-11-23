local _, ns = ...

-- Lead section 286 (zflow-travel-visible): a far quest goal says how to get
-- there on screen, or says what is missing and how the player supplies it.
-- Never a bare straight line on a default profile with no flight data.
-- Whole add-on loaded the way the game loads it (ns.offline.addon) on a
-- fake client, made-up places and names only. Not tested in game.
--   1. Data from the old add-on (its account and character tables, the
--      legacy shape) is copied into Z-Flow once at load, and then gives a
--      flight line for a quest goal on another map.
--   2. No flight data: the explaining line under the quest.
--   3. A flight map opened during play changes the line, no reload.

local tests = {}
local Flights, Travel, Guard = ns.Nav.Flights, ns.Nav.Travel, ns.Guard

local function questie()
    local db = {}
    function db.GetQuest(id)
        if id == 303 then return { ObjectiveData = { { Type = "monster", Id = 9002 } } } end
    end
    function db.GetNPC(id)
        if id == 9002 then return { name = "Far Wolf", spawns = { [40] = { { 50, 50 } } } } end
    end
    local zones = {}
    function zones.GetUiMapIdByAreaId(area) return ({ [12] = 1411, [40] = 1420 })[area] end
    return db, zones
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for key, value in pairs(v) do out[key] = copy(value) end
    return out
end

-- World yards as in Tests/E2E/FlightWay.lua: map 1411 is x 0..1000,
-- y 0..500; map 1420 (the wolves) x 5000..6000, y 0..1000; both continent
-- 1. Map 1414 is the continent flight map, x 0..10000, y 0..1000. The
-- player at 1411 (0.5, 0.5) is world (500, 250); the wolves at 1420
-- (0.5, 0.5) are world (5500, 500), about 5006 yards away.
local HOME_POST, FAR_POST = "Home Post", "Far Post"
local function legacyFlights()
    return {
        [HOME_POST] = { cont = 1, wx = 700, wy = 250 },    -- 200 yd from the player
        [FAR_POST] = { cont = 1, wx = 5480, wy = 500 },    -- 20 yd from the wolves
    }
end

-- opts.account, opts.char: Z-Flow's saved tables. opts.flow = { db, char }:
-- the old add-on's saved tables, present as the client loads them.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    if opts.char then c.setSaved(ns.id.charDB, opts.char) end
    if opts.flow then
        c.setSaved(ns.id.predecessorDB, opts.flow.db or {})
        if opts.flow.char then c.setSaved(ns.id.predecessorCharDB, opts.flow.char) end
    end
    c.setZone(1, 1411); c.setPosition(1411, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(1411, 1000, 500); c.setMapCont(1411, 1)
    c.setMapSize(1420, 1000, 1000); c.setMapCont(1420, 1)
    c.setMapCorners(1411, { cont = 1, ox = 0, oy = 0, ex = 1000, ey = 0, sx = 0, sy = 500 })
    c.setMapCorners(1420, { cont = 1, ox = 5000, oy = 0, ex = 6000, ey = 0, sx = 5000, sy = 1000 })
    c.setMapCorners(1414, { cont = 1, ox = 0, oy = 0, ex = 10000, ey = 0, sx = 0, sy = 1000 })
    c.setClass("WARRIOR"); c.setFaction("Horde")
    local db, zones = questie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    c.setQuestLog({ { id = 303, title = "Wolves", objectives = { { text = "Wolves slain: 0/4" } } } })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

local function has(lines, text)
    for _, l in ipairs(lines or {}) do if l == text then return true end end
    return false
end

local function said(c, from, text)
    for i = from + 1, #(c.printed or {}) do
        if c.printed[i] == text then return true end
    end
    return false
end

-- The old add-on keeps a character's flight points per character
-- (legacy Modules/Nav/Nav.lua:2712 PerCharacter("flights")): parked under
-- its character table's data at logout (legacy Core.lua:226-232), and put
-- back live at the account table's top while it is loaded (legacy
-- Core.lua:197-206). Times and rate are account values. live = true: the
-- second shape.
local function legacy(live)
    local db = { flightTimes = { [HOME_POST .. ">" .. FAR_POST] = 150 }, flightRate = 30 }
    if live then
        db.flights = legacyFlights()
        return { db = db, char = { data = {} } }
    end
    return { db = db, char = { data = { flights = legacyFlights() } } }
end

local ROUTE = Flights.ROUTE and Flights.ROUTE:format(HOME_POST, FAR_POST, 20)

-- Fails before: nothing runs the import at load, so the old flight points
-- never reach Z-Flow and no line is printed.
tests["travel visible: the old add-on's flights are copied once at load, and say so"] = function(t)
    local c = start({ flow = legacy() })
    t.ok(Guard.IMPORTED ~= nil, "the line exists")
    local line = Guard.IMPORTED and Guard.IMPORTED:format(ns.id.title, 2)
    t.ok(said(c, 0, line), "said: " .. tostring(line))
    local char = c.saved(ns.id.charDB)
    local learned = type(char.learned) == "table" and char.learned.flights or {}
    t.eq(learned.nodes, legacyFlights(), "both points copied into the character")
    local account = c.saved(ns.id.accountDB)
    local aFlights = type(account.learned) == "table" and account.learned.flights or {}
    t.eq(aFlights.times, { [HOME_POST .. ">" .. FAR_POST] = 150 }, "your own flight time")
    t.eq(aFlights.rate, 30, "your own flight rate")
    t.eq(c.saved(ns.id.predecessorCharDB).data.flights, legacyFlights(), "the old data is not changed")

    -- The old add-on is still on at the next load: no second copy, no line.
    local records = #(account.imports or {})
    local c2 = start({ account = copy(account), char = copy(char), flow = legacy() })
    t.eq(#(c2.saved(ns.id.accountDB).imports or {}), records, "no second import record")
    t.ok(not said(c2, 0, line), "nothing said again")
    local zero = Guard.IMPORTED and Guard.IMPORTED:format(ns.id.title, 0)
    t.ok(not said(c2, 0, zero), "no line with nothing new either")
end

-- Fails before: nothing runs the import at load.
tests["travel visible: the old add-on's live flights (it is loaded) are copied the same"] = function(t)
    local c = start({ flow = legacy(true) })
    local char = c.saved(ns.id.charDB)
    local learned = type(char.learned) == "table" and char.learned.flights or {}
    t.eq(learned.nodes, legacyFlights(), "both points copied into the character")
    t.eq(c.saved(ns.id.predecessorDB).flights, legacyFlights(), "the old data is not changed")
end

-- Fails before: the import never ran, so no flight is known and no route
-- line is shown.
tests["travel visible: imported data gives the flight line for a quest on another map"] = function(t)
    local c1 = start({ flow = legacy() })
    -- The old add-on turned off: only Z-Flow's own saved tables load.
    local c = start({ account = copy(c1.saved(ns.id.accountDB)), char = copy(c1.saved(ns.id.charDB)) })
    local a = c.arrows[1]
    t.eq(a.shown, true)
    t.eq(a.lines[1], Flights.LABEL:format(FAR_POST))
    t.eq(a.lines[2], Travel.THEN:format("Wolves"))
    t.eq(a.lines[3], ROUTE, "the route line")
    t.ok(type(a.lines[4]) == "string" and a.lines[4]:match("^%d+ yd") ~= nil, "then the distance: " .. tostring(a.lines[4]))
end

-- Fails before: a fresh character sees "Wolves" and a straight line of
-- about 5000 yards with no word on flights.
tests["travel visible: no flight data says so under a far quest, never a bare line"] = function(t)
    local c = start()
    local a = c.arrows[1]
    t.eq(a.shown, true)
    t.eq(a.lines[1], "Wolves")
    t.ok(Flights.NONE ~= nil, "the line exists")
    t.eq(a.lines[2], "Wolves slain: 0/4")
    t.eq(a.lines[3], Flights.NONE, "the explaining line")
    t.ok(type(a.lines[4]) == "string" and a.lines[4]:match("^%d+ yd") ~= nil, "then the distance: " .. tostring(a.lines[4]))
    t.eq(a.place ~= nil or a.shown, true, "still the waypoint to the quest")

    -- Near: the same quest goal within a short walk on this map says nothing
    -- about flights.
    c.setZone(1, 1420); c.setPosition(1420, 0.45, 0.5)
    c.fire("ZONE_CHANGED_NEW_AREA")
    c.advance(10, 40)
    t.eq(a.lines[1], "Wolves")
    t.ok(not has(a.lines, Flights.NONE), "no flight line near the goal")
end

-- Fails before: no explaining line first, and no route line after.
tests["travel visible: opening a flight map changes the line with no reload"] = function(t)
    local c = start()
    local a = c.arrows[1]
    t.eq(a.lines[3], Flights.NONE, "before: the explaining line")
    -- The flight map of the continent, opened at Home Post: every known
    -- point of it is learned, not only the one the player stands at.
    c.setTaxiNodes({ map = 1414, nodes = {
        { name = HOME_POST, x = 0.07, y = 0.25, state = "current" },
        { name = FAR_POST, x = 0.548, y = 0.5, state = "reachable" },
        { name = "Shut Post", x = 0.9, y = 0.9, state = "unreachable" },
    } })
    c.fire("TAXIMAP_OPENED")
    c.setTaxiNodes(nil)
    c.fire("TAXIMAP_CLOSED")
    c.advance(2, 8)
    t.eq(a.lines[1], Flights.LABEL:format(FAR_POST), "after: the flight step")
    t.eq(a.lines[3], ROUTE, "after: the route line")
    t.ok(not has(a.lines, Flights.NONE), "the explaining line is gone")
    local nodes = c.saved(ns.id.charDB).learned.flights.nodes
    t.eq(nodes["Shut Post"], nil, "a point the map shows as not reachable is not learned")
end

-- Fails before: with points known but none on the player's map, the far
-- quest is a bare line.
tests["travel visible: points known but none here names the nearest flight master"] = function(t)
    local far = { [FAR_POST] = { cont = 1, wx = 5480, wy = 500 }, ["Mid Post"] = { cont = 1, wx = 2500, wy = 250 } }
    local c = start({ char = { learned = { flights = { nodes = far } } } })
    local a = c.arrows[1]
    t.eq(a.lines[1], "Wolves", "no flight step: no master on this map")
    t.eq(a.lines[3], Flights.ROUTE and Flights.ROUTE:format("Mid Post", FAR_POST, 20), "the nearest known master")
end

return tests
