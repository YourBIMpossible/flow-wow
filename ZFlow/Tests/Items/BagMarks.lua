local _, ns = ...

-- Tests for ZFlow/Items/BagMarks.lua (G4, the bag slot marks only; the
-- tooltip line is Items/TooltipDisposition.lua's). Made-up items only.

local tests = {}

local function B() return ns.BagMarks end

tests["bag marks: a quest item is marked quest"] = function(t)
    t.eq(B().KindOf({ action = "keep", rule = "quest", basis = "fact" }), "quest")
    t.eq(B().KindOf({ action = "keep", rule = "questNeeds", basis = "fact" }), "quest")
end

tests["bag marks: junk to sell, an upgrade, a kept material"] = function(t)
    t.eq(B().KindOf({ action = "sell", rule = "junk" }), "sell")
    t.eq(B().KindOf({ action = "equip", rule = "upgrade" }), "upgrade")
    t.eq(B().KindOf({ action = "keep", rule = "professionMaterial" }), "material")
    t.eq(B().KindOf({ action = "keep", rule = "professionTool" }), "material")
end

tests["bag marks: a split decision that sells the rest is marked sell"] = function(t)
    t.eq(B().KindOf({ action = "keep", rule = "held", count = 2,
        rest = { action = "sell", rule = "junk", count = 3 } }), "sell")
end

tests["bag marks: no opinion, a plain keep, or not a decision: no mark"] = function(t)
    t.eq(B().KindOf({ action = "keep", rule = "notGear" }), nil)
    t.eq(B().KindOf({ action = "keep", basis = "unknown" }), nil)
    t.eq(B().KindOf({ action = "auction", rule = "x" }), nil)
    t.eq(B().KindOf(nil), nil)
    t.eq(B().KindOf("sell"), nil)
end

tests["bag marks: Marks maps each slot to its mark"] = function(t)
    local info = {
        [1001] = { name = "Rusty Gear", quality = 0, sellPrice = 5, classID = 15 },
        [1002] = { name = "Odd Letter", quality = 1, sellPrice = 0, classID = 12 },
        [1003] = { name = "Plain Cloth", quality = 1, sellPrice = 10, classID = 7 },
    }
    local function read(item) return info[tonumber(tostring(item):match("%d+"))] end
    local slots = {
        { bag = 0, slot = 1, item = 1001, count = 2 },
        { bag = 0, slot = 2, item = 1002, count = 1 },
        { bag = 1, slot = 4, item = 1003, count = 3 },
    }
    local marks, n = B().Marks(slots, read, {})
    t.eq(marks, { [0] = { [1] = "sell", [2] = "quest" } })
    t.eq(n, 2)
    local m2 = B().Marks(slots, read, { materials = { [1003] = { { prof = "Tailoring" } } } })
    t.eq(m2[1], { [4] = "material" })
    t.eq(B().Marks(nil, read, {}), nil, "bags not read: nil, not an empty table")
end

tests["bag marks: an item read that raises gives no mark and stops nothing"] = function(t)
    local function read(item)
        if item == 1 then error("boom") end
        return { name = "Grey", quality = 0, sellPrice = 1, classID = 15 }
    end
    local marks = B().Marks({ { bag = 0, slot = 1, item = 1 }, { bag = 0, slot = 2, item = 2 } }, read, {})
    t.eq(marks, { [0] = { [2] = "sell" } })
end

tests["bag marks: every kind has a game texture and a word"] = function(t)
    for _, kind in ipairs({ "quest", "sell", "upgrade", "material" }) do
        t.ok(type(B().TEXTURE[kind]) == "string" and B().TEXTURE[kind]:sub(1, 10) == "Interface\\", kind)
        t.ok(type(B().WORD[kind]) == "string", kind)
    end
end

return tests
