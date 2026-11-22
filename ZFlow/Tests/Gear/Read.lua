local _, ns = ...

-- Tests for ZFlow/Gear/Read.lua. Pure: what the client would have answered
-- is a table made here. Whole numbers only.

local G = ns.GearRead
local S = ns.GearScore
local tests = {}

local STR, STA, AGI = "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_STAMINA_SHORT", "ITEM_MOD_AGILITY_SHORT"

-- Stats --------------------------------------------------------------------

tests["gear read: stats keep the client's own keys and numbers"] = function(t)
    local raw = { [STR] = 10, [STA] = 7, RESISTANCE0_NAME = 120 }
    local stats, unmapped = G.Stats(raw)
    t.eq(stats, { [STR] = 10, [STA] = 7, RESISTANCE0_NAME = 120 })
    t.eq(unmapped, {})
    t.ok(stats ~= raw, "a table of its own")
    t.eq(raw, { [STR] = 10, [STA] = 7, RESISTANCE0_NAME = 120 }, "what was handed in is not changed")
end

tests["gear read: an item with no stats is an empty table, not an unknown one"] = function(t)
    local stats, unmapped = G.Stats({})
    t.eq(stats, {})
    t.eq(unmapped, {})
end

tests["gear read: no answer is stats not known, never an empty table"] = function(t)
    for _, raw in ipairs({ false, "none", 0 }) do
        local stats, unmapped = G.Stats(raw or nil)
        t.eq(stats, nil, tostring(raw))
        t.eq(unmapped, {})
    end
    local stats = G.Stats(nil)
    t.eq(stats, nil)
end

tests["gear read: a key it does not know is kept and named, never dropped"] = function(t)
    local stats, unmapped = G.Stats({ [STR] = 4, ITEM_MOD_NEW_THING_SHORT = 9, EMPTY_SOCKET_RED = 1 })
    t.eq(unmapped, { "EMPTY_SOCKET_RED", "ITEM_MOD_NEW_THING_SHORT" }, "sorted")
    t.eq(stats, { [STR] = 4, ITEM_MOD_NEW_THING_SHORT = 9, EMPTY_SOCKET_RED = 1 }, "and still in the stats")
end

