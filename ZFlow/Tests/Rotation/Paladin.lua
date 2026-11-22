local _, ns = ...

-- The Paladin pack: it passes PackCheck, it is for yourself and your own
-- target only, and its list gives the old order against ns.Choose.

local ALL = {
    "Devotion Aura", "Blessing of Might", "Blessing of Wisdom", "Seal of Righteousness", "Judgement",
    "Hammer of Wrath", "Holy Wrath", "Hammer of Justice", "Flash of Light", "Holy Light", "Purify",
}
local READY = { ["Devotion Aura"] = true, ["Blessing of Might"] = true, ["Seal of Righteousness"] = true }

-- An enemy targeted, in the fight, already swinging, aura, blessing and seal up.
local function snap(over, knows, buffs)
    local s = { role = "dps", hostile = true, inCombat = true, dead = false, attacking = true,
                current = { Attack = true, ["Auto Attack"] = true }, spells = {}, buffs = buffs or READY }
    for _, name in ipairs(knows or ALL) do s.spells[name] = { known = true } end
    for k, v in pairs(over or {}) do s[k] = v end
    return s
end

local function advice(over, knows, buffs)
    local s = ns.Choose(snap(over, knows, buffs), ns.Packs.PALADIN)
    return s and s.spell or nil, s
end

local IDLE = { hostile = false, inCombat = false }

