local _, ns = ...

-- The Banker window (E-17, E-22, E-23, E-25; E-24 its fourth view): four
-- tabs over the bank list, the remembered bank contents, the take-out
-- rows and the auction prices. Fake client; the pure Children builder is
-- tested directly, the window through c.kitWindows(). The keep click's
-- data call (ItemKeep.Set) is a Lane Items NEED: the round-trip test
-- stands a fake one in its place (it writes the never list through the
-- store, as the real one will) and puts the real table back after; the
-- take-out list in that test is the real BankTakeOut.Make.
-- Look only: nothing here moves an item. Not tested in game.
--
-- Fails before the change: ns.BankerWindow is nil.

local W = ns.BankerWindow
local B = ns.Banker
local tests = {}

local CLOTH, POTION = 2589, 858
local INFO = {
    [9001] = { name = "Broken Fang", quality = 0, sellPrice = 5, classID = 0 },
    [CLOTH] = { name = "Linen Cloth", quality = 1, sellPrice = 13, classID = 7 },
    [POTION] = { name = "Lesser Healing Potion", quality = 1, sellPrice = 20, classID = 0 },
}

local function byKey(kids, key)
    for _, p in ipairs(kids or {}) do
        if p.key == key then return p end
        if type(p.children) == "table" then
            local hit = byKey(p.children, key)
            if hit then return hit end
        end
    end
    return nil
end

local function partOf(rec, key)
    for _, p in ipairs(type(rec) == "table" and rec.parts or {}) do
        if p.key == key then return p end
    end
    return nil
end

-- ------------------------------------------------------------- Children

tests["banker children: in your bank lists the contents under the last-visit line"] = function(t)
    local items = {
        { key = CLOTH, name = "Linen Cloth", count = 12, quality = 1 },
        { key = POTION, name = "Lesser Healing Potion", count = 3, quality = 1 },
    }
    local kids = W.Children(W.TAB_IN, { inItems = items, inHead = "Last visit: 2 hours ago", inLook = {} }, {})
    local tabs = byKey(kids, "tabs")
    t.eq(tabs and tabs.selected, W.TAB_IN)
    t.eq(tabs and tabs.items, W.TABS, "the four views, in order")
    t.eq(byKey(kids, "inHead").text, "Last visit: 2 hours ago")
    t.eq(byKey(kids, "in1").name, "Linen Cloth")
    t.eq(byKey(kids, "in1").count, 12)
    t.eq(byKey(kids, "in2").name, "Lesser Healing Potion")
    local none = W.Children(W.TAB_IN, {}, {})
    t.eq(byKey(none, "inLine").text, B.NOT_SEEN, "never seen: the data's own line")
    local many = { inItems = {}, inHead = "Last visit: your last visit", inLook = {} }
    for i = 1, B.MAX + 2 do many.inItems[i] = { key = 1000 + i, name = "Item " .. i, count = 1, quality = 0 } end
    local capped = W.Children(W.TAB_IN, many, {})
    t.eq(byKey(capped, "inMore").text, "and 2 more.", "past the cap, a count of the rest")
end

tests["banker children: to bank away from the bank is one line"] = function(t)
    local kids = W.Children(W.TAB_BANK, { atBank = false }, {})
    t.eq(byKey(kids, "away").text, W.AWAY_LINE)
end

