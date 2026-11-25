local _, ns = ...
-- The repair cost line (reconcile row G2, show only), end to end, on the
-- whole add-on loaded on a fake client. The entry is the player's: the
-- merchant window opening (MERCHANT_SHOW). What is held here: at a
-- merchant that repairs, one chat line says the cost, the player's money
-- and which button repairs; nothing is said where there is nothing to
-- repair or the merchant does not repair; nothing is repaired or sold.
-- Made-up figures. Not tested in game.
local tests = {}

local function boot()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon, addon.problems:count()
end

local function lines(c)
    local out = {}
    for _, l in ipairs(c.printed or {}) do
        if type(l) == "string" and l:find("Repairing everything", 1, true) then out[#out + 1] = l end
    end
    return out
end

local function at(c, repairs, cost, money)
    c.setMerchantRepairs(repairs)
    c.setRepairCost(cost)
    c.setMoney(money)
    c.setMerchantOpen(true)
end

tests["repair cost: at a merchant that repairs, the cost, your money and the button"] = function(t)
    local c, addon, before = boot()
    t.eq(#lines(c), 0, "nothing before a merchant")
    at(c, true, 1240, 10500)
    t.eq(lines(c), { ns.id.title .. ": Repairing everything here costs 12.4s; you have 1.05g. "
        .. "Press the merchant's Repair All button." })
    t.eq(addon.repairCost.said(), 1)
    t.eq(addon.problems:count(), before)
end

tests["repair cost: too little money says so and what to do"] = function(t)
    local c, addon, before = boot()
    at(c, true, 1240, 500)
    local l = lines(c)[1] or ""
    t.ok(l:find("costs 12.4s; you have 5s. That is not enough for all of it", 1, true) ~= nil, l)
    t.ok(l:find("Repair All", 1, true) == nil, "the button it can't pay for is not named")
    t.eq(addon.problems:count(), before)
end

tests["repair cost: money not read: the cost and the button only"] = function(t)
    local c, addon, before = boot()
    at(c, true, 300, nil)
    t.eq(lines(c), { ns.id.title .. ": Repairing everything here costs 3s. Press the merchant's Repair All button." })
    t.eq(addon.problems:count(), before)
end

tests["repair cost: quiet with nothing to repair, at a merchant that does not repair, and with the cost not read"] = function(t)
    local c, addon, before = boot()
    at(c, true, 0, 10500)
    c.setMerchantOpen(false)
    at(c, false, 1240, 10500)
    c.setMerchantOpen(false)
    at(c, true, nil, 10500)
    c.setMerchantOpen(false)
    at(c, nil, 1240, 10500)
    t.eq(#lines(c), 0)
    t.eq(addon.repairCost.last(), nil)
    t.eq(addon.problems:count(), before)
end

tests["repair cost: once per opened window, again at the next visit; off says nothing"] = function(t)
    local c, addon, before = boot()
    at(c, true, 1240, 10500)
    c.fire("BAG_UPDATE_DELAYED")
    c.advance(1, 5)
    t.eq(#lines(c), 1, "once")
    c.setMerchantOpen(false)
    at(c, true, 900, 10500)
    t.eq(#lines(c), 2, "the next visit")
    t.ok((lines(c)[2] or ""):find("costs 9s;", 1, true) ~= nil, "read again")
    c.setMerchantOpen(false)
    addon.settings:set(addon.RepairCost.SETTING, false)
    at(c, true, 900, 10500)
    t.eq(#lines(c), 2, "off")
    t.eq(addon.problems:count(), before)
end

tests["repair cost: the line is words only: no figure without a cost"] = function(t)
    local L = ns.RepairCost.Line
    t.eq(L(nil, 5), nil)
    t.eq(L(0, 5), nil)
    t.eq(L(-3, 5), nil)
    t.eq(L(1.5, 5), nil)
    t.eq(L("12", 5), nil)
    t.eq(L(100, 100), "Repairing everything here costs 1s; you have 1s. Press the merchant's Repair All button.")
end

return tests
