local _, ns = ...

-- The Priest and Shaman packs: they pass PackCheck and hold what the old
-- shared tables said. Both are filled (section 197): every row a first
-- guess, nothing for another player, and their key rows are planned.

local EQUIP = {
    PRIEST = { [4] = { 0, 1 }, [2] = { 4, 10, 15, 19, 20 } },
    SHAMAN = { [4] = { 0, 1, 2, 3, 6, 9 }, [2] = { 0, 1, 4, 5, 10, 13, 15, 20 } },
}
local REAGENTS = {
    PRIEST = { "Light Feather", "Holy Candle", "Sacred Candle" },
    SHAMAN = { "Ankh" },
}
local function asSet(list)
    local set = {}
    for _, k in ipairs(list) do set[k] = true end
    return set
end

local tests = {}

for _, class in ipairs({ "PRIEST", "SHAMAN" }) do
    local name = string.lower(class)

    tests[name .. " pack passes PackCheck"] = function(t)
        local ok, problems = ns.PackCheck(ns.Packs[class])
        t.eq(table.concat(problems, "; "), "", "no problems")
        t.ok(ok, "ok")
        -- A9 (section 229 item 7): the pack also plays. Its self buff is
        -- chosen with none up out of a fight, and not with it up.
        local buff = class == "PRIEST" and "Power Word: Fortitude" or "Lightning Shield"
        local function snap(buffs)
            return { dead = false, inCombat = false, hostile = false, formKnown = true,
                     buffs = buffs, targetDebuffs = {}, current = {},
                     spells = { [buff] = { known = true, usable = true, onCooldown = false, inRange = true } } }
        end
        local got = ns.Choose(snap({}), ns.Packs[class])
        t.eq(got and got.spell, buff, buff .. " missing: chosen")
        t.eq(got and got.step, "list", "from the priority list")
        got = ns.Choose(snap({ [buff] = 1200 }), ns.Packs[class])
        t.ok(not (got and got.spell == buff), buff .. " up for 20 minutes: not chosen")
    end

    tests[name .. " pack: what it can equip is the old table's"] = function(t)
        local p = ns.Packs[class].proficiency
        local armor = asSet(EQUIP[class][4])
        -- Section 205: the Shaman learns mail (3) at level 40.
        if class == "SHAMAN" then armor[3] = 40 end
        t.eq(p[4], armor, "armor")
        t.eq(p[2], asSet(EQUIP[class][2]), "weapons")
        t.eq(p.evidence, "first guess", "evidence")
    end

    tests[name .. " pack: a mana user, a caster, with its reagents"] = function(t)
        local p = ns.Packs[class]
        t.eq(#p.resources, 1, "one resource")
        t.eq(p.resources[1].name, "Mana", "mana")
        t.eq(p.kind.name, "caster", "kind")
        local items = {}
        for i, r in ipairs(p.reagents) do
            items[i] = r.item
            t.eq(r.evidence, "first guess", r.item)
        end
        t.eq(items, REAGENTS[class], "reagents")
    end

    tests[name .. " pack: nothing observed; care rows for another player (S12)"] = function(t)
        local p = ns.Packs[class]
        t.ok(not string.find(p.provenance.facts, "observed in", 1, true), "no observation claimed")
        -- P-PARTY: the priest's Fortitude for the group, only shown; the shaman has none.
        if class == "PRIEST" then
            t.eq(#p.groups, 1, "one group row")
            t.eq({ p.groups[1].spell, p.groups[1].who, p.groups[1].aura, p.groups[1].unit },
                { "Power Word: Fortitude", "all", { "Power Word: Fortitude", "Prayer of Fortitude" }, nil },
                "Fortitude for everyone; Prayer counts")
        else
            t.eq(p.groups, {}, "no group rows")
        end
        -- PRIEST-1, SHAMAN-1: the revive and the heals for another player
        -- (the care key, Rotation/CareKeys.lua), each a first guess.
        local revive = class == "PRIEST" and "Resurrection" or "Ancestral Spirit"
        t.eq(type(p.care) == "table" and p.care.revive, revive, "the revive for another player")
        t.eq(p.spells[revive] and p.spells[revive].evidence, "first guess", "its spell row")
    end
end

for _, class in ipairs({ "PRIEST", "SHAMAN" }) do
    local name = string.lower(class)

    tests[name .. " pack: every row is filled, each spell a first guess"] = function(t)
        local p = ns.Packs[class]
        local count = 0
        for spell, row in pairs(p.spells) do
            count = count + 1
            t.eq(row.evidence, "first guess", spell)
        end
        t.ok(count > 0, "spells written")
        t.ok(#p.lists.default > 0, "a default list")
        t.ok(#p.heals.self > 0, "heals for yourself")
        t.ok(p.roles.dps ~= nil and p.roles.heal ~= nil, "two roles")
        t.ok(p.weights.dps ~= nil and p.weights.heal ~= nil, "weights per role")
        t.eq(p.unknown, nil, "nothing left listed as unknown")
        for _, rule in ipairs(p.lists.default) do
            t.eq(rule.evidence, "first guess", rule.spell)
            t.ok(p.spells[rule.spell] ~= nil, "a spell row for " .. tostring(rule.spell))
        end
    end
end

-- PRIEST-3 (P-SELFBUFF): Power Word: Shield in the list, read against your
-- own debuffs by name (snapshot.debuffs, client.playerDebuffs).
local function shieldSnap(over)
    local s = { dead = false, inCombat = true, hostile = true, formKnown = true,
                buffs = { ["Power Word: Fortitude"] = 1200, ["Inner Fire"] = 600 },
                targetDebuffs = { ["Shadow Word: Pain"] = 10 }, debuffs = {}, current = {},
                spells = { ["Power Word: Shield"] = { known = true, usable = true, onCooldown = false, inRange = true } } }
    for k, v in pairs(over or {}) do
        if v == "nil" then s[k] = nil else s[k] = v end
    end
    return s
end

tests["priest PRIEST-3: Power Word: Shield in a fight without Weakened Soul"] = function(t)
    local got = ns.Choose(shieldSnap(), ns.Packs.PRIEST)
    t.eq(got and got.spell, "Power Word: Shield", "no Weakened Soul, no shield: shield")
    got = ns.Choose(shieldSnap({ debuffs = { ["Weakened Soul"] = 10 } }), ns.Packs.PRIEST)
    t.ok(not (got and got.spell == "Power Word: Shield"), "Weakened Soul on you: no shield")
    got = ns.Choose(shieldSnap({ debuffs = "nil" }), ns.Packs.PRIEST)
    t.ok(not (got and got.spell == "Power Word: Shield"), "your debuffs not read: no shield")
    local up = { ["Power Word: Fortitude"] = 1200, ["Inner Fire"] = 600, ["Power Word: Shield"] = 20 }
    got = ns.Choose(shieldSnap({ buffs = up }), ns.Packs.PRIEST)
    t.ok(not (got and got.spell == "Power Word: Shield"), "a shield on you: no shield")
    got = ns.Choose(shieldSnap({ inCombat = false }), ns.Packs.PRIEST)
    t.ok(not (got and got.spell == "Power Word: Shield"), "out of a fight: no shield")
end

tests["priest pack: the key plan has rows for no form and Shadowform"] = function(t)
    local kp = ns.KeyPlan(ns.Packs.PRIEST, { forms = { { name = "Shadowform", index = 1 } } })
    t.ok(kp.states[0] ~= nil, "a row for no form")
    t.ok(kp.states[1] ~= nil, "a row for Shadowform")
end

-- Section 208 pin update: section 203 had no weapon enchant read, so imbues
-- were keys only. Section 241 (P-SELFBUFF) builds imbue rows once that read is
-- in: an imbue may now be a step, but only a buff rule that waits on the read.
-- Totems still have no read and stay keys.
tests["shaman pack: totems are keys, never list steps; imbues only as buff rules on the enchant read"] = function(t)
    for _, rule in ipairs(ns.Packs.SHAMAN.lists.default) do
        if string.find(rule.spell, " Weapon", 1, true) then
            t.eq(rule.kind, "buff", "an imbue step is a buff rule: " .. rule.spell)
            t.eq(type(rule.when), "function", "an imbue step waits on a test: " .. rule.spell)
            t.eq(rule.when({}), false, "no enchant read: no imbue step: " .. rule.spell)
        end
        t.ok(not string.find(rule.spell, " Totem", 1, true), "no totem read: " .. rule.spell)
    end
end

tests["shaman pack: the key plan has a row for no form"] = function(t)
    local kp = ns.KeyPlan(ns.Packs.SHAMAN, {})
    t.ok(kp.states[0] ~= nil, "a row for no form")
end

tests["priest and shaman packs are separate tables"] = function(t)
    t.ok(ns.Packs.PRIEST ~= ns.Packs.SHAMAN, "two packs")
    t.eq(ns.Packs.PRIEST.foodStats, nil, "no food stats for a priest in the old table")
    t.eq(ns.Packs.SHAMAN.foodStats.Strength, true, "strength food for a shaman")
    t.eq(ns.Packs.SHAMAN.foodStats.Agility, true, "agility food for a shaman")
end

return tests
