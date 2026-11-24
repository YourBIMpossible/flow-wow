local _, ns = ...

-- End to end (G36): the auction house as a stop. The whole add-on on a fake
-- client: the player opens the auction house window at an auctioneer, walks
-- off, and `<slash> stop auction` points the arrow back at it. Nothing is
-- bought, posted or searched. Made-up places; not tested in game.

local tests = {}

local MAP = 1453

local function boot()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setFaction("Alliance"); c.setLevel(12)
    c.setZone(1, MAP); c.setPosition(MAP, 0.6, 0.7); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 0)
    c.setQuestLog({})
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

local function said(c)
    return table.concat(c.printed or {}, " | ")
end

tests["stop auction: nothing seen yet says so and changes nothing"] = function(t)
    local c, addon = boot()
    c.slashes[ns.id.slash]("stop auction")
    local out = said(c)
    t.ok(out:find("no auction you have seen is on this map", 1, true) ~= nil, out)
    t.eq(addon.store:get("char", ns.Nav.SERVICES), nil)
end

tests["stop auction: the window opened at an auctioneer is remembered, and the arrow points back at it"] = function(t)
    local c, addon = boot()
    c.setServiceNpc("Creature-0-1-0-0-9001-0000000001", "Auctioneer Test")
    c.fire("AUCTION_HOUSE_SHOW")
    c.advance(1, 4)
    local places = addon.store:get("char", ns.Nav.SERVICES)
    local seen
    for _, p in pairs(type(places) == "table" and places or {}) do
        if type(p.kinds) == "table" and p.kinds.auction then seen = p end
    end
    t.ok(seen ~= nil, "the auctioneer is kept as a place")
    t.eq(seen and seen.name, "Auctioneer Test")

    c.setServiceNpc(nil, nil)
    c.setPosition(MAP, 0.5, 0.7)
    c.advance(1, 4)
    c.slashes[ns.id.slash]("stop auction")
    local out = said(c)
    t.ok(out:find("the arrow points at Auction house Auctioneer Test (100 yd)", 1, true) ~= nil, out)
    c.advance(1, 4)
    local shown
    for _, a in ipairs(c.arrows or {}) do
        if a.shown then shown = a end
    end
    t.ok(shown ~= nil, "an arrow is shown")
end

tests["stop: the help line names the auction house"] = function(t)
    local c = boot()
    c.slashes[ns.id.slash]("stop nonsense")
    local out = said(c)
    t.ok(out:find("auction", 1, true) ~= nil, out)
end

return tests
