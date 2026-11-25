local _, ns = ...

-- Parity rows E-22 + E-23, the data half (lead section 755): the rows of
-- the Flow Banker's "In your bank" view away from a bank and its "To sell"
-- view with keep or sell, as Flow's Modules/Items/Banker.lua: B.BankRows
-- (:647-656), the "bank" header (:707-715), B.SellRows (:255-274),
-- B.SellLines' note (:359-387) and B.NextSellChoice (:1105-1108). Pure;
-- made-up items. Not tested in game. Fails before: no file.
local tests = {}

local function BR() return ns.BankerRows end

tests["banker rows: in your bank, by name, with the header"] = function(t)
    t.eq(type(BR()), "table", "loaded")
    if type(BR()) ~= "table" then return end
    local items = { { key = 2, name = "Linen Cloth", count = 20 }, { key = 1, name = "Copper Ore", count = 5 },
                    { key = 3, count = 1 } }
    local rows = BR().BankRows(items)
    t.eq(#rows, 3)
    t.eq(rows[1].name, "Copper Ore", "by name")
    t.eq(rows[2].name, "Linen Cloth")
    t.eq(rows[3].name, "item 3", "a name not read")
    t.eq(rows[1].count, 5)
    t.eq(BR().BankRows(nil), nil, "not seen")
    t.eq(BR().BankHeader(nil, nil, 100), BR().NOT_SEEN)
    local h = BR().BankHeader(rows, 0, 2 * 3600)
    t.ok(type(h) == "string" and h:find("3 thing(s) in your bank", 1, true) ~= nil, tostring(h))
    t.ok(h:find(ns.PriceChart.Span(2 * 3600), 1, true) ~= nil, "how long ago")
    t.eq(BR().BankHeader(rows, nil, nil), BR().BANK_SOME:format(3, BR().LAST_VISIT))
end

local function sell(reason) return { action = "sell", count = 1, reason = reason, rule = "junk" } end

tests["banker rows: to sell, then kept by your own choice, then what is in the bank"] = function(t)
    if type(BR()) ~= "table" then return t.ok(false, "not loaded") end
    local bags = {
        { key = 10, name = "Broken Fang", count = 3, quality = 0, decision = sell("junk") },
        { key = 11, name = "Wolf Pelt", count = 2, decision = { action = "keep", rule = "neverSell",
                                                                reason = "on your never-sell list" } },
        { key = 12, name = "Hearthstone", count = 1, decision = { action = "keep", rule = "unsellable" } },
        { key = 13, name = "Linen Cloth", count = 4, decision = { action = "keep", rule = "yourChoice" } },
    }
    local bank = { { key = 20, name = "Old Boot", count = 1, decision = sell("junk") },
                   { key = 21, name = "Copper Ore", count = 5, decision = { action = "keep", rule = "neverSell" } } }
    local rows = BR().SellRows(bags, bank)
    t.eq(#rows, 4, "the sold one, two kept by choice, the bank's sold one")
    t.eq(rows[1].name, "Broken Fang")
    t.eq(rows[1].kept, nil)
    t.eq(rows[1].reason, "junk")
    t.eq(rows[1].next, "keep", "a click keeps it")
    t.eq(rows[2].kept, true)
    t.eq(rows[2].name, "Wolf Pelt")
    t.eq(rows[2].reason, BR().KEPT.neverSell)
    t.eq(rows[2].next, "sell", "a click sells it after all")
    t.eq(rows[3].reason, BR().KEPT.yourChoice)
    t.eq(rows[4].name, "Old Boot")
    t.eq(rows[4].bank, true)
    t.eq(BR().NextChoice(true), "sell")
    t.eq(BR().NextChoice(false), "keep")
    t.eq(BR().NextChoice(true, true), nil, "reset: the rules' own")
end

tests["banker rows: the to-sell note, as Flow's"] = function(t)
    if type(BR()) ~= "table" then return t.ok(false, "not loaded") end
    t.eq(BR().SellNote({}), BR().NOTHING)
    t.eq(BR().SellNote({ { kept = true } }), "Nothing to sell. Below: 1 thing(s) kept because you chose to; a click sells one instead.",
        "our own words (section 757)")
    local rows = { { name = "a" }, { name = "b" }, { kept = true }, { bank = true } }
    t.eq(BR().SellNote(rows, false), BR().BAGS:format(2) .. BR().BANK_AWAY:format(1))
    t.eq(BR().SellNote(rows, true), BR().BAGS:format(2) .. BR().BANK_AT:format(1))
    t.eq(BR().SellNote({ { name = "a" } }), BR().BAGS:format(1))
end

return tests
