local _, ns = ...
-- The inventory word (parity row E-27), end to end, on the whole add-on
-- loaded on a fake client: the player types the word away from any
-- merchant and a kit window lists every item in the bags with what the
-- sell rules say of it (sell or keep) and why, the sell rows first, under
-- a header that counts them. An item the game has not read is "not read
-- yet", never a verdict; bags that were not read say so; reservations that
-- cannot be worked out say so and offer nothing for sale. Look only:
-- nothing is sold and the window has no button. Made-up items. Not tested
-- in game.
--
-- Fails before the change: the slash command has no such word, so no
-- window with the id InventoryList is made and addon.inventoryList is nil.
local tests = {}

local plain = ns.ItemPresent.Plain

local FANG, SCRAP, STONE, CLOTH, FOG = 97, 2934, 6948, 2589, 3306
local INFO = {
    [FANG] = { name = "Broken Fang", quality = 0, sellPrice = 4 },
    [SCRAP] = { name = "Ruined Leather Scraps", quality = 0, sellPrice = 1 },
    [STONE] = { name = "Hearthstone", quality = 1, sellPrice = 0 },
    [CLOTH] = { name = "Linen Cloth", quality = 1, sellPrice = 13, classID = 7 },
    -- FOG has no facts: the game has not read it yet.
}
-- The kept ones first in the bags, so the order of the window is its own.
local BAG = {
    { bag = 0, slot = 1, item = STONE, count = 1 },
    { bag = 0, slot = 2, item = FANG, count = 3 },
    { bag = 0, slot = 3, item = CLOTH, count = 20 },
    { bag = 0, slot = 4, item = FANG, count = 2 },
    { bag = 1, slot = 1, item = SCRAP, count = 1 },
}
local ID = "InventoryList"

-- opts: bag (stacks; false: the bags are never set, so not read), source
-- (a test-only reservations source). No merchant window anywhere.
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    if opts.bag ~= false then c.setBagItems(opts.bag or BAG) end
    c.setItemInfo(INFO)
    local addon = ns.offline.addon(c)
    if opts.source then addon.Reservations.Source("test", opts.source) end
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon, addon.problems:count()
end

local function ask(c)
    c.slashes[ns.id.slash]("inventory")
    c.advance(1, 5)
    return c.kitWindows()[ID]
end

