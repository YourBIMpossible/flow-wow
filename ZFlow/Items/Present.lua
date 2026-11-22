local _, ns = ...

-- ItemPresent: an ItemPlan result as plain rows and texts for the player.
--
--   view = ItemPresent.View(plan, { names = table or function })
--
-- This is the presenter half of the old skill planner file: the planner
-- (ItemPlan) works things out, and this file only words them. It never
-- counts anything itself, never reads the game, draws no frame and prints
-- nothing. It does not change the plan it is given.
--
-- What it must never blur:
--   * a price nobody has seen reads "price unknown—check vendor" (a plan
--     buys items from a merchant; F-085), and no figure (not 0 either) is
--     shown in its place;
--   * an estimate is always labelled "(estimate)", is never added to an
--     observed figure, and never makes the money line say yes;
--   * a bank that was never seen is said on the row that might be helped by
--     it, and on the "ready" line;
--   * bags that were not read give no "in your bags" count at all: the
--     amounts are worded as "at most".
--
-- view = {
--   ok        as the plan's; false with one line saying why
--   rows      { { key, name, need, state, text, note, parts } } one per plan row
--             state  "have" (nothing more to get), "missing", or "unknown"
--                    (bags unread)
--             parts  one text per source, in the plan's order
--             note   "bank not seen yet: some may be there", a cycle, or nil
--   crafts    { "Make 2 x Bar", ... } in the order to do them; the figure is
--             how many times to craft, not how many come out
--   cost      one text
--   afford    one text, or nil when nothing is bought
--   ready     one text
--   problems  the plan's problems, copied
--   lines     everything above as a flat list of texts, top to bottom
-- }
--
-- names: { [itemKey] = "Name" } or function(itemKey) -> "Name". An item with
-- no name reads "item <key>": a name is never made up.

local Present = {}
ns.ItemPresent = Present

Present.BAGS_UNREAD = "the bags have not been read yet"
Present.BANK_UNSEEN = "the bank has not been seen yet"
Present.BANK_NOTE = "bank not seen yet: some may be there"
Present.CYCLE_NOTE = "can only be made from itself"

-- F-085: a merchant's price for an item that nobody has seen.
local UNKNOWN_PRICE = "price unknown—check vendor"

local function isCount(n)
    return type(n) == "number" and n == n and n >= 0 and n < math.huge
end

local function coin(copper)
    local Prices = ns.Prices
    return Prices and Prices.Coin(copper) or nil
end

local function estimateText(copper)
    local c = coin(copper)
    return c and ("about " .. c .. " (estimate)") or nil
end

-- The name of an item for the player.
function Present.Name(key, names)
    local name
    if type(names) == "table" then
        name = names[key]
    elseif type(names) == "function" then
        local ok, got = pcall(names, key)
        if ok then name = got end
    end
    if type(name) == "string" and name ~= "" then return name end
    return "item " .. tostring(key)
end

-- One source of a plan row, as a text.
function Present.SourceText(s)
    if type(s) ~= "table" or not isCount(s.count) then return "source unknown" end
    local n = s.count
    if s.from == "bags" then return n .. " in your bags" end
    if s.from == "bank" then return n .. " from your bank" end
    if s.from == "vendor" then
        local buy = "buy " .. n .. " from a merchant"
        if s.basis == "observed" and isCount(s.cost) and type(s.text) == "string" then
            return buy .. " at " .. s.text .. " each (" .. tostring(coin(s.cost)) .. ")"
        end
        if s.basis == "estimated" and isCount(s.estimate) and type(s.text) == "string" then
            return buy .. " at " .. s.text .. " each (" .. tostring(estimateText(s.estimate)) .. ")"
        end
        return buy .. ", " .. UNKNOWN_PRICE
    end
    if s.from == "gather" then
        if type(s.what) == "string" and s.what ~= "" then return "gather " .. n .. " (" .. s.what .. ")" end
        return "gather " .. n
    end
    if s.from == "craft" then return "make " .. n end
    return n .. " still to get, source unknown"
end

