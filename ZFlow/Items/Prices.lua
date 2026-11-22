local _, ns = ...

-- Prices: what something costs, and how Z-Flow knows.
--
-- Every price has a basis, and it is exactly one of three:
--   observed   the game showed this price (a trainer's line, a merchant's
--              window, an auction) and Z-Flow wrote it down
--   estimated  a figure worked out or assumed; always labelled as such, and
--              never enough to say "you can afford it"
--   unknown    Z-Flow has no figure. It says so; it never shows 0.
--
-- This is the pure core. The price book is a plain table passed in (the
-- caller keeps it in saved data); nothing here reads the game or the clock.
--
--   price = Prices.Get(book, key, kind)
--   entry, why = Prices.Record(book, key, kind, value, info)
--   text  = Prices.Text(price)
--   can   = Prices.CanAfford(price, money)      true, false or "unknown"
--   n     = Prices.Amount(price)                the copper to claim, or nil
--
--   key   what is priced: an item key, "tier:Mining:150", a spell name
--   kind  where the price applies: "trainer", "vendor", "auction", ...
--   book  { [kind] = { [key] = { value, basis, source, seenAt } } }
--   price { value = copper or nil, basis, source, seenAt }; a fresh table each
--         time, so a caller can't change the book through it.

local Prices = {}
ns.Prices = Prices

Prices.OBSERVED = "observed"
Prices.ESTIMATED = "estimated"
Prices.UNKNOWN = "unknown"
Prices.UNKNOWN_TEXT = "price unknown - check trainer"

-- A count: a number that is not negative, not NaN and not endless.
local function isCount(n)
    return type(n) == "number" and n == n and n >= 0 and n < math.huge
end

local function isName(k)
    return type(k) == "string" or type(k) == "number"
end

-- A stack size: a whole number of one or more.
local function isPer(n)
    return isCount(n) and n >= 1 and n == math.floor(n)
end

local function unknown()
    return { value = nil, basis = Prices.UNKNOWN, source = nil, seenAt = nil }
end

-- The stored entry, if it is one this file would have written: a count with
-- a basis of observed or estimated. Anything else is treated as no entry.
local function stored(book, key, kind)
    if type(book) ~= "table" or not isName(key) or not isName(kind) then return nil end
    local byKind = book[kind]
    local e = type(byKind) == "table" and byKind[key] or nil
    if type(e) ~= "table" or not isCount(e.value) then return nil end
    if e.basis ~= Prices.OBSERVED and e.basis ~= Prices.ESTIMATED then return nil end
    return e
end

-- The price of `key` for `kind`. Always a table; unknown when there is none.
function Prices.Get(book, key, kind)
    local e = stored(book, key, kind)
    if not e then return unknown() end
    return {
        value = e.value, basis = e.basis, source = e.source, seenAt = e.seenAt,
        per = isPer(e.per) and e.per or nil,
    }
end