tests["gear read: every key the class weights name is known"] = function(t)
    local raw = {}
    for _, key in ipairs(G.KEYS) do raw[key] = 1 end
    local stats, unmapped = G.Stats(raw)
    t.eq(unmapped, {})
    t.eq(stats, raw)
    t.ok(#G.KEYS >= 21, "the keys the two class files name")
    for _, key in ipairs({ STR, STA, AGI, "RESISTANCE0_NAME", "ITEM_MOD_VERSATILITY",
        "ITEM_MOD_DAMAGE_PER_SECOND_SHORT", "ITEM_MOD_SPELL_HEALING_DONE_SHORT" }) do
        t.eq(G.Known(key), true, key)
    end
    t.eq(G.Known("ITEM_MOD_NEW_THING_SHORT"), false)
    t.eq(G.Known(nil), false)
end

tests["gear read: a value that is no plain number is a stat not read, never 0"] = function(t)
    local nan = 0 / 0
    for _, bad in ipairs({ "10", true, nan, math.huge, -math.huge }) do
        local stats = G.Stats({ [STR] = bad, [STA] = 3 })
        t.eq(stats[STR], false, tostring(bad))
        t.eq(stats[STA], 3)
    end
    local stats = G.Stats({ [STR] = false })
    t.eq(stats[STR], false, "a false handed in stays not read")
end

tests["gear read: a key that is no name is named and left out"] = function(t)
    local stats, unmapped = G.Stats({ [STR] = 4, [7] = 2, [true] = 1 })
    t.eq(stats, { [STR] = 4 })
    t.eq(unmapped, { "7", "true" })
end

-- Item ---------------------------------------------------------------------

tests["gear read: an item is its equip location and its stats"] = function(t)
    local item, unmapped = G.Item("INVTYPE_HEAD", { [STR] = 5 })
    t.eq(item, { kind = "INVTYPE_HEAD", stats = { [STR] = 5 } })
    t.eq(unmapped, {})
end

tests["gear read: an equip location or stats not read are left out, not guessed"] = function(t)
    t.eq(G.Item(nil, { [STR] = 5 }), { stats = { [STR] = 5 } })
    t.eq(G.Item("", { [STR] = 5 }), { stats = { [STR] = 5 } }, "an empty location is no location")
    t.eq(G.Item(17, { [STR] = 5 }), { stats = { [STR] = 5 } })
    t.eq(G.Item("INVTYPE_HEAD", nil), { kind = "INVTYPE_HEAD" })
    local item, unmapped = G.Item(nil, nil)
    t.eq(item, {})
    t.eq(unmapped, {})
end

-- Equipped -----------------------------------------------------------------

tests["gear read: worn items go to their slot names by inventory id"] = function(t)
    local ids = { [1] = "head", [2] = "neck", [3] = "shoulder", [5] = "chest", [6] = "waist", [7] = "legs",
        [8] = "feet", [9] = "wrist", [10] = "hands", [11] = "finger1", [12] = "finger2", [13] = "trinket1",
        [14] = "trinket2", [15] = "back", [16] = "mainHand", [17] = "offHand", [18] = "ranged" }
    local worn, want, n = {}, {}, 0
    for id, slot in pairs(ids) do
        worn[id] = { kind = "INVTYPE_X" .. id, stats = { [STA] = id } }
        want[slot] = { kind = "INVTYPE_X" .. id, stats = { [STA] = id } }
        n = n + 1
    end
    local equipped, unmapped, ignored = G.Equipped(worn)
    t.eq(equipped, want)
    t.eq(unmapped, {})
    t.eq(ignored, {})
    t.eq(n, 17)
    t.eq(#S.SLOTS, 17, "the scorer's slots, all of them")
    for _, slot in ipairs(S.SLOTS) do t.ok(equipped[slot] ~= nil, slot) end
end

tests["gear read: a slot read as empty is false; a slot not read is absent, never false"] = function(t)
    local equipped = G.Equipped({ [1] = false, [16] = { kind = "INVTYPE_WEAPON", stats = { [STR] = 3 } } })
    t.eq(equipped.head, false, "read and empty")
    t.eq(equipped.offHand, nil, "not read")
    t.eq(equipped.neck, nil)
    t.eq(equipped.mainHand, { kind = "INVTYPE_WEAPON", stats = { [STR] = 3 } })
    local n = 0
    for _ in pairs(equipped) do n = n + 1 end
    t.eq(n, 2, "nothing is filled in for the fifteen slots nobody read")
end

tests["gear read: an answer for a slot that is neither an item nor empty is not read"] = function(t)
    local equipped = G.Equipped({ [1] = true, [2] = "item:123", [3] = 0 })
    t.eq(equipped, {})
end

tests["gear read: nothing read at all is nothing worn known"] = function(t)
    for _, worn in ipairs({ false, "x", 5 }) do
        local equipped, unmapped, ignored = G.Equipped(worn or nil)
        t.eq(equipped, {})
        t.eq(unmapped, {})
        t.eq(ignored, {})
    end
end

tests["gear read: the shirt, the tabard and anything else are named as ignored"] = function(t)
    local equipped, _, ignored = G.Equipped({ [4] = { kind = "INVTYPE_BODY", stats = {} }, [19] = false,
        [0] = false, [23] = false, bag = false, [1] = false })
    t.eq(equipped, { head = false })
    t.eq(ignored, { "0", "19", "23", "4", "bag" }, "sorted as text")
end

tests["gear read: a worn item with stats not read keeps its place with no stats"] = function(t)
    local equipped = G.Equipped({ [1] = { kind = "INVTYPE_HEAD" } })
    t.eq(equipped.head, { kind = "INVTYPE_HEAD" })
end

tests["gear read: keys not known on worn items are named once, sorted"] = function(t)
    local _, unmapped = G.Equipped({
        [1] = { kind = "INVTYPE_HEAD", stats = { ITEM_MOD_ZED = 1, [STR] = 2 } },
        [2] = { kind = "INVTYPE_NECK", stats = { ITEM_MOD_ZED = 3, ITEM_MOD_ABC = 1 } },
    })
    t.eq(unmapped, { "ITEM_MOD_ABC", "ITEM_MOD_ZED" })
end

-- Can ----------------------------------------------------------------------

tests["gear read: dual wield is yes, no, or left out when not known"] = function(t)
    t.eq(G.Can(true), { dualWield = true })
    t.eq(G.Can(false), { dualWield = false })
    for _, unknown in ipairs({ 1, 0, "yes" }) do
        t.eq(G.Can(unknown), {}, tostring(unknown))
    end
    t.eq(G.Can(nil), {}, "no answer is not a no")
end

-- Shapes: all three at once ---------------------------------------------------

tests["gear read: the three shapes the scorer takes, and one list of keys not known"] = function(t)
    local out = G.Shapes({
        kind = "INVTYPE_WEAPON", stats = { [STR] = 6, ITEM_MOD_ZED = 1 },
        worn = { [16] = { kind = "INVTYPE_WEAPON", stats = { [STR] = 10 } },
                 [17] = { kind = "INVTYPE_WEAPON", stats = { [STR] = 3, ITEM_MOD_ABC = 2 } },
                 [19] = false },
        dualWield = true,
    })
    t.eq(out.candidate, { kind = "INVTYPE_WEAPON", stats = { [STR] = 6, ITEM_MOD_ZED = 1 } })
    t.eq(out.equipped, { mainHand = { kind = "INVTYPE_WEAPON", stats = { [STR] = 10 } },
        offHand = { kind = "INVTYPE_WEAPON", stats = { [STR] = 3, ITEM_MOD_ABC = 2 } } })
    t.eq(out.can, { dualWield = true })
    t.eq(out.unmapped, { "ITEM_MOD_ABC", "ITEM_MOD_ZED" })
    t.eq(out.ignored, { "19" })
end

tests["gear read: nothing handed in gives shapes that say nothing is known"] = function(t)
    for _, input in ipairs({ false, {} }) do
        local out = G.Shapes(input or nil)
        t.eq(out.candidate, {})
        t.eq(out.equipped, {})
        t.eq(out.can, {})
        t.eq(out.unmapped, {})
        t.eq(out.ignored, {})
    end
end

-- With the scorer ------------------------------------------------------------

tests["gear read: its shapes go straight into the scorer (F-006, the off hand)"] = function(t)
    local out = G.Shapes({
        kind = "INVTYPE_WEAPON", stats = { [STR] = 6 },
        worn = { [16] = { kind = "INVTYPE_WEAPON", stats = { [STR] = 10 } },
                 [17] = { kind = "INVTYPE_WEAPON", stats = { [STR] = 3 } } },
        dualWield = true,
    })
    local r = S.Compare(out.candidate, out.equipped, { [STR] = 2 }, out.can)
    t.eq({ r.verdict, r.delta, r.slot }, { "upgrade", 6, "offHand" })
end

tests["gear read: a slot nobody read gives no recommendation, where an empty one gives an upgrade"] = function(t)
    local weights = { [STA] = 1 }
    local notRead = G.Shapes({ kind = "INVTYPE_HEAD", stats = { [STA] = 4 }, worn = {} })
    local r = S.Compare(notRead.candidate, notRead.equipped, weights, notRead.can)
    t.eq(r.verdict, "none")
    t.eq(r.reason, S.REASON.worn .. ": head")
    local empty = G.Shapes({ kind = "INVTYPE_HEAD", stats = { [STA] = 4 }, worn = { [1] = false } })
    r = S.Compare(empty.candidate, empty.equipped, weights, empty.can)
    t.eq({ r.verdict, r.delta }, { "upgrade", 4 })
end

tests["gear read: a stat not read reaches the scorer as not known, and stats not read at all too"] = function(t)
    local weights = { [STA] = 1 }
    local worn = { [1] = { kind = "INVTYPE_HEAD", stats = { [STA] = 2 } } }
    local out = G.Shapes({ kind = "INVTYPE_HEAD", stats = { [STA] = "?" }, worn = worn })
    local r = S.Compare(out.candidate, out.equipped, weights, out.can)
    t.eq(r.verdict, "none")
    t.eq(r.reason, S.REASON.stat .. ": " .. STA)
    out = G.Shapes({ kind = "INVTYPE_HEAD", worn = worn })
    r = S.Compare(out.candidate, out.equipped, weights, out.can)
    t.eq(r.verdict, "none")
    t.eq(r.reason, S.REASON.stats)
    out = G.Shapes({ kind = "INVTYPE_HEAD", stats = { [STA] = 9 }, worn = { [1] = { kind = "INVTYPE_HEAD" } } })
    r = S.Compare(out.candidate, out.equipped, weights, out.can)
    t.eq(r.verdict, "none")
    t.eq(r.reason, S.REASON.wornStat .. ": head")
end

tests["gear read: dual wield not read is passed on as not known"] = function(t)
    local out = G.Shapes({
        kind = "INVTYPE_WEAPON", stats = { [STR] = 6 },
        worn = { [16] = { kind = "INVTYPE_WEAPON", stats = { [STR] = 10 } },
                 [17] = { kind = "INVTYPE_WEAPON", stats = { [STR] = 3 } } },
    })
    local r = S.Compare(out.candidate, out.equipped, { [STR] = 2 }, out.can)
    t.eq({ r.verdict, r.slot }, { "worse", "mainHand" })
    t.eq(r.note, S.REASON.dualWield)
end

return tests
