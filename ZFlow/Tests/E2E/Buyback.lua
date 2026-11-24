local _, ns = ...

-- End to end (G3): the buyback list. The whole add-on on a fake client: at
-- a merchant, `<slash> buyback` says what is on the Buyback tab and where
-- to click. It buys nothing. Made-up items; not tested in game.

local tests = {}

local STONE = "|cffffffff|Hitem:2835:0:0:0:0:0:0:0|h[Rough Stone]|h|r"

local function boot()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(2, 10)
    return c, addon
end

local function said(c, from)
    local out = {}
    for i = (from or 0) + 1, #(c.printed or {}) do out[#out + 1] = tostring(c.printed[i]) end
    return out
end

local function ask(c)
    local from = #(c.printed or {})
    c.slashes[ns.id.slash](ns.Buyback.WORD)
    return said(c, from)
end

tests["buyback: away from a merchant it says to open one"] = function(t)
    local c = boot()
    local out = ask(c)
    t.eq(#out, 1)
    t.eq(out[1], ns.id.title .. ": " .. ns.Buyback.NOT_OPEN)
end

tests["buyback: at a merchant with nothing sold it says the tab is empty"] = function(t)
    local c = boot()
    c.setReturnable({})
    c.setMerchantOpen(true)
    local out = ask(c)
    t.eq(out, { ns.id.title .. ": nothing is on this merchant's Buyback tab." })
end

tests["buyback: each item sold is listed with its price, then where to click"] = function(t)
    local c = boot()
    c.setMoney(50000)
    c.setReturnable({
        { index = 1, item = STONE, name = "Rough Stone", price = 40, count = 5 },
        { index = 2, name = "Bent Sword", price = 1250, count = 1 },
        { index = 3, item = STONE },
    })
    c.setMerchantOpen(true)
    local out = ask(c)
    t.eq(out, {
        ns.id.title .. ": 3 items are on this merchant's Buyback tab:",
        "1. Rough Stone x5: 40c to buy back",
        "2. Bent Sword: 12s 50c to buy back",
        "3. Rough Stone: its price was not read",
        ns.Buyback.HOW,
    })
    t.eq(c.money(), 50000, "nothing was bought")
end

tests["buyback: one item reads as one, and help lists the word"] = function(t)
    local c, addon = boot()
    c.setReturnable({ { index = 1, name = "Bent Sword", price = 1250, count = 1 } })
    c.setMerchantOpen(true)
    local out = ask(c)
    t.eq(out[1], ns.id.title .. ": 1 item is on this merchant's Buyback tab:")
    t.eq(addon.diag.help[ns.Buyback.WORD], ns.Buyback.HELP)
    c.setMerchantOpen(false)
    t.eq(ask(c), { ns.id.title .. ": " .. ns.Buyback.NOT_OPEN })
end

return tests
