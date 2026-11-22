local _, ns = ...

-- Tests for ZFlow/Gear/Score.lua. Pure: items, what is worn and the weights
-- are tables made here. Whole numbers only, so every sum is exact.

local S = ns.GearScore
local tests = {}

local W = { Strength = 2, Agility = 1, Stamina = 1 }

local function item(kind, stats)
    return { kind = kind, stats = stats }
end

-- Score ------------------------------------------------------------------

tests["gear score: the sum of each stat times its weight"] = function(t)
    local n, why = S.Score({ Strength = 10, Agility = 4, Stamina = 3 }, W)
    t.eq(n, 27)
    t.eq(why, nil)
    t.eq(S.Score({}, W), 0, "an item with no stats is a known 0")
end

tests["gear score: a stat the weights do not name adds nothing"] = function(t)
    t.eq(S.Score({ Strength = 5, Spirit = 100 }, W), 10)
end

tests["gear score: no weights is no score, with the reason"] = function(t)
    local n, why = S.Score({ Strength = 10 }, nil)
    t.eq(n, nil, "not 0")
    t.eq(why, S.REASON.weights)
    n, why = S.Score({ Strength = 10 }, {})
    t.eq(n, nil, "an empty table is no weights either")
    t.eq(why, S.REASON.weights)
    n, why = S.Score({ Strength = 10 }, "dps")
    t.eq(n, nil)
    t.eq(why, S.REASON.weights)
end

tests["gear score: a weight that is no number is no score"] = function(t)
    local nan = 0 / 0
    for _, bad in ipairs({ "2", true, nan, math.huge }) do
        local n, why = S.Score({ Strength = 10 }, { Strength = bad, Agility = 1 })
        t.eq(n, nil, tostring(bad))
        t.eq(why, S.REASON.weight .. ": Strength")
    end
end

tests["gear score: no stats is no score, never 0"] = function(t)
    local n, why = S.Score(nil, W)
    t.eq(n, nil)
    t.eq(why, S.REASON.stats)
    n, why = S.Score("Strength 10", W)
    t.eq(n, nil)
    t.eq(why, S.REASON.stats)
end

tests["gear score: a weighted stat that is not known is no score, and is named"] = function(t)
    local nan = 0 / 0
    for _, unknown in ipairs({ false, "?", nan, math.huge }) do
        local n, why = S.Score({ Strength = unknown, Agility = 4 }, W)
        t.eq(n, nil, "not counted as 0: " .. tostring(unknown))
        t.eq(why, S.REASON.stat .. ": Strength")
    end
    local n, why = S.Score({ Stamina = false, Agility = false, Strength = 1 }, W)
    t.eq(n, nil)
    t.eq(why, S.REASON.stat .. ": Agility", "the first in name order")
end

tests["gear score: a stat that is not known and not weighted does not matter"] = function(t)
    t.eq(S.Score({ Strength = 3, Spirit = false }, W), 6)
end

tests["gear score: a negative weight or stat counts as it is"] = function(t)
    t.eq(S.Score({ Strength = 5, Agility = -2 }, { Strength = 1, Agility = 3 }), -1)
    t.eq(S.Score({ Strength = 5 }, { Strength = -1 }), -5)
end

-- Compare: one slot ---------------------------------------------------------

tests["gear compare: an upgrade, the same and a worse item, with the slot named"] = function(t)
    local worn = { head = item("INVTYPE_HEAD", { Strength = 5 }) }
    local up = S.Compare(item("INVTYPE_HEAD", { Strength = 8 }), worn, W)
    t.eq({ up.verdict, up.delta, up.slot, up.score, up.against }, { "upgrade", 6, "head", 16, 10 })
    t.eq(up.reason, S.REASON.upgrade)
    local same = S.Compare(item("INVTYPE_HEAD", { Strength = 5 }), worn, W)
    t.eq({ same.verdict, same.delta, same.slot }, { "same", 0, "head" })
    t.eq(same.reason, S.REASON.same)
    local worse = S.Compare(item("INVTYPE_HEAD", { Strength = 1 }), worn, W)
    t.eq({ worse.verdict, worse.delta, worse.slot }, { "worse", -8, "head" })
    t.eq(worse.reason, S.REASON.worse)
