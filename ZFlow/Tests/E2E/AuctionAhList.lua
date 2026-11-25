local _, ns = ...

-- End to end (E-33): the whole add-on (ns.offline.addon) on a fake client.
-- Bare `ah` lists the watch list with the last price seen in the player's
-- own searches, as the legacy /flow ah did
-- (Flow d78839f7 Modules/Items/Auction.lua:224-235): a heading, one line an
-- item, then the words. Advice only: nothing searches, posts, bids, buys or
-- cancels. Made-up realm, items and prices.

local tests = {}

local function start()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setScreen(1024, 768)
    c.setClock(1700000000)
    c.setRealm("Realm1")
    c.setFaction("Horde")
    c.setItemInfo({ [2589] = { name = "Linen Cloth" }, [2592] = { name = "Wool Cloth" } })
    ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c
end

local function T(s) return ns.id.title .. ": " .. s end

tests["auction ah e2e: bare ah lists watched items with the last price seen"] = function(t)
    local c = start()
    c.slashes[ns.id.slash]("ah watch item:2589 1.5s")
    c.slashes[ns.id.slash]("ah watch item:2592")
    c.auctionResult(2589, { unitPrice = 140, quantity = 5 })
    c.fire("AUCTION_HOUSE_CLOSED")
    local before = #c.printed
    c.slashes[ns.id.slash]("ah")
    t.eq(c.printed[before + 1], T("watch: auction watch list, last price seen:"))
    t.eq(c.printed[before + 2], T("watch: Linen Cloth: 1.4s each, under your 1.5s."))
    t.eq(c.printed[before + 3], T("watch: Wool Cloth: not seen in your searches yet."))
    t.eq(c.printed[before + 4], T("watch: ah watch <item> [price] | ah unwatch <item> | ah (the list). It buys nothing."))
    t.eq(#c.printed, before + 4)
end

return tests
