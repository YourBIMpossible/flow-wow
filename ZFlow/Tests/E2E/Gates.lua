local _, ns = ...

-- Gates (S35), on the whole add-on loaded on a fake client. The real
-- entries: the gates watcher tick (every N.Gates.EVERY seconds it reads
-- the position, the world position and the taxi read, and learns a walk
-- from the open into a walled city), and the quest arrow, whose step goes
-- through Travel's Via, which asks ns.use("gates").Step. A quest inside
-- Orgrimmar's walls (1454) seen from outside (1411) with a gate learned:
-- the arrow says "Way to Orgrimmar", then the quest. Made-up quests and
-- places; only the walled city's map number is the game's. Not tested in
-- game.

local tests = {}
local N, Travel = ns.Nav, ns.Nav.Travel
local Gates = N.Gates

local OUT, CITY = 1411, 1454

local function questie()
    local db = {}
    function db.GetQuest(id)
        if id == 304 then return { ObjectiveData = { { Type = "monster", Id = 9003 } } } end
    end
    function db.GetNPC(id)
        if id == 9003 then return { name = "City Rat", spawns = { [41] = { { 50, 50 } } } } end
    end
    local zones = {}
    function zones.GetUiMapIdByAreaId(area) return ({ [41] = CITY })[area] end
    return db, zones
end

local function gate()
    return { a = OUT, b = CITY, ax = 0.9, ay = 0.5, bx = 0.1, by = 0.5, cont = 1, wx = 905, wy = 250 }
end

-- opts.account: the account table. The player stands outside at (0.5, 0.5).
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    local account = opts.account or {}
    account.layout = account.layout or { arrowIntroSeen = true }
    c.setSaved(ns.id.accountDB, account)
    c.setSaved(ns.id.charDB, {})
    c.setZone(1, OUT); c.setPosition(OUT, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(OUT, 1000, 1000); c.setMapCont(OUT, 1)
    c.setMapSize(CITY, 1000, 1000); c.setMapCont(CITY, 1)
    c.setClass("WARRIOR"); c.setFaction("Horde"); c.setLevel(20)
    local db, zones = questie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    c.setQuestLog({ { id = 304, title = "Rats", objectives = { { text = "Rats slain: 0/6" } } } })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

local function lines(c)
    local a = c.arrows[1]
    return a and a.lines or {}
end

local function hasPrefix(list, prefix)
    for _, l in ipairs(list) do
        if type(l) == "string" and l:sub(1, #prefix) == prefix then return true end
    end
    return false
end

local function learned(c)
    local a = c.saved(ns.id.accountDB)
    local l = type(a) == "table" and a.learned
    local p = type(l) == "table" and l.places
    return type(p) == "table" and p.gates or nil
end

-- One walk: stand at (map, x, y) / world (wx, wy) for a second of ticks.
local function stand(c, map, x, y, wx, wy)
    c.setPosition(map, x, y)
    c.setWorldPosition(1, wx, wy)
    c.advance(1, 4)
end

tests["gates: a learned gate turns the arrow to it, then the quest"] = function(t)
    local c, addon = boot({ account = { learned = { places = { gates = { gate() } } } } })
    t.eq(addon.use(Gates.NAME).Count(), 1, "one gate known")
    local l = lines(c)
    t.eq(c.arrows[1] and c.arrows[1].shown, true, "the quest arrow is shown")
    t.eq(l[1], "Way to Orgrimmar")
    t.eq(l[2], Travel.THEN:format("Rats"))
    -- Inside the walls the quest is on the player's map: no gate step.
    c.setZone(1, CITY); c.setPosition(CITY, 0.4, 0.5)
    c.fire("ZONE_CHANGED_NEW_AREA")
    c.advance(10, 40)
    t.eq(lines(c)[1], "Rats", "same map: the quest itself")
end

tests["gates: walking in through the gate learns it, and the arrow uses it"] = function(t)
    local c, addon = boot()
    c.setOnTaxi(false)
    stand(c, OUT, 0.9, 0.5, 900, 250)
    stand(c, CITY, 0.1, 0.5, 905, 250)
    t.eq(learned(c), { gate() }, "the gate is saved with both sides")
    t.eq(addon.use(Gates.NAME).Count(), 1)
    -- Walking out again is not a second gate.
    stand(c, OUT, 0.9, 0.5, 900, 250)
    t.eq(#(learned(c) or {}), 1, "still one gate")
    c.setZone(1, OUT); c.setPosition(OUT, 0.5, 0.5)
    c.fire("ZONE_CHANGED_NEW_AREA")
    c.advance(10, 40)
    t.eq(lines(c)[1], "Way to Orgrimmar")
end

tests["gates: a flight or a jump across the world is not a gate"] = function(t)
    local c = boot()
    c.setOnTaxi(true)
    stand(c, OUT, 0.9, 0.5, 900, 250)
    stand(c, CITY, 0.1, 0.5, 905, 250)
    t.eq(learned(c), nil, "on a taxi: nothing learned")
    c.setOnTaxi(false)
    stand(c, OUT, 0.9, 0.5, 900, 250)
    stand(c, CITY, 0.1, 0.5, 4000, 250)
    t.eq(learned(c), nil, "a jump of thousands of yards: nothing learned")
end

tests["gates: unknown data says nothing wrong"] = function(t)
    local c, addon = boot()
    -- No world position and no taxi read: learning stays off.
    c.setPosition(OUT, 0.9, 0.5); c.advance(1, 4)
    c.setPosition(CITY, 0.1, 0.5); c.advance(1, 4)
    t.eq(learned(c), nil, "nothing learned")
    t.eq(addon.use(Gates.NAME).Count(), 0)
    c.setPosition(OUT, 0.5, 0.5)
    c.advance(10, 40)
    t.eq(lines(c)[1], "Rats", "no gate known: the quest itself")
    t.ok(not hasPrefix(lines(c), "Way to"), "no way is made up")
end

return tests