-- Writes a price into the book.
--   info = { basis = "observed" (default) or "estimated",
--            source = "trainer window", seenAt = time,
--            per = how many one purchase gives (a merchant's stack) }
-- The value is always the price of one; `per` says it is only sold `per`
-- at a time, so what is paid is counted in whole stacks (Prices.Cost).
-- Left out when not given or not a whole number of one or more.
-- -> the price as Get would give it, or nil and why it was not written.
-- Rules:
--   - the value must be a count; "unknown" can't be recorded (leave it out)
--   - an estimate never replaces an observed price
--   - an observed price replaces an estimate, and an older observed price;
--     one seen earlier than what the book has is not written
--   - an estimate replaces an estimate
function Prices.Record(book, key, kind, value, info)
    if type(book) ~= "table" then return nil, "no price book" end
    if not isName(key) then return nil, "no key" end
    if not isName(kind) then return nil, "no kind" end
    if not isCount(value) then return nil, "the price is not a count" end
    info = type(info) == "table" and info or {}
    local basis = info.basis == nil and Prices.OBSERVED or info.basis
    if basis ~= Prices.OBSERVED and basis ~= Prices.ESTIMATED then return nil, "basis is not observed or estimated" end
    local seenAt = type(info.seenAt) == "number" and info.seenAt or nil
    local old = stored(book, key, kind)
    if old then
        if old.basis == Prices.OBSERVED and basis == Prices.ESTIMATED then
            return nil, "an estimate does not replace an observed price"
        end
        if old.basis == Prices.OBSERVED and old.seenAt and seenAt and seenAt < old.seenAt then
            return nil, "the book has a newer observed price"
        end
    end
    if type(book[kind]) ~= "table" then book[kind] = {} end
    book[kind][key] = {
        value = value, basis = basis, source = info.source, seenAt = seenAt,
        per = isPer(info.per) and info.per or nil,
    }
    return Prices.Get(book, key, kind)
end

-- Removes a price (the game showed that the thing is no longer sold there).
-- -> true when there was one.
function Prices.Forget(book, key, kind)
    if not stored(book, key, kind) then return false end
    book[kind][key] = nil
    return true
end

-- Copper as text: "1g 2s 3c", leaving out the parts that are zero ("5s",
-- "1g 3c"); "0c" for nothing, and "under 1c" for anything more than
-- nothing that is less than one copper (the price of one out of a stack):
-- never "0c" for a price that is not zero. nil when `copper` is not a count.
-- This is the one money text of the Items surfaces (A5): the price texts
-- here, the sell list, the plan and the price lookup all call it, so a
-- change to how money reads is made once. Each part is written as plain
-- digits, however large the sum: never "2e+14g".
function Prices.Coin(copper)
    if not isCount(copper) then return nil end
    if copper > 0 and copper < 1 then return "under 1c" end
    copper = math.floor(copper + 0.5)
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = string.format("%.0f", g) .. "g" end
    if s > 0 then parts[#parts + 1] = string.format("%.0f", s) .. "s" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = string.format("%.0f", c) .. "c" end
    return table.concat(parts, " ")
end

-- The price for the player to read.
--   observed   "12s 40c"
--   estimated  "about 12s 40c (estimate)": an estimate is always labelled
--   unknown    "price unknown - check trainer"
-- Anything that isn't a well-formed price reads as unknown.
function Prices.Text(price)
    if type(price) ~= "table" or not isCount(price.value) then return Prices.UNKNOWN_TEXT end
    if price.basis == Prices.OBSERVED then return Prices.Coin(price.value) end
    if price.basis == Prices.ESTIMATED then return "about " .. Prices.Coin(price.value) .. " (estimate)" end
    return Prices.UNKNOWN_TEXT
end

-- What `count` of the item costs at `price`, in copper. Where the price
-- has a stack size (`per`), only whole stacks can be bought: a stack of 5
-- for 1c costs 1c with 1 needed and 2c with 6 needed. nil when the price
-- has no value or `count` is not a count; the basis is the caller's to read.
function Prices.Cost(price, count)
    if type(price) ~= "table" or not isCount(price.value) or not isCount(count) then return nil end
    if not isPer(price.per) or price.per == 1 then return price.value * count end
    local stack = math.floor(price.value * price.per + 0.5)
    return math.ceil(count / price.per) * stack
end

-- Can the player pay it with `money` copper?
--   true / false  only for an observed price and money that was read
--   "unknown"     for an estimate (never true: an estimate does not decide
--                 this), for an unknown price, and when money wasn't read
function Prices.CanAfford(price, money)
    if type(price) ~= "table" or price.basis ~= Prices.OBSERVED or not isCount(price.value) then return Prices.UNKNOWN end
    if not isCount(money) then return Prices.UNKNOWN end
    return money >= price.value
end

-- For a money claim (Resources): the amount to ask for, and the estimate to
-- carry for the text.
--   observed   -> value, nil
--   estimated  -> nil, value      no amount: the claim stays "price unknown"
--   unknown    -> nil, nil
function Prices.Amount(price)
    if type(price) ~= "table" or not isCount(price.value) then return nil, nil end
    if price.basis == Prices.OBSERVED then return price.value, nil end
    if price.basis == Prices.ESTIMATED then return nil, price.value end
    return nil, nil
end
