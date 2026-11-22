local _, ns = ...

-- Tests for ZFlow/UI/BankList.lua (L6-D): the look-only list of what to bank,
-- shown while the bank window is open. Fake client; not tested in game.
-- Item facts come through client.itemInfo(item) (CLIENT NEED, as for the
-- sell list); until the fake has setItemInfo the read is put on it directly.

local L = ns.BankList
local tests = {}

local INFO = {
    [2589] = { name = "Linen Cloth", quality = 1, sellPrice = 13, classID = 7 },
    [858] = { name = "Lesser Healing Potion", quality = 1, sellPrice = 20, classID = 0 },
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

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.saved or {})
    if opts.bag ~= false then
        c.setBagItems(opts.bag or { { item = 2589, count = 20 }, { item = 858, count = 5 } })
    end
    setItemInfo(c, INFO)
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    if opts.setting ~= nil then
        k:Setting({ key = L.SETTING, scope = "char", type = "bool", default = true, label = "Bank list" })
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
        if type(p.spec) == "table" and p.spec.name == ns.id.framePrefix .. "BankList" then return p end
    end
    return nil
end

local function has(lines, text)
    for _, l in ipairs(lines or {}) do
        if l == text then return true end
    end
    return false
end

tests["bank list panel: started, and hidden until the bank opens"] = function(t)
    local k, c, api = start()
    t.eq((k:ModuleState(L.NAME)), "started")
    t.eq(panelOf(c).shown, false)
    t.eq(api.shows(), 0)
end

tests["bank list panel: the bank window shows what to bank"] = function(t)
    local _, c, api = start()
    c.setBankOpen(true)
    local p = panelOf(c)
    t.eq(p.shown, true)
    t.ok(has(p.lines, "20 x Linen Cloth: kept for later"), "trade goods to the bank")
    t.ok(not has(p.lines, "5 x Lesser Healing Potion: kept for later"), "the potion stays")
    t.eq(api.shows(), 1)
    c.setBankOpen(false)
    t.eq(p.shown, false, "hidden when the bank closes")
end

tests["bank list panel: bags not read say so"] = function(t)
    local _, c = start({ bag = false })
    c.setBankOpen(true)
    t.eq(panelOf(c).lines, { "Can't list what to bank: the bags have not been read yet" })
end

tests["bank list panel: without the item read it says so, not 'nothing to bank'"] = function(t)
    local _, c = start()
    c.itemInfo = nil
    if type(c.setItemInfo) == "function" then c.setItemInfo(nil) end
    c.setBankOpen(true)
    t.eq(panelOf(c).lines, { "Can't tell what to bank: 2 items were not read yet." })
end

tests["bank list panel: the player's carry choice is honoured"] = function(t)
    local _, c = start({ saved = { settings = { banker = { rules = { [2589] = "carry" } } } } })
    c.setBankOpen(true)
    t.ok(has(panelOf(c).lines, ns.ItemPresent.NOTHING_TO_BANK), "carried by choice")
end

tests["bank list panel: bank.list off shows nothing; on by default without a row"] = function(t)
    local _, c, api = start({ setting = false })
    c.setBankOpen(true)
    t.eq(panelOf(c).shown, false)
    t.eq(api.shows(), 0)
    t.eq(L.SETTING, "bank.list")
    local _, c2 = start()
    c2.setBankOpen(true)
    t.eq(panelOf(c2).shown, true, "no row yet: on")
end

tests["bank list panel: look only - only the bag and item reads, no acting names"] = function(t)
    local called = {}
    local only = {
        bagItems = function() called.bagItems = true return { { item = 2589, count = 1 } } end,
        itemInfo = function() called.itemInfo = true return { name = "Linen Cloth", classID = 7 } end,
    }
    local lines = L.Lines(setmetatable(only, { __index = function(_, name)
        called["other:" .. tostring(name)] = true
        return nil
    end }), nil)
    t.ok(#lines > 0, "a listing")
    t.eq(called, { bagItems = true, itemInfo = true })
    for name in pairs(L) do
        local n = tostring(name):lower()
        t.ok(not (n:find("deposit") or n:find("withdraw") or n:find("click")), "no acting function: " .. n)
    end
end

return tests
