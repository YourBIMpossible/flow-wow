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
    t.eq(rows[1], { key = 9001, id = 9001, name = "Broken Fang", count = 7, quality = 0, reason = "made up",
                    take = T.SELL, next = ns.BankerRows.NextChoice(nil) })
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

-- E-19 one-source join: Flow's whole B.TakeOutRows (a529eea
-- Modules/Items/Banker.lua, after B.ChoiceRows). A thing a route step wants
-- (e.step), a quest wants (e.quest) or a reservation holds (e.hold, Z-Flow's
-- own, between quest and sell) is taken out too. One row per thing, the
-- winner by Flow's priority route > quest > hold > sell, then one sort of all
-- rows by name, then key. NOT_OUT holds back the sell rows only.
local WANTED = {
    { key = 9002, name = "Bent Sword", count = 1, quality = 0, classID = 2, step = "Get from your bank: Bent Sword" },
    { key = 9003, name = "Torn Vest", count = 1, quality = 0, classID = 4, quest = "Vests Wanted" },
    { key = 9004, name = "Old Token", count = 2, quality = 0, classID = 12, hold = "for one of your item goals" },
    { key = 4865, name = "Ruined Pelt", count = 3, quality = 0, classID = 15, quest = "Pelts", hold = "held" },
    { key = 9001, name = "Broken Fang", count = 7, quality = 0, classID = 15 },
    { key = 9006, name = "Apple", count = 1, classID = 0, step = "Buy apples", quest = "Fruit", hold = "held" },
}

local function takes(rows)
    local out = {}
    for i, r in ipairs(rows) do out[i] = r.take end
    return out
end

tests["bank take out: one row per thing, the winner by Flow's priority, all by name"] = function(t)
    local sells = { sell(4865, "Ruined Pelt", 3), sell(9001, "Broken Fang", 7), sell(9002, "Bent Sword", 1) }
    local rows, unread = T.Rows(WANTED, sells, nil, nil)
    t.eq(keys(rows), { 9006, 9002, 9001, 9004, 4865, 9003 }, "one sort by name, not route rows first")
    t.eq(takes(rows), { T.ROUTE, T.ROUTE, T.SELL, T.HOLD, T.QUEST, T.QUEST })
    t.eq(rows[1].reason, WANTED[6].step, "the route wins over a quest and a hold")
    t.eq(rows[5].reason, WANTED[4].quest, "a quest wins over a hold and a sell")
    t.eq(rows[4].reason, WANTED[3].hold)
    t.eq(rows[2].count, 1, "the bank's count")
    t.eq(rows[2].next, nil, "no keep or sell choice for a wanted thing")
    t.eq(rows[3].next, ns.BankerRows.NextChoice(nil))
    t.eq(unread, 0)
end

tests["bank take out: weapons, armor and quest things are held back from the sell rows only"] = function(t)
    local rows = T.Rows(WANTED, { sell(9002, "Bent Sword", 1), sell(9003, "Torn Vest", 1) }, nil, nil)
    local by = {}
    for _, r in ipairs(rows) do by[r.key] = r.take end
    t.eq(by[9002], T.ROUTE, "a weapon a route step wants is taken out (as Flow)")
    t.eq(by[9003], T.QUEST, "armor a quest wants is taken out")
    t.eq(by[9004], T.HOLD, "a quest thing a reservation holds is taken out")
    local plain = {
        { key = 9002, name = "Bent Sword", count = 1, classID = 2 },
        { key = 9003, name = "Torn Vest", count = 1, classID = 4 },
    }
    t.eq(T.Rows(plain, { sell(9002, "Bent Sword", 1), sell(9003, "Torn Vest", 1) }, nil, nil), {},
        "the same weapon and armor, only sold: not listed")
end

