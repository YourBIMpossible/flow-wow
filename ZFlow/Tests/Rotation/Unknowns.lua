local _, ns = ...
-- A flag nobody read is not "no". The snapshot keeps it nil, and the chooser
-- and the cast plan take the careful side of each one:
--   dead not known       nothing is suggested
--   inCombat not known   counts as a fight: what a fight forbids is not
--                        suggested (a dispel, starting the attack, a top-up
--                        heal, a buff kept for out of a fight); an interrupt
--                        is allowed
--   lockdown not known   the keys are not changed
-- Tests not executed where they were written.
local R = ns.Rotation

local function rule(spell, extra)
    local r = { spell = spell, evidence = "first guess" }
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
end

local function pack()
    return {
        lists = {
            default = {
                rule("Shield", { kind = "buff", when = function(s) return not (s.buffs and s.buffs.Shield) end }),
                rule("Bolt", { target = true }),
            },
        },
        heals = { self = { "Mend", "Big Mend", "Renew" }, hots = { "Renew" }, lingers = {} },
        interrupts = { rule("Kick", { near = true }), rule("Silence") },
        breakers = { rule("Slip", { types = { ROOT = true } }) },
        dispels = { rule("Cleanse", { types = { Poison = true } }) },
    }
end

local ALL = { "Shield", "Bolt", "Mend", "Big Mend", "Renew", "Kick", "Silence", "Slip", "Cleanse", "Attack" }

-- Alive, every spell known; inCombat is left out unless `over` gives it.
local function snap(over, known)
    local s = { dead = false, spells = {} }
    for _, name in ipairs(known or ALL) do s.spells[name] = { known = true, onCooldown = false } end
    for k, v in pairs(over or {}) do s[k] = v end
    return s
end

local function with(base, key, value)
    local out = {}
    for k, v in pairs(base) do out[k] = v end
    out[key] = value
    return out
end

local function stepOf(over, p)
    local s = ns.Choose(snap(over), p or pack())
    return s and s.step or nil, s
end

local function keyPlan()
    return { states = { [0] = { key = "Wrath" } }, condition = "0" }
end

local T = {}

T["snapshot: a flag not given stays nil, no stays false, yes stays true"] = function(t)
    local none = ns.SnapshotOf({})
    local no, yes, flags = {}, {}, 0
    for _, f in ipairs(R.SNAPSHOT_FIELDS) do
        if f[2] == "flag" then
            flags = flags + 1
            no[f[1]], yes[f[1]] = false, 1
        end
    end
    t.ok(flags > 0, "the snapshot has flags")
    local saidNo, saidYes = ns.SnapshotOf(no), ns.SnapshotOf(yes)
    for _, f in ipairs(R.SNAPSHOT_FIELDS) do
        if f[2] == "flag" then
            t.eq(none[f[1]], nil, f[1] .. " not given")
            t.eq(saidNo[f[1]], false, f[1] .. " given as no")
            t.eq(saidYes[f[1]], true, f[1] .. " given as yes")
            t.eq(ns.SnapshotOf({ [f[1]] = "x" })[f[1]], true, f[1] .. " given as some other value")
        end
    end
end

T["snapshot: a flag the reader did not answer stays nil"] = function(t)
    local s = ns.Snapshot(function(name)
        if name == "hostile" then return true end
        if name == "resting" then return false end
    end)
    t.eq(s.hostile, true)
    t.eq(s.resting, false)
    t.eq(s.inCombat, nil, "inCombat not answered")
    t.eq(s.dead, nil, "dead not answered")
end

