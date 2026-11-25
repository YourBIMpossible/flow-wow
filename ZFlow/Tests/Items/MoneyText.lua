local _, ns = ...

-- Tests for the one money-text function of the Items surfaces (L6-I, A5):
-- Prices.Coin. Zero, copper only, mixed, large sums, and that every Items
-- text that shows money goes through it.

local P, Present, Sell = ns.Prices, ns.ItemPresent, ns.ItemSell
local tests = {}
-- Item names carry the game's quality colour (Items/Present.lua, Tint; the
-- colour itself is tested in Tests/Items/ItemColourTests.lua). These tests are
-- about the words, so they read them with the colour taken off.
local plain = ns.ItemPresent.Plain

tests["money text: zero is 0c, and nothing is never shown as a price"] = function(t)
    t.eq(P.Coin(0), "0c")
    t.eq(P.Coin(nil), nil, "not known: no text, not 0c")
    t.eq(P.Coin(-1), nil)
    t.eq(P.Coin(0 / 0), nil)
    t.eq(P.Coin(math.huge), nil)
    t.eq(P.Coin("12"), nil, "text is not a count")
end

tests["money text: copper only"] = function(t)
    t.eq(P.Coin(1), "1c")
    t.eq(P.Coin(99), "99c")
    t.eq(P.Coin(0.4), "under 1c", "less than one copper is never 0c")
    t.eq(P.Coin(98.6), "99c", "rounded to the copper")
end

tests["money text: silver and gold, short in the biggest coin"] = function(t)
    t.eq(P.Coin(100), "1s")
    t.eq(P.Coin(1240), "12.4s")
    t.eq(P.Coin(10000), "1g")
    t.eq(P.Coin(10203), "1.02g")
    t.eq(P.Coin(10003), "1g")
    t.eq(P.Coin(99.6), "1s", "rounding carries into silver")
    t.eq(P.Coin(9999.5), "1g", "and into gold")
end

tests["money text: large sums are whole gold in plain digits"] = function(t)
    t.eq(P.Coin(2147483647), "214748g", "the old 32-bit money cap")
    t.eq(P.Coin(99999999999), "10000000g")
    t.eq(P.Coin(123456789 * 10000), "123456789g")
    -- Gold of 2e14 and more: plain digits, never "2e+14g".
    t.eq(P.Coin(2e18), "200000000000000g")
    t.ok(not P.Coin(5e19):find("e", 1, true), "no exponent in a money text")
end

-- Every Items surface that shows money uses this one function: swap it and
-- each text shows the swap.
local function withMarker(fn)
    local real = P.Coin
    P.Coin = function(copper)
        if type(copper) ~= "number" then return nil end
        return "<" .. tostring(copper) .. ">"
    end
    local ok, err = pcall(fn)
    P.Coin = real
    if not ok then error(err, 0) end
end

tests["money text: the price texts, the sell list and the plan all use it"] = function(t)
    withMarker(function()
        t.eq(P.Text({ value = 1240, basis = P.OBSERVED }), "<1240>", "Prices.Text")
        t.eq(P.Text({ value = 1240, basis = P.ESTIMATED }), "about <1240> (estimate)")
        local list = Sell.List({ { key = 97, name = "Broken Fang", count = 3, quality = 0, sellPrice = 4 } }, {})
        t.eq(list.rows[1].priceText, "<4>", "ItemSell's row text")
        t.eq(Present.SellRowText(list.rows[1]), "3 x Broken Fang: <4> each, <12> (the item's own sell price)",
            "the sell list's row")
        t.eq(Present.SellTotal(list), "Would sell for: <12>", "the sell list's total")
        t.eq(Present.Cost({ cost = { known = 500, estimated = 0, unknown = 0 } }), "To buy: <500>", "the plan's cost")
        t.eq(Present.SourceText({ from = "vendor", count = 2, basis = "observed", cost = 120, text = "60c" }),
            "buy 2 from a merchant at 60c each (<120>)", "a plan row's merchant part")
    end)
end

for name, fn in pairs(tests) do
    tests[name] = function(t)
        return fn(setmetatable({ eq = function(got, want, msg) return t.eq(plain(got), plain(want), msg) end },
            { __index = t }))
    end
end

return tests