end

tests["gear compare: a slot known to be empty counts as nothing worn"] = function(t)
    local r = S.Compare(item("INVTYPE_HEAD", { Strength = 2 }), { head = false }, W)
    t.eq({ r.verdict, r.delta, r.slot, r.against }, { "upgrade", 4, "head", 0 })
end

tests["gear compare: a slot nobody read is no recommendation, not an empty slot"] = function(t)
    local r = S.Compare(item("INVTYPE_HEAD", { Strength = 2 }), {}, W)
    t.eq(r.verdict, "none")
    t.eq(r.delta, nil)
    t.eq(r.reason, S.REASON.worn .. ": head")
    r = S.Compare(item("INVTYPE_HEAD", { Strength = 2 }), nil, W)
    t.eq(r.verdict, "none")
    t.eq(r.reason, S.REASON.worn .. ": head")
end

tests["gear compare: no weights is no recommendation, with the reason"] = function(t)
    local worn = { head = item("INVTYPE_HEAD", { Strength = 5 }) }
    for _, weights in ipairs({ false, {} }) do
        local r = S.Compare(item("INVTYPE_HEAD", { Strength = 50 }), worn, weights or nil)
        t.eq(r.verdict, "none")
        t.eq(r.delta, nil, "no number at all")
        t.eq(r.reason, S.REASON.weights)
    end
end

tests["gear compare: a stat not known on either item is no recommendation"] = function(t)
    local worn = { head = item("INVTYPE_HEAD", { Strength = 5 }) }
    local r = S.Compare(item("INVTYPE_HEAD", { Strength = false }), worn, W)
    t.eq(r.verdict, "none")
    t.eq(r.reason, S.REASON.stat .. ": Strength")
    r = S.Compare(item("INVTYPE_HEAD", { Strength = 9 }), { head = item("INVTYPE_HEAD", { Agility = false }) }, W)
    t.eq(r.verdict, "none")
    t.eq(r.delta, nil)
    t.eq(r.reason, S.REASON.wornStat .. ": head")
    r = S.Compare(item("INVTYPE_HEAD", { Strength = 9 }), { head = { kind = "INVTYPE_HEAD" } }, W)
    t.eq(r.verdict, "none", "a worn item with no stats read")
    t.eq(r.reason, S.REASON.wornStat .. ": head")
end

tests["gear compare: what cannot be worn, or is of no known kind, is no recommendation"] = function(t)
    for _, c in ipairs({ item("INVTYPE_BAG", { Strength = 9 }), item(nil, { Strength = 9 }),
        item("INVTYPE_TABARD", {}), "a helm" }) do
        local r = S.Compare(c, { head = false }, W)
        t.eq(r.verdict, "none")
        t.eq(r.reason, S.REASON.kind)
    end
end

tests["gear compare: a robe and a chest piece share the chest slot"] = function(t)
    local r = S.Compare(item("INVTYPE_ROBE", { Stamina = 9 }), { chest = item("INVTYPE_CHEST", { Stamina = 4 }) }, W)
    t.eq({ r.verdict, r.delta, r.slot }, { "upgrade", 5, "chest" })
end

-- Compare: two slots of one kind --------------------------------------------

tests["gear compare: a ring is compared with both fingers and the better slot is named"] = function(t)
    local worn = { finger1 = item("INVTYPE_FINGER", { Stamina = 9 }), finger2 = item("INVTYPE_FINGER", { Stamina = 2 }) }
    local r = S.Compare(item("INVTYPE_FINGER", { Stamina = 5 }), worn, W)
    t.eq({ r.verdict, r.delta, r.slot, r.against }, { "upgrade", 3, "finger2", 2 })
    worn.finger2 = false
    r = S.Compare(item("INVTYPE_FINGER", { Stamina = 5 }), worn, W)
    t.eq({ r.verdict, r.delta, r.slot }, { "upgrade", 5, "finger2" }, "an empty finger is the better place")
    r = S.Compare(item("INVTYPE_FINGER", { Stamina = 1 }),
        { finger1 = item("INVTYPE_FINGER", { Stamina = 9 }), finger2 = item("INVTYPE_FINGER", { Stamina = 2 }) }, W)
    t.eq({ r.verdict, r.delta, r.slot }, { "worse", -1, "finger2" }, "worse than both: the nearer one is named")
