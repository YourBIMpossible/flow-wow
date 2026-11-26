local _, ns = ...

-- The Deals tab's panel (E-38): the session's deals from Items/Trader.lua
-- as kit parts — one row a deal with its cost and gain, the data's own
-- advice lines under it, and one empty line before any deal. The tab on
-- Blizzard's auction frame is the lead's CLIENT NEED; this file tests the
-- parts and the module surface the tab reads (Parts, On). Fake client.
-- Look only: clicking a row does nothing, and nothing here buys.
-- Not tested in game.
--
-- Fails before the change: ns.DealsPanel is nil.

local DP = ns.DealsPanel
local T = ns.Trader
local tests = {}

local VENDOR = { id = 2589, name = "Linen Cloth", kind = "vendor", qty = 3, cost = 30, gain = 90, limit = 40 }
local RESELL = { id = 858, name = "Lesser Healing Potion", kind = "resell", qty = 1, cost = 100, gain = 400, limit = 250, usual = 500 }

local function byKey(kids, key)
    for _, p in ipairs(kids or {}) do
        if p.key == key then return p end
    end
    return nil
end

tests["deals parts: a deal row carries its cost and gain, with the advice under it"] = function(t)
    local kids = DP.Parts({ VENDOR, RESELL }, ns.Prices.Coin)
    local first = byKey(kids, "deal1")
    t.eq(first and first.text, "Linen Cloth x3", "the name, with how many")
    t.ok(first and first.sub and first.sub:find(ns.Prices.Coin(30), 1, true) ~= nil, "what it costs: " .. tostring(first and first.sub))
    t.ok(first and first.sub and first.sub:find(ns.Prices.Coin(90), 1, true) ~= nil, "and the gain")
    local tips = T.TipLines(VENDOR, ns.Prices.Coin)
    t.eq(byKey(kids, "deal1tip1").text, tips[1], "the data's own advice, in its words")
    local second = byKey(kids, "deal2")
    t.eq(second and second.text, "Lesser Healing Potion", "one of it: no count")
    local rtips = T.TipLines(RESELL, ns.Prices.Coin)
    t.eq(byKey(kids, "deal2tip1").text, rtips[1])
    t.eq(byKey(kids, "deal2tip2").text, rtips[2], "both of a resell deal's advice lines")
    t.ok(ns.Kit.Window({ id = "dealsPanel", title = "x", children = kids }) ~= nil, "the kit takes the parts")
end

tests["deals parts: no deals is the one empty line, and the half follows the constant"] = function(t)
    local kids = DP.Parts({}, ns.Prices.Coin)
    t.eq(#kids, 1)
    t.eq(kids[1].text, DP.EmptyText())
    t.ok(kids[1].text:find("half its usual price", 1, true) ~= nil,
        "Trader.DEAL is " .. tostring(T.DEAL) .. ": the line says half")
    t.eq(DP.Parts(nil, ns.Prices.Coin)[1].text, DP.EmptyText(), "no list reads the same")
end

tests["deals module: Parts reads the trader's deals; On follows its switch"] = function(t)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    T.Declare(k, ns.diag)
    local api = DP.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    t.eq(api.on(), true, "the trader runs unless its switch says nothing (trader.off, default false)")
    local kids = api.parts()
    t.eq(kids and kids[1] and kids[1].text, DP.EmptyText(), "no searches yet: the empty line")
    k.settings:set(T.SETTING, true)
    t.eq(api.on(), false, "the switch on: no tab")
    t.eq(api.parts(), nil, "and no parts")
end

return tests
