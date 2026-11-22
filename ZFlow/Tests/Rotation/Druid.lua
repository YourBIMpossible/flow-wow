local _, ns = ...

-- The Druid pack: it passes PackCheck, and the form advice cases from
-- Modules/Tests/Class.lua hold against ns.Choose.

local FORMS = { "Dire Bear Form", "Bear Form", "Cat Form" }

-- An enemy targeted, not fighting yet, already swinging (so the engage step
-- stays out of the way), knowing only the form spells named.
local function snap(role, form, tree, knows, over)
    local s = { role = role, form = form, tree = tree, hostile = true, inCombat = false, dead = false,
                attacking = true, spells = {} }
    for _, name in ipairs(knows or FORMS) do s.spells[name] = { known = true, onCooldown = false } end
    for k, v in pairs(over or {}) do s[k] = v end
    return s
end

local function advice(role, form, tree, knows, over)
    local s = ns.Choose(snap(role, form, tree, knows, over), ns.Packs.DRUID)
    return s and s.spell or nil, s
end

local function find(list, spell)
    for _, rule in ipairs(list) do
        if rule.spell == spell then return rule end
    end
end

return {
    ["druid pack passes PackCheck"] = function(t)
        local ok, problems = ns.PackCheck(ns.Packs.DRUID)
        t.eq(table.concat(problems, "; "), "", "no problems")
        t.ok(ok, "ok")
    end,

    ["druid pack has no group dispel entry and every dispel is for yourself"] = function(t)
        for _, rule in ipairs(ns.Packs.DRUID.dispels) do
            t.ok(not rule.group and rule.unit == nil, rule.spell .. " is not a group entry")
        end
    end,

    ["druid pack marks every spell with an evidence class and none as observed"] = function(t)
        local n = 0
        for name, row in pairs(ns.Packs.DRUID.spells) do
            n = n + 1
            t.eq(row.evidence, "first guess", name)
        end
        t.ok(n > 40, "the spell rows are there")
    end,

    ["cat form: dps in no form with feral talents"] = function(t)
        t.eq(advice("dps", nil, "Feral"), "Cat Form", "pull")
    end,

    ["cat form: dps with talents unread"] = function(t)
        t.eq(advice("dps", nil, nil), "Cat Form", "tree unknown is not Balance")
    end,

    ["cat form: dps in a fight with nothing targeted"] = function(t)
        t.eq(advice("dps", nil, "Feral", nil, { hostile = false, inCombat = true }), "Cat Form", "in combat")
    end,

    ["cat form: not while travelling with nothing targeted"] = function(t)
        t.eq(advice("dps", nil, "Feral", nil, { hostile = false, inCombat = false }), nil, "no fight to take")
    end,

    ["cat form: the rule is a buff, says suggested, and is in both lists"] = function(t)
        local pack = ns.Packs.DRUID
        local rule = find(pack.lists.default, "Cat Form")
        t.ok(rule ~= nil, "in the default list")
        t.eq(rule.kind, "buff", "kind")
        t.ok(string.find(rule.reason, "Suggested", 1, true) ~= nil, "reason says Suggested")
        t.ok(find(pack.lists.aoe, "Cat Form") == rule, "the same rule in the aoe list")
        t.eq(rule.evidence, "authored", "an authored model")
        t.ok(type(rule.provenance) == "string" and #rule.provenance > 0, "with its provenance note")
        local _, s = advice("dps", nil, "Feral")
        t.eq(s.kind, "buff", "suggested as a buff")
        t.eq(s.step, "list", "from the priority list")
        local spell = advice("dps", nil, "Feral", nil, { fightType = "aoe" })
        t.eq(spell, "Cat Form", "several enemies too")
    end,

    ["cat form: not in the default rest state"] = function(t)
        t.eq(advice("dps", nil, "Feral", nil, { hostile = false, resting = true }), nil, "resting in town")
        -- Resting decides on its own: the same enemy targeted, resting or not.
        t.eq(advice("dps", nil, "Feral", nil, { hostile = true, resting = true }), nil, "an enemy targeted while resting: still nothing")
        t.eq(advice("dps", nil, "Feral", nil, { hostile = true, resting = false }), "Cat Form", "the same enemy, not resting: Cat Form")
        t.eq(advice("dps", nil, "Feral", nil, { hostile = false, resting = false }), nil, "no enemy and not resting: nothing either")
        t.eq(advice("dps", nil, "Feral", nil, { hostile = false, inCombat = true, resting = true }), "Cat Form",
            "in a fight while resting: Cat Form")
    end,

    ["bear form: a tank gets dire bear form when known"] = function(t)
        t.eq(advice("tank", nil, "Feral"), "Dire Bear Form", "all forms known")
    end,

    ["bear form: a tank without dire bear gets bear form"] = function(t)
        t.eq(advice("tank", nil, "Feral", { "Bear Form", "Cat Form" }), "Bear Form", "no Dire Bear")
    end,

    ["bear form: a tank already in bear form gets nothing"] = function(t)
        t.eq(advice("tank", "Bear Form", "Feral"), nil, "Bear Form")
        t.eq(advice("tank", "Dire Bear Form", "Feral"), nil, "Dire Bear Form")
    end,

    ["cat form: never for a tank"] = function(t)
        t.eq(advice("tank", nil, "Feral", { "Cat Form" }), nil, "a tank knowing only Cat Form")
        t.ok(advice("tank", nil, nil) ~= "Cat Form", "a tank knowing all forms")
        t.eq(advice("tank", nil, "Feral", { "Cat Form" }, { inCombat = true }), nil, "nor in a fight already under way")
        t.eq(advice("tank", nil, "Feral", { "Cat Form" }, { fightType = "aoe" }), nil, "nor against several")
        -- The same call with the role changed does give Cat Form: the role decides.
        t.eq(advice("dps", nil, "Feral", { "Cat Form" }), "Cat Form", "a dps knowing only Cat Form gets it")
        t.eq(ns.DruidWantsCat("tank", true, nil, "Feral"), false, "the cat rule says no to a tank in a fight")
        t.eq(ns.DruidWantsCat("dps", true, nil, "Feral"), true, "and yes to a dps in the same fight")
    end,

    ["cat form: a dps who knows only bear form gets nothing"] = function(t)
        t.eq(advice("dps", nil, "Feral", { "Bear Form" }), nil, "only Bear Form known")
    end,

    ["cat form: knowing no form gets nothing"] = function(t)
        t.eq(advice("dps", nil, "Feral", {}), nil, "no form known")
    end,

    ["cat form: not for a balance build"] = function(t)
        t.eq(advice("dps", nil, "Balance"), nil, "Balance talents")
    end,

    ["cat form: moonkin form is left alone"] = function(t)
        t.eq(advice("dps", "Moonkin Form", "Balance"), nil, "Balance")
        t.eq(advice("dps", "Moonkin Form", nil), nil, "tree unknown")
    end,

    ["cat form: not for the heal role"] = function(t)
        t.eq(advice("heal", nil, "Restoration"), nil, "Restoration talents")
        t.eq(advice("heal", nil, "Feral"), nil, "Feral talents")
    end,

    ["cat form: a form you chose is left alone"] = function(t)
        t.eq(advice("dps", "Travel Form", "Feral"), nil, "Travel Form")
        t.eq(advice("dps", "Aquatic Form", "Feral"), nil, "Aquatic Form")
        t.eq(advice("dps", "Bear Form", "Feral"), nil, "Bear Form")
    end,

    ["cat form: already in cat form gets nothing"] = function(t)
        t.eq(advice("dps", "Cat Form", "Feral"), nil, "on a pull")
        t.eq(advice("dps", "Cat Form", "Feral", nil, { inCombat = true }), nil, "in a fight")
        t.eq(ns.DruidWantsCat("dps", true, "Cat Form", nil), false, "the predicate")
    end,

    ["cat list: opener from stealth, then finisher, bleed, builder"] = function(t)
        local function cat(over, known)
            local s = snap("dps", "Cat Form", "Feral", known, over)
            local got = ns.Choose(s, ns.Packs.DRUID)
            return got and got.spell or nil
        end
        local all = { "Cat Form", "Prowl", "Ravage", "Pounce", "Shred", "Ferocious Bite", "Rip", "Rake", "Claw" }
        t.eq(cat({}, all), "Prowl", "before the pull, not stealthed")
        t.eq(cat({ stealthed = true }, all), "Ravage", "from stealth")
        t.eq(cat({ inCombat = true, finisherReady = true }, all), "Ferocious Bite", "the reader says a finisher is due")
        t.eq(cat({ inCombat = true, finisherReady = true }, { "Cat Form", "Rip", "Rake", "Claw" }), "Rip", "no Ferocious Bite: Rip")
        t.eq(cat({ inCombat = true }, all), "Rake", "Rake missing")
        t.eq(cat({ inCombat = true, targetDebuffs = { Rake = true } }, all), "Claw", "Rake is on it")
    end,

    ["caster list: buffs out of a fight, then moonfire, then wrath"] = function(t)
        local known = { "Mark of the Wild", "Thorns", "Moonfire", "Wrath" }
        local function cast(over)
            local got = ns.Choose(snap("heal", nil, "Restoration", known, over), ns.Packs.DRUID)
            return got and got.spell or nil
        end
        t.eq(cast({}), "Mark of the Wild", "no buff on you")
        t.eq(cast({ buffs = { ["Mark of the Wild"] = 1200 } }), "Thorns", "Mark is up")
        t.eq(cast({ buffs = { ["Mark of the Wild"] = 30, Thorns = 500 } }), "Mark of the Wild", "Mark running out")
        local up = { ["Mark of the Wild"] = 1200, Thorns = 500 }
        t.eq(cast({ buffs = up }), "Moonfire", "Moonfire missing")
        t.eq(cast({ buffs = up, targetDebuffs = { Moonfire = true } }), "Wrath", "Moonfire is on it")
        t.eq(cast({ inCombat = true, targetDebuffs = { Moonfire = true } }), "Wrath", "no buffs in a fight")
    end,

    ["rooted: shift to break free, not into the form you are in"] = function(t)
        local known = { "Cat Form", "Bear Form" }
        local s = ns.Choose(snap("dps", "Cat Form", "Feral", known, { loc = "ROOT", inCombat = true }), ns.Packs.DRUID)
        t.eq(s and s.spell, "Bear Form", "in Cat Form: Bear Form")
        t.eq(s and s.step, "breakFree", "the first step")
    end,

    ["poisoned out of a fight: your own cure, never in a fight"] = function(t)
        local known = { "Cure Poison" }
        local s = ns.Choose(snap("dps", nil, "Feral", known, { hostile = false, debuffTypes = { Poison = "Venom" } }), ns.Packs.DRUID)
        t.eq(s and s.spell, "Cure Poison", "out of a fight")
        t.eq(s and s.unit, "player", "on yourself")
        s = ns.Choose(snap("heal", nil, "Restoration", known, { inCombat = true, debuffTypes = { Poison = "Venom" } }), ns.Packs.DRUID)
        t.eq(s, nil, "nothing in a fight, also as a healer")
    end,
}
