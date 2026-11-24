local _, ns = ...

-- End to end (lead section 477, parity row A1-32): each flight is timed
-- from take-off to landing and kept per path; `/zflow flights` lists the
-- times flown. A path never flown shows no time. On the whole add-on with
-- a fake client; made-up places and names. Not tested in game.
-- Fails before: nothing times a flight, so no time line is said and
-- account learned.flights.times stays empty.

local tests = {}

local MAP = 1436
local NODES = {
    Stonegate = { cont = 0, wx = 100, wy = 100 },
    Rivermouth = { cont = 0, wx = 2100, wy = 100 },
}

local function boot()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
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

local function fly(c, seconds, landX)
    c.setOnTaxi(true); c.advance(2, 4)
    c.setWorldPosition(0, 1000, 100); c.advance(seconds - 2, 20)
    c.setWorldPosition(0, landX or 2090, 100); c.setOnTaxi(false); c.advance(2, 4)
end

local function said(c)
    local out, prefix = {}, ns.id.title .. ": "
    for _, line in ipairs(c.printed or {}) do
        local s = tostring(line)
        if s:sub(1, #prefix) == prefix then s = s:sub(#prefix + 1) end
        out[#out + 1] = s
    end
    return out
end

local function flights(c)
    c.printed = {}
    c.slashes[ns.id.slash]("flights")
    return said(c)
end

local function has(list, line)
    for _, s in ipairs(list) do if s == line then return true end end
    return false
end

local function times(addon) return addon.store:get("account", "learned.flights.times") end

tests["flight times e2e: a flight is timed and /zflow flights says it"] = function(t)
    local c, addon = boot()
    fly(c, 90)
    local got = times(addon)
    local s = type(got) == "table" and got["Stonegate>Rivermouth"] or nil
    t.ok(type(s) == "number" and s >= 89 and s <= 92, tostring(s))
    local lines = flights(c)
    local T = ns.Nav.FlightTimes
    t.ok(T ~= nil and has(lines, T.HEADER), table.concat(lines, " | "))
    t.ok(T ~= nil and has(lines, T.LINE:format("Stonegate", "Rivermouth", s)), table.concat(lines, " | "))
end

tests["flight times e2e: a path never flown shows no time"] = function(t)
    local c, addon = boot()
    t.eq(times(addon), nil)
    for _, line in ipairs(flights(c)) do
        t.ok(not line:find(" s (your last flight)", 1, true), line)
    end
end

tests["flight times e2e: landing far from any saved point keeps nothing"] = function(t)
    local c, addon = boot()
    fly(c, 90, 1500)
    t.eq(times(addon), nil)
end

tests["flight times e2e: a flight already under way at login is not kept"] = function(t)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, { learned = { flights = { nodes = NODES } } })
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 0)
    c.setOnTaxi(true); c.setWorldPosition(0, 1000, 100)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(40, 40)
    c.setWorldPosition(0, 2090, 100); c.setOnTaxi(false); c.advance(2, 4)
    t.eq(addon.store:get("account", "learned.flights.times"), nil)
end

tests["flight times e2e: a newer flight replaces the old time"] = function(t)
    local c, addon = boot()
    fly(c, 90)
    c.setWorldPosition(0, 110, 100); c.advance(2, 4)
    fly(c, 60)
    local s = (times(addon) or {})["Stonegate>Rivermouth"]
    t.ok(type(s) == "number" and s >= 59 and s <= 62, tostring(s))
end

return tests
