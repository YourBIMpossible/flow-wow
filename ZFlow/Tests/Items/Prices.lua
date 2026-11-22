local _, ns = ...

-- Tests for ZFlow/Items/Prices.lua. Pure: the price book is a table made here.

local P = ns.Prices
local tests = {}

tests["prices: no entry is unknown, never zero"] = function(t)
    local book = {}
    local p = P.Get(book, "tier:Mining:150", "trainer")
    t.eq(p.basis, "unknown", "nothing recorded: unknown")
    t.eq(p.value, nil, "and no number, not 0")
    t.eq(P.Get(nil, "x", "trainer").basis, "unknown", "no book: unknown")
    t.eq(P.Get(book, nil, "trainer").basis, "unknown", "no key: unknown")
    t.eq(P.Get(book, "x", nil).basis, "unknown", "no kind: unknown")
    t.eq(next(book), nil, "asking writes nothing into the book")
end

tests["prices: an observed price is read back with where and when"] = function(t)
    local book = {}
    local p, why = P.Record(book, "tier:Mining:150", "trainer", 500, { source = "trainer window", seenAt = 100 })
    t.eq(why, nil, "recorded")
    t.eq(p.basis, "observed", "observed is the default basis")
    t.eq(p.value, 500, "its value")
    local got = P.Get(book, "tier:Mining:150", "trainer")
    t.ok(got.value == 500 and got.basis == "observed" and got.source == "trainer window" and got.seenAt == 100,
        "value, basis, source and time come back")
    t.eq(P.Get(book, "tier:Mining:150", "vendor").basis, "unknown", "a price is kept per kind")
    t.eq(P.Get(book, "tier:Herbalism:150", "trainer").basis, "unknown", "and per key")
    -- What Get returns is a copy.
    got.value = 1
    t.eq(P.Get(book, "tier:Mining:150", "trainer").value, 500, "changing what Get returned does not change the book")
    -- A price of nothing is a price.
    P.Record(book, 2320, "vendor", 0, { seenAt = 5 })
    t.ok(P.Get(book, 2320, "vendor").value == 0 and P.Get(book, 2320, "vendor").basis == "observed", "free is observed, not unknown")
end

tests["prices: the basis is exactly observed, estimated or unknown"] = function(t)
    local book = {}
    t.eq(P.Record(book, "a", "trainer", 500, { basis = "estimated" }).basis, "estimated", "an estimate can be recorded")
    local p, why = P.Record(book, "b", "trainer", 500, { basis = "unknown" })
    t.eq(p, nil, "unknown can't be recorded")
    t.eq(why, "basis is not observed or estimated", "with the reason")
    t.eq(select(2, P.Record(book, "b", "trainer", 500, { basis = "guess" })), "basis is not observed or estimated", "nor any other word")
    t.eq(P.Get(book, "b", "trainer").basis, "unknown", "nothing was written")
    -- A book entry this file wouldn't have written reads as unknown.
    local odd = { trainer = {
        a = { value = 500, basis = "guess" },
        b = { value = -1, basis = "observed" },
        c = { value = "500", basis = "observed" },
        d = { basis = "observed" },
        e = 500,
        f = { value = 0 / 0, basis = "estimated" },
    } }
    for _, k in ipairs({ "a", "b", "c", "d", "e", "f" }) do
        local got = P.Get(odd, k, "trainer")
        t.ok(got.basis == "unknown" and got.value == nil, k .. ": a broken entry is unknown")
    end
    t.eq(P.Get({ trainer = "nonsense" }, "a", "trainer").basis, "unknown", "a broken kind is unknown")
end

tests["prices: what Record refuses"] = function(t)
    local book = {}
    local function why(...)
        local p, problem = P.Record(...)
        return p == nil and problem or "written"
    end
    t.eq(why(nil, "a", "trainer", 5), "no price book", "no book")
    t.eq(why(book, nil, "trainer", 5), "no key", "no key")
    t.eq(why(book, {}, "trainer", 5), "no key", "a table as a key")
    t.eq(why(book, "a", nil, 5), "no kind", "no kind")
    t.eq(why(book, "a", "trainer", nil), "the price is not a count", "no value")
    t.eq(why(book, "a", "trainer", -5), "the price is not a count", "a negative value")
    t.eq(why(book, "a", "trainer", "5"), "the price is not a count", "a value in text")
    t.eq(why(book, "a", "trainer", 0 / 0), "the price is not a count", "not a number")
    t.eq(why(book, "a", "trainer", math.huge), "the price is not a count", "endless")
    t.eq(next(book), nil, "none of them wrote anything")
    t.eq(why(book, "a", "trainer", 5), "written", "a good one is written")