-- The parts of that kind, in the order drawn.
local function parts(win, kind)
    local out = {}
    for _, p in ipairs(type(win) == "table" and win.parts or {}) do
        if p.kind == kind then out[#out + 1] = p end
    end
    return out
end

local function texts(win, kind)
    local out = {}
    for i, p in ipairs(parts(win, kind)) do out[i] = tostring(p.text) end
    return out
end

-- The note of the item line with that name, or nil.
local function noteOf(win, name)
    for _, p in ipairs(parts(win, "itemLine")) do
        if p.text == name then return p.note end
    end
    return nil
end

local function has(lines, text)
    for _, line in ipairs(type(lines) == "table" and lines or {}) do
        if plain(tostring(line)) == text then return true end
    end
    return false
end

local function joined(lines)
    local out = {}
    for i, line in ipairs(type(lines) == "table" and lines or {}) do out[i] = plain(tostring(line)) end
    return table.concat(out, " | ")
end

local function sold(c)
    return type(c.soldSlots) == "table" and #c.soldSlots or -1
end

tests["inventory list: the word lists every bag item with its verdict and why, away from a merchant"] = function(t)
    local c, addon, before = boot()
    t.eq(c.kitWindows()[ID], nil, "no window before it is asked for")
    local win = ask(c)
    t.ok(type(win) == "table", "the word makes a kit window")
    if type(win) ~= "table" then return end
    t.eq(win.shown, true, "shown with no merchant window open")
    t.eq(win.title, ns.id.title .. ": Inventory")
    t.eq(#parts(win, "itemLine"), 4, "one line per item: two stacks of one item are one line")
    t.eq(noteOf(win, "Broken Fang"), "sell: junk")
    t.eq(noteOf(win, "Ruined Leather Scraps"), "sell: junk")
    local stone = tostring(noteOf(win, "Hearthstone"))
    t.eq(stone:sub(1, 33), "keep: can't be sold to a merchant", stone)
    local cloth = tostring(noteOf(win, "Linen Cloth"))
    t.eq(cloth:sub(1, 6), "keep: ", cloth)
    t.ok(#cloth > 6, "a kept item says why: " .. cloth)
    -- The counts are on the lines as text too (what a client that cannot
    -- draw the kit prints).
    local lines = addon.inventoryList.last()
    t.ok(has(lines, "sell: 5 x Broken Fang (junk)"), joined(lines))
    t.ok(has(lines, "sell: 1 x Ruined Leather Scraps (junk)"), joined(lines))
    t.ok(joined(lines):find("keep: 1 x Hearthstone (can't be sold to a merchant", 1, true) ~= nil, joined(lines))
    t.ok(joined(lines):find("keep: 20 x Linen Cloth (", 1, true) ~= nil, joined(lines))
    t.eq(addon.problems:count() - before, 0)
end

tests["inventory list: the sell rows come first, and the header counts both"] = function(t)
    local c, addon, before = boot()
    local win = ask(c)
    if type(win) ~= "table" then t.ok(false, "a kit window") return end
    t.eq(texts(win, "header"), { "2 to sell, 2 to keep" })
    local names = texts(win, "itemLine")
    t.eq({ names[1], names[2] }, { "Broken Fang", "Ruined Leather Scraps" }, "sell first, in bag order")
    local rest = { tostring(names[3]), tostring(names[4]) }
    table.sort(rest)
    t.eq(rest, { "Hearthstone", "Linen Cloth" }, "then what is kept")
    t.eq(texts(win, "section"), { "To sell", "To keep" })
    t.eq(plain(tostring((addon.inventoryList.last() or {})[1])), "Inventory: 2 to sell, 2 to keep")
    t.eq(addon.problems:count() - before, 0)
end

tests["inventory list: an item the game has not read is not read yet, never a verdict"] = function(t)
    local c, addon, before = boot({ bag = {
        { item = FANG, count = 3 }, { item = FOG, count = 2 }, { item = STONE, count = 1 },
    } })
    local win = ask(c)
    if type(win) ~= "table" then t.ok(false, "a kit window") return end
    t.eq(texts(win, "header"), { "1 to sell, 1 to keep, 1 not read yet" })
    t.eq(noteOf(win, "item " .. tostring(FOG)), "not read yet")
    local names = texts(win, "itemLine")
    t.eq(names[#names], "item " .. tostring(FOG), "after the verdicts")
    t.ok(has(addon.inventoryList.last(), "not read yet: 2 x item " .. tostring(FOG)),
        joined(addon.inventoryList.last()))
    t.eq(addon.problems:count() - before, 0)
end

tests["inventory list: bags that were not read say so, not that there is nothing"] = function(t)
    local c, addon, before = boot({ bag = false })
    local win = ask(c)
    if type(win) ~= "table" then t.ok(false, "a kit window") return end
    t.eq(win.shown, true)
    t.eq(texts(win, "header"), { "Bags not read yet" })
    t.eq(texts(win, "empty"), { "Your bags have not been read yet." })
    t.eq(#parts(win, "itemLine"), 0)
    t.ok(not joined(addon.inventoryList.last()):find("to sell", 1, true), joined(addon.inventoryList.last()))
    t.eq(addon.problems:count() - before, 0)
end

tests["inventory list: empty bags say no items were found"] = function(t)
    local c, addon, before = boot({ bag = {} })
    local win = ask(c)
    if type(win) ~= "table" then t.ok(false, "a kit window") return end
    t.eq(texts(win, "header"), { "No items" })
    t.eq(texts(win, "empty"), { "No items were found in your bags." })
    t.eq(addon.problems:count() - before, 0)
end

tests["inventory list: reservations not known says so and gives no sell verdict"] = function(t)
    local c, addon, before = boot({ source = function() error("goals could not be read") end })
    local win = ask(c)
    if type(win) ~= "table" then t.ok(false, "a kit window") return end
    t.eq(texts(win, "header"), { addon.SellList.UNKNOWN_HEAD })
    t.eq(#parts(win, "itemLine"), 4, "every item is still listed")
    t.eq(noteOf(win, "Broken Fang"), "not known yet: " .. addon.SellList.WHY_RESERVATIONS)
    for _, p in ipairs(parts(win, "itemLine")) do
        t.ok(tostring(p.note):sub(1, 5) ~= "sell:", "no sell verdict: " .. tostring(p.text))
    end
    t.ok(has(addon.inventoryList.last(), "Inventory: " .. addon.SellList.RESERVATIONS_UNKNOWN),
        joined(addon.inventoryList.last()))
    t.eq(addon.problems:count() - before, 0)
end

tests["inventory list: look only: nothing is sold and the window has no button"] = function(t)
    local c, addon, before = boot()
    local win = ask(c)
    if type(win) ~= "table" then t.ok(false, "a kit window") return end
    c.advance(2, 40)
    t.eq(sold(c), 0, "nothing sold by asking")
    t.eq(#parts(win, "button"), 0, "no button")
    t.eq(#parts(win, "footer"), 0, "no footer for another lane's button either")
    t.eq(c.kitClick(ID, ns.SellThese.KEY), false, "no sell button to press")
    c.advance(2, 40)
    t.eq(sold(c), 0, "and nothing sold after")
    t.eq(addon.problems:count() - before, 0)
end

tests["inventory list: the window follows the bags while it is shown"] = function(t)
    local c, addon, before = boot()
    if type(ask(c)) ~= "table" then t.ok(false, "a kit window") return end
    c.setBagItems({ { bag = 0, slot = 1, item = STONE, count = 1 } })
    c.fire(addon.SellList.BAG_EVENT)
    c.advance(1, 5)
    t.eq(texts(c.kitWindows()[ID], "header"), { "0 to sell, 1 to keep" })
    t.eq(addon.problems:count() - before, 0)
end

tests["inventory list: a client that cannot draw the window gets the same lines in chat"] = function(t)
    local c, addon, before = boot()
    c.setKitFails(1)
    local from = #c.printed
    c.slashes[ns.id.slash]("inventory")
    local said = {}
    for i = from + 1, #c.printed do said[#said + 1] = c.printed[i] end
    t.ok(has(said, ns.id.title .. ": Inventory: 2 to sell, 2 to keep"), joined(said))
    t.ok(has(said, ns.id.title .. ": sell: 5 x Broken Fang (junk)"), joined(said))
    t.eq(sold(c), 0)
    t.eq(addon.problems:count() - before, 0)
end

return tests
