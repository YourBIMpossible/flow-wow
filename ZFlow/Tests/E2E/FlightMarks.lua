local _, ns = ...

-- End to end (lead section 187 section 7): the whole add-on loaded the way
-- the game loads it (ns.offline.addon), on a fake client, for a far quest
-- on another map of the same continent with two known flight masters (as
-- FlightWay.lua). Quest log -> Questie stand-in -> QuestSource -> Travel ->
-- Flights -> the arrow; then the flight map's ring (taxiMark) and the world
-- map's pins (mapFlights). Made-up places; not tested in game. Look only:
-- nothing takes a flight.

local tests = {}
local TM, MF = ns.TaxiMark, ns.MapFlights

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

-- World yards as FlightWay.lua: map 1411 is x 0..1000, y 0..500; map 1420
-- (the wolves) is x 5000..6000, y 0..1000; the wolves are at (5500, 500).
-- The flight map and the continent's world map 1414 span x 0..10000,
-- y 0..1000: Home Post is its (0.052, 0.25), Far Post its (0.548, 0.5).
local HOME_POST, FAR_POST = "Home Post", "Far Post"
local function nodes()
    return {
        [HOME_POST] = { cont = 1, wx = 520, wy = 250 },
        [FAR_POST] = { cont = 1, wx = 5480, wy = 500 },
    }
end

local function taxiRead()
    return { map = 1414, here = HOME_POST, nodes = {
        { name = HOME_POST, x = 0.052, y = 0.25, state = "current" },
        { name = FAR_POST, x = 0.548, y = 0.5, state = "reachable" },
    } }
end

local function start()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, { learned = { flights = { nodes = nodes() } } })
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

local function names(h)
    local out = {}
    for i, p in ipairs(h.pins) do out[i] = p.name .. ":" .. tostring(p.role) end
    return table.concat(out, ", ")
end

tests["flight marks: opening the flight map rings the landing for the far quest; closing hides it"] = function(t)
    local c, addon = start()
    t.eq(c.arrows[1].lines[1], ns.Nav.Flights.LABEL:format(FAR_POST), "the arrow says to fly")
    t.eq(addon.settings:get(TM.SETTING), true, "on by default")
    c.setTaxiNodes(taxiRead())
    c.fire("TAXIMAP_OPENED")
    local h = c.taxiMarks[1]
    t.ok(h ~= nil, "a ring was made")
    t.eq(h and h.shown, true)
    t.eq(h and h.node and h.node.name, FAR_POST)
    t.eq(h and h.label, TM.Label(nil))
    c.advance(2, 8)
    t.eq(h and h.shown, true, "still rung while open")
    t.eq(h and h.node.name, FAR_POST)
    c.setTaxiNodes(nil)
    c.fire("TAXIMAP_CLOSED")
    t.eq(h and h.shown, false, "hidden at the closing")
end

tests["flight marks: with nav.taxiMark off the flight map gets no ring"] = function(t)
    local c, addon = start()
    t.ok((addon.settings:set(TM.SETTING, false)), "set off")
    c.setTaxiNodes(taxiRead())
    c.fire("TAXIMAP_OPENED")
    c.advance(2, 8)
    t.eq(#c.taxiMarks, 0, "nothing made")
end

tests["flight marks: the world map shows the known flight points with nav.mapFlights on, none off"] = function(t)
    local c, addon = start()
    t.eq(addon.settings:get(MF.SETTING), false, "off by default")
    c.setWorldMap(1414)
    c.advance(2, 8)
    t.eq(#c.mapPinSets, 0, "nothing drawn while off")
    t.ok((addon.settings:set(MF.SETTING, true)), "set on")
    c.advance(2, 8)
    local h = c.mapPinSets[1]
    t.ok(h ~= nil, "pins made")
    t.eq(h and names(h), FAR_POST .. ":to, " .. HOME_POST .. ":from")
    t.eq(h and #h.lines, 1, "the next step's flight")
    c.setWorldMap(nil)
    c.advance(2, 8)
    t.eq(h and h.shown, false, "the map closed: cleared")
    c.setWorldMap(1414)
    addon.settings:set(MF.SETTING, false)
    c.advance(2, 8)
    t.eq(h and h.shown, false, "off: nothing drawn")
end

return tests
