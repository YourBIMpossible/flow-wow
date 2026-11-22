local _, ns = ...

-- S4 price chart, tooltip only: the pure core. Ported from legacy Flow's
-- Modules/Items/PriceChart.lua (0.35.301; the owner asked to see "its price
-- over history like commodities or stocks"); research:
-- WoW/from-plexy/RESEARCH-price-chart.md.
--
-- What is ported: reading an item's auction looks (each the cheapest
-- buyout for one, and when) into points, oldest first; their range,
-- lowest, highest, average and the change from the first look to the last;
-- and, in place of legacy Flow's window, the lines an item's tooltip shows.
-- Not wired yet: Z-Flow has no auction read (L6-F, a lead decision) and no
-- saved history of looks, so nothing calls this in game. The note says what
-- the wiring needs.
--
--   PriceChart.Points(e) -> { { at =, price = }, ... } oldest first
--     e: legacy Flow's entry ({ h = { at, price, at, price, ... } }, or the
--     older { looks = { { price =, at = }, ... } } newest first, or
--     { price =, at = }), or a Z-Flow price book entry ({ value =, seenAt = }).
--     A look without a time or a price is left out, never guessed.
--   PriceChart.Range(points) -> first, last, lowest, highest (nil: no points)
--   PriceChart.Stats(points) -> { now, low, high, avg, looks, change } or nil
--   PriceChart.ChangeText(change) -> "up 25%", "down 8%", "unchanged" or nil
--   PriceChart.Span(seconds) -> "40 min", "5 h", "3 days"
--   PriceChart.TipLines(points, now) -> the tooltip's lines; none for no
--     looks (an item nobody listed says nothing rather than "unknown" on
--     every tooltip)
--
-- Pure: nothing here reads the game, the clock or the saved data, and
-- nothing buys, sells, posts or bids.
local PC = {}
ns.PriceChart = PC

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function look(out, at, price)
    if finite(at) and finite(price) and price >= 0 then out[#out + 1] = { at = at, price = price } end
end

function PC.Points(e)
    local out = {}
    if type(e) ~= "table" then return out end
    if type(e.h) == "table" and #e.h >= 2 then
        for i = 1, #e.h - 1, 2 do look(out, e.h[i], e.h[i + 1]) end
    elseif type(e.looks) == "table" then
        for i = #e.looks, 1, -1 do
            local l = e.looks[i]
            if type(l) == "table" then look(out, l.at, l.price) end
        end
    elseif e.price ~= nil then
        look(out, e.at, e.price)
    else
        look(out, e.seenAt, e.value)
    end
    table.sort(out, function(a, b) return a.at < b.at end)
    return out
end

function PC.Range(points)
    if type(points) ~= "table" or #points == 0 then return nil end
    local t0, t1, lo, hi = points[1].at, points[1].at, points[1].price, points[1].price
    for _, p in ipairs(points) do
        t0, t1 = math.min(t0, p.at), math.max(t1, p.at)
        lo, hi = math.min(lo, p.price), math.max(hi, p.price)
    end
    return t0, t1, lo, hi
end

function PC.Stats(points)
    if type(points) ~= "table" or #points == 0 then return nil end
    local _, _, lo, hi = PC.Range(points)
    local sum = 0
    for _, p in ipairs(points) do sum = sum + p.price end
    local first, last = points[1].price, points[#points].price
    return { now = last, low = lo, high = hi, avg = sum / #points, looks = #points,
             change = (#points > 1 and first > 0) and (last - first) / first or nil }
end

function PC.ChangeText(change)
    if not finite(change) then return nil end
    local pct = math.floor(math.abs(change) * 100 + 0.5)
    if pct == 0 then return "unchanged" end
    return string.format("%s %d%%", change > 0 and "up" or "down", pct)
end

function PC.Span(seconds)
    seconds = finite(seconds) and math.max(0, seconds) or 0
    if seconds < 3600 then return string.format("%d min", math.floor(seconds / 60)) end
    if seconds < 2 * 86400 then return string.format("%d h", math.floor(seconds / 3600)) end
    return string.format("%d days", math.floor(seconds / 86400))
end

function PC.TipLines(points, now)
    local s = PC.Stats(points)
    if not s then return {} end
    local coin = ns.Prices.Coin
    local t0, t1 = PC.Range(points)
    local head = "Auction: " .. coin(s.now) .. " each"
    if finite(now) and now >= t1 then head = head .. ", " .. PC.Span(now - t1) .. " ago" end
    if s.looks == 1 then return { head } end
    local change = PC.ChangeText(s.change)
    return { head, string.format("Low %s, high %s, average %s: %d looks over %s%s", coin(s.low), coin(s.high),
        coin(s.avg), s.looks, PC.Span(t1 - t0), change and (", " .. change) or "") }
end
