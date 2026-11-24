local _, ns = ...

-- The trader (S2, Items/Trader.lua), end to end, on the whole add-on loaded
-- on a fake client. The real entries: the player's own auction searches
-- answering (c.auctionRows, the client's watchAuctionRows) put a deal in
-- chat and on the item's tooltip; the trader word (<slash> trader) lists
-- the session's deals and turns the lines off and on. Advice only: nothing
-- searches, bids, buys, sells, posts or moves an item. Made-up items. Not
-- tested in game.
--
-- The numbers: 20 grey fangs listed at 1c each; a vendor pays 4c each, so
-- 20c buys what a vendor pays 80c for: +60c, over the 50c floor.

local tests = {}

local FANG, ODD = 97, 9004
local INFO = {
    [FANG] = { name = "Broken Fang", quality = 0, sellPrice = 4 },
}
local NOW = 1700000000
local MONEY = 12345
local GREEN = { 0.25, 1, 0.25 }

local function boot()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setScreen(1024, 768)
    c.setClock(NOW)
    c.setRealm("Realm1")
    c.setFaction("Horde")
    c.setMoney(MONEY)
    c.setItemInfo(INFO)
    c.setBagItems({ { item = FANG, count = 1 } })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

local function clear(c)
    for i = #c.printed, 1, -1 do c.printed[i] = nil end
end

local function said(c)
    local out = {}
    for i, l in ipairs(c.printed) do out[i] = l end
    return out
end

local function word(c, arg)
    clear(c)
    c.slashes[ns.id.slash](arg and ("trader " .. arg) or "trader")
    return said(c)
end

-- The deal line on an item's tooltip, or nil.
local function tip(c, item)
    for _, l in ipairs(c.showItemTooltip(item)) do
        if type(l.text) == "string" and l.text:sub(1, 6) == "Deal: " then return l end
    end
    return nil
end

local HEAD0 = ns.id.title .. " Trader: 0 deal(s) from your searches this session"
local HEAD1 = ns.id.title .. " Trader: 1 deal(s) from your searches this session"
local RULE = "  resell at 50% of the usual price or less, from 4 visits; the house keeps 5%, the deposit is not counted"
local FOOT = "Buying is yours, in the auction window: " .. ns.id.title .. " buys nothing."
local ROW = "20 x Broken Fang for 20c: a vendor pays 80c  +60c"

-- Only what the trader shows: no item, coin or action leaves the player.
local function noneActs(t, c)
    t.eq(#c.soldSlots, 0, "nothing sold")
    t.eq(c.equipCalls, 0, "nothing equipped")
    t.eq(c.money(), MONEY, "no money spent")
    t.eq(c.bagItems(), { { item = FANG, count = 1 } }, "the bags as they were")
end

tests["trader e2e: a listing under the vendor price is a deal in chat, tooltip and word"] = function(t)
    local c = boot()
    t.eq(word(c), { HEAD0, RULE, FOOT }, "no searches yet: no deals")
    clear(c)
    c.auctionRows(FANG, { { unit = 1, qty = 20 }, { unit = 9, qty = 3 } })
    t.eq(said(c), { "Deal: 20 x |cff9d9d9dBroken Fang|r for 20c: a vendor pays 80c  |cff40ff40+60c|r" })
    c.setClock(NOW + 300)
    local l = tip(c, FANG)
    t.eq(l and l.text, "Deal: listed at 1c each, under a vendor's 4c (seen 5 min ago)")
    t.eq(l and { l.r, l.g, l.b }, GREEN)
    t.eq(word(c), { HEAD1, RULE, "  " .. ROW, FOOT })
    noneActs(t, c)
end

tests["trader e2e: the same deal again is not said twice"] = function(t)
    local c = boot()
    c.auctionRows(FANG, { { unit = 1, qty = 20 } })
    clear(c)
    c.auctionRows(FANG, { { unit = 1, qty = 20 } })
    t.eq(said(c), {}, "already in the list")
    noneActs(t, c)
end

tests["trader e2e: a later search without the deal takes it off"] = function(t)
    local c = boot()
    c.auctionRows(FANG, { { unit = 1, qty = 20 } })
    c.auctionRows(FANG, { { unit = 9, qty = 20 } })
    t.eq(tip(c, FANG), nil)
    t.eq(word(c)[1], HEAD0)
end

tests["trader e2e: off says nothing in chat or tooltip, the word still lists"] = function(t)
    local c = boot()
    t.eq(word(c, "off"), { ns.id.title .. " Trader off" })
    clear(c)
    c.auctionRows(FANG, { { unit = 1, qty = 20 } })
    t.eq(said(c), {}, "no chat line")
    t.eq(tip(c, FANG), nil, "no tooltip line")
    t.eq(word(c), { ns.id.title .. " Trader (off): 1 deal(s) from your searches this session", RULE,
        "  " .. ROW, FOOT })
    t.eq(word(c, "on"), { ns.id.title .. " Trader on" })
    t.eq(tip(c, FANG) ~= nil, true, "on again: the tooltip line is back")
    noneActs(t, c)
end

tests["trader e2e: an item the game does not describe is no deal"] = function(t)
    local c = boot()
    clear(c)
    c.auctionRows(ODD, { { unit = 1, qty = 500 } })
    c.auctionRows(FANG, { { unit = 1 }, { qty = 20 } })
    t.eq(said(c), {}, "unknown item, rows without a count or price: nothing said")
    t.eq(tip(c, ODD), nil)
    t.eq(word(c), { HEAD0, RULE, FOOT })
    noneActs(t, c)
end

return tests