-- One plan row, as a display row.
function Present.Row(r, names)
    local out = { key = r.key, name = Present.Name(r.key, names), need = r.need, parts = {} }
    for _, s in ipairs(type(r.sources) == "table" and r.sources or {}) do
        out.parts[#out.parts + 1] = Present.SourceText(s)
    end
    local head = tostring(r.need) .. " x " .. out.name .. ": "
    if r.unknown == "bags" then
        out.state = "unknown"
        out.text = head .. "bags not read yet"
        if #out.parts > 0 then out.text = out.text .. "; at most " .. table.concat(out.parts, ", ") end
    else
        local missing = isCount(r.missing) and r.missing or 0
        out.state = missing > 0 and "missing" or "have"
        out.text = head .. (#out.parts > 0 and table.concat(out.parts, ", ") or "nothing needed")
        if r.bankUnseen and missing > 0 then out.note = Present.BANK_NOTE end
    end
    if r.cycle then
        out.note = out.note and (out.note .. "; " .. Present.CYCLE_NOTE) or Present.CYCLE_NOTE
    end
    return out
end

local function costOf(plan)
    local c = type(plan.cost) == "table" and plan.cost or {}
    return isCount(c.known) and c.known or 0, isCount(c.estimated) and c.estimated or 0,
        isCount(c.unknown) and c.unknown or 0
end

-- What the merchant part comes to. An observed figure and an estimate are
-- two figures, never one sum; an unknown price is counted, not priced.
function Present.Cost(plan)
    local known, estimated, unknown = costOf(plan)
    local parts = {}
    if known > 0 then parts[#parts + 1] = tostring(coin(known)) end
    if estimated > 0 then parts[#parts + 1] = tostring(estimateText(estimated)) end
    if unknown > 0 then
        -- The count line ends in the same phrase (F-085).
        parts[#parts + 1] = unknown .. (unknown == 1 and " price " or " prices ") .. "unknown—check vendor"
    end
    if #parts == 0 then return "Nothing to buy" end
    return "To buy: " .. (plan.unknown == "bags" and "at most " or "") .. table.concat(parts, ", plus ")
end

-- Whether the player can pay. nil when nothing is bought.
function Present.Afford(plan)
    local known, estimated, unknown = costOf(plan)
    if known == 0 and estimated == 0 and unknown == 0 then return nil end
    if plan.afford == true then return "You have the money for it" end
    if plan.afford == false then return "Not enough money for it" end
    local why = "your money has not been read"
    if plan.unknown == "bags" then
        why = Present.BAGS_UNREAD
    elseif estimated > 0 or unknown > 0 then
        why = "a price is an estimate or unknown"
    end
    return "Can't tell if you have the money: " .. why
end

-- Whether it can be made from what the player has now.
function Present.Ready(plan)
    if plan.ready == true then return "Ready to make" end
    if plan.ready == false then return "Not ready: something is still to get" end
    return "Can't tell if it is ready: " .. (plan.unknown == "bags" and Present.BAGS_UNREAD or Present.BANK_UNSEEN)
end

-- ---------------------------------------------------------------- sell list
-- The vendor sell list (L6-A): ItemSell.List and SellView.Kept as lines.
-- The same rules as above: a price nobody has seen is "price unknown—check
-- vendor" (F-085's words, with its em dash) and no figure; an estimate is
-- labelled and never added to an observed figure; a count that is not known
-- is said, not guessed.

Present.VENDOR_PRICE_UNKNOWN = "price unknown—check vendor"
Present.SELL_HEADER = "Would sell (nothing is sold for you):"
Present.KEPT_HEADER = "Kept, never sold:"
Present.NOTHING_TO_SELL = "Nothing to sell"

local function plural(n, one, many)
    return n .. " " .. (n == 1 and one or many)
end

-- One row of ItemSell.List, as a text.
function Present.SellRowText(r, names)
    local name = type(r.name) == "string" and r.name ~= "" and r.name or Present.Name(r.key, names)
    local head = isCount(r.count) and (r.count .. " x " .. name) or (name .. " (how many not known)")
    local Prices = ns.Prices
    local price
    if r.basis == Prices.OBSERVED and isCount(r.unit) then
        price = coin(r.unit) .. " each"
        if isCount(r.total) then price = price .. ", " .. coin(r.total) end
        if type(r.source) == "string" and r.source ~= "" then price = price .. " (" .. r.source .. ")" end
    elseif r.basis == Prices.ESTIMATED and isCount(r.unit) and type(r.source) == "string" and r.source ~= "" then
        price = "about " .. coin(r.unit) .. " each (estimate, " .. r.source .. ")"
        if isCount(r.total) then price = price .. ", about " .. coin(r.total) end
    else
        price = Present.VENDOR_PRICE_UNKNOWN
    end
    return head .. ": " .. price
end

-- The price lookup (L6-H): PriceLookup.Find's result as lines. One line for
-- what a vendor pays; a second only when a merchant was seen selling it.
function Present.PriceLines(result, names)
    local Prices = ns.Prices
    local name = type(result.name) == "string" and result.name ~= "" and result.name
        or Present.Name(result.key, names)
    local sell = type(result.sell) == "table" and result.sell or {}
    local first
    if sell.unsellable then
        first = "can't be sold to a merchant"
    elseif sell.basis == Prices.OBSERVED and isCount(sell.unit) then
        first = "a vendor pays " .. coin(sell.unit) .. " each"
        if type(sell.source) == "string" and sell.source ~= "" then first = first .. " (" .. sell.source .. ")" end
    elseif sell.basis == Prices.ESTIMATED and isCount(sell.unit) and type(sell.source) == "string" and sell.source ~= "" then
        first = "a vendor pays about " .. coin(sell.unit) .. " each (estimate, " .. sell.source .. ")"
    else
        first = Present.VENDOR_PRICE_UNKNOWN
    end
    local lines = { name .. ": " .. first }
    local buy = type(result.buy) == "table" and result.buy or {}
    if isCount(buy.unit) and (buy.basis == Prices.OBSERVED or buy.basis == Prices.ESTIMATED) then
        local text = "A merchant sells it for " .. (buy.basis == Prices.ESTIMATED and "about " or "") .. coin(buy.unit) .. " each"
        if isCount(buy.per) and buy.per > 1 then text = text .. ", " .. buy.per .. " at a time" end
        local source = type(buy.source) == "string" and buy.source ~= "" and buy.source or nil
        if buy.basis == Prices.ESTIMATED then
            text = text .. " (estimate" .. (source and (", " .. source) or "") .. ")"
        elseif source then
            text = text .. " (" .. source .. ")"
        end
        lines[#lines + 1] = text
    end
    return lines
end

-- What the list comes to: the observed figure and the estimate apart, and
-- the rows with no price counted, not priced.
function Present.SellTotal(list)
    local t = type(list.total) == "table" and list.total or {}
    local known = isCount(t.known) and t.known or 0
    local estimated = isCount(t.estimated) and t.estimated or 0
    local unknown = isCount(t.unknown) and t.unknown or 0
    local parts = {}
    if known > 0 then parts[#parts + 1] = coin(known) end
    if estimated > 0 then parts[#parts + 1] = "about " .. coin(estimated) .. " (estimate)" end
    if unknown > 0 then
        parts[#parts + 1] = plural(unknown, "price", "prices") .. " unknown—check vendor"
    end
    if #parts == 0 then return nil end
    return "Would sell for: " .. table.concat(parts, ", plus ")
end

-- One row of SellView.Kept, as a text.
function Present.KeptText(k, names)
    local name = type(k.name) == "string" and k.name ~= "" and k.name or Present.Name(k.key, names)
    return name .. ": " .. tostring(k.reason or "kept")
end

-- The whole list, top to bottom: what would be sold, its total, notes on
-- what could not be listed, then what is kept and why.
function Present.SellLines(list, kept, names)
    if type(list) ~= "table" or not list.ok then
        local why = type(list) == "table" and type(list.problem) == "string" and list.problem
            or ns.ItemSell.BAGS_UNREAD
        return { "Can't list what to sell: " .. why }
    end
    local lines = {}
    local rows = type(list.rows) == "table" and list.rows or {}
    if #rows == 0 then
        lines[#lines + 1] = Present.NOTHING_TO_SELL
    else
        lines[#lines + 1] = Present.SELL_HEADER
        for _, r in ipairs(rows) do lines[#lines + 1] = Present.SellRowText(r, names) end
        local total = Present.SellTotal(list)
        if total then lines[#lines + 1] = total end
    end
    if isCount(list.unread) and list.unread > 0 then
        lines[#lines + 1] = plural(list.unread, "bag slot", "bag slots") .. " could not be read"
    end
    if isCount(list.unsellable) and list.unsellable > 0 then
        lines[#lines + 1] = plural(list.unsellable, "item", "items") .. " to sell can't be sold to a merchant"
    end
    local keptRows = type(kept) == "table" and type(kept.rows) == "table" and kept.rows or {}
    if #keptRows > 0 then
        lines[#lines + 1] = Present.KEPT_HEADER
        for _, k in ipairs(keptRows) do lines[#lines + 1] = Present.KeptText(k, names) end
    end
    return lines
end

function Present.View(plan, opts)
    opts = type(opts) == "table" and opts or {}
    local view = { ok = false, rows = {}, crafts = {}, problems = {}, lines = {} }
    if type(plan) ~= "table" or not plan.ok or type(plan.rows) ~= "table" then
        local why = type(plan) == "table" and type(plan.problem) == "string" and plan.problem or "no plan was given"
        view.lines[1] = "Can't plan this: " .. why
        return view
    end
    view.ok = true
    for _, r in ipairs(plan.rows) do
        local row = Present.Row(r, opts.names)
        view.rows[#view.rows + 1] = row
        view.lines[#view.lines + 1] = row.note and (row.text .. "; " .. row.note) or row.text
    end
    for _, c in ipairs(type(plan.crafts) == "table" and plan.crafts or {}) do
        view.crafts[#view.crafts + 1] = "Make " .. tostring(c.times) .. " x " .. Present.Name(c.makes, opts.names)
    end
    -- One craft is the goal itself: the list is worth showing from two up.
    if #view.crafts > 1 then
        for _, text in ipairs(view.crafts) do view.lines[#view.lines + 1] = text end
    end
    view.cost = Present.Cost(plan)
    view.afford = Present.Afford(plan)
    view.ready = Present.Ready(plan)
    view.lines[#view.lines + 1] = view.cost
    if view.afford then view.lines[#view.lines + 1] = view.afford end
    view.lines[#view.lines + 1] = view.ready
    for _, p in ipairs(type(plan.problems) == "table" and plan.problems or {}) do
        view.problems[#view.problems + 1] = p
        view.lines[#view.lines + 1] = "Problem: " .. tostring(p)
    end
    return view
end
