local _, ns = ...
-- Tests for ZFlow/Items/LootLeft.lua (E-45): after looting, one chat line
-- saying how many junk (grey, quality 0) items were left in the loot window.
-- Flow: Modules/Items/LootFilter.lua:176 (told once per session, :73).
-- Made-up items. Not tested in game.
local tests = {}

local function L() return ns.LootLeft end

tests["loot left: only quality 0 is junk, counted per slot"] = function(t)
    if type(L()) ~= "table" then t.ok(false, "no ns.LootLeft") return end
    t.eq(L().Junk({
        { item = "item:97", count = 3, quality = 0 },
        { item = "item:98", count = 1, quality = 0 },
        { item = "item:2318", count = 2, quality = 1 },
        { item = "item:3000", count = 1 },            -- quality not read: not junk
    }), 2)
    t.eq(L().Junk({}), 0)
    t.eq(L().Junk(nil), 0, "nothing read")
    t.eq(L().Junk({ "bad", { quality = "0" } }), 0, "bad entries are skipped")
end

tests["loot left: the line, one and many"] = function(t)
    if type(L()) ~= "table" then t.ok(false, "no ns.LootLeft") return end
    t.eq(L().Line(1), "left 1 grey item in the loot window.")
    t.eq(L().Line(3), "left 3 grey items in the loot window.")
    t.eq(L().Line(0), nil, "none left: nothing said")
    t.eq(L().Line(nil), nil)
end

tests["loot left: skin warning only with Skinning and something left"] = function(t)
    if type(L()) ~= "table" or type(L().SkinWarning) ~= "function" then t.ok(false, "no LootLeft.SkinWarning") return end
    local left = { { item = "item:2318", count = 2, quality = 1 } }
    t.eq(L().SkinWarning(left, { Skinning = true }), L().SKIN_WARNING)
    t.eq(L().SkinWarning({}, { Skinning = true }), nil, "nothing left")
    t.eq(L().SkinWarning(left, { Mining = true }), nil, "no Skinning")
    t.eq(L().SkinWarning(left, nil), nil, "professions not read")
    t.eq(L().SkinWarning(nil, { Skinning = true }), nil)
end

return tests
