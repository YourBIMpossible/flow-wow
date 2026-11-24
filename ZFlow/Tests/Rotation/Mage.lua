local _, ns = ...

-- Tests for ZFlow/Classes/Mage.lua: the armor you cast or choose (N58, lead
-- section 241), with made-up snapshots through the chooser. Offline only;
-- nothing here was seen in the game.

local tests = {}

local function mage() return ns.Packs and ns.Packs.MAGE end

local MAGE_ARMOR, ICE, FROST = "Mage Armor", "Ice Armor", "Frost Armor"
local ALL = { MAGE_ARMOR, ICE, FROST, "Arcane Intellect", "Frostbolt", "Fire Blast" }

-- Alive, out of a fight, no armor on, the intellect up, no enemy; `over`
-- replaces fields ("nil" takes one away); known: the spells known (all by
-- default), each ready and in range.
local function snap(over, known)
    local s = {
        dead = false, inCombat = false, hostile = false, buffs = { ["Arcane Intellect"] = 900 },
        current = { ["Shoot"] = false }, spells = {},
    }
    for _, name in ipairs(known or ALL) do
        s.spells[name] = { known = true, usable = true, onCooldown = false, inRange = true }
    end
    for k, v in pairs(over or {}) do
        if v == "nil" then s[k] = nil else s[k] = v end
    end
    return ns.SnapshotOf(s)
end

local function pick(over, known)
    local got = ns.Choose(snap(over, known), mage())
    return got and got.spell or nil, got
end

local function armorRow()
    local p = mage()
    local sticky = type(p) == "table" and type(p.options) == "table" and p.options.sticky or nil
    for _, row in ipairs(type(sticky) == "table" and sticky or {}) do
        if row.key == "armor" then return row end
    end
    return nil
end

tests["mage N58: the armor row: no prefix, only the armors, the armor word"] = function(t)
    if type(mage()) ~= "table" then t.ok(false, "no pack") return end
    local ok, problems = ns.PackCheck(mage())
    t.ok(ok, table.concat(problems or {}, "; "))
    local row = armorRow()
    t.ok(row ~= nil, "options.sticky has the armor row")
    if not row then return end
    t.eq(row.prefix, "")
    t.eq(row.word, "armor")
    t.eq(row.names, { MAGE_ARMOR, ICE, FROST }, "the armors, best first")
    t.eq(row.only, { [MAGE_ARMOR] = true, [ICE] = true, [FROST] = true })
    for _, name in ipairs(row.names) do t.ok(mage().spells[name] ~= nil, name .. " is in the spell list") end
    t.eq(row.onYou, nil, "an armor only ever goes on you")
    t.eq(row.fightOnly, nil)
    t.eq(row.temporary, nil, "no armor is for a moment")
    t.eq(ns.OwnCasts.Match(mage().options.sticky, FROST), row, "Frost Armor matches the row")
    t.eq(ns.OwnCasts.Match(mage().options.sticky, "Arcane Intellect"), nil, "the intellect does not")
    t.eq(ns.OwnCasts.Find(row.names, row.prefix, "ice"), ICE, "the word: ice")
    t.eq(row.pick(snap({ buffs = {} })), MAGE_ARMOR, "pick: the best known, nothing kept")
    t.eq(row.pick(snap({ buffs = {} }, { FROST })), FROST, "pick: only Frost Armor known")
    t.eq(row.pick(snap({ buffs = {}, chosen = { armor = FROST } })), FROST, "pick: the kept one")
end

tests["mage N58: nothing kept: the best armor known, as before"] = function(t)
    if type(mage()) ~= "table" then t.ok(false, "no pack") return end
    t.eq(pick({ buffs = {} }), MAGE_ARMOR, "all known: Mage Armor")
    t.eq(pick({ buffs = {} }, { ICE, FROST }), ICE, "no Mage Armor: Ice Armor")
    t.eq(pick({ buffs = {} }, { FROST }), FROST, "only Frost Armor")
    t.eq(ns.MageArmor(snap({ buffs = {} }, { "Arcane Intellect" })), nil, "no armor known: none")
end

tests["mage N58: the armor kept is the one asked for"] = function(t)
    if type(mage()) ~= "table" then t.ok(false, "no pack") return end
    t.eq(pick({ buffs = {}, chosen = { armor = FROST } }), FROST, "cast for the role: Frost Armor")
    t.eq(pick({ buffs = {}, chosen = { armorSet = ICE, armor = FROST } }), ICE, "the word over the cast")
    t.eq(pick({ buffs = {}, chosen = { armorFight = FROST, armorSet = ICE } }), FROST, "this fight's first")
    t.eq(pick({ buffs = { [MAGE_ARMOR] = true, ["Arcane Intellect"] = 900 }, chosen = { armor = FROST } }), nil, "an armor on: left alone")
    t.eq(pick({ buffs = "nil", chosen = { armor = FROST } }), nil, "buffs not read: nothing")
    local _, got = pick({ buffs = {}, chosen = { armor = FROST }, inCombat = true })
    t.ok(got == nil or got.spell ~= FROST, "in a fight: no armor asked for, as before")
