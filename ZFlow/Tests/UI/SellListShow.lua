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

return tests
