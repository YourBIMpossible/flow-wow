-- S5 have-count on item tooltips (Items/HaveTip.lua, the module that shows
-- Items/TooltipHave.lua's line). Fake client only.
local _, ns = ...

local H = ns.HaveTip
local tests = {}
local BLUE = { 0.6, 0.85, 1 }

local function key(item) return ns.Items.Key(item) end

tests["have tip: stacks summed by item, unknown stays unknown"] = function(t)
    t.eq(H.Counts({ { item = 2318, count = 5 }, { item = "item:2318", count = 3 }, { item = 2589, count = 1 } }, key),
        { [2318] = 8, [2589] = 1 })
    t.eq(H.Counts({}, key), {})
    t.eq(H.Counts({ { item = "not an item", count = 1 } }, key), nil, "a stack with no key: no count at all")
    t.eq(H.Counts({ { item = 2318, count = 1.5 } }, key), nil)
    t.eq(H.Counts(nil, key), nil)
end

tests["have tip: the snapshot says whether the bank was seen"] = function(t)
    t.eq(H.Snapshot({ [1] = 2 }, nil), { bags = { [1] = 2 }, bankKnown = false })
    t.eq(H.Snapshot(nil, { at = 5, counts = { [1] = 3 } }), { bank = { [1] = 3 }, bankKnown = true })
end

local function start()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setClock(5000)
    c.setBagItems({ { item = 2318, count = 12 } })
    local k = ns.Kernel({}, c)
    local api = H.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api
end

local function texts(lines)
    local out = {}
    for i, l in ipairs(lines) do out[i] = l.text end
    return out
end

tests["have tip module: bags only, before the bank is seen"] = function(t)
    local _, c, api = start()
    t.eq(api.hooked(), true)
    local lines = c.showItemTooltip("item:2318")
    t.eq(texts(lines), { "You have 12 in bags (bank not seen yet)" })
    t.eq({ lines[1].r, lines[1].g, lines[1].b }, BLUE)
end

tests["have tip module: a bank visit is kept for later"] = function(t)
    local k, c, api = start()
    c.setBank({ { item = 2318, count = 40 } })
    c.setBankOpen(true)
    t.eq(api.bankReads(), 1)
    t.eq(k.store:get("char", H.PATH), { at = 5000, counts = { [2318] = 40 } })
    c.setBankOpen(false)
    c.setBank({})
    t.eq(texts(c.showItemTooltip("item:2318")),
        { "You have 52: 12 in bags, 40 in the bank (as of your last bank visit)" })
    t.eq(texts(c.showItemTooltip("item:999")), {}, "none anywhere: no line")
end

tests["have tip module: the bags are read again a second later, or when they change"] = function(t)
    local _, c = start()
    c.showItemTooltip("item:2318")
    c.setBagItems({ { item = 2318, count = 20 } })
    t.eq(texts(c.showItemTooltip("item:2318")), { "You have 12 in bags (bank not seen yet)" }, "within the second")
    c.advance(1)
    t.eq(texts(c.showItemTooltip("item:2318")), { "You have 20 in bags (bank not seen yet)" })
    c.setBagItems({ { item = 2318, count = 7 } })
    c.fire("BAG_UPDATE_DELAYED")
    t.eq(texts(c.showItemTooltip("item:2318")), { "You have 7 in bags (bank not seen yet)" })
end

tests["have tip module: switched off, or not an item, no line"] = function(t)
    local k, c = start()
    t.eq(texts(c.showItemTooltip("spell:133")), {})
    t.eq(k.settings:set(H.SETTING, false), true)
    t.eq(texts(c.showItemTooltip("item:2318")), {})
end

return tests
