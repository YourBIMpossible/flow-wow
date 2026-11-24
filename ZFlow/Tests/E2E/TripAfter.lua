local _, ns = ...

-- End to end (G42, P-TRIP slice 3): "trip after" on the whole add-on, and a
-- trip stop on another continent reached through a learned boat: the list
-- says "via" the boat and the arrow's step for that leg is the boat's.
-- Made-up places and crossing; not tested in game.

local tests = {}

local function boat()
    return { key = "boat", how = "boat", seen = 2,
             a = { cont = 1, map = 1411, x = 0.5, y = 0.1, name = "Durotar dock" },
             b = { cont = 0, map = 1420, x = 0.6, y = 0.6, name = "Tirisfal dock" } }
end

local function start()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { learned = { places = { crossings = { boat() } } } })
    c.setSaved(ns.id.charDB, {})
    c.setZone(1, 1411); c.setPosition(1411, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(1411, 1000, 500); c.setMapCont(1411, 1)
    c.setMapSize(1420, 1000, 1000); c.setMapCont(1420, 0)
    c.setMapCorners(1411, { cont = 1, ox = 1000, oy = 2000, ex = 0, ey = -1000, sx = -500, sy = 0 })
    c.setMapCorners(1420, { cont = 0, ox = 1000, oy = 1000, ex = 0, ey = -1000, sx = -1000, sy = 0 })
    c.setClass("WARRIOR"); c.setFaction("Horde"); c.setLevel(20)
    c.setOnTaxi(false)
    c.setQuestLog({})
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

local function slash(c, text)
    c.slashes[ns.id.slash](text)
    c.advance(1, 5)
end

local function said(c, text)
    for _, line in ipairs(c.printed or {}) do
        if tostring(line):find(text, 1, true) then return line end
    end
    return nil
end

local function at(c, zoneCont, map, x, y)
    c.setZone(zoneCont, map); c.setPosition(map, x, y)
    c.advance(1, 5)
end

-- Camp here on 1411; Mail over the sea on 1420.
-- Test was wrong: the slash handler (Core/Diag.lua) lowers the whole line, so
-- "trip add here Camp" saves the label "camp"; the labels are typed lower here.
local function twoStops(c)
    at(c, 1, 1411, 0.5, 0.6)
    slash(c, "trip add here camp")
    at(c, 0, 1420, 0.3, 0.3)
    slash(c, "trip add here mail")
    at(c, 1, 1411, 0.5, 0.5)
end

tests["trip after e2e: the owner sets an after and the route obeys it"] = function(t)
    local c, addon = start()
    twoStops(c)
    slash(c, "trip after 1 2")
    t.ok(said(c, ns.Nav.Trip.AFTER_SET:format(1, "camp", 2, "mail")) ~= nil, "said what was set")
    local v = addon.store:get("char", ns.Nav.Trip.PATH)
    t.ok(type(v) == "table" and type(v.stops[1].after) == "table", "saved with the stop")
    slash(c, "trip go")
    local a = c.arrows[1]
    t.eq(a and a.lines and a.lines[1], "Boat to Tirisfal dock", "Mail first, by way of the boat")
    t.eq(a and a.lines and a.lines[2], "Then: mail")
end

tests["trip after e2e: a circle is refused with one line naming the stops"] = function(t)
    local c = start()
    twoStops(c)
    slash(c, "trip after 1 2")
    slash(c, "trip after 2 1")
    local line = said(c, ns.Nav.Trip.CIRCLE_WORD)
    t.ok(line ~= nil and line:find("camp", 1, true) ~= nil and line:find("mail", 1, true) ~= nil, tostring(line))
end

tests["trip via e2e: a stop on another continent is listed via the boat"] = function(t)
    local c = start()
    twoStops(c)
    slash(c, "trip")
    local line = said(c, "2. mail")
    t.ok(line ~= nil and line:find("via Boat to Tirisfal dock", 1, true) ~= nil, tostring(line))
    slash(c, "trip go")
    local a = c.arrows[1]
    t.eq(a and a.lines and a.lines[1], "camp", "this map first, as before")
end

return tests
