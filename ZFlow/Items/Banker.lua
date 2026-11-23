local _, ns = ...

-- S1 slice 1: the banker word. Legacy Flow's `/flow banker` (Modules/Items/
-- Banker.lua) and its window's "In your bank" and "To sell" views, as three
-- short lists in chat. Research: WoW/from-plexy/RESEARCH-banker.md.
--
--   to bank now    Bank.Pick over the bags, the same as the bank list panel
--                  (UI/BankList.lua) shows at the bank
--   in your bank   what the bank held at your last visit (char
--                  "learned.bankCounts", kept by Items/HaveTip.lua), with how
--                  long ago: the game tells add-ons the bank only while it is
--                  open
--   to sell        of those, what the sell rules (Disposition.Decide) would
--                  now sell, with the reason
--
-- One reservations evaluation (Items/Reservations.lua) per word: "to bank"
-- counts what the goals hold in the bags, "to sell" what they hold in the
-- bank, so nothing is counted twice. When the reservations are not known,
-- nothing in the bank is offered for sale.
--
-- LOOK ONLY (§156 §8). Nothing here deposits, withdraws, moves, sells or
-- picks up anything; there are no buttons.
--
--   Banker.Items(saved, itemInfo) -> the bank's items, or nil when not seen
--   Banker.InBankLines(items, at, now, max) -> lines
--   Banker.SellRows(items, context) -> rows, or nil when not seen
--   Banker.SellLines(rows, max) -> lines
--   Banker.Declare(k, diag) -> api   (api.runs())
--
--   <slash> banker   the three lists
local B = {}
ns.Banker = B

B.NAME = "banker"
B.WORD = "banker"
B.HELP = "what to put in the bank now, what your bank held at your last visit, "
    .. "and what in it you would now sell; it moves nothing"
B.MAX = 10   -- rows a list shows before "and N more."
B.NOT_SEEN = "In your bank: not seen yet. Open your bank once to fill this list."
B.SELL_HEADER = "In your bank, you would now sell (take it out yourself):"
B.NOTHING_TO_SELL = "Nothing in your bank to sell."
B.SELL_NOT_SEEN = "In your bank to sell: not known until your bank is seen."
B.FAILED = "could not be listed this time."
B.SELL_UNKNOWN = "In your bank to sell: reservations not known, so nothing is offered for sale."

local function whole(v)
    return type(v) == "number" and v == v and v >= 0 and v ~= math.huge and v == math.floor(v)
end

local function nameOf(e)
    return ns.ItemPresent.Name(e.key, type(e.name) == "string" and { [e.key] = e.name } or nil)
end

local function byCount(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return tostring(a.name or a.key) < tostring(b.name or b.key)
end

function B.Items(saved, itemInfo)
    local counts = type(saved) == "table" and saved.counts or nil
    if type(counts) ~= "table" then return nil end
    local items, at = {}, {}
    for raw, n in pairs(counts) do
        local key = ns.Items.Key(raw)
        if key ~= nil and whole(n) and n > 0 then
            local e = at[key]
            if e then
                e.count = e.count + n
            else
                e = { key = key, count = n }
                at[key] = e
                items[#items + 1] = e
                if type(itemInfo) == "function" then
                    local ok, f = pcall(itemInfo, ns.Items.Id(key))
                    if ok and type(f) == "table" then
                        if type(f.name) == "string" and f.name ~= "" then e.name = f.name end
                        if whole(f.quality) then e.quality = f.quality end
                        if whole(f.sellPrice) then e.sellPrice = f.sellPrice end
                        if whole(f.classID) then e.classID = f.classID end
                    end
                end
            end
        end
    end
    table.sort(items, byCount)
    return items
end

-- Rows, then "and N more." past max.
local function listed(lines, rows, max, text)
    max = whole(max) and max or B.MAX
    for i = 1, math.min(#rows, max) do lines[#lines + 1] = text(rows[i]) end
    if #rows > max then lines[#lines + 1] = "and " .. (#rows - max) .. " more." end
    return lines
end

function B.InBankLines(items, at, now, max)
    if type(items) ~= "table" then return { B.NOT_SEEN } end
    local when = "your last visit"
    if whole(at) and whole(now) and now >= at then when = ns.PriceChart.Span(now - at) .. " ago" end
    if #items == 0 then return { "In your bank, as of " .. when .. ": nothing." } end
    return listed({ "In your bank, as of " .. when .. ":" }, items, max, function(e)
        return e.count .. " x " .. nameOf(e)
    end)
end

-- The reason of the part of a decision that sells.
local function sellReason(d)
    while type(d) == "table" do
        if d.action == "sell" then return d.reason end
        d = d.rest
    end
    return nil
end

function B.SellRows(items, context)
    if type(items) ~= "table" then return nil end
    local D, rows = ns.Disposition, {}
    for _, e in ipairs(items) do
        local d = D.Decide(e, context)
        local n = D.CountOf(d, "sell")
        if n == nil or n > 0 then
            rows[#rows + 1] = { key = e.key, name = e.name, count = n,
                                reason = sellReason(d) or "the sell rules would sell it" }
        end
    end
    return rows
end

function B.SellLines(rows, max)
    if type(rows) ~= "table" then return { B.SELL_NOT_SEEN } end
    if #rows == 0 then return { B.NOTHING_TO_SELL } end
    return listed({ B.SELL_HEADER }, rows, max, function(r)
        local head = whole(r.count) and (r.count .. " x " .. nameOf(r)) or nameOf(r)
        return head .. ": " .. tostring(r.reason)
    end)
end

function B.Declare(k, diag)
    local api = {}
    local ctx, runs = nil, 0
    function api.runs() return runs end

    -- One list; when it raises, one line says so and the others still show.
    local function section(say, label, make)
        local ok, lines = pcall(make)
        if not ok or type(lines) ~= "table" then
            say(label .. ": " .. B.FAILED)
            return
        end
        for _, line in ipairs(lines) do say(line) end
    end

    local function run()
        local function say(s) k.client.print(k.id.title .. ": " .. s) end
        if not ctx then say(B.WORD .. ": not started yet") return end
        runs = runs + 1
        local client, store = ctx.client, ctx.store
        local R = ns.Reservations
        local r = ns.BankList.Current(ctx.use)
        local grants = R.Grants(r)
        section(say, "To bank", function()
            return ns.BankList.Lines(client, store, R.HeldIn(grants, "bags"), r)
        end)
        local saved = store:get("char", ns.HaveTip.PATH)
        local items
        section(say, "In your bank", function()
            items = B.Items(saved, client.itemInfo)
            local now = type(client.clock) == "function" and client.clock() or nil
            return B.InBankLines(items, type(saved) == "table" and saved.at or nil, now)
        end)
        section(say, "To sell", function()
            if r.status == R.UNAVAILABLE then return { B.SELL_UNKNOWN } end
            return B.SellLines(B.SellRows(items, ns.BankList.Context(store, R.HeldIn(grants, "bank"))))
        end)
    end

    if diag and type(diag.commands) == "table" then
        diag.commands[B.WORD] = run
        if type(diag.help) == "table" then diag.help[B.WORD] = B.HELP end
    end

    k:Module({
        name = B.NAME,
        needs = { "client", "store" },
        start = function(c) ctx = c end,
        stop = function() ctx = nil end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.banker = B.Declare(ns, ns.diag)
