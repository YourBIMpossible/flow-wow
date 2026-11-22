local _, ns = ...

-- Tests for ZFlow/Items/PriceObserve.lua over the fake client. Pure: the
-- price book is a table made here. Not tested in game.

local O = ns.PriceObserve
local P = ns.Prices
local tests = {}

local LEATHER = "|cffffffff|Hitem:2318:0:0:0:0:0:0:0|h[Light Leather]|h|r"
local BEAR = "item:15234:0:0:0:0:0:588:0"

local function shop(rows)
    local c = ns.make.fakeClient()
    c.setMerchant(rows)
    c.setMerchantOpen(true)
    return c
end

local function stock()
    return {
        { index = 1, item = LEATHER, price = 60, stack = 1, other = false },
        { index = 2, item = "item:2320", price = 50, stack = 5 },
        { index = 3, item = BEAR, price = 4000, stack = 1 },
    }
end

local function count(list)
    local n = 0
    for _ in pairs(list) do n = n + 1 end
    return n
end

tests["price observe: one merchant read gives one observed entry per item"] = function(t)
    local book = {}
    local report = O.FromClient(shop(stock()), book, 100)
    t.eq(report.ok, true, tostring(report.reason))
    t.eq(report.reason, nil)
    t.eq(report.skipped, {})
    t.eq(report.recorded, {
        { index = 1, key = 2318, value = 60 },
        { index = 2, key = 2320, value = 10 },
        { index = 3, key = "15234:588", value = 4000 },
    })
    t.eq(book, { vendor = {
        [2318] = { value = 60, basis = "observed", source = "merchant window", seenAt = 100, per = 1 },
        [2320] = { value = 10, basis = "observed", source = "merchant window", seenAt = 100, per = 5 },
        ["15234:588"] = { value = 4000, basis = "observed", source = "merchant window", seenAt = 100, per = 1 },
    } }, "one entry per item, of kind vendor, and nothing else")
    local got = P.Get(book, 2320, "vendor")
    t.eq(got.basis, "observed")
    t.eq(got.value, 10, "the price for one, not for the stack of five")
    t.eq(got.per, 5, "and the stack of five it is sold in is kept")
    t.eq(P.Cost(got, 6), 100, "six of them are two whole stacks")
    t.eq(got.seenAt, 100, "the date the caller stamped")
    t.eq(P.Get(book, 2320, "trainer").basis, "unknown", "no other kind is written")
    t.eq(P.Get(book, 2319, "vendor").basis, "unknown", "an item not on sale stays unknown")
end

