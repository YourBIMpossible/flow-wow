local _, ns = ...

-- PriceObserve: what a merchant window shows becomes observed prices.
--
-- The client reads the open merchant window (client.merchantItems()); this
-- turns that one reading into Prices.Record calls of kind "vendor", basis
-- observed, stamped with the date the caller gives. Prices.Get then answers
-- observed for each item read.
--
--   PriceObserve.Read(book, rows, seenAt)          -> report
--   PriceObserve.FromClient(client, book, seenAt)  -> report
--   PriceObserve.Book(store)                       -> the saved price book
--
--   report = { ok, reason, recorded, skipped }
--     ok        true when the window was read (even if nothing was recorded)
--     reason    why nothing was recorded, when nothing was
--     recorded  { { index =, key =, value = }, ... }   value: copper for one
--     skipped   { { index =, item =, reason = }, ... } one per row left out
--
-- The price recorded is for one of the item: what the window shows for the
-- stack, divided by the size of the stack; the size of the stack is kept
-- with it (the entry's `per`), since only whole stacks are sold. Unknown stays unknown: a row
-- with no item, no price, no stack size or a price that is not coin is left
-- out and the report says why. A price of 0 is left out too: the window
-- shows 0 coin for what is paid for in something else, and whether the
-- client says so is not yet seen in game.
--
-- Pure: nothing here reads the game, and nothing here or in the read it
-- uses buys, sells or clicks. Nothing calls this in game yet: what runs it
-- when the window opens is not part of this file.

local PriceObserve = ns.PriceObserve or {}
ns.PriceObserve = PriceObserve

PriceObserve.KIND = "vendor"
PriceObserve.SOURCE = "merchant window"

local NO_BOOK = "no price book"
local NO_DATE = "no date for the reading"
local NO_READ = "the merchant window could not be read"
local NO_CLIENT = "this client has no merchant read"
local NOTHING = "nothing with a price in coin was read"

local function isCount(n)
    return type(n) == "number" and n == n and n >= 0 and n < math.huge
end

local function refusal(reason)
    return { ok = false, reason = reason, recorded = {}, skipped = {} }
end

-- -> key, value for one row, or nil and why it is left out.
local function priced(row)
    if type(row) ~= "table" then return nil, "the row could not be read" end
    local key = ns.Items.Key(row.item)
    if key == nil then return nil, "no item was read for this row" end
    if row.other == true then return nil, "the price is not in coin" end
    if not isCount(row.price) then return nil, "no price was read for this row" end
    if row.price == 0 then return nil, "the window shows no price in coin" end
    if not isCount(row.stack) or row.stack < 1 then return nil, "no stack size was read for this row" end
    return key, row.price / row.stack, row.stack
end

function PriceObserve.Read(book, rows, seenAt)
    if type(book) ~= "table" then return refusal(NO_BOOK) end
    if type(seenAt) ~= "number" or seenAt ~= seenAt then return refusal(NO_DATE) end
    if type(rows) ~= "table" then return refusal(NO_READ) end
    local report = { ok = true, reason = nil, recorded = {}, skipped = {} }
    local seen = {}
    for index = 1, #rows do
        local row = rows[index]
        local key, value, per = priced(row)
        local why
        if key == nil then
            why = value
        elseif seen[key] then
            why = "the item is listed twice in one reading; its first price was kept"
        else
            local price, refused = ns.Prices.Record(book, key, PriceObserve.KIND, value,
                { basis = ns.Prices.OBSERVED, source = PriceObserve.SOURCE, seenAt = seenAt, per = per })
            if price then
                seen[key] = true
                report.recorded[#report.recorded + 1] = { index = index, key = key, value = value }
            else
                why = refused or "the price was not recorded"
            end
        end
        if why then
            report.skipped[#report.skipped + 1] = {
                index = index, item = type(row) == "table" and row.item or nil, reason = why,
            }
        end
    end
    if #report.recorded == 0 then report.reason = NOTHING end
    return report
end

-- Reads the client's open merchant window into the book. The one client
-- function asked is merchantItems(), and only once the book and the date
-- are there to take what it gives.
function PriceObserve.FromClient(client, book, seenAt)
    if type(client) ~= "table" or type(client.merchantItems) ~= "function" then return refusal(NO_CLIENT) end
    if type(book) ~= "table" then return refusal(NO_BOOK) end
    if type(seenAt) ~= "number" or seenAt ~= seenAt then return refusal(NO_DATE) end
    return PriceObserve.Read(book, client.merchantItems(), seenAt)
end

-- The saved price book: one for the account, under what it has learned.
-- nil when the store will not give a table there.
function PriceObserve.Book(store)
    if type(store) ~= "table" or type(store.table) ~= "function" then return nil end
    return store:table("account", "learned.prices")
end
