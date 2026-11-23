local _, ns = ...

-- ns.Choose: the step order, each step, the adaptive group, and that it is pure.

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
            aoe = { rule("Storm", { target = true }) },
        },
        heals = { self = { "Mend", "Big Mend", "Renew" }, hots = { "Renew" }, lingers = {} },
        interrupts = { rule("Kick", { near = true }), rule("Silence") },
        breakers = { rule("Slip", { types = { ROOT = true } }), rule("Beast", { any = true, form = true }) },
        dispels = { rule("Cleanse", { types = { Poison = true } }) },
    }
end

-- A range a row does not give is read as in range here: what a range
-- nobody read does is in RangeUnknown.lua.
local function snap(known, over)
    local s = { dead = false, inCombat = false, spells = {} }
    for _, name in ipairs(known or {}) do s.spells[name] = { known = true, onCooldown = false } end
    for k, v in pairs(over or {}) do s[k] = v end
    for _, row in pairs(s.spells) do
        if row.inRange == nil then row.inRange = true end
    end
    return s
end

-- A copy all the way down (functions are kept as they are).
local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = deepCopy(x) end
    return out
end

local ALL = { "Shield", "Bolt", "Storm", "Mend", "Big Mend", "Renew", "Kick", "Silence", "Slip", "Beast", "Cleanse", "Attack" }

local function pick(known, over, prefs, bias, p)
    local s, trace = ns.Choose(snap(known, over), p or pack(), prefs, bias)
    return s and s.spell or nil, s, trace
end

