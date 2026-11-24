local _, ns = ...

-- End to end (G43, P-TRIP): the route tracker window and the world-map pin
-- of the current step on the whole add-on with a fake client. A trip of
-- three seen places is planned; the window lists it, the current stop
-- marked; the pin moves on when the route does; the window empties when the
-- route clears and hides when its setting is off. Made-up places; not
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
    local extras = {}
    local real = c.kitWindow
    c.kitWindow = function(id, tree, extra)
        extras[id] = extra
        return real(id, tree, extra)
    end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    addon.store:set("char", ns.Nav.SERVICES, {
        ["svc:1"] = { name = "Bob", map = MAP, x = 0.8, y = 0.5, kinds = { vendor = true } },
        ["svc:2"] = { name = "Inna", map = MAP, x = 0.5, y = 0.6, kinds = { innkeeper = true } },
    })
    return c, addon, extras
end

local function slash(c, text)
    c.slashes[ns.id.slash](text)
    c.advance(2, 10)
end

local function window(c)
    return c.kitWindows()[ns.RouteTracker.ID]
end

local function part(c, key)
    local w = window(c)
    for _, p in ipairs(w and w.parts or {}) do
        if p.key == key then return p end
    end
    return nil
end

-- The route's pin: a pin of the route's role on any pin set drawn now.
local function pin(c)
    for i = #c.mapPinSets, 1, -1 do
        for _, p in ipairs(c.mapPinSets[i].pins) do
            if p.role == ns.RouteTracker.PIN_ROLE then return p end
        end
    end
    return nil
end

local function plan(c)
    slash(c, "trip add vendor")
    slash(c, "trip add inn")
    slash(c, "trip go")
end

tests["route tracker e2e: a planned trip shows the window, the current stop marked"] = function(t)
    local c, _, extras = boot()
    t.ok(not (window(c) and window(c).shown), "no window before a route")
    plan(c)
    t.eq(window(c) and window(c).shown, true)
    t.eq(part(c, "current") and part(c, "current").text, "Inn: Inna")
    t.eq(part(c, "next1") and part(c, "next1").text, "Vendor: Bob")
    local extra = extras[ns.RouteTracker.ID]
    t.eq(extra and extra.name, ns.id.framePrefix .. "Tracker", "named, so Escape closes it")
    t.eq(type(extra and extra.onMoved), "function")
end

tests["route tracker e2e: its place is saved when moved"] = function(t)
    local c, addon = boot()
    plan(c)
    t.ok(c.kitDrag(ns.RouteTracker.ID, { "TOPLEFT", "TOPLEFT", 40, -60 }, 300, 240), "dragged")
    local v = addon.store:get("account", ns.RouteTracker.PATH)
    t.eq(v and v.point, { "TOPLEFT", "TOPLEFT", 40, -60 })
end

tests["route tracker e2e: the map pin is the current stop and moves on with the route"] = function(t)
    local c = boot()
    plan(c)
    local p = pin(c)
    t.eq(p and p.name, "Inn: Inna")
    t.eq(p and { p.x, p.y }, { 0.5, 0.6 })
    c.setPosition(MAP, 0.5, 0.6)
    c.advance(2, 20)
    p = pin(c)
    t.eq(p and p.name, "Vendor: Bob", "at the inn: the pin moves to the vendor")
    t.eq(part(c, "current") and part(c, "current").text, "Vendor: Bob")
end

tests["route tracker e2e: the route cleared empties the window"] = function(t)
    local c = boot()
    plan(c)
    slash(c, "route off")
    local e = part(c, "empty")
    t.eq(e and e.text, ns.RouteTracker.EMPTY[1])
    t.eq(part(c, "current"), nil)
end

tests["route tracker e2e: the setting off hides it; the word opens it again"] = function(t)
    local c, addon = boot()
    plan(c)
    t.eq(addon.settings:get(ns.RouteTracker.SETTING), true, "on at first")
    local row = addon.settings:row(ns.RouteTracker.SETTING)
    t.eq(row and row.group, "travel.route")
    addon.settings:set(ns.RouteTracker.SETTING, false)
    c.advance(2, 10)
    t.eq(window(c).shown, false)
    addon.settings:set(ns.RouteTracker.SETTING, true)
    c.advance(2, 10)
    c.kitClose(ns.RouteTracker.ID)
    t.eq(window(c).shown, false, "closed by the player")
    slash(c, "tracker")
    t.eq(window(c).shown, true, "the word opens it again")
end

return tests
