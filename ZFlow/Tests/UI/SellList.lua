local _, ns = ...

-- Tests for ZFlow/UI/SellList.lua (L6-A): the look-only sell list shown
-- while a merchant window is open. Fake client; not tested in game.
--
-- The item facts come through client.itemInfo(item), a CLIENT NEED the lead
-- adds to Core/Client.lua and Core/ClientFake.lua. Until the fake has its
-- setter (setItemInfo), these tests put the read on the fake directly, in
-- the same shape.

local L = ns.SellList
local tests = {}

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
-- row declared), saved (account), char (character saved data), noFrames.
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
    local api = L.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    if opts.setting == false then k.settings:set(L.SETTING, false) end
    return k, c, api
end

local function panelOf(c)
    for _, p in ipairs(c.panels) do
        if type(p.spec) == "table" and p.spec.name == ns.id.framePrefix .. "SellList" then return p end
    end
    return nil
end

local function has(lines, text)
    for _, l in ipairs(lines or {}) do
        if l == text then return true end
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
    local reads = 0
    local bagItems = c.bagItems
    c.bagItems = function(...) reads = reads + 1 return bagItems(...) end
    c.setMerchantOpen(true)
    t.eq(panelOf(c).shown, false, "not shown")
    t.eq(reads, 0, "the bags were not read")
    t.eq(api.shows(), 0, "nothing listed")
    t.eq(L.SETTING, "vendor.list", "the settings row's name")
end

tests["sell list panel: the player's never-sell list is honoured and shown as kept"] = function(t)
    local _, c = start({ char = { settings = { sell = { never = { [97] = true } } } } })
    c.setMerchantOpen(true)
    local p = panelOf(c)
    t.ok(not has(p.lines, "3 x Broken Fang: 4c each, 12c (the item's own sell price)"), "not on the sell list")
    t.ok(has(p.lines, "Broken Fang: you bought it back, so it's never sold"), "listed as kept")
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
    local p = panelOf(c)
    for field in pairs(p.spec) do
        local f = tostring(field):lower()
        t.ok(not (f:find("button") or f:find("click") or f:find("secure")), "no acting field on the panel: " .. f)
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
    end }), nil)
    t.ok(type(lines) == "table" and #lines > 0, "a listing")
    t.eq(called, { bagItems = true, itemInfo = true }, "the bag read and the item read, nothing else")
    for name in pairs(L) do
        local n = tostring(name):lower()
        t.ok(not (n:find("^sell$") or n:find("buy") or n:find("click")), "no acting function: " .. n)
    end
end

return tests
