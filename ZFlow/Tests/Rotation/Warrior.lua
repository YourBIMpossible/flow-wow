local _, ns = ...

-- The Warrior pack (lead section 197): it passes PackCheck, it is for
-- yourself and your own target only, stances come from the form read, and
-- the reactive strikes wait for the game to mark them usable.

local ALL = {
    "Battle Stance", "Defensive Stance", "Battle Shout", "Charge", "Attack", "Rend", "Heroic Strike",
    "Execute", "Overpower", "Revenge", "Sunder Armor", "Thunder Clap", "Demoralizing Shout", "Cleave",
}
local SHOUT = { ["Battle Shout"] = 100 }

-- In Battle Stance, shout up, an enemy targeted, in the fight, swinging,
-- Rend on it, Heroic Strike not queued.
local function snap(over, knows)
    local s = { role = "dps", hostile = true, inCombat = true, dead = false, attacking = true,
                form = "Battle Stance", formKnown = true, buffs = SHOUT, targetDebuffs = { Rend = 15 },
                current = { Attack = true, ["Heroic Strike"] = false, Cleave = false }, spells = {} }
    for _, name in ipairs(knows or ALL) do
        s.spells[name] = { known = true, onCooldown = false, inRange = true }
    end
    for _, name in ipairs({ "Execute", "Overpower", "Revenge" }) do
        if s.spells[name] then s.spells[name].usable = false end
    end
    for k, v in pairs(over or {}) do s[k] = v end
    return s
end

local function advice(over, knows)
    local r = ns.Choose(snap(over, knows), ns.Packs.WARRIOR)
    return r and r.spell or nil
end

