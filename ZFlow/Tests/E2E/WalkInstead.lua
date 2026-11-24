local _, ns = ...

-- Parity B-30 (lead sections 455, 458): "Walk there instead" as a row of
-- the arrow's menu, not only the typed word. A far quest with a flight
-- that saves the walk: the arrow says to fly. The player right-clicks the
-- arrow, opens the step's level and picks the row: the arrow points the
-- way on foot. The same row then brings the flight back. Only the route
-- choice changes: the character is never moved. Whole add-on loaded the
-- way the game loads it (ns.offline.addon) on a fake client; made-up
-- quest and places. Not tested in game.

local tests = {}
local N, M = ns.Nav, ns.ArrowMenu
local Flights = N.Flights

local HOME_POST, FAR_POST = "Home Post", "Far Post"

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

-- As Tests/E2E/FlightWay.lua: the player at 1411 (0.5, 0.5) is world
-- (500, 250); the wolves at 1420 (0.5, 0.5) are world (5500, 500).
local function start()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, { learned = { flights = { nodes = {
        [HOME_POST] = { cont = 1, wx = 700, wy = 250 },
        [FAR_POST] = { cont = 1, wx = 5480, wy = 500 },
    } } } })
    c.setScreen(1024, 768)
    c.setZone(1, 1411); c.setPosition(1411, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(1411, 1000, 500); c.setMapCont(1411, 1)
    c.setMapSize(1420, 1000, 1000); c.setMapCont(1420, 1)
    c.setMapCorners(1411, { cont = 1, ox = 0, oy = 0, ex = 1000, ey = 0, sx = 0, sy = 500 })
    c.setMapCorners(1420, { cont = 1, ox = 5000, oy = 0, ex = 6000, ey = 0, sx = 5000, sy = 1000 })
    c.setClass("WARRIOR"); c.setFaction("Horde"); c.setLevel(20)
    local db, zones = questie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    c.setQuestLog({ { id = 303, title = "Wolves", objectives = { { text = "Wolves slain: 0/4" } } } })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

local function rowAt(items, key)
    for _, r in ipairs(items or {}) do if r.key == key then return r end end
    return nil
end

-- Right-click, into the step's level; the walk row there, or nil.
local function walkRow(a)
    a.click("right")
    if type(a.enter) ~= "function" or not a.enter(M.STEP) then return nil end
    return rowAt(a.menuItems, M.WALK)
end

-- Fails before: the step's level has no walk row (the word only).
tests["walk instead: the arrow menu's row walks past the flight, and brings it back"] = function(t)
    local c = start()
    local a = c.arrows[1]
    t.eq(a.lines[1], Flights.LABEL:format(FAR_POST), "before: fly")
    local before = { c.position and c.position() }

    local row = walkRow(a)
    t.eq(row and row.text, "Walk there instead", "the row is offered")
    t.eq(a.pickRow(M.WALK), true)
    c.advance(1, 5)
    t.eq(a.lines[1], "Wolves", "the way on foot to the quest")
    t.eq({ c.position and c.position() }, before, "the character is not moved")

    row = walkRow(a)
    t.eq(row and row.text, "Show the shortcut again")
    t.eq(a.pickRow(M.WALK), true)
    c.advance(1, 5)
    t.eq(a.lines[1], Flights.LABEL:format(FAR_POST), "the flight is back")
end

tests["walk instead: a step with no shortcut has no walk row"] = function(t)
    local c = start()
    c.setZone(1, 1420); c.setPosition(1420, 0.45, 0.5)
    c.fire("ZONE_CHANGED_NEW_AREA")
    c.advance(10, 40)
    local a = c.arrows[1]
    t.eq(a.lines[1], "Wolves", "near: the quest itself")
    t.eq(walkRow(a), nil, "no row")
end

return tests
