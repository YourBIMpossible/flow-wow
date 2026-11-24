local _, ns = ...

-- End to end (N43, P-TRIP route display): the whole route on the world
-- map. A trip of two seen places is planned; both are pinned, the current
-- one in the route's role, with a line between; the setting off leaves the
-- current one only; the route cleared clears them. Made-up places; not
-- tested in game.

local tests = {}

local MAP = 1436

local function boot()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setFaction("Alliance"); c.setLevel(18)
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 0)
    c.setWorldMap(MAP)
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
    c.advance(2, 10)
end

-- The route's pins on the pin set drawn last that has any, and that set.
local function routePins(c)
    for i = #c.mapPinSets, 1, -1 do
        local set = c.mapPinSets[i]
        local out = {}
        for _, p in ipairs(set.pins) do
            if p.role == ns.RouteTracker.PIN_ROLE or p.role == ns.RouteTracker.PIN_NEXT_ROLE then
                out[#out + 1] = p
            end
        end
        if #out > 0 then return out, set end
    end
    return {}, nil
end

tests["route map e2e: every stop is pinned, the current one first, joined by a line"] = function(t)
    local c, addon = boot()
    t.eq(addon.settings:get(ns.RouteTracker.MAP_SETTING), true, "on at first")
    local row = addon.settings:row(ns.RouteTracker.MAP_SETTING)
    t.eq(row and row.group, "travel.route")
    slash(c, "trip add vendor")
    slash(c, "trip add inn")
    slash(c, "trip go")
    local pins, set = routePins(c)
    t.eq(#pins, 2)
    t.eq(pins[1] and pins[1].role, ns.RouteTracker.PIN_ROLE)
    t.eq(pins[1] and pins[1].order, 1)
    t.eq(pins[2] and pins[2].role, ns.RouteTracker.PIN_NEXT_ROLE)
    t.eq(pins[2] and pins[2].order, 2)
    t.eq(set and #set.lines, 1)

    addon.settings:set(ns.RouteTracker.MAP_SETTING, false)
    c.advance(2, 10)
    pins = routePins(c)
    t.eq(#pins, 1, "off: the current stop only, as before")

    addon.settings:set(ns.RouteTracker.MAP_SETTING, true)
    c.advance(2, 10)
    slash(c, "route off")
    pins = routePins(c)
    t.eq(#pins, 0, "the route cleared clears the pins")
end

return tests
