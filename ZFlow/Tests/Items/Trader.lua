-- S2 slice 1 and 2: the trader (Items/Trader.lua), from legacy Flow's
-- Modules/Items/Trader.lua rules. Advice only: nothing searches, bids, buys
-- or pays. Fake client only; not tested in game.
local _, ns = ...

local T = ns.Trader
local tests = {}
local coin = ns.Prices.Coin

local function near(t, a, b, msg)
    t.ok(type(a) == "number" and math.abs(a - b) < 0.01, (msg or "") .. ": " .. tostring(a) .. " ~ " .. tostring(b))
end

tests["trader: the rules are the legacy numbers"] = function(t)
    t.eq({ T.DEAL, T.CUT, T.MIN_LOOKS, T.MIN_GAIN, T.MAX }, { 0.5, 0.05, 4, 50, 8 })
    t.eq({ T.NAME, T.WORD, T.SETTING }, { "trader", "trader", "trader.off" })
end

tests["trader: the usual price is the middle of the visits, from four"] = function(t)
    t.eq({ T.Usual({ 1, 100, 2, 300, 3, 200, 4, 400, 5, 500 }) }, { 300, 5 }, "odd: the middle one")
    t.eq({ T.Usual({ 1, 100, 2, 200, 3, 300, 4, 400 }) }, { 250, 4 }, "even: between the middle two")
    local usual, n = T.Usual({ 1, 100, 2, 200, 3, 300 })
    t.eq(usual, nil, "under four visits: no usual price")
    t.eq(n, 3)
    usual, n = T.Usual(nil)
    t.eq(usual, nil)
    t.eq(n, 0)
    t.eq({ T.Usual({ 1, 100, 2, 200, 3, 300 }, 3) }, { 200, 3 }, "the least can be given")
end

tests["trader: a listing counts when under the vendor or at half the usual price"] = function(t)
    t.eq(T.Listing(nil, nil, 50, 13, 400), nil, "no count")
    t.eq(T.Listing(nil, 0, 50, 13, 400), nil, "none")
    t.eq(T.Listing(nil, 5, 0, 13, 400), nil, "no price")
    t.eq(T.Listing(nil, 5, nil, 13, 400), nil)
    t.eq(T.Listing(nil, 5, 50, 13, nil), { vq = 5, vc = 50, dq = 0, dc = 0, vendor = 13 }, "under a vendor")
    t.eq(T.Listing(nil, 5, 65, 13, nil), nil, "at the vendor price: not under it")
    t.eq(T.Listing(nil, 2, 200, nil, 200), { vq = 0, vc = 0, dq = 2, dc = 200, usual = 200 }, "exactly half")
    t.eq(T.Listing(nil, 2, 202, nil, 200), nil, "a copper over half")
    t.eq(T.Listing(nil, 2, 1000, 13, 400), nil, "above both")
    t.eq(T.Listing(nil, 2, 1000, 0, 0), nil, "no vendor price and no usual price")
    local agg = T.Listing(nil, 5, 50, 13, 400)
    t.eq(agg, { vq = 5, vc = 50, dq = 5, dc = 50, vendor = 13, usual = 400 }, "under both")
    local same = T.Listing(agg, 2, 300, 13, 400)
    t.ok(same == agg, "the same table is added to")
    t.eq(agg, { vq = 5, vc = 50, dq = 7, dc = 350, vendor = 13, usual = 400 })
    t.ok(T.Listing(agg, 1, 5000, 13, 400) == agg, "a listing that is no deal leaves it as it was")
    t.eq(agg.dq, 7)
end

