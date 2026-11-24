local _, ns = ...

-- End to end (P-TRIP slice 2): the trip handed to the route is shown in the
-- quest arrow's tooltip: the current stop marked, the distance left. Z-Flow
-- has no route panel; the arrow's tooltip is the existing place that shows
-- the step. Made-up places; not tested in game.

local tests = {}

local MAP = 1436

local function boot()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setFaction("Alliance"); c.setLevel(18)
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 0)
    c.setQuestLog({})
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    addon.store:set("char", ns.Nav.SERVICES, {
        ["svc:1"] = { name = "Bob", map = MAP, x = 0.8, y = 0.5, kinds = { vendor = true } },
        ["svc:2"] = { name = "Inna", map = MAP, x = 0.5, y = 0.6, kinds = { innkeeper = true } },
    })
    return c, addon
end

local function slash(c, text)
    c.slashes[ns.id.slash](text)
    c.advance(1, 5)
end

local function tipOf(c)
    local a = c.arrows[1]
    if not a then return {} end
    a.hover(false)
    a.hover(true)
    return a.tipLines or {}
end

local function has(lines, a, b)
    for _, line in ipairs(lines) do
        if line:find(a, 1, true) and (b == nil or line:find(b, 1, true)) then return line end
    end
    return nil
end

tests["trip tip e2e: the quest arrow's tooltip shows the trip, the current stop marked"] = function(t)
    local c = boot()
    slash(c, "trip add vendor")
    slash(c, "trip add inn")
    slash(c, "trip go")
    local lines = tipOf(c)
    t.ok(has(lines, ns.Nav.Trip.TIP_NOW .. "Inn: Inna", "100 yd") ~= nil, table.concat(lines, " | "))
    t.ok(has(lines, ns.Nav.Trip.TIP_NEXT .. "Vendor: Bob", "316 yd") ~= nil, table.concat(lines, " | "))
    t.ok(has(lines, ns.Nav.Trip.TIP_HEADER:format(2, "416 yd")) ~= nil, table.concat(lines, " | "))
    c.setPosition(MAP, 0.5, 0.6)
    c.advance(2, 20)
    lines = tipOf(c)
    t.ok(has(lines, ns.Nav.Trip.TIP_NOW .. "Vendor: Bob") ~= nil, table.concat(lines, " | "))
    t.ok(has(lines, "Inn: Inna") == nil, "the passed stop is gone")
end

tests["trip tip e2e: no route, no trip lines in the tooltip"] = function(t)
    local c = boot()
    slash(c, "stop vendor")
    local lines = tipOf(c)
    t.ok(has(lines, ns.Nav.Trip.TIP_NOW) == nil, table.concat(lines, " | "))
end

return tests
