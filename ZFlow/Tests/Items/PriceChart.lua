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
    t.eq(PC.TipLines({ { at = 1000, price = 12345 } }, 1000 + 2 * HOUR), { "Auction: 1g 23s 45c each, 2 h ago" })
    local pts = { { at = 0, price = 100 }, { at = 3 * DAY, price = 125 } }
    t.eq(PC.TipLines(pts, 3 * DAY + 600), {
        "Auction: 1s 25c each, 10 min ago",
        "Low 1s, high 1s 25c, average 1s 13c: 2 looks over 3 days, up 25%",
    })
    t.eq(PC.TipLines(pts, nil)[1], "Auction: 1s 25c each", "no clock: no age, never guessed")
end

-- Parity row E-41, the data half (lead section 787): the chart window's
-- numbers and words, as Flow's Modules/Items/PriceChart.lua (PC.Axis :64,
-- PC.Place :71, PC.Ticks :114, PC.Stamp :127, PC.Words :139, PC.IsChartClick
-- :338), in our own words. The window is the drawing lane's; the item-link
-- hook the lead's. Fails before: none of these were here.
local PTS = { { at = 0, price = 100 }, { at = 2 * DAY, price = 200 }, { at = 4 * DAY, price = 150 } }

tests["price chart E-41: the price axis has room around the spread, never under 0"] = function(t)
    t.eq(PC.PAD, 0.12, "as Flow")
    t.eq({ PC.Axis(100, 200) }, { 88, 212 })
    t.eq({ PC.Axis(100, 100) }, { 90, 110 }, "a flat price: a tenth of itself each way")
    t.eq({ PC.Axis(5, 200, 0.5) }, { 0, 297.5 }, "never under 0")
    t.eq({ PC.Axis(0, 0) }, { 0, 1 }, "nothing at all: a copper of room")
end

tests["price chart E-41: each point placed in the box, time to scale; one point in the middle"] = function(t)
    local placed = PC.Place(PTS, 400, 100)
    t.eq(#placed, 3)
    t.eq(placed[1].x, 0)
    t.eq(placed[3].x, 400)
    t.eq(placed[2].x, 200)
    t.ok(math.abs(placed[1].y - 100 * (100 - 88) / (212 - 88)) < 0.001, "the low point's height")
    t.eq({ placed[2].at, placed[2].price }, { 2 * DAY, 200 })
    local one = PC.Place({ { at = 5, price = 50 } }, 400, 100)
    t.eq({ one[1].x, one[1].y }, { 200, 50 })
    t.eq(PC.Place({}, 400, 100), {})
end

tests["price chart E-41: the time labels, spread from the first look to the last"] = function(t)
    t.eq(PC.Ticks(0, 4 * DAY, 3), { { at = 0, share = 0 }, { at = 2 * DAY, share = 0.5 }, { at = 4 * DAY, share = 1 } })
    t.eq(PC.Ticks(10, 10, 3), { { at = 10, share = 0.5 } }, "one look: one label")
    t.eq(PC.Ticks(nil, nil, 3), {})
    local asked
    local function date(fmt, at) asked = { fmt, at } return "x" end
    t.eq(PC.Stamp(5, HOUR, date), "x")
    t.eq(asked, { PC.STAMP_HOUR, 5 }, "within two days: the hour")
    PC.Stamp(5, 3 * DAY, date)
    t.eq(asked, { PC.STAMP_DAY, 5 }, "longer: the day")
    t.eq(PC.Stamp(5, HOUR, nil), nil, "no clock words: none")
end

tests["price chart E-41: the words above the chart"] = function(t)
    local head, line = PC.Words("Linen Cloth", {}, 10)
    t.eq({ head, line }, { "Linen Cloth", PC.NO_LOOKS })
    head, line = PC.Words("Linen Cloth", { { at = 100, price = 40 } }, 100 + HOUR)
    t.ok(head:find("Linen Cloth", 1, true) == 1 and head:find(PC.Span(HOUR), 1, true) ~= nil, head)
    t.eq(line, PC.ONE_LOOK)
    _, line = PC.Words("Linen Cloth", PTS, 4 * DAY)
    t.ok(line:find("3 looks over " .. PC.Span(4 * DAY), 1, true) ~= nil, line)
    t.ok(line:find(PC.ChangeText(0.5), 1, true) ~= nil, line)
end

tests["price chart E-41: Alt alone on an item link opens the chart, when switched on"] = function(t)
    local link = "|cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|r"
    t.eq(PC.IsChartClick(link, true, false, false, true), 2589)
    t.eq(PC.IsChartClick(link, true, true, false, true), nil, "with Ctrl")
    t.eq(PC.IsChartClick(link, true, false, true, true), nil, "with Shift")
    t.eq(PC.IsChartClick(link, false, false, false, true), nil, "no Alt")
    t.eq(PC.IsChartClick(link, true, false, false, false), nil, "switched off")
    t.eq(PC.IsChartClick("no link", true, false, false, true), nil)
    t.eq(PC.CLICK_SETTING, "items.chartClick")
end

return tests