tests["trader: deals, the vendor one first, the resell gain less the 5% cut"] = function(t)
    local deals = T.Deals({ [7] = { vq = 5, vc = 50, dq = 5, dc = 50, vendor = 30, usual = 200 } })
    t.eq(#deals, 1)
    t.eq(deals[1], { id = 7, kind = "vendor", qty = 5, cost = 50, gain = 100, limit = 30, name = "item 7" })
    deals = T.Deals({ [8] = { vq = 0, vc = 0, dq = 2, dc = 200, usual = 400 } }, function(id) return "Thing " .. id end)
    t.eq(#deals, 1)
    t.eq({ deals[1].id, deals[1].kind, deals[1].qty, deals[1].cost, deals[1].usual, deals[1].name },
        { 8, "resell", 2, 200, 400, "Thing 8" })
    near(t, deals[1].gain, 560, "two at the usual 4s less 5%, less the 2s paid")
    near(t, deals[1].limit, 200, "half the usual price")
end

tests["trader: a gain under 50 copper is dropped, the rest by gain then id, a refused one left out"] = function(t)
    local aggs = {
        [1] = { vq = 1, vc = 51, dq = 0, dc = 0, vendor = 100 },
        [2] = { vq = 1, vc = 50, dq = 0, dc = 0, vendor = 100 },
        [3] = { vq = 2, vc = 100, dq = 0, dc = 0, vendor = 100 },
        [4] = { vq = 2, vc = 100, dq = 0, dc = 0, vendor = 100 },
        [5] = { vq = 0, vc = 0, dq = 0, dc = 0, vendor = 100 },
        [6] = { vq = 9, vc = 100, dq = 0, dc = 0, vendor = 100 },
    }
    local ids = {}
    for _, row in ipairs(T.Deals(aggs)) do ids[#ids + 1] = row.id end
    t.eq(ids, { 6, 3, 4, 2 }, "49 copper is no deal; 50 is; nothing listed is nothing")
    ids = {}
    for _, row in ipairs(T.Deals(aggs, nil, function(id) return id ~= 6 end)) do ids[#ids + 1] = row.id end
    t.eq(ids, { 3, 4, 2 }, "the candidate rule refused 6")
    ids = {}
    for _, row in ipairs(T.Deals(aggs, nil, nil, 150)) do ids[#ids + 1] = row.id end
    t.eq(ids, { 6 }, "the least gain can be given")
    t.eq(T.Deals(nil), {})
end

local VENDOR = { id = 4306, kind = "vendor", qty = 3, cost = 300, gain = 150, limit = 150, name = "Silk Cloth" }
local RESELL = { id = 2589, kind = "resell", qty = 20, cost = 3000, gain = 4600, limit = 200, usual = 400,
                 name = "Linen Cloth" }

-- Words that would promise a buy the addon does not make.
local function advisory(t, s)
    local low = s:lower()
    for _, word in ipairs({ "pays at most", "of your gold", "now:", "flow", "confirm", "click" }) do
        t.ok(not low:find(word, 1, true), word .. " in: " .. s)
    end
end

tests["trader: a deal's line"] = function(t)
    t.eq(T.Line(VENDOR, coin), "3 x Silk Cloth for 3s: a vendor pays 4.5s  |cff40ff40+1.5s|r")
    t.eq(T.Line(RESELL, coin), "20 x Linen Cloth for 30s: usually 4s each  |cffffd100about +46s|r")
    advisory(t, T.Line(VENDOR, coin))
    advisory(t, T.Line(RESELL, coin))
    t.eq(T.Plain("a |cff40ff40+1s|r b"), "a +1s b", "the colour marks taken off for a chat list")
end

tests["trader: a deal's tooltip text is advice, with no word of paying"] = function(t)
    local v = T.TipLines(VENDOR, coin)
    t.eq(v, { "Listed under what a vendor pays (1.5s each). Buy it, sell it to any vendor: the gain is certain." })
    local r = T.TipLines(RESELL, coin)
    t.eq(r, {
        "Listed at half or less of its usual price here (4s each, from your own searches). "
            .. "Buy it and post it again: a guess, not a promise.",
        "The auction house's 5% is taken off the gain; the deposit isn't, and it may not sell.",
    })
    for _, line in ipairs(v) do advisory(t, line) end
    for _, line in ipairs(r) do advisory(t, line) end
end

tests["trader: the one line on an item's tooltip"] = function(t)
    t.eq({ T.TipLine(VENDOR, coin) }, { "Deal: listed at 1s each, under a vendor's 1.5s", 0.25, 1, 0.25 })
    t.eq({ T.TipLine(RESELL, coin) }, { "Deal: listed at 1.5s each, usually 4s", 1, 0.82, 0 })
    t.eq(T.TipLine(nil, coin), nil)
    t.eq(T.TipLine({ kind = "resell", qty = 0, cost = 0 }, coin), nil, "nothing listed: no line")
end

local INFO = {
    [2589] = { name = "Linen Cloth", quality = 1, sellPrice = 13, classID = 7 },
    [4306] = { name = "Silk Cloth", quality = 1, sellPrice = 150, classID = 7 },
}
local LINEN_ROWS = { { unit = 100, qty = 10 }, { unit = 200, qty = 10 }, { unit = 300, qty = 5 } }
local LINEN_LINE = "20 x |cffffffffLinen Cloth|r for 30s: usually 4s each  |cffffd100about +46s|r"
local RULES = "  resell at 50% of the usual price or less, from 4 visits; the house keeps 5%, the deposit is not counted"

local function start()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setRealm("Old Blanchy")
    c.setFaction("Horde")
    c.setClock(5000)
    c.setItemInfo(INFO)
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    local api = T.Declare(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    k.store:set("account", ns.AuctionLog.PATH .. ".Old Blanchy-Horde",
        { [2589] = { h = { 1000, 400, 2000, 400, 3000, 400, 4000, 400 } } })
    return k, c, api
end

tests["trader module: a deal in your own search prints once, and a search without it takes it away"] = function(t)
    local _, c, api = start()
    local before = #c.printed
    c.auctionRows(2589, LINEN_ROWS)
    t.eq(c.printed[before + 1], "Deal: " .. LINEN_LINE)
    t.eq(#c.printed, before + 1)
    t.eq(#api.deals(), 1)
    t.eq(api.deals()[1].id, 2589)
    c.auctionRows(2589, LINEN_ROWS)
    t.eq(#c.printed, before + 1, "still the same deal: not said again")
    c.auctionRows(2589, { { unit = 300, qty = 5 } })
    t.eq(#api.deals(), 0, "the search no longer shows it")
    t.eq(#c.printed, before + 1)
    c.auctionRows(2589, LINEN_ROWS)
    t.eq(c.printed[before + 2], "Deal: " .. LINEN_LINE, "a deal again: said again")
end

tests["trader module: a listing under the vendor needs no price history"] = function(t)
    local _, c, api = start()
    local before = #c.printed
    c.auctionRows(4306, { { unit = 100, qty = 3 }, { unit = 150, qty = 9 }, { unit = 90 }, { qty = 4 } })
    t.eq(c.printed[before + 1], "Deal: 3 x |cffffffffSilk Cloth|r for 3s: a vendor pays 4.5s  |cff40ff40+1.5s|r",
        "a row without a count or without a price is passed over")
    t.eq(api.deals()[1].kind, "vendor")
end

tests["trader module: under four visits there is no usual price, and so no resell deal"] = function(t)
    local k, c, api = start()
    k.store:set("account", ns.AuctionLog.PATH .. ".Old Blanchy-Horde",
        { [2589] = { h = { 1000, 400, 2000, 400, 3000, 400 } } })
    local before = #c.printed
    c.auctionRows(2589, LINEN_ROWS)
    t.eq(#c.printed, before)
    t.eq(#api.deals(), 0)
end

tests["trader module: an item you chose never to sell is no deal"] = function(t)
    local k, c, api = start()
    t.eq(k.store:set("char", "settings.sell.never", { [2589] = true }), true)
    local before = #c.printed
    c.auctionRows(2589, LINEN_ROWS)
    t.eq(#c.printed, before)
    t.eq(#api.deals(), 0)
end

tests["trader module: the word lists the session's deals and buys nothing"] = function(t)
    local _, c = start()
    local title = ns.id.title
    local before = #c.printed
    c.slashes[ns.id.slash]("trader")
    t.eq(c.printed[before + 1], title .. " Trader: 0 deal(s) from your searches this session")
    t.eq(c.printed[before + 2], RULES)
    t.eq(c.printed[before + 3], "Buying is yours, in the auction window: " .. title .. " buys nothing.")
    t.eq(#c.printed, before + 3)
    c.auctionRows(4306, { { unit = 100, qty = 3 } })
    c.auctionRows(2589, LINEN_ROWS)
    before = #c.printed
    c.slashes[ns.id.slash]("trader")
    t.eq(c.printed[before + 1], title .. " Trader: 2 deal(s) from your searches this session")
    t.eq(c.printed[before + 2], RULES)
    t.eq(c.printed[before + 3], "  20 x Linen Cloth for 30s: usually 4s each  about +46s", "the larger gain first")
    t.eq(c.printed[before + 4], "  3 x Silk Cloth for 3s: a vendor pays 4.5s  +1.5s")
    t.eq(c.printed[before + 5], "Buying is yours, in the auction window: " .. title .. " buys nothing.")
    t.eq(#c.printed, before + 5)
end

tests["trader module: off says nothing of a deal, and the list still answers"] = function(t)
    local k, c, api = start()
    local title = ns.id.title
    t.eq(k.settings:get(T.SETTING), false, "on until turned off")
    local before = #c.printed
    c.slashes[ns.id.slash]("trader off")
    t.eq(c.printed[before + 1], title .. " Trader off")
    t.eq(k.settings:get(T.SETTING), true)
    t.eq(k.store:get("account", "settings.trader.off"), true, "the key legacy Flow kept")
    before = #c.printed
    c.auctionRows(2589, LINEN_ROWS)
    t.eq(#c.printed, before, "no chat line")
    t.eq(#api.deals(), 1, "still listed")
    t.eq(c.showItemTooltip(2589), {}, "no tooltip line")
    c.slashes[ns.id.slash]("trader")
    t.eq(c.printed[before + 1], title .. " Trader (off): 1 deal(s) from your searches this session")
    before = #c.printed
    c.slashes[ns.id.slash]("trader on")
    t.eq(c.printed[before + 1], title .. " Trader on")
    t.eq(k.settings:get(T.SETTING), false)
end

tests["trader module: an item in the session's list says so on its tooltip"] = function(t)
    local _, c = start()
    t.eq(c.showItemTooltip(2589), {}, "no deal seen: no line")
    c.auctionRows(2589, LINEN_ROWS)
    c.auctionRows(4306, { { unit = 100, qty = 3 } })
    t.eq(c.showItemTooltip(2589), { { text = "Deal: listed at 1.5s each, usually 4s (seen 0 min ago)", r = 1, g = 0.82, b = 0 } })
    t.eq(c.showItemTooltip(4306),
        { { text = "Deal: listed at 1s each, under a vendor's 1.5s (seen 0 min ago)", r = 0.25, g = 1, b = 0.25 } })
    t.eq(c.showItemTooltip(858), {}, "another item: no line")
    c.auctionRows(2589, { { unit = 300, qty = 5 } })
    t.eq(c.showItemTooltip(2589), {}, "no longer a deal: no line")
end

tests["trader module: a client without the rows read starts, and lists nothing"] = function(t)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setAuctionHouse(false)
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    local api = T.Declare(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    t.eq(api.followed(), false)
    local before = #c.printed
    c.slashes[ns.id.slash]("trader")
    t.eq(c.printed[before + 1], ns.id.title .. " Trader: 0 deal(s) from your searches this session")
end

return tests
