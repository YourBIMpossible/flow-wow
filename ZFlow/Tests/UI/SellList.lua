local _, ns = ...

-- Tests for ZFlow/UI/SellList.lua (L6-A): the look-only sell list shown
-- while a merchant window is open. Fake client; not tested in game.
-- Since lead section 303 the list is a kit window (Tests/UI/SellListKit.lua
-- has what it draws); these read whether it is shown and its text lines.
--
-- The item facts come through client.itemInfo(item), a CLIENT NEED the lead
-- adds to Core/Client.lua and Core/ClientFake.lua. Until the fake has its
-- setter (setItemInfo), these tests put the read on the fake directly, in
-- the same shape.

local L = ns.SellList
local tests = {}
-- Item names carry the game's quality colour (Items/Present.lua, Tint; the
-- colour itself is tested in Tests/Items/ItemColourTests.lua). These tests are
-- about the words, so they read them with the colour taken off.
local plain = ns.ItemPresent.Plain

local INFO = {
    [97] = { name = "Broken Fang", quality = 0, sellPrice = 4 },
    [6948] = { name = "Hearthstone", quality = 1, sellPrice = 0 },
    [2318] = { name = "Light Leather", quality = 1, sellPrice = 15, classID = 7 },
}

local function setItemInfo(c, map)
    if type(c.setItemInfo) == "function" then return c.setItemInfo(map) end
    c.itemInfo = function(item)
        local id = ns.Items.Id(item)
        local i = id and map[id]
        if not i then return nil end
        local out = {}
        for k, v in pairs(i) do out[k] = v end
        return out
    end
end

-- opts: bag (stacks, or false for unread), setting (true / false / nil: no
-- row declared), saved (account), char (character saved data), noFrames,
-- noReservations (the kernel has no reservations module).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.saved or {})
    if opts.char then c.setSaved(ns.id.charDB, opts.char) end
    if opts.noFrames then c.setFrames(false) end
    if opts.bag ~= false then
        c.setBagItems(opts.bag or { { item = 97, count = 3 }, { item = 6948, count = 1 } })
    end
    setItemInfo(c, INFO)
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    if opts.setting ~= nil then
        k:Setting({ key = L.SETTING, scope = "char", type = "bool", default = true, label = "Vendor sell list" })
    end
    if not opts.noReservations then ns.Reservations.Declare(k) end
    local api = L.Declare(k)
    c.lists = { SellList = api }
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    if opts.setting == false then k.settings:set(L.SETTING, false) end
    return k, c, api
end

-- The list as the player has it since it moved to the window kit (lead
-- section 303): whether its kit window is shown, and the text lines of the
-- last listing (what the text panel shows on a client that cannot draw the
-- kit). Read each time it is asked, as a panel's own fields were.
local function panelOf(c)
    local id = "SellList"
    if type(c.kitWindows()[id]) ~= "table" then return nil end
    return setmetatable({}, { __index = function(_, field)
        if field == "shown" then return c.kitWindows()[id].shown end
        if field == "lines" then return c.lists[id].last() or {} end
        return nil
    end })
end

local function has(lines, text)
    for _, l in ipairs(lines or {}) do
        if plain(l) == text then return true end
    end
    return false
end

tests["sell list panel: declared, started, and hidden until a merchant opens"] = function(t)
    local k, c, api = start()
    t.eq((k:ModuleState(L.NAME)), "started")
    local p = panelOf(c)
    t.ok(p ~= nil, "the panel is made")
    t.eq(p.shown, false, "hidden with no merchant")
    t.eq(api.shows(), 0, "nothing listed yet")
    t.ok(type(ns.sellList) == "table", "the addon's own is declared")
end

tests["sell list panel: a merchant window shows what would be sold, and what is kept"] = function(t)
    local _, c, api = start()
    c.setMerchantOpen(true)
    local p = panelOf(c)
    t.eq(p.shown, true, "shown")
    t.ok(has(p.lines, "3 x Broken Fang: 4c each, 12c (the item's own sell price)"), "the junk, priced")
    t.ok(has(p.lines, "Hearthstone: can't be sold to a merchant"), "the kept item, with its reason")
    t.eq(api.shows(), 1, "one listing")
    t.eq(api.last(), p.lines, "the last lines are kept")
end

tests["sell list panel: closing the merchant hides it"] = function(t)
    local _, c = start()
    c.setMerchantOpen(true)
    c.setMerchantOpen(false)
    t.eq(panelOf(c).shown, false, "hidden again")
end

tests["sell list panel: each opening reads the bags again"] = function(t)
    local _, c, api = start()
    c.setMerchantOpen(true)
    c.setMerchantOpen(false)
    c.setBagItems({ { item = 2318, count = 1 } })
    c.setMerchantOpen(true)
    local p = panelOf(c)
    t.ok(has(p.lines, ns.ItemPresent.NOTHING_TO_SELL), "the new bag has nothing to sell")
    t.eq(api.shows(), 2, "two listings")
end

tests["sell list panel: bags not read say so and show no figures"] = function(t)
    local _, c = start({ bag = false })
    c.setMerchantOpen(true)
    t.eq(panelOf(c).lines, { "Can't list what to sell: " .. ns.ItemSell.BAGS_UNREAD }, "one line, no figure")
end

tests["sell list panel: on by default, also before the lead's settings row exists"] = function(t)
    local _, c = start({ setting = true })
    c.setMerchantOpen(true)
    t.eq(panelOf(c).shown, true, "row declared, default on: shown")
    local _, c2 = start()
    c2.setMerchantOpen(true)
    t.eq(panelOf(c2).shown, true, "no row yet: shown")
