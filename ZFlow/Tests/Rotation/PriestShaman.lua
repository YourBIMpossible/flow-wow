local _, ns = ...

-- The Priest and Shaman packs: they pass PackCheck, they hold what the old
-- shared tables said and nothing else, and with nothing known the chooser,
-- the key plan and the cast plan all answer "nothing" without failing.

local EQUIP = {
    PRIEST = { [4] = { 0, 1 }, [2] = { 4, 10, 15, 19, 20 } },
    SHAMAN = { [4] = { 0, 1, 2, 3, 6, 9 }, [2] = { 0, 1, 4, 5, 10, 13, 15, 20 } },
}
local REAGENTS = {
    PRIEST = { "Light Feather", "Holy Candle", "Sacred Candle" },
    SHAMAN = { "Ankh" },
}
local EMPTY = { "roles", "maintain", "groups", "interrupts", "breakers", "dispels", "keys", "weights", "spells",
                "talentBuilds", "options" }

local function asSet(list)
    local set = {}
    for _, k in ipairs(list) do set[k] = true end
    return set
end

local function snap()
    return { role = "dps", hostile = true, inCombat = true, attacking = true, health = 0.2, mana = 1,
             current = {}, spells = {}, buffs = {}, debuffs = {} }
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

    tests[name .. " pack: what is not known is empty, and listed as unknown"] = function(t)
        local p = ns.Packs[class]
        for _, key in ipairs(EMPTY) do
            t.eq(p[key], {}, key)
        end
        t.eq(p.lists, { default = {} }, "lists")
        t.eq(p.heals, { self = {} }, "heals")
        local unknown = asSet(p.unknown)
        for _, key in ipairs({ "lists", "spells", "keys", "roles", "weights" }) do
            t.ok(unknown[key], key .. " is listed as unknown")
        end
    end

    tests[name .. " pack: nothing observed, nothing for another player"] = function(t)
        local p = ns.Packs[class]
        t.ok(not string.find(p.provenance.facts, "observed in", 1, true), "no observation claimed")
        t.eq(p.groups, {}, "no group rows")
        t.eq(p.spells.Resurrection, nil, "no Resurrection")
        t.eq(p.spells["Ancestral Spirit"], nil, "no Ancestral Spirit")
    end

    tests[name .. " pack: the chooser suggests nothing and says why"] = function(t)
        local s, trace = ns.Choose(snap(), ns.Packs[class])
        t.eq(s, nil, "no suggestion, even hurt in a fight")
        t.ok(type(trace) == "table", "a trace all the same")
    end

    tests[name .. " pack: the key plan and the attributes are empty, not an error"] = function(t)
        local kp = ns.KeyPlan(ns.Packs[class], {})
        t.eq(kp.states[0], nil, "no row for no form")
        local r = ns.cast.Attributes(ns.Choose(snap(), ns.Packs[class]), kp, nil, false)
        t.eq(r.ok, true, "ok")
        t.eq(r.spell, nil, "the key casts nothing")
        t.eq(r.apply.counts, { set = 0, clear = 0, unchanged = 0 }, "nothing to bind")
    end
end

tests["priest and shaman packs are separate tables"] = function(t)
    t.ok(ns.Packs.PRIEST ~= ns.Packs.SHAMAN, "two packs")
    t.eq(ns.Packs.PRIEST.foodStats, nil, "no food stats for a priest in the old table")
    t.eq(ns.Packs.SHAMAN.foodStats.Strength, true, "strength food for a shaman")
    t.eq(ns.Packs.SHAMAN.foodStats.Agility, true, "agility food for a shaman")
end

return tests
