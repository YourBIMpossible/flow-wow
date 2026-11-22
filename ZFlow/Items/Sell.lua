local _, ns = ...

-- ItemSell: the list of what would be sold to a merchant, from a bag read.
--
--   list = ItemSell.List(bag, context)
--
-- It only lists. Nothing here sells, opens a merchant, moves or destroys
-- anything, draws a frame or prints, and nothing reads the game: the bag,
-- the rules' facts and the price book are all passed in. Whether a list is
-- ever acted on is decided elsewhere.
--
-- bag: a list of items as Disposition takes them
--   { key, name, count, quality, sellPrice, classID, bound }
-- one entry per bag slot or per item; entries with the same key are counted
-- together before anything is decided, so a rule that keeps "8 of them"
-- sees all of them. nil (or not a table) means the bags were not read.
--
-- context: what Disposition.Decide takes (grants, choices, questItems,
-- tools, classKeep, level, rules, onError), and
--   book   the price book for Prices; a merchant's paying price for one is
--          recorded under the kind ItemSell.KIND
--
-- list = {
--   ok        false with `problem` when the bags were not read; then there
--             are no rows and every figure below is nil, never 0
--   rows      one per item that would be sold, in the order first met:
--     { key, name (as read; nil when it was not), count (nil when not known),
--       unit       the price of one in copper, or nil
--       basis      "observed", "estimated" or "unknown" (as in Prices)
--       source     where the price is from; nil when unknown
--       priceText  "12s 40c", "about 12s (estimate, <source>)" or
--                  "price unknown"; never a 0 for a price nobody saw
--       total      count x unit; nil when either is not known
--       reason, rule   from the decision that sells it }
--   total     { known     = copper on observed prices
--               estimated = copper on estimates (never added to known)
--               unknown   = how many rows have no total }
--   kept      what is not listed because it is kept for something better:
--     { auction    = { rows = items, count = how many in all },
--       disenchant = { rows = items, count = how many in all } }
--             count is nil when it is not known for one of them
--   unsellable  items a rule would sell but the game (or a merchant seen
--               to pay nothing) says can't be sold: not listed
--   unread      bag entries that are not a readable item: not listed
-- }
--
-- The price of one, in this order:
--   the item's own sellPrice (the game states it)         observed
--   an observed price in the book                         observed
--   an estimate in the book that names its source         estimated
--   anything else                                         unknown
--
-- The player's choices come first, whatever the rules in use say: an item
-- in choices.never or choices.keep is never listed and not counted as kept
-- for the auction house or for disenchanting.

local Sell = {}
ns.ItemSell = Sell

Sell.KIND = "sell"     -- the price kind for what a merchant pays for one
Sell.BAGS_UNREAD = "the bags have not been read yet"
Sell.PRICE_UNKNOWN = "price unknown"
Sell.ITEM_SOURCE = "the item's own sell price"

local function isCount(n)
    return type(n) == "number" and n == n and n >= 0 and n < math.huge
end

-- Did the player put this item on the list `which` ("never" or "keep")?
local function chosen(context, which, key)
    local choices = context.choices
    local set = type(choices) == "table" and choices[which] or nil
    return type(set) == "table" and set[key] and true or false
end