tests["banker children: to sell groups its rows, kept rows at the bottom, clicks wired"] = function(t)
    local sellRow = { key = 9001, name = "Broken Fang", count = 7, quality = 0, reason = "the sell rules would sell it" }
    local keptRow = { key = 9002, name = "Bent Sword", count = 1, quality = 0, reason = "the sell rules would sell it" }
    local clicked = {}
    local acts = {
        keep = function(r) clicked.keep = r end,
        unkeep = function(r) clicked.unkeep = r end,
    }
    local kids = W.Children(W.TAB_SELL, {
        sellGroups = { { header = B.SELL_HEADER, rows = { sellRow } } },
        sellKept = { keptRow }, sellLook = {},
    }, acts)
    local sell = byKey(kids, "sell1")
    t.eq(sell and sell.kind, "line", "a row the player can click (the kit's item line cannot be)")
    t.eq(sell and sell.text, "Broken Fang x7")
    t.eq(sell and sell.sub, "the sell rules would sell it", "the reason underneath")
    sell.onClick()
    t.eq(clicked.keep, sellRow, "clicking keeps the item")
    local kept = byKey(kids, "kept1")
    t.eq(kept and kept.text, "Bent Sword")
    t.eq(kept and kept.sub, W.KEPT_NOTE)
    kept.onClick()
    t.eq(clicked.unkeep, keptRow, "clicking a kept row puts it back")
    local unknown = W.Children(W.TAB_SELL, { sellLine = B.SELL_UNKNOWN }, {})
    t.eq(byKey(unknown, "sellLine").text, B.SELL_UNKNOWN, "reservations unknown: nothing is offered")
    local empty = W.Children(W.TAB_SELL, { sellGroups = {}, sellKept = {} }, {})
    t.eq(byKey(empty, "sellLine").text, B.NOTHING_TO_SELL)
end

