local _, ns = ...
-- Grey items in the sell list, end to end, on the whole add-on loaded on a
-- fake client (lead section 340): every bag item the list does not offer
-- for sale still has a row with its reason in the player's words (kept, a
-- grey item with no vendor price, a price not read yet, the reservations
-- not known, no rule sells it); item facts that arrive late redraw the list
-- when the game says they arrived (GET_ITEM_INFO_RECEIVED); and the saved
-- diagnostics name the first grey item in the bags and what was done with
-- it (diag.sellGrey). Look only: nothing here sells or moves anything.
-- Made-up items. Not tested in game.
--
-- Fails before the change: a grey item whose price is not read yet has no
-- line at all (the window says "Nothing to sell."), the window is not drawn
-- again on GET_ITEM_INFO_RECEIVED, an item no rule sells has no line, and
-- diag.sellGrey is nil.
local tests = {}

local BONE, ROCK, LETTER, SPOON = 3300, 3301, 3302, 3303
local FULL = {
    [BONE] = { name = "Cracked Bone", quality = 0, sellPrice = 5 },
    [ROCK] = { name = "Dull Rock", quality = 0, sellPrice = 0 },
    [LETTER] = { name = "Sealed Letter", quality = 1, sellPrice = 10, classID = 12 },
    [SPOON] = { name = "Bent Spoon", quality = 1, sellPrice = 7 },
}

local atBoot = setmetatable({}, { __mode = "k" })
local function newProblems(addon) return addon.problems:count() - atBoot[addon] end

-- opts: bag, info (the item facts at the start).
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setBagItems(opts.bag or { { item = BONE, count = 2 } })
    c.setItemInfo(opts.info or FULL)
    c.setWindow("MerchantFrame", { shown = true })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    atBoot[addon] = addon.problems:count()
    return c, addon
end

local function shows(rec, kind, text)
    for _, p in ipairs(type(rec) == "table" and rec.parts or {}) do
        if p.kind == kind and p.text == text then return true end
    end
    return false
end

-- The note of the item line named `name` in a listing made now, or false.
local function noteOf(c, addon, name, r)
    local tree = ns.Kit.Window(addon.SellList.Tree(c, addon.store, nil, r or { status = addon.Reservations.NONE }))
    local got = false
    ns.Kit.Each(tree, function(p) if p.kind == "itemLine" and p.name == name then got = p.note end end)
    return got
end

local function grey(c)
    local db = c.saved(ns.id.accountDB)
    local d = type(db) == "table" and type(db.diag) == "table" and db.diag.sellGrey or nil
    if type(d) ~= "table" then return nil end
    return { item = d.item, rule = d.rule, why = d.why }
end

tests["sell grey: a grey item with no vendor price is a row that says it can't be sold"] = function(t)
    local c, addon = boot({ bag = { { item = ROCK, count = 4 } } })
    if type(c.kitWindows().SellList) ~= "table" then t.ok(false, "a kit window") return end
    c.setMerchantOpen(true)
    t.ok(shows(c.kitWindows().SellList, "itemLine", "Dull Rock"), "the grey item has its line")
    t.eq(noteOf(c, addon, "Dull Rock"), "can't be sold to a merchant", "and why")
    t.eq(grey(c), { item = "Dull Rock", rule = "unsellable", why = "can't be sold to a merchant" },
        "the diagnostics name it")
    t.eq(newProblems(addon), 0)
end

tests["sell grey: price not read yet, then the sell line once the facts arrive"] = function(t)
    local c, addon = boot({ info = { [BONE] = { name = "Cracked Bone", quality = 0 } } })
    if type(c.kitWindows().SellList) ~= "table" then t.ok(false, "a kit window") return end
    c.setMerchantOpen(true)
    local win = c.kitWindows().SellList
    t.ok(shows(win, "itemLine", "Cracked Bone"), "the grey item does not vanish")
    t.ok(not shows(win, "empty", "Nothing to sell."), "a price not read is not nothing to sell")
    t.eq(noteOf(c, addon, "Cracked Bone"), "price not read yet", "and why")
    t.eq(grey(c), { item = "Cracked Bone", rule = "not read", why = "price not read yet" })
    c.setItemInfo(FULL)
    c.fire("GET_ITEM_INFO_RECEIVED", BONE, true)
    c.advance(1, 4)
    win = c.kitWindows().SellList
    t.ok(shows(win, "header", "1 item to sell"), "drawn again when the facts arrive")
    t.ok(shows(win, "itemLine", "Cracked Bone"), "now as an item to sell")
    t.eq(grey(c), { item = "Cracked Bone", rule = "sold", why = "junk" })
    t.eq(newProblems(addon), 0)
end

tests["sell grey: nothing read at first, then the list once the game says the facts arrived"] = function(t)
    local c, addon = boot({ info = {} })
    if type(c.kitWindows().SellList) ~= "table" then t.ok(false, "a kit window") return end
    c.setMerchantOpen(true)
    t.ok(shows(c.kitWindows().SellList, "empty", "Items not read yet."), "not read, said so")
    c.setItemInfo(FULL)
    c.fire("GET_ITEM_INFO_RECEIVED", BONE, true)
    c.advance(1, 4)
    t.ok(shows(c.kitWindows().SellList, "header", "1 item to sell"), "drawn again without a bag change")
    t.eq(newProblems(addon), 0)
end

tests["sell grey: a kept item shows its reason, and an item no rule sells says so"] = function(t)
    local c, addon = boot({ bag = { { item = LETTER, count = 1 }, { item = SPOON, count = 1 } } })
    if type(c.kitWindows().SellList) ~= "table" then t.ok(false, "a kit window") return end
    c.setMerchantOpen(true)
    local win = c.kitWindows().SellList
    t.ok(shows(win, "itemLine", "Sealed Letter"), "the kept item")
    t.eq(noteOf(c, addon, "Sealed Letter"), "quest item", "with its reason")
    t.ok(shows(win, "itemLine", "Bent Spoon"), "the item no rule sells")
    t.eq(noteOf(c, addon, "Bent Spoon"), "no rule says to sell it")
    t.eq(grey(c), { item = nil, rule = "no grey item", why = nil }, "no grey item in the bags")
    t.eq(newProblems(addon), 0)
end

tests["sell grey: reservations not known - the grey item is a row that says so"] = function(t)
    local c, addon = boot()
    t.eq(noteOf(c, addon, "Cracked Bone", { status = addon.Reservations.UNAVAILABLE }), "reservations not known")
end

return tests
