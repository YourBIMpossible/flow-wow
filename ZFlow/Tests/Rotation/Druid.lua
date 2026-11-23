local _, ns = ...

-- The Druid pack: it passes PackCheck, and the form advice cases from
-- Modules/Tests/Class.lua hold against ns.Choose.

local FORMS = { "Dire Bear Form", "Bear Form", "Cat Form" }

-- An enemy targeted, not fighting yet, already swinging (so the engage step
-- stays out of the way), knowing only the form spells named. The form, your
-- buffs and the target's debuffs are read (section 186). A case that wants one
-- of these not read passes it as false in over, and it is then left nil.
local UNREAD = { formKnown = true, buffs = true, targetDebuffs = true, current = true }
local function snap(role, form, tree, knows, over)
    local s = { role = role, form = form, formKnown = true, tree = tree, hostile = true, inCombat = false,
                dead = false, attacking = true, spells = {}, buffs = {}, targetDebuffs = {} }
    for _, name in ipairs(knows or FORMS) do s.spells[name] = { known = true, onCooldown = false, inRange = true } end
    for k, v in pairs(over or {}) do
        if v == false and UNREAD[k] then s[k] = nil else s[k] = v end
    end
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

-- True when any rule of that spell in the list says yes to s.
local function anyWhen(list, spell, s)
    local seen = false
    for _, rule in ipairs(list) do
        if rule.spell == spell then
            seen = true
            if rule.when(s) then return true end
        end
    end
    assert(seen, "no rule for " .. spell)
    return false
end

