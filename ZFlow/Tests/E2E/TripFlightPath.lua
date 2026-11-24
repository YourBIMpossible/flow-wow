local _, ns = ...

-- End to end (lead section 398 item 5): the flight path still to learn as a
-- route stop. The player says `trip add flightpath`; the nearest flight
-- master on this map whose path this character lacks (Nav/FlightPaths.lua
-- FP.Step, through the module's Step) becomes a trip stop, and `trip go`
-- hands it to the route the quest arrow walks: "Learn the flight path:
-- <name>". Made-up places and names; not tested in game.
--
-- Red before the code: "flightpath" is no trip stop kind, so the add is
-- refused and nothing is on the arrow.

local tests = {}

local MAP = 1436

local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setFaction("Alliance"); c.setLevel(18)
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 0)
    c.setQuestLog({})
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    addon.store:set("account", ns.FlightPaths.NPCS, {
        Karos = { map = MAP, x = 0.6, y = 0.5, roles = { flight = true }, factions = { Alliance = true } },
        Dalin = { map = MAP, x = 0.9, y = 0.9, roles = { flight = true }, factions = { Alliance = true } },
    })
    if opts.talked then addon.store:set("char", ns.FlightPaths.TALKED, opts.talked) end
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

local function first(c)
    local a = c.arrows[1]
    return a and a.lines and a.lines[1]
end

tests["trip flight path e2e: trip add flightpath, trip go: the arrow says learn the nearest one"] = function(t)
    local c, addon = boot()
    slash(c, "trip add flightpath")
    t.ok(said(c, "Added stop 1: Learn the flight path: Karos."), "the nearer master")
    local v = addon.store:get("char", ns.Nav.Trip.PATH)
    local stop = type(v) == "table" and v.stops and v.stops[1] or {}
    t.eq(stop.place, { map = MAP, x = 0.6, y = 0.5 })
    slash(c, "trip go")
    t.eq(first(c), "Learn the flight path: Karos", "the arrow walks to it")
end

tests["trip flight path e2e: every path here learned: not added, said plainly"] = function(t)
    local c, addon = boot({ talked = { Karos = true, Dalin = true } })
    slash(c, "trip add flightpath")
    t.ok(said(c, ns.Nav.Trip.NO_FLIGHTPATH), "nothing to learn on this map")
    local v = addon.store:get("char", ns.Nav.Trip.PATH)
    t.eq(type(v) == "table" and v.stops and #v.stops or 0, 0)
end

tests["trip flight path e2e: the setting off: no flight path stop"] = function(t)
    local c, addon = boot()
    addon.settings:set(ns.FlightPaths.SETTING, false)
    slash(c, "trip add flightpath")
    t.ok(said(c, ns.Nav.Trip.NO_FLIGHTPATH), "off reads as nothing to learn")
end

return tests
