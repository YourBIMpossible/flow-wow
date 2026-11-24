local _, ns = ...

-- The price word (L6-H, Items/PriceLookup.lua), end to end, on the whole
-- add-on loaded on a fake client. The real entry: <slash> price <item>
-- prints what is known of an item's price and how it is known: the
-- item's own sell price, a merchant's price seen in its window, and the
-- player's own auction searches on this realm. Unknown stays unknown:
-- "price unknown—check vendor", never a 0. Reads only: nothing is sold,
-- bought or equipped, and no price is written by a lookup. Made-up items.
-- Not tested in game.

local tests = {}

local LINEN, THREAD, ODD = 2589, 2320, 424242
local INFO = {
    [LINEN] = { name = "Linen Cloth", quality = 1, sellPrice = 13, classID = 7 },
    [THREAD] = { name = "Coarse Thread", quality = 1, sellPrice = 2, classID = 7 },
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
    c.setBagItems({ { item = LINEN, count = 5 } })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

local function say(c, text)
    for i = #c.printed, 1, -1 do c.printed[i] = nil end
    c.slashes[ns.id.slash](text)
    local out = {}
    for i, l in ipairs(c.printed) do out[i] = l end
    return out
end

local function T(text) return ns.id.title .. ": " .. text end

local function noneActs(t, c)
    t.eq(#c.soldSlots, 0, "nothing sold")
    t.eq(c.equipCalls, 0, "nothing equipped")
end

tests["price e2e: the item's own sell price, labelled"] = function(t)
    local c = boot()
    t.eq(say(c, "price " .. LINEN), { T("|cffffffffLinen Cloth|r: a vendor pays 13c each (the item's own sell price)") })
    noneActs(t, c)
end

tests["price e2e: a merchant seen selling it adds its price, by the stack"] = function(t)
    local c = boot()
    c.setMerchant({ { index = 1, item = THREAD, price = 50, stack = 5 } })
    c.setMerchantOpen(true)
    c.setMerchantOpen(false)
    t.eq(say(c, "price " .. THREAD), {
        T("|cffffffffCoarse Thread|r: a vendor pays 2c each (the item's own sell price)"),
        T("A merchant sells it for 10c each, 5 at a time (merchant window)"),
    })
    noneActs(t, c)
end

tests["price e2e: the player's own auction search adds the auction line"] = function(t)
    local c = boot()
    c.auctionResult(LINEN, { unitPrice = 5000 })
    t.eq(say(c, "price " .. LINEN), {
        T("|cffffffffLinen Cloth|r: a vendor pays 13c each (the item's own sell price)"),
        T("Auction: 50s each, 0 min ago"),
    })
end

tests["price e2e: an item link is read, lower-cased by the slash command"] = function(t)
    local c = boot()
    t.eq(say(c, "price |cffffffff|Hitem:2589:0:0:0:0:0:0:0|h[Linen Cloth]|h|r"),
        { T("|cffffffffLinen Cloth|r: a vendor pays 13c each (the item's own sell price)") })
end

tests["price e2e: unknown data stays unknown"] = function(t)
    local c = boot()
    -- An item the client cannot read and nobody priced: no figure, no 0.
    t.eq(say(c, "price " .. ODD), { T("item " .. ODD .. ": price unknown—check vendor") })
    -- Not an item at all: the usage line.
    t.eq(say(c, "price"), { T("say price <item link> (or an item ID).") })
    t.eq(say(c, "price fish"), { T("say price <item link> (or an item ID).") })
    -- A lookup writes no price.
    local account = c.saved(ns.id.accountDB)
    local prices = account.learned and account.learned.prices or nil
    t.ok(type(prices) ~= "table" or type(prices.vendor) ~= "table" or prices.vendor[ODD] == nil,
        "nothing saved for the unknown item")
    noneActs(t, c)
end

return tests
