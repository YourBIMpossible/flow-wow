local _, ns = ...

-- The price chart's tooltip lines (Items/PriceChart.lua TipLines), end to
-- end, on the whole add-on loaded on a fake client. PriceChart has no entry
-- of its own; its reachable one is the item tooltip that Items/AuctionLog.lua
-- fills from the looks in the player's own auction searches
-- (c.auctionResult). Advice only: nothing buys, bids or posts. Made-up
-- realm and items. Not tested in game.
--
-- The numbers: 50s at NOW, then 40s an hour later (a second visit, past
-- AuctionLog.SAME_LOOK); the tooltip read 20 min after that: low 40s, high
-- 50s, average 45s, 2 looks over 1 h, down 20%.

local tests = {}

local ORE, DUST = 2770, 9003
local INFO = {
    [ORE] = { name = "Copper Ore", quality = 1, sellPrice = 5 },
    [DUST] = { name = "Grey Dust", quality = 1, sellPrice = 1 },
}
local NOW = 1700000000

local function boot()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setScreen(1024, 768)
    c.setClock(NOW)
    c.setRealm("Realm1")
    c.setFaction("Horde")
    c.setItemInfo(INFO)
    c.setBagItems({})
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

-- The price lines on an item's tooltip (the posting ask line left out).
local function tip(c, item)
    local out = {}
    for _, l in ipairs(c.showItemTooltip(item)) do
        local text = l.text
        if type(text) == "string" and text:sub(1, 13) ~= "Auction: ask "
            and (text:sub(1, 9) == "Auction: " or text:sub(1, 4) == "Low ") then
            out[#out + 1] = text
        end
    end
    return out
end

tests["price chart e2e: two visits give the price and how it moved"] = function(t)
    local c = boot()
    c.auctionResult(ORE, { unitPrice = 5000, quantity = 10 })
    c.setClock(NOW + 3600)
    c.auctionResult(ORE, { unitPrice = 4000, quantity = 10 })
    c.setClock(NOW + 3600 + 1200)
    t.eq(tip(c, ORE), {
        "Auction: 40s each, 20 min ago",
        "Low 40s, high 50s, average 45s: 2 looks over 1 h, down 20%",
    })
end

tests["price chart e2e: one look gives the price alone"] = function(t)
    local c = boot()
    c.auctionResult(ORE, { buyoutAmount = 30000, quantity = 5 })
    t.eq(tip(c, ORE), { "Auction: 60s each, 0 min ago" })
end

tests["price chart e2e: looks within one visit count once, the cheapest"] = function(t)
    local c = boot()
    c.auctionResult(ORE, { unitPrice = 5000, quantity = 1 })
    c.setClock(NOW + 60)
    c.auctionResult(ORE, { unitPrice = 4500, quantity = 1 })
    t.eq(tip(c, ORE), { "Auction: 45s each, 1 min ago" })
end

tests["price chart e2e: an item nobody looked up says nothing"] = function(t)
    local c = boot()
    c.auctionResult(ORE, { unitPrice = 5000, quantity = 1 })
    t.eq(tip(c, DUST), {}, "no look: no line, not unknown")
    c.auctionResult(DUST, { quantity = 3 })
    t.eq(tip(c, DUST), {}, "a look without a price is not kept")
end

return tests
