local _, ns = ...

-- Tests for ZFlow/Items/Bank.lua and the bank-list words in
-- ZFlow/Items/Present.lua (L6-D, S1 / A4). Pure: stacks, item facts, claims
-- and choices are made up. Nothing is deposited, withdrawn or moved.
-- The banking rule is ported from Flow's Modules/Items/Banker.lua:42-93.

local B, Present = ns.Bank, ns.ItemPresent
local tests = {}

local INFO = {
    [2589] = { name = "Linen Cloth", quality = 1, sellPrice = 13, classID = 7 },     -- trade goods
    [2318] = { name = "Light Leather", quality = 1, sellPrice = 15, classID = 7 },
    [6948] = { name = "Hearthstone", quality = 1, sellPrice = 0, classID = 15 },
    [5056] = { name = "Quest Thing", quality = 1, sellPrice = 0, classID = 12 },
    [858] = { name = "Lesser Healing Potion", quality = 1, sellPrice = 20, classID = 0 },  -- consumable
    [97] = { name = "Broken Fang", quality = 0, sellPrice = 4 },
}

local function info(item)
    local id = ns.Items.Id(item)
    local i = id and INFO[id]
    if not i then return nil end
    local out = {}
    for k, v in pairs(i) do out[k] = v end
    return out
end

local function find(rows, key)
    for _, r in ipairs(rows or {}) do
        if r.key == key then return r end
    end
    return nil
end

local function has(lines, text)
    for _, l in ipairs(lines or {}) do
        if l == text then return true end
    end
    return false
end

local function pick(stacks, context)
    return B.Pick(B.Entries(stacks, info), context or {})
end

-- ------------------------------------------------------------------ Banks

tests["bank: only what is kept can be banked"] = function(t)
    t.eq((B.Banks({ action = "sell", classID = 7 })), false, "something to sell stays out of the bank list")
    t.eq((B.Banks(nil)), false, "not a row")
end

tests["bank: your own choice comes first"] = function(t)
    local carry, why = B.Banks({ key = 2589, action = "keep", classID = 7 }, nil, { [2589] = "carry" })
    t.eq(carry, false)
    t.eq(why, "you chose to carry it")
    local bank, why2 = B.Banks({ key = 5056, action = "keep", classID = 12 }, nil, { [5056] = "bank" })
    t.eq(bank, true)
    t.eq(why2, "you chose to bank it")
end

tests["bank: what a step holds stays with you"] = function(t)
    local yes, why = B.Banks({ key = 2589, action = "keep", classID = 7 }, { [2589] = true })
    t.eq(yes, false)
    t.eq(why, "a step on your route uses it")
end

tests["bank: quest things, consumables, gear, bags, keys and recipes stay"] = function(t)
    for _, classID in ipairs({ 12, 0, 2, 4, 1, 13, 9 }) do
        t.eq((B.Banks({ key = 1, action = "keep", classID = classID })), false, "class " .. classID .. " stays")
    end
    local _, why = B.Banks({ key = 1, action = "keep", classID = 7, reason = "for your quest: Wool" })
    t.eq(why, "your quest needs it")
end

tests["bank: trade goods and what is kept for later go in"] = function(t)
    local yes, why = B.Banks({ key = 2589, action = "keep", classID = 7 })
    t.eq(yes, true)
    t.eq(why, "kept for later")
    t.eq((B.Banks({ key = 1, action = "keep", rule = "professionMaterial", classID = 5 })), true, "a profession material")
    t.eq((B.Banks({ key = 1, action = "keep", rule = "neverSell" })), true, "on your never-sell list")
    t.eq((B.Banks({ key = 1, action = "keep" })), false, "kind not known: you carry it")
end

tests["bank: a quest that continues on another continent, or a leftover, goes in"] = function(t)
    local yes, why = B.Banks({ key = 5056, action = "keep", classID = 12 }, nil, nil, { [5056] = "Gathering the Cure" })
    t.eq(yes, true)
    t.eq(why, "its quest (Gathering the Cure) continues on another continent")
    t.eq((B.Banks({ key = 1, action = "keep", rule = "leftover", classID = 12 })), true)
end

-- ------------------------------------------------------------------ Pick

