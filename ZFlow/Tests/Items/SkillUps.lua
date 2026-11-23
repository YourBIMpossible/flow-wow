local _, ns = ...

-- Tests for ZFlow/Items/SkillUps.lua (P-PROF, rows N22, N23). Pure: the
-- recipes, colours, mats and bags are made up here; the names are invented.

local U = ns.SkillUps
local tests = {}

tests["skill ups: the window colour says how sure a point is"] = function(t)
    t.eq(U.Chance("optimal"), "sure")
    t.eq(U.Chance("medium"), "maybe")
    t.eq(U.Chance("easy"), "maybe")
    t.eq(U.Chance("trivial"), "none")
    t.eq(U.Chance("difficult"), "none")
    t.eq(U.Chance(nil), "unknown", "no colour read")
    t.eq(U.Chance("purple"), "unknown", "a word the window never gave")
end

tests["skill ups: what the window showed widens the span of each colour"] = function(t)
    local seen = U.Observe({}, { { key = 11, difficulty = "optimal" }, { key = 12, difficulty = "easy" } }, 40)
    t.eq(seen, { [11] = { optimal = { lo = 40, hi = 40 } }, [12] = { easy = { lo = 40, hi = 40 } } })
    U.Observe(seen, { { key = 11, difficulty = "optimal" } }, 44)
    U.Observe(seen, { { key = 11, difficulty = "medium" } }, 46)
    U.Observe(seen, { { key = 11, difficulty = "optimal" } }, 38)
    t.eq(seen[11], { optimal = { lo = 38, hi = 44 }, medium = { lo = 46, hi = 46 } })
    U.Observe(seen, { { key = 13 }, { difficulty = "optimal" }, { key = 14, difficulty = "purple" } }, 50)
    t.eq(seen[13], nil, "no colour: nothing seen")
    t.eq(seen[14], nil, "an unknown colour: nothing seen")
    t.eq(U.Observe(seen, { { key = 11, difficulty = "optimal" } }, nil), seen, "no skill read: unchanged")
    t.eq(seen[11].optimal, { lo = 38, hi = 44 })
end

tests["skill ups: sure points left come only from the orange span seen"] = function(t)
    local seen = { [11] = { optimal = { lo = 38, hi = 44 } }, [12] = { easy = { lo = 40, hi = 40 } } }
    t.eq(U.SureLeft(seen, 11, 40), 5, "orange seen up to 44: 40 to 44")
    t.eq(U.SureLeft(seen, 11, 44), 1)
    t.eq(U.SureLeft(seen, 11, 45), nil, "past what was seen: not known")
    t.eq(U.SureLeft(seen, 11, 30), nil, "below what was seen: not known")
    t.eq(U.SureLeft(seen, 12, 40), nil, "never seen orange")
    t.eq(U.SureLeft(seen, 99, 40), nil)
    t.eq(U.SureLeft(nil, 11, 40), nil)
end

tests["skill ups: recipes rank sure, then maybe, then unknown; cheapest first; grey dropped"] = function(t)
    local ranked = U.Rank({
        { key = 1, name = "Grey Hat", difficulty = "trivial", cost = 1 },
        { key = 2, name = "Green Belt", difficulty = "easy", cost = 5 },
        { key = 3, name = "Orange Boots", difficulty = "optimal", cost = 90 },
        { key = 4, name = "Orange Cap", difficulty = "optimal", cost = 30 },
        { key = 5, name = "Odd Ring", cost = 2 },
        { key = 6, name = "Orange Cloak", difficulty = "optimal" },
        { key = 7, name = "Yellow Vest", difficulty = "medium", cost = 5 },
        { key = 8, name = "Red Robe", difficulty = "difficult", cost = 1 },
    })
    local keys = {}
    for i, r in ipairs(ranked) do keys[i] = r.key end
    t.eq(keys, { 4, 3, 6, 2, 7, 5 })
    t.eq(ranked[1].chance, "sure")
    t.eq(ranked[4].chance, "maybe")
    t.eq(ranked[6].chance, "unknown")
end

local MATS = { [1] = { [100] = 2 }, [2] = { [100] = 1, [200] = 1 }, [3] = { [300] = 1 } }

local function opts(have, extra)
    local o = {
        mats = function(row) return MATS[row.key] end,
        have = function(item) return have[item] end,
        skill = 40, max = 75, seen = {},
    }
    for k, v in pairs(extra or {}) do o[k] = v end
    return o
end

tests["skill ups: what the bags make is counted in rank order, mats used once"] = function(t)
    local ranked = U.Rank({
        { key = 1, name = "A", difficulty = "optimal", cost = 1 },
        { key = 2, name = "B", difficulty = "easy", cost = 2 },
    })
    local seen = { [1] = { optimal = { lo = 30, hi = 49 } } }
    local r = U.FromBags(ranked, opts({ [100] = 7, [200] = 5 }, { seen = seen }))
    t.eq(r.sure, 3, "three crafts of A, each sure while orange up to 49")
    t.eq(r.maybe, 1, "one B with the cloth left")
    t.eq(r.crafts, { { key = 1, n = 3, chance = "sure" }, { key = 2, n = 1, chance = "maybe" } })
end

tests["skill ups: sure points never pass what was seen orange, nor the cap"] = function(t)
    local ranked = U.Rank({ { key = 1, name = "A", difficulty = "optimal", cost = 1 } })
    local r = U.FromBags(ranked, opts({ [100] = 20 }))
    t.eq(r.sure, 1, "orange now, no span seen: only the first craft is sure")
    t.eq(r.maybe, 9)
    local seen = { [1] = { optimal = { lo = 40, hi = 42 } } }
    r = U.FromBags(ranked, opts({ [100] = 20 }, { seen = seen }))
    t.eq(r.sure, 3, "orange seen to 42: 40, 41, 42")
    t.eq(r.maybe, 7)
    r = U.FromBags(ranked, opts({ [100] = 20 }, { seen = { [1] = { optimal = { lo = 1, hi = 99 } } }, skill = 73 }))
    t.eq(r.sure, 2, "73 to the cap of 75")
    t.eq(r.maybe, 0, "nothing past the cap")
end

tests["skill ups: a recipe whose mats are not read, or not in the bags, makes nothing"] = function(t)
    local ranked = U.Rank({
        { key = 3, name = "C", difficulty = "optimal", cost = 1 },
        { key = 9, name = "D", difficulty = "optimal", cost = 1 },
    })
    local r = U.FromBags(ranked, opts({ [300] = nil }))
    t.eq(r, { sure = 0, maybe = 0, crafts = {} })
end

tests["skill ups: the goal says what is left and when it is past the cap"] = function(t)
    t.eq(U.Goal(40, 75, 60), { need = 20, overCap = false })
    t.eq(U.Goal(40, 75, 40), { need = 0, overCap = false })
    t.eq(U.Goal(40, 75, 30), { need = 0, overCap = false })
    t.eq(U.Goal(40, 75, 100), { need = 60, overCap = true })
    t.eq(U.Goal(40, 75, nil), nil)
    t.eq(U.Goal(nil, 75, 60), nil)
end

return tests