end

tests["sell list panel: vendor.list off shows nothing and reads nothing"] = function(t)
    local _, c, api = start({ setting = false })
    -- Count the list's own read only: Diag's merchant snapshot also reads
    -- the bags at MERCHANT_SHOW, and that is not this module (lead, L6-A merge).
    local reads = 0
    local lines = L.Lines
    L.Lines = function(...) reads = reads + 1 return lines(...) end
    c.setMerchantOpen(true)
    t.eq(panelOf(c).shown, false, "not shown")
    t.eq(reads, 0, "the bags were not read")
    t.eq(api.shows(), 0, "nothing listed")
    L.Lines = lines
    t.eq(L.SETTING, "vendor.list", "the settings row's name")
end

tests["sell list panel: the player's never-sell list is honoured and shown as kept"] = function(t)
    local _, c = start({ char = { settings = { sell = { never = { [97] = true } } } } })
    c.setMerchantOpen(true)
    local p = panelOf(c)
    t.ok(not has(p.lines, "3 x Broken Fang: 4c each, 12c (the item's own sell price)"), "not on the sell list")
    t.ok(has(p.lines, "Broken Fang: on your never-sell list"), "listed as kept")
end

tests["sell list panel: a client that cannot draw leaves nothing to do"] = function(t)
    local k, c, api = start({ noFrames = true })
    t.eq((k:ModuleState(L.NAME)), "started", "still started")
    c.setMerchantOpen(true)
    t.eq(#c.panels, 0, "no panel")
    t.eq(api.shows(), 1, "the list is still worked out")
end

tests["sell list panel: look only - no buttons, no clicks, only the two reads"] = function(t)
    local _, c = start()
    c.setMerchantOpen(true)
    -- Nothing drawn can be pressed: no button part, and no part with a
    -- click of its own.
    local parts = c.kitWindows().SellList.parts
    t.ok(#parts > 0, "the window has parts")
    -- But one: the Sell these button (lead section 337 item 1), whose
    -- click is tested in Tests/E2E/SellThese.lua.
    for _, part in ipairs(parts) do
        if part.key ~= ns.SellThese.KEY then
            t.ok(part.kind ~= "button" and part.kind ~= "bind" and part.kind ~= "checkbox",
                "no acting part in the window: " .. part.kind)
            t.eq(c.kitClick("SellList", part.path), false, "nothing happens on a click: " .. part.kind)
        end
    end
    -- A listing over a client that has only the two reads: anything else it
    -- touched would be nil and raise. (Diag's own window snapshot is not
    -- this module's and is left out by calling Lines directly.)
    local called = {}
    local only = {
        bagItems = function() called.bagItems = true return { { item = 97, count = 1 } } end,
        itemInfo = function(item) called.itemInfo = true return { name = "Broken Fang", quality = 0, sellPrice = 4 } end,
    }
    local lines = L.Lines(setmetatable(only, { __index = function(_, name)
        called["other:" .. tostring(name)] = true
        return nil
    end }), nil, nil, { status = ns.Reservations.NONE })
    t.ok(type(lines) == "table" and #lines > 0, "a listing")
    -- Plus the skill rank read for the skill boosters (lead section 337 item 2).
    -- Plus the professions read for the materials kept for a profession.
    t.eq(called, { bagItems = true, itemInfo = true, ["other:skillRanks"] = true, ["other:professions"] = true },
        "the bag read, the item read, the skill rank read and the professions read, nothing else")
    for name in pairs(L) do
        local n = tostring(name):lower()
        t.ok(not (n:find("^sell$") or n:find("buy") or n:find("click")), "no acting function: " .. n)
    end
end

tests["sell list panel: no reservations module is unavailable: nothing offered, and it says so"] = function(t)
    local _, c, api = start({ noReservations = true })
    c.setMerchantOpen(true)
    local lines = api.last() or {}
    t.eq(lines[1], L.RESERVATIONS_UNKNOWN, "the first line says it")
    t.ok(not has(lines, ns.ItemPresent.SELL_HEADER), "no sell advice")
    t.ok(not has(lines, "3 x Broken Fang: 4c each, 12c (the item's own sell price)"), "nothing offered")
    t.ok(has(lines, "Hearthstone: can't be sold to a merchant"), "what is kept is still said")
end

tests["sell list lines: bags not read says only that, even when unavailable"] = function(t)
    local c = ns.make.fakeClient()
    local lines = L.Lines(c, nil, nil, { status = ns.Reservations.UNAVAILABLE })
    t.eq(lines, { "Can't list what to sell: " .. ns.ItemSell.BAGS_UNREAD })
end

tests["sell list lines: none changes nothing"] = function(t)
    local c = ns.make.fakeClient()
    c.setBagItems({ { item = 97, count = 3 } })
    setItemInfo(c, INFO)
    local r = { status = ns.Reservations.NONE }
    -- Lead section 226: a missing evaluation is unavailable (SR-3), so the
    -- plain list is the one made with an explicit none on both sides.
    t.eq(L.Lines(c, nil, L.Held(r), r), L.Lines(c, nil, nil, r))
end

for name, fn in pairs(tests) do
    tests[name] = function(t)
        return fn(setmetatable({ eq = function(got, want, msg) return t.eq(plain(got), plain(want), msg) end },
            { __index = t }))
    end
end

return tests