tests["banker children: only a sell row clicks to keep (CHANGES-1 a)"] = function(t)
    local routeRow = { key = 9003, name = "Dreamfoil", count = 2, quality = 1, take = "route", reason = "for a route step" }
    local sellRow = { key = 9001, name = "Broken Fang", count = 7, quality = 0, take = "sell", reason = "the sell rules would sell it" }
    local plainRow = { key = 9004, name = "Old Boot", count = 1, quality = 0, reason = "the sell rules would sell it" }
    local clicked = {}
    local acts = { keep = function(r) clicked[#clicked + 1] = r end }
    local kids = W.Children(W.TAB_SELL, {
        sellGroups = {
            { header = B.ROUTE_HEADER, rows = { routeRow } },
            { header = B.SELL_HEADER, rows = { sellRow, plainRow } },
        },
        sellKept = {}, sellLook = {},
    }, acts)
    local route = byKey(kids, "sell1")
    t.eq(route and route.text, "Dreamfoil x2")
    t.eq(route and route.onClick, nil, "a route row has no click: keeping it means nothing")
    local sell = byKey(kids, "sell2")
    t.ok(sell and type(sell.onClick) == "function", "a sell row clicks")
    sell.onClick()
    t.eq(clicked[1], sellRow)
    local plain = byKey(kids, "sell3")
    t.ok(plain and type(plain.onClick) == "function", "a row with no take clicks too (it reads as sell)")
end

tests["banker children: auction prices show the buyout and when it was seen"] = function(t)
    local rows = { { id = CLOTH, name = "Linen Cloth", price = 30, at = 900 } }
    local kids = W.Children(W.TAB_PRICES, {
        priceRows = rows, priceHead = ns.PriceList.Header(1, 1, ""), priceNow = 1000, search = "",
    }, {})
    t.eq(byKey(kids, "priceHead").text, ns.PriceList.ALL:format(1))
    local row = byKey(kids, "price1")
    t.eq(row and row.text, "Linen Cloth")
    t.eq(row and row.right, ns.Prices.Coin(30), "the cheapest buyout, as coin")
    t.eq(row and row.sub, "seen " .. ns.PriceChart.Span(100) .. " ago")
    local header = byKey(kids, "header")
    t.ok(header and type(header.search) == "table", "the prices view carries the search box")
    local footer
    for _, p in ipairs(kids) do if p.kind == "footer" then footer = p end end
    t.eq(footer and footer.text, W.PRICES_FOOTER)
end

-- -------------------------------------------------------------- window

local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setClock(opts.now or 1000)
    c.setItemInfo(INFO)
    c.setBagItems(opts.bag or {})
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    ns.Reservations.Declare(k)
    local diag = { commands = {}, help = {} }
    ns.Banker.Declare(k, diag)
    local api = W.Declare(k, diag)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api, diag
end

local BANKED = { learned = { bankCounts = { at = 900, counts = { [CLOTH] = 12, [POTION] = 3 } } } }

tests["banker window: away from the bank it opens on in your bank"] = function(t)
    local _, c, api = boot({ char = BANKED })
    t.eq(api.show(), true)
    local rec = c.kitWindows()[W.ID]
    t.ok(rec and rec.shown, "the window is drawn and shown")
    local head = partOf(rec, "inHead")
    t.ok(head and head.text:sub(1, 12) == "Last visit: ", "the last-visit line: " .. tostring(head and head.text))
    t.ok(partOf(rec, "in1") ~= nil, "the remembered contents are listed")
end

tests["banker window: at the bank it opens on to bank, with the bank list"] = function(t)
    local _, c, api = boot({ char = BANKED })
    c.setBankOpen(true)
    t.eq(api.show(), true)
    local rec = c.kitWindows()[W.ID]
    t.eq(partOf(rec, "away"), nil, "not the away line")
    local found = false
    for _, p in ipairs(rec.parts) do if p.text == B.NOTHING or p.text == "Nothing to bank." then found = true end end
    t.ok(found, "the bank list itself renders (nothing to bank, on an empty bag)")
end

tests["banker window: the banker word prints its lists and opens the window"] = function(t)
    local _, c, _, diag = boot({ char = BANKED })
    t.eq(type(diag.commands[B.WORD]), "function")
    diag.commands[B.WORD]()
    local rec = c.kitWindows()[W.ID]
    t.ok(rec and rec.shown, "the word opens the window")
    t.ok(#c.printed > 0, "and the lists still print")
end

tests["banker window: the keep click round-trips through the data's call"] = function(t)
    -- The real BankTakeOut.Make over a bank holding grey junk; only the
    -- keep call is stood in for, writing the never list through the
    -- store as the real ItemKeep.Set will (CHANGES-1 b).
    local realSet = ns.ItemKeep.Set
    local calls = {}
    ns.ItemKeep.Set = function(k, key, on)
        calls[#calls + 1] = { key = key, on = on }
        local set = k.store:get("char", ns.SellList.NEVER_PATH)
        if type(set) ~= "table" then set = {} end
        if on then set[key] = true else set[key] = nil end
        k.store:set("char", ns.SellList.NEVER_PATH, set)
        return true
    end
    local char = { learned = { bankCounts = { at = 900, counts = { [9001] = 7, [CLOTH] = 12 } } } }
    local _, c, api = boot({ char = char })
    local ok, err = pcall(function()
        t.eq(api.show(W.TAB_SELL), true)
        local function findRow(prefix)
            for _, p in ipairs(c.kitWindows()[W.ID].parts) do
                if p.text == "Broken Fang x7" and p.key:sub(1, #prefix) == prefix then return p end
            end
            return nil
        end
        local row = findRow("sell")
        t.ok(row ~= nil, "the real Make offers the junk under To sell")
        t.eq(c.kitClick(W.ID, row.key), true, "the row clicks")
        t.eq(calls, { { key = 9001, on = true } }, "the click asks the data to keep it")
        t.eq(findRow("sell"), nil, "and the real Make no longer offers it")
        local kept = findRow("kept")
        t.ok(kept ~= nil, "it shows under Kept, built from the bank's own items")
        t.eq(c.kitClick(W.ID, kept.key), true)
        t.eq(calls[2], { key = 9001, on = false }, "clicking there asks to put it back")
        t.ok(findRow("sell") ~= nil, "and the row is offered again")
        t.eq(findRow("kept"), nil, "and Kept is empty again")
    end)
    ns.ItemKeep.Set = realSet
    if not ok then error(err) end
end

tests["banker window: without the data's keep call, a click changes nothing"] = function(t)
    local realMake, realSet = ns.BankTakeOut.Make, ns.ItemKeep.Set
    ns.BankTakeOut.Make = function()
        return { rows = { { key = 9001, name = "Broken Fang", count = 7, quality = 0,
            reason = "the sell rules would sell it", take = "sell" } } }
    end
    ns.ItemKeep.Set = nil
    local _, c, api = boot({ char = BANKED })
    local ok, err = pcall(function()
        t.eq(api.show(W.TAB_SELL), true)
        t.eq(c.kitClick(W.ID, "sell1"), true, "the row still clicks")
        t.ok(partOf(c.kitWindows()[W.ID], "sell1") ~= nil, "but the row stays (the list keeps its one writer)")
    end)
    ns.BankTakeOut.Make, ns.ItemKeep.Set = realMake, realSet
    if not ok then error(err) end
end

return tests
