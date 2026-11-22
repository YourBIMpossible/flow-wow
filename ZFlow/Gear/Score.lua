local _, ns = ...

-- Gear scoring: is this item better than what you wear, by the weights
-- handed in. The pure core: an item, what is worn and the weights are plain
-- tables; nothing here reads the game, draws anything or keeps anything.
--
--   n, why  = GearScore.Score(stats, weights)
--   result  = GearScore.Compare(candidate, equipped, weights[, can])
--
--   stats    { [stat name] = number }: every stat the item has. A stat that
--            is on the item but could not be read is given as anything that
--            is not a plain number (false, say). It is never counted as 0.
--   weights  { [stat name] = number }: what one point of each stat is worth
--            to this role. Authored data with a written origin; none is
--            made here. A stat the weights do not name is worth nothing to
--            the role and is not looked at.
--   item     { kind, stats }. kind is the equip location as the client
--            names it ("INVTYPE_HEAD"), passed in as data.
--   equipped { [slot] = item, or false for a slot known to be empty }. A
--            slot that is absent was not read: it is not known, and it is
--            not treated as empty. Slots are named in GearScore.SLOTS.
--   can      { dualWield = true or false }; absent: not known.
--
-- Score: the sum of stat times weight, or nil and why:
--   no weights at all (nil, not a table, or naming no stat): there is no
--   recommendation to make, and never a score of 0; a weight that is not a
--   plain number; no stats; a weighted stat that is not known.
--
-- Compare: { verdict, reason, delta, slot, score, against, pair, note }
--   verdict  "upgrade", "same", "worse", or "none": no recommendation
--   reason   always given, one of GearScore.REASON (with the stat or slot it
--            is about after a colon where there is one)
--   delta    candidate minus what it would replace; nil when verdict is none
--   slot     the slot it was compared with. Where two slots take the item
--            (rings, trinkets, a dual wielder's one-hander) each is tried
--            and the one that gains most is named; equal: the first.
--   score, against   the candidate's score and the score it was held up to
--   pair     true when `against` is the main hand and the off hand together
--   note     a second thing worth saying (see REASON.dualWield)
--
-- Weapons:
--   a one-hander    the main hand; for a dual wielder the off hand as well,
--                   and the better slot is named (F-006). Dual wield not
--                   known: the main hand only, and the note says so.
--   main-hand only  the main hand.
--   off hand, shield, held item   the off hand only, never the main hand.
--   a two-hander    the main hand and the off hand together.
--   wearing a two-hander   a one-hander is held up to the two-hander, on its
--                   own: it cannot go in the off hand beside it. An off-hand
--                   item alone gets no recommendation: it needs a one-hander
--                   with it, and choosing that partner is not done here.
-- Whether you can use the item at all (class, level, skill) is the caller's
-- question, asked before this.

local S = {}
ns.GearScore = S

S.REASON = {
    weights = "no stat weights for this role: no recommendation",
    weight = "a stat weight is not a number",
    stats = "the item's stats are not known",
    stat = "a stat on the item is not known",
    kind = "not an item for a slot that is compared",
    worn = "what you wear in that slot is not known",
    wornStat = "the stats of what you wear in that slot are not known",
    needsMain = "it needs a one-hander beside it: you wear a two-hander",
    dualWield = "not known whether you can dual wield: compared with the main hand only",
    upgrade = "better than what you wear in that slot",
    same = "the same as what you wear in that slot",
    worse = "worse than what you wear in that slot",
}
local R = S.REASON

S.SLOTS = { "head", "neck", "shoulder", "back", "chest", "wrist", "hands", "waist", "legs", "feet",
    "finger1", "finger2", "trinket1", "trinket2", "mainHand", "offHand", "ranged" }

local TWO_HANDER = "INVTYPE_2HWEAPON"

-- kind -> the slots it can go in, in the order they are tried, and for a
-- weapon which hand it is for. Shirts, tabards, bags and ammunition are not
-- compared: they have no entry.
local KIND = {
    INVTYPE_HEAD = { slots = { "head" } },
    INVTYPE_NECK = { slots = { "neck" } },
    INVTYPE_SHOULDER = { slots = { "shoulder" } },
    INVTYPE_CLOAK = { slots = { "back" } },
    INVTYPE_CHEST = { slots = { "chest" } },
    INVTYPE_ROBE = { slots = { "chest" } },
    INVTYPE_WRIST = { slots = { "wrist" } },
    INVTYPE_HAND = { slots = { "hands" } },
    INVTYPE_WAIST = { slots = { "waist" } },
    INVTYPE_LEGS = { slots = { "legs" } },
    INVTYPE_FEET = { slots = { "feet" } },
    INVTYPE_FINGER = { slots = { "finger1", "finger2" } },
    INVTYPE_TRINKET = { slots = { "trinket1", "trinket2" } },
    INVTYPE_RANGED = { slots = { "ranged" } },
    INVTYPE_RANGEDRIGHT = { slots = { "ranged" } },
    INVTYPE_THROWN = { slots = { "ranged" } },
    INVTYPE_RELIC = { slots = { "ranged" } },
    INVTYPE_WEAPON = { hand = "one" },
    INVTYPE_WEAPONMAINHAND = { hand = "main" },
    INVTYPE_WEAPONOFFHAND = { hand = "off" },
    INVTYPE_SHIELD = { hand = "off" },
    INVTYPE_HOLDABLE = { hand = "off" },
    [TWO_HANDER] = { hand = "two" },
}

local MAIN, OFF = { "mainHand" }, { "offHand" }
local BOTH = { "mainHand", "offHand" }

-- A plain number: not NaN, not endless.
local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- The names (string keys) of a table, sorted, so that what is named in a
-- reason does not depend on the order a table happens to be walked in.
local function names(t)
    local out = {}
    for key in pairs(t) do
        if type(key) == "string" then out[#out + 1] = key end
    end
    table.sort(out)
    return out
end

function S.Score(stats, weights)
    if type(weights) ~= "table" then return nil, R.weights end
    local weighted = names(weights)
    if #weighted == 0 then return nil, R.weights end
    for i = 1, #weighted do
        if not finite(weights[weighted[i]]) then return nil, R.weight .. ": " .. weighted[i] end
    end
    if type(stats) ~= "table" then return nil, R.stats end
    local total = 0
    for i = 1, #weighted do
        local name = weighted[i]
        local weight, value = weights[name], stats[name]
        -- A stat the item does not have adds nothing. One it has but that
        -- was not read is not known, and neither is the score, unless the
        -- role gives that stat no worth at all.
        if value ~= nil and weight ~= 0 then
            if not finite(value) then return nil, R.stat .. ": " .. name end
            total = total + value * weight
        end
    end
    return total
end

local function none(reason)
    return { verdict = "none", reason = reason }
end

-- The score of what is worn in `slot`: a number (0 for a slot known to be
-- empty), or nil and why.
local function wornScore(equipped, slot, weights)
    local worn = equipped[slot]
    if worn == false then return 0 end
    if type(worn) ~= "table" then return nil, R.worn .. ": " .. slot end
    local n = S.Score(worn.stats, weights)
    -- The weights were already found good for the candidate, so what is
    -- wrong here is the worn item's stats.
    if n == nil then return nil, R.wornStat .. ": " .. slot end
    return n
end

local function answer(score, against, slot)
    local delta = score - against
    local verdict = (delta > 0 and "upgrade") or (delta < 0 and "worse") or "same"
    return { verdict = verdict, reason = R[verdict], delta = delta, slot = slot, score = score, against = against }
end

-- Held up to each slot in turn; the one that gains most is the answer, the
-- first of equals. A slot that cannot be scored ends it: no recommendation.
local function best(score, equipped, slots, weights)
    local found
    for i = 1, #slots do
        local against, why = wornScore(equipped, slots[i], weights)
        if against == nil then return none(why) end
        if found == nil or score - against > found.delta then
            found = answer(score, against, slots[i])
        end
    end
    return found
end

function S.Compare(candidate, equipped, weights, can)
    if type(candidate) ~= "table" then return none(R.kind) end
    local kind = type(candidate.kind) == "string" and KIND[candidate.kind] or nil
    if not kind then return none(R.kind) end
    local score, why = S.Score(candidate.stats, weights)
    if score == nil then return none(why) end
    equipped = type(equipped) == "table" and equipped or {}

    if not kind.hand then return best(score, equipped, kind.slots, weights) end

    if kind.hand == "two" then
        local main, whyMain = wornScore(equipped, "mainHand", weights)
        if main == nil then return none(whyMain) end
        local off, whyOff = wornScore(equipped, "offHand", weights)
        if off == nil then return none(whyOff) end
        local result = answer(score, main + off, "mainHand")
        result.pair = true
        return result
    end

    -- Every other weapon needs the main hand read first: a two-hander there
    -- changes what the item can replace.
    local main = equipped.mainHand
    if main ~= false and type(main) ~= "table" then return none(R.worn .. ": mainHand") end
    local twoHanded = main ~= false and main.kind == TWO_HANDER

    if kind.hand == "off" then
        if twoHanded then return none(R.needsMain) end
        return best(score, equipped, OFF, weights)
    end
    if twoHanded or kind.hand == "main" then return best(score, equipped, MAIN, weights) end

    -- A one-hander, with no two-hander worn.
    local dualWield = nil
    if type(can) == "table" and type(can.dualWield) == "boolean" then dualWield = can.dualWield end
    local result = best(score, equipped, dualWield and BOTH or MAIN, weights)
    if dualWield == nil then result.note = R.dualWield end
    return result
end
