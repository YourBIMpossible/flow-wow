local _, ns = ...
-- The sell list at a merchant, end to end, on the whole add-on loaded on a
-- fake client (owner, 2026-11-23: the window "looks good, but there's
-- nothing populated in it even though I have things to sell"). The entry is
-- the player's: the merchant window opening (MERCHANT_SHOW). What is held
-- here: with a mixed bag every item is on a line of the window, under "To
-- sell", "Kept, and why" or "Not sold, and why", or is counted as not read
-- yet; none is dropped without a word. Bags that read as holding nothing
-- say so, apart from bags that hold only things not to sell.
-- Look only: nothing here sells or moves anything. Made-up items. Not
-- tested in game.
local tests = {}

local BONE, ROCK, LETTER, SPOON, CLOTH, BLADE, FOG = 3300, 3301, 3302, 3303, 3304, 3305, 3306
local FACTS = {
    [BONE] = { name = "Cracked Bone", quality = 0, sellPrice = 5 },
    [ROCK] = { name = "Dull Rock", quality = 0, sellPrice = 0 },
    [LETTER] = { name = "Sealed Letter", quality = 1, sellPrice = 10, classID = 12 },
    [SPOON] = { name = "Bent Spoon", quality = 1, sellPrice = 7 },
    [CLOTH] = { name = "Frayed Cloth", quality = 1, sellPrice = 3, classID = 7 },
    [BLADE] = { name = "Notched Blade", quality = 2, sellPrice = 120, classID = 2 },
    -- FOG has no facts: the game has not read it yet.
}
local NAMED = { "Cracked Bone", "Dull Rock", "Sealed Letter", "Bent Spoon", "Frayed Cloth", "Notched Blade" }

local function boot(bag)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setBagItems(bag)
    c.setItemInfo(FACTS)
    c.setWindow("MerchantFrame", { shown = true })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon, addon.problems:count()
end

-- How many parts of that kind say that text.
local function count(rec, kind, text)
    local n = 0
    for _, p in ipairs(type(rec) == "table" and rec.parts or {}) do
        if p.kind == kind and (text == nil or p.text == text) then n = n + 1 end
    end
    return n
end

-- The how line of the window's empty state, or nil when it has none.
local function emptyHow(c, addon)
    local tree = ns.Kit.Window(addon.SellList.Tree(c, addon.store, nil, { status = addon.Reservations.NONE }))
    local how
    ns.Kit.Each(tree, function(p) if p.kind == "empty" then how = p.how end end)
    return how
end

tests["merchant list: every item in a mixed bag is on a line of the window"] = function(t)
    local c, addon, before = boot({
        { item = BONE, count = 2 }, { item = ROCK, count = 1 }, { item = LETTER, count = 1 },
        { item = SPOON, count = 1 }, { item = CLOTH, count = 6 }, { item = BLADE, count = 1 },
        { item = BONE, count = 3 }, { item = FOG, count = 1 },
    })
    if type(c.kitWindows().SellList) ~= "table" then t.ok(false, "a kit window") return end
    c.setMerchantOpen(true)
    local win = c.kitWindows().SellList
    t.eq(win.shown, true, "the window opens with the merchant")
    for _, name in ipairs(NAMED) do
        t.eq(count(win, "itemLine", name), 1, name .. " is on one line")
    end
    t.eq(count(win, "itemLine"), #NAMED, "and nothing else is")
    t.eq(count(win, "header", "1 item to sell"), 1, "the header counts what would be sold")
    t.eq(count(win, "section", addon.SellList.SELL_SECTION), 1)
    t.eq(count(win, "section", addon.SellList.KEPT_SECTION), 1)
    t.eq(count(win, "section", addon.SellList.OTHER_SECTION), 1)
    t.eq(count(win, "empty"), 0, "a window with lines has no empty state")
    t.eq(addon.sellList.last() ~= nil, true, "the same listing as text")
    t.eq(addon.problems:count(), before)
end

tests["merchant list: only things not to sell - it says nothing to sell and still lists them"] = function(t)
    local c, addon, before = boot({ { item = SPOON, count = 1 }, { item = LETTER, count = 1 } })
    if type(c.kitWindows().SellList) ~= "table" then t.ok(false, "a kit window") return end
    c.setMerchantOpen(true)
    local win = c.kitWindows().SellList
    t.eq(count(win, "empty", addon.SellList.NOTHING), 1)
    t.eq(emptyHow(c, addon), "Bags hold nothing " .. ns.id.title .. " would sell.")
    t.eq(count(win, "itemLine", "Bent Spoon"), 1, "what is not sold is still listed")
    t.eq(count(win, "itemLine", "Sealed Letter"), 1, "and what is kept")
    t.eq(addon.problems:count(), before)
end

-- Fails before the change: bags that read as empty said "Bags hold nothing
-- Z-Flow would sell.", the same words as bags full of things to keep, so a
-- player with items and an empty window could not tell which it was.
tests["merchant list: bags that read as holding nothing say so"] = function(t)
    local c, addon, before = boot({})
    if type(c.kitWindows().SellList) ~= "table" then t.ok(false, "a kit window") return end
    c.setMerchantOpen(true)
    local win = c.kitWindows().SellList
    t.eq(win.shown, true)
    t.eq(count(win, "empty", addon.SellList.NOTHING), 1)
    t.eq(count(win, "itemLine"), 0)
    t.eq(emptyHow(c, addon), addon.SellList.BAGS_EMPTY)
    t.eq(addon.problems:count(), before)
end

tests["merchant list: closing the merchant hides the window"] = function(t)
    local c = boot({ { item = BONE, count = 2 } })
    if type(c.kitWindows().SellList) ~= "table" then t.ok(false, "a kit window") return end
    c.setMerchantOpen(true)
    t.eq(c.kitWindows().SellList.shown, true)
    c.setMerchantOpen(false)
    t.eq(c.kitWindows().SellList.shown, false)
end

return tests