T["chooser: dead not known, nothing is suggested"] = function(t)
    local busy = { inCombat = false, hostile = true, loc = "ROOT", lowHealth = true, canStartAttack = true }
    local s = ns.Choose(snap(busy), pack())
    t.eq(s and s.spell, "Slip", "alive: the first step answers")

    local unknown = snap(busy)
    unknown.dead = nil
    local none, trace = ns.Choose(unknown, pack())
    t.eq(none, nil, "dead not known")
    t.eq(#trace, 1, "one trace row")
    t.eq(trace[1].step, "dead")
    t.eq(trace[1].result, "skip")
    t.ok(type(trace[1].note) == "string" and trace[1].note ~= "", "the row says why")

    local built = ns.SnapshotOf({ inCombat = false, hostile = true, lowHealth = true,
                                  spells = { Mend = { known = true, onCooldown = false } } })
    t.eq(built.dead, nil, "the built snapshot keeps dead unknown")
    t.eq(ns.Choose(built, pack()), nil, "and nothing is suggested from it")
end

T["chooser: dead, nothing is suggested"] = function(t)
    local none, trace = ns.Choose(snap({ dead = true, inCombat = true, hostile = true, loc = "ROOT" }), pack())
    t.eq(none, nil)
    t.eq(#trace, 1, "one trace row")
    t.eq(trace[1].step, "dead")
end

T["chooser: an empty snapshot gives nothing and the one row"] = function(t)
    local none, trace = ns.Choose({}, pack())
    t.eq(none, nil)
    t.eq(#trace, 1)
    t.eq(trace[1].step, "dead", "not the bad-input row")
    t.eq(R.InFight({}), true, "not known counts as a fight")
    t.eq(R.OutOfFight({}), false, "and not as out of one")
    t.eq(R.InFight({ inCombat = false }), false)
    t.eq(R.OutOfFight({ inCombat = false }), true)
    t.eq(R.InFight({ inCombat = true }), true)
    t.eq(R.OutOfFight({ inCombat = true }), false)
end

T["chooser: combat not known, no dispel"] = function(t)
    local over = { debuffTypes = { Poison = "Venom" } }
    t.eq(stepOf(with(over, "inCombat", false)), "dispel", "out of a fight")
    t.ok(stepOf(with(over, "inCombat", true)) ~= "dispel", "in a fight")
    local s, trace = ns.Choose(snap(over), pack())
    t.ok(not s or s.step ~= "dispel", "not known")
    t.ok(not s or s.spell ~= "Cleanse", "Cleanse is not suggested")
    local note
    for _, row in ipairs(trace) do
        if row.step == "dispel" then note = row.note end
    end
    t.ok(type(note) == "string" and string.find(note, "not known", 1, true) ~= nil, "the trace says it is not known")
end

T["chooser: combat not known, the attack is not started"] = function(t)
    local over = { hostile = true, canStartAttack = true }
    local step, s = stepOf(with(over, "inCombat", false))
    t.eq(step, "engage", "before the pull")
    t.eq(s and s.spell, "Attack")
    t.ok(stepOf(with(over, "inCombat", true)) ~= "engage", "in a fight")
    t.ok(stepOf(over) ~= "engage", "not known")
end

T["chooser: combat not known, an interrupt is allowed"] = function(t)
    local over = { hostile = true, attacking = true, targetCasting = "Fireball", targetNear = true }
    local step, s = stepOf(with(over, "inCombat", true))
    t.eq(step, "interrupt", "in a fight")
    t.eq(s and s.spell, "Kick")
    t.ok(stepOf(with(over, "inCombat", false)) ~= "interrupt", "out of a fight")
    local unknownStep, got = stepOf(over)
    t.eq(unknownStep, "interrupt", "not known: counts as a fight")
    t.eq(got and got.spell, "Kick")
    t.ok(stepOf({ targetCasting = "Fireball", targetNear = true }) ~= "interrupt", "enemy not known: no interrupt")
end

T["chooser: combat not known, no top-up heal, a needed heal all the same"] = function(t)
    local little = { hurt = R.HURT.outStart + 1 }
    t.ok(little.hurt < R.HURT.inHot, "the case is a top-up only")
    t.eq(stepOf(with(little, "inCombat", false)), "heal", "out of a fight: top up")
    t.ok(stepOf(with(little, "inCombat", true)) ~= "heal", "in a fight: not yet")
    t.ok(stepOf(little) ~= "heal", "not known: no top-up")

    local much = { hurt = R.HURT.inHeal }
    t.eq(stepOf(with(much, "inCombat", true)), "heal", "in a fight: heal")
    t.eq(stepOf(much), "heal", "not known: the in-fight rule still heals")

    local step, s = stepOf({ lowHealth = true })
    t.eq(step, "heal", "the game's warning gets a heal, combat known or not")
    t.eq(s and s.kind, "emergency", "not known: as in a fight")
    local _, calm = stepOf({ lowHealth = true, inCombat = false })
    t.eq(calm and calm.kind, "heal", "out of a fight")
end

T["chooser: resting holds a buff back only when known to be out of a fight"] = function(t)
    local function spell(over)
        local s = ns.Choose(snap(over, { "Shield" }), pack())
        return s and s.spell or nil
    end
    t.eq(spell({ resting = true, inCombat = false }), nil, "resting, out of a fight: held back")
    t.eq(spell({ resting = true, inCombat = true }), "Shield", "resting, in a fight")
    t.eq(spell({ resting = true }), "Shield", "resting, combat not known: not held back")
    t.eq(spell({ inCombat = false }), "Shield", "resting not known: not held back")
end

T["druid: combat not known, no out-of-fight buff and no Prowl"] = function(t)
    local function druid(over, role, form, tree, known)
        local s = { dead = false, role = role, form = form, tree = tree, hostile = true, attacking = true, spells = {} }
        for _, name in ipairs(known) do s.spells[name] = { known = true, onCooldown = false } end
        for k, v in pairs(over or {}) do s[k] = v end
        local got = ns.Choose(s, ns.Packs.DRUID)
        return got and got.spell or nil
    end
    local caster = { "Mark of the Wild", "Thorns", "Moonfire", "Wrath" }
    local onIt = { targetDebuffs = { Moonfire = true } }
    t.eq(druid(with(onIt, "inCombat", false), "heal", nil, "Restoration", caster), "Mark of the Wild", "out of a fight")
    t.eq(druid(with(onIt, "inCombat", true), "heal", nil, "Restoration", caster), "Wrath", "in a fight")
    t.eq(druid(onIt, "heal", nil, "Restoration", caster), "Wrath", "not known: no buff")

    local cat = { "Cat Form", "Prowl", "Rake", "Claw" }
    t.eq(druid({ inCombat = false }, "dps", "Cat Form", "Feral", cat), "Prowl", "before the pull")
    t.ok(druid({}, "dps", "Cat Form", "Feral", cat) ~= "Prowl", "not known: no Prowl")

    local buffs = { "Mark of the Wild", "Thorns", "Wrath" }
    local thorns = druid({ targetDebuffs = { Moonfire = true } }, "heal", nil, "Restoration", buffs)
    t.ok(thorns ~= "Thorns" and thorns ~= "Mark of the Wild", "not known: no Thorns either")
    local roots = druid({ targetMelee = true }, "heal", nil, "Restoration", { "Entangling Roots", "Wrath" })
    t.ok(roots ~= "Entangling Roots", "not known, and not known whether it is on you: no root")
end

T["paladin: combat not known, no blessing, and the seal by the in-fight rule"] = function(t)
    t.eq(ns.PaladinWantsBlessing({ buffs = {}, inCombat = false }), true, "out of a fight")
    t.eq(ns.PaladinWantsBlessing({ buffs = {}, inCombat = true }), false, "in a fight")
    t.eq(ns.PaladinWantsBlessing({ buffs = {} }), false, "not known")

    local function seal(left, combat)
        return ns.PaladinWantsSeal({ buffs = { ["Seal of Light"] = left }, hostile = true, inCombat = combat })
    end
    t.eq(seal(5, false), true, "5 s left before the pull")
    t.eq(seal(5, true), false, "5 s left in the fight")
    t.eq(seal(5, nil), false, "5 s left, not known: as in the fight")
    t.eq(seal(2, nil), true, "2 s left, not known")
    t.eq(ns.PaladinWantsSeal({ buffs = {} }), true, "none up: wanted, combat known or not")
end

T["cast: lockdown not known is refused, with its own reason"] = function(t)
    local C = ns.cast
    local open = C.Apply(keyPlan(), nil, false)
    t.eq(open.ok, true, "a plain false: applied")
    local locked = C.Apply(keyPlan(), nil, true)
    t.eq(locked.refused, "lockdown")

    local r = C.Apply(keyPlan(), nil, nil)
    t.eq(r.ok, false, "not known: refused")
    t.eq(r.refused, "lockdownUnknown")
    t.eq(r.ops, {}, "no ops")
    t.ok(type(r.reason) == "string" and r.reason ~= "", "a reason")
    t.ok(r.reason ~= locked.reason, "not the in-a-fight reason")
    t.eq(r.reason, C.REFUSED.lockdownUnknown)
    t.eq(C.Apply(keyPlan(), keyPlan(), nil).refused, "lockdownUnknown", "refused even when nothing would change")
    t.eq(C.Apply(keyPlan(), nil).refused, "lockdownUnknown", "left out")
    for _, odd in ipairs({ 0, 1, "", "false", "no", "yes" }) do
        local got = C.Apply(keyPlan(), nil, odd)
        t.eq(got.ok, false, "not a plain false: " .. tostring(odd))
        t.eq(got.refused, "lockdownUnknown", tostring(odd))
    end
    t.eq(C.Apply(keyPlan(), nil, {}).refused, "lockdownUnknown", "a table")
    t.eq(C.Apply(nil, nil, nil).refused, "plan", "a bad plan comes first")
end

T["cast: the reason does not name the product"] = function(t)
    for why, text in pairs(ns.cast.REFUSED) do
        local lower = string.lower(text)
        t.ok(not string.find(lower, "flow", 1, true), why)
    end
end

T["attributes: lockdown not known, nothing is given"] = function(t)
    local r = ns.cast.Attributes({ spell = "Moonfire" }, keyPlan(), nil, nil)
    t.eq(r.ok, false)
    t.eq(r.refused, "lockdownUnknown")
    t.eq(r.button, {}, "no button attributes")
    t.eq(r.header, {}, "no header attributes")
    t.eq(ns.cast.Attributes({ spell = "Moonfire" }, keyPlan(), nil, false).ok, true, "a plain false: given")
end

return T
