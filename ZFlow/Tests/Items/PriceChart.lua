-- S4 price chart, tooltip only: the pure core (Items/PriceChart.lua; ported
-- from legacy Flow's Modules/Items/PriceChart.lua). Hand-made looks only.
local _, ns = ...

local PC = ns.PriceChart
local tests = {}
local HOUR, DAY = 3600, 86400

tests["price chart: legacy Flow's history reads oldest first"] = function(t)
    local pts = PC.Points({ h = { 200, 50, 100, 40, 300 } })
    t.eq(pts, { { at = 100, price = 40 }, { at = 200, price = 50 } }, "pairs only; the odd one out is left")
end

tests["price chart: the older looks, newest first, and a single price read too"] = function(t)
    t.eq(PC.Points({ looks = { { price = 60, at = 300 }, { price = 40, at = 100 } } }),
        { { at = 100, price = 40 }, { at = 300, price = 60 } })
    t.eq(PC.Points({ price = 70, at = 5 }), { { at = 5, price = 70 } })
    t.eq(PC.Points({ value = 80, seenAt = 9, basis = "observed" }), { { at = 9, price = 80 } }, "a price book entry")
end

tests["price chart: a look without a time or a price is left out"] = function(t)
    t.eq(PC.Points({ value = 80 }), {}, "an imported price has no date: no point")
    t.eq(PC.Points({ looks = { { price = 60 }, "x", { price = -1, at = 2 }, { price = 0 / 0, at = 3 } } }), {})
    t.eq(PC.Points(nil), {})
end

tests["price chart: range and stats"] = function(t)
    local pts = { { at = 100, price = 40 }, { at = 200, price = 80 }, { at = 400, price = 60 } }
    t.eq({ PC.Range(pts) }, { 100, 400, 40, 80 })
    t.eq(PC.Stats(pts), { now = 60, low = 40, high = 80, avg = 60, looks = 3, change = 0.5 })
    t.eq(PC.Stats({}), nil)
    t.eq(PC.Stats({ { at = 1, price = 0 }, { at = 2, price = 5 } }).change, nil, "from nothing: no share")
end

tests["price chart: the change and the span in words"] = function(t)
    t.eq(PC.ChangeText(0.25), "up 25%")
    t.eq(PC.ChangeText(-0.084), "down 8%")
    t.eq(PC.ChangeText(0.004), "unchanged")
    t.eq(PC.ChangeText(nil), nil)
    t.eq(PC.Span(40 * 60), "40 min")
    t.eq(PC.Span(5 * HOUR + 59), "5 h")
    t.eq(PC.Span(3 * DAY + 1), "3 days")
    t.eq(PC.Span(-5), "0 min")
end

tests["price chart: the tooltip's lines"] = function(t)
    t.eq(PC.TipLines({}, 1000), {}, "no looks, no line")
    t.eq(PC.TipLines({ { at = 1000, price = 12345 } }, 1000 + 2 * HOUR), { "Auction: 1.23g each, 2 h ago" })
    local pts = { { at = 0, price = 100 }, { at = 3 * DAY, price = 125 } }
    t.eq(PC.TipLines(pts, 3 * DAY + 600), {
        "Auction: 1.25s each, 10 min ago",
        "Low 1s, high 1.25s, average 1.13s: 2 looks over 3 days, up 25%",
    })
    t.eq(PC.TipLines(pts, nil)[1], "Auction: 1.25s each", "no clock: no age, never guessed")
end

return tests
