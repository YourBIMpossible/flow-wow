local _, ns = ...

-- End to end (lead section 477, parity row A1-33): `/zflow arrow status`
-- says in two lines what the quest arrow points at and why, then the
-- route's next stop. On the whole add-on with a fake client; made-up
-- places and names. Not tested in game.
-- Fails before: "status" is not an arrow word, so the usage line is said.

local tests = {}

local MAP = 1411

local function boot()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, {})
    c.setScreen(1024, 768)
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 500); c.setMapCont(MAP, 1)
    c.setClass("WARRIOR"); c.setFaction("Horde"); c.setLevel(20)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function said(c, rest)
    c.printed = {}
    c.slashes[ns.id.slash](rest)
    local out, prefix = {}, ns.id.title .. ": "
    for _, line in ipairs(c.printed) do
        local s = tostring(line)
        if s:sub(1, #prefix) == prefix then s = s:sub(#prefix + 1) end
        out[#out + 1] = s
    end
    return out
end

tests["arrow status e2e: a waypoint of your own, no route: two lines"] = function(t)
    local c = boot()
    said(c, "way 40 60 Camp")
    c.advance(2, 8)
    local WS = ns.Nav.WaypointStatus
    local lines = said(c, "arrow status")
    t.eq(#lines, 2, table.concat(lines, " | "))
    t.ok(lines[1] and lines[1]:find("your own waypoint", 1, true) ~= nil, tostring(lines[1]))
    t.eq(lines[2], WS and WS.NO_ROUTE)
end

tests["arrow status e2e: nothing to point at says so"] = function(t)
    local c = boot()
    local lines = said(c, "arrow status")
    t.eq(#lines, 2, table.concat(lines, " | "))
    t.ok(lines[1] and lines[1]:find("^Arrow: ") ~= nil, tostring(lines[1]))
end

tests["arrow status: the next stop is the one after the arrow's"] = function(t)
    local WS = ns.Nav.WaypointStatus
    t.eq(WS.Lines("Kill boars", "your route", { { label = "Kill boars" }, { label = "Hand in: Boars" } }),
        { "Arrow: Kill boars (from your route).", "Next stop: Hand in: Boars." })
    t.eq(WS.Lines("Kill boars", "your route", { { label = "Kill boars" } }),
        { "Arrow: Kill boars (from your route).", WS.LAST })
    t.eq(WS.Lines(nil, nil, nil), { "Arrow: no step now (from nothing).", WS.NO_ROUTE })
end

tests["arrow status: tripRoute Current() as given, stops inside"] = function(t)
    local WS = ns.Nav.WaypointStatus
    local current = { kind = "quests", label = "Route", stops = { { label = "Kill boars" }, { label = "Hand in: Boars" } } }
    t.eq(WS.Lines("Kill boars", "your route", current),
        { "Arrow: Kill boars (from your route).", "Next stop: Hand in: Boars." })
end

return tests
