local _, ns = ...
-- ProfPlan.VendorFor (Items/ProfPlan.lua) and the buy step's place in
-- ProfSources.For: pure, over made-up vendors. Not tested in game.
local tests = {}

local function V() return ns.ProfPlan.VendorFor end

local function vendor(name, map, x, y, wares, trade)
    return { name = name, map = map, x = x, y = y, kinds = { vendor = true }, wares = wares, trade = trade }
end

local HERE = { map = 10, x = 0.5, y = 0.5 }
local function cont(map) return ({ [10] = 1, [11] = 1, [20] = 2 })[map] end

tests["vendor for: none seen, or none that fits, is nil"] = function(t)
    t.eq(V()(nil, HERE, cont, 4), nil)
    t.eq(V()({}, HERE, cont, 4), nil)
    t.eq(V()({ a = vendor("A", 10, 0.5, 0.6, { [9] = true }) }, HERE, cont, 4), nil, "sold something else, no trade goods")
    t.eq(V()({ a = vendor("A", 10, 0.5, 0.6, { [4] = true }) }, nil, cont, 4), nil, "no position")
    local banker = vendor("B", 10, 0.5, 0.6, { [4] = true })
    banker.kinds = { banker = true }
    t.eq(V()({ b = banker }, HERE, cont, 4), nil, "not a vendor")
end

tests["vendor for: the nearest that sold it, before any trade goods vendor"] = function(t)
    local places = {
        far = vendor("Far", 10, 0.9, 0.5, { [4] = true }),
        near = vendor("Near", 10, 0.6, 0.5, { [4] = true }),
        trade = vendor("Trade", 10, 0.51, 0.5, { [9] = true }, true),
    }
    t.eq(V()(places, HERE, cont, 4), { map = 10, x = 0.6, y = 0.5, name = "Near", sells = true })
    t.eq(V()(places, HERE, cont, "item:4"), { map = 10, x = 0.6, y = 0.5, name = "Near", sells = true }, "a link is the same item")
end

tests["vendor for: none sold it: the nearest trade goods vendor"] = function(t)
    local places = {
        a = vendor("A", 10, 0.9, 0.5, { [9] = true }, true),
        b = vendor("B", 10, 0.4, 0.5, { [9] = true }, true),
        c = vendor("C", 10, 0.5, 0.5, { [9] = true }),
    }
    t.eq(V()(places, HERE, cont, 4), { map = 10, x = 0.4, y = 0.5, name = "B", sells = false })
end

tests["vendor for: this continent only, this map first"] = function(t)
    local away = { a = vendor("A", 20, 0.5, 0.5, { [4] = true }) }
    t.eq(V()(away, HERE, cont, 4), nil, "another continent")
    local next = { a = vendor("A", 11, 0.5, 0.5, { [4] = true }) }
    t.eq(V()(next, HERE, cont, 4), { map = 11, x = 0.5, y = 0.5, name = "A", sells = true }, "the next map over")
    t.eq(V()(next, HERE, nil, 4), nil, "the continent is not known: only this map counts")
    next.b = vendor("B", 10, 0.9, 0.9, { [4] = true })
    t.eq(V()(next, HERE, cont, 4).name, "B", "this map before the next")
    -- One that sold it on the next map still wins over trade goods here.
    local mixed = { a = vendor("A", 11, 0.5, 0.5, { [4] = true }), b = vendor("B", 10, 0.5, 0.6, {}, true) }
    t.eq(V()(mixed, HERE, cont, 4).name, "A")
end

local function input(over)
    local i = { here = HERE, nodes = {}, name = function() return "Test Thread" end,
        vendorPrice = function() return 50 end }
    for k, v in pairs(over or {}) do i[k] = v end
    return i
end

tests["buy step: a vendor that sold it is named and is the target"] = function(t)
    local s = ns.ProfSources.For(input({ vendorFor = function()
        return { map = 10, x = 0.6, y = 0.5, name = "Test Vendor", sells = true }
    end }), 4, 3)
    t.eq(s.kind, "buy_vendor")
    t.eq(s.text, "Buy 3 Test Thread from Test Vendor (50c each)")
    t.eq(s.vendor, "Test Vendor")
    t.eq(s.target, { map = 10, x = 0.6, y = 0.5 })
end

tests["buy step: seen selling it with no price saved still gives the step, without a price"] = function(t)
    local s = ns.ProfSources.For(input({ vendorPrice = function() return nil end, vendorFor = function()
        return { map = 10, x = 0.6, y = 0.5, name = "Test Vendor", sells = true }
    end }), 4, 3)
    t.eq(s.kind, "buy_vendor")
    t.eq(s.text, "Buy 3 Test Thread from Test Vendor")
end

tests["buy step: a trade goods vendor is a place to try, not named as the seller"] = function(t)
    local s = ns.ProfSources.For(input({ vendorFor = function()
        return { map = 10, x = 0.4, y = 0.5, name = "Test Trader", sells = false }
    end }), 4, 3)
    t.eq(s.text, "Buy 3 Test Thread from a trade goods vendor (50c each): try Test Trader")
    t.eq(s.vendor, nil)
    t.eq(s.target, { map = 10, x = 0.4, y = 0.5 })
    -- With no price seen, a trade goods vendor alone is not a reason to send
    -- the player there: the auction house line stands.
    s = ns.ProfSources.For(input({ vendorPrice = function() return nil end, vendorFor = function()
        return { map = 10, x = 0.4, y = 0.5, name = "Test Trader", sells = false }
    end }), 4, 3)
    t.eq(s.kind, "buy_auction")
end

tests["buy step: no vendor, a broken answer or an error: the plain line, no target"] = function(t)
    for _, f in ipairs({ function() return nil end, function() return { name = "X" } end,
        function() error("boom") end }) do
        local s = ns.ProfSources.For(input({ vendorFor = f }), 4, 3)
        t.eq(s.text, "Buy 3 Test Thread from a trade goods vendor (50c each)")
        t.eq(s.target, nil)
    end
end

return tests
