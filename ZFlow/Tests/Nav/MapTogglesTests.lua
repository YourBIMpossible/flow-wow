local _, ns = ...

-- Tests for ZFlow/Nav/MapToggles.lua (FLOW-PARITY B-13, B-14; lead section
-- 843.2, plan accepted 846.4): the world map button's menu has a switch for
-- the flight masters on the map (as Flow's MapFlights.lua button, :615-688)
-- and one for the route on the map (as Flow's MapOverlay.lua route button,
-- :1261-1292). The state is the settings the drawing already reads:
-- nav.mapFlights (MapFlights) and nav.mapTrail (MapRouteLines). Fails
-- before: there is no MapToggles. Fake client; not tested in game.

local tests = {}

local function MT() return ns.MapToggles end

local function start()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    local k = ns.Kernel({}, c)
    ns.MapFlights.Declare(k)
    ns.MapRouteLines.Declare(k)
    ns.RouteList.Declare(k)
    local api = MT().Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    return k, api
end

local function row(items, key)
    for _, r in ipairs(items) do
        if r.key == key then return r end
    end
    return nil
end

tests["map toggles B-13 B-14: two menu rows, checked as the switches are"] = function(t)
    t.eq(type(MT()), "table")
    if type(MT()) ~= "table" then return end
    local items = MT().Items(true, false)
    t.eq(#items, 2)
    t.eq(row(items, MT().FLIGHTS).checked, true)
    t.eq(row(items, MT().ROUTE).checked, false)
    t.eq(type(row(items, MT().FLIGHTS).text), "string")
end

tests["map toggles B-13 B-14: the switches are the settings the map drawing reads"] = function(t)
    if type(MT()) ~= "table" then return t.ok(false, "no MapToggles") end
    local k, api = start()
    t.eq(api.FlightsShown(), false, "flight pins off as made (nav.mapFlights)")
    t.eq(api.RouteShown(), true, "route on as made (nav.mapTrail)")
    api.SetRoute(false)
    t.eq(k.settings:get(ns.MapRouteLines.TRAIL_SETTING), false)
    t.eq(row(api.MenuItems(), MT().ROUTE).checked, false)
    t.eq(api.Toggle(MT().FLIGHTS), true, "a click on the flights row turns them on")
    t.eq(k.settings:get(ns.MapFlights.SETTING), true)
    t.eq(api.Toggle(MT().ROUTE), true)
    t.eq(api.RouteShown(), true)
    t.eq(api.Toggle("nope"), nil, "not one of ours")
    t.ok(type(k.use("mapToggles")) == "table", "provided")
end

-- B-13 CHANGES-1 (Plexy, lead section 852.5): the route lines are drawn only
-- while the route panel (nav.routePanel) is on as well, so with the panel off
-- the route switch reads off even with nav.mapTrail on.
tests["map toggles B-13: the route reads off while the route panel is off"] = function(t)
    if type(MT()) ~= "table" then return t.ok(false, "no MapToggles") end
    local k, api = start()
    t.eq(k.settings:get(ns.MapRouteLines.TRAIL_SETTING), true)
    k.settings:set(ns.RouteList.SETTING, false)
    t.eq(api.RouteShown(), false, "panel off: route off")
    t.eq(row(api.MenuItems(), MT().ROUTE).checked, false)
    k.settings:set(ns.RouteList.SETTING, true)
    t.eq(api.RouteShown(), true, "both on: route on")
end

return tests
