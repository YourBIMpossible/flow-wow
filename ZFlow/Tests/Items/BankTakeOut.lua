-- E-19: the bank "Take out" list (Items/BankTakeOut.lua): what the bank held
-- at the last visit that the sell rules would now sell. Data only. Made-up
-- items, fake client only; not tested in game.
local _, ns = ...

local T = ns.BankTakeOut
local tests = {}

local INFO = {
    [2318] = { name = "Light Leather", quality = 1, sellPrice = 15, classID = 7 },
    [4865] = { name = "Ruined Pelt", quality = 0, sellPrice = 5, classID = 15 },
    [9001] = { name = "Broken Fang", quality = 0, sellPrice = 3, classID = 15 },
}

-- Banker.Items' entries, as the pure rule takes them.
local ITEMS = {
    { key = 4865, name = "Ruined Pelt", count = 3, quality = 0, classID = 15 },
    { key = 9001, name = "Broken Fang", count = 7, quality = 0, classID = 15 },
    { key = 9002, name = "Bent Sword", count = 1, quality = 0, classID = 2 },
    { key = 9003, name = "Torn Vest", count = 1, quality = 0, classID = 4 },
    { key = 9004, name = "Old Token", count = 2, quality = 0, classID = 12 },
    { key = 9005, count = 4 },
}

local function sell(key, name, count)
    return { key = key, name = name, count = count, quality = 0, reason = "made up" }
end

local function keys(rows)
    local out = {}
    for i, r in ipairs(rows) do out[i] = r.key end
    return out
end

-- ------------------------------------------------------------------ pure

tests["bank take out: the names agreed"] = function(t)
    t.eq(T.NAME, "bankTakeOut")
    t.eq(T.NOT_OUT, { [2] = true, [4] = true, [12] = true })
    t.ok(type(T.NOT_SEEN) == "string" and T.NOT_SEEN ~= "")
    t.ok(type(T.RESERVATIONS_UNKNOWN) == "string" and T.RESERVATIONS_UNKNOWN ~= T.NOT_SEEN)
    t.ok(type(T.NOT_STARTED) == "string" and T.NOT_STARTED ~= T.NOT_SEEN)
    t.ok(type(T.FAILED) == "string" and T.FAILED ~= T.NOT_SEEN)
end

tests["bank take out: what the sell rules sell, by name, with its count and reason"] = function(t)
    local rows, unread = T.Rows(ITEMS, { sell(4865, "Ruined Pelt", 3), sell(9001, "Broken Fang", 7) }, nil, nil)
    t.eq(keys(rows), { 9001, 4865 }, "by name, not by count")
    t.eq(rows[1], { key = 9001, id = 9001, name = "Broken Fang", count = 7, quality = 0, reason = "made up" })
    t.eq(rows[2].count, 3)
    t.eq(unread, 0)
end

tests["bank take out: the same name is ordered by its key, and no name by its key"] = function(t)
    local items = {
        { key = 20, name = "Same", count = 1, classID = 15 },
        { key = 10, name = "Same", count = 1, classID = 15 },
        { key = 30, count = 1, classID = 15 },
    }
    local rows = T.Rows(items, { sell(20, "Same", 1), sell(30, nil, 1), sell(10, "Same", 1) }, nil, nil)
    t.eq(keys(rows), { 30, 10, 20 })
    t.eq(rows[1].name, nil, "a name not read is not made up")
end

tests["bank take out: what you chose to keep in the bank stays there"] = function(t)
    local sells = { sell(4865, "Ruined Pelt", 3), sell(9001, "Broken Fang", 7) }
    t.eq(keys((T.Rows(ITEMS, sells, { [4865] = "bank" }, nil))), { 9001 })
    t.eq(keys((T.Rows(ITEMS, sells, { [4865] = "carry" }, nil))), { 9001, 4865 }, "only the bank choice holds it")
end

tests["bank take out: weapons, armor and quest things are never listed"] = function(t)
    local rows, unread = T.Rows(ITEMS, { sell(9002, "Bent Sword", 1), sell(9003, "Torn Vest", 1),
        sell(9004, "Old Token", 2), sell(4865, "Ruined Pelt", 3) }, nil, nil)
    t.eq(keys(rows), { 4865 })
    t.eq(unread, 0, "left out by the rule, not for want of a read")
end

tests["bank take out: an item whose kind was not read is counted, not listed"] = function(t)
    local rows, unread = T.Rows(ITEMS, { sell(9005, nil, 4), sell(4865, "Ruined Pelt", 3) }, nil, nil)
    t.eq(keys(rows), { 4865 })
    t.eq(unread, 1)
end

