local _, ns = ...

-- F-085 wording across the Items surfaces (L6-M, lead ruling §113 Decision 2).
-- Exactly two phrases, em dash always:
--   "price unknown—check vendor"    an item's price
--   "price unknown—check trainer"   a training cost
-- and a count line ends in the same phrase: "<n> prices unknown—check vendor".
-- These tests pin the words themselves, not only the constants.

local P, Present, Sell, Plan = ns.Prices, ns.ItemPresent, ns.ItemSell, ns.ItemPlan
local tests = {}

local VENDOR = "price unknown—check vendor"
local TRAINER = "price unknown—check trainer"

-- Anything that looks like the fallback but is not one of the two phrases.
local function wrong(text)
    if type(text) ~= "string" then return false end
    if text:find("unknown - check", 1, true) then return true end           -- the hyphen form
    if text:find("unknown–check", 1, true) then return true end              -- an en dash
    local rest = text:gsub(VENDOR, ""):gsub(TRAINER, "")
        :gsub("prices unknown—check vendor", ""):gsub("prices unknown—check trainer", "")
    return rest:find("price unknown", 1, true) ~= nil or rest:find("prices unknown", 1, true) ~= nil
        or rest:find("unknown—check", 1, true) ~= nil
end

tests["F-085: the checker itself knows right from wrong"] = function(t)
    t.eq(wrong(VENDOR), false)
    t.eq(wrong("3 x Thread: buy 3 from a merchant, " .. VENDOR), false)
    t.eq(wrong("To buy: 2 prices unknown—check vendor"), false)
    t.eq(wrong("price unknown - check vendor"), true, "the hyphen form")
    t.eq(wrong("1 price unknown - check trainer"), true)
    t.eq(wrong("price unknown"), true, "the bare form")
    t.eq(wrong("unknown—check trainer"), true, "without 'price'")
end

tests["F-085: the constants are the two phrases"] = function(t)
    t.eq(P.UNKNOWN_TEXT, TRAINER, "a training cost")
    t.eq(P.UNKNOWN_VENDOR_TEXT, VENDOR, "an item's price")
    t.eq(Present.VENDOR_PRICE_UNKNOWN, VENDOR)
    t.eq(Sell.PRICE_UNKNOWN, VENDOR, "no bare 'price unknown'")
end

tests["F-085: Prices.Text names the trainer for a training cost and the vendor for an item"] = function(t)
    t.eq(P.Text(nil), TRAINER, "no kind given: a training cost, as before")
    t.eq(P.Text(nil, "trainer"), TRAINER)
    t.eq(P.Text({ basis = P.UNKNOWN }, "vendor"), VENDOR)
    t.eq(P.Text(nil, Sell.KIND), VENDOR, "what a merchant pays")
    t.eq(P.Text(nil, "auction"), VENDOR, "an item's price too")
    t.eq(P.Text({ value = 500 }, "vendor"), VENDOR, "a value with no basis is not shown as a price")
    t.eq(P.Text({ value = 60, basis = P.OBSERVED }, "vendor"), "60c", "a known price is unchanged")
end

tests["F-085: a plan's merchant row and its cost line"] = function(t)
    -- Plan's own text for a merchant price nobody saw is pinned in
    -- Tests/Items/Plan.lua (a built plan's vendor source reads VENDOR).
    t.eq(Plan.VENDOR, "vendor", "a plan's merchant price is an item's price")
    t.eq(Present.SourceText({ from = "vendor", count = 3, basis = "unknown" }),
        "buy 3 from a merchant, " .. VENDOR, "the row")
    t.eq(Present.Cost({ cost = { known = 0, estimated = 0, unknown = 1 } }), "To buy: 1 " .. VENDOR, "one")
    t.eq(Present.Cost({ cost = { known = 0, estimated = 0, unknown = 2 } }),
        "To buy: 2 prices unknown—check vendor", "the count line ends in the same phrase")
    t.eq(Present.Cost({ cost = { known = 500, estimated = 0, unknown = 3 } }),
        "To buy: 5s, plus 3 prices unknown—check vendor")
end

tests["F-085: the sell list's row, its total and the price lookup"] = function(t)
    local rules = { { key = "all", order = 1, check = function()
        return { action = "sell", reason = "test", basis = "recommendation" }
    end } }
    local list = Sell.List({ { key = 3000, name = "Grey Mystery", count = 2 }, { key = 3001, count = 1 } }, { rules = rules })
    t.eq(list.rows[1].priceText, VENDOR)
    t.eq(Present.SellRowText(list.rows[1]), "2 x Grey Mystery: " .. VENDOR)
    t.eq(Present.SellTotal(list), "Would sell for: 2 prices unknown—check vendor")
    t.eq(Present.SellTotal({ total = { known = 0, estimated = 0, unknown = 1 } }), "Would sell for: 1 " .. VENDOR)
    t.eq(Present.PriceLines({ key = 4444, sell = { basis = P.UNKNOWN }, buy = { basis = P.UNKNOWN } }),
        { "item 4444: " .. VENDOR })
end

tests["F-085: no Items text carries a wrong form"] = function(t)
    local rules = { { key = "all", order = 1, check = function()
        return { action = "sell", reason = "test", basis = "recommendation" }
    end } }
    local list = Sell.List({ { key = 3000, count = 2 } }, { rules = rules })
    local texts = {
        P.UNKNOWN_TEXT, P.UNKNOWN_VENDOR_TEXT, Sell.PRICE_UNKNOWN, Present.VENDOR_PRICE_UNKNOWN,
        P.Text(nil), P.Text(nil, "vendor"), list.rows[1].priceText,
        Present.SellRowText(list.rows[1]), Present.SellTotal(list),
        Present.SourceText({ from = "vendor", count = 1, basis = "unknown" }),
        Present.Cost({ cost = { known = 0, estimated = 0, unknown = 1 } }),
        Present.Cost({ cost = { known = 0, estimated = 0, unknown = 4 } }),
    }
    for _, line in ipairs(Present.SellLines(list, { ok = true, rows = {} })) do texts[#texts + 1] = line end
    for i, text in ipairs(texts) do
        t.ok(not wrong(text), "text " .. i .. " uses an allowed phrase: " .. tostring(text))
    end
end

return tests
