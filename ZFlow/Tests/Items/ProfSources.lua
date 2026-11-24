local _, ns = ...

-- Tests for ZFlow/Items/ProfSources.lua (lead section 382, P-COACH C3):
-- where a material the plan lacks can come from, in order: a node seen on
-- this map, a vendor price seen, else the auction house as text. And
-- ProfPlan.Plan using it when the bags and bank are short. Pure: every
-- item, node, price and place here is made up.
--
-- Red before the code: ns.ProfSources does not exist, so every test fails.

local tests = {}

local function S() return ns.ProfSources end

-- Items: 2 Test Bar, 3 Test Cloth, 4 Test Thread, 5 Test Ore, 6 Testbloom.
local NAMES = { [2] = "Test Bar", [3] = "Test Cloth", [4] = "Test Thread", [5] = "Test Ore", [6] = "Testbloom" }
local VENDOR = { [4] = 50 }

local function input(over)
    local i = {
        here = { map = 1429, x = 0.5, y = 0.5 },
        nodes = {
            { kind = "ore", node = "Test Vein", map = 1429, x = 0.9, y = 0.9 },
            { kind = "ore", node = "Test Vein", map = 1429, x = 0.6, y = 0.5 },
            { kind = "herb", node = "Testbloom", map = 1429, x = 0.1, y = 0.1 },
        },
        name = function(item) return NAMES[item] end,
        vendorPrice = function(item) return VENDOR[item] end,
    }
    for k, v in pairs(over or {}) do i[k] = v end
    return i
end

tests["prof sources: the module and its words exist"] = function(t)
    t.eq(type(S()), "table", "ns.ProfSources")
    if type(S()) ~= "table" then return end
    t.eq(type(S().For), "function", "ProfSources.For")
    t.eq(type(S().Gives), "function", "ProfSources.Gives")
end

tests["prof sources: a node gives the item of its name; a vein or deposit gives ore"] = function(t)
    if type(S()) ~= "table" then return t.ok(false, "ns.ProfSources") end
    t.eq(S().Gives("Testbloom", "Testbloom"), true)
    t.eq(S().Gives("Test Vein", "Test Ore"), true)
    t.eq(S().Gives("Test Deposit", "Test Ore"), true)
    t.eq(S().Gives("Test Vein", "Test Bar"), false)
    t.eq(S().Gives("Other Vein", "Test Ore"), false)
    t.eq(S().Gives(nil, "Test Ore"), false)
end

tests["prof sources: a node seen on this map: gather at the nearest"] = function(t)
    if type(S()) ~= "table" then return t.ok(false, "ns.ProfSources") end
    local s = S().For(input(), 5, 4)
    t.eq(s and s.kind, "gather")
    t.eq(s and s.item, 5)
    t.eq(s and s.count, 4)
    t.eq(s and s.target, { map = 1429, x = 0.6, y = 0.5 }, "the nearer vein")
    t.eq(s and s.text, "Gather 4 Test Ore (Test Vein)")
    s = S().For(input({ here = { map = 1430, x = 0.5, y = 0.5 } }), 5, 4)
    t.eq(s and s.kind, "buy_auction", "a node on another map is not here")
end

tests["prof sources: no node, a vendor price seen: buy from a vendor, text only"] = function(t)
    if type(S()) ~= "table" then return t.ok(false, "ns.ProfSources") end
    local s = S().For(input(), 4, 3)
    t.eq(s and s.kind, "buy_vendor")
    t.eq(s and s.target, nil, "the vendor's place is not saved with the price")
    t.eq(s and s.text, "Buy 3 Test Thread from a vendor (50c each)")
end

tests["prof sources: nothing else: the auction house, as text"] = function(t)
    if type(S()) ~= "table" then return t.ok(false, "ns.ProfSources") end
    local s = S().For(input(), 3, 6)
    t.eq(s and s.kind, "buy_auction")
    t.eq(s and s.target, nil)
    t.eq(s and s.text, "Buy 6 Test Cloth at the auction house")
    t.eq(S().For(input(), 3, 0), nil, "nothing short")
    t.eq(S().For(nil, 3, 2) and S().For(nil, 3, 2).kind, "buy_auction", "no reading: still the auction text")
end

tests["prof sources: the plan names where the short materials come from"] = function(t)
    if type(S()) ~= "table" or type(ns.ProfPlan) ~= "table" then return t.ok(false, "ns.ProfSources") end
    local plan = ns.ProfPlan.Plan({
        prof = "Tailoring", skill = 50, max = 75,
        book = { ["Test Bolt"] = { profession = "Tailoring", makes = 53, mats = { [3] = 2, [4] = 1 } } },
        colours = { ["Test Bolt"] = { optimal = { lo = 50, hi = 52 } } },
        bags = { [3] = 2 }, bank = {},
        name = function(item) return NAMES[item] end,
        vendorPrice = function(item) return VENDOR[item] end,
    })
    local kinds = {}
    for i, s in ipairs(plan) do kinds[i] = s.kind end
    t.eq(kinds, { "buy_auction", "buy_vendor", "craft" }, "three bolts: 4 more cloth, 3 thread")
    t.eq(plan[1] and plan[1].count, 4)
    t.eq(plan[2] and plan[2].count, 3)
    t.eq(plan[3] and plan[3].count, 3)
end

tests["prof sources: a name not read yet is never a number (section 383)"] = function(t)
    if type(S()) ~= "table" then return t.ok(false, "ns.ProfSources") end
    local s = S().For(input({ name = function() return nil end }), 3, 6)
    t.eq(s and s.text, "Buy 6 of the materials at the auction house")
end

return tests
