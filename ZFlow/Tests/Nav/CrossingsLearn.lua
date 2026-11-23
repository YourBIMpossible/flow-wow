local _, ns = ...

-- Tests for lead section 184 G2: the crossings module learns the player's
-- own trips. When the continent client.zone gives changes and the player
-- was not on a flight, N.CrossingSeen is called with the place before and
-- the place after, and the list it gives is saved in
-- learned.places.crossings. Only the player's own trips; no route data is
-- copied in. Made-up places; fake client. Not tested in game. Look only:
-- nothing boards, clicks or casts.

local N = ns.Nav
local C = N.Crossings
local tests = {}

-- A warrior at the Durotar tower (map 1411, continent 1), not on a flight.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.saved or {})
    if opts.char then c.setSaved(ns.id.charDB, opts.char) end
    c.setZone(1, 1411)
    c.setPosition(1411, 0.5, 0.1)
    c.setMapSize(1411, 1000, 500)
    c.setMapSize(1420, 1000, 1000)
    c.setClass("WARRIOR")
    c.setFaction("Horde")
    c.setOnTaxi(false)
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    local api = C.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api
end

local function saved(k)
    return k.store:get("account", N.CROSSING_PLACES)
end

-- Off the zeppelin at the Tirisfal tower (map 1420, continent 0).
local function land(c)
    c.setZone(0, 1420)
    c.setPosition(1420, 0.6, 0.6)
end

local function home(c)
    c.setZone(1, 1411)
    c.setPosition(1411, 0.5, 0.1)
end

tests["crossings learn: a continent change saves one crossing"] = function(t)
    local k, c, api = start()
    api.sample()
    land(c)
    api.sample()
    local list = saved(k)
    t.ok(type(list) == "table")
    t.eq(#list, 1)
    t.eq(list[1].key, "seen:1411:1420")
    t.eq(list[1].seen, 1)
    t.eq(list[1].a, { cont = 1, map = 1411, x = 0.5, y = 0.1 })
    t.eq(list[1].b, { cont = 0, map = 1420, x = 0.6, y = 0.6 })
    t.eq(k.problems:count(), 0)
end

tests["crossings learn: the tick samples by itself"] = function(t)
    local k, c = start()
    c.advance(C.EVERY, 1)
    land(c)
    c.advance(C.EVERY, 1)
    local list = saved(k)
    t.ok(type(list) == "table")
    t.eq(list and #list, 1)
end

tests["crossings learn: a flight does not"] = function(t)
    local k, c, api = start()
    c.setOnTaxi(true)
    api.sample()
    land(c)
    api.sample()
    t.eq(saved(k), nil, "on a flight both times")
    local k2, c2, api2 = start()
    c2.setOnTaxi(true)
    api2.sample()
    land(c2)
    c2.setOnTaxi(false)
    api2.sample()
    t.eq(saved(k2), nil, "on a flight before, landed after")
    local k3, c3, api3 = start()
    api3.sample()
    land(c3)
    c3.setOnTaxi(true)
    api3.sample()
    t.eq(saved(k3), nil, "on a flight after")
end

tests["crossings learn: a taxi read that is not known learns nothing"] = function(t)
    local k, c, api = start()
    c.setOnTaxi(nil)
    api.sample()
    land(c)
    api.sample()
    t.eq(saved(k), nil)
end

tests["crossings learn: the same trip twice keeps one entry"] = function(t)
    local k, c, api = start()
    api.sample()
    land(c)
    api.sample()
    c.setOnTaxi(nil)
    api.sample()
    home(c)
    c.setOnTaxi(false)
    api.sample()
    land(c)
    api.sample()
    local list = saved(k)
    t.eq(#list, 1)
    t.eq(list[1].key, "seen:1411:1420")
    t.eq(list[1].seen, 2)
    t.eq(k.problems:count(), 0)
end

tests["crossings learn: a place not known between keeps the place before"] = function(t)
    local k, c, api = start()
    api.sample()
    c.setPosition(nil)
    c.setZone(nil)
    api.sample()
    land(c)
    api.sample()
    t.eq(#saved(k), 1, "a loading screen between the two")
end

tests["crossings learn: a move on one continent saves nothing"] = function(t)
    local k, c, api = start()
    api.sample()
    c.setZone(1, 1412)
    c.setPosition(1412, 0.3, 0.3)
    api.sample()
    t.eq(saved(k), nil)
end

tests["crossings learn: a landing at the hearthstone home is not a crossing"] = function(t)
    local k, c, api = start({ char = { learned = { places = { bind = { name = "Brill", map = 1420, x = 0.6, y = 0.6 } } } } })
    api.sample()
    land(c)
    api.sample()
    t.eq(saved(k), nil)
end

tests["crossings learn: crossings already saved are kept"] = function(t)
    local other = { key = "boat", how = "boat", a = { cont = 1, map = 1413, x = 0.1, y = 0.1 }, b = { cont = 0, map = 1426, x = 0.2, y = 0.2 } }
    local k, c, api = start({ saved = { learned = { places = { crossings = { other } } } } })
    api.sample()
    land(c)
    api.sample()
    local list = saved(k)
    t.eq(#list, 2)
    t.eq(list[1], other)
    t.eq(list[2].key, "seen:1411:1420")
end

tests["crossings learn: two trips make a crossing Way gives"] = function(t)
    local k, c, api = start()
    api.sample()
    land(c)
    api.sample()
    c.setOnTaxi(nil)
    api.sample()
    home(c)
    c.setOnTaxi(false)
    api.sample()
    land(c)
    api.sample()
    home(c)
    c.setPosition(1411, 0.5, 0.5)
    local s = k.use(C.NAME).Way({ cont = 0, map = 1420, x = 0.6, y = 0.7 })
    t.ok(type(s) == "table")
    t.eq(s and s.place, { cont = 1, map = 1411, x = 0.5, y = 0.1 })
end

tests["crossings learn: nothing known saves nothing and logs no problem"] = function(t)
    local k, c, api = start()
    c.setZone(nil)
    c.setPosition(nil)
    api.sample()
    api.sample()
    t.eq(saved(k), nil)
    t.eq(k.problems:count(), 0)
end

return tests
