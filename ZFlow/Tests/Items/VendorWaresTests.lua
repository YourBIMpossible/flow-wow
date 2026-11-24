local _, ns = ...

-- Queue item A5: which vendor sold what and where (Items/VendorWares.lua),
-- and the plan's buy line naming that vendor (Items/ProfSources.lua).
-- Offline, over the fake client: every vendor, item and place here is made
-- up, and none of this was looked at in game.

local V = ns.VendorWares
local tests = {}

local function memory(start, refuse)
    local data = { char = { [V.PATH] = start } }
    return {
        data = data,
        get = function(_, scope, path) return data[scope] and data[scope][path] end,
        set = function(_, scope, path, value)
            if refuse then return false end
            data[scope] = data[scope] or {}
            data[scope][path] = value
            return true
        end,
    }
end

local function client(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    if opts.npc ~= false then c.setServiceNpc("Creature-0-1-2-3-4", opts.npc or "Test Vendor") end
    if opts.pos ~= false then c.setPosition(opts.map or 7, opts.x or 0.4, opts.y or 0.6) end
    if opts.clock ~= false then c.setClock(opts.clock or 5000) end
    c.setMerchant(opts.rows or {
        { index = 1, item = "item:2320", price = 50, stack = 5 },
        { index = 2, item = "item:2321", price = 100, stack = 1 },
    })
    -- The wares are read only while the window is open.
    if opts.open ~= false then c.setMerchantOpen(true) end
    return c
end

tests["vendor wares: a merchant window saves who sold each item and where"] = function(t)
    local store = memory()
    local report = V.Read(client(), store)
    t.eq(report.ok, true, "read")
    t.eq(report.npc, "Test Vendor", "the vendor")
    t.eq(report.recorded, 2, "both items")
    local wares = store.data.char[V.PATH]
    t.eq(wares[2320], { ["Test Vendor"] = { map = 7, x = 0.4, y = 0.6, seen = 5000 } }, "the first")
    t.eq(wares[2321]["Test Vendor"].map, 7, "the second")
end

tests["vendor wares: nothing is written without a vendor name or a place"] = function(t)
    local store = memory()
    local a = V.Read(client({ npc = false }), store)
    t.eq(a.ok, false, "no vendor")
    t.eq(a.reason, "the vendor is not known")
    t.eq(store.data.char[V.PATH], nil, "nothing written")
    local c = ns.make.fakeClient()
    c.setServiceNpc(nil, "Test Vendor")
    c.setMerchant({ { index = 1, item = "item:2320", price = 50, stack = 5 } })
    c.setMerchantOpen(true)
    c.position = function() return nil end
    local b = V.Read(c, store)
    t.eq(b.reason, "the position is not known")
    t.eq(store.data.char[V.PATH], nil, "nothing written")
end

tests["vendor wares: an empty window or rows that are no items save nothing"] = function(t)
    local store = memory()
    local r = V.Read(client({ rows = { { index = 1, item = "not an item", price = 1, stack = 1 } } }), store)
    t.eq(r.ok, false, "nothing")
    t.eq(r.reason, "nothing to save")
    t.eq(store.data.char[V.PATH], nil, "nothing written")
end

tests["vendor wares: a store that refuses is left as it was"] = function(t)
    local before = { [2320] = { ["Old Vendor"] = { map = 1, x = 0.1, y = 0.1, seen = 10 } } }
    local store = memory(before, true)
    local r = V.Read(client(), store)
    t.eq(r.ok, false, "refused")
    t.eq(r.recorded, 0, "nothing counted")
    t.eq(before[2320]["Test Vendor"], nil, "the saved table was not touched")
    t.eq(before[2321], nil, "nor added to")
end

tests["vendor wares: an item keeps a few vendors, the oldest going first"] = function(t)
    local store = memory()
    for i = 1, V.PER_ITEM + 1 do
        V.Read(client({ npc = "Test Vendor " .. i, clock = 1000 * i, x = i / 10 }), store)
    end
    local vendors = store.data.char[V.PATH][2320]
    local n = 0
    for _ in pairs(vendors) do n = n + 1 end
    t.eq(n, V.PER_ITEM, "no more than the bound")
    t.eq(vendors["Test Vendor 1"], nil, "the one seen longest ago went")
    t.ok(vendors["Test Vendor " .. (V.PER_ITEM + 1)] ~= nil, "the newest stays")
end

tests["vendor wares: a new item past the bound is not written, a known one still is"] = function(t)
    local full = {}
    for i = 1, V.MAX do full[100000 + i] = { ["Old Vendor"] = { map = 1, x = 0.1, y = 0.1, seen = 1 } } end
    full[100003] = nil
    full[100001] = nil
    full[2321] = { ["Old Vendor"] = { map = 1, x = 0.1, y = 0.1, seen = 1 } }
    full[100002] = nil
    full[2322] = { ["Old Vendor"] = { map = 1, x = 0.1, y = 0.1, seen = 1 } }
    -- V.MAX - 1 items now: room for one new item only.
    local store = memory(full)
    local r = V.Read(client({ rows = {
        { index = 1, item = "item:2321", price = 1, stack = 1 },
        { index = 2, item = "item:2320", price = 1, stack = 1 },
        { index = 3, item = "item:2323", price = 1, stack = 1 },
    } }), store)
    local wares = store.data.char[V.PATH]
    t.eq(r.recorded, 2, "the known one and one new one")
    t.ok(wares[2321]["Test Vendor"] ~= nil, "the known item took the vendor")
    t.ok(wares[2320] ~= nil, "the first new item fitted")
    t.eq(wares[2323], nil, "the next did not")
end

tests["vendor wares: the same vendor seen again moves with the player, the date kept without a clock"] = function(t)
    local store = memory()
    V.Read(client({ clock = 5000 }), store)
    V.Read(client({ clock = false, x = 0.45 }), store)
    local e = store.data.char[V.PATH][2320]["Test Vendor"]
    t.eq(e.x, 0.45, "the newer place")
    t.eq(e.seen, 5000, "the date already saved stays")
end

tests["vendor wares: the nearest on this map, else the one seen last"] = function(t)
    local wares = { [2320] = {
        ["Test Far"] = { map = 7, x = 0.9, y = 0.9, seen = 900 },
        ["Test Near"] = { map = 7, x = 0.42, y = 0.6, seen = 100 },
        ["Test Elsewhere"] = { map = 8, x = 0.4, y = 0.6, seen = 950 },
    } }
    t.eq(V.Of(wares, 2320, { map = 7, x = 0.4, y = 0.6 }).npc, "Test Near", "the nearest here")
    t.eq(V.Of(wares, 2320, { map = 9, x = 0.4, y = 0.6 }).npc, "Test Elsewhere", "none here: seen last")
    t.eq(V.Of(wares, 2320, nil).npc, "Test Elsewhere", "no position: seen last")
    t.eq(V.Of(wares, 2321, nil), nil, "never seen sold")
    t.eq(V.Of(nil, 2320, nil), nil, "nothing saved")
    t.eq(V.Of({ [2320] = { ["Test Bad"] = { map = "x" } } }, 2320, nil), nil, "a broken entry is no vendor")
end

-- ------------------------------------------------------------ the buy line
local function input(over)
    local i = {
        name = function() return "Test Thread" end,
        vendorPrice = function() return 10 end,
        nodes = {},
    }
    for k, v in pairs(over or {}) do i[k] = v end
    return i
end

tests["vendor wares: the buy line names the vendor and gives the arrow a place"] = function(t)
    local step = ns.ProfSources.For(input({ vendorOf = function(item)
        if item == 2320 then return { npc = "Test Vendor", map = 7, x = 0.4, y = 0.6 } end
    end }), 2320, 5)
    t.eq(step.kind, "buy_vendor", "still a vendor step")
    t.eq(step.item, 2320, "the item")
    t.eq(step.count, 5, "how many")
    t.eq(step.npc, "Test Vendor", "who sells it")
    t.eq(step.target, { map = 7, x = 0.4, y = 0.6 }, "where")
    t.ok(step.text:find("Buy 5 Test Thread from Test Vendor (", 1, true) == 1, step.text)
    t.eq(step.text:find("a vendor", 1, true), nil, "no vague vendor")
end

tests["vendor wares: no vendor seen keeps the old line, with no place guessed"] = function(t)
    local plain = ns.ProfSources.For(input(), 2320, 5)
    t.ok(plain.text:find("Buy 5 Test Thread from a vendor (", 1, true) == 1, plain.text)
    t.eq(plain.npc, nil, "no vendor named")
    t.eq(plain.target, nil, "no place")
    local unseen = ns.ProfSources.For(input({ vendorOf = function() return nil end }), 2320, 5)
    t.eq(unseen.text, plain.text, "asked and not known: the same line")
    local placeless = ns.ProfSources.For(input({ vendorOf = function() return { npc = "Test Vendor" } end }), 2320, 5)
    t.eq(placeless.npc, "Test Vendor", "named")
    t.eq(placeless.target, nil, "but no place guessed")
    local noPrice = ns.ProfSources.For(input({ vendorPrice = function() return nil end,
        vendorOf = function() return { npc = "Test Vendor", map = 7, x = 0.4, y = 0.6 } end }), 2320, 5)
    t.eq(noPrice.kind, "buy_auction", "no vendor price seen: the auction house as before")
end

-- ------------------------------------------------------------ whole add-on
tests["vendor wares: in the whole add-on a visit to a vendor names it in the plan"] = function(t)
    if type(ns.offline) ~= "table" or type(ns.offline.addon) ~= "function" then
        t.skip("no whole add-on offline")
        return
    end
    local c = client({ open = false })
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, {})
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    local before = #addon.problems:list()
    c.setMerchantOpen(true)
    local wares = addon.store:get("char", V.PATH)
    t.ok(type(wares) == "table" and type(wares[2320]) == "table", "the wares were saved")
    if type(wares) ~= "table" or type(wares[2320]) ~= "table" then return end
    t.eq(wares[2320]["Test Vendor"].map, 7, "with the place")
    local i = ns.ProfPlan.Input(c, addon.store, "Tailoring")
    t.eq(i.vendorOf(2320).npc, "Test Vendor", "the plan's input knows the vendor")
    t.eq(i.vendorOf(999999), nil, "and no vendor for what was never seen sold")
    i.name = function() return "Test Thread" end
    local step = ns.ProfSources.For(i, 2320, 3)
    t.eq(step.kind, "buy_vendor", "the price was read at the same visit")
    t.eq(step.npc, "Test Vendor", "the line's vendor")
    t.ok(step.text:find("from Test Vendor", 1, true) ~= nil, step.text)
    t.eq(step.target.map, 7, "and the place for the arrow")
    t.eq(#addon.problems:list(), before, "no problem recorded")
end

return tests