end

tests["gear compare: equal on both fingers, the first is named"] = function(t)
    local worn = { finger1 = item("INVTYPE_FINGER", { Stamina = 2 }), finger2 = item("INVTYPE_FINGER", { Stamina = 2 }) }
    local r = S.Compare(item("INVTYPE_FINGER", { Stamina = 5 }), worn, W)
    t.eq({ r.delta, r.slot }, { 3, "finger1" })
end

tests["gear compare: one finger not read is no recommendation"] = function(t)
    local r = S.Compare(item("INVTYPE_TRINKET", { Stamina = 5 }), { trinket1 = item("INVTYPE_TRINKET", { Stamina = 1 }) }, W)
    t.eq(r.verdict, "none")
    t.eq(r.reason, S.REASON.worn .. ": trinket2")
end

-- Compare: weapons (F-006) --------------------------------------------------

local function sword(n) return item("INVTYPE_WEAPON", { Strength = n }) end
local function twoHander(n) return item("INVTYPE_2HWEAPON", { Strength = n }) end

tests["F-006: a dual wielder's one-hander is compared with the off hand too, and the better slot is named"] = function(t)
    local worn = { mainHand = sword(10), offHand = sword(3) }
    local r = S.Compare(sword(6), worn, W, { dualWield = true })
    t.eq({ r.verdict, r.delta, r.slot, r.against }, { "upgrade", 6, "offHand", 6 },
        "worse than the main hand, better than the off hand")
    r = S.Compare(sword(12), { mainHand = sword(4), offHand = sword(10) }, W, { dualWield = true })
    t.eq({ r.verdict, r.delta, r.slot }, { "upgrade", 16, "mainHand" }, "the main hand when that gains more")
    r = S.Compare(sword(6), { mainHand = sword(10), offHand = false }, W, { dualWield = true })
    t.eq({ r.verdict, r.delta, r.slot }, { "upgrade", 12, "offHand" }, "an empty off hand")
end

tests["F-006: without dual wield a one-hander is compared with the main hand only"] = function(t)
    local worn = { mainHand = sword(10), offHand = sword(3) }
    local r = S.Compare(sword(6), worn, W, { dualWield = false })
    t.eq({ r.verdict, r.delta, r.slot }, { "worse", -8, "mainHand" })
    t.eq(r.note, nil)
end

tests["F-006: dual wield not known compares with the main hand only, and says so"] = function(t)
    local worn = { mainHand = sword(10), offHand = sword(3) }
    for _, can in ipairs({ false, {} }) do
        local r = S.Compare(sword(6), worn, W, can or nil)
        t.eq({ r.verdict, r.delta, r.slot }, { "worse", -8, "mainHand" })
        t.eq(r.note, S.REASON.dualWield)
    end
end

tests["F-006: a dual wielder with the off hand not read gets no recommendation"] = function(t)
    local r = S.Compare(sword(6), { mainHand = sword(10) }, W, { dualWield = true })
    t.eq(r.verdict, "none")
    t.eq(r.reason, S.REASON.worn .. ": offHand")
end

tests["F-006: an off-hand weapon is compared with the off hand, never the main hand"] = function(t)
    local worn = { mainHand = sword(1), offHand = sword(5) }
    local r = S.Compare(item("INVTYPE_WEAPONOFFHAND", { Strength = 7 }), worn, W, { dualWield = true })
    t.eq({ r.verdict, r.delta, r.slot }, { "upgrade", 4, "offHand" })
    r = S.Compare(item("INVTYPE_SHIELD", { Stamina = 7 }), { mainHand = sword(1), offHand = item("INVTYPE_SHIELD", { Stamina = 9 }) }, W)
    t.eq({ r.verdict, r.delta, r.slot }, { "worse", -2, "offHand" })
    r = S.Compare(item("INVTYPE_WEAPONMAINHAND", { Strength = 7 }), worn, W, { dualWield = true })
    t.eq({ r.verdict, r.delta, r.slot }, { "upgrade", 12, "mainHand" }, "a main-hand weapon: the main hand only")
end