tests["bank take out: a count the rules could not give stays unknown"] = function(t)
    local rows = T.Rows(ITEMS, { sell(4865, "Ruined Pelt", nil) }, nil, nil)
    t.eq(#rows, 1)
    t.eq(rows[1].count, nil, "never a zero")
end

tests["bank take out: not known is nil, never an empty list"] = function(t)
    t.eq(T.Rows(nil, {}, nil, nil), nil, "the bank not seen")
    t.eq(T.Rows(ITEMS, nil, nil, nil), nil, "the sell rules gave nothing to go by")
    local rows, unread = T.Rows({}, {}, nil, nil)
    t.eq(rows, {}, "a bank seen empty is an empty list")
    t.eq(unread, 0)
end

tests["bank take out: where in the bank, only when a read gives it"] = function(t)
    local where = T.Where({ bankSlots = function()
        return { { bag = -1, slot = 4, item = 4865, count = 2 }, { bag = 5, slot = 1, item = 4865, count = 1 },
                 { bag = 5, slot = 2, item = 9001 }, { slot = 3, item = 9001, count = 1 }, "not a row" }
    end })
    t.eq(where[4865], { { bag = -1, slot = 4, count = 2 }, { bag = 5, slot = 1, count = 1 } })
    t.eq(where[9001], { { bag = 5, slot = 2 } }, "a count not read is left out; a row with no bag is no place")
    local rows = T.Rows(ITEMS, { sell(4865, "Ruined Pelt", 3) }, nil, where)
    t.eq(rows[1].slots, where[4865])
    t.eq(T.Where({}), nil, "a client without the read: not known")
    t.eq(T.Where(nil), nil)
    t.eq(T.Where({ bankSlots = function() error("boom") end }), nil)
    t.eq(T.Where({ bankSlots = function() return nil end }), nil, "the bank closed: not known")
    t.eq(T.Rows(ITEMS, { sell(4865, "Ruined Pelt", 3) }, nil, nil)[1].slots, nil)
end

-- ---------------------------------------------------------------- module

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setClock(5000)
    c.setItemInfo(INFO)
    c.setBagItems({ { item = 2318, count = 20 } })
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    if opts.reservations ~= false then ns.Reservations.Declare(k) end
    local api = T.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api
end

tests["bank take out module: a bank never seen is not known, never empty"] = function(t)
    local k, _, api = start()
    t.eq((k:ModuleState(T.NAME)), "started")
    local list, why = api.list()
    t.eq(list, nil)
    t.eq(why, T.NOT_SEEN)
end

tests["bank take out module: the banked junk, as last seen"] = function(t)
    local k, _, api = start()
    t.eq(k.store:set("char", ns.HaveTip.PATH, { at = 1000, counts = { [2318] = 40, [4865] = 3, [9001] = 7 } }), true)
    local list, why = api.list()
    t.eq(why, nil)
    t.eq(keys(list.rows), { 9001, 4865 })
    t.eq(list.rows[2].id, 4865)
    t.eq(list.rows[2].count, 3)
    t.eq(list.rows[2].name, INFO[4865].name)
    t.eq(list.rows[2].slots, nil, "the saved bank has no places")
    t.eq(list.at, 1000)
    t.eq(list.unread, 0)
    local asked = k.use(T.NAME).List()
    t.eq(keys(asked.rows), { 9001, 4865 }, "others ask for it by name")
end

tests["bank take out module: your never-sell list and your bank choice are kept"] = function(t)
    local k, _, api = start()
    t.eq(k.store:set("char", ns.HaveTip.PATH, { at = 1000, counts = { [4865] = 3, [9001] = 7 } }), true)
    t.eq(k.store:set("char", "settings.sell.never", { [4865] = true }), true)
    t.eq(keys(api.list().rows), { 9001 })
    t.eq(k.store:set("account", "settings.banker.rules", { [9001] = "bank" }), true)
    local list, why = api.list()
    t.eq(list.rows, {}, "seen, and nothing to take out: an empty list, not nil")
    t.eq(why, nil)
end

tests["bank take out module: reservations not known, nothing is offered for sale"] = function(t)
    local k, _, api = start({ reservations = false })
    t.eq(k.store:set("char", ns.HaveTip.PATH, { at = 1000, counts = { [4865] = 3 } }), true)
    local list, why = api.list()
    t.eq(list, nil)
    t.eq(why, T.RESERVATIONS_UNKNOWN)
end

tests["bank take out module: a read that raises is said, not passed on"] = function(t)
    local k, _, api = start()
    t.eq(k.store:set("char", ns.HaveTip.PATH, { at = 1000, counts = { [4865] = 3 } }), true)
    local kept = ns.Reservations.Grants
    ns.Reservations.Grants = function() error("boom") end
    local ok, list, why = pcall(api.list)
    ns.Reservations.Grants = kept
    t.ok(ok, "the call does not raise")
    t.eq(list, nil)
    t.eq(why, T.FAILED)
end

tests["bank take out module: a made-up place read is carried on the rows"] = function(t)
    local k, c, api = start()
    t.eq(k.store:set("char", ns.HaveTip.PATH, { at = 1000, counts = { [4865] = 3 } }), true)
    c.bankSlots = function() return { { bag = -1, slot = 4, item = 4865, count = 3 } } end
    t.eq(api.list().rows[1].slots, { { bag = -1, slot = 4, count = 3 } })
end

tests["bank take out module: stopped, it says so"] = function(t)
    local k, _, api = start()
    k:SwitchOff(T.NAME, "a test")
    local list, why = api.list()
    t.eq(list, nil)
    t.eq(why, T.NOT_STARTED)
end

-- Nothing acts: every client function the list calls is noted, and none of
-- them is one that moves, takes, puts, sells, buys or uses a thing.
tests["bank take out module: look only, no acting client call is made"] = function(t)
    local k, c, api = start()
    t.eq(k.store:set("char", ns.HaveTip.PATH, { at = 1000, counts = { [4865] = 3, [9001] = 7 } }), true)
    local called, n = {}, 0
    for name, fn in pairs(c) do
        if type(fn) == "function" then
            c[name] = function(...)
                called[name] = true
                n = n + 1
                return fn(...)
            end
        end
    end
    local list = api.list()
    t.eq(#list.rows, 2)
    t.ok(n > 0, "the calls are seen")
    for name in pairs(called) do
        local w = tostring(name):lower()
        t.ok(not (w:find("deposit") or w:find("withdraw") or w:find("pickup") or w:find("sell") or w:find("click")
            or w:find("^use") or w:find("^buy") or w:find("^move") or w:find("^equip") or w:find("^delete")), "a read, not an act: " .. w)
    end
    for name in pairs(T) do
        local w = tostring(name):lower()
        t.ok(not (w:find("withdraw") or w:find("deposit") or w:find("^take") or w:find("click") or w:find("auto")),
            "no acting function: " .. w)
    end
end

return tests
