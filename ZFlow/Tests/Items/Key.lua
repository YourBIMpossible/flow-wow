local _, ns = ...

-- Tests for ZFlow/Items/Key.lua and Resources.Take. Pure.

local I, R = ns.Items, ns.Resources
local tests = {}

tests["items: a key from an ID, an item string or a link"] = function(t)
    t.eq(I.Key(2318), 2318, "an ID is its own key")
    t.eq(I.Key("2318"), 2318, "an ID in text")
    t.eq(I.Key("item:2318"), 2318, "a short item string")
    t.eq(I.Key("item:2318:0:0:0:0:0:0:0"), 2318, "a full item string with no suffix")
    t.eq(I.Key("|cffffffff|Hitem:2318:0:0:0:0:0:0:0|h[Light Leather]|h|r"), 2318, "a chat link")
    t.eq(I.Key("item:2318::::::"), 2318, "empty fields are no suffix")
    t.eq(I.Key("item:15234:0:0:0:0:0:588:0"), "15234:588", "a random suffix is part of the key")
    t.eq(I.Key("item:15234:0:0:0:0:0:-12:0"), "15234:-12", "a negative suffix too")
    t.eq(I.Key("item:15234:77:0:0:0:0:0:99"), 15234, "an enchant and the unique number are not")
    t.eq(I.Key("15234:588"), "15234:588", "a key is its own key")
    t.eq(I.Key("15234:0"), 15234, "a suffix of 0 is no suffix")
    t.eq(I.Key(I.Key("item:15234:0:0:0:0:0:588:0")), "15234:588", "taking the key twice changes nothing")
end

tests["items: what isn't an item has no key"] = function(t)
    t.eq(I.Key(nil), nil, "nothing")
    t.eq(I.Key(""), nil, "an empty string")
    t.eq(I.Key("Light Leather"), nil, "a name: Z-Flow doesn't guess")
    t.eq(I.Key(0), nil, "0 is not an item")
    t.eq(I.Key(-5), nil, "a negative number")
    t.eq(I.Key(12.5), nil, "a fraction")
    t.eq(I.Key(0 / 0), nil, "not a number")
    t.eq(I.Key({}), nil, "a table")
    t.eq(I.Key("spell:2318"), nil, "another kind of link")
    t.eq(I.Key("item:"), nil, "an item string with no ID")
    t.eq(I.Key("item:0:0:0"), nil, "an ID of 0")
end

tests["items: the ID of a key, and the same item"] = function(t)
    t.eq(I.Id(2318), 2318, "a plain key")
    t.eq(I.Id("15234:588"), 15234, "a key with a suffix")
    t.eq(I.Id("|cffffffff|Hitem:2318:0:0:0:0:0:0:0|h[Light Leather]|h|r"), 2318, "a link")
    t.eq(I.Id("nonsense"), nil, "not an item")
    t.eq(I.Same(2318, "item:2318:0:0:0:0:0:0:0"), true, "an ID and its item string")
    t.eq(I.Same("item:15234:0:0:0:0:0:588:0", "item:15234:0:0:0:0:0:589:0"), false, "two suffixes are two items")
    t.eq(I.Same(15234, "item:15234:0:0:0:0:0:588:0"), false, "the plain item and the suffixed one differ")
    t.eq(I.Same(nil, nil), false, "nothing is not the same as nothing")
    t.eq(I.Same("x", "x"), false, "two things that aren't items")
end

tests["resources: Take builds a snapshot from the functions it is given"] = function(t)
    local calls = { money = 0, bags = 0, items = 0, bank = 0, now = 0 }
    local read = {
        money = function() calls.money = calls.money + 1; return 1234 end,
        bags = function() calls.bags = calls.bags + 1
            return { { free = 4, total = 16, family = 0 }, { free = 10, total = 12, family = 32 }, { free = 6, total = 6 } } end,
        items = function() calls.items = calls.items + 1; return { [2318] = 12 } end,
        bank = function() calls.bank = calls.bank + 1; return { [2318] = 20 }, 900 end,
        now = function() calls.now = calls.now + 1; return 1000 end,
    }
    local shot = R.Take(read)
    t.eq(shot.money, 1234, "money")
    t.eq(shot.slots[0].free, 4, "general room")
    t.eq(shot.slots[32].free, 10, "a special bag under its family")
    t.eq(shot.slots.unknown.free, 6, "a bag with no family: listed as unknown")
    t.eq(shot.bags[2318], 12, "bag counts")
    t.eq(shot.bank[2318], 20, "bank counts")
    t.eq(shot.bankKnown, true, "the bank was seen")
    t.eq(shot.bankSeenAt, 900, "and when")
    t.eq(shot.takenAt, 1000, "the time it was taken")
    t.ok(calls.money == 1 and calls.bags == 1 and calls.items == 1 and calls.bank == 1 and calls.now == 1,
        "each function is called once")
    -- It resolves like a made-up one.
    local g = R.Resolve(shot, { { owner = "craft", kind = "item", key = 2318, amount = 30, bank = true } })
    t.ok(g[1].got == 30 and g[1].from.bags == 12 and g[1].from.bank == 18, "12 from the bags, 18 from the bank")
end

tests["resources: what Take can't read stays unknown"] = function(t)
    local blank = R.Take(nil)
    t.ok(blank.money == nil and blank.slots == nil and blank.bags == nil and blank.bank == nil, "no functions: all unknown")
    t.eq(blank.bankKnown, false, "the bank has not been seen")
    local broken = R.Take({
        money = function() error("no money API") end,
        bags = function() return "nonsense" end,
        items = function() return nil end,
        bank = function() return nil, 500 end,
        now = "not a function",
    })
    t.eq(broken.money, nil, "a function that errors: unknown, not 0")
    t.eq(broken.slots, nil, "an answer that isn't a list of bags: unknown")
    t.eq(broken.bags, nil, "no answer: unknown")
    t.eq(broken.bankKnown, false, "the bank answered nil: never seen")
    t.eq(broken.takenAt, 0, "no clock: no time made up beyond 0")
    t.eq(R.Take({ money = function() return -5 end }).money, nil, "money that isn't a count: unknown")
    local g = R.Resolve(broken, { { owner = "x", kind = "money", amount = 1 } })
    t.eq(g[1].unknown, "money", "and a claim against it is unknown, not refused")
    -- The snapshot is a copy of what was read.
    local counts = { [2318] = 5 }
    local shot = R.Take({ items = function() return counts end })
    counts[2318] = 0
    t.eq(shot.bags[2318], 5, "changing the table that was read does not change the snapshot")
end

return tests