return {
    -- Section 242, DRUID-3: each talent in the levelling build says why it
    -- is taken, in words of our own, and the build keeps its carried-over
    -- mark (the order and the meaning of each reason came with it).
    ["druid talent build: every talent says why, under the carried-over mark"] = function(t)
        local builds = ns.Packs.DRUID and ns.Packs.DRUID.talentBuilds or {}
        t.eq(#builds, 1, "one build")
        local build = builds[1] or {}
        t.eq(build.evidence, "first guess", "still a first guess")
        t.ok(type(build.note) == "string" and build.note:find("carried over", 1, true) ~= nil, "the carried-over mark")
        local order = build.order or {}
        t.eq(#order, 20, "twenty talents")
        local seen = {}
        for i, row in ipairs(order) do
            local why = row.why
            t.ok(type(why) == "string" and #why > 10, "talent " .. i .. " has a reason")
            if type(why) == "string" then
                t.eq(why:sub(-1), ".", "talent " .. i .. " ends as a sentence")
                t.ok(not why:find("Flow", 1, true), "talent " .. i .. " never names the add-on")
                t.ok(not seen[why], "talent " .. i .. " has its own reason")
                seen[why] = true
            end
        end
    end,

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
        t.eq(cat({ stealthed = false }, all), "Prowl", "before the pull, read as not stealthed")
        t.eq(cat({ stealthed = true }, all), "Ravage", "from stealth")
        t.eq(cat({ inCombat = true, finisherReady = true }, all), "Ferocious Bite", "the reader says a finisher is due")
        t.eq(cat({ inCombat = true, finisherReady = true }, { "Cat Form", "Rip", "Rake", "Claw" }), "Rip", "no Ferocious Bite: Rip")
        t.eq(cat({ inCombat = true }, all), "Rake", "Rake missing")
        t.eq(cat({ inCombat = true, targetDebuffs = { Rake = true } }, all), "Claw", "Rake is on it")
    end,

    ["stealth not known: no Prowl"] = function(t)
        local known = { "Cat Form", "Prowl" }
        local function cat(over)
            local got = ns.Choose(snap("dps", "Cat Form", "Feral", known, over), ns.Packs.DRUID)
            return got and got.spell or nil
        end
        t.eq(cat({ stealthed = false }), "Prowl", "read: not stealthed")
        t.eq(cat({}), nil, "not read: stealth is not assumed off")
        t.eq(cat({ stealthed = true }), nil, "read: already stealthed")
    end,

    ["stealth not known: neither attack rule starts the swing"] = function(t)
        for _, swing in ipairs({ "Attack", "Auto Attack" }) do
            for _, form in ipairs({ "Cat Form", "Bear Form", "Dire Bear Form" }) do
                local function animal(over)
                    local s = snap("dps", form, "Feral", { swing }, over)
                    s.inCombat, s.current = true, { [swing] = false }
                    local got = ns.Choose(s, ns.Packs.DRUID)
                    return got and got.spell or nil
                end
                local what = swing .. " in " .. form
                t.eq(animal({ stealthed = false }), swing, what .. ": read, not stealthed")
                t.eq(animal({}), nil, what .. ": not read, no swing")
                t.eq(animal({ stealthed = true }), nil, what .. ": stealthed, no swing")
            end
        end
    end,

    ["stealth not known: the rules themselves say no"] = function(t)
        local function when(list, spell, s)
            local rule = find(list, spell)
            return rule and rule.when(s) and true or false
        end
        local list = ns.Packs.DRUID.lists.default
        local function pull(stealthed)
            return { dead = false, inCombat = false, hostile = true, form = "Cat Form", stealthed = stealthed,
                     current = { Attack = false, ["Auto Attack"] = false } }
        end
        t.eq(when(list, "Prowl", pull(false)), true, "Prowl: read, not stealthed")
        t.eq(when(list, "Prowl", pull(nil)), false, "Prowl: not read")
        t.eq(when(list, "Prowl", pull(true)), false, "Prowl: stealthed")
        for _, swing in ipairs({ "Attack", "Auto Attack" }) do
            t.eq(when(list, swing, pull(false)), true, swing .. ": read, not stealthed")
            t.eq(when(list, swing, pull(nil)), false, swing .. ": not read")
            t.eq(when(list, swing, pull(true)), false, swing .. ": stealthed")
        end
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

    -- Section 186 (C1): a read that is nil is not known, and the rule skips.
    ["186 buffs not read: no Mark of the Wild, Thorns or Nature's Grasp"] = function(t)
        local list = ns.Packs.DRUID.lists.default
        for _, name in ipairs({ "Mark of the Wild", "Thorns" }) do
            local s = { dead = false, inCombat = false, hostile = true, formKnown = true }
            t.eq(anyWhen(list, name, s), false, name .. ": buffs not read")
            s.buffs = {}
            t.eq(anyWhen(list, name, s), true, name .. ": read, not up")
            s.buffs = { [name] = 1200 }
            t.eq(anyWhen(list, name, s), false, name .. ": read, up")
        end
        local grasp = { dead = false, inCombat = true, hostile = true, formKnown = true, targetMelee = true,
                        targetOnYou = true, hittingYou = true, targetDebuffs = {} }
        t.eq(anyWhen(list, "Nature's Grasp", grasp), false, "Nature's Grasp: buffs not read")
        grasp.buffs = {}
        t.eq(anyWhen(list, "Nature's Grasp", grasp), true, "Nature's Grasp: read, not up")
        grasp.buffs = { ["Nature's Grasp"] = true }
        t.eq(anyWhen(list, "Nature's Grasp", grasp), false, "Nature's Grasp: read, up")
    end,

    ["186 target debuffs not read: no Rip, Rake, Roar, roots, Grasp or Moonfire"] = function(t)
        local list = ns.Packs.DRUID.lists.default
        local cases = {
            { "Rip", "Rip", { form = "Cat Form", finisherReady = true } },
            { "Rake", "Rake", { form = "Cat Form" } },
            { "Demoralizing Roar", "Demoralizing Roar", { form = "Bear Form" } },
            { "Moonfire", "Moonfire", { formKnown = true } },
            { "Entangling Roots", "Entangling Roots", { formKnown = true, targetMelee = true, targetOnYou = true } },
            { "Nature's Grasp", "Entangling Roots", { formKnown = true, targetMelee = true, targetOnYou = true,
                                                     hittingYou = true } },
        }
        for _, case in ipairs(cases) do
            local spell, debuff = case[1], case[2]
            local s = { dead = false, inCombat = true, hostile = true, buffs = {} }
            for k, v in pairs(case[3]) do s[k] = v end
            t.eq(anyWhen(list, spell, s), false, spell .. ": target debuffs not read")
            s.targetDebuffs = {}
            t.eq(anyWhen(list, spell, s), true, spell .. ": read, not on it")
            s.targetDebuffs = { [debuff] = true }
            t.eq(anyWhen(list, spell, s), false, spell .. ": read, on it")
        end
        local known = { "Cat Form", "Rake", "Claw" }
        local got = advice("dps", "Cat Form", "Feral", known, { inCombat = true, targetDebuffs = false })
        t.eq(got, "Claw", "Cat Form, target debuffs not read: the builder, not Rake")
        t.eq(advice("dps", "Cat Form", "Feral", known, { inCombat = true }), "Rake", "read, not on it: Rake")
    end,

    ["186 current not read: no swing, no Maul, no weapon fallback"] = function(t)
        local list = ns.Packs.DRUID.lists.default
        for _, swing in ipairs({ "Attack", "Auto Attack" }) do
            local s = { dead = false, inCombat = true, hostile = true, form = "Cat Form", stealthed = false }
            t.eq(anyWhen(list, swing, s), false, swing .. ": current not read")
            s.current = {}
            t.eq(anyWhen(list, swing, s), false, swing .. ": left out of current, not known")
            s.current = { [swing] = true }
            t.eq(anyWhen(list, swing, s), false, swing .. ": read, already on")
            s.current = { [swing] = false }
            t.eq(anyWhen(list, swing, s), true, swing .. ": read, off")
        end
        local bear = { dead = false, inCombat = true, hostile = true, form = "Bear Form" }
        t.eq(anyWhen(list, "Maul", bear), false, "Maul: current not read")
        bear.current = {}
        t.eq(anyWhen(list, "Maul", bear), false, "Maul: left out of current, not known")
        bear.current = { Maul = true }
        t.eq(anyWhen(list, "Maul", bear), false, "Maul: read, queued")
        bear.current = { Maul = false }
        t.eq(anyWhen(list, "Maul", bear), true, "Maul: read, not queued")
        for _, swing in ipairs({ "Attack", "Auto Attack" }) do
            local s = { dead = false, inCombat = true, hostile = true, formKnown = true,
                        spells = { Wrath = { known = true, noPower = true } } }
            t.eq(anyWhen(list, swing, s), false, swing .. " for a caster out of mana: current not read")
            s.current = { [swing] = false }
            t.eq(anyWhen(list, swing, s), true, swing .. " for a caster out of mana: read, off")
        end
    end,

    ["186 form not known: not caster, and no Cat Form"] = function(t)
        local list = ns.Packs.DRUID.lists.default
        local function with(formKnown, form)
            return { dead = false, inCombat = false, hostile = true, buffs = {}, targetDebuffs = {},
                     targetMelee = true, role = "dps", tree = "Feral", form = form, formKnown = formKnown }
        end
        for _, spell in ipairs({ "Mark of the Wild", "Thorns", "Moonfire", "Wrath", "Entangling Roots", "Cat Form" }) do
            t.eq(anyWhen(list, spell, with(nil)), false, spell .. ": form not known")
            t.eq(anyWhen(list, spell, with(true)), true, spell .. ": read, no form")
        end
        t.eq(anyWhen(list, "Wrath", with(nil, "Moonkin Form")), true, "Moonkin Form named: caster")
        t.eq(anyWhen(list, "Cat Form", with(nil, "Moonkin Form")), false, "Moonkin Form named: no Cat Form")
        local cure = find(ns.Packs.DRUID.dispels, "Cure Poison")
        t.eq(cure.when(with(nil)) and true or false, false, "Cure Poison: form not known")
        t.eq(cure.when(with(true)) and true or false, true, "Cure Poison: read, no form")
        t.eq(advice("dps", nil, "Feral", nil, { formKnown = false }), nil, "form not known: no Cat Form")
        t.eq(advice("dps", nil, "Feral"), "Cat Form", "read, no form: Cat Form")
        t.eq(ns.DruidWantsCat("dps", true, nil, "Feral"), true, "the predicate itself is unchanged")
    end,
}