return {
    ["paladin pack passes PackCheck"] = function(t)
        local ok, problems = ns.PackCheck(ns.Packs.PALADIN)
        t.eq(table.concat(problems, "; "), "", "no problems")
        t.ok(ok, "ok")
    end,

    ["nothing is for the group: no group rows, every dispel is for yourself"] = function(t)
        local p = ns.Packs.PALADIN
        t.eq(p.groups, {}, "groups")
        for _, rule in ipairs(p.dispels) do
            t.ok(not rule.group and rule.unit == nil, rule.spell .. " is not a group entry")
        end
        t.eq(p.heals.self, { "Flash of Light", "Holy Light" }, "heals are the self list")
    end,

    ["no rule suggests a spell cast on another player"] = function(t)
        local other = { ["Lay on Hands"] = true, ["Blessing of Protection"] = true, ["Redemption"] = true,
                        ["Righteous Fury"] = true, ["Blessing of Freedom"] = true, ["Blessing of Salvation"] = true,
                        ["Divine Intervention"] = true }
        local p = ns.Packs.PALADIN
        for name, list in pairs(p.lists) do
            for _, rule in ipairs(list) do t.ok(not other[rule.spell], name .. ": " .. rule.spell) end
        end
        for _, rule in ipairs(p.interrupts) do t.ok(not other[rule.spell], rule.spell) end
        for _, name in ipairs(p.heals.self) do t.ok(not other[name], name) end
    end,

    ["every spell fact is a first guess: none is marked observed"] = function(t)
        local n = 0
        for name, row in pairs(ns.Packs.PALADIN.spells) do
            n = n + 1
            t.eq(row.evidence, "first guess", name)
        end
        t.ok(n >= 30, "the spell list is there")
        for name, list in pairs(ns.Packs.PALADIN.lists) do
            for _, rule in ipairs(list) do t.eq(rule.evidence, "first guess", name .. ": " .. rule.spell) end
        end
    end,

    ["the rows taken out of the old spell list stay out"] = function(t)
        for _, name in ipairs({ "Holy Strike", "Seal of Fury", "Consecration", "Blessing of Kings",
                                "Judgment", "Crusader Strike", "Shield of the Righteous", "Word of Glory" }) do
            t.eq(ns.Packs.PALADIN.spells[name], nil, name)
        end
    end,

    ["out of a fight: aura, then blessing, then seal, then nothing"] = function(t)
        t.eq(advice(IDLE, nil, {}), "Devotion Aura", "no aura")
        t.eq(advice(IDLE, nil, { ["Devotion Aura"] = true }), "Blessing of Might", "no blessing")
        t.eq(advice(IDLE, nil, { ["Devotion Aura"] = true, ["Blessing of Might"] = 600 }),
             "Seal of Righteousness", "no seal")
        t.eq(advice(IDLE), nil, "all up")
    end,

    ["another aura, or the aura shown as your stance, counts as an aura"] = function(t)
        t.eq(advice(IDLE, nil, { ["Retribution Aura"] = true }), "Blessing of Might", "another aura")
        t.eq(advice({ hostile = false, inCombat = false, form = "Concentration Aura" }, nil, {}),
             "Blessing of Might", "the stance")
    end,

    ["a blessing is recast with under 30 s left, and never in a fight"] = function(t)
        local low = { ["Devotion Aura"] = true, ["Blessing of Might"] = 20, ["Seal of Righteousness"] = true }
        t.eq(advice(IDLE, nil, low), "Blessing of Might", "20 s left")
        t.eq(advice(nil, nil, low), "Judgement", "in a fight: left alone")
        t.eq(advice(nil, nil, { ["Devotion Aura"] = true, ["Seal of Righteousness"] = true }),
             "Judgement", "none up, in a fight")
    end,

    ["a blessing you put up yourself is left alone"] = function(t)
        t.eq(advice(IDLE, nil, { ["Devotion Aura"] = true, ["Blessing of Kings"] = 600,
                                 ["Seal of Righteousness"] = true }), nil, "another blessing")
    end,

    ["a healer who knows Blessing of Wisdom is given it; otherwise Might"] = function(t)
        local b = { ["Devotion Aura"] = true }
        t.eq(advice({ hostile = false, inCombat = false, role = "heal" }, nil, b), "Blessing of Wisdom", "healer")
        t.eq(advice({ hostile = false, inCombat = false, role = "heal" },
                    { "Blessing of Might", "Seal of Righteousness" }, b), "Blessing of Might", "Wisdom not known")
        t.eq(advice({ hostile = false, inCombat = false, role = "tank" }, nil, b), "Blessing of Might", "tank")
    end,

    ["the seal: recast under 3 s in a fight, under 8 s before the pull"] = function(t)
        local function with(left) return { ["Devotion Aura"] = true, ["Blessing of Might"] = true,
                                           ["Seal of Righteousness"] = left } end
        t.eq(advice(nil, nil, with(2)), "Seal of Righteousness", "2 s, fighting")
        t.eq(advice(nil, nil, with(5)), "Judgement", "5 s, fighting")
        t.eq(advice({ inCombat = false }, nil, with(5)), "Seal of Righteousness", "5 s, before the pull")
        t.eq(advice({ inCombat = false }, nil, with(20)), "Judgement", "20 s, before the pull")
        t.eq(advice(IDLE, nil, with(5)), nil, "5 s, no enemy: left alone")
        t.eq(ns.PaladinWantsSeal({ buffs = {} }), true, "none up")
        t.eq(ns.PaladinWantsSeal({ buffs = { ["Seal of Light"] = true }, inCombat = true }), false, "another seal")
    end,

    ["a dps paladin who knows Seal of Command is given it"] = function(t)
        local knows = { "Seal of Righteousness", "Seal of Command", "Judgement" }
        local b = { ["Devotion Aura"] = true, ["Blessing of Might"] = true }
        t.eq(advice(nil, knows, b), "Seal of Command", "dps")
        t.eq(advice({ role = "heal" }, knows, b), "Seal of Righteousness", "healer")
        t.eq(advice({ role = "tank" }, knows, b), "Seal of Righteousness", "tank")
    end,

    ["Judgement only with a seal up and an enemy targeted"] = function(t)
        t.eq(advice(), "Judgement", "seal up")
        t.eq(advice(nil, { "Judgement" }, { ["Devotion Aura"] = true, ["Blessing of Might"] = true }),
             nil, "no seal, and no seal known")
        t.eq(advice({ hostile = false }), nil, "no enemy")
        local s = snap()
        s.spells.Judgement.inRange = false
        local far = ns.Choose(s, ns.Packs.PALADIN)
        t.eq(far.step, "farOpener", "out of range: shown as out of range, not as the next cast")
        t.eq(far.label, "Out of range", "label")
    end,

    ["Hammer of Wrath comes before Judgement when the game lets you cast it"] = function(t)
        local s = snap()
        s.spells["Hammer of Wrath"].usable = true
        t.eq(ns.Choose(s, ns.Packs.PALADIN).spell, "Hammer of Wrath", "usable")
        s.spells["Hammer of Wrath"].usable = false
        t.eq(ns.Choose(s, ns.Packs.PALADIN).spell, "Judgement", "not usable")
    end,

    ["not attacking yet: start the attack first"] = function(t)
        t.eq(advice({ current = {} }, { "Attack", "Judgement" }), "Attack", "Attack")
        t.eq(advice({ current = {} }, { "Auto Attack", "Judgement" }), "Auto Attack", "Auto Attack")
    end,

    ["several enemies: Holy Wrath, in the fight only"] = function(t)
        local s = snap({ fightType = "aoe" })
        s.spells["Hammer of Wrath"].usable = false
        t.eq(ns.Choose(s, ns.Packs.PALADIN).spell, "Holy Wrath", "fighting")
        s.inCombat = nil
        t.eq(ns.Choose(s, ns.Packs.PALADIN).spell, "Holy Wrath", "not known whether the fight is on: as in the fight")
        s.inCombat = false
        t.eq(ns.Choose(s, ns.Packs.PALADIN).spell, "Judgement", "before the pull")
    end,

    ["low health: the quick heal on yourself"] = function(t)
        local s = snap({ lowHealth = true })
        s.spells["Flash of Light"].castMs = 1500
        s.spells["Holy Light"].castMs = 2500
        local got = ns.Choose(s, ns.Packs.PALADIN)
        t.eq(got.spell, "Flash of Light", "spell")
        t.eq(got.kind, "emergency", "kind")
        t.eq(got.step, "heal", "step")
    end,

    ["your target starts a cast: Hammer of Justice"] = function(t)
        local got = ns.Choose(snap({ targetCasting = true }), ns.Packs.PALADIN)
        t.eq(got.spell, "Hammer of Justice", "spell")
        t.eq(got.step, "interrupt", "step")
        t.eq(advice({ targetCasting = true, inCombat = false }), "Judgement", "not in a fight: no interrupt")
    end,

    ["a poison on you is removed out of a fight only"] = function(t)
        local got = ns.Choose(snap({ hostile = false, inCombat = false, debuffTypes = { Poison = true } }),
                              ns.Packs.PALADIN)
        t.eq(got.spell, "Purify", "spell")
        t.eq(got.step, "dispel", "step")
        t.eq(advice({ debuffTypes = { Poison = true } }), "Judgement", "in a fight")
        t.eq(advice({ hostile = false, inCombat = false, debuffTypes = { Magic = true } }), nil,
             "Purify does not take magic off")
    end,

    ["resting in town: no buff is asked for"] = function(t)
        t.eq(advice({ hostile = false, inCombat = false, resting = true }, nil, {}), nil, "resting")
    end,

    ["no reason spells the addon's name"] = function(t)
        local n = 0
        for _, list in pairs(ns.Packs.PALADIN.lists) do
            for _, rule in ipairs(list) do
                n = n + 1
                t.ok(not string.find(string.lower(rule.reason), "flow", 1, true), rule.spell)
            end
        end
        t.ok(n > 0, "rules were read")
    end,

    ["the key plan: one row, and it goes into the cast plan"] = function(t)
        local plan = ns.KeyPlan(ns.Packs.PALADIN, nil)
        t.eq(plan.condition, "0", "no forms")
        t.eq(plan.states, { [0] = { key = "Judgement", ctrl = "Exorcism", more = "Hammer of Wrath" } }, "states")
        plan = ns.KeyPlan(ns.Packs.PALADIN, { known = { ["Seal of Righteousness"] = true } })
        t.eq(plan.states[0], { key = "Seal of Righteousness" }, "level 1: the seal on the key")
        plan = ns.KeyPlan(ns.Packs.PALADIN, { slots = { "ctrl", "shift", "alt", "more" } })
        local r = ns.cast.Apply(plan, nil, false)
        t.eq(r.ok, true, "applied")
        t.eq(r.counts.set, 5, "five slots set")
        t.eq(r.ops[1], { op = "set", state = 0, slot = "key", spell = "Judgement" }, "key first")
    end,

    ["the paladin pack is on ns.Packs, and registered when the kernel is loaded"] = function(t)
        t.ok(type(ns.Packs.PALADIN) == "table", "ns.Packs.PALADIN")
        if type(ns.Get) == "function" then
            t.eq(ns:Get("classPack", "PALADIN"), ns.Packs.PALADIN, "registered as a classPack")
        end
    end,
}