-- E-19 join CHANGES-2 (§885): a hold covers only what it holds. The part
-- the sell rules still sell (they already leave the held part out) keeps its
-- sell row, and the hold row counts the held part, not the whole bank count.
-- Fails before: the hold row takes the whole thing and no sell row is made.
tests["bank take out: a hold keeps only its count; the free part is still offered for sale"] = function(t)
    local held = { { key = 4865, name = "Ruined Pelt", count = 3, quality = 0, classID = 15,
                     hold = "for one of your item goals", holdCount = 2 } }
    local rows = T.Rows(held, { sell(4865, "Ruined Pelt", 1) }, nil, nil)
    t.eq(#rows, 2, "a hold row and a sell row")
    local by = {}
    for _, r in ipairs(rows) do by[r.take] = r end
    t.eq(by[T.HOLD] and by[T.HOLD].count, 2, "the held part")
    t.eq(by[T.SELL] and by[T.SELL].count, 1, "the free part the sell rules sell")
    t.eq((T.Rows(held, {}, nil, nil))[1].count, 2, "nothing sold: the hold row alone")
    local wanted = { { key = 4865, name = "Ruined Pelt", count = 3, quality = 0, classID = 15,
                       quest = "Pelts", hold = "held", holdCount = 2 } }
    t.eq(#T.Rows(wanted, { sell(4865, "Ruined Pelt", 1) }, nil, nil), 1, "a quest still takes the whole thing")
end

-- E-19 join CHANGES-3 (section 888.1): the hold row and the sell row
-- together are the whole bank count: what two claims hold, and the rest.
-- Fails before: the hold row counted the first claim only (2 + 1 of 6).
tests["bank take out: two holds and the free part add up to the bank count"] = function(t)
    local grants = {
        { claim = { kind = "item", key = 4865, amount = 2, activity = "goal" }, from = { bank = 2 } },
        { claim = { kind = "item", key = 4865, amount = 3, activity = "goal" }, from = { bank = 3 } },
    }
    local bank = { { key = 4865, name = "Ruined Pelt", count = 6, quality = 0, classID = 15 } }
    local free = 6 - ns.Reservations.HeldIn(grants, "bank"):Held(4865)
    local rows = T.Rows(ns.TakeOutWhy.Fill(bank, nil, {}, grants), { sell(4865, "Ruined Pelt", free) }, nil, nil)
    local by = {}
    for _, r in ipairs(rows) do by[r.take] = r.count end
    t.eq({ by[T.HOLD], by[T.SELL] }, { 5, 1 })
    t.eq((by[T.HOLD] or 0) + (by[T.SELL] or 0), 6, "every pelt in one row or the other")
end

tests["bank take out: kept in the bank, nothing takes it out"] = function(t)
    local sells = { sell(4865, "Ruined Pelt", 3), sell(9001, "Broken Fang", 7) }
    local rules = { [9002] = "bank", [9003] = "bank", [9004] = "bank", [4865] = "bank", [9006] = "carry" }
    t.eq(keys((T.Rows(WANTED, sells, rules, nil))), { 9006, 9001 })
end

tests["bank take out: your own sell choice is marked"] = function(t)
    local mine = sell(9001, "Broken Fang", 7)
    mine.mine = true
    local rows = T.Rows(ITEMS, { mine, sell(4865, "Ruined Pelt", 3) }, nil, nil)
    t.eq(rows[1].mine, true)
    t.eq(rows[2].mine, nil)
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

-- ------------------------------------------------- one source, every surface

-- One saved bank, one set of bank rules, the reservations: the Take out
-- list, E-21's route step count, the banker view's bank rows and the banker
-- word's to-sell lines all come from the same rows. A banked grey weapon and
-- a banked grey armor piece the sell rules would sell are in none of them.
local LINEN = 2589
local EVERY_INFO = {
    [LINEN] = { name = "Linen Cloth", quality = 1, sellPrice = 13, classID = 7 },
    [2318] = { name = "Light Leather", quality = 1, sellPrice = 15, classID = 7 },
    [4865] = { name = "Ruined Pelt", quality = 0, sellPrice = 5, classID = 15 },
    [9001] = { name = "Broken Fang", quality = 0, sellPrice = 3, classID = 15 },
    [9002] = { name = "Bent Sword", quality = 0, sellPrice = 7, classID = 2 },
    [9003] = { name = "Torn Vest", quality = 0, sellPrice = 6, classID = 4 },
}
local EVERY_BANK = { at = 1000, counts = { [2318] = 40, [4865] = 3, [9001] = 7, [9002] = 1, [9003] = 1 } }
local EVERY_BANKER = { a = { map = 1411, x = 0.5, y = 0.3, name = "Made Up Banker", kinds = { banker = true } } }

local function startEvery()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, { learned = { places = { services = EVERY_BANKER } } })
    c.setClock(5000)
    c.setItemInfo(EVERY_INFO)
    local bag = {}
    for i = 1, ns.BankPutAway.MIN_STACKS do bag[i] = { item = LINEN, count = 20 } end
    c.setBagItems(bag)
    c.setBags({ { free = 10, total = 16, family = 0 } })
    c.setZone(1, 1411)
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    ns.Reservations.Declare(k)
    local api = T.Declare(k)
    ns.BankPutAway.Declare(k)
    ns.Banker.Declare(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api
end

local function keySet(rows)
    local out = {}
    for _, r in ipairs(rows) do out[#out + 1] = tostring(r.key) end
    table.sort(out)
    return out
end

tests["bank take out: one fixture, every surface lists the same rows"] = function(t)
    local k, c, api = startEvery()
    t.eq(k.store:set("char", ns.HaveTip.PATH, EVERY_BANK), true)
    t.eq(k.store:set("account", "settings.banker.rules", { [9001] = "bank" }), true)
    local list = api.list()
    t.eq(keySet(list.rows), { "4865" }, "the pelt; not the fang you keep in the bank, not the sword or the vest")
    -- E-21's step counts the same list.
    local step = k.use(ns.BankPutAway.NAME).Step()
    t.eq(step and step.out, #list.rows)
    -- The banker view, from the same bank, decisions and rules.
    local R = ns.Reservations
    local r = ns.BankList.Current(k.use)
    local context = ns.BankList.Context(k.store, R.HeldIn(R.Grants(r), "bank"))
    local bank = {}
    for i, e in ipairs(ns.Banker.Items(EVERY_BANK, c.itemInfo)) do
        local x = {}
        for f, v in pairs(e) do x[f] = v end
        x.decision = ns.Disposition.Decide(e, context)
        bank[i] = x
    end
    local inBank = {}
    for _, row in ipairs(ns.BankerRows.SellRows({}, bank, context.bankRules)) do
        if row.bank then inBank[#inBank + 1] = row end
    end
    t.eq(keySet(inBank), keySet(list.rows), "the banker view's bank rows")
    -- The banker word's to-sell lines are the same rows' lines.
    local before = #c.printed
    c.slashes[ns.id.slash]("banker")
    local want = ns.Banker.SellLines(list.rows)
    local lines = {}
    for i = before + 1, #c.printed do lines[#lines + 1] = c.printed[i] end
    local tail = {}
    for i = #lines - #want + 1, #lines do tail[#tail + 1] = ns.ItemPresent.Plain(lines[i]) end
    local p = ns.id.title .. ": "
    local plainWant = {}
    for i, line in ipairs(want) do plainWant[i] = p .. ns.ItemPresent.Plain(line) end
    t.eq(tail, plainWant, "the banker word's bank rows")
end

return tests
