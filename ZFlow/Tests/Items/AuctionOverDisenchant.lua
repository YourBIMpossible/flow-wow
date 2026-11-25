local _, ns = ...

-- Tests for ZFlow/Items/AuctionOverDisenchant.lua (E-new-8, lead section
-- 809a): gear you could disenchant, with a price seen in your own auction
-- searches clearly worth more, gets a line saying so. The rule is Flow's
-- (branch w1-safety, commit ff05c4eb, Modules/Items/Disposition.lua:880-900,
-- AuctionBeatsDisenchant): after the 5% cut and a fee of 30% of the vendor
-- price, at least 3 times the vendor price and at least 1 gold. Look only.
--
-- Red before the code: ns.AuctionOverDE does not exist, so every test fails.

local tests = {}

local function A() return ns.AuctionOverDE end

-- Green gear, a vendor price of 10s, seen at 2g: well past the margin.
local function facts(over)
    local f = { quality = 2, classID = 4, sellPrice = 1000, seen = 20000, enchanting = true, bound = false }
    for k, v in pairs(over or {}) do f[k] = v end
    return f
end

tests["auction over disenchant: the module and its numbers exist"] = function(t)
    t.eq(type(A()), "table", "ns.AuctionOverDE")
    if type(A()) ~= "table" then return end
    t.eq({ A().CUT, A().FEE, A().OVER, A().MIN }, { 0.05, 0.30, 3, 10000 })
    t.eq(type(A().Beats), "function")
    t.eq(type(A().Line), "function")
    t.eq(type(A().Declare), "function")
end

tests["auction over disenchant: the margin, after the cut and the fee"] = function(t)
    if type(A()) ~= "table" then return t.ok(false, "ns.AuctionOverDE") end
    -- vendor 1000: net = seen * 0.95 - 300; needs net >= 3000 and >= 10000.
    t.eq(A().Beats(10843, 1000), true, "net 10000.85: just past 1 gold")
    t.eq(A().Beats(10842, 1000), false, "net 9999.9: under 1 gold")
    -- vendor 5000: net = seen * 0.95 - 1500; needs net >= 15000.
    t.eq(A().Beats(17369, 5000), true, "net 15000.55: three times the vendor")
    t.eq(A().Beats(17368, 5000), false, "net 14999.6: under three times the vendor")
    t.eq(A().Beats(10527, nil), true, "no vendor price: counted as none, 1 gold still needed")
    t.eq(A().Beats(10526, 0), false)
    t.eq(A().Beats(0, 0), false)
    t.eq(A().Beats(nil, 100), false, "no price seen")
end

tests["auction over disenchant: tradeable gear gets the plain line"] = function(t)
    if type(A()) ~= "table" then return t.ok(false, "ns.AuctionOverDE") end
    local line = A().Line(facts())
    t.eq(type(line), "string")
    t.ok(type(line) == "string" and line:find("2g", 1, true) ~= nil, tostring(line))
    t.ok(type(line) == "string" and line:find("if tradeable", 1, true) == nil, "bound false: no if")
    t.ok(A().Line(facts({ classID = 2 })) ~= nil, "a weapon is gear too")
    t.ok(A().Line(facts({ quality = 4 })) ~= nil, "epic too")
end

tests["auction over disenchant: not known whether bound says if tradeable"] = function(t)
    if type(A()) ~= "table" then return t.ok(false, "ns.AuctionOverDE") end
    local f = facts()
    f.bound = nil
    local line = A().Line(f)
    t.ok(type(line) == "string" and line:find("if tradeable", 1, true) ~= nil, tostring(line))
    line = A().Line(facts({ bound = "unread" }))
    t.ok(type(line) == "string" and line:find("if tradeable", 1, true) ~= nil, "not a yes or no: not known")
end

tests["auction over disenchant: no line when it does not apply"] = function(t)
    if type(A()) ~= "table" then return t.ok(false, "ns.AuctionOverDE") end
    t.eq(A().Line(facts({ bound = true })), nil, "bound: it cannot be sold")
    t.eq(A().Line(facts({ quality = 1 })), nil, "white: the rule starts at green")
    t.eq(A().Line(facts({ classID = 7 })), nil, "not gear")
    t.eq(A().Line(facts({ enchanting = false })), nil, "no Enchanting: no disenchant to beat")
    local f = facts()
    f.enchanting = nil
    t.eq(A().Line(f), nil, "Enchanting not known: no line")
    f = facts()
    f.seen = nil
    t.eq(A().Line(f), nil, "no price seen")
    t.eq(A().Line(facts({ seen = 1000 })), nil, "seen, but not clearly worth more")
    t.eq(A().Line(nil), nil)
end

-- Through the tooltip of a bag item: the add-on booted on the fake client.
local INFO = {
    [15011] = { name = "Lupine Cuffs", quality = 2, sellPrice = 1000, classID = 4 },
    [2589] = { name = "Linen Cloth", quality = 1, sellPrice = 13, classID = 7 },
}

local function start(bound)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setRealm("Old Blanchy")
    c.setFaction("Horde")
    c.setClock(5000)
    c.setItemInfo(INFO)
    c.setProfessions({ "Enchanting", "Tailoring" })
    c.setBagItems({ { item = 15011, count = 1 }, { item = 2589, count = 20 } })
    c.setBagBound(15011, bound)
    local k = ns.Kernel({}, c)
    ns.DispositionTip.Declare(k)
    local api = A().Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    -- Two looks: 90s at 1000, then 2g 50s at 4000; the latest counts.
    k.store:set("account", ns.AuctionLog.PATH .. ".Old Blanchy-Horde",
        { [15011] = { h = { 1000, 9000, 4000, 25000 } } })
    return k, c, api
end

local function find(lines, needle)
    for _, l in ipairs(lines or {}) do
        if type(l.text) == "string" and l.text:find(needle, 1, true) then return l.text end
    end
    return nil
end

tests["auction over disenchant: the bag item's tooltip says it, from the latest look"] = function(t)
    if type(A()) ~= "table" then return t.ok(false, "ns.AuctionOverDE") end
    local _, c, api = start(false)
    t.eq(api.hooked(), true)
    local text = find(c.showItemTooltip("item:15011"), "disenchant")
    t.ok(text ~= nil and text:find("2g 50s", 1, true) ~= nil, tostring(text))
    t.ok(text ~= nil and text:find("if tradeable", 1, true) == nil, "bound false")
    t.eq(find(c.showItemTooltip("item:2589"), "disenchant"), nil, "cloth is not gear")
end

tests["auction over disenchant: through the tooltip, bound or not known"] = function(t)
    if type(A()) ~= "table" then return t.ok(false, "ns.AuctionOverDE") end
    local _, c = start(true)
    t.eq(find(c.showItemTooltip("item:15011"), "disenchant"), nil, "bound: no line")
    local _, c2 = start(nil)
    local text = find(c2.showItemTooltip("item:15011"), "disenchant")
    t.ok(text ~= nil and text:find("if tradeable", 1, true) ~= nil, tostring(text))
    c2.setProfessions({ "Tailoring" })
    t.eq(find(c2.showItemTooltip("item:15011"), "disenchant"), nil, "no Enchanting: no line")
end

return tests
