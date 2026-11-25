local _, ns = ...

-- Parity row E-38, the data half (lead section 755): the rows of the
-- auction house's deals list, from the trader's deals (Items/Trader.lua
-- T.Deals, the "Deal:" logic), as Flow's Modules/Items/Trader.lua T:Fill
-- (:510-546): the note above the list, the rows (the most gain first), and
-- how many more there are. Pure; made-up deals. Not tested in game.
-- Fails before: no file.
local tests = {}

local function TR() return ns.TraderRows end

local function deals(n)
    local out = {}
    for i = 1, n do
        out[i] = { id = i, name = "Item " .. i, kind = (i % 2 == 0) and "resell" or "vendor", qty = 1, cost = 10,
                   gain = 1000 - i, limit = 20, usual = 40 }
    end
    return out
end

tests["trader rows: the deals, the most gain first, then how many more"] = function(t)
    t.eq(type(TR()), "table", "loaded")
    if type(TR()) ~= "table" then return end
    local list = deals(TR().ROWS + 2)
    local rows, more = TR().Rows(list)
    t.eq(#rows, TR().ROWS)
    t.eq(more, 2)
    t.eq(rows[1].id, 1, "the most gain first")
    t.eq(rows[1].kind, "vendor")
    t.eq(rows[2].kind, "resell")
    t.eq(TR().Foot(more), "2 more deal(s) not shown.", "our own words (section 757)")
    t.eq(TR().Foot(0), "")
    local mixed = { { id = 5, gain = 60, kind = "vendor", name = "B" }, { id = 4, gain = 90, kind = "resell", name = "A" },
                    "not a row", { id = 3, gain = 90, kind = "vendor", name = "C" } }
    local r2 = TR().Rows(mixed)
    t.eq(#r2, 3, "a value that is no row is left out")
    t.eq(r2[1].id, 3, "same gain: by id")
    t.eq(r2[2].id, 4)
    t.eq(r2[3].id, 5)
    local r3, m3 = TR().Rows(nil)
    t.eq(#r3, 0)
    t.eq(m3, 0)
end

tests["trader rows: the note above the list, as Flow's"] = function(t)
    if type(TR()) ~= "table" then return t.ok(false, "not loaded") end
    t.eq(TR().Note(0, false), TR().NOT_FOLLOWED, "searches not followed: no list")
    t.eq(TR().Note(0, true), TR().NONE)
    t.eq(TR().Note(3, true), TR().SOME:format(3))
    t.eq(TR().Note(3, false), TR().SOME:format(3), "deals found say so")
end

return tests
