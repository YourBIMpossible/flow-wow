local _, ns = ...

-- Tests for ZFlow/Items/PriceLookup.lua (L6-H, G10): `<slash> price <item>`.
-- Prices per F-085: an observed price, else a labelled estimate, else
-- "price unknown—check vendor". It only reads and prints.

local L, P, Present = ns.PriceLookup, ns.Prices, ns.ItemPresent
local tests = {}
-- Item names carry the game's quality colour (Items/Present.lua, Tint; the
-- colour itself is tested in Tests/Items/ItemColourTests.lua). These tests are
-- about the words, so they read them with the colour taken off.
local plain = ns.ItemPresent.Plain

local INFO = {
    [97] = { name = "Broken Fang", quality = 0, sellPrice = 4 },
    [6948] = { name = "Hearthstone", quality = 1, sellPrice = 0 },
    [3000] = { name = "Grey Mystery", quality = 0 },
}

local function info(item)
    local i = INFO[ns.Items.Id(item) or 0]
    if not i then return nil end
    local out = {}
    for k, v in pairs(i) do out[k] = v end
    return out
end

-- ------------------------------------------------------------------ Find

tests["price: the item's own sell price is an observed price"] = function(t)
    local r = L.Find("item:97", info, {})
    t.eq(r.key, 97)
    t.eq(r.name, "Broken Fang")
    t.eq(r.sell, { unit = 4, basis = P.OBSERVED, source = ns.ItemSell.ITEM_SOURCE })
    t.eq(r.buy.basis, P.UNKNOWN, "no merchant seen selling it")
end

tests["price: a price in the book is used when the item gives none"] = function(t)
    local book = {}
    P.Record(book, 3000, ns.ItemSell.KIND, 30, { source = "merchant window", seenAt = 5 })
    t.eq(L.Find("3000", info, book).sell, { unit = 30, basis = P.OBSERVED, source = "merchant window" })
end

tests["price: an estimate is only an estimate, and needs its source"] = function(t)
    local book = {}
    P.Record(book, 3000, ns.ItemSell.KIND, 25, { basis = P.ESTIMATED, source = "Flow's import" })
    local r = L.Find("3000", info, book)
    t.eq(r.sell, { unit = 25, basis = P.ESTIMATED, source = "Flow's import" })
    local bare = {}
    P.Record(bare, 3000, ns.ItemSell.KIND, 25, { basis = P.ESTIMATED })
    t.eq(L.Find("3000", info, bare).sell.basis, P.UNKNOWN, "an estimate that names no source is not shown")
end

tests["price: nothing known stays unknown, never 0"] = function(t)
    local r = L.Find("4444", info, {})
    t.eq(r.sell, { unit = nil, basis = P.UNKNOWN, source = nil })
    t.eq(r.name, nil, "no name made up")
    t.eq(L.Find("4444", nil, nil).sell.basis, P.UNKNOWN, "no item read and no book: the same")
end

tests["price: an item the game says can't be sold"] = function(t)
    t.eq(L.Find("6948", info, {}).sell, { unsellable = true })
end

tests["price: what a merchant charges comes from the book's vendor prices"] = function(t)
    local book = {}
    P.Record(book, 97, ns.PriceObserve.KIND, 60, { source = "merchant window", seenAt = 9, per = 5 })
    local r = L.Find("97", info, book)
    t.eq(r.buy.unit, 60)
    t.eq(r.buy.basis, P.OBSERVED)
    t.eq(r.buy.per, 5)
end

tests["price: not an item"] = function(t)
    t.eq(L.Find("a fang", info, {}), nil)
    t.eq(L.Find("", info, {}), nil)
end

-- ------------------------------------------------------------------ words

tests["price words: observed, with where it is from"] = function(t)
    t.eq(Present.PriceLines(L.Find("97", info, {})),
        { "Broken Fang: a vendor pays 4c each (the item's own sell price)" })
end

tests["price words: an estimate is labelled"] = function(t)
    local book = {}
    P.Record(book, 3000, ns.ItemSell.KIND, 25, { basis = P.ESTIMATED, source = "Flow's import" })
    t.eq(Present.PriceLines(L.Find("3000", info, book)),
        { "Grey Mystery: a vendor pays about 25c each (estimate, Flow's import)" })
end

