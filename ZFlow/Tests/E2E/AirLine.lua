local _, ns = ...

-- Parity row A1-19 (lead section 488): when the arrow's step is reached by a
-- flight, mapFlights AirLine() says "Quicker by air: fly from A to B.".
-- Setup as FlightMarks.lua: a far quest, two known flight masters. On the
-- whole add-on with a fake client; made-up places. Not tested in game.
-- Fails before: there is no Nav/AirLine.lua and no AirLine().

local tests = {}
local MF = ns.MapFlights

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

tests["air line e2e: a flight step gives the quicker-by-air line, setting off or on"] = function(t)
    local c, addon = start()
    local mod = addon.use("mapFlights")
    t.ok(mod ~= nil and type(mod.AirLine) == "function", "provided")
    t.eq(addon.settings:get(MF.SETTING), false, "pins off")
    t.eq(mod and mod.AirLine(), "Quicker by air: fly from " .. HOME_POST .. " to " .. FAR_POST .. ".")
end

tests["air line: without both names, or the same place, there is no line"] = function(t)
    local AL = ns.Nav.AirLine
    t.eq(AL.Words(nil), nil)
    t.eq(AL.Words({ from = "A" }), nil)
    t.eq(AL.Words({ from = "", to = "B" }), nil)
    t.eq(AL.Words({ from = "A", to = "A" }), nil)
    t.eq(AL.Words({ from = "A", to = "B" }), "Quicker by air: fly from A to B.")
end

return tests
