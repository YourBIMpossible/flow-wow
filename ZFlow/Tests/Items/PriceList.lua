local _, ns = ...
-- Parity row E-24, the data half (lead section 752): the "Auction prices"
-- view's list and its search, as Flow's Modules/Items/Banker.lua
-- (B.PriceRows :662-674, B.Filter :692-700, the "prices" header lines
-- :718-737). From Items/AuctionLog.lua's saved realm table ([itemID] =
-- { h = { at, price, ... } }). Made-up items and prices. Not tested in game.
-- Fails before: no such file.
local tests = {}

local function PL() return ns.PriceList end

local NAMES = { [2589] = "Linen Cloth", [2592] = "Wool Cloth", [769] = "Chunk of Boar Meat" }
local function nameOf(id) return NAMES[id] end

local REALM = {
    [2589] = { h = { 100, 12, 200, 10 } },     -- the last look: 10 copper at 200
    [2592] = { h = { 150, 40 } },
    [769] = { h = { 50, 7 } },
    [9999] = { h = {} },                         -- no look: no row
    bad = { h = { 1, 2 } },                      -- not an item number: no row
}

tests["price list: one row an item, the price the last look saw, by name"] = function(t)
    t.eq(type(PL()), "table", "loaded")
    if type(PL()) ~= "table" then return end
    t.eq(PL().Rows(REALM, nameOf), {
        { id = 769, name = "Chunk of Boar Meat", price = 7, at = 50 },
        { id = 2589, name = "Linen Cloth", price = 10, at = 200 },
        { id = 2592, name = "Wool Cloth", price = 40, at = 150 },
    })
    local unnamed = PL().Rows({ [5] = { h = { 1, 3 } } }, function() return nil end)
    t.eq(unnamed[1].name, "item 5", "a name not read: the item number, as Flow")
    t.eq(PL().Rows(nil, nameOf), {})
end

tests["price list: the search finds any part of the name, any case; no text, all"] = function(t)
    if type(PL()) ~= "table" then return t.ok(false, "not loaded") end
    local rows = PL().Rows(REALM, nameOf)
    t.eq(#PL().Filter(rows, "CLOTH"), 2)
    t.eq(PL().Filter(rows, "  boar "), { rows[1] }, "spaces around it trimmed")
    t.eq(#PL().Filter(rows, ""), 3)
    t.eq(#PL().Filter(rows, nil), 3)
    t.eq(PL().Filter(rows, "zz"), {})
    t.eq(PL().Filter(rows, "("), {}, "a pattern letter is plain text")
end

tests["price list: the line above the list, as Flow's"] = function(t)
    if type(PL()) ~= "table" then return t.ok(false, "not loaded") end
    t.eq(PL().Header(0, 0, ""), PL().NONE)
    t.eq(PL().Header(3, 3, ""), "The cheapest buyout seen, for 3 item(s). Search below.")
    t.eq(PL().Header(2, 3, "cloth"), "2 of 3 item(s) with \"cloth\" in the name (the cheapest buyout seen):")
end

return tests
