local _, ns = ...

-- End to end (lead section 481, parity row A1-18): while on a flight the
-- arrow's words say "On a flight", and what the route advised from the
-- flight point left: where that flight goes and the time it took last
-- (Nav/FlightTimes.lua). The player picks the destination on the flight map
-- and the add-on has no read of that pick, so the advised flight is said as
-- advice and never as "Flying to <place>"; a time never learned stays
-- unknown. On the whole add-on with a fake client; made-up places and
-- names. Not tested in game.
-- Fails before: the advised destination was said as a fact ("Flying to
-- Rivermouth", "landing in ~1m 00s") though the player may have picked
-- another flight.

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

-- The route advised the flight Stonegate to Rivermouth: what flights
-- Last() answers after api.way found it (its provides table, by reference).
local function plan(addon)
    local flights = addon.use("flights")
    if flights then flights.Last = function() return { from = "Stonegate", to = "Rivermouth" } end end
end

local function now(addon)
    local mod = addon.use("flightNow")
    return mod and mod.Now() or nil
end

local ADVICE = "The route's flight from here goes to Rivermouth"

-- No line may say a destination as a fact.
local function noFact(t, got)
    t.ok(got.title:find("Flying to", 1, true) == nil, got.title)
    t.ok(got.sub:find("Flying to", 1, true) == nil, got.sub)
    t.ok(got.sub:find("landing in", 1, true) == nil, got.sub)
end

tests["flight now e2e: the advised flight is said as advice, never as Flying to"] = function(t)
    local c, addon = boot({ ["Stonegate>Rivermouth"] = 90 })
    plan(addon)
    c.setOnTaxi(true); c.advance(30, 30)
    local got = now(addon)
    t.ok(got ~= nil, "the flight has words")
    if not got then return end
    t.eq(got.title, "On a flight")
    t.eq(got.sub, ADVICE .. ", ~1m 30s if that is yours")
    noFact(t, got)
end

tests["flight now e2e: the learned time is the whole flight, not a countdown"] = function(t)
    local c, addon = boot({ ["Stonegate>Rivermouth"] = 90 })
    plan(addon)
    c.setOnTaxi(true); c.advance(10, 10)
    local first = now(addon)
    c.advance(40, 40)
    local later = now(addon)
    t.ok(first ~= nil and later ~= nil, "the flight has words")
    if not first or not later then return end
    t.eq(first.sub, ADVICE .. ", ~1m 30s if that is yours")
    t.eq(later.sub, first.sub, "the same words the whole flight")
end

tests["flight now e2e: an advised path never flown says no time"] = function(t)
    local c, addon = boot(nil)
    plan(addon)
    c.setOnTaxi(true); c.advance(10, 10)
    local got = now(addon)
    t.ok(got ~= nil, "the flight has words")
    if not got then return end
    t.eq(got.title, "On a flight")
    t.eq(got.sub, ADVICE)
    noFact(t, got)
end

tests["flight now e2e: with no advised flight it is only a flight"] = function(t)
    local c, addon = boot({ ["Stonegate>Rivermouth"] = 90 })
    c.setOnTaxi(true); c.advance(10, 10)
    local got = now(addon)
    t.eq(got and got.title, "On a flight")
    t.eq(got and got.sub, "landing time not known yet")
end

tests["flight now e2e: a flight advised from another point is not said"] = function(t)
    local c, addon = boot({ ["Rivermouth>Stonegate"] = 90 })
    local flights = addon.use("flights")
    if flights then flights.Last = function() return { from = "Rivermouth", to = "Stonegate" } end end
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

tests["flight now e2e: the next step is said after the advice"] = function(t)
    local FN = ns.Nav.FlightNow
    local title, sub = FN.Words("Rivermouth", 50, "Wolf Pelts")
    t.eq(title, "On a flight")
    t.eq(sub, ADVICE .. ", ~50s if that is yours, then: Wolf Pelts")
    title, sub = FN.Words(nil, nil, "Wolf Pelts")
    t.eq(title, "On a flight")
    t.eq(sub, "landing time not known yet, then: Wolf Pelts")
end

tests["flight now e2e: no words can say Flying to a place"] = function(t)
    local FN = ns.Nav.FlightNow
    t.eq(FN.TO, nil, "no Flying to words are kept")
    t.eq(FN.LANDING, nil, "no landing countdown words are kept")
    local cases = {
        { "Rivermouth", 50, "Wolf Pelts" }, { "Rivermouth", 50, nil }, { "Rivermouth", nil, nil },
        { nil, 50, nil }, { nil, nil, nil }, { "", 50, "" }, { 7, "x", 9 },
    }
    for i = 1, #cases do
        local title, sub = FN.Words(cases[i][1], cases[i][2], cases[i][3])
        t.eq(title, "On a flight", "case " .. i)
        t.ok(type(sub) == "string" and sub:find("Flying to", 1, true) == nil, "case " .. i)
    end
    -- A time with no advised flight is a time for nothing: not said.
    local _, bare = FN.Words(nil, 50, nil)
    t.eq(bare, "landing time not known yet")
end

tests["flight now e2e: the learned time of a path, or nil"] = function(t)
    local FN = ns.Nav.FlightNow
    t.ok(type(FN.Total) == "function", "FN.Total is there")
    if type(FN.Total) ~= "function" then return end
    local times = { ["Stonegate>Rivermouth"] = 90, ["A>B"] = 0, ["C>D"] = "soon" }
    t.eq(FN.Total(times, "Stonegate", "Rivermouth"), 90)
    t.eq(FN.Total(times, "Rivermouth", "Stonegate"), nil, "the other way is another path")
    t.eq(FN.Total(times, "A", "B"), nil, "no time")
    t.eq(FN.Total(times, "C", "D"), nil, "not a number")
    t.eq(FN.Total(times, nil, "Rivermouth"), nil, "no take-off point")
    t.eq(FN.Total(times, "Stonegate", nil), nil, "no advised flight")
    t.eq(FN.Total(nil, "Stonegate", "Rivermouth"), nil, "nothing learned")
end

return tests
