local _, ns = ...
-- Parity row E-38, the data half (lead section 762): the auction house's
-- deals list, as Flow's Modules/Items/Trader.lua: T.Rows (:175-180, what
-- the route needs first, then the deals), T.ROWS (:49, ten lines), the
-- route row's line (T.Line :184-186) and T.Budget (:206, a quarter of your
-- gold at most). The deals are Items/Trader.lua's own (api.deals()); Z-Flow
-- buys nothing, so Flow's buying (T.Pick, T.Button) is not here. Made-up
-- items. Not tested in game. Fails before: no such file.
local tests = {}

local function DL() return ns.DealList end
local function coin(c) return c .. "c" end

local NEED = { id = 3, name = "Dig Rat", kind = "route", qty = 8, cost = 400 }
local function deal(id, gain) return { id = id, name = "Item " .. id, kind = "vendor", qty = 1, cost = 10, gain = gain, limit = 60 } end

tests["deal list: what the route needs first, then the deals, ten at most"] = function(t)
    t.eq(type(DL()), "table", "loaded")
    if type(DL()) ~= "table" then return end
    t.eq(DL().ROWS, 10)
    local deals = {}
    for i = 1, 12 do deals[i] = deal(100 + i, 100 - i) end
    local rows, more = DL().Rows({ NEED }, deals)
    t.eq(#rows, 10)
    t.eq(rows[1], NEED, "the route's need heads the list")
    t.eq(rows[2].id, 101, "then the deals, in their order")
    t.eq(more, 3, "13 in all, 3 not shown")
    local r2, m2 = DL().Rows(nil, { deal(1, 60) })
    t.eq({ #r2, m2 }, { 1, 0 })
    local r3, m3 = DL().Rows(nil, nil)
    t.eq({ #r3, m3 }, { 0, 0 })
end

tests["deal list: a route row's line in our words; a deal's is the trader's"] = function(t)
    if type(DL()) ~= "table" then return t.ok(false, "not loaded") end
    t.eq(DL().Line(NEED, coin), "8 x Dig Rat, for your route (about 400c)")
    t.eq(DL().Line({ kind = "route", qty = 2, name = "Wool" }, coin), "2 x Wool, for your route")
    local d = deal(5, 50)
    t.eq(DL().Line(d, coin), ns.Trader.Line(d, coin))
end

tests["deal list: the most to spend on one trade is a quarter of your gold"] = function(t)
    if type(DL()) ~= "table" then return t.ok(false, "not loaded") end
    t.eq(DL().Budget(10000), 2500)
    t.eq(DL().Budget(10001, 0.5), 5000)
    t.eq(DL().Budget(nil), 0, "money not read: nothing")
end

return tests