return {
    ["bad input gives nothing and one trace row"] = function(t)
        local s, trace = ns.Choose(nil, pack())
        t.eq(s, nil, "no snapshot")
        t.eq(#trace, 1, "one row")
        t.eq(trace[1].step, "input", "the input row")
        s = ns.Choose({}, nil)
        t.eq(s, nil, "no pack")
    end,

    ["alive with nothing else known gives nothing and a row per step, in order"] = function(t)
        local s, trace = ns.Choose({ dead = false }, pack())
        t.eq(s, nil, "nothing")
        t.eq(#trace, #ns.Rotation.STEPS, "one row per step")
        for i, name in ipairs(ns.Rotation.STEPS) do
            t.eq(trace[i].step, name, "row " .. i)
            t.eq(trace[i].result, "skip", name .. " skipped")
        end
        t.eq(table.concat(ns.Rotation.STEPS, " "), "breakFree heal interrupt dispel engage list farOpener", "the order")
    end,

    ["step order: each step answers before the ones after it"] = function(t)
        local everything = {
            loc = "ROOT", lowHealth = true, inCombat = true, hostile = true, targetCasting = "Fireball", targetNear = true,
        }
        local spell, s, trace = pick(ALL, everything)
        t.eq(spell, "Slip", "held: break free first")
        t.eq(s.step, "breakFree", "step")
        t.eq(#trace, 1, "the trace stops at the pick")
        t.eq(trace[1].result, "pick", "a pick row")
        everything.loc = nil
        spell, s = pick(ALL, everything)
        t.eq(spell, "Mend", "then the heal")
        t.eq(s.step, "heal", "step")
        everything.lowHealth = nil
        spell, s = pick(ALL, everything)
        t.eq(spell, "Kick", "then the interrupt")
        t.eq(s.step, "interrupt", "step")
        everything.targetCasting = nil
        spell, s, trace = pick(ALL, everything)
        t.eq(spell, "Shield", "then the list")
        t.eq(s.step, "list", "step")
        t.eq(#trace, 6, "five skipped rows and the pick")
        -- out of a fight: dispel before engage before the list
        local pull = { hostile = true, canStartAttack = true, stealthed = false, debuffTypes = { Poison = "Venom" } }
        _, s = pick(ALL, pull)
        t.eq(s.step, "dispel", "dispel before engage")
        pull.debuffTypes = nil
        spell, s = pick(ALL, pull)
        t.eq(spell, "Attack", "then engage")
        t.eq(s.step, "engage", "step")
        t.eq(s.engage, true, "marked as the engage press")
    end,

    ["break free: by type, by any, and never into the form you are in"] = function(t)
        t.eq(pick({ "Slip", "Beast" }, { loc = "ROOT" }), "Slip", "the ROOT breaker")
        t.eq(pick({ "Slip", "Beast" }, { loc = "STUN" }), "Beast", "the any breaker")
        t.eq(pick({ "Beast" }, { loc = "ROOT", form = "Beast" }), nil, "already in that form")
        local _, s = pick({ "Slip" }, { loc = "ROOT", inCombat = true })
        t.eq(s.kind, "emergency", "kind")
        t.ok(string.find(s.reason, "root", 1, true) ~= nil, "the reason names it")
        local _, _, trace = pick({}, { loc = "ROOT" })
        t.eq(trace[1].result, "skip", "nothing known: skipped")
    end,

    ["heal: low health takes the quickest direct heal"] = function(t)
        local over = { lowHealth = true, inCombat = true, spells = {
            Mend = { known = true, onCooldown = false, castMs = 2500 },
            ["Big Mend"] = { known = true, onCooldown = false, castMs = 1500 },
            Renew = { known = true, onCooldown = false, castMs = 0 },
        } }
        local spell, s = pick(nil, over)
        t.eq(spell, "Big Mend", "the quicker direct heal, not the heal over time")
        t.eq(s.kind, "emergency", "an emergency in a fight")
        over.inCombat = false
        _, s = pick(nil, over)
        t.eq(s.kind, "heal", "a heal out of a fight")
        t.eq(pick({ "Renew" }, { lowHealth = true }), "Renew", "only a heal over time known: that one")
        t.eq(pick({ "Mend" }, { lowHealth = true, dead = true }), nil, "not when dead")
        t.eq(pick({ "Mend" }, { lowHealth = true, casting = "Mend" }), nil, "not while already casting a heal")
        t.eq(pick({ "Mend" }, { lowHealth = true, hpPct = 0.9 }), "Mend", "a health amount handed in is not read")
    end,

    ["heal: the hurt estimate, out of a fight and in one"] = function(t)
        local H = ns.Rotation.HURT
        local heals = { "Mend", "Big Mend", "Renew" }
        local function hurt(n, over)
            local o = { hurt = n, buffs = {}, spells = {
                Mend = { known = true, onCooldown = false, castMs = 1500 },
                ["Big Mend"] = { known = true, onCooldown = false, castMs = 3000 },
                Renew = { known = true, onCooldown = false, castMs = 0 },
            } }
            for k, v in pairs(over or {}) do o[k] = v end
            if o.buffs == false then o.buffs = nil end   -- false here: not read
            return pick(nil, o)
        end
        t.eq(pack().heals.self, heals, "the pack offers these three heals, in this order")
        t.eq(hurt(H.outStart - 1), nil, "under the start: nothing")
        t.eq(hurt(H.outStart), "Renew", "a little hurt: the heal over time")
        t.eq(hurt(H.outStart, { buffs = { Renew = 9 } }), nil, "it is already on you")
        t.eq(hurt(H.outBig), "Big Mend", "hurt: the big heal")
        t.eq(hurt(H.inHot - 1, { inCombat = true }), nil, "in a fight, under the threshold")
        t.eq(hurt(H.inHot, { inCombat = true }), "Renew", "in a fight: the heal over time")
        t.eq(hurt(H.inHeal, { inCombat = true }), "Mend", "hit a lot: the quickest direct heal")
        local _, s = hurt(H.outStart)
        t.eq(s.early, true, "marked early")
        t.eq(s.kind, "heal", "kind")
        t.ok(string.find(s.reason, "estimate", 1, true) ~= nil, "the reason says it is an estimate")
        -- Section 183: buffs not read, so the heal over time may be on already.
        t.eq(hurt(H.outStart, { buffs = false }), "Mend", "buffs not read: a direct heal, not the heal over time")
        t.eq(hurt(H.inHot, { inCombat = true, buffs = false }), nil, "buffs not read, in a fight: no heal over time")
        t.eq(hurt(H.inHeal, { inCombat = true, buffs = false }), "Mend", "buffs not read, hit a lot: still healed")
        t.eq(hurt(H.outBig, { buffs = false }), "Big Mend", "buffs not read, hurt: the big heal")
    end,

    -- The snapshot carries only targetCasting: whose target it is cannot be told here.
    ["interrupt: only while the target is casting, in a fight"] = function(t)
        local on = { inCombat = true, hostile = true, targetCasting = "Fireball", targetNear = true }
        t.eq(pick({ "Kick", "Silence" }, on), "Kick", "near: the near interrupt")
        on.targetNear = false
        t.eq(pick({ "Kick", "Silence" }, on), "Silence", "far: the ranged one")
        t.eq(pick({ "Kick" }, on), nil, "far with only the near one")
        on.spells = { Silence = { known = true, onCooldown = false, inRange = false } }
        t.eq(pick(nil, on), nil, "the ranged one out of range")
        t.eq(pick({ "Kick" }, { inCombat = true, hostile = true, targetNear = true }), nil, "not casting")
        t.eq(pick({ "Kick" }, { hostile = true, targetCasting = "Fireball", targetNear = true }), nil, "not in a fight")
        local _, s = pick({ "Kick" }, { inCombat = true, hostile = true, targetCasting = "Fireball", targetNear = true })
        t.eq(s.kind, "damage", "kind")
        t.ok(string.find(s.reason, "Fireball", 1, true) ~= nil, "the reason names the cast")
    end,

    ["dispel: yourself, out of a fight, by type, honouring when"] = function(t)
        local spell, s = pick({ "Cleanse" }, { debuffTypes = { Poison = "Venom" } })
        t.eq(spell, "Cleanse", "poisoned")
        t.eq(s.unit, "player", "on yourself")
        t.eq(s.kind, "buff", "kind")
        t.eq(pick({ "Cleanse" }, { debuffTypes = { Curse = "Hex" } }), nil, "a type it does not remove")
        t.eq(pick({ "Cleanse" }, { debuffTypes = { Poison = "Venom" }, inCombat = true }), nil, "not in a fight")
        local p = pack()
        p.dispels[1].when = function(s2) return s2.form == nil end
        t.eq(pick({ "Cleanse" }, { debuffTypes = { Poison = "Venom" }, form = "Beast" }, nil, nil, p), nil, "when says no")
        t.eq(pick({ "Cleanse" }, { debuffTypes = { Poison = "Venom" } }, nil, nil, p), "Cleanse", "when says yes")
    end,

    ["engage: start the attack on a pull, unless told not to"] = function(t)
        local pull = { hostile = true, canStartAttack = true, stealthed = false }
        t.eq(pick({ "Attack", "Bolt" }, pull), "Attack", "Attack")
        t.eq(pick({ "Attack", "Auto Attack", "Bolt" }, pull), "Auto Attack", "Auto Attack when known")
        t.eq(pick({ "Attack", "Bolt" }, pull, { autoAttack = false }), "Bolt", "switched off")
        t.eq(pick({ "Attack", "Bolt" }, { hostile = true, stealthed = false, canStartAttack = true, attacking = true }), "Bolt", "already swinging")
        t.eq(pick({ "Attack", "Bolt" }, { hostile = true, stealthed = false }), "Bolt", "the key cannot start it")
        t.eq(pick({ "Attack", "Bolt" }, { hostile = true, stealthed = false, canStartAttack = true, engageGaveUp = true }), "Bolt", "gave up")
        t.eq(pick({ "Attack", "Bolt" }, { hostile = true, stealthed = false, canStartAttack = true, inCombat = true }), "Bolt", "already fighting")
        t.eq(pick({ "Bolt" }, pull), "Bolt", "no attack known")
    end,

    ["list: first ready rule, when, skip, cooldown, usable, fight type"] = function(t)
        local fight = { inCombat = true, hostile = true }
        t.eq(pick({ "Shield", "Bolt" }, fight), "Shield", "the first rule")
        t.eq(pick({ "Shield", "Bolt" }, { inCombat = true, hostile = true, buffs = { Shield = 20 } }), "Bolt", "when says no")
        t.eq(pick({ "Shield", "Bolt" }, fight, { skip = { Shield = true } }), "Bolt", "a skipped spell")
        fight.spells = { Shield = { known = true, onCooldown = true }, Bolt = { known = true, onCooldown = false } }
        t.eq(pick(nil, fight), "Bolt", "on cooldown")
        fight.spells = { Shield = { known = true, onCooldown = false, usable = false }, Bolt = { known = true, onCooldown = false } }
        t.eq(pick(nil, fight), "Bolt", "not usable")
        local spell, s = pick({ "Shield", "Bolt", "Storm" }, { inCombat = true, hostile = true, fightType = "aoe" })
        t.eq(spell, "Storm", "the aoe list")
        t.eq(s.fightType, "aoe", "the fight type on the suggestion")
        t.eq(pick({ "Bolt" }, { inCombat = true, hostile = true, fightType = "cleave" }), "Bolt", "an unknown fight type: the default list")
        t.eq(pick({ "Shield" }, { resting = true }), nil, "no buffs while resting out of a fight")
        t.eq(pick({ "Shield" }, { resting = true, inCombat = true }), "Shield", "but in a fight, yes")
        local _, s2 = pick({ "Bolt" }, { inCombat = true, hostile = true })
        t.eq(s2.kind, "damage", "the default kind")
        t.eq(s2.reason, "Bolt", "the default reason is the spell")
    end,

    ["list: neighbouring adaptive rules follow what was pressed, past the edge"] = function(t)
        local p = pack()
        p.lists.default = {
            rule("One", { adaptive = true }), rule("Two", { adaptive = true }), rule("Three"),
        }
        local known = { "One", "Two", "Three" }
        local fight = { inCombat = true }
        local edge = ns.Rotation.BIAS_EDGE
        t.eq(pick(known, fight, nil, nil, p), "One", "no bias: the first")
        t.eq(pick(known, fight, nil, { Two = edge }, p), "One", "at the edge: still the first")
        local spell, s = pick(known, fight, nil, { Two = edge * 3 }, p)
        t.eq(spell, "Two", "pressed clearly more: the second")
        t.ok(string.find(s.reason, "(learned)", 1, true) ~= nil, "marked learned")
        t.eq(pick(known, fight, nil, { Three = 1 }, p), "One", "a rule outside the group is not moved up")
        t.eq(pick({ "Two", "Three" }, fight, nil, nil, p), "Two", "the first not known: the second")
        t.eq(pick({ "Three" }, fight, nil, { One = 1 }, p), "Three", "none of the group ready: on to the next rule")
    end,

    ["far opener: the first wanted rule that is only out of range"] = function(t)
        local over = { hostile = true, attacking = true, spells = { Bolt = { known = true, onCooldown = false, inRange = false } } }
        local spell, s = pick(nil, over)
        t.eq(spell, "Bolt", "the opener")
        t.eq(s.step, "farOpener", "the last step")
        t.eq(s.label, "Out of range", "label")
        t.ok(string.find(s.reason, "(out of range)", 1, true) ~= nil, "the reason says so")
        over.hostile = false
        t.eq(pick(nil, over), nil, "no enemy targeted")
        over.hostile = true
        over.spells.Bolt.onCooldown = true
        t.eq(pick(nil, over), nil, "not castable anyway")
    end,

    ["castable: a cooldown nobody read is not castable, with its own reason"] = function(t)
        local R = ns.Rotation
        local function with(row) return { dead = false, inCombat = true, hostile = true, spells = { Bolt = row } } end
        local ok, why = R.Castable(with({ known = true, onCooldown = false }), "Bolt")
        t.eq(ok, true, "read, ready: castable")
        t.eq(why, nil, "no reason with a yes")
        ok, why = R.Castable(with({ known = true }), "Bolt")
        t.eq(ok, false, "not read: not castable")
        t.eq(why, "not known whether it is ready", "its own reason")
        ok, why = R.Castable(with({ known = true, usable = true, inRange = true }), "Bolt")
        t.eq(ok, false, "all else read and fine: still not castable")
        t.eq(why, "not known whether it is ready")
        ok, why = R.Castable(with({ known = true, onCooldown = true }), "Bolt")
        t.eq(ok, false, "read, on cooldown")
        t.eq(why, nil, "a plain no: not the not-known reason")
        ok, why = R.Castable(with({ onCooldown = false }), "Bolt")
        t.eq(ok, false, "known not read")
        t.eq(why, nil, "the cooldown is not what stops it")
        ok, why = R.Castable(with({ known = true, usable = false }), "Bolt")
        t.eq(ok, false, "refused by the game")
        t.eq(why, nil, "the cooldown is not what stops it")
        ok, why = R.Castable(with({ known = true }), "Other")
        t.eq(ok, false, "no row")
        t.eq(why, nil, "no row, no reason")
        local ready = R.Ready(with({ known = true }), "Bolt")
        t.eq(ready, false, "Ready follows Castable")
    end,

    ["a cooldown nobody read: the list, a heal and the far opener pass the spell by"] = function(t)
        local fight = { inCombat = true, hostile = true }
        fight.spells = { Shield = { known = true }, Bolt = { known = true, onCooldown = false } }
        t.eq(pick(nil, fight), "Bolt", "the list goes on to the rule whose cooldown was read")
        fight.spells = { Shield = { known = true }, Bolt = { known = true } }
        t.eq(pick(nil, fight), nil, "neither read: nothing")
        local hurt = { lowHealth = true, inCombat = true, spells = {
            Mend = { known = true, castMs = 1500 },
            ["Big Mend"] = { known = true, onCooldown = false, castMs = 2500 },
        } }
        t.eq(pick(nil, hurt), "Big Mend", "the heal whose cooldown was read, though slower")
        hurt.spells["Big Mend"].onCooldown = nil
        t.eq(pick(nil, hurt), nil, "no heal whose cooldown is not known")
        local far = { hostile = true, attacking = true, spells = { Bolt = { known = true, inRange = false } } }
        t.eq(pick(nil, far), nil, "out of range and cooldown not read: not offered as the opener")
    end,

    ["CD1: each trace row lists the spells its step passed by for a cooldown not read"] = function(t)
        local fight = { inCombat = true, hostile = true }
        fight.spells = { Shield = { known = true }, Bolt = { known = true, onCooldown = false } }
        local spell, _, trace = pick(nil, fight)
        t.eq(spell, "Bolt")
        t.eq(trace[#trace].step, "list")
        t.eq(trace[#trace].passed, { "Shield" }, "the pick's row names what the list passed by first")
        for i = 1, #trace - 1 do t.eq(trace[i].passed, nil, trace[i].step .. ": passed nothing by") end

        fight.spells = { Shield = { known = true, onCooldown = false }, Bolt = { known = true } }
        spell, _, trace = pick(nil, fight)
        t.eq(spell, "Shield")
        t.eq(trace[#trace].passed, nil, "Bolt was never weighed: not named")

        fight.spells = { Shield = { known = true }, Bolt = { known = true } }
        spell, _, trace = pick(nil, fight)
        t.eq(spell, nil)
        t.eq(trace[6].step, "list")
        t.eq(trace[6].passed, { "Bolt", "Shield" }, "no pick: the row still names them, sorted")
        t.eq(trace[6].note, "no rule ready; not known whether it is ready: Bolt, Shield", "and the note is as it was")
        t.eq(trace[7].passed, nil, "the far opener weighed none")

        local hurt = { lowHealth = true, inCombat = true, spells = {
            Mend = { known = true, castMs = 1500 },
            ["Big Mend"] = { known = true, onCooldown = false, castMs = 2500 },
        } }
        spell, _, trace = pick(nil, hurt)
        t.eq(spell, "Big Mend")
        t.eq(trace[2].step, "heal")
        t.eq(trace[2].passed, { "Mend" }, "the heal step's own row")
        t.eq(trace[1].passed, nil)
    end,

    ["F-086: a spell that needs a target is not suggested while the target is not known"] = function(t)
        local function noteOf(trace, step)
            for _, r in ipairs(trace) do
                if r.step == step then return r.note end
            end
        end
        local fight = { inCombat = true }
        local spell, _, trace = pick({ "Bolt" }, fight)
        t.eq(spell, nil, "hostile not known: Bolt is not suggested")
        t.eq(noteOf(trace, "list"), "no rule ready; not known whether you have a target: Bolt")
        t.eq(noteOf(trace, "farOpener"), "not known whether you have a target", "not the no-enemy note")
        t.eq(ns.Rotation.TARGET_UNKNOWN, "not known whether you have a target")
        t.eq(trace[6].passed, nil, "no cooldown was in the way")

        t.eq(pick({ "Shield", "Bolt" }, fight), "Shield", "a spell that needs no target is still suggested")
        spell, _, trace = pick({ "Shield", "Bolt" }, { inCombat = true, buffs = { Shield = 20 } })
        t.eq(spell, nil, "and when it is not wanted, nothing")
        t.eq(noteOf(trace, "list"), "no rule ready; not known whether you have a target: Bolt")
        t.eq(pick({ "Bolt" }, { inCombat = true, hostile = true }), "Bolt", "an enemy targeted: suggested")

        -- Named only when the target alone is in the way.
        _, _, trace = pick(nil, { inCombat = true, spells = { Bolt = { known = true, onCooldown = true } } })
        t.eq(noteOf(trace, "list"), "no rule ready", "on cooldown: a plain no")
        _, _, trace = pick(nil, { inCombat = true, spells = { Bolt = { known = true } } })
        t.eq(noteOf(trace, "list"), "no rule ready; not known whether it is ready: Bolt", "the cooldown comes first")
        _, _, trace = pick({ "Bolt" }, { inCombat = true }, { skip = { Bolt = true } })
        t.eq(noteOf(trace, "list"), "no rule ready", "a skipped spell is not named")

        local p = pack()
        p.lists.default = { rule("Storm", { target = true }), rule("Bolt", { target = true }),
            rule("Kick", { target = true }) }
        local s = { inCombat = true, spells = {
            Storm = { known = true, onCooldown = false }, Bolt = { known = true, onCooldown = false },
            Kick = { known = true },
        } }
        spell, _, trace = pick(nil, s, nil, nil, p)
        t.eq(spell, nil)
        t.eq(noteOf(trace, "list"),
            "no rule ready; not known whether it is ready: Kick; not known whether you have a target: Bolt, Storm",
            "both reasons, each with its own spells, sorted")

        p.lists.default = { rule("One", { adaptive = true, target = true }), rule("Two", { adaptive = true }) }
        t.eq(pick({ "One", "Two" }, fight, nil, nil, p), "Two", "in an adaptive group too")
        spell, _, trace = pick({ "One" }, fight, nil, nil, p)
        t.eq(spell, nil)
        t.eq(noteOf(trace, "list"), "no rule ready; not known whether you have a target: One")
    end,

    ["pure: the same input gives the same answer and nothing is changed"] = function(t)
        local p = pack()
        local s = snap({ "Shield", "Bolt" }, { inCombat = true, hostile = true, buffs = {} })
        local prefs, bias = { skip = {} }, { Bolt = 0.5 }
        local sWas, pWas, prefsWas, biasWas = deepCopy(s), deepCopy(p), deepCopy(prefs), deepCopy(bias)
        local a, traceA = ns.Choose(s, p, prefs, bias)
        local b, traceB = ns.Choose(s, p, prefs, bias)
        t.eq(a, b, "the whole suggestion is the same")
        t.eq(traceA, traceB, "and the whole trace")
        t.ok(traceA ~= traceB, "each call has a trace of its own")
        t.eq(s, sWas, "the whole snapshot is as it was")
        t.eq(p, pWas, "the whole pack is as it was")
        t.eq(prefs, prefsWas, "the prefs are as they were, nothing added")
        t.eq(bias, biasWas, "the bias is as it was")
        t.eq(a.spell, b.spell, "same spell")
        t.eq(a.reason, b.reason, "same reason")
        t.ok(a ~= b, "a fresh table each call")
        a.spell = "changed"
        t.eq(ns.Choose(s, p, prefs, bias).spell, "Shield", "changing a suggestion changes nothing kept")
        t.eq(next(s.buffs), nil, "the snapshot is as it was")
        t.eq(next(prefs.skip), nil, "the prefs are as they were")
        t.eq(#p.lists.default, 2, "the pack is as it was")
    end,
}
