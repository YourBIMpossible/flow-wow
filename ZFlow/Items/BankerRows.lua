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
--   BR.SellRows(bags, bank[, rules[, taken]]) -> rows; bags and bank: { {
--     key, name, count, quality, decision } } (bank's also classID, step,
--     quest, hold). A row: { key, name, count, quality, reason,
--     kept = true | nil, bank = true | nil, next = "keep" | "sell" }; a bank
--     row is BankTakeOut's row (also id, take, mine, slots). taken: rows
--     already made by BankTakeOut (List().rows); then bank is not read.
--     E-19 join: the bank half is BankTakeOut.Rows, so a banked weapon,
--     armor or quest thing is not offered to sell (Flow's B.NOT_OUT), and
--     one whose kind (classID) was not read is not offered either.
--   BR.SellNote(rows, atBank) -> the line above the to-sell rows
--   BR.NextChoice(kept, reset) -> "sell" | "keep" | nil
-- Lead section 767.3c: as Flow's B.TakeOutRows (:321-326), a bank thing the
-- route wants (e.step, the step's words) or a quest wants (e.quest, its
-- title) is taken out too, the route first: { bank, take = "route" |
-- "quest", reason, next = nil } (no keep or sell choice for those). Then a
-- thing a reservation holds that no route stop names (e.hold, its reason;
-- lead section 776): take = "hold", the same shape. A bank
-- thing to sell has take = "sell". mine = true marks your own choice (a
-- sell or a keep by the rule "yourChoice"), as Flow's r.mine. The auction
-- house is never a way out here (owner boundary).
-- Not tested in game.
local BR = {}
ns.BankerRows = BR

BR.NOT_SEEN = "Your bank hasn't been seen yet. Open it once and it is remembered."
BR.BANK_SOME = "%d thing(s) in your bank, as seen %s:"
BR.LAST_VISIT = "at your last visit"
BR.KEPT = { yourChoice = "your choice", neverSell = "on your never-sell list" }
BR.NOTHING = "Nothing to sell: everything in your bags and your bank is kept."
BR.ONLY_KEPT = "Nothing to sell. Below: %d thing(s) kept because you chose to; a click sells one instead."
BR.BAGS = "%d thing(s) in your bags to sell at the next vendor."
BR.BANK_AWAY = " %d more in your bank to take out, to sell or for a quest or your route: at a bank."
BR.BANK_AT = " %d more in your bank to take out, to sell or for a quest or your route: now."
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

local function listOf(v)
    if type(v) == "table" then return v end
    return {}
end

-- The rule of the part of a decision that sells, or the decision's own.
local function sellRule(d)
    local first = d
    while type(d) == "table" do
        if d.action == "sell" then return d.rule end
        d = d.rest
    end
    if type(first) == "table" then return first.rule end
    return nil
end

local function row(e, extra)
    local r = { key = e.key, name = nameOf(e), count = e.count, quality = e.quality }
    for k, v in pairs(extra) do r[k] = v end
    r.next = BR.NextChoice(r.kept)
    return r
end

-- rules: settings.banker.rules ({ [key] = "bank" | "carry" }, as Items/
-- Bank.lua reads it, context.bankRules), passed in. A thing whose rule is
-- "bank" is never taken out of the bank (Flow B.TakeOutRows :316; Twin,
-- lead section 774). nil: no rules.
-- E-19 one-source join: the bank half is BankTakeOut's rule (Items/
-- BankTakeOut.lua Rows, Flow's B.TakeOutRows): rows handed in as taken
-- (BankTakeOut.List().rows), else BankTakeOut.Rows on bank's entries (their
-- step, quest and hold, and a sell where the decision sells). A thing to
-- sell needs its kind read (classID), and a weapon, armor or quest thing is
-- never offered to sell (NOT_OUT); one a route step, quest or hold wants is.
local function bankHalf(bank, rules)
    local items, sold = {}, {}
    for _, e in ipairs(listOf(bank)) do
        if type(e) == "table" and e.key ~= nil then
            items[#items + 1] = e
            local d = e.decision
            if type(d) == "table" and d.action ~= "keep" and sells(d) then
                local s = { key = e.key, name = e.name, count = e.count, quality = e.quality,
                            reason = sellReason(d) or BR.NO_REASON }
                if sellRule(d) == "yourChoice" then s.mine = true end
                sold[#sold + 1] = s
            end
        end
    end
    return ns.BankTakeOut.Rows(items, sold, rules, nil)
end

function BR.SellRows(bags, bank, rules, taken)
    local out, kept, inBank = {}, {}, {}
    for _, e in ipairs(listOf(bags)) do
        if type(e) == "table" and type(e.decision) == "table" then
            local d = e.decision
            if d.action == "keep" and BR.KEPT[d.rule or ""] then
                local r = row(e, { kept = true, reason = BR.KEPT[d.rule] })
                if d.rule == "yourChoice" then r.mine = true end
                kept[#kept + 1] = r
            elseif sells(d) then
                local r = row(e, { reason = sellReason(d) or BR.NO_REASON })
                if sellRule(d) == "yourChoice" then r.mine = true end
                out[#out + 1] = r
            end
        end
    end
    -- You keep it in the bank (rules): not listed, whatever wants it; the
    -- order is the rule's own (one sort by name, then key).
    local rows = taken
    if type(rows) ~= "table" then rows = bankHalf(bank, rules) end
    for _, t in ipairs(listOf(rows)) do
        if type(t) == "table" and t.key ~= nil then
            local r = {}
            for k, v in pairs(t) do r[k] = v end
            r.name = nameOf(t)
            r.bank = true
            inBank[#inBank + 1] = r
        end
    end
    for _, r in ipairs(kept) do out[#out + 1] = r end
    for _, r in ipairs(inBank) do out[#out + 1] = r end
    return out
end

function BR.SellNote(rows, atBank)
    local nBags, nKept, nBank = 0, 0, 0
    for _, r in ipairs(listOf(rows)) do
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
