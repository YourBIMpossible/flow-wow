-- S4 auction prices on item tooltips (Items/AuctionLog.lua; legacy Flow's
-- Modules/Items/Auction.lua history rules). Fake client only.
local _, ns = ...

local AL = ns.AuctionLog
local tests = {}
local DAY = 86400
local REALM = "Old Blanchy-Horde"

tests["auction log: the price for one, as legacy Flow read it"] = function(t)
    t.eq(AL.UnitFrom({ unitPrice = 50 }), 50)
    t.eq(AL.UnitFrom({ buyoutAmount = 300, quantity = 3 }), 100)
    t.eq(AL.UnitFrom({ unitPrice = 0 / 0, buyoutAmount = 200 }), 200, "no quantity: one")
    t.eq(AL.UnitFrom({ buyoutAmount = 0 }), nil)
    t.eq(AL.UnitFrom(nil), nil)
end

tests["auction log: one point a visit, the cheapest of it, thinned at the far end"] = function(t)
    local h = {}
    AL.AddPoint(h, 100, 1000)
    AL.AddPoint(h, 90, 1300)
    t.eq(h, { 1000, 90 }, "ten minutes apart: one visit, the cheapest stands")
    AL.AddPoint(h, 120, 2000)
    t.eq(h, { 1000, 90, 2000, 120 })
    local thin = {}
    for i = 1, 5 do AL.AddPoint(thin, i, (i - 1) * 1000, 4, 1) end
    t.eq(thin, { 0, 1, 2000, 3, 3000, 4, 4000, 5 }, "past four points every other one of the older half goes")
end

tests["auction log: the realm key, as legacy Flow wrote it"] = function(t)
    t.eq(AL.RealmKey("Old Blanchy", "Horde"), REALM)
    t.eq(AL.RealmKey("A.B", nil), "A_B-?")
    t.eq(AL.RealmKey(nil, "Horde"), nil)
end

tests["auction log: the probe says what the client has and lacks"] = function(t)
    local lines = AL.ProbeLines(function(n) return n == "C_AuctionHouse" or n == "GetRealmName" end)
    t.eq(lines[1], "auction probe: has C_AuctionHouse, GetRealmName")
    t.eq(lines[2], "auction probe: lacks C_AuctionHouse.GetCommoditySearchResultInfo, C_AuctionHouse.GetItemSearchResultInfo, "
        .. "C_AuctionHouse.GetNumCommoditySearchResults, C_AuctionHouse.GetNumItemSearchResults, "
        .. "C_AuctionHouse.SendSearchQuery, C_AuctionHouse.MakeItemKey, C_AuctionHouse.ReplicateItems, QueryAuctionItems")
end

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    if not opts.noRealm then c.setRealm("Old Blanchy") end
    c.setFaction("Horde")
    c.setClock(1000)
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    local api = AL.Declare(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api
end

local function texts(lines)
    local out = {}
    for i, l in ipairs(lines) do out[i] = l.text end
    return out
end

tests["auction log module: a search the player ran is kept, and its tooltip grows with each visit"] = function(t)
    local k, c, api = start()
    c.auctionResult(2589, { unitPrice = 12 })
    t.eq(api.looks(), 1)
    t.eq(k.store:get("account", AL.PATH .. "." .. REALM), { [2589] = { h = { 1000, 12 } } })
    local lines = c.showItemTooltip("item:2589")
    t.eq(texts(lines), { "Auction: 12c each, 0 min ago" })
    t.eq({ lines[1].r, lines[1].g, lines[1].b }, AL.COLOUR)
    c.setClock(1000 + 3 * DAY)
    c.auctionResult(2589, { buyoutAmount = 30, quantity = 2 })
    t.eq(texts(c.showItemTooltip("item:2589")), {
        "Auction: 15c each, 0 min ago",
        "Low 12c, high 15c, average 14c: 2 looks over 3 days, up 25%",
    })
    t.eq(texts(c.showItemTooltip("item:2318")), {}, "no look: no line")
end

tests["auction log module: no price, no realm or switched off keeps and shows nothing"] = function(t)
    local k, c, api = start()
    c.auctionResult(2589, { quantity = 1 })
    t.eq(api.looks(), 0)
    c.auctionResult(2589, { unitPrice = 12 })
    t.eq(k.settings:set(AL.SETTING, false), true)
    t.eq(texts(c.showItemTooltip("item:2589")), {})
    local k2, c2, api2 = start({ noRealm = true })
    c2.auctionResult(2589, { unitPrice = 12 })
    t.eq(api2.looks(), 0)
    t.eq(k2.store:get("account", AL.PATH), nil)
end

tests["auction log module: the word counts, and probe says what the client has"] = function(t)
    local _, c = start()
    c.auctionResult(2589, { unitPrice = 12 })
    local before = #c.printed
    c.slashes[ns.id.slash]("auction")
    t.eq(c.printed[before + 1], ns.id.title .. ": auction: prices for 1 item(s) on " .. REALM .. ", from 1 search(es) this session.")
    c.setApi("C_AuctionHouse", true)
    before = #c.printed
    c.slashes[ns.id.slash]("auction probe")
    t.eq(c.printed[before + 1], ns.id.title .. ": auction probe: has C_AuctionHouse")
    t.eq(#c.printed, before + 3)
end

return tests
