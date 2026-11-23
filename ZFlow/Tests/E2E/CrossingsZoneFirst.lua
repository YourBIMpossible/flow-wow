local _, ns = ...

-- End to end (lead section 187): the whole add-on (ns.offline.addon) on a
-- fake client, for the two navigation settings that had no reader and no
-- row: nav.crossings (boats and zeppelins on the way) and nav.zoneFirst
-- (what is left on this map before a quest elsewhere). Quest log ->
-- Questie stand-in -> QuestRead/QuestSource -> Travel (crossings) -> the
-- quest arrow's lines. Made-up places, quests and crossings. Offline only:
-- not tested in game.

local tests = {}
local N = ns.Nav
local Travel = N.Travel

local CROSS, ZONE = "nav.crossings", "nav.zoneFirst"

-- Wolves (303) only on map 1420; Boars (304) on map 1411.
local function questie()
    local db = {}
    function db.GetQuest(id)
        if id == 303 then return { ObjectiveData = { { Type = "monster", Id = 9002 } } } end
        if id == 304 then return { ObjectiveData = { { Type = "monster", Id = 9003 } } } end
    end
    function db.GetNPC(id)
        if id == 9002 then return { name = "Far Wolf", spawns = { [40] = { { 50, 50 } } } } end
        if id == 9003 then return { name = "Near Boar", spawns = { [12] = { { 50, 30 } } } } end
    end
    local zones = {}
    function zones.GetUiMapIdByAreaId(area) return ({ [12] = 1411, [40] = 1420 })[area] end
    return db, zones
end

-- One boat, taken twice, from the dock on map 1411 (continent 1) to the
-- dock on map 1420 (continent 0).
local function boat()
    return { key = "boat", how = "boat", seen = 2,
             a = { cont = 1, map = 1411, x = 0.5, y = 0.1, name = "Durotar dock" },
             b = { cont = 0, map = 1420, x = 0.6, y = 0.6, name = "Tirisfal dock" } }
end

local function wolves() return { id = 303, title = "Wolves", objectives = { { text = "Wolves slain: 0/4" } } } end
local function boars() return { id = 304, title = "Boars", objectives = { { text = "Boars slain: 0/4" } } } end

