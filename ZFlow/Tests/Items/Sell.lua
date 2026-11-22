local _, ns = ...

-- Tests for ZFlow/Items/Sell.lua. Pure: the bag, the rules and the price
-- book are made up. Nothing is sold anywhere in here.

local S, P = ns.ItemSell, ns.Prices
local tests = {}

local function fang(count)
    return { key = 97, name = "Broken Fang", count = count, quality = 0, sellPrice = 4 }
end

local function leather(count)
    return { key = 2318, name = "Light Leather", count = count, quality = 1, sellPrice = 15, classID = 7 }
end

-- A rule list that sells everything it is asked about.
local function sellAll()
    return { { key = "all", order = 1, check = function()
        return { action = "sell", reason = "test rule", basis = "recommendation" }
    end } }
end

-- A rule list that answers by item key: { [key] = action }.
local function byKey(actions)
    return { { key = "byKey", order = 1, check = function(i)
        local action = actions[i.key]
        if action then return { action = action, reason = "test " .. action, basis = "recommendation" } end
    end } }
end

tests["sell list: bags not read gives no rows and no figures"] = function(t)
    local l = S.List(nil, {})
    t.eq(l.ok, false, "not ok")
    t.eq(l.problem, S.BAGS_UNREAD, "and it says why")
    t.eq(l.problem, "the bags have not been read yet", "the words")
    t.eq(#l.rows, 0, "no rows")
    t.eq(l.total.known, nil, "no total, not 0")
    t.eq(l.total.estimated, nil, "no estimate, not 0")
    t.eq(l.total.unknown, nil, "no count of unknowns either")
    t.eq(l.kept.auction.rows, nil, "nothing counted for the auction house")
    t.eq(l.kept.auction.count, nil, "nor how many")
    t.eq(l.kept.disenchant.rows, nil, "nothing counted for disenchanting")
    t.eq(l.kept.disenchant.count, nil, "nor how many")
    t.eq(S.List("bags", {}).ok, false, "not a table: the same")
end

tests["sell list: an empty bag is a read bag with nothing to sell"] = function(t)
    local l = S.List({}, {})
    t.eq(l.ok, true, "ok")
    t.eq(l.problem, nil, "no problem")
    t.eq(#l.rows, 0, "no rows")
    t.eq(l.total.known, 0, "a known nothing")
    t.eq(l.total.estimated, 0, "no estimate")
    t.eq(l.total.unknown, 0, "nothing unknown")
    t.eq(l.kept.auction, { rows = 0, count = 0 }, "nothing for the auction house")
    t.eq(l.kept.disenchant, { rows = 0, count = 0 }, "nothing to disenchant")
    t.eq(S.List({}).ok, true, "no context at all: the same")
end

tests["sell list: a row has the item, the count, the price of one and the reason"] = function(t)
    local l = S.List({ fang(3) }, {})
    t.eq(#l.rows, 1, "one row")
    local r = l.rows[1]
    t.eq(r.key, 97, "the item's key")
    t.eq(r.name, "Broken Fang", "its name as read")
    t.eq(r.count, 3, "how many")
    t.eq(r.unit, 4, "the price of one")
    t.eq(r.basis, P.OBSERVED, "the game stated it")
    t.eq(r.source, S.ITEM_SOURCE, "and where it was stated")
    t.eq(r.priceText, "4c", "for the player")
    t.eq(r.total, 12, "count times the price of one")
    t.eq(r.reason, "junk", "the rule's reason")
    t.eq(r.rule, "junk", "and the rule")
    t.eq(l.total, { known = 12, estimated = 0, unknown = 0 }, "the totals")
end

tests["sell list: a name that was not read is not made up"] = function(t)
    local l = S.List({ { key = 97, count = 1, quality = 0, sellPrice = 4 } }, {})
    t.eq(l.rows[1].name, nil, "no name")
end

tests["sell list: what the rules keep is not listed"] = function(t)
    local l = S.List({
        leather(5),
        { key = 98, name = "Sealed Note", count = 1, classID = 12 },
        fang(2),
    }, {})
    t.eq(#l.rows, 1, "only the grey one")
    t.eq(l.rows[1].key, 97, "the fang")
end

tests["sell list: an item the player said never to sell is never listed"] = function(t)
    local c = { choices = { never = { [97] = true } } }
    t.eq(#S.List({ fang(3) }, c).rows, 0, "not with the built-in rules")
    c.rules = sellAll()
    local l = S.List({ fang(3), leather(2) }, c)
    t.eq(#l.rows, 1, "not even when a rule says sell")
    t.eq(l.rows[1].key, 2318, "the other item is still listed")
    t.eq(l.total.known, 30, "and the never item adds nothing to the total")
end

tests["sell list: an item the player chose to keep is not listed either"] = function(t)
    local c = { choices = { keep = { [97] = true } }, rules = sellAll() }
    t.eq(#S.List({ fang(3) }, c).rows, 0, "kept whatever the rules say")
end

tests["sell list: only the part a claim does not hold is listed"] = function(t)
    local grants = { Held = function(_, key) return key == 97 and 8 or 0 end }
    local l = S.List({ fang(12) }, { grants = grants })
    t.eq(#l.rows, 1, "one row")
    t.eq(l.rows[1].count, 4, "twelve less the eight held")
    t.eq(l.rows[1].total, 16, "priced for the four")
end

tests["sell list: the same item in several slots is one row, counted together"] = function(t)
    local grants = { Held = function(_, key) return key == 97 and 4 or 0 end }
    local l = S.List({ fang(3), leather(1), fang(2) }, { grants = grants })
    t.eq(#l.rows, 1, "one row for the fangs")
    t.eq(l.rows[1].count, 1, "five in all, four held")
    local all = S.List({ fang(3), leather(1), fang(2) }, { rules = sellAll() })
    t.eq(#all.rows, 2, "one row per item")
    t.eq(all.rows[1].key, 97, "in the order first met")
    t.eq(all.rows[1].count, 5, "both slots")
    t.eq(all.rows[2].key, 2318, "then the next")
end

tests["sell list: a count that is not known stays not known"] = function(t)
    local l = S.List({ { key = 97, quality = 0, sellPrice = 4 } }, {})
    t.eq(#l.rows, 1, "still listed")
    t.eq(l.rows[1].count, nil, "no count, not 0")
    t.eq(l.rows[1].unit, 4, "the price of one is known")
    t.eq(l.rows[1].total, nil, "no total for the row")
    t.eq(l.total, { known = 0, estimated = 0, unknown = 1 }, "and the row counts as unknown")
    local mixed = S.List({ fang(3), { key = 97, quality = 0, sellPrice = 4 } }, {})
    t.eq(mixed.rows[1].count, nil, "one slot with no count: the whole count is not known")
end

tests["sell list: a price nobody saw reads price unknown, never 0"] = function(t)
    local l = S.List({ { key = 50, name = "Odd Cog", count = 2 } }, { rules = sellAll() })
    local r = l.rows[1]
    t.eq(r.unit, nil, "no figure")
    t.eq(r.basis, P.UNKNOWN, "the basis says so")
    t.eq(r.source, nil, "no source")
    t.eq(r.priceText, "price unknown—check vendor", "the words")
    t.eq(S.PRICE_UNKNOWN, "price unknown—check vendor", "kept in one place")
    t.eq(r.total, nil, "no total for the row")
    t.eq(l.total, { known = 0, estimated = 0, unknown = 1 }, "counted as unknown, not as 0")
end

tests["sell list: an observed price from the book is used when the item has none"] = function(t)
    local book = {}
    P.Record(book, 50, S.KIND, 25, { source = "merchant window", seenAt = 10 })
    local l = S.List({ { key = 50, count = 2 } }, { rules = sellAll(), book = book })
    local r = l.rows[1]
    t.eq(S.KIND, "sell", "the kind a merchant's paying price is recorded under")
    t.eq(r.unit, 25, "the book's figure")
    t.eq(r.basis, P.OBSERVED, "observed")
    t.eq(r.source, "merchant window", "with its source")
    t.eq(r.priceText, "25c", "plain, as observed")
    t.eq(l.total, { known = 50, estimated = 0, unknown = 0 }, "it counts as known")
end

tests["sell list: the item's own price comes before the book"] = function(t)
    local book = {}
    P.Record(book, 97, S.KIND, 99, { source = "merchant window" })
    local l = S.List({ fang(1) }, { book = book })
    t.eq(l.rows[1].unit, 4, "the item's own")
    t.eq(l.rows[1].source, S.ITEM_SOURCE, "and its source")
end

tests["sell list: an estimate is labelled with its source and never added to the known total"] = function(t)
    local book = {}
    P.Record(book, 50, S.KIND, 50, { basis = P.ESTIMATED, source = "price of a like item" })
    local l = S.List({ { key = 50, count = 3 }, fang(2) }, { rules = sellAll(), book = book })
    local r = l.rows[1]
    t.eq(r.unit, 50, "the estimate")
    t.eq(r.basis, P.ESTIMATED, "its basis")
    t.eq(r.source, "price of a like item", "its source")
    t.eq(r.priceText, "about 50c (estimate, price of a like item)", "labelled, with the source")
    t.eq(r.total, 150, "the row's own figure")
    t.eq(l.total, { known = 8, estimated = 150, unknown = 0 }, "kept apart from the known total")
end

tests["sell list: an estimate with no source is price unknown"] = function(t)
    local book = {}
    P.Record(book, 50, S.KIND, 50, { basis = P.ESTIMATED })
    local l = S.List({ { key = 50, count = 3 } }, { rules = sellAll(), book = book })
    t.eq(l.rows[1].unit, nil, "no figure")
    t.eq(l.rows[1].basis, P.UNKNOWN, "unknown")
    t.eq(l.rows[1].priceText, "price unknown—check vendor", "the words")
    t.eq(l.total, { known = 0, estimated = 0, unknown = 1 }, "counted as unknown")
end

tests["sell list: what the game says can not be sold is not listed"] = function(t)
    local l = S.List({ { key = 60, count = 1, sellPrice = 0 }, fang(1) }, { rules = sellAll() })
    t.eq(#l.rows, 1, "only the one with a price")
    t.eq(l.rows[1].key, 97, "the fang")
    t.eq(l.unsellable, 1, "and the other is counted")
    local book = {}
    P.Record(book, 61, S.KIND, 0, { source = "merchant window" })
    local seen = S.List({ { key = 61, count = 1 } }, { rules = sellAll(), book = book })
    t.eq(#seen.rows, 0, "a merchant seen to pay nothing: not listed")
    t.eq(seen.unsellable, 1, "counted")
end

tests["sell list: the footer counts what is kept for the auction house and for disenchanting"] = function(t)
    local rules = byKey({ [10] = "auction", [11] = "auction", [12] = "disenchant", [97] = "sell" })
    local l = S.List({
        { key = 10, count = 5 }, { key = 11, count = 2 }, { key = 12, count = 1 }, fang(1), leather(3),
    }, { rules = rules })
    t.eq(#l.rows, 1, "none of them is listed to sell")
    t.eq(l.rows[1].key, 97, "only the one to sell")
    t.eq(l.kept.auction, { rows = 2, count = 7 }, "two items, seven in all, for the auction house")
    t.eq(l.kept.disenchant, { rows = 1, count = 1 }, "one to disenchant")
end

tests["sell list: a footer count that is not known stays not known"] = function(t)
    local rules = byKey({ [10] = "auction", [11] = "auction" })
    local l = S.List({ { key = 10, count = 5 }, { key = 11 } }, { rules = rules })
    t.eq(l.kept.auction.rows, 2, "two items")
    t.eq(l.kept.auction.count, nil, "how many in all is not known")
    t.eq(l.kept.disenchant, { rows = 0, count = 0 }, "the other footer is not touched by it")
end

tests["sell list: a never item is not counted in the footer"] = function(t)
    local l = S.List({ { key = 10, count = 5 } },
                     { rules = byKey({ [10] = "auction" }), choices = { never = { [10] = true } } })
    t.eq(l.kept.auction, { rows = 0, count = 0 }, "kept by the player's choice, not for the auction house")
end

tests["sell list: what is not a readable item is counted, not listed"] = function(t)
    local l = S.List({ "Broken Fang", { count = 2, quality = 0, sellPrice = 4 }, fang(1) }, { rules = sellAll() })
    t.eq(#l.rows, 1, "only the readable one")
    t.eq(l.unread, 2, "the two others are counted")
    t.eq(S.List({ fang(1) }, {}).unread, 0, "none otherwise")
    t.eq(S.List({ fang(1) }, {}).unsellable, 0, "and nothing unsellable")
end

tests["sell list: a failing rule keeps the item"] = function(t)
    local rules = { { key = "broken", order = 1, check = function() error("boom") end },
                    { key = "all", order = 2, check = function()
                        return { action = "sell", reason = "test rule", basis = "recommendation" }
                    end } }
    t.eq(#S.List({ fang(3) }, { rules = rules }).rows, 0, "not listed")
end

tests["sell list: the bag and the context are left as they were"] = function(t)
    local item = fang(3)
    local bag = { item, fang(2) }
    local c = { choices = { never = {} } }
    local l = S.List(bag, c)
    t.eq(#bag, 2, "the bag has its two entries")
    t.eq(item.count, 3, "the entry has its own count")
    t.eq(bag[2].count, 2, "the other too")
    t.eq(next(c.choices.never), nil, "nothing written into the choices")
    t.ok(l.rows[1] ~= item, "a row is its own table")
    t.eq(l.rows[1].count, 5, "and holds the count of both")
end

return tests
