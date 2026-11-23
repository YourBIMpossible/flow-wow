local _, ns = ...

-- The Rogue pack (lead section 197): it passes PackCheck, it is for yourself
-- and your own target only, stealth comes from the stealth read (nil is not
-- known, never "not stealthed"), the openers wait for stealth, and the
-- finishers wait for finisherReady (built by Rotation/Driver.lua from the
-- combo read or Rotation/Combo.lua's count; end to end in
-- Tests/E2E/RogueFinisher.lua).

local ALL = {
    "Stealth", "Ambush", "Garrote", "Cheap Shot", "Attack", "Sinister Strike", "Eviscerate",
    "Slice and Dice", "Evasion", "Kick", "Gouge",
}

-- Not stealthed (read), an enemy targeted, in the fight, swinging, no
-- finisher due, buffs and debuffs read and empty, everything known and ready.
local function snap(over, knows)
    local s = { role = "dps", hostile = true, inCombat = true, dead = false, attacking = true,
                stealthed = false, buffs = {}, targetDebuffs = {},
                current = { Attack = true }, spells = {} }
    for _, name in ipairs(knows or ALL) do
        s.spells[name] = { known = true, onCooldown = false, inRange = true }
    end
    for k, v in pairs(over or {}) do s[k] = v end
    return s
end

local function advice(over, knows)
    local r = ns.Choose(snap(over, knows), ns.Packs.ROGUE)
    return r and r.spell or nil
end

-- Out of a fight, an enemy targeted, not swinging.
local PULL = { inCombat = false, attacking = false, current = { Attack = false } }