tests["bank pick: bags not read give nothing and say so"] = function(t)
    local p = B.Pick(nil, {})
    t.eq(p.ok, false)
    t.eq(#p.rows, 0)
    t.eq(B.Entries(nil, info), nil, "no stacks: no bag")
end

tests["bank pick: trade goods go in; the hearthstone, potions, quest items and junk stay"] = function(t)
    local p = pick({ { item = 2589, count = 20 }, { item = 6948, count = 1 }, { item = 858, count = 5 },
                     { item = 5056, count = 1 }, { item = 97, count = 3 } })
    t.eq(p.ok, true)
    local linen = find(p.rows, 2589)
    t.ok(linen ~= nil, "Linen Cloth to the bank")
    t.eq(linen.count, 20)
    t.eq(linen.reason, "kept for later")
    for _, key in ipairs({ 6948, 858, 5056, 97 }) do
        t.eq(find(p.rows, key), nil, "item " .. key .. " stays")
    end
end

tests["bank pick: stacks of one item are one row, biggest first"] = function(t)
    local p = pick({ { item = 2318, count = 4 }, { item = 2589, count = 10 }, { item = 2589, count = 10 } })
    t.eq(#p.rows, 2)
    t.eq(p.rows[1].key, 2589, "20 linen before 4 leather")
    t.eq(p.rows[1].count, 20)
end

tests["bank pick: what Resources holds for a step stays with you, listed apart"] = function(t)
    local grants = { Held = function(_, key) return key == 2589 and 8 or 0 end }
    local p = pick({ { item = 2589, count = 20 } }, { grants = grants })
    t.eq(find(p.rows, 2589), nil, "not to the bank")
    local held = find(p.held, 2589)
    t.ok(held ~= nil, "listed as held")
    t.eq(held.count, 8, "how many the steps hold")
end

tests["bank pick: the player's bank / carry choices are honoured"] = function(t)
    local p = pick({ { item = 2589, count = 20 }, { item = 858, count = 5 } },
        { bankRules = { [2589] = "carry", [858] = "bank" } })
    t.eq(find(p.rows, 2589), nil, "carried by choice")
    t.ok(find(p.rows, 858) ~= nil, "banked by choice")
end

tests["bank entries: facts the client did not give stay unknown"] = function(t)
    local bag = B.Entries({ { item = 4444, count = 2 }, { item = "nonsense", count = 1 } }, info)
    t.eq(bag[1], { key = 4444, count = 2 })
    t.eq(bag[2].key, nil, "no item: no key")
    t.eq(B.Entries({ { item = 2589, count = 1 } }, function() error("x") end), { { key = 2589, count = 1 } })
end

-- ------------------------------------------------------------------ words

tests["bank words: what to bank, and what stays held"] = function(t)
    local grants = { Held = function(_, key) return key == 2318 and 4 or 0 end }
    local p = pick({ { item = 2589, count = 20 }, { item = 2318, count = 4 } }, { grants = grants })
    local lines = Present.BankLines(p)
    t.ok(has(lines, Present.BANK_HEADER), "a heading")
    t.ok(has(lines, "20 x Linen Cloth: kept for later"), "the row")
    t.ok(has(lines, Present.HELD_HEADER), "a held heading")
    t.ok(has(lines, "4 x Light Leather"), "the held row")
end

tests["bank words: nothing to bank says so; bags not read say so"] = function(t)
    t.ok(has(Present.BankLines(pick({ { item = 858, count = 1 } })), Present.NOTHING_TO_BANK), "nothing")
    t.eq(Present.BankLines(B.Pick(nil, {})), { "Can't list what to bank: the bags have not been read yet" })
end

-- Review of 78d94fc, finding 1 (F-086): item facts that were not read are
-- not "nothing to bank".
tests["bank pick: items whose kind was not read are counted, not passed over"] = function(t)
    local none = B.Pick(B.Entries({ { item = 2589, count = 20 }, { item = 2318, count = 4 } }, nil), {})
    t.eq(#none.rows, 0, "nothing can be picked without the item read")
    t.eq(none.unread, 2, "and both are counted as not read")
    local nilRead = B.Pick(B.Entries({ { item = 2589, count = 20 } }, function() return nil end), {})
    t.eq(nilRead.unread, 1, "an item read that answers nothing: the same")
    local mixed = pick({ { item = 2589, count = 20 }, { item = 4444, count = 1 }, { item = 858, count = 2 } })
    t.eq(#mixed.rows, 1)
    t.eq(mixed.unread, 1, "only the one with no facts; a potion that was read is simply carried")
    local chosen = B.Pick(B.Entries({ { item = 2589, count = 20 } }, nil), { bankRules = { [2589] = "bank" } })
    t.eq(chosen.unread, 0, "your own choice needs no item read")
    t.eq(#chosen.rows, 1)
    t.eq(pick({ { item = 858, count = 1 } }).unread, 0, "everything read: nothing unread")
end

tests["bank words: unread items are said, and 'nothing to bank' is only said when all were read"] = function(t)
    local none = Present.BankLines(B.Pick(B.Entries({ { item = 2589, count = 20 }, { item = 2318, count = 4 } }, nil), {}))
    t.eq(none, { "Can't tell what to bank: 2 items were not read yet." })
    local one = Present.BankLines(B.Pick(B.Entries({ { item = 2589, count = 20 } }, nil), {}))
    t.eq(one, { "Can't tell what to bank: 1 item was not read yet." })
    local mixed = Present.BankLines(pick({ { item = 2589, count = 20 }, { item = 4444, count = 1 } }))
    t.ok(has(mixed, "20 x Linen Cloth: kept for later"), "what was read is listed")
    t.ok(has(mixed, "1 more item was not read yet, so it is not listed."), "and the rest is said")
    t.ok(not has(mixed, Present.NOTHING_TO_BANK))
end

tests["bank: nothing in here deposits, withdraws or moves anything"] = function(t)
    for name in pairs(B) do
        local n = tostring(name):lower()
        t.ok(not (n:find("deposit") or n:find("withdraw") or n:find("move") or n:find("use")), "no acting function: " .. n)
    end
end

return tests