-- A Horde warrior facing north in the middle of map 1411 (continent 1),
-- not on a flight. Map 1420 is on continent opts.cont (default 0, another
-- continent). opts.saved: the account DB; opts.log: the quest log
-- (default Wolves alone).
local function start(opts)
    opts = opts or {}
    local cont2 = opts.cont or 0
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.saved or {})
    c.setZone(1, 1411); c.setPosition(1411, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(1411, 1000, 500); c.setMapCont(1411, 1)
    c.setMapSize(1420, 1000, 1000); c.setMapCont(1420, cont2)
    c.setMapCorners(1411, { cont = 1, ox = 1000, oy = 2000, ex = 0, ey = -1000, sx = -500, sy = 0 })
    c.setMapCorners(1420, { cont = cont2, ox = 1000, oy = 1000, ex = 0, ey = -1000, sx = -1000, sy = 0 })
    c.setClass("WARRIOR"); c.setFaction("Horde")
    c.setOnTaxi(false)
    local db, zones = questie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    c.setQuestLog(opts.log or { wolves() })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

local function has(lines, text)
    for _, l in ipairs(lines or {}) do if l == text then return true end end
    return false
end

-- What the quest arrow shows; nil when it is hidden (a hidden arrow keeps
-- the lines it last drew).
local function shown(c)
    local a = c.arrows[1]
    if not a.shown then return nil end
    return a.lines
end

local BOAT_LINES = { "Boat to Tirisfal dock", "Then: Wolves", "200 yd N" }
local FAR_LINES = { "Wolves", "Wolves slain: 0/4", Travel.FAR }

-- ------------------------------------------------------------- the rows

tests["crossings and zone first are rows the player can switch, on at first"] = function(t)
    local _, addon = start()
    for _, key in ipairs({ CROSS, ZONE }) do
        local row = addon.settings:row(key)
        t.ok(row ~= nil, key .. " is a row")
        t.eq(row and row.type, "bool")
        t.eq(addon.settings:get(key), true, key .. " starts on")
    end
    t.eq(N.CROSSING_SETTING, CROSS)
    t.eq(N.LEAVING_SETTING, ZONE)
end

-- -------------------------------------------------------------- crossings

tests["learned boat: a quest on the other continent gives the boarding place, not far"] = function(t)
    local c = start({ saved = { learned = { places = { crossings = { boat() } } } } })
    t.eq(shown(c), BOAT_LINES)
    t.ok(not has(shown(c), Travel.FAR), "not the far words")
end

tests["crossings off: the same quest says another continent; on again, the boat is back"] = function(t)
    local c, addon = start({ saved = { learned = { places = { crossings = { boat() } } } } })
    local ok, why = addon.settings:set(CROSS, false)
    t.ok(ok, "setting taken: " .. tostring(why))
    c.advance(1, 4)
    t.eq(shown(c), FAR_LINES)
    addon.settings:set(CROSS, true)
    c.advance(1, 4)
    t.eq(shown(c), BOAT_LINES)
end

tests["crossings off survives a reload"] = function(t)
    local c, addon = start({ saved = { learned = { places = { crossings = { boat() } } } } })
    addon.settings:set(CROSS, false)
    c.advance(1, 4)
    local c2 = start({ saved = c.saved(ns.id.accountDB) })
    t.eq(shown(c2), FAR_LINES)
end

-- The player's own trips: the boat taken there and back twice, then back
-- in the middle of map 1411.
local function trips(c)
    local function dock() c.setZone(1, 1411); c.setPosition(1411, 0.5, 0.1); c.advance(1, 4) end
    local function over() c.setZone(0, 1420); c.setPosition(1420, 0.6, 0.6); c.advance(1, 4) end
    dock(); over(); dock(); over(); dock()
    c.setPosition(1411, 0.5, 0.5)
    c.advance(1, 4)
end

local function savedCrossings(c)
    local acc = c.saved(ns.id.accountDB)
    local l = type(acc.learned) == "table" and acc.learned.places
    return type(l) == "table" and l.crossings or nil
end

tests["own trips, nothing saved before: the boat is learned and used"] = function(t)
    local c = start()
    t.eq(shown(c), FAR_LINES, "far before any trip")
    trips(c)
    local l = shown(c)
    t.ok(type(l) == "table" and l[1] ~= "Wolves", "a crossing step first: " .. tostring(l and l[1]))
    t.eq(l and l[2], "Then: Wolves")
    t.eq(l and l[3], "200 yd N")
end

tests["crossings off: own trips are still noted, and used once it is on"] = function(t)
    local c, addon = start()
    addon.settings:set(CROSS, false)
    trips(c)
    t.eq(shown(c), FAR_LINES, "off: not used")
    local list = savedCrossings(c)
    t.ok(type(list) == "table" and #list == 1, "the trips are saved as one crossing")
    addon.settings:set(CROSS, true)
    c.advance(1, 4)
    local l = shown(c)
    t.eq(l and l[2], "Then: Wolves")
    t.eq(l and l[3], "200 yd N")
end

-- ------------------------------------------------------------- zone first

tests["zone first on: the quest on this map comes before the first in the log"] = function(t)
    local c = start({ cont = 1, log = { wolves(), boars() } })
    t.eq(shown(c), { "Boars", "Boars slain: 0/4", "100 yd N" })
end

tests["zone first off: the first quest in the log, on another map; on again, back here"] = function(t)
    local c, addon = start({ cont = 1, log = { wolves(), boars() } })
    local ok, why = addon.settings:set(ZONE, false)
    t.ok(ok, "setting taken: " .. tostring(why))
    c.advance(1, 4)
    t.eq(shown(c), { "Wolves", "Wolves slain: 0/4", N.Flights.NONE, "1415 yd SE" }) -- section 208: the line of section 286
    addon.settings:set(ZONE, true)
    c.advance(1, 4)
    t.eq(shown(c), { "Boars", "Boars slain: 0/4", "100 yd N" })
end

tests["zone first off, quest on the other continent with a learned boat: the boarding place"] = function(t)
    local c, addon = start({ log = { wolves(), boars() },
                             saved = { learned = { places = { crossings = { boat() } } } } })
    addon.settings:set(ZONE, false)
    c.advance(1, 4)
    t.eq(shown(c), BOAT_LINES)
end

tests["zone first off survives a reload"] = function(t)
    local c, addon = start({ cont = 1, log = { wolves(), boars() } })
    addon.settings:set(ZONE, false)
    c.advance(1, 4)
    local c2 = start({ cont = 1, log = { wolves(), boars() }, saved = c.saved(ns.id.accountDB) })
    t.eq(shown(c2), { "Wolves", "Wolves slain: 0/4", N.Flights.NONE, "1415 yd SE" }) -- section 208: the line of section 286
end

return tests
