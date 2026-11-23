local _, ns = ...

-- End to end (lead section 187 item 4): the whole add-on loaded the way the
-- game loads it (ns.offline.addon), on a fake client, for a far quest on
-- another map of the same continent. Quest log -> Questie stand-in ->
-- QuestSource -> Travel -> Flights (saved char learned.flights.nodes, or
-- the travel preview's made-up master) -> the quest arrow's lines. Made-up
-- places; not tested in game. Look only: nothing takes a flight.

local tests = {}
local Flights, Travel, Try = ns.Nav.Flights, ns.Nav.Travel, ns.Nav.Try

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

-- World yards: map 1411 is x 0..1000, y 0..500; map 1420 (the wolves, the
-- same continent 1) is x 5000..6000, y 0..1000. The wolves at 1420
-- (0.5, 0.5) are world (5500, 500); the player at 1411 (0.5, 0.5) is
-- world (500, 250), about 5006 yards away.
local HOME_POST, FAR_POST = "Home Post", "Far Post"
local function nodes()
    return {
        [HOME_POST] = { cont = 1, wx = 700, wy = 250 },    -- 1411 (0.7, 0.5): 200 yd from the player (outside the arrival radius)
        [FAR_POST] = { cont = 1, wx = 5480, wy = 500 },    -- 1420 (0.48, 0.5): 20 yd from the wolves
    }
end

-- A Horde warrior facing north in the middle of map 1411 with the wolves
-- quest. opts.char: the char DB.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    if opts.char then c.setSaved(ns.id.charDB, opts.char) end
    c.setZone(1, 1411); c.setPosition(1411, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(1411, 1000, 500); c.setMapCont(1411, 1)
    c.setMapSize(1420, 1000, 1000); c.setMapCont(1420, 1)
    c.setMapCorners(1411, { cont = 1, ox = 0, oy = 0, ex = 1000, ey = 0, sx = 0, sy = 500 })
    c.setMapCorners(1420, { cont = 1, ox = 5000, oy = 0, ex = 6000, ey = 0, sx = 5000, sy = 1000 })
    c.setClass("WARRIOR"); c.setFaction("Horde")
    local db, zones = questie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    c.setQuestLog({ { id = 303, title = "Wolves", objectives = { { text = "Wolves slain: 0/4" } } } })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

local function startsWith(text, head)
    return type(text) == "string" and text:sub(1, #head) == head
end

local function anyStarts(lines, head)
    for _, l in ipairs(lines or {}) do if startsWith(l, head) then return true end end
    return false
end

tests["flight way: a far quest with two known flight masters, fly first"] = function(t)
    local c = start({ char = { learned = { flights = { nodes = nodes() } } } })
    local a = c.arrows[1]
    -- Flights.Pick: board Home Post (200 yd), land Far Post (20 yd from the
    -- wolves); 220/7 + 4780/24 + 10 s is well under 0.8 of the 5006 yd walk.
    t.eq(a.shown, true)
    t.eq(a.lines[1], Flights.LABEL:format(FAR_POST))
    t.eq(a.lines[2], Travel.THEN:format("Wolves"))
    t.ok(type(a.lines[3]) == "string" and a.lines[3]:match("^%d+ yd") ~= nil, "a distance line: " .. tostring(a.lines[3]))

    -- At the flight master: still the flight step (Pick boards here).
    c.setPosition(1411, 0.7, 0.5)
    c.advance(2, 8)

    -- Landed: the player is on the wolves' map. The only known point on
    -- this map is Far Post, which is also the one nearest the wolves, so
    -- Pick answers "the same flight point" and the arrow points at the
    -- quest itself. (Arrival is simulated by moving the player there.)
    c.setZone(1, 1420); c.setPosition(1420, 0.4, 0.5)
    c.fire("ZONE_CHANGED_NEW_AREA")
    c.advance(10, 40)
    t.eq(a.shown, true)
    t.eq(a.lines[1], "Wolves")
    t.ok(not anyStarts(a.lines, "Fly to "), "no flight step on the wolves' map")
end

tests["flight way: try flight with no saved points flies to the made-up landing, nothing saved"] = function(t)
    local c = start()
    local before = #c.printed
    c.slashes[ns.id.slash]("try flight")
    c.advance(2, 8)
    local prefix = ns.id.title .. ": Preview"
    t.ok(#c.printed > before, "try said something")
    for i = before + 1, #c.printed do
        t.ok(startsWith(c.printed[i], prefix), "a Preview line: " .. tostring(c.printed[i]))
    end
    local a = c.arrows[1]
    t.eq(a.shown, true)
    t.eq(a.lines[1], Flights.LABEL:format(Try.LAND_NAME))
    t.eq(a.lines[2], Travel.THEN:format(Try.LABEL.flight))

    c.slashes[ns.id.slash]("try off")
    c.advance(2, 8)
    local char = c.saved(ns.id.charDB)
    t.ok(not (type(char.learned) == "table" and char.learned.flights ~= nil), "nothing written to learned.flights")
    t.ok(not anyStarts(a.shown and a.lines or {}, Flights.LABEL:format(Try.LAND_NAME)), "the preview's flight is gone")
end

return tests