end

tests["mage N58: a kept armor you do not know: the best known, as before"] = function(t)
    if type(mage()) ~= "table" then t.ok(false, "no pack") return end
    t.eq(pick({ buffs = {}, chosen = { armor = ICE } }, { MAGE_ARMOR, FROST }), MAGE_ARMOR, "Ice Armor not known")
    t.eq(pick({ buffs = {}, chosen = { armor = "Molten Armor" } }), MAGE_ARMOR, "not an armor of this pack")
end

-- MAGE-5 (P-SELFBUFF): Amplify or Dampen Magic, your own choice (the magic
-- row of options.sticky, Rotation/OwnCasts.lua): off unless you cast or
-- chose one and know it.
local AMPLIFY, DAMPEN = "Amplify Magic", "Dampen Magic"
local ARMORED = { [MAGE_ARMOR] = 1800, ["Arcane Intellect"] = 900 }
local WITH_MAGIC = { MAGE_ARMOR, ICE, FROST, "Arcane Intellect", "Frostbolt", "Fire Blast", AMPLIFY, DAMPEN }

local function magicRow()
    local p = mage()
    local sticky = type(p) == "table" and type(p.options) == "table" and p.options.sticky or nil
    for _, row in ipairs(type(sticky) == "table" and sticky or {}) do
        if row.key == "magic" then return row end
    end
    return nil
end

tests["mage MAGE-5: the magic row: only Amplify and Dampen, the magic word"] = function(t)
    local row = magicRow()
    t.ok(row ~= nil, "a magic row")
    if not row then return end
    t.eq(row.prefix, "")
    t.eq(row.word, "magic")
    t.eq(row.names, { AMPLIFY, DAMPEN })
    t.eq(row.only[AMPLIFY], true); t.eq(row.only[DAMPEN], true); t.eq(row.only[MAGE_ARMOR], nil)
end

tests["mage MAGE-5: the magic you chose is kept up out of a fight"] = function(t)
    if type(mage()) ~= "table" then t.ok(false, "no pack") return end
    t.eq(pick({ buffs = ARMORED, chosen = { magic = AMPLIFY } }, WITH_MAGIC), AMPLIFY, "cast for the role: Amplify")
    t.eq(pick({ buffs = ARMORED, chosen = { magicSet = DAMPEN, magic = AMPLIFY } }, WITH_MAGIC), DAMPEN, "the word over the cast")
    t.eq(pick({ buffs = ARMORED }, WITH_MAGIC), nil, "none cast or chosen: off")
    t.eq(pick({ buffs = ARMORED, chosen = { magic = AMPLIFY } }, ALL), nil, "not known: off")
    local on = { [MAGE_ARMOR] = 1800, ["Arcane Intellect"] = 900, [AMPLIFY] = 300 }
    t.eq(pick({ buffs = on, chosen = { magic = AMPLIFY } }, WITH_MAGIC), nil, "up: left alone")
    t.eq(pick({ buffs = "nil", chosen = { magic = AMPLIFY } }, WITH_MAGIC), nil, "buffs not read: nothing")
    local _, got = pick({ buffs = ARMORED, chosen = { magic = AMPLIFY }, inCombat = true }, WITH_MAGIC)
    t.ok(got == nil or got.spell ~= AMPLIFY, "in a fight: not asked for")
end

tests["mage N52: an enemy hitting you up close: Frost Nova first; otherwise not"] = function(t)
    local known = { MAGE_ARMOR, "Arcane Intellect", "Frostbolt", "Fire Blast", "Frost Nova" }
    local close = { buffs = ARMORED, inCombat = true, hostile = true,
        targetMelee = true, targetOnYou = true, hittingYou = true }
    t.eq(pick(close, known), "Frost Nova", "an enemy next to you, hitting you")
    local apart = { buffs = ARMORED, inCombat = true, hostile = true, targetOnYou = true, hittingYou = true }
    t.eq(pick(apart, known), "Fire Blast", "not next to you: damage as before")
    local quiet = { buffs = ARMORED, inCombat = true, hostile = true, targetMelee = true, targetOnYou = true }
    t.eq(pick(quiet, known), "Fire Blast", "next to you, not hitting you yet: as before")
    t.eq(pick(close, { MAGE_ARMOR, "Arcane Intellect", "Frostbolt", "Fire Blast" }), "Fire Blast",
        "Frost Nova not known: as before")
end

return tests
