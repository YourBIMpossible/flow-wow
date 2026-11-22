local _, ns = ...

-- L6-P (review of L6-I 3523ff0, lows 2 and 3): the estimate texts also go
-- through the one money-text function (Prices.Coin), and the sell row's
-- price text never raises on a unit it cannot word.

local P, Present, Sell = ns.Prices, ns.ItemPresent, ns.ItemSell
local tests = {}

-- Swap the money text for a marker while fn runs.
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

tests["money text: the estimate texts use the one function too"] = function(t)
    withMarker(function()
        local book = {}
        P.Record(book, 3000, Sell.KIND, 25, { basis = P.ESTIMATED, source = "an import" })
        local rules = { { key = "all", order = 1, check = function()
            return { action = "sell", reason = "test", basis = "recommendation" }
        end } }
        local list = Sell.List({ { key = 3000, name = "Grey Mystery", count = 2 } }, { rules = rules, book = book })
        t.eq(list.rows[1].priceText, "about <25> (estimate, an import)", "ItemSell's estimated row")
        t.eq(Present.SellRowText(list.rows[1]), "2 x Grey Mystery: about <25> each (estimate, an import), about <50>",
            "the sell list's estimated row")
        t.eq(Present.SellTotal(list), "Would sell for: about <50> (estimate)", "its total")
        t.eq(Present.Cost({ cost = { known = 0, estimated = 700, unknown = 0 } }), "To buy: about <700> (estimate)",
            "the plan's estimated cost")
        t.eq(Present.SourceText({ from = "vendor", count = 2, basis = "estimated", estimate = 120, text = "x" }),
            "buy 2 from a merchant at x each (about <120> (estimate))", "a plan row's estimated merchant part")
    end)
end

tests["sell row text: a unit that is not a count reads as unknown and raises nothing"] = function(t)
    for _, unit in ipairs({ "12", -5, 0 / 0, math.huge }) do
        local ok, text = pcall(Sell.PriceText, { unit = unit, basis = P.ESTIMATED, source = "an import" })
        t.ok(ok, "no error for " .. tostring(unit))
        t.eq(text, Sell.PRICE_UNKNOWN)
    end
    local ok, text = pcall(Sell.PriceText, { unit = nil, basis = P.OBSERVED })
    t.ok(ok)
    t.eq(text, Sell.PRICE_UNKNOWN, "an observed row with no unit: unknown, not nil")
    t.eq(Sell.PriceText({ unit = 25, basis = P.ESTIMATED }), Sell.PRICE_UNKNOWN, "an estimate with no source is not shown")
    t.eq(Sell.PriceText({ unit = 25, basis = P.ESTIMATED, source = "an import" }), "about 25c (estimate, an import)")
    t.eq(Sell.PriceText({ unit = 4, basis = P.OBSERVED }), "4c")
end

return tests
