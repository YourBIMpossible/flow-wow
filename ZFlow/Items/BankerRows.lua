local _, ns = ...

-- Parity rows E-22 + E-23, the data half (lead section 755): the rows of
-- the banker window's "In your bank" view, away from a bank, and its "To
-- sell" view, where a click keeps a thing or sells it after all. As Flow's
-- Modules/Items/Banker.lua:
--   B.BankRows (:647-656)       the bank's things by name ("item <id>"
--                                when the name is not read)
--   the "bank" view (:707-715)  its header: not seen yet, or how many and
--                                how long ago
--   B.SellRows (:255-274)       what the sell rules sell, then what you keep
--                                by your own choice (marked kept, with why)
--   B.TakeOutRows (:313-336)    then what in the bank they would sell
--   B.SellLines (:359-387)      the note above the list
--   B.NextSellChoice (:1105-08) what a click makes a row: kept -> sell,
--                                else keep; a reset -> the rules' own (nil)
-- Pure: no client read, nothing saved or sold. The inputs are what
-- Items/Banker.lua already reads (B.Items over the saved bank counts) and
-- Disposition.Decide's answer per thing, worked out by the caller. Writing
-- the choice is Items/Keep.lua's (the never-sell list); the window, its
-- lines and the click are the drawing lane's (a MUSE NEED). Look only: a
-- row never takes anything out of the bank.
--
--   BR.BankRows(items) -> { { key, name, count } } by name, or nil (not seen)
--   BR.BankHeader(rows, at, now) -> the line above the bank's rows
--   BR.SellRows(bags, bank) -> rows; bags and bank: { { key, name, count,
--     quality, decision } }. A row: { key, name, count, quality, reason,
--     kept = true | nil, bank = true | nil, next = "keep" | "sell" }
--   BR.SellNote(rows, atBank) -> the line above the to-sell rows
--   BR.NextChoice(kept, reset) -> "sell" | "keep" | nil
-- Not tested in game.
local BR = {}
ns.BankerRows = BR

BR.NOT_SEEN = "Your bank hasn't been seen yet. Open it once and it is remembered."
BR.BANK_SOME = "%d thing(s) in your bank, as seen %s:"
BR.LAST_VISIT = "at your last visit"
BR.KEPT = { yourChoice = "your choice", neverSell = "on your never-sell list" }
BR.NOTHING = "Nothing to sell: everything in your bags and your bank is kept."
BR.ONLY_KEPT = "Nothing to sell now. %d thing(s) you keep by your own choice are listed: click one to sell it after all."
BR.BAGS = "%d thing(s) in your bags to sell at the next vendor."
BR.BANK_AWAY = " %d more in your bank to sell: take them out at a bank."
BR.BANK_AT = " %d more in your bank to sell: take them out now."
BR.NO_REASON = "the sell rules would sell it"

local function whole(v)
    return type(v) == "number" and v == v and v >= 0 and v ~= math.huge and v == math.floor(v)
end

local function nameOf(e)
    if type(e.name) == "string" and e.name ~= "" then return e.name end
    return "item " .. tostring(e.key)
end

local function byName(a, b)
    if a.name ~= b.name then return a.name < b.name end
    return tostring(a.key) < tostring(b.key)
end

function BR.BankRows(items)
    if type(items) ~= "table" then return nil end
    local out = {}
    for _, e in ipairs(items) do
        if type(e) == "table" and e.key ~= nil and whole(e.count) and e.count > 0 then
            out[#out + 1] = { key = e.key, name = nameOf(e), count = e.count }
        end
    end
    table.sort(out, byName)
    return out
end

function BR.BankHeader(rows, at, now)
    if type(rows) ~= "table" then return BR.NOT_SEEN end
    local when = BR.LAST_VISIT
    if whole(at) and whole(now) and now >= at then when = ns.PriceChart.Span(now - at) .. " ago" end
    return BR.BANK_SOME:format(#rows, when)
end

function BR.NextChoice(kept, reset)
    if reset then return nil end
    if kept then return "sell" end
    return "keep"
end

-- The reason of the part of a decision that sells.
local function sellReason(d)
    while type(d) == "table" do
        if d.action == "sell" then return d.reason end
        d = d.rest
    end
    return nil
end

local function sells(d)
    local n = ns.Disposition.CountOf(d, "sell")
    return n == nil or n > 0
end

local function row(e, extra)
    local r = { key = e.key, name = nameOf(e), count = e.count, quality = e.quality }
    for k, v in pairs(extra) do r[k] = v end
    r.next = BR.NextChoice(r.kept)
    return r
end

function BR.SellRows(bags, bank)
    local out, kept, inBank = {}, {}, {}
    for _, e in ipairs(type(bags) == "table" and bags or {}) do
        if type(e) == "table" and type(e.decision) == "table" then
            local d = e.decision
            if d.action == "keep" and BR.KEPT[d.rule or ""] then
                kept[#kept + 1] = row(e, { kept = true, reason = BR.KEPT[d.rule] })
            elseif sells(d) then
                out[#out + 1] = row(e, { reason = sellReason(d) or BR.NO_REASON })
            end
        end
    end
    for _, e in ipairs(type(bank) == "table" and bank or {}) do
        if type(e) == "table" and type(e.decision) == "table" and e.decision.action ~= "keep" and sells(e.decision) then
            inBank[#inBank + 1] = row(e, { bank = true, reason = sellReason(e.decision) or BR.NO_REASON })
        end
    end
    table.sort(inBank, byName)
    for _, r in ipairs(kept) do out[#out + 1] = r end
    for _, r in ipairs(inBank) do out[#out + 1] = r end
    return out
end

function BR.SellNote(rows, atBank)
    local nBags, nKept, nBank = 0, 0, 0
    for _, r in ipairs(type(rows) == "table" and rows or {}) do
        if r.bank then
            nBank = nBank + 1
        elseif r.kept then
            nKept = nKept + 1
        else
            nBags = nBags + 1
        end
    end
    if nBags + nBank == 0 then
        if nKept > 0 then return BR.ONLY_KEPT:format(nKept) end
        return BR.NOTHING
    end
    local note = BR.BAGS:format(nBags)
    if nBank > 0 then
        if atBank then
            note = note .. BR.BANK_AT:format(nBank)
        else
            note = note .. BR.BANK_AWAY:format(nBank)
        end
    end
    return note
end