-- The bag as one item per key, in the order first met. Each is a copy: the
-- bag's own entries are not changed. A count is the sum over the slots, or
-- nil when one of them had none. -> items, how many entries were unreadable
local function gather(bag)
    local items, byKey, unread = {}, {}, 0
    for idx = 1, #bag do
        local entry = bag[idx]
        if type(entry) ~= "table" or entry.key == nil then
            unread = unread + 1
        else
            local held = byKey[entry.key]
            if not held then
                local item = {}
                for k, v in pairs(entry) do item[k] = v end
                if not isCount(item.count) then item.count = nil end
                held = { item = item, counted = item.count ~= nil }
                byKey[entry.key] = held
                items[#items + 1] = item
            else
                local item = held.item
                if held.counted and isCount(entry.count) then
                    item.count = item.count + entry.count
                else
                    held.counted = false
                    item.count = nil
                end
                -- What the first slot did not give, a later one may.
                for k, v in pairs(entry) do
                    if k ~= "count" and item[k] == nil then item[k] = v end
                end
            end
        end
    end
    return items, unread
end

-- The same gathering, for the sell list's kept part (SellView.Kept):
-- -> items (one per key, copies), how many entries were unreadable.
Sell.Gather = gather

-- The price of one. nil when it can't be sold to a merchant at all.
local function priceOf(item, book)
    local Prices = ns.Prices
    if isCount(item.sellPrice) then
        if item.sellPrice == 0 then return nil end
        return { unit = item.sellPrice, basis = Prices.OBSERVED, source = Sell.ITEM_SOURCE }
    end
    local p = Prices.Get(book, item.key, Sell.KIND)
    if isCount(p.value) then
        if p.basis == Prices.OBSERVED then
            if p.value == 0 then return nil end
            return { unit = p.value, basis = Prices.OBSERVED, source = p.source }
        end
        if p.basis == Prices.ESTIMATED and p.value > 0 and type(p.source) == "string" and p.source ~= "" then
            return { unit = p.value, basis = Prices.ESTIMATED, source = p.source }
        end
    end
    return { unit = nil, basis = Prices.UNKNOWN, source = nil }
end

local function priceText(price)
    local Prices = ns.Prices
    -- A unit the money text can't word (not a count) reads as unknown: it
    -- never raises and never shows a figure nobody has.
    local coin = Prices.Coin(price.unit)
    if coin == nil then return Sell.PRICE_UNKNOWN end
    if price.basis == Prices.OBSERVED then return coin end
    if price.basis == Prices.ESTIMATED and type(price.source) == "string" then
        return "about " .. coin .. " (estimate, " .. price.source .. ")"
    end
    return Sell.PRICE_UNKNOWN
end

-- The same text, for tests and other Items surfaces: price = { unit, basis, source }.
Sell.PriceText = priceText

-- The part of a decision (or of its rest) that sells.
local function sellPart(decision)
    local d = decision
    while type(d) == "table" do
        if d.action == "sell" then return d end
        d = d.rest
    end
    return nil
end

local function unread()
    return {
        ok = false, problem = Sell.BAGS_UNREAD, rows = {},
        total = { known = nil, estimated = nil, unknown = nil },
        kept = { auction = { rows = nil, count = nil }, disenchant = { rows = nil, count = nil } },
        unsellable = nil, unread = nil,
    }
end

function Sell.List(bag, context)
    if type(bag) ~= "table" then return unread() end
    context = type(context) == "table" and context or {}
    local D, Prices = ns.Disposition, ns.Prices
    local items, unreadable = gather(bag)

    local rows = {}
    local total = { known = 0, estimated = 0, unknown = 0 }
    local kept = { auction = { rows = 0, count = 0 }, disenchant = { rows = 0, count = 0 } }
    local unsellable = 0

    for idx = 1, #items do
        local item = items[idx]
        if not chosen(context, "never", item.key) and not chosen(context, "keep", item.key) then
            local decision = D.Decide(item, context)

            for action, footer in pairs(kept) do
                local n = D.CountOf(decision, action)
                if n == nil then
                    footer.rows = footer.rows + 1
                    footer.count = nil
                elseif n > 0 then
                    footer.rows = footer.rows + 1
                    if footer.count ~= nil then footer.count = footer.count + n end
                end
            end

            local count = D.CountOf(decision, "sell")
            if count == nil or count > 0 then
                local price = priceOf(item, context.book)
                if not price then
                    unsellable = unsellable + 1
                else
                    local part = sellPart(decision)
                    local sum = nil
                    if count ~= nil and price.unit ~= nil then sum = count * price.unit end
                    rows[#rows + 1] = {
                        key = item.key,
                        name = type(item.name) == "string" and item.name ~= "" and item.name or nil,
                        count = count,
                        unit = price.unit, basis = price.basis, source = price.source,
                        priceText = priceText(price),
                        total = sum,
                        reason = part and part.reason or nil,
                        rule = part and part.rule or nil,
                    }
                    if sum == nil then
                        total.unknown = total.unknown + 1
                    elseif price.basis == Prices.OBSERVED then
                        total.known = total.known + sum
                    else
                        total.estimated = total.estimated + sum
                    end
                end
            end
        end
    end

    return {
        ok = true, problem = nil, rows = rows, total = total, kept = kept,
        unsellable = unsellable, unread = unreadable,
    }
end
