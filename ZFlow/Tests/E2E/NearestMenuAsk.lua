local _, ns = ...

-- End to end (lead sections 628 and 638): the arrow menu's "Go to the
-- nearest..." rows ask Nav/Errand.lua E.Find the same way a click on one
-- does, with the module lookup handed in (k.use), so a row that is live is
-- one a click can follow and a greyed row is one it could not. E.Find is
-- replaced by a stand-in that knows a vendor only for a caller that hands
-- in the lookup, as Questie's places are (lead section 626). Made-up place;
-- not tested in game.

local MAP = 1429
local PLACE = { kind = "vendor", key = "made-up-vendor", map = MAP, x = 0.4, y = 0.4 }

local tests = {}

tests["nearest rows: the menu asks as the click does, so a live row is followed"] = function(t)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 0)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    local E = addon.Errand
    t.ok(type(E) == "table" and type(E.Find) == "function", "Nav/Errand.lua E.Find is there")
    if type(E) ~= "table" or type(E.Find) ~= "function" then return end
    local asks, withUse = 0, 0
    E.Find = function(kind, _, _, use)
        asks = asks + 1
        if type(use) ~= "function" then return nil end
        withUse = withUse + 1
        if kind == "vendor" then return PLACE end
        return nil
    end
    c.slashes[ns.id.slash]("arrow demo")
    c.advance(0.1, 2)
    local q = c.arrows[1]
    t.ok(q ~= nil, "an arrow to right-click")
    if not q then return end
    q.click("right")
    t.ok(asks > 0, "the menu asked E.Find")
    t.eq(withUse, asks, "every ask of the menu handed in the module lookup")
    t.eq(q.enter(ns.ArrowMenu.STEP), true, "the step row's level")
    t.eq(q.enter(ns.ArrowMenu.NEAREST), true, "the Go to the nearest... submenu")
    t.eq(q.pickRow(ns.ArrowMenu.NEAREST .. ".repair"), false, "no repair vendor: greyed, as a click would find none")
    t.eq(q.pickRow(ns.ArrowMenu.NEAREST .. ".vendor"), true, "the vendor row is live")
    local errand = addon.use("errand")
    t.ok(type(errand) == "table" and type(errand.Stop) == "function", "the errand module answers")
    if type(errand) ~= "table" or type(errand.Stop) ~= "function" then return end
    local stop = errand.Stop()
    t.ok(type(stop) == "table", "the click set an errand stop")
    if type(stop) ~= "table" then return end
    t.eq(stop.key, PLACE.key, "the click went to the place the row promised")
end

return tests