tests["price observe: a repeat read on a later date replaces the older observed price"] = function(t)
    local book = {}
    local c = shop(stock())
    O.FromClient(c, book, 100)
    local rows = stock()
    rows[1].price = 75
    c.setMerchant(rows)
    local report = O.FromClient(c, book, 200)
    t.eq(report.ok, true, tostring(report.reason))
    t.eq(#report.recorded, 3)
    local got = P.Get(book, 2318, "vendor")
    t.eq(got.value, 75, "the later price")
    t.eq(got.seenAt, 200, "with the later date")
    t.eq(got.basis, "observed")
    t.eq(count(book.vendor), 3, "still one entry per item")
end

tests["price observe: a read on an earlier date does not replace a later one and says why"] = function(t)
    local book = {}
    local c = shop({ { index = 1, item = LEATHER, price = 60, stack = 1 } })
    O.FromClient(c, book, 200)
    c.setMerchant({ { index = 1, item = LEATHER, price = 10, stack = 1 } })
    local report = O.FromClient(c, book, 100)
    t.eq(report.ok, true)
    t.eq(report.recorded, {})
    t.eq(#report.skipped, 1)
    t.eq(report.skipped[1].reason, "the book has a newer observed price")
    t.eq(P.Get(book, 2318, "vendor").value, 60)
    t.eq(P.Get(book, 2318, "vendor").seenAt, 200)
end

tests["price observe: an estimate never replaces the observed price"] = function(t)
    local book = {}
    O.FromClient(shop(stock()), book, 100)
    local price, why = P.Record(book, 2318, "vendor", 1, { basis = "estimated", seenAt = 900 })
    t.eq(price, nil, "the estimate was taken")
    t.eq(why, "an estimate does not replace an observed price")
    local got = P.Get(book, 2318, "vendor")
    t.eq(got.value, 60)
    t.eq(got.basis, "observed")
    t.eq(got.seenAt, 100)
end

tests["price observe: an observed read replaces an estimate"] = function(t)
    local book = {}
    P.Record(book, 2318, "vendor", 1, { basis = "estimated", seenAt = 900 })
    local report = O.FromClient(shop(stock()), book, 100)
    t.eq(#report.recorded, 3)
    t.eq(P.Get(book, 2318, "vendor").basis, "observed")
    t.eq(P.Get(book, 2318, "vendor").value, 60)
end

tests["price observe: a row with no price records nothing and says why"] = function(t)
    local book = {}
    local report = O.FromClient(shop({
        { index = 1, item = LEATHER, stack = 1 },
        { index = 2, item = "item:2320", price = 0, stack = 1 },
        { index = 3, item = BEAR, price = 4000, stack = 1, other = true },
        { index = 4, price = 5, stack = 1 },
        { index = 5, item = "item:2321", price = 5 },
        { index = 6, item = "not an item", price = 5, stack = 1 },
        { index = 7, item = "item:2322", price = "5", stack = 1 },
    }), book, 100)
    t.eq(report.ok, true, "the window was read")
    t.eq(report.recorded, {})
    t.eq(report.reason, "nothing with a price in coin was read")
    t.eq(book, {}, "nothing was written, not even an empty kind")
    local why = {}
    for _, entry in ipairs(report.skipped) do why[entry.index] = entry.reason end
    t.eq(why, {
        "no price was read for this row",
        "the window shows no price in coin",
        "the price is not in coin",
        "no item was read for this row",
        "no stack size was read for this row",
        "no item was read for this row",
        "no price was read for this row",
    })
    t.eq(report.skipped[1].item, LEATHER, "the row left out is named")
    t.eq(P.Get(book, 2318, "vendor").basis, "unknown", "no price is unknown, never 0")
end

tests["price observe: a row left out does not stop the rows that have a price"] = function(t)
    local book = {}
    local report = O.FromClient(shop({
        { index = 1, item = LEATHER, stack = 1 },
        { index = 2, item = "item:2320", price = 50, stack = 5 },
    }), book, 100)
    t.eq(report.reason, nil)
    t.eq(report.recorded, { { index = 2, key = 2320, value = 10 } })
    t.eq(#report.skipped, 1)
    t.eq(book, { vendor = { [2320] = { value = 10, basis = "observed", source = "merchant window", seenAt = 100, per = 5 } } })
end

tests["price observe: a failing read records nothing and says why"] = function(t)
    local book = {}
    local closed = ns.make.fakeClient()
    closed.setMerchant(stock())
    local report = O.FromClient(closed, book, 100)
    t.eq(report.ok, false, "a closed window was read")
    t.eq(report.reason, "the merchant window could not be read")
    t.eq(report.recorded, {})
    t.eq(book, {})

    local unknown = ns.make.fakeClient()
    unknown.setMerchant(stock())
    unknown.setMerchantOpen(nil)
    t.eq(O.FromClient(unknown, book, 100).reason, "the merchant window could not be read")

    local unread = shop(nil)
    t.eq(O.FromClient(unread, book, 100).reason, "the merchant window could not be read")
    t.eq(O.Read(book, nil, 100).reason, "the merchant window could not be read")
    t.eq(O.Read(book, "rows", 100).ok, false)
    t.eq(book, {}, "a failing read wrote something")
end

tests["price observe: a failing read leaves what the book already has"] = function(t)
    local book = {}
    local c = shop(stock())
    O.FromClient(c, book, 100)
    c.setMerchantOpen(false)
    local report = O.FromClient(c, book, 200)
    t.eq(report.ok, false)
    t.eq(P.Get(book, 2318, "vendor").value, 60)
    t.eq(P.Get(book, 2318, "vendor").seenAt, 100)
end

tests["price observe: no book, no date or no client records nothing and says why"] = function(t)
    local book = {}
    local c = shop(stock())
    t.eq(O.FromClient(c, nil, 100).reason, "no price book")
    t.eq(O.FromClient(c, book, nil).reason, "no date for the reading")
    t.eq(O.FromClient(c, book, "today").reason, "no date for the reading")
    t.eq(O.FromClient(nil, book, 100).reason, "this client has no merchant read")
    t.eq(O.FromClient({}, book, 100).reason, "this client has no merchant read")
    t.eq(O.Read(nil, stock(), 100).reason, "no price book")
    t.eq(O.Read(book, stock(), nil).reason, "no date for the reading")
    t.eq(O.Read(book, stock(), nil).ok, false)
    t.eq(book, {}, "something was written")
end

tests["price observe: an item listed twice in one reading keeps one entry"] = function(t)
    local book = {}
    local report = O.FromClient(shop({
        { index = 1, item = LEATHER, price = 60, stack = 1 },
        { index = 2, item = "item:2318", price = 90, stack = 1 },
    }), book, 100)
    t.eq(#report.recorded, 1)
    t.eq(#report.skipped, 1)
    t.eq(report.skipped[1].index, 2)
    t.eq(P.Get(book, 2318, "vendor").value, 60)
    t.eq(count(book.vendor), 1)
end

tests["price observe: nothing asks the client for anything but the merchant read"] = function(t)
    local real = shop(stock())
    local asked = {}
    local watcher = setmetatable({}, { __index = function(_, name)
        asked[name] = (asked[name] or 0) + 1
        return real[name]
    end })
    local book = {}
    local report = O.FromClient(watcher, book, 100)
    t.eq(#report.recorded, 3, "the read did not go through the watcher")
    asked.merchantItems = nil
    t.eq(asked, {}, "a client function other than merchantItems was asked for")
    for name in pairs(real) do
        local lower = type(name) == "string" and name:lower() or ""
        t.ok(not lower:find("buy", 1, true) and not lower:find("sell", 1, true),
            "the fake client has a buy or sell function: " .. tostring(name))
    end
end

tests["price observe: the rows read are not changed"] = function(t)
    local rows = stock()
    O.Read({}, rows, 100)
    t.eq(rows, stock())
end

tests["price observe: the saved book is one table under what the account has learned"] = function(t)
    local saved, asked = {}, {}
    local store = { table = function(self, scope, path)
        asked[#asked + 1] = { self = self, scope = scope, path = path }
        return saved
    end }
    local book = O.Book(store)
    t.ok(book == saved, "the book is not the store's own table")
    t.eq(#asked, 1)
    t.ok(asked[1].self == store, "the store was not called as a method")
    t.eq(asked[1].scope, "account")
    t.eq(asked[1].path, "learned.prices")
    O.FromClient(shop(stock()), book, 100)
    t.eq(P.Get(saved, 2318, "vendor").basis, "observed", "the read did not land in the saved table")
    t.eq(O.Book(nil), nil)
    t.eq(O.Book({}), nil)
    t.eq(O.Book({ table = function() return nil end }), nil, "a store that gives no table gives no book")
end

return tests
