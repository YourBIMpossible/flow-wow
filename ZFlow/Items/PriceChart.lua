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

-- Parity row E-41, the data half (lead section 787): the chart window's
-- numbers and words, as Flow's Modules/Items/PriceChart.lua, in our own
-- words. Pure, like the rest of this file. The window is the drawing
-- lane's (a MUSE NEED); the hook on a modified item click is the lead's
-- (a LEAD NEED: HandleModifiedItemClick, calling IsChartClick). It only
-- opens a chart; nothing is bought or posted.
--   PC.Axis(lo, hi[, pad]) -> bottom, top   room around the spread (:64)
--   PC.Place(points, w, h[, pad]) -> { { x, y, at, price } }   in a w by h
--     box, x from the left, y from the bottom; time to scale (:71)
--   PC.Ticks(t0, t1, n) -> { { at, share } }   the time labels (:114)
--   PC.Stamp(at, span, date) -> text   date: the client's date(fmt, at);
--     the hour within two days, else the day (:127)
--   PC.Words(name, points, now) -> title, line   above the chart (:139)
--   PC.IsChartClick(link, alt, ctrl, shift, on) -> itemID | nil   Alt alone
--     on an item link, with CLICK_SETTING on (:338)
PC.PAD = 0.12          -- as Flow: room above and under, a share of the spread
PC.TWO_DAYS = 2 * 86400
PC.STAMP_HOUR = "%d %b %H:%M"
PC.STAMP_DAY = "%d %b"
-- A new setting row, on as made (as Flow's chartClick): a changed
-- behaviour, reviewed from another lane (lead section 557). Its row is in
-- Items/AuctionLog.lua, beside the tooltip's.
PC.CLICK_SETTING = "items.chartClick"
PC.NO_LOOKS = "No auction price seen yet: one is noted each time a search of yours lists it."
PC.ONE_LOOK = "Seen once so far: each search that lists it adds a point."
PC.LOOKS = "Low %s, high %s, average %s: %d looks over %s%s."

function PC.Axis(lo, hi, pad)
    if not finite(lo) or not finite(hi) then return 0, 1 end
    local room
    if hi > lo then
        room = (hi - lo) * (tonumber(pad) or PC.PAD)
    else
        room = math.max(1, hi * 0.1)
    end
    return math.max(0, lo - room), hi + room
end

function PC.Place(points, w, h, pad)
    local out = {}
    local t0, t1, lo, hi = PC.Range(points)
    if not t0 or not finite(w) or not finite(h) then return out end
    local bottom, top = PC.Axis(lo, hi, pad)
    for i, p in ipairs(points) do
        local x, y = w / 2, h / 2
        if t1 > t0 then x = (p.at - t0) / (t1 - t0) * w end
        if top > bottom then y = (p.price - bottom) / (top - bottom) * h end
        out[i] = { x = x, y = y, at = p.at, price = p.price }
    end
    return out
end

function PC.Ticks(t0, t1, n)
    if not finite(t0) or not finite(t1) then return {} end
    if t1 <= t0 then return { { at = t0, share = 0.5 } } end
    n = math.max(2, math.floor(tonumber(n) or 3))
    local out = {}
    for i = 0, n - 1 do
        local share = i / (n - 1)
        out[#out + 1] = { at = t0 + (t1 - t0) * share, share = share }
    end
    return out
end

function PC.Stamp(at, span, date)
    if type(date) ~= "function" or not finite(at) then return nil end
    local fmt = PC.STAMP_DAY
    if (tonumber(span) or 0) < PC.TWO_DAYS then fmt = PC.STAMP_HOUR end
    local ok, text = pcall(date, fmt, at)
    if ok and type(text) == "string" then return text end
    return nil
end

function PC.Words(name, points, now)
    local title = tostring(name or "?")
    local s = PC.Stats(points)
    if not s then return title, PC.NO_LOOKS end
    local coin = ns.Prices.Coin
    local t0, t1 = PC.Range(points)
    local head = title .. ": " .. coin(s.now) .. " each"
    if finite(now) and now >= t1 then head = head .. ", " .. PC.Span(now - t1) .. " ago" end
    if s.looks == 1 then return head, PC.ONE_LOOK end
    local change = PC.ChangeText(s.change)
    local tail = ""
    if change then tail = ", " .. change end
    return head, PC.LOOKS:format(coin(s.low), coin(s.high), coin(s.avg), s.looks, PC.Span(t1 - t0), tail)
end

function PC.IsChartClick(link, alt, ctrl, shift, on)
    if on ~= true or alt ~= true or ctrl == true or shift == true then return nil end
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("item:(%d+)"))
end