end

tests["prices: an estimate never replaces an observed price"] = function(t)
    local book = {}
    P.Record(book, "a", "trainer", 500, { seenAt = 10 })
    local p, why = P.Record(book, "a", "trainer", 900, { basis = "estimated", seenAt = 99 })
    t.eq(p, nil, "the estimate is not written, however new")
    t.eq(why, "an estimate does not replace an observed price", "with the reason")
    t.ok(P.Get(book, "a", "trainer").value == 500 and P.Get(book, "a", "trainer").basis == "observed", "the observed price stands")
    -- The other way round: seeing the price replaces the estimate.
    P.Record(book, "b", "trainer", 900, { basis = "estimated", seenAt = 50 })
    P.Record(book, "b", "trainer", 450, { seenAt = 20 })
    t.ok(P.Get(book, "b", "trainer").value == 450 and P.Get(book, "b", "trainer").basis == "observed",
        "an observed price replaces an estimate, even an estimate made later")
    -- Estimates replace each other.
    P.Record(book, "c", "trainer", 900, { basis = "estimated" })
    P.Record(book, "c", "trainer", 700, { basis = "estimated" })
    t.eq(P.Get(book, "c", "trainer").value, 700, "a new estimate replaces the old one")
end

tests["prices: the newer observation wins"] = function(t)
    local book = {}
    P.Record(book, "a", "vendor", 500, { seenAt = 10 })
    P.Record(book, "a", "vendor", 550, { seenAt = 20 })
    t.eq(P.Get(book, "a", "vendor").value, 550, "seen later: replaces")
    local p, why = P.Record(book, "a", "vendor", 400, { seenAt = 15 })
    t.eq(p, nil, "seen earlier than what the book has: not written")
    t.eq(why, "the book has a newer observed price", "with the reason")
    t.eq(P.Get(book, "a", "vendor").value, 550, "the newer one stands")
    P.Record(book, "a", "vendor", 600, { seenAt = 20 })
    t.eq(P.Get(book, "a", "vendor").value, 600, "seen at the same time: the later call wins")
    P.Record(book, "a", "vendor", 650)
    t.eq(P.Get(book, "a", "vendor").value, 650, "no time given: the age check is skipped and it replaces what was there")
    t.eq(P.Get(book, "a", "vendor").seenAt, nil, "and no time is made up")
end

tests["prices: Forget removes one price"] = function(t)
    local book = {}
    P.Record(book, "a", "vendor", 500)
    P.Record(book, "b", "vendor", 700)
    t.eq(P.Forget(book, "a", "vendor"), true, "there was one")
    t.eq(P.Get(book, "a", "vendor").basis, "unknown", "it is unknown again")
    t.eq(P.Get(book, "b", "vendor").value, 700, "the other stays")
    t.eq(P.Forget(book, "a", "vendor"), false, "nothing to forget the second time")
    t.eq(P.Forget(nil, "a", "vendor"), false, "no book: nothing")
end

tests["prices: copper as text"] = function(t)
    t.eq(P.Coin(0), "0c", "nothing")
    t.eq(P.Coin(7), "7c", "copper")
    t.eq(P.Coin(100), "1s", "a silver, no '0c'")
    t.eq(P.Coin(1240), "12s 40c", "silver and copper")
    t.eq(P.Coin(10000), "1g", "a gold")
    t.eq(P.Coin(10203), "1g 2s 3c", "all three")
    t.eq(P.Coin(10003), "1g 3c", "no silver: left out")
    t.eq(P.Coin(1234567), "123g 45s 67c", "a large sum")
    t.eq(P.Coin(12.4), "12c", "a part of a copper is rounded")
    t.eq(P.Coin(-1), nil, "not a count: no text")
    t.eq(P.Coin(nil), nil, "nothing given: no text")
    t.eq(P.Coin("12"), nil, "text is not a count")
end

