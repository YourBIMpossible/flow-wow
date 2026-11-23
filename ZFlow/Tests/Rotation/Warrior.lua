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
}
