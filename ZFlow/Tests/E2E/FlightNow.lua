local _, ns = ...

-- End to end (lead section 481, parity row A1-18): while on a flight the
-- arrow's words say where it lands and when, from the time that path took
-- last (Nav/FlightTimes.lua); a time never learned stays unknown. On the
-- whole add-on with a fake client; made-up places and names. Not tested
-- in game.
-- Fails before: there is no flightNow module, so nothing says the flight.

local tests = {}

local MAP = 1436
local NODES = {
    Stonegate = { cont = 0, wx = 100, wy = 100 },
    Rivermouth = { cont = 0, wx = 2100, wy = 100 },
}

local function boot(times)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, times and { learned = { flights = { times = times } } } or {})
    c.setSaved(ns.id.charDB, { learned = { flights = { nodes = NODES } } })
    c.setClass("WARRIOR"); c.setFaction("Alliance"); c.setLevel(18)
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 0)
    c.setOnTaxi(false); c.setWorldPosition(0, 110, 100)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

-- The route planned the flight Stonegate to Rivermouth: what flights
-- Last() answers after api.way found it (its provides table, by reference).
local function plan(addon)
    local flights = addon.use("flights")
    if flights then flights.Last = function() return { from = "Stonegate", to = "Rivermouth" } end end
end

local function now(addon)
    local mod = addon.use("flightNow")
    return mod and mod.Now() or nil
end

tests["flight now e2e: a flight flown before says where and when it lands"] = function(t)
    local c, addon = boot({ ["Stonegate>Rivermouth"] = 90 })
    plan(addon)
    c.setOnTaxi(true); c.advance(30, 30)
    local got = now(addon)
    local FN = ns.Nav.FlightNow
    t.ok(got ~= nil and FN ~= nil, "the flight has words")
    if not got then return end
    t.eq(got.title, "Flying to Rivermouth")
    t.ok(got.sub:find("^landing in ~") ~= nil, got.sub)
    local left = tonumber(got.sub:match("~(%d+)s"))
    t.ok(left ~= nil and left >= 58 and left <= 62, got.sub)
end

tests["flight now e2e: a path never flown keeps its landing time unknown"] = function(t)
    local c, addon = boot(nil)
    plan(addon)
    c.setOnTaxi(true); c.advance(10, 10)
    local got = now(addon)
    t.ok(got ~= nil, "the flight has words")
    if not got then return end
    t.eq(got.title, "Flying to Rivermouth")
    t.eq(got.sub, "landing time not known yet")
end

tests["flight now e2e: with no planned flight it is only a flight"] = function(t)
    local c, addon = boot({ ["Stonegate>Rivermouth"] = 90 })
    c.setOnTaxi(true); c.advance(10, 10)
    local got = now(addon)
    t.eq(got and got.title, "On a flight")
    t.eq(got and got.sub, "landing time not known yet")
end

tests["flight now e2e: on the ground, and after landing, there are no flight words"] = function(t)
    local c, addon = boot({ ["Stonegate>Rivermouth"] = 90 })
    plan(addon)
    t.eq(now(addon), nil, "on the ground")
    c.setOnTaxi(true); c.advance(10, 10)
    c.setWorldPosition(0, 2090, 100); c.setOnTaxi(false); c.advance(2, 4)
    t.eq(now(addon), nil, "landed")
end

tests["flight now e2e: the next step is said after the landing time"] = function(t)
    local title, sub = ns.Nav.FlightNow.Words("Rivermouth", 50, "Wolf Pelts")
    t.eq(title, "Flying to Rivermouth")
    t.eq(sub, "landing in ~50s, then: Wolf Pelts")
end

return tests
