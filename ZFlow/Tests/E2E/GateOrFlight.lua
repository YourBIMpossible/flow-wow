local _, ns = ...

-- Parity B-05 (lead section 455): a walled place far away, with a gate
-- into it learned and two flight masters known. Flow never chains a gate
-- leg and a flight leg (legacy Modules/Nav/Gates.lua:340 WithAir puts a
-- flight where no gate is known; Nav.lua:3843). Z-Flow's choice, pinned
-- here: N.TravelVia asks the flight before the gate, and a flight is taken
-- only when it saves a fifth of the walk (Flights.SAVES 0.8, legacy
-- N.AIR_SAVES). Else the gate. Whole add-on loaded the way the game loads
-- it (ns.offline.addon) on a fake client; made-up quest and places, only
-- the walled city's map number is the game's. Not tested in game.

local tests = {}
local N, Travel = ns.Nav, ns.Nav.Travel
local Flights = N.Flights

local OUT, CITY = 1411, 1454
local HOME_POST, CITY_POST = "Home Post", "City Post"

local function questie()
    local db = {}
    function db.GetQuest(id)
        if id == 305 then return { ObjectiveData = { { Type = "monster", Id = 9004 } } } end
    end
    function db.GetNPC(id)
        if id == 9004 then return { name = "Sewer Rat", spawns = { [41] = { { 50, 50 } } } } end
    end
    local zones = {}
    function zones.GetUiMapIdByAreaId(area) return ({ [12] = OUT, [41] = CITY })[area] end
    return db, zones
end

-- World yards: OUT is x 0..1000, y 0..500; CITY is x 5000..6000,
-- y 0..1000. The player at OUT (0.5, 0.5) is world (500, 250); the rats at
-- CITY (0.5, 0.5) are world (5500, 500), about 5006 yards away.
local function gate()
    return { a = OUT, b = CITY, ax = 0.9, ay = 0.5, bx = 0.1, by = 0.5, cont = 1, wx = 900, wy = 250 }
end

local function nodes()
    return {
        [HOME_POST] = { cont = 1, wx = 700, wy = 250 },    -- 200 yd from the player
        [CITY_POST] = { cont = 1, wx = 5480, wy = 500 },   -- 20 yd from the rats
    }
end

-- opts.gate (default true), opts.flights (default true), opts.times: the
-- account's flight times.
local function boot(opts)
    opts = opts or {}
    local learned = {}
    if opts.gate ~= false then learned.places = { gates = { gate() } } end
    if opts.times then learned.flights = { times = opts.times } end
    local char = {}
    if opts.flights ~= false then char.learned = { flights = { nodes = nodes() } } end
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true }, learned = learned })
    c.setSaved(ns.id.charDB, char)
    c.setZone(1, OUT); c.setPosition(OUT, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(OUT, 1000, 500); c.setMapCont(OUT, 1)
    c.setMapSize(CITY, 1000, 1000); c.setMapCont(CITY, 1)
    c.setMapCorners(OUT, { cont = 1, ox = 0, oy = 0, ex = 1000, ey = 0, sx = 0, sy = 500 })
    c.setMapCorners(CITY, { cont = 1, ox = 5000, oy = 0, ex = 6000, ey = 0, sx = 5000, sy = 1000 })
    c.setClass("WARRIOR"); c.setFaction("Horde"); c.setLevel(20)
    local db, zones = questie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    c.setQuestLog({ { id = 305, title = "Sewer Rats", objectives = { { text = "Sewer Rat slain: 0/6" } } } })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

local function lines(c)
    local a = c.arrows[1]
    return a and a.lines or {}
end

tests["gate or flight: a flight that saves a fifth of the walk is taken before the gate"] = function(t)
    local c = boot()
    t.eq(lines(c)[1], Flights.LABEL:format(CITY_POST), "the flight step, not the gate")
    t.eq(lines(c)[2], Travel.THEN:format("Sewer Rats"))
end

tests["gate or flight: a flight that saves too little leaves the gate"] = function(t)
    -- About 5006 yd on foot; a flight of an hour saves nothing.
    local c = boot({ times = { [HOME_POST .. ">" .. CITY_POST] = 3600 } })
    t.eq(lines(c)[1], "Way to Orgrimmar", "the gate step")
    t.eq(lines(c)[2], Travel.THEN:format("Sewer Rats"))
end

tests["gate or flight: no flight known, the gate"] = function(t)
    local c = boot({ flights = false })
    t.eq(lines(c)[1], "Way to Orgrimmar")
end

tests["gate or flight: no gate known, the flight (Flow's WithAir)"] = function(t)
    local c = boot({ gate = false })
    t.eq(lines(c)[1], Flights.LABEL:format(CITY_POST))
end

return tests
