local _, ns = ...

-- Tests for the sell list's Show() (PROVIDER NEED of U-E, the window
-- buttons): ns.use("sellList").Show() lists the bags and shows the sell
-- list panel while a merchant window is open. Look only, as the list is.

local L = ns.SellList
local tests = {}

local INFO = { [97] = { name = "Broken Fang", quality = 0, sellPrice = 4 } }

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    if opts.noFrames then c.setFrames(false) end
    c.setBagItems({ { item = 97, count = 3 } })
    if type(c.setItemInfo) == "function" then
        c.setItemInfo(INFO)
    else
        c.itemInfo = function(item)
            local i = INFO[ns.Items.Id(item) or 0]
            if not i then return nil end
            return { name = i.name, quality = i.quality, sellPrice = i.sellPrice }
        end
    end
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    if opts.setting ~= nil then
        k:Setting({ key = L.SETTING, scope = "char", type = "bool", default = true, label = "Vendor sell list" })
    end
    local api = L.Declare(k)
    if not opts.noBoot then
        k:Boot()
        c.fire("ADDON_LOADED", ns.id.addon)
        c.fire("PLAYER_LOGIN")
        c.fire("PLAYER_ENTERING_WORLD")
    end
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

tests["sell list Show: the module provides it"] = function(t)
    local k = start()
    local provided = k.use(L.NAME)
    t.ok(type(provided) == "table" and type(provided.Show) == "function", "ns.use('sellList').Show is there")
    t.ok(type(provided.Last) == "function" and type(provided.Shows) == "function", "what it provided before is still there")
end

tests["sell list Show: at an open merchant it lists and shows the panel"] = function(t)
    local k, c, api = start({ setting = false })       -- vendor.list off: nothing shows by itself
    c.setMerchantOpen(true)
    local p = panelOf(c)
    t.eq(p.shown, false, "off: not shown on its own")
    local ok = k.use(L.NAME).Show()
    t.eq(ok, true)
    t.eq(p.shown, true, "asked for: shown, whatever the automatic setting says")
    t.ok(has(p.lines, "3 x Broken Fang: 4c each, 12c (the item's own sell price)"), "with the list")
    t.eq(api.shows(), 1)
    c.setMerchantOpen(false)
    t.eq(p.shown, false, "closing the merchant hides it as always")
end

tests["sell list Show: it lists again each time, with the bags as they are now"] = function(t)
    local k, c = start()
    c.setMerchantOpen(true)
    c.setBagItems({})
    t.eq(k.use(L.NAME).Show(), true)
    t.ok(has(panelOf(c).lines, ns.ItemPresent.NOTHING_TO_SELL), "the bags were read again")
end

-- Review of 8f5e861 (low): a list opened by the button stays open when the
-- never-sell list changes, also with vendor.list off.
tests["sell list Show: a list the player asked for survives a refresh, with vendor.list off"] = function(t)
    local k, c, api = start({ setting = false })
    c.setMerchantOpen(true)
    local p = panelOf(c)
    k.use(L.NAME).Show()
    t.eq(p.shown, true)
    c.setBagItems({})                      -- something changed (as after <slash> keep)
    api.refresh()
    t.eq(p.shown, true, "still shown: it was asked for")
    t.ok(has(p.lines, ns.ItemPresent.NOTHING_TO_SELL), "and listed again")
    t.eq(api.shows(), 2)
end

tests["sell list Show: the ask ends with the merchant window"] = function(t)
    local k, c, api = start({ setting = false })
    c.setMerchantOpen(true)
    k.use(L.NAME).Show()
    c.setMerchantOpen(false)
    c.setMerchantOpen(true)
    local p = panelOf(c)
    t.eq(p.shown, false, "a new merchant window: off again until asked")
    api.refresh()
    t.eq(p.shown, false, "and a refresh does not bring it back")
    t.eq(api.shows(), 1, "nothing was read for it")
end

tests["sell list Show: with no merchant window open it shows nothing and says why"] = function(t)
    local k, c, api = start()
    local ok, why = k.use(L.NAME).Show()
    t.eq(ok, false)
    t.eq(why, L.NO_MERCHANT)
    t.eq(panelOf(c).shown, false)
    t.eq(api.shows(), 0, "and the bags were not read")
    c.setMerchantOpen(true)
    c.setMerchantOpen(false)
    t.eq((k.use(L.NAME).Show()), false, "after it closed: the same")
end

tests["sell list Show: before the module has started, or with no panel, it answers false"] = function(t)
    local _, _, api = start({ noBoot = true })
    local ok, why = api.show()
    t.eq(ok, false)
    t.eq(why, L.NOT_STARTED)
    local k2, c2 = start({ noFrames = true })
    c2.setMerchantOpen(true)
    local ok2, why2 = k2.use(L.NAME).Show()
    t.eq(ok2, false)
    t.eq(why2, L.NO_PANEL, "a client that cannot draw: nothing to show")
end

tests["sell list Show: look only"] = function(t)
    local k, c = start()
    c.setMerchantOpen(true)
    local before = #c.printed
    k.use(L.NAME).Show()
    t.eq(#c.printed, before, "it prints nothing")
    for field in pairs(panelOf(c).spec) do
        local f = tostring(field):lower()
        t.ok(not (f:find("button") or f:find("click") or f:find("secure")), "no acting field on the panel: " .. f)
    end
end

-- Asked for by the U-E review: Show() only shows the panel. No sell, no
-- merchant call, no store write.
tests["sell list Show: it reads the bags and the item facts, draws, and does nothing else"] = function(t)
    local function deepCopy(v)
        if type(v) ~= "table" then return v end
        local out = {}
        for key, x in pairs(v) do out[key] = deepCopy(x) end
        return out
    end
    local k, c = start()
    c.setSaved(ns.id.charDB, { settings = { sell = { never = { [5] = true } } } })
    c.setMerchantOpen(true)
    local p = panelOf(c)

    -- Every call on the client from here on, by name.
    local called = {}
    for name, fn in pairs(c) do
        if type(fn) == "function" then
            c[name] = function(...)
                called[name] = (called[name] or 0) + 1
                return fn(...)
            end
        end
    end
    -- Every write to the store, and the saved data as it was.
    local writes = 0
    local set, tableOf = k.store.set, k.store.table
    k.store.set = function(...) writes = writes + 1 return set(...) end
    k.store.table = function(...) writes = writes + 1 return tableOf(...) end
    local accountWas, charWas = deepCopy(c.saved(ns.id.accountDB)), deepCopy(c.saved(ns.id.charDB))
    called = {}

    t.eq(k.use(L.NAME).Show(), true)

    k.store.set, k.store.table = set, tableOf
    local readsAllowed = { bagItems = true, itemInfo = true, saved = true }
    for name in pairs(called) do
        t.ok(readsAllowed[name], "Show() called client." .. name .. ", which is not one of its reads")
    end
    t.ok((called.bagItems or 0) >= 1, "it read the bags")
    t.eq(called.merchantItems, nil, "no merchant read")
    t.eq(called.raw, nil, "no raw game call")
    t.eq(called.print, nil, "nothing printed")
    t.eq(called.panel, nil, "no new frame: the one panel is reused")
    t.eq(writes, 0, "no store write")
    t.eq(c.saved(ns.id.accountDB), accountWas, "the account's saved data is as it was")
    t.eq(c.saved(ns.id.charDB), charWas, "and the character's")
    t.eq(p.shown, true, "and the panel is shown: that is all it does")
end

return tests
