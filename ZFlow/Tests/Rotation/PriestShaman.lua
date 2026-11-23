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
    end

    tests[name .. " pack: what it can equip is the old table's"] = function(t)
        local p = ns.Packs[class].proficiency
        t.eq(p[4], asSet(EQUIP[class][4]), "armor")
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

    tests[name .. " pack: nothing observed, nothing for another player"] = function(t)
        local p = ns.Packs[class]
        t.ok(not string.find(p.provenance.facts, "observed in", 1, true), "no observation claimed")
        t.eq(p.groups, {}, "no group rows")
        t.eq(p.spells.Resurrection, nil, "no Resurrection")
        t.eq(p.spells["Ancestral Spirit"], nil, "no Ancestral Spirit")
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

tests["priest pack: Power Word: Shield is a key, never a list step"] = function(t)
    for _, rule in ipairs(ns.Packs.PRIEST.lists.default) do
        t.ok(rule.spell ~= "Power Word: Shield", "no Weakened Soul read: not suggested")
    end
end

tests["priest pack: the key plan has rows for no form and Shadowform"] = function(t)
    local kp = ns.KeyPlan(ns.Packs.PRIEST, { forms = { { name = "Shadowform", index = 1 } } })
    t.ok(kp.states[0] ~= nil, "a row for no form")
    t.ok(kp.states[1] ~= nil, "a row for Shadowform")
end

tests["shaman pack: weapon imbues and totems are keys, never list steps"] = function(t)
    for _, rule in ipairs(ns.Packs.SHAMAN.lists.default) do
        t.ok(not string.find(rule.spell, " Weapon", 1, true), "no weapon enchant read: " .. rule.spell)
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
