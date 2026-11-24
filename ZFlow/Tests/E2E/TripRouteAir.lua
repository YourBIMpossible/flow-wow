local _, ns = ...
-- The route says the "Quicker by air" line (parity row A1-19; lead sections
-- 488, 497, 522 and 541): under the route's list, when the arrow's step is
-- reached by a flight whose time was learned. A guessed time says nothing,
-- so an unknown stays unknown (section 497): that rule is Nav/AirLine.lua's
-- and is held here too. The flight itself is the mapFlights module's to
-- work out (Tests/E2E/AirLine.lua); here its answer is a stand-in, so this
-- file tests the route's part alone. Whole add-on on a fake client; made-up
-- quests and places. Not tested in game.
-- Red on 065ffdd9: the route word says no such line and the tripRoute
-- module has no AirLine.
local tests = {}

local MAP = 1436
local LINE = "Quicker by air: fly from Home Post to Far Post."

local function questie()
    local quests = {
        [401] = { ObjectiveData = { { Type = "monster", Id = 9101 } } },
        [403] = { ObjectiveData = {}, Finisher = { NPC = { 9103 } } },
    }
    local npcs = {
        [9101] = { name = "Boar", spawns = { [40] = { { 60, 50 } } } },
        [9103] = { name = "Smith", spawns = { [40] = { { 55, 50 } } } },
    }
    local db = {}
    function db.GetQuest(id) return quests[id] end
    function db.GetNPC(id) return npcs[id] end
    local zones = {}
    function zones.GetUiMapIdByAreaId(area) return ({ [40] = MAP })[area] end
    return db, zones
end

local LOG = {
    { id = 401, title = "Boars", objectives = { { text = "Boars slain: 0/4" } } },
    { id = 403, title = "Bandages", complete = true, objectives = { { text = "Linen: 4/4", done = true } } },
}

-- air: what the mapFlights module's AirLine answers (a function), or nil to
-- leave the module as it is.
local function boot(air)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setFaction("Alliance"); c.setLevel(18)
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 0)
    local db, zones = questie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    c.setQuestLog(LOG)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    if air then
        local flights = addon.use("mapFlights")
        if type(flights) == "table" then flights.AirLine = air end
    end
    return c, addon, addon.problems:count()
end

local function word(c, rest)
    local from = #c.printed
    c.slashes[ns.id.slash](rest)
    c.advance(1, 5)
    local out = {}
    for i = from + 1, #c.printed do out[#out + 1] = tostring(c.printed[i]) end
    return out
end

local function count(lines, text)
    local n = 0
    for _, line in ipairs(lines) do
        if line == text then n = n + 1 end
    end
    return n
end

local function index(lines, text)
    for i, line in ipairs(lines) do
        if line:find(text, 1, true) then return i end
    end
    return nil
end

-- Red on 065ffdd9: the line is not said.
tests["route air line: a learned flight is said once, under the route's list"] = function(t)
    local c, addon, base = boot(function() return LINE end)
    local lines = word(c, "route new")
    t.eq(count(lines, ns.id.title .. ": " .. LINE), 1, "the line, once")
    local list, air = index(lines, "1. Bandages"), index(lines, LINE)
    t.ok(list ~= nil and air ~= nil and air > list, "under the list")
    local trip = addon.use(ns.Nav.TripRoute.NAME)
    t.eq(trip and trip.AirLine and trip.AirLine(), LINE, "the module gives it to other faces too")
    t.eq(addon.problems:count(), base, "no new problem")
end

-- Lead section 497: only when the leg's time was learned.
tests["route air line: a guessed time says nothing, so an unknown stays unknown"] = function(t)
    local AL = ns.Nav.AirLine
    t.eq(AL.Words({ from = "Home Post", to = "Far Post", learned = true }), LINE, "learned: the line")
    t.eq(AL.Words({ from = "Home Post", to = "Far Post", learned = false }), nil, "guessed: nothing")
    t.eq(AL.Words({ from = "Home Post", to = "Far Post" }), nil, "not said to be learned: nothing")
    -- What the flights module answers for a guessed time is nil: the route says nothing.
    local c, addon = boot(function() return nil end)
    local lines = word(c, "route new")
    t.ok(index(lines, "1. Bandages") ~= nil, "the route is planned")
    t.eq(index(lines, "Quicker by air"), nil, "no air line")
    t.eq(addon.use(ns.Nav.TripRoute.NAME).AirLine(), nil)
end

tests["route air line: with no route there is no air line"] = function(t)
    local c, addon = boot(function() return LINE end)
    local trip = addon.use(ns.Nav.TripRoute.NAME)
    t.eq(trip.AirLine and trip.AirLine(), nil, "nothing planned: nothing said")
    word(c, "route new")
    t.eq(trip.AirLine(), LINE, "planned: said")
    local off = word(c, "route off")
    t.eq(index(off, "Quicker by air"), nil, "switching the route off says no air line")
    t.eq(trip.AirLine(), nil, "and there is none again")
end

-- Section 236: a read that raises, then recovers; an answer that comes later.
tests["route air line: a flights module that raises says nothing, then the line once it answers"] = function(t)
    local state = { mode = "raise" }
    local c, addon, base = boot(function()
        if state.mode == "raise" then error("flights not ready (test)") end
        if state.mode == "none" then return nil end
        return LINE
    end)
    local lines = word(c, "route new")
    t.ok(index(lines, "1. Bandages") ~= nil, "the route is still planned and listed")
    t.eq(index(lines, "Quicker by air"), nil, "raising: no air line")
    state.mode = "none"
    t.eq(index(word(c, "route new"), "Quicker by air"), nil, "no flight yet: no air line")
    state.mode = "line"
    t.eq(count(word(c, "route new"), ns.id.title .. ": " .. LINE), 1, "the flight is known later: said")
    t.eq(addon.problems:count(), base, "no new problem")
end

return tests