tests["prices: an estimate is always labelled, unknown reads as unknown"] = function(t)
    local book = {}
    P.Record(book, "seen", "trainer", 1240)
    P.Record(book, "guess", "trainer", 1240, { basis = "estimated" })
    t.eq(P.Text(P.Get(book, "seen", "trainer")), "12s 40c", "observed: the plain price")
    t.eq(P.Text(P.Get(book, "guess", "trainer")), "about 12s 40c (estimate)", "estimated: labelled twice over")
    t.eq(P.Text(P.Get(book, "none", "trainer")), "price unknown - check trainer", "unknown: the exact words")
    t.eq(P.UNKNOWN_TEXT, "price unknown - check trainer", "kept in one place")
    t.eq(P.Text(P.Get(book, "none", "trainer")), P.UNKNOWN_TEXT, "an unknown price reads as that one text")
    t.eq(P.Text(nil), P.UNKNOWN_TEXT, "and so does no price at all")
    t.eq(P.Text(nil), "price unknown - check trainer", "no price at all: unknown")
    t.eq(P.Text({ value = 500 }), "price unknown - check trainer", "a value with no basis is not shown as a price")
    t.eq(P.Text({ value = 500, basis = "guess" }), "price unknown - check trainer", "nor one with another basis")
    t.eq(P.Text({ basis = "observed" }), "price unknown - check trainer", "nor a basis with no value")
    t.eq(P.Text({ value = -5, basis = "observed" }), "price unknown - check trainer", "nor a value that isn't a count")
    local text = P.Text(P.Get(book, "guess", "trainer"))
    t.ok(text:find("estimate", 1, true) ~= nil and text ~= P.Text(P.Get(book, "seen", "trainer")),
        "an estimate never reads like an observed price")
end

tests["prices: an estimate never decides affordability"] = function(t)
    local book = {}
    P.Record(book, "seen", "trainer", 500)
    P.Record(book, "guess", "trainer", 500, { basis = "estimated" })
    local seen, guess, none = P.Get(book, "seen", "trainer"), P.Get(book, "guess", "trainer"), P.Get(book, "none", "trainer")
    t.eq(P.CanAfford(seen, 500), true, "observed and exactly enough: yes")
    t.eq(P.CanAfford(seen, 9000), true, "observed and more than enough: yes")
    t.eq(P.CanAfford(seen, 499), false, "observed and one copper short: no")
    t.eq(P.CanAfford(guess, 9000), "unknown", "an estimate with plenty of money: unknown, never true")
    t.eq(P.CanAfford(guess, 0), "unknown", "an estimate with no money: unknown, not false either")
    t.eq(P.CanAfford(none, 9000), "unknown", "an unknown price: unknown")
    t.eq(P.CanAfford(seen, nil), "unknown", "money that wasn't read: unknown")
    t.eq(P.CanAfford(seen, -1), "unknown", "money that isn't a count: unknown")
    t.eq(P.CanAfford(nil, 9000), "unknown", "no price: unknown")
    t.eq(P.CanAfford({ value = 1, basis = "guess" }, 9000), "unknown", "another basis: unknown")
    t.eq(P.CanAfford({ value = 0, basis = "observed" }, 0), true, "free, observed, with no money: yes")
    -- "unknown" is a word, so a caller that tests `if can then` would take it
    -- for yes: the three answers must be compared, and this pins what they are.
    t.ok(P.CanAfford(guess, 9000) ~= true, "the estimate's answer is not `true`")
end

tests["prices: what a money claim asks for"] = function(t)
    local book = {}
    P.Record(book, "seen", "trainer", 500)
    P.Record(book, "guess", "trainer", 450, { basis = "estimated" })
    local amount, estimate = P.Amount(P.Get(book, "seen", "trainer"))
    t.ok(amount == 500 and estimate == nil, "observed: the amount, no estimate")
    amount, estimate = P.Amount(P.Get(book, "guess", "trainer"))
    t.ok(amount == nil and estimate == 450, "estimated: no amount, the figure only as an estimate")
    amount, estimate = P.Amount(P.Get(book, "none", "trainer"))
    t.ok(amount == nil and estimate == nil, "unknown: neither")
    amount, estimate = P.Amount(nil)
    t.ok(amount == nil and estimate == nil, "no price: neither")
    -- Through the resolver: an estimated price holds no money and is not refused.
    local R = ns.Resources
    t.ok(type(R) == "table" and type(R.Resolve) == "function" and type(R.Fake) == "function",
        "the resolver is loaded: this part is not skipped")
    local a, e = P.Amount(P.Get(book, "guess", "trainer"))
    local g = R.Resolve(R.Fake({ money = 100 }), {
        { owner = "train:guess", kind = "money", amount = a, estimate = e },
        { owner = "train:seen", kind = "money", amount = (P.Amount(P.Get(book, "seen", "trainer"))) },
    })
    local by = {}
    for _, x in ipairs(g) do by[x.claim.owner] = x end
    t.eq(by["train:guess"].unknown, "price", "the estimated one stays 'price unknown'")
    t.eq(by["train:guess"].estimate, 450, "its estimate rides along")
    t.eq(by["train:seen"].short, 500, "the observed one is known to be short")
    t.eq(g:Held("money"), 0, "and nothing is held on the strength of an estimate")
end

return tests
