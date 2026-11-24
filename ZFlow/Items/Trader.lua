local _, ns = ...

-- The trader (S2): deals among the auction searches you run yourself. Ported
-- from Flow's Modules/Items/Trader.lua, advice only: the rules and the
-- numbers are Flow's; the buying is not here. Nothing in this file searches,
-- bids, buys, pays or posts.
--
-- Not seen in game: the rows come from Core/Client.lua watchAuctionRows, a
-- first guess that needs a game test. Only the rows the game has already
-- delivered for your own search are judged (at most 50), so a deal further
-- down a long list is not seen.
--
-- A resell deal is judged on a commodity search only: an item search's rows
-- are one kind of item among many (their level, their stats), and one usual
-- price for its itemID would mix them (R4, lead section 179). A vendor deal
-- is judged on both kinds of search. The usual price is made from visits
-- older than AuctionLog.SAME_LOOK, so the search being judged is not one of
-- them (R1).
--
--   usual, n = Trader.Usual(h[, min[, before]])   the middle price of the
--                                            visits, those at `before` or older
--   agg      = Trader.Listing(agg, count, buyout, vendor, usual)
--   rows     = Trader.Deals(aggs[, name, ok, minGain])
--   text     = Trader.Line(row, coin)
--   text     = Trader.Plain(text)           colour marks taken off
--   lines    = Trader.TipLines(row, coin)   the advice for one deal
--   text, r, g, b = Trader.TipLine(row, coin[, now])   one line for an item
--                                            tooltip; with now, how long ago
--   api      = Trader.Declare(k, diag)
--     api.deals()      this session's deals, the larger gain first
--     api.followed()   true once your searches are being followed
--
-- A deal row: { id, name, kind = "vendor" | "resell", qty, cost, gain, limit,
-- usual (resell only), at (when the search showed it) }. Money is copper. The session's list is memory only:
-- nothing is saved.

ns.Trader = {}
local T = ns.Trader

T.NAME = "trader"
T.WORD = "trader"
T.SETTING = "trader.off"
T.HELP = "trader [on|off]: deals among your own auction searches this session; it buys nothing"
T.DEAL = 0.5        -- at this share of the usual price or less: a deal
T.CUT = 0.05        -- the auction house keeps this share of a sale
T.MIN_LOOKS = 4     -- visits needed before there is a usual price
T.MIN_GAIN = 50     -- copper: a smaller gain is not worth a line
T.MAX = 8           -- deals listed in chat
T.COLOUR = { vendor = { 0.25, 1, 0.25 }, resell = { 1, 0.82, 0 } }

