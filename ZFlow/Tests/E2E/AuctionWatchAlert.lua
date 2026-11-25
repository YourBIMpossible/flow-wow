local _, ns = ...

-- End to end (E-31, lead 681, 682): the whole add-on (ns.offline.addon) on a
-- fake client. The player watches an item with the short money form the
-- add-on prints; a search the player ran shows it under that mark; one chat
-- line and the alert sound follow, once a visit. Advice only: nothing
-- searches, posts, bids, buys or cancels. Made-up realm, item and prices.

local tests = {}

local function start()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setScreen(1024, 768)
    c.setClock(1700000000)
    c.setRealm("Realm1")
    c.setFaction("Horde")
    c.setItemInfo({ [2589] = { name = "Linen Cloth" } })
    ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c
end

local function T(s) return ns.id.title .. ": " .. s end

tests["auction watch e2e: a watched item under its mark alerts once a visit"] = function(t)
    local c = start()
    c.slashes[ns.id.slash]("ah watch item:2589 1.5s")
    t.eq(c.printed[#c.printed], T("watch: Linen Cloth, at or under 1.5s."))
    local before = #c.printed
    c.auctionResult(2589, { unitPrice = 140, quantity = 5 })
    c.auctionResult(2589, { unitPrice = 120, quantity = 5 })
    t.eq(c.printed[before + 1], T("watch: Linen Cloth is on the auction house for 1.4s each, at or under your 1.5s."))
    t.eq(#c.printed, before + 1, "once a visit")
    t.eq(#c.alertsPlayed(), 1, "the alert sound")
    c.slashes[ns.id.slash]("ah unwatch item:2589")
    t.eq(c.printed[#c.printed], T("watch: Linen Cloth dropped."))
end

return tests
