local _, ns = ...

-- Tests for the crossings module in ZFlow/Nav/Crossings.lua (lead section
-- 182): k.use("crossings").Way(place), the provider Nav/Travel.lua asks for
-- a step on another continent. It answers with the boarding place of the
-- best crossing on the player's own continent, from the crossings saved in
-- learned.places.crossings. Made-up places and crossings; fake client. Not
-- tested in game. Look only: nothing boards, clicks or casts.

local N = ns.Nav
local C = N.Crossings
local T = N.Travel
local tests = {}

-- A Horde zeppelin from map 1411 on continent 1 to map 1420 on continent 0.
local function zeppelin()
    return {
        key = "zep", how = "zeppelin", faction = "Horde",
        a = { cont = 1, map = 1411, x = 0.5, y = 0.1, name = "Durotar tower" },
        b = { cont = 0, map = 1420, x = 0.6, y = 0.6, name = "Tirisfal tower" },
    }
end

-- A warrior in the middle of 1411 (1000 by 500 yards) on continent 1.
-- opts.list: the saved crossings (default one zeppelin); opts.where = false:
-- no position read; opts.faction; opts.travel: the travel module too.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    local list = opts.list
    if list == nil then list = { zeppelin() } end
    local saved = {}
    if list ~= false then saved.learned = { places = { crossings = list } } end
    c.setSaved(ns.id.accountDB, saved)
    c.setZone(1, 1411)
    if opts.where ~= false then c.setPosition(1411, 0.5, 0.5) end
    c.setMapSize(1411, 1000, 500)
    c.setMapSize(1420, 1000, 1000)
    c.setClass("WARRIOR")
    c.setFaction(opts.faction or "Horde")
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    local api = C.Declare(k)
    local travel = opts.travel and T.Declare(k, d) or nil
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api, travel
end

local function way(k, place)
    return k.use(C.NAME).Way(place)
end

tests["crossings module: started, and it provides Way"] = function(t)
    local k = start()
    t.eq(C.NAME, "crossings")
    t.eq((k:ModuleState(C.NAME)), "started")
    t.ok(type(k.use(C.NAME).Way) == "function")
end

tests["crossings module: a place on the same continent has no crossing"] = function(t)
    local k = start()
    t.eq(way(k, { cont = 1, map = 1411, x = 0.2, y = 0.2 }), nil)
    t.eq(way(k, { cont = 1, map = 1412, x = 0.2, y = 0.2 }), nil)
    t.eq(k.problems:count(), 0)
end

tests["crossings module: a place on another continent is the crossing on yours"] = function(t)
    local k = start()
    local s = way(k, { cont = 0, map = 1420, x = 0.6, y = 0.7 })
    t.ok(type(s) == "table")
    t.eq(s.kind, "crossing")
    t.eq(s.label, "Zeppelin to Tirisfal tower")
    t.eq(s.place, { cont = 1, map = 1411, x = 0.5, y = 0.1 })
    t.eq(s.radius, C.NEAR)
    t.eq(s.toCont, 0)
    t.eq(s.crossing, "zep")
    t.eq(s.lands, { cont = 0, map = 1420, x = 0.6, y = 0.6 })
    t.eq(k.problems:count(), 0)
end

tests["crossings module: no place gives nil"] = function(t)
    local k = start()
    t.eq(way(k, nil), nil)
    t.eq(way(k, "Undercity"), nil)
    t.eq(way(k, {}), nil)
    t.eq(way(k, { map = 1420, x = 0.6, y = 0.7 }), nil, "no continent: not guessed")
    t.eq(way(k, { cont = 0, map = 1420 }), nil, "no x and y")
    t.eq(k.problems:count(), 0)
end

tests["crossings module: where you are not known gives nil"] = function(t)
    local k = start({ where = false })
    t.eq(way(k, { cont = 0, map = 1420, x = 0.6, y = 0.7 }), nil)
end

tests["crossings module: no crossing known, or none for you, gives nil"] = function(t)
    t.eq(way((start({ list = false })), { cont = 0, map = 1420, x = 0.6, y = 0.7 }), nil, "none saved")
    t.eq(way((start({ list = {} })), { cont = 0, map = 1420, x = 0.6, y = 0.7 }), nil, "an empty list")
    t.eq(way((start({ faction = "Alliance" })), { cont = 0, map = 1420, x = 0.6, y = 0.7 }), nil, "Horde only")
    local away = zeppelin()
    away.a = { cont = 2, map = 1500, x = 0.5, y = 0.5 }
    t.eq(way((start({ list = { away } })), { cont = 0, map = 1420, x = 0.6, y = 0.7 }), nil, "not from your continent")
end

tests["crossings module: crossings imported from legacy, with no map place, are not used"] = function(t)
    local k = start({ list = { zep = { a = { cont = 1, wx = 10, wy = 20 }, b = { cont = 0, wx = 30, wy = 40 } } } })
    t.eq(way(k, { cont = 0, map = 1420, x = 0.6, y = 0.7 }), nil)
    t.eq(k.problems:count(), 0)
end

tests["crossings module: the place handed in is not changed"] = function(t)
    local k = start()
    local target = { cont = 0, map = 1420, x = 0.6, y = 0.7 }
    way(k, target)
    t.eq(target, { cont = 0, map = 1420, x = 0.6, y = 0.7 })
end

tests["crossings module: travel sends a step over the sea to the boarding place"] = function(t)
    local k, _, _, travel = start({ travel = true })
    local s = { label = "Kill bats", place = { cont = 0, map = 1420, x = 0.6, y = 0.7 } }
    local out, how = travel.via(s)
    t.eq(how, "crossing")
    t.eq(out.label, "Zeppelin to Tirisfal tower")
    t.eq(out.place, { cont = 1, map = 1411, x = 0.5, y = 0.1 })
    t.eq(out.detail, "Then: Kill bats")
    t.eq(k.problems:count(), 0)
end

tests["crossings module: travel leaves a step on your own continent alone"] = function(t)
    local _, _, _, travel = start({ travel = true })
    local s = { label = "Kill boars", place = { cont = 1, map = 1411, x = 0.6, y = 0.7 } }
    local out, how = travel.via(s)
    t.eq(how, nil)
    t.ok(out == s)
end

tests["crossings module: look only - nothing boards, clicks or casts"] = function(t)
    for name in pairs(C) do
        local n = tostring(name):lower()
        t.ok(not (n:find("board") or n:find("take") or n:find("click") or n:find("cast")), "no acting function: " .. n)
    end
end

return tests