local function without(name)
    local out = {}
    for _, n in ipairs(ALL) do if n ~= name then out[#out + 1] = n end end
    return out
end

return {
    ["rogue pack passes PackCheck"] = function(t)
        t.ok(type(ns.Packs.ROGUE) == "table", "ns.Packs.ROGUE")
        local ok, problems = ns.PackCheck(ns.Packs.ROGUE)
        t.eq(table.concat(problems or {}, "; "), "", "no problems")
        t.ok(ok, "ok")
    end,

    ["rogue pack has a dps role and Energy"] = function(t)
        local p = ns.Packs.ROGUE
        t.eq(p.roles.dps ~= nil, true, "a dps role")
        t.eq(p.roles.tank, nil, "no tank role")
        t.eq(p.resources[1].name, "Energy")
    end,

    ["every rule and spell row is marked first guess"] = function(t)
        for key, list in pairs(ns.Packs.ROGUE.lists) do
            for i, rule in ipairs(list) do
                t.eq(rule.evidence, "first guess", key .. " " .. i .. " " .. tostring(rule.spell))
            end
        end
        for name, row in pairs(ns.Packs.ROGUE.spells) do
            t.eq(row.evidence, "first guess", name)
        end
    end,

    ["an enemy out of a fight, not stealthed: Stealth first"] = function(t)
        t.eq(advice(PULL), "Stealth")
    end,

    ["stealth not read: no Stealth, no attack, no strike"] = function(t)
        local s = snap(PULL)
        s.stealthed = nil
        local r = ns.Choose(s, ns.Packs.ROGUE)
        local got = r and r.spell or nil
        t.ok(got ~= "Stealth" and got ~= "Attack" and got ~= "Sinister Strike", tostring(got))
    end,

    ["stealthed: the opener, Ambush first"] = function(t)
        t.eq(advice({ inCombat = false, attacking = false, stealthed = true, current = { Attack = false } }), "Ambush")
    end,

    ["Ambush the game refuses (no dagger in hand): Garrote"] = function(t)
        local s = snap({ inCombat = false, attacking = false, stealthed = true, current = { Attack = false } })
        s.spells.Ambush.usable = false
        t.eq(ns.Choose(s, ns.Packs.ROGUE).spell, "Garrote")
    end,

    ["stealthed, Ambush and Garrote not learned: Cheap Shot"] = function(t)
        local knows = {}
        for _, n in ipairs(ALL) do if n ~= "Ambush" and n ~= "Garrote" then knows[#knows + 1] = n end end
        t.eq(advice({ inCombat = false, attacking = false, stealthed = true, current = { Attack = false } }, knows),
            "Cheap Shot")
    end,

    ["stealthed: never the swing, never Stealth again"] = function(t)
        local got = advice({ stealthed = true, current = { Attack = false } })
        t.ok(got ~= "Attack" and got ~= "Stealth", tostring(got))
    end,

    ["Stealth not learned: Attack on the pull"] = function(t)
        t.eq(advice(PULL, without("Stealth")), "Attack")
    end,

    ["in the fight, swinging, no finisher due: Sinister Strike"] = function(t)
        t.eq(advice(), "Sinister Strike")
    end,

    ["finisherReady not given: no finisher is suggested"] = function(t)
        local got = advice({ buffs = {} })
        t.ok(got ~= "Eviscerate" and got ~= "Slice and Dice", tostring(got))
    end,

    ["a finisher due: Slice and Dice when it is off, else Eviscerate"] = function(t)
        t.eq(advice({ finisherReady = true }), "Slice and Dice")
        t.eq(advice({ finisherReady = true, buffs = { ["Slice and Dice"] = 2 } }), "Slice and Dice", "nearly out")
        t.eq(advice({ finisherReady = true, buffs = { ["Slice and Dice"] = 20 } }), "Eviscerate")
    end,

    ["a finisher due, buffs not read: Eviscerate, no Slice and Dice"] = function(t)
        local s = snap({ finisherReady = true })
        s.buffs = nil
        t.eq(ns.Choose(s, ns.Packs.ROGUE).spell, "Eviscerate")
    end,

    ["low health (the game's warning) in a fight: Evasion"] = function(t)
        t.eq(advice({ lowHealth = true }), "Evasion")
        t.eq(advice({ lowHealth = nil }), "Sinister Strike", "warning not read: no Evasion")
    end,

    ["the swing not read as off: no Attack"] = function(t)
        local got = advice({ current = nil, inCombat = false, attacking = false }, without("Stealth"))
        t.ok(got ~= "Attack", tostring(got))
    end,

    ["Kick is the interrupt, on your own target"] = function(t)
        local i = ns.Packs.ROGUE.interrupts
        t.eq(#i, 1)
        t.eq(i[1].spell, "Kick")
        local s = snap({ targetCasting = "Fireball" })
        t.eq(ns.Choose(s, ns.Packs.ROGUE).spell, "Kick")
    end,

    ["keys: a stealth row with no form, and a row for no form"] = function(t)
        local k = ns.Packs.ROGUE.keys
        t.ok(type(k.none) == "table", "none")
        t.ok(type(k.stealth) == "table", "stealth")
        t.eq(k.stealth.form, nil, "the stealth row belongs to no shapeshift form")
        local plan = ns.KeyPlan(ns.Packs.ROGUE, nil)
        t.eq(plan.states[0].key, "Sinister Strike", "the key out of stealth")
        t.eq(plan.states[ns.Rotation.STEALTH_STATE].key, "Ambush", "the key in stealth")
        t.eq(plan.condition, "[stealth] 9; 0", "condition")
    end,

    ["gear: leather is worn, mail, plate, shields and wands are not"] = function(t)
        local p = ns.Packs.ROGUE.proficiency
        t.eq(p.evidence, "first guess")
        t.eq(p[4][2], true, "leather")
        t.eq(p[4][3], nil, "mail")
        t.eq(p[4][4], nil, "plate")
        t.eq(p[4][6], nil, "shield")
        t.eq(p[2][15], true, "dagger")
        t.eq(p[2][7], true, "one-handed sword")
        t.eq(p[2][8], nil, "two-handed sword")
        t.eq(p[2][19], nil, "wand")
    end,

    ["not built, named: poisons and a talent order"] = function(t)
        t.eq(ns.Packs.ROGUE.talentBuilds, {})
        t.eq(ns.Packs.ROGUE.spells["Instant Poison"], nil, "no poison row")
    end,

    -- N58 (lead section 241): no own-choice row while no rule suggests a
    -- poison (Classes/Rogue.lua says what the row waits for).
    ["N58 rogue pack: no poison choice row while no rule suggests a poison"] = function(t)
        t.eq(ns.Packs.ROGUE.options.sticky, nil, "no sticky rows")
    end,
}
