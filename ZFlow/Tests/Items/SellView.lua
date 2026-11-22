local _, ns = ...

-- Tests for ZFlow/Items/SellView.lua and the sell-list words in
-- ZFlow/Items/Present.lua (L6-A: the vendor sell list). Pure: the bag
-- stacks, the item facts and the price book are made up. Nothing is sold,
-- bought or moved anywhere in here.

local V, Present, P = ns.SellView, ns.ItemPresent, ns.Prices
local tests = {}

-- The item facts a client would give, by item ID (the CLIENT NEED itemInfo).
local INFO = {
    [97] = { name = "Broken Fang", quality = 0, sellPrice = 4 },
    [2318] = { name = "Light Leather", quality = 1, sellPrice = 15, classID = 7 },
    [6948] = { name = "Hearthstone", quality = 1, sellPrice = 0 },
    [5056] = { name = "Quest Thing", quality = 1, sellPrice = 0, classID = 12 },
    [3000] = { name = "Grey Mystery", quality = 0 },          -- no sell price given
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

local function contains(lines, part)
    for _, l in ipairs(lines or {}) do
        if type(l) == "string" and l:find(part, 1, true) then return true end
    end
    return false
end

-- ---------------------------------------------------------------- Bag

tests["sell view: bags not read stay unread"] = function(t)
    t.eq(V.Bag(nil, info), nil, "no stacks: no bag, not an empty one")
    t.eq(V.Bag("x", info), nil, "not a table: the same")
end

tests["sell view: stacks become bag entries with the item's facts"] = function(t)
    local bag = V.Bag({ { item = "item:97", count = 3 }, { item = 2318, count = 4 } }, info)
    t.eq(#bag, 2, "one entry per stack")
    t.eq(bag[1], { key = 97, name = "Broken Fang", count = 3, quality = 0, sellPrice = 4 }, "first")
    t.eq(bag[2], { key = 2318, name = "Light Leather", count = 4, quality = 1, sellPrice = 15, classID = 7 }, "second")
end

tests["sell view: facts the client did not give stay unknown, never 0"] = function(t)
    local bag = V.Bag({ { item = 4444, count = 2 }, { item = 3000, count = 1 } }, info)
    t.eq(bag[1], { key = 4444, count = 2 }, "no facts at all: key and count only")
    t.eq(bag[2].sellPrice, nil, "no sell price given: nil, not 0")
    t.eq(bag[2].quality, 0, "what was given is kept")
end

tests["sell view: no item read on the client at all"] = function(t)
    local bag = V.Bag({ { item = 97, count = 1 } }, nil)
    t.eq(bag, { { key = 97, count = 1 } }, "the stack is still listed, with nothing made up")
end

tests["sell view: an item read that fails or answers junk is no fact"] = function(t)
    local bag = V.Bag({ { item = 97, count = 1 } }, function() error("boom") end)
    t.eq(bag, { { key = 97, count = 1 } }, "an error reads as unknown")
    bag = V.Bag({ { item = 97, count = 1 } }, function() return "x" end)
    t.eq(bag, { { key = 97, count = 1 } }, "not a table: unknown")
    bag = V.Bag({ { item = 97, count = 1 } }, function() return { name = 5, quality = -1, sellPrice = 0 / 0 } end)
    t.eq(bag, { { key = 97, count = 1 } }, "badly typed facts are left out")
end

tests["sell view: a stack that is no item is passed on unreadable"] = function(t)
    local bag = V.Bag({ { item = "nonsense", count = 1 }, "x" }, info)
    t.eq(#bag, 2, "both still there")
    t.eq(bag[1].key, nil, "no key: Sell counts it as unread")
    t.eq(bag[2].key, nil, "the same")
end

-- ---------------------------------------------------------------- Kept

local function bagOf(...)
    return V.Bag({ ... }, info)
end

tests["sell view: kept lists what a rule keeps, with the reason"] = function(t)
    local bag = bagOf({ item = 6948, count = 1 }, { item = 5056, count = 2 }, { item = 97, count = 3 })
    local kept = V.Kept(bag, {})
    t.eq(kept.ok, true, "read")
    local hearth = find(kept.rows, 6948)
    t.ok(hearth ~= nil, "the hearthstone is kept")
    t.eq(hearth.reason, "can't be sold to a merchant", "with its reason")
    t.eq(hearth.name, "Hearthstone", "and its name")
    local quest = find(kept.rows, 5056)
    t.ok(quest ~= nil, "the quest item is kept")
    t.ok(quest.reason:find("quest item", 1, true) ~= nil, "for being a quest item")
    t.eq(quest.count, 2, "both of them")
    t.eq(find(kept.rows, 97), nil, "junk is sold, not kept")
end

tests["sell view: the player's never-sell list is shown as kept"] = function(t)
    local bag = bagOf({ item = 97, count = 3 })
    local kept = V.Kept(bag, { choices = { never = { [97] = true } } })
    local fang = find(kept.rows, 97)
    t.ok(fang ~= nil, "a never-sell item is listed as kept")
    t.eq(fang.reason, "on your never-sell list", "with the choice as the reason")
    t.eq(fang.basis, "choice", "it rests on the player's choice")
end

tests["sell view: an item no rule speaks for is not listed as kept"] = function(t)
    local kept = V.Kept(bagOf({ item = 2318, count = 4 }), {})
    t.eq(#kept.rows, 0, "ordinary goods are not a 'kept' line")
end

tests["sell view: a part kept by count lists only that part"] = function(t)
    local grants = { Held = function(_, key) return key == 2318 and 8 or 0 end }
    local junkLeather = { { key = "all", order = 30, check = function()
        return { action = "sell", reason = "test", basis = "recommendation" }
    end } }
    for _, r in ipairs(ns.Disposition.RULES) do junkLeather[#junkLeather + 1] = r end
    local kept = V.Kept(bagOf({ item = 2318, count = 12 }), { grants = grants, rules = junkLeather })
    local leather = find(kept.rows, 2318)
    t.ok(leather ~= nil, "listed")
    t.eq(leather.count, 8, "only the 8 held")
    t.ok(leather.reason:find("8 held for your steps", 1, true) ~= nil, "with the hold as the reason")
end

tests["sell view: bags not read keep nothing listed"] = function(t)
    local kept = V.Kept(nil, {})
    t.eq(kept.ok, false, "not read")
    t.eq(#kept.rows, 0, "no rows")
end

tests["sell view: stacks of one item are kept as one line"] = function(t)
    local kept = V.Kept(bagOf({ item = 5056, count = 1 }, { item = 5056, count = 2 }), {})
    t.eq(#kept.rows, 1, "one line")
    t.eq(kept.rows[1].count, 3, "with both counted")
end

-- ---------------------------------------------------------------- words

local function view(stacks, context)
    context = context or {}
    local bag = V.Bag(stacks, info)
    return ns.ItemSell.List(bag, context), V.Kept(bag, context)
end

tests["sell words: an observed price shows the money and where it is from"] = function(t)
    local list, kept = view({ { item = 97, count = 3 } })
    local lines = Present.SellLines(list, kept)
    t.ok(has(lines, "3 x Broken Fang: 4c each, 12c (the item's own sell price)"), "the row")
    t.ok(has(lines, "Would sell for: 12c"), "the total")
end

tests["sell words: an unknown price says so and shows no figure"] = function(t)
    local rows = { { key = 3000, name = "Grey Mystery", count = 2, basis = P.UNKNOWN, priceText = "price unknown" } }
    local list = { ok = true, rows = rows, total = { known = 0, estimated = 0, unknown = 1 } }
    local lines = Present.SellLines(list, { ok = true, rows = {} })
    t.ok(has(lines, "2 x Grey Mystery: " .. Present.VENDOR_PRICE_UNKNOWN), "the row")
    t.eq(Present.VENDOR_PRICE_UNKNOWN, "price unknown—check vendor", "the F-085 words, with the em dash (L6-H)")
    t.ok(has(lines, "Would sell for: 1 price unknown—check vendor"), "counted, not priced")
    local two = { ok = true, rows = {}, total = { known = 0, estimated = 0, unknown = 2 } }
    t.eq(Present.SellTotal(two), "Would sell for: 2 prices unknown—check vendor", "the plural keeps the same words")
    t.ok(not contains(lines, "0c"), "never a 0 for a price nobody saw")
end

tests["sell words: an estimate is labelled and never added to the observed total"] = function(t)
    local book = {}
    P.Record(book, 3000, ns.ItemSell.KIND, 25, { basis = P.ESTIMATED, source = "Flow's import" })
    -- A rule that sells both: the grey has no sell price, so junk alone would not.
    local sellBoth = { { key = "both", order = 1, check = function()
        return { action = "sell", reason = "test", basis = "recommendation" }
    end } }
    local list, kept = view({ { item = 3000, count = 2 }, { item = 97, count = 1 } }, { book = book, rules = sellBoth })
    local lines = Present.SellLines(list, kept)
    t.ok(has(lines, "2 x Grey Mystery: about 25c each (estimate, Flow's import), about 50c"), "the row")
    t.ok(has(lines, "Would sell for: 4c, plus about 50c (estimate)"), "two figures, not one sum")
end

tests["sell words: kept items are listed apart, each with its reason"] = function(t)
    local list, kept = view({ { item = 6948, count = 1 }, { item = 97, count = 3 } })
    local lines = Present.SellLines(list, kept)
    t.ok(has(lines, Present.KEPT_HEADER), "a kept heading")
    t.ok(has(lines, "Hearthstone: can't be sold to a merchant"), "the kept line")
    local sellAt, keptAt
    for i, l in ipairs(lines) do
        if l == Present.SELL_HEADER then sellAt = i end
        if l == Present.KEPT_HEADER then keptAt = i end
    end
    t.ok(sellAt and keptAt and sellAt < keptAt, "sold first, kept after")
end

tests["sell words: nothing to sell says so"] = function(t)
    local list, kept = view({ { item = 2318, count = 1 } })
    local lines = Present.SellLines(list, kept)
    t.ok(has(lines, Present.NOTHING_TO_SELL), "says there is nothing")
    t.ok(not has(lines, Present.KEPT_HEADER), "no empty kept heading")
end

tests["sell words: bags not read give one line and no figures"] = function(t)
    local lines = Present.SellLines(ns.ItemSell.List(nil, {}), V.Kept(nil, {}))
    t.eq(lines, { "Can't list what to sell: " .. ns.ItemSell.BAGS_UNREAD }, "one line")
end

tests["sell words: a row with no name reads 'item <key>' and an unknown count says so"] = function(t)
    local rows = { { key = 4444, count = nil, unit = 10, basis = P.OBSERVED, source = "merchant window" } }
    local list = { ok = true, rows = rows, total = { known = 0, estimated = 0, unknown = 1 } }
    local lines = Present.SellLines(list, { ok = true, rows = {} })
    t.ok(has(lines, "item 4444 (how many not known): 10c each (merchant window)"), "no name made up, no count made up")
end

tests["sell words: unreadable and unsellable entries are counted in a note"] = function(t)
    local list = { ok = true, rows = {}, total = { known = 0, estimated = 0, unknown = 0 }, unread = 2, unsellable = 1 }
    local lines = Present.SellLines(list, { ok = true, rows = {} })
    t.ok(has(lines, "2 bag slots could not be read"), "unread")
end

tests["sell view: nothing in here sells, buys or moves anything"] = function(t)
    for name in pairs(V) do
        local lower = tostring(name):lower()
        t.ok(not (lower:find("^sell$") or lower:find("buy") or lower:find("use") or lower:find("pickup")),
            "no acting function: " .. tostring(name))
    end
end

return tests
