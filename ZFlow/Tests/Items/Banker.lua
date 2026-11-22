-- S1 slice 1: the banker word (Items/Banker.lua), three look-only lists:
-- what to bank now, what your bank held at your last visit, and what in it
-- you would now sell. Fake client only; not tested in game.
local _, ns = ...

local B = ns.Banker
local tests = {}
local HOUR = 3600

local INFO = {
    [2589] = { name = "Linen Cloth", quality = 1, sellPrice = 13, classID = 7 },
    [858] = { name = "Lesser Healing Potion", quality = 1, sellPrice = 20, classID = 0 },
    [4865] = { name = "Ruined Pelt", quality = 0, sellPrice = 5, classID = 15 },
    [2318] = { name = "Light Leather", quality = 1, sellPrice = 15, classID = 7 },
}

local function info(item)
    local id = ns.Items.Id(item)
    local i = id and INFO[id]
    if not i then return nil end
    local out = {}
    for k, v in pairs(i) do out[k] = v end
    return out
end

local SAVED = { at = 1000, counts = { [2318] = 40, [4865] = 3, [2589] = 12 } }

tests["banker: the bank's items, biggest count first, with their facts"] = function(t)
    local items = B.Items(SAVED, info)
    t.eq(#items, 3)
    t.eq(items[1], { key = 2318, name = "Light Leather", count = 40, quality = 1, sellPrice = 15, classID = 7 })
    t.eq(items[2].key, 2589)
    t.eq(items[3], { key = 4865, name = "Ruined Pelt", count = 3, quality = 0, sellPrice = 5, classID = 15 })
    t.eq(B.Items(nil, info), nil, "the bank not seen: nil, not an empty bank")
    t.eq(B.Items({ at = 1 }, info), nil, "no counts: not seen")
    t.eq(B.Items({ counts = {} }, info), {}, "seen empty")
end

tests["banker: a bad count is left out, a name not read is not made up"] = function(t)
    local items = B.Items({ counts = { [2589] = 1.5, ["not an item"] = 3, [9999] = 2, ["2318"] = 4 } }, info)
    t.eq(#items, 2)
    t.eq(items[1], { key = 2318, name = "Light Leather", count = 4, quality = 1, sellPrice = 15, classID = 7 })
    t.eq(items[2], { key = 9999, count = 2 })
    t.eq(#B.Items({ counts = { [2589] = 2 } }, nil), 1, "no item read: the counts still list")
    t.eq(B.Items({ counts = { [2589] = 2 } }, function() error("boom") end), { { key = 2589, count = 2 } })
end

tests["banker: in your bank, with how long ago"] = function(t)
    local items = B.Items(SAVED, info)
    t.eq(B.InBankLines(items, 1000, 1000 + 2 * HOUR), {
        "In your bank, as of 2 h ago:",
        "40 x Light Leather",
        "12 x Linen Cloth",
        "3 x Ruined Pelt",
    })
    t.eq(B.InBankLines(items, nil, 5000)[1], "In your bank, as of your last visit:", "when not kept: not guessed")
    t.eq(B.InBankLines(items, 1000, nil)[1], "In your bank, as of your last visit:", "now not read: not guessed")
    t.eq(B.InBankLines(nil, nil, 5000), { B.NOT_SEEN })
    t.eq(B.InBankLines({}, 1000, 1000), { "In your bank, as of 0 min ago: nothing." })
    t.eq(B.InBankLines({ { key = 9999, count = 2 } }, nil, nil)[2], "2 x item 9999")
end

tests["banker: a long list is cut short and says how many more"] = function(t)
    local items = B.Items(SAVED, info)
    t.eq(B.InBankLines(items, 1000, 1000, 2), {
        "In your bank, as of 0 min ago:",
        "40 x Light Leather",
        "12 x Linen Cloth",
        "and 1 more.",
    })
    t.eq(B.MAX, 10)
end

tests["banker: what in your bank you would now sell, by the sell rules"] = function(t)
    local items = B.Items(SAVED, info)
    local rows = B.SellRows(items, {})
    t.eq(rows, { { key = 4865, name = "Ruined Pelt", count = 3, reason = "junk" } })
    t.eq(B.SellLines(rows), { B.SELL_HEADER, "3 x Ruined Pelt: junk" })
    t.eq(B.SellRows(items, { choices = { never = { [4865] = true } } }), {}, "on your never-sell list: kept")
    t.eq(B.SellLines({}), { B.NOTHING_TO_SELL })
    t.eq(B.SellRows(nil, {}), nil)
    t.eq(B.SellLines(nil), { B.SELL_NOT_SEEN })
end

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setClock(1000 + 3 * HOUR)
    c.setItemInfo(INFO)
    if opts.bag ~= false then c.setBagItems({ { item = 2589, count = 20 }, { item = 858, count = 5 } }) end
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    local api = B.Declare(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api
end

local function said(c, from)
    local out = {}
    for i = from + 1, #c.printed do out[#out + 1] = c.printed[i] end
    return out
end

tests["banker word: before the bank is seen, the bags' list and how to fill the rest"] = function(t)
    local _, c, api = start()
    local before = #c.printed
    c.slashes[ns.id.slash]("banker")
    local p = ns.id.title .. ": "
    t.eq(said(c, before), {
        p .. "To bank (nothing is moved for you):",
        p .. "20 x Linen Cloth: kept for later",
        p .. B.NOT_SEEN,
        p .. B.SELL_NOT_SEEN,
    })
    t.eq(api.runs(), 1)
end

tests["banker word: the bank as last seen, and what in it you would sell"] = function(t)
    local k, c = start()
    t.eq(k.store:set("char", ns.HaveTip.PATH, { at = 1000, counts = { [2318] = 40, [4865] = 3 } }), true)
    local before = #c.printed
    c.slashes[ns.id.slash]("banker")
    local p = ns.id.title .. ": "
    t.eq(said(c, before), {
        p .. "To bank (nothing is moved for you):",
        p .. "20 x Linen Cloth: kept for later",
        p .. "In your bank, as of 3 h ago:",
        p .. "40 x Light Leather",
        p .. "3 x Ruined Pelt",
        p .. B.SELL_HEADER,
        p .. "3 x Ruined Pelt: junk",
    })
    -- Your never-sell list counts here as at the vendor.
    t.eq(k.store:set("char", "settings.sell.never", { [4865] = true }), true)
    before = #c.printed
    c.slashes[ns.id.slash]("banker")
    local lines = said(c, before)
    t.eq(lines[#lines], p .. B.NOTHING_TO_SELL)
end

tests["banker word: bags not read still lists the bank"] = function(t)
    local k, c = start({ bag = false })
    t.eq(k.store:set("char", ns.HaveTip.PATH, { at = 1000, counts = { [2318] = 40 } }), true)
    local before = #c.printed
    c.slashes[ns.id.slash]("banker")
    local lines = said(c, before)
    local p = ns.id.title .. ": "
    t.eq(lines[1], p .. "Can't list what to bank: " .. ns.ItemPresent.BAGS_UNREAD)
    t.eq(lines[2], p .. "In your bank, as of 3 h ago:")
    t.eq(lines[#lines], p .. B.NOTHING_TO_SELL)
end

tests["banker word: one list failing does not stop the others"] = function(t)
    local k, c = start()
    t.eq(k.store:set("char", ns.HaveTip.PATH, { at = 1000, counts = { [2318] = 40 } }), true)
    c.itemInfo = function() error("boom") end
    c.bagItems = function() error("bags boom") end
    local before = #c.printed
    t.ok(pcall(c.slashes[ns.id.slash], "banker"), "the word does not raise")
    local lines = said(c, before)
    local p = ns.id.title .. ": "
    t.eq(lines[1], p .. "To bank: " .. B.FAILED)
    t.eq(lines[2], p .. "In your bank, as of 3 h ago:")
    t.eq(lines[3], p .. "40 x item 2318")
end

tests["banker word: help names it, and nothing is moved"] = function(t)
    local _, c = start()
    t.ok(type(B.HELP) == "string" and B.HELP:find("moves nothing", 1, true) ~= nil)
    t.eq(B.WORD, "banker")
    local before = #c.printed
    c.slashes[ns.id.slash]("help")
    local found = false
    for _, line in ipairs(said(c, before)) do
        if line:find("banker", 1, true) then found = true end
    end
    t.ok(found, "help lists the banker word")
end

return tests