-- The usual price: the middle one of the prices seen on your visits, kept
-- as h = { time, price, time, price ... }. nil until there are `min` visits.
-- With `before`, a visit later than it is left out.
function T.Usual(h, min, before)
    local prices = {}
    for i = 2, #(h or {}), 2 do
        if type(before) ~= "number" or (type(h[i - 1]) == "number" and h[i - 1] <= before) then
            prices[#prices + 1] = h[i]
        end
    end
    if #prices < (min or T.MIN_LOOKS) then return nil, #prices end
    table.sort(prices)
    local mid = math.floor((#prices + 1) / 2)
    return (#prices % 2 == 1) and prices[mid] or (prices[mid] + prices[mid + 1]) / 2, #prices
end

-- Adds one listing (count of them for buyout in all) to the item's sums, if
-- it is under what a vendor pays or at T.DEAL of the usual price or less.
-- A listing that is neither leaves agg as it was (nil stays nil).
function T.Listing(agg, count, buyout, vendor, usual)
    if not (count and buyout) or count <= 0 or buyout <= 0 then return agg end
    local unit = buyout / count
    local underVendor = vendor and vendor > 0 and unit < vendor
    local underUsual = usual and usual > 0 and unit <= usual * T.DEAL
    if not (underVendor or underUsual) then return agg end
    agg = agg or { vq = 0, vc = 0, dq = 0, dc = 0, vendor = vendor, usual = usual }
    if underVendor then agg.vq, agg.vc = agg.vq + count, agg.vc + buyout end
    if underUsual then agg.dq, agg.dc = agg.dq + count, agg.dc + buyout end
    return agg
end

-- The deals in aggs = { [id] = agg }: the vendor one where there is one (its
-- gain is certain), else the resell one, its gain less the house's cut.
-- ok(id) false leaves an item out. The larger gain first, then the lower id.
function T.Deals(aggs, name, ok, minGain)
    local out = {}
    for id, a in pairs(aggs or {}) do
        if not ok or ok(id) then
            local row
            if a.vq > 0 then
                row = { id = id, kind = "vendor", qty = a.vq, cost = a.vc,
                        gain = a.vendor * a.vq - a.vc, limit = a.vendor }
            elseif a.dq > 0 then
                row = { id = id, kind = "resell", qty = a.dq, cost = a.dc,
                        gain = a.usual * (1 - T.CUT) * a.dq - a.dc, limit = a.usual * T.DEAL, usual = a.usual }
            end
            if row and row.gain >= (minGain or T.MIN_GAIN) then
                row.name = (name and name(id)) or ("item " .. id)
                out[#out + 1] = row
            end
        end
    end
    table.sort(out, function(x, y)
        if x.gain ~= y.gain then return x.gain > y.gain end
        return x.id < y.id
    end)
    return out
end

-- One deal as a line of text; coin(copper) writes the money.
function T.Line(row, coin)
    if row.kind == "vendor" then
        return string.format("%d x %s for %s: a vendor pays %s  |cff40ff40+%s|r",
            row.qty, row.name, coin(row.cost), coin(row.limit * row.qty), coin(row.gain))
    end
    return string.format("%d x %s for %s: usually %s each  |cffffd100about +%s|r",
        row.qty, row.name, coin(row.cost), coin(row.usual), coin(row.gain))
end

-- A line without its colour marks, for a list in chat.
function T.Plain(text)
    return (tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- What to make of one deal, as advice. Nothing here says what will be paid:
-- the buying is yours.
function T.TipLines(row, coin)
    if row.kind == "vendor" then
        return { string.format(
            "Listed under what a vendor pays (%s each). Buy it, sell it to any vendor: the gain is certain.",
            coin(row.limit)) }
    end
    return {
        string.format("Listed at half or less of its usual price here (%s each, from your own searches). "
            .. "Buy it and post it again: a guess, not a promise.", coin(row.usual)),
        "The auction house's 5% is taken off the gain; the deposit isn't, and it may not sell.",
    }
end

-- The one line an item's tooltip gets while it is in the session's list,
-- with its colour; nil when there is nothing to say. Given now, it says how
-- long ago the search showed it, in the auction line's words (R2).
function T.TipLine(row, coin, now)
    if type(row) ~= "table" or type(row.qty) ~= "number" or row.qty <= 0 or type(row.cost) ~= "number" then
        return nil
    end
    local each = coin(row.cost / row.qty)
    local seen = ""
    if type(now) == "number" and type(row.at) == "number" and now >= row.at then
        seen = " (seen " .. ns.PriceChart.Span(now - row.at) .. " ago)"
    end
    if row.kind == "vendor" then
        local c = T.COLOUR.vendor
        return string.format("Deal: listed at %s each, under a vendor's %s%s", each, coin(row.limit), seen),
            c[1], c[2], c[3]
    end
    local c = T.COLOUR.resell
    return string.format("Deal: listed at %s each, usually %s%s", each, coin(row.usual), seen), c[1], c[2], c[3]
end

function T.Declare(k, diag)
    local api = {}
    local ctx, cancel
    local followed = false
    local deals = {}        -- [itemID] = deal row, this session only
    local coin = ns.Prices.Coin

    local function sorted()
        local out = {}
        for _, row in pairs(deals) do out[#out + 1] = row end
        table.sort(out, function(x, y)
            if x.gain ~= y.gain then return x.gain > y.gain end
            return x.id < y.id
        end)
        return out
    end
    function api.deals() return sorted() end
    function api.followed() return followed end

    local function off() return ctx ~= nil and ctx.settings:get(T.SETTING) == true end

    -- What the item is, as the bank and the posting list know it.
    local function entry(id)
        local ok, entries = pcall(ns.Bank.Entries, { { item = id, count = 1 } }, ctx.client.itemInfo)
        return ok and type(entries) == "table" and entries[1] or nil
    end

    -- The rule the posting list uses: only what you would sell is a deal.
    -- An item that cannot be judged is not a candidate.
    local function candidate(id)
        local ok, yes = pcall(function()
            local item = entry(id)
            if type(item) ~= "table" then return false end
            local decision = ns.Disposition.Decide(item, ns.BankList.Context(ctx.store, nil))
            return ns.Posting.Candidate(decision, item)
        end)
        return ok and yes == true
    end

    -- The usual price here, from your own recorded looks (Items/AuctionLog):
    -- the realm table AuctionLog keeps this session, not a read a search.
    local function usualFor(id)
        local rk = ns.AuctionLog.Key(ctx.client)
        local saved = rk and ns.AuctionLog.Kept(ctx.store).realm(rk)
        local e = type(saved) == "table" and saved[id] or nil
        if type(e) ~= "table" or type(e.h) ~= "table" then return nil end
        local now = ctx.client.clock()
        if type(now) ~= "number" then return nil end
        return (T.Usual(e.h, nil, now - ns.AuctionLog.SAME_LOOK))
    end

    -- One of your searches answered: rows = { { unit =, qty = } ... }, kind
    -- "commodity" or "item". The item's place in the list is made again from
    -- these rows alone. A row without a count is passed over: how many is
    -- not guessed. A usual price is used for a commodity search only.
    local function judge(id, rows, kind)
        if type(id) ~= "number" or type(rows) ~= "table" then return end
        local item = entry(id)
        local vendor = type(item) == "table" and type(item.sellPrice) == "number" and item.sellPrice or nil
        local usual = kind == "commodity" and usualFor(id) or nil
        local agg
        for i = 1, #rows do
            local row = rows[i]
            if type(row) == "table" and type(row.unit) == "number" and type(row.qty) == "number" then
                agg = T.Listing(agg, row.qty, row.unit * row.qty, vendor, usual)
            end
        end
        local found = agg and T.Deals({ [id] = agg }, function()
            return type(item) == "table" and type(item.name) == "string"
                and ns.ItemPresent.Tint(item.name, item.quality) or nil
        end, candidate)[1] or nil
        if found then found.at = ctx.client.clock() end
        local was = deals[id]
        deals[id] = found
        if found and not was and not off() then
            ctx.client.print("Deal: " .. T.Line(found, coin))
        end
    end

    local function say(text) k.client.print(text) end

    local function run(arg)
        local title = k.id.title
        if not ctx then
            say(title .. " Trader: not started yet")
            return
        end
        local word = type(arg) == "string" and arg:lower():match("^%s*(%S*)") or ""
        if word == "on" or word == "off" then
            ctx.settings:set(T.SETTING, word == "off")
            say(title .. " Trader " .. word)
            return
        end
        local list = sorted()
        say(string.format("%s Trader%s: %d deal(s) from your searches this session",
            title, off() and " (off)" or "", #list))
        say(string.format(
            "  resell at %d%% of the usual price or less, from %d visits; the house keeps %d%%, the deposit is not counted",
            T.DEAL * 100, T.MIN_LOOKS, T.CUT * 100))
        for i = 1, math.min(#list, T.MAX) do say("  " .. T.Plain(T.Line(list[i], coin))) end
        say("Buying is yours, in the auction window: " .. title .. " buys nothing.")
    end
    if type(diag) == "table" then
        if type(diag.commands) == "table" then diag.commands[T.WORD] = run end
        if type(diag.help) == "table" then diag.help[T.WORD] = T.HELP end
    end

    k:Module({
        name = T.NAME,
        needs = { "client", "store", "settings" },
        settings = { {
            key = T.SETTING, scope = "account", type = "bool", default = false,
            label = "Trader: say nothing of deals",
            help = "On: no chat line and no tooltip line for a deal in your own auction searches. "
                .. "The trader word still lists them. It never buys.",
            group = "auctions", synonyms = { "deals", "auction", "bargain", "flip", "ah" },
        } },
        provides = { Deals = api.deals, Followed = api.followed },
        start = function(c)
            ctx = c
            local client = c.client
            if type(client.watchAuctionRows) == "function" then
                followed = client.watchAuctionRows(function(id, rows, kind) pcall(judge, id, rows, kind) end) == true
            end
            if type(client.onItemTooltip) == "function" then
                cancel = client.onItemTooltip(function(link, add)
                    if type(add) ~= "function" or off() then return end
                    local ok, text, r, g, b = pcall(function()
                        local id = ns.Items.Id(link)
                        return T.TipLine(id ~= nil and deals[id] or nil, coin, ctx.client.clock())
                    end)
                    if ok and type(text) == "string" then add(text, r, g, b) end
                end)
            end
        end,
        stop = function()
            if type(cancel) == "function" then cancel() end
            cancel = nil
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.trader = T.Declare(ns, ns.diag)