tests["price words: unknown is the F-085 fallback, with no figure"] = function(t)
    local lines = Present.PriceLines(L.Find("4444", info, {}))
    t.eq(lines, { "item 4444: price unknown—check vendor" })
    t.eq(Present.VENDOR_PRICE_UNKNOWN, "price unknown—check vendor")
end

tests["price words: can't be sold, and what a merchant charges"] = function(t)
    t.eq(Present.PriceLines(L.Find("6948", info, {})), { "Hearthstone: can't be sold to a merchant" })
    local book = {}
    P.Record(book, 97, ns.PriceObserve.KIND, 60, { source = "merchant window", per = 5 })
    t.eq(Present.PriceLines(L.Find("97", info, book)), {
        "Broken Fang: a vendor pays 4c each (the item's own sell price)",
        "A merchant sells it for 60c each, 5 at a time (merchant window)",
    })
end

-- ------------------------------------------------------------------ command

local function start(saved)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, saved or {})
    if type(c.setItemInfo) == "function" then c.setItemInfo(INFO) else c.itemInfo = info end
    local k = ns.Kernel({}, c)
    local diag = ns.Diag.Start(k)
    L.Start(k, diag)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    return k, c, diag
end

tests["price command: the word is added, and it prints with the title"] = function(t)
    local _, c, diag = start()
    t.eq(L.WORD, "price")
    diag.commands[L.WORD]("|cff9d9d9d|hitem:97:0:0:0:0:0:0:0|h[broken fang]|h|r")
    t.eq(c.printed[#c.printed], ns.id.title .. ": Broken Fang: a vendor pays 4c each (the item's own sell price)")
end

tests["price command: it reads the saved price book"] = function(t)
    local saved = { learned = { prices = { sell = { [3000] = { value = 30, basis = "observed", source = "merchant window" } } } } }
    local k = start(saved)
    t.eq(L.Run(k, "3000"), { "Grey Mystery: a vendor pays 30c each (merchant window)" })
end

tests["price command: no item says how to use it, and nothing is written"] = function(t)
    local k, c = start()
    t.eq(L.Run(k, ""), { L.USAGE })
    t.eq(L.Run(k, "fang"), { L.NotFound("fang") })
    local saved = c.saved(ns.id.accountDB)
    t.eq(type(saved.learned) == "table" and saved.learned.prices or nil, nil, "a lookup makes no price book")
end

-- E-42 (lead §674): an item by its name, through the client's name read.
tests["price command E-42: an item name is read through the client"] = function(t)
    local k = start()
    t.eq(L.Run(k, "broken fang"), { "Broken Fang: a vendor pays 4c each (the item's own sell price)" })
    t.eq(L.Run(k, "  Broken Fang "), { "Broken Fang: a vendor pays 4c each (the item's own sell price)" })
end

tests["price command E-42: an unknown name says so, with no price"] = function(t)
    local k = start()
    t.eq(L.Run(k, "no such thing"), { L.NotFound("no such thing") })
    t.eq(L.NotFound("fish"), 'No known item is called "fish": link it, or use its item ID.')
end

tests["price command E-42 nit (section 685): an id with no item info says has id"] = function(t)
    local k = start()
    k.client.itemInfo = function() return nil end
    t.eq(L.NoId("123"), "No known item has id 123: link it, or use its name.")
    -- An ID that is no item key (0) took the name path and said "called".
    t.eq(L.Run(k, "0"), { L.NoId("0") })
    -- A real ID with no info keeps the unknown-price line.
    t.eq(L.Run(k, "123"), { "item 123: price unknown—check vendor" })
end

tests["price command E-42: no name read in the client, a name is not found"] = function(t)
    local k = start()
    k.client.itemIdByName = nil
    t.eq(L.Run(k, "broken fang"), { L.NotFound("broken fang") })
end

tests["price command E-42: a name read that raises is not found"] = function(t)
    local k = start()
    k.client.itemIdByName = function() error("boom") end
    t.eq(L.Run(k, "broken fang"), { L.NotFound("broken fang") })
end

tests["price command E-42: the usage line names all three ways"] = function(t)
    t.eq(L.USAGE, "say price <item link>, an item name or an item ID.")
end

for name, fn in pairs(tests) do
    tests[name] = function(t)
        return fn(setmetatable({ eq = function(got, want, msg) return t.eq(plain(got), plain(want), msg) end },
            { __index = t }))
    end
end

return tests