return {
    ["warrior pack passes PackCheck"] = function(t)
        local ok, problems = ns.PackCheck(ns.Packs.WARRIOR)
        t.eq(table.concat(problems, "; "), "", "no problems")
        t.ok(ok, "ok")
    end,

    ["warrior pack is registered for the class"] = function(t)
        t.ok(type(ns.Packs.WARRIOR) == "table", "ns.Packs.WARRIOR")
        t.eq(ns.Packs.WARRIOR.roles.dps ~= nil, true, "a dps role")
        t.eq(ns.Packs.WARRIOR.roles.tank ~= nil, true, "a tank role")
    end,

    ["every rule and spell row is marked first guess"] = function(t)
        for key, list in pairs(ns.Packs.WARRIOR.lists) do
            for i, rule in ipairs(list) do
                t.eq(rule.evidence, "first guess", key .. " " .. i .. " " .. tostring(rule.spell))
            end
        end
        for name, row in pairs(ns.Packs.WARRIOR.spells) do
            t.eq(row.evidence, "first guess", name)
        end
    end,

    ["no stance read as none: Battle Stance first"] = function(t)
        local s = snap({ formKnown = true })
        s.form = nil
        t.eq(ns.Choose(s, ns.Packs.WARRIOR).spell, "Battle Stance")
    end,

    ["the stance not read: no stance asked for"] = function(t)
        local s = snap({ formKnown = false, hostile = false, inCombat = false, buffs = {} })
        s.form = nil
        t.eq(ns.Choose(s, ns.Packs.WARRIOR).spell, "Battle Shout")
    end,

    ["shout missing or nearly out: Battle Shout"] = function(t)
        t.eq(advice({ buffs = {} }), "Battle Shout")
        t.eq(advice({ buffs = { ["Battle Shout"] = 5 } }), "Battle Shout")
    end,

    ["buffs not read: no shout"] = function(t)
        local got = advice({ buffs = nil })
        t.ok(got ~= "Battle Shout", tostring(got))
    end,

    ["an enemy out of a fight in Battle Stance: Charge"] = function(t)
        t.eq(advice({ inCombat = false, attacking = false, current = { Attack = false } }), "Charge")
    end,

    ["no Charge once in the fight"] = function(t)
        t.ok(advice({ current = { Attack = false } }) ~= "Charge")
    end,

    ["Execute, Overpower, Revenge only when the game marks them usable"] = function(t)
        t.eq(advice(), "Heroic Strike", "none usable")
        local s = snap()
        s.spells.Overpower.usable = true
        t.eq(ns.Choose(s, ns.Packs.WARRIOR).spell, "Overpower")
        s.spells.Execute.usable = true
        t.eq(ns.Choose(s, ns.Packs.WARRIOR).spell, "Execute")
        s.spells.Execute.usable = nil
        s.spells.Overpower.usable = nil
        t.eq(ns.Choose(s, ns.Packs.WARRIOR).spell, "Heroic Strike", "usable not read: not a yes")
    end,

    ["Overpower is a Battle Stance strike"] = function(t)
        local s = snap({ form = "Defensive Stance", role = "tank" })
        s.spells.Overpower.usable = true
        t.ok(ns.Choose(s, ns.Packs.WARRIOR).spell ~= "Overpower")
    end,

    ["a tank: Defensive Stance, then Revenge when usable, else Sunder Armor"] = function(t)
        t.eq(advice({ role = "tank" }), "Defensive Stance")
        t.eq(advice({ role = "tank", form = "Defensive Stance" }), "Sunder Armor")
        local s = snap({ role = "tank", form = "Defensive Stance" })
        s.spells.Revenge.usable = true
        t.eq(ns.Choose(s, ns.Packs.WARRIOR).spell, "Revenge")
    end,

    ["Rend when it is not on the target, not when debuffs are not read"] = function(t)
        t.eq(advice({ targetDebuffs = {} }), "Rend")
        t.ok(advice({ targetDebuffs = nil }) ~= "Rend")
    end,

    ["Heroic Strike already queued is not asked again"] = function(t)
        t.ok(advice({ current = { Attack = true, ["Heroic Strike"] = true } }) ~= "Heroic Strike")
    end,

    ["the next-swing strikes are named for the driver"] = function(t)
        local o = ns.Packs.WARRIOR.options
        t.eq(o.nextSwing, { "Heroic Strike", "Cleave" })
    end,

    ["gear: plate and shields are worn, wands are not"] = function(t)
        local p = ns.Packs.WARRIOR.proficiency
        t.eq(p.evidence, "first guess")
        t.eq(p[4][4], true, "plate")
        t.eq(p[4][6], true, "shield")
        t.eq(p[2][8], true, "two-handed sword")
        t.eq(p[2][19], nil, "wand")
        t.eq(p[4][7], nil, "libram")
    end,

    -- N58 (lead section 241): the stance you cast or choose.
    ["N58 warrior: the stance row: no prefix, the three stances, held 6 s"] = function(t)
        local rows = ns.Packs.WARRIOR.options.sticky
        t.ok(type(rows) == "table" and #rows == 1, "one row")
        local row = rows[1]
        t.eq(row.prefix, "", "no prefix")
        t.eq(row.key, "stance")
        t.eq(row.word, "stance")
        t.eq(row.window, 6, "a stance swapped for one ability and back is not kept")
        t.eq(row.names, { "Battle Stance", "Defensive Stance", "Berserker Stance" })
        t.eq(row.only, { ["Battle Stance"] = true, ["Defensive Stance"] = true, ["Berserker Stance"] = true })
        t.eq(row.temporary, nil, "no stance is for a moment")
        t.eq(row.fightOnly, nil, "a stance cast in a fight is kept for the role")
        t.eq(ns.OwnCasts.Note(rows, "Defensive Stance"), "stance", "a stance cast matches the row")
        t.eq(ns.OwnCasts.Note(rows, "Battle Shout"), nil, "the shout does not")
        t.eq(row.pick(snap({ form = nil })), "Battle Stance", "PC-1: dps, nothing kept: Battle Stance")
        t.eq(row.pick(snap({ role = "tank" })), "Defensive Stance", "PC-1: a tank: Defensive Stance")
    end,

    ["N58 warrior: nothing kept: Battle Stance in no stance, Defensive for a tank, as before"] = function(t)
        t.eq(ns.WarriorStance(snap()), "Battle Stance")
        t.eq(ns.WarriorStance(snap({ role = "tank" })), "Defensive Stance")
        local s = snap({ role = "tank" })
        s.form = nil
        t.eq(ns.Choose(s, ns.Packs.WARRIOR).spell, "Defensive Stance", "a tank in no stance")
        t.ok(advice() ~= "Battle Stance", "dps in Battle Stance: no stance asked")
        t.ok(advice({ form = "Defensive Stance" }) ~= "Battle Stance", "dps in another stance: left alone, as before")
    end,

    ["N58 warrior: the kept stance is the one asked for in no stance"] = function(t)
        local s = snap({ chosen = { stance = "Defensive Stance" } })
        s.form = nil
        t.eq(ns.WarriorStance(s), "Defensive Stance")
        t.eq(ns.Choose(s, ns.Packs.WARRIOR).spell, "Defensive Stance", "dps, kept Defensive, no stance")
        s.form = "Battle Stance"
        t.ok(ns.Choose(s, ns.Packs.WARRIOR).spell ~= "Defensive Stance", "dps in a stance: not asked to change it")
        s.form = nil
        s.chosen = { stance = "Defensive Stance", stanceSet = "Battle Stance" }
        t.eq(ns.Choose(s, ns.Packs.WARRIOR).spell, "Battle Stance", "the word's choice before the one cast")
    end,

    ["N58 warrior: a tank's kept stance replaces Defensive"] = function(t)
        local s = snap({ role = "tank", form = "Defensive Stance", chosen = { stance = "Battle Stance" } })
        t.eq(ns.Choose(s, ns.Packs.WARRIOR).spell, "Battle Stance", "a tank in Defensive, kept Battle")
        s.form = "Battle Stance"
        t.ok(ns.Choose(s, ns.Packs.WARRIOR).spell ~= "Defensive Stance", "in the kept one: Defensive not asked")
        s.formKnown = nil
        t.ok(ns.Choose(s, ns.Packs.WARRIOR).spell ~= "Battle Stance", "the stance not read: no stance asked")
    end,

    ["N58 warrior: a kept stance not known: the role's own"] = function(t)
        local s = snap({ chosen = { stance = "Berserker Stance" } })
        s.form = nil
        t.eq(ns.WarriorStance(s), "Battle Stance", "Berserker Stance not known: Battle Stance")
        t.eq(ns.Choose(s, ns.Packs.WARRIOR).spell, "Battle Stance")
        local tankS = snap({ role = "tank", chosen = { stance = "Berserker Stance" } })
        t.eq(ns.Choose(tankS, ns.Packs.WARRIOR).spell, "Defensive Stance", "a tank: Defensive Stance")
        local knows = { "Berserker Stance" }
        for _, name in ipairs(ALL) do knows[#knows + 1] = name end
        local k = snap({ chosen = { stance = "Berserker Stance" } }, knows)
        k.form = nil
        t.eq(ns.Choose(k, ns.Packs.WARRIOR).spell, "Berserker Stance", "known: the kept one")
    end,
}
