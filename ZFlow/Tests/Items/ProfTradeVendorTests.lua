local _, ns = ...
-- ProfPlan.OnContinent and ProfPlan.TradeVendor (Items/ProfPlan.lua), and
-- the buy step's place in ProfSources.For: pure, over made-up vendors.
-- Not tested in game.
local tests = {}

local function TV() return ns.ProfPlan.TradeVendor end
local function OC() return ns.ProfPlan.OnContinent end

local function vendor(name, map, x, y, trade)
    return { name = name, map = map, x = x, y = y, kinds = { vendor = true }, trade = trade }
end

local HERE = { map = 10, x = 0.5, y = 0.5 }
local function cont(map) return ({ [10] = 1, [11] = 1, [20] = 2 })[map] end

tests["on continent: own map always, another map only on the same known continent"] = function(t)
    t.eq(OC()(10, HERE, nil), true, "own map")
    t.eq(OC()(11, HERE, cont), true, "the next map over")
    t.eq(OC()(20, HERE, cont), false, "another continent")
    t.eq(OC()(11, HERE, nil), false, "continent not known")
    t.eq(OC()(11, HERE, function() error("boom") end), false, "a read that errors")
    t.eq(OC()(10, nil, cont), false, "no position")
end

tests["trade vendor: none seen, or none that fits, is nil"] = function(t)
    t.eq(TV()(nil, HERE, cont), nil)
    t.eq(TV()({}, HERE, cont), nil)
    t.eq(TV()({ a = vendor("A", 10, 0.5, 0.6) }, HERE, cont), nil, "no trade goods")
    t.eq(TV()({ a = vendor("A", 10, 0.5, 0.6, true) }, nil, cont), nil, "no position")
    local banker = vendor("B", 10, 0.5, 0.6, true)
    banker.kinds = { banker = true }
    t.eq(TV()({ b = banker }, HERE, cont), nil, "not a vendor")
    t.eq(TV()({ a = vendor("", 10, 0.5, 0.6, true) }, HERE, cont), nil, "no name")
end

tests["trade vendor: the nearest, this map before the rest of the continent"] = function(t)
    local places = {
        a = vendor("A", 10, 0.9, 0.5, true),
        b = vendor("B", 10, 0.4, 0.5, true),
        c = vendor("C", 10, 0.5, 0.5),
        d = vendor("D", 11, 0.5, 0.5, true),
        e = vendor("E", 20, 0.5, 0.5, true),
    }
    t.eq(TV()(places, HERE, cont), { name = "B", map = 10, x = 0.4, y = 0.5 })
    t.eq(TV()({ d = places.d, e = places.e }, HERE, cont), { name = "D", map = 11, x = 0.5, y = 0.5 }, "next map")
    t.eq(TV()({ e = places.e }, HERE, cont), nil, "another continent")
end

local function input(over)
    local i = { here = HERE, nodes = {}, name = function() return "Test Thread" end,
        vendorPrice = function() return 50 end }
    for k, v in pairs(over or {}) do i[k] = v end
    return i
end

tests["buy step: the one seen selling it wins over a trade goods vendor"] = function(t)
    local s = ns.ProfSources.For(input({
        vendorOf = function() return { npc = "Test Vendor", map = 10, x = 0.9, y = 0.5 } end,
        tradeVendor = function() return { name = "Test Trader", map = 10, x = 0.51, y = 0.5 } end,
    }), 4, 3)
    t.eq(s.text, "Buy 3 Test Thread from Test Vendor (50c each)")
    t.eq(s.target, { map = 10, x = 0.9, y = 0.5 })
end

tests["buy step: a trade goods vendor is a place to try, not named as the seller"] = function(t)
    local tv = function() return { name = "Test Trader", map = 10, x = 0.4, y = 0.5 } end
    local s = ns.ProfSources.For(input({ tradeVendor = tv }), 4, 3)
    t.eq(s.kind, "buy_vendor")
    t.eq(s.text, "Buy 3 Test Thread from a trade goods vendor (50c each): try Test Trader")
    t.eq(s.npc, nil)
    t.eq(s.target, { map = 10, x = 0.4, y = 0.5 })
    -- With no price seen, a trade goods vendor alone is not a reason to send
    -- the player there: the auction house line stands.
    s = ns.ProfSources.For(input({ vendorPrice = function() return nil end, tradeVendor = tv }), 4, 3)
    t.eq(s.kind, "buy_auction")
end

tests["buy step: no trade vendor, a broken answer or an error: the plain line, no target"] = function(t)
    for _, f in ipairs({ function() return nil end, function() return { name = "X" } end,
        function() error("boom") end }) do
        local s = ns.ProfSources.For(input({ tradeVendor = f, vendorOf = f }), 4, 3)
        t.eq(s.text, "Buy 3 Test Thread from a trade goods vendor (50c each)")
        t.eq(s.target, nil)
    end
end

return tests