tests["two-hander: compared with the main hand and the off hand together"] = function(t)
    local worn = { mainHand = sword(6), offHand = item("INVTYPE_SHIELD", { Stamina = 5 }) }
    local r = S.Compare(twoHander(9), worn, W)
    t.eq({ r.verdict, r.delta, r.slot, r.score, r.against }, { "upgrade", 1, "mainHand", 18, 17 })
    t.eq(r.pair, true, "said to be against the pair")
    r = S.Compare(twoHander(8), worn, W)
    t.eq({ r.verdict, r.delta }, { "worse", -1 }, "better than the sword alone, worse than the pair")
    r = S.Compare(twoHander(9), { mainHand = sword(6), offHand = false }, W)
    t.eq({ r.verdict, r.delta, r.pair }, { "upgrade", 6, true }, "an empty off hand adds nothing")
    r = S.Compare(twoHander(9), { mainHand = twoHander(7), offHand = false }, W)
    t.eq({ r.verdict, r.delta, r.slot }, { "upgrade", 4, "mainHand" }, "two-hander against two-hander")
end

tests["two-hander: either hand not read is no recommendation"] = function(t)
    local r = S.Compare(twoHander(9), { mainHand = sword(6) }, W)
    t.eq(r.verdict, "none")
    t.eq(r.reason, S.REASON.worn .. ": offHand")
    r = S.Compare(twoHander(9), { offHand = false }, W)
    t.eq(r.verdict, "none")
    t.eq(r.reason, S.REASON.worn .. ": mainHand")
end

tests["wearing a two-hander: a one-hander is compared with the two-hander, on its own"] = function(t)
    local worn = { mainHand = twoHander(9), offHand = false }
    local r = S.Compare(sword(6), worn, W, { dualWield = true })
    t.eq({ r.verdict, r.delta, r.slot, r.against }, { "worse", -6, "mainHand", 18 },
        "not an upgrade for the empty off hand: it cannot go there beside a two-hander")
    r = S.Compare(sword(12), worn, W, { dualWield = false })
    t.eq({ r.verdict, r.delta, r.slot }, { "upgrade", 6, "mainHand" })
end

tests["wearing a two-hander: an off-hand item alone is no recommendation"] = function(t)
    local worn = { mainHand = twoHander(9), offHand = false }
    local r = S.Compare(item("INVTYPE_SHIELD", { Stamina = 50 }), worn, W)
    t.eq(r.verdict, "none")
    t.eq(r.delta, nil)
    t.eq(r.reason, S.REASON.needsMain)
    r = S.Compare(item("INVTYPE_SHIELD", { Stamina = 50 }), { offHand = false }, W)
    t.eq(r.verdict, "none", "the main hand not read: it may be a two-hander")
    t.eq(r.reason, S.REASON.worn .. ": mainHand")
end

tests["ranged: bows, thrown and relics share the ranged slot"] = function(t)
    for _, kind in ipairs({ "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT", "INVTYPE_THROWN", "INVTYPE_RELIC" }) do
        local r = S.Compare(item(kind, { Agility = 5 }), { ranged = item("INVTYPE_RANGED", { Agility = 2 }) }, W)
        t.eq({ r.verdict, r.delta, r.slot }, { "upgrade", 3, "ranged" }, kind)
    end
end

-- Whole ----------------------------------------------------------------------

tests["gear compare: nothing handed in is changed, and every answer has a reason"] = function(t)
    local cand = sword(6)
    local worn = { mainHand = sword(10), offHand = sword(3) }
    local weights = { Strength = 2 }
    local r = S.Compare(cand, worn, weights, { dualWield = true })
    t.eq(cand, { kind = "INVTYPE_WEAPON", stats = { Strength = 6 } })
    t.eq(worn, { mainHand = { kind = "INVTYPE_WEAPON", stats = { Strength = 10 } },
        offHand = { kind = "INVTYPE_WEAPON", stats = { Strength = 3 } } })
    t.eq(weights, { Strength = 2 })
    t.ok(type(r.reason) == "string" and r.reason ~= "", "a reason")
    for _, text in pairs(S.REASON) do
        t.ok(type(text) == "string" and text ~= "", "every reason is a sentence")
        t.ok(not text:lower():find("flow", 1, true), "no reason names the product")
    end
end

return tests
