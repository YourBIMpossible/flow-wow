local _, ns = ...

local function plan()
    return {
        states = { [0] = { key = "A", ctrl = "B" }, [3] = { key = "G", more = "J" }, [9] = { key = "M" } },
        condition = "[form:3,stealth] 9; [form:3] 3; 0",
        stealthForm = 3,
    }
end

local function brief(ops)
    local out = {}
    for i, o in ipairs(ops) do
        out[i] = string.format("%s %d.%s %s", o.op, o.state, o.slot, tostring(o.spell or o.was))
    end
    return out
end

local function attrs(list)
    local out = {}
    for i, a in ipairs(list) do
        out[i] = a.attr .. "=" .. tostring(a.value)
    end
    return out
end

return {
    ["nothing bound yet: every filled slot is a set, in state then slot order"] = function(t)
        local r = ns.cast.Apply(plan(), nil, false)
        t.eq(r.ok, true, "ok")
        t.eq(brief(r.ops), { "set 0.key A", "set 0.ctrl B", "set 3.key G", "set 3.more J", "set 9.key M" }, "ops")
        t.eq(r.counts, { set = 5, clear = 0, unchanged = 0 }, "counts")
        t.eq(r.changed, true, "changed")
        t.eq(r.condition, "[form:3,stealth] 9; [form:3] 3; 0", "condition")
        t.eq(r.conditionChanged, true, "condition is new")
        t.eq(r.stealthForm, 3, "stealthForm")
    end,

    ["the same plan again: everything unchanged"] = function(t)
        local first = ns.cast.Apply(plan(), nil, false)
        local r = ns.cast.Apply(plan(), first.plan, false)
        t.eq(r.counts, { set = 0, clear = 0, unchanged = 5 }, "counts")
        t.eq(r.changed, false, "changed")
        t.eq(r.conditionChanged, false, "condition")
        t.eq(r.ops[1], { op = "unchanged", state = 0, slot = "key", spell = "A" }, "first op")
    end,

    ["a changed slot is a set with what it was; a dropped one is a clear"] = function(t)
        local new = plan()
        new.states[0].ctrl = "C"
        new.states[3].more = nil
        new.states[9] = nil
        new.condition = "[form:3] 3; 0"
        new.stealthForm = nil
        local r = ns.cast.Apply(new, plan(), false)
        t.eq(brief(r.ops), {
            "unchanged 0.key A", "set 0.ctrl C", "unchanged 3.key G", "clear 3.more J", "clear 9.key M",
        }, "ops")
        t.eq(r.ops[2], { op = "set", state = 0, slot = "ctrl", spell = "C", was = "B" }, "the set names what was there")
        t.eq(r.ops[4], { op = "clear", state = 3, slot = "more", was = "J" }, "the clear names what was there")
        t.eq(r.counts, { set = 1, clear = 2, unchanged = 2 }, "counts")
        t.eq(r.conditionChanged, true, "condition")
        t.eq(r.stealthForm, nil, "stealthForm")
    end,

    ["only the condition differs: changed, with no set or clear"] = function(t)
        local new = plan()
        new.condition = "[form:3] 3; 0"
        local r = ns.cast.Apply(new, plan(), false)
        t.eq(r.counts.set + r.counts.clear, 0, "no binding changes")
        t.eq(r.changed, true, "changed")
    end,

    ["in combat lockdown: refused, with no ops"] = function(t)
        local r = ns.cast.Apply(plan(), nil, true)
        t.eq(r.ok, false, "not ok")
        t.eq(r.refused, "lockdown", "why")
        t.eq(r.ops, {}, "nothing to do")
        t.eq(r.plan, nil, "no plan to remember: keep the one in place")
        t.ok(type(r.reason) == "string" and #r.reason > 0, "a reason to show")
        r = ns.cast.Apply(plan(), plan(), true)
        t.eq(r.refused, "lockdown", "refused even when nothing would change")
    end,

    ["not a plan: refused"] = function(t)
        t.eq(ns.cast.Apply(nil, nil, false).refused, "plan", "nil")
        t.eq(ns.cast.Apply({}, nil, false).refused, "plan", "no states")
        t.eq(ns.cast.Apply("x", nil, true).refused, "plan", "a bad plan comes before the lockdown")
    end,

    ["an empty plan clears what was bound"] = function(t)
        local r = ns.cast.Apply({ states = {}, condition = "0" }, plan(), false)
        t.eq(r.counts, { set = 0, clear = 5, unchanged = 0 }, "counts")
        t.eq(r.condition, "0", "condition")
        t.eq(r.plan, { states = {}, condition = "0" }, "the plan to remember")
    end,

    ["states out of range, unknown slots and values that are not names are left out"] = function(t)
        local r = ns.cast.Apply({
            states = { [0] = { key = "A", extra = "Z", ctrl = 7 }, [10] = { key = "X" }, [-1] = { key = "Y" }, [2] = "row" },
        }, nil, false)
        t.eq(brief(r.ops), { "set 0.key A" }, "ops")
        t.eq(r.condition, "0", "no condition given reads as 0")
        t.eq(r.plan.states, { [0] = { key = "A" } }, "plan")
    end,

    ["a bad applied plan reads as nothing bound"] = function(t)
        local r = ns.cast.Apply(plan(), "old", false)
        t.eq(r.counts.set, 5, "all set")
    end,

    ["pure: the same input gives the same result and nothing is changed"] = function(t)
        local p, a = plan(), plan()
        a.states[0].key = "Q"
        local r = ns.cast.Apply(p, a, false)
        t.eq(r, ns.cast.Apply(p, a, false), "same answer")
        t.eq(p, plan(), "plan not changed")
        t.eq(a.states[0].key, "Q", "applied not changed")
        t.ok(r.plan ~= p and r.plan.states ~= p.states and r.plan.states[0] ~= p.states[0], "the remembered plan is a copy")
    end,

    ["no reason spells the addon's name"] = function(t)
        for why, text in pairs(ns.cast.REFUSED) do
            t.ok(not string.find(string.lower(text), "flow", 1, true), why)
        end
    end,

    ["a key plan from the druid pack goes straight in"] = function(t)
        local kp = ns.KeyPlan(ns.Packs.DRUID, { forms = {
            { name = "Bear Form", index = 1 }, { name = "Cat Form", index = 3 },
        } })
        local r = ns.cast.Apply(kp, nil, false)
        t.eq(r.ok, true, "ok")
        t.eq(r.ops[1], { op = "set", state = 0, slot = "key", spell = "Wrath" }, "caster key first")
        t.eq(r.ops[#r.ops].state, ns.Rotation.STEALTH_STATE, "the stealth state last")
        t.eq(r.condition, kp.condition, "condition carried")
        local again = ns.cast.Apply(kp, r.plan, false)
        t.eq(again.changed, false, "applied, then nothing to do")
    end,

    -- ns.cast.Attributes: a suggestion plus a key plan, as secure attributes.

    ["attributes: a suggestion on the key, the no-form row on the modifiers"] = function(t)
        local r = ns.cast.Attributes({ spell = "Moonfire", kind = "damage" }, plan(), nil, false)
        t.eq(r.ok, true, "ok")
        t.eq(r.source, "suggestion", "source")
        t.eq(r.spell, "Moonfire", "spell")
        t.eq(r.form, 0, "form")
        t.eq(attrs(r.button), {
            "type=spell", "spell=Moonfire", "unit=nil", "macrotext=nil",
            "*type-ctrl=spell", "*spell-ctrl=B", "*unit-ctrl=target",
            "*type-shift=nil", "*spell-shift=nil", "*unit-shift=nil",
            "*type-alt=nil", "*spell-alt=nil", "*unit-alt=nil",
            "*type-more=nil", "*spell-more=nil", "*unit-more=nil",
        }, "button")
    end,

    ["attributes: a heal, an emergency or your own buff goes on you"] = function(t)
        for _, kind in ipairs({ "heal", "emergency", "buff" }) do
            local r = ns.cast.Attributes({ spell = "Rejuvenation", kind = kind }, plan(), nil, false)
            t.eq(attrs(r.button)[3], "unit=player", kind)
        end
        local r = ns.cast.Attributes({ spell = "Rejuvenation", kind = "heal", unit = "pet" }, plan(), nil, false)
        t.eq(attrs(r.button)[3], "unit=pet", "a unit the suggestion names is kept")
        for _, unit in ipairs({ "party1", "raid3", "focus", "mouseover", 4 }) do
            r = ns.cast.Attributes({ spell = "Rejuvenation", kind = "heal", unit = unit }, plan(), nil, false)
            t.eq(attrs(r.button)[3], "unit=player", "never another player: " .. tostring(unit))
        end
    end,

    ["attributes: Attack is the start-attack macro"] = function(t)
        for _, name in ipairs({ "Attack", "Auto Attack" }) do
            local r = ns.cast.Attributes({ spell = name, kind = "damage" }, plan(), nil, false)
            t.eq({ attrs(r.button)[1], attrs(r.button)[2], attrs(r.button)[3], attrs(r.button)[4] },
                { "type=macro", "spell=nil", "unit=nil", "macrotext=/startattack" }, name)
        end
    end,

    ["attributes: no suggestion, the key holds the form's own spell"] = function(t)
        local r = ns.cast.Attributes(nil, plan(), nil, false, 3)
        t.eq(r.source, "plan", "source")
        t.eq(r.spell, "G", "spell")
        t.eq(r.form, 3, "form")
        local a = attrs(r.button)
        t.eq({ a[1], a[2], a[3] }, { "type=spell", "spell=G", "unit=target" }, "key")
        t.eq({ a[14], a[15], a[16] }, { "*type-more=spell", "*spell-more=J", "*unit-more=target" }, "more")
        t.eq(a[5], "*type-ctrl=nil", "form 3 has no ctrl")
    end,

    ["attributes: nothing to cast clears the key"] = function(t)
        local r = ns.cast.Attributes(nil, { states = {}, condition = "0" }, nil, false)
        t.eq(r.ok, true, "ok")
        t.eq(r.source, nil, "source")
        t.eq(r.spell, nil, "spell")
        for i, a in ipairs(attrs(r.button)) do
            t.ok(string.sub(a, -4) == "=nil", "cleared " .. i)
        end
        t.eq(#r.button, 16, "every attribute named")
    end,

    ["attributes: a form with no row, or not a form number, reads as described"] = function(t)
        local r = ns.cast.Attributes(nil, plan(), nil, false, 5)
        t.eq(r.form, 5, "an empty form stays that form")
        t.eq(r.spell, nil, "and casts nothing")
        t.eq(ns.cast.Attributes(nil, plan(), nil, false, 42).form, 0, "out of range: no form")
        t.eq(ns.cast.Attributes(nil, plan(), nil, false, "cat").form, 0, "not a number: no form")
        t.eq(ns.cast.Attributes(nil, plan(), nil, false, 9).spell, "M", "the stealth state")
    end,

    ["attributes: the header carries every state, empty ones as empty text"] = function(t)
        local r = ns.cast.Attributes(nil, plan(), nil, false)
        t.eq(#r.header, (ns.Rotation.STEALTH_STATE + 1) * 5, "five per state")
        t.eq(r.header[1], { attr = "key-0", value = "A" }, "key-0")
        t.eq(r.header[2], { attr = "ctrl-0", value = "B" }, "ctrl-0")
        t.eq(r.header[3], { attr = "shift-0", value = "" }, "shift-0")
        t.eq(r.header[6], { attr = "key-1", value = "" }, "key-1")
        t.eq(r.header[16], { attr = "key-3", value = "G" }, "key-3")
        t.eq(r.header[20], { attr = "more-3", value = "J" }, "more-3")
        t.eq(r.header[46], { attr = "key-9", value = "M" }, "key-9")
    end,

    ["attributes: the state driver carries the condition and says when it is new"] = function(t)
        local r = ns.cast.Attributes(nil, plan(), nil, false)
        t.eq(r.driver, { state = ns.cast.STATE, condition = "[form:3,stealth] 9; [form:3] 3; 0", changed = true }, "first time")
        local again = ns.cast.Attributes(nil, plan(), r.plan, false)
        t.eq(again.driver.changed, false, "same condition")
        t.eq(again.apply.changed, false, "nothing to rebind")
        t.ok(type(ns.cast.STATE) == "string" and not string.find(string.lower(ns.cast.STATE), "flow", 1, true), "state name")
    end,

    ["attributes: the cast plan rides along"] = function(t)
        local r = ns.cast.Attributes({ spell = "X" }, plan(), nil, false)
        t.eq(r.apply, ns.cast.Apply(plan(), nil, false), "apply")
        t.eq(r.plan, r.apply.plan, "the plan to remember")
    end,

    ["attributes: in combat lockdown nothing is given"] = function(t)
        local r = ns.cast.Attributes({ spell = "Moonfire" }, plan(), nil, true)
        t.eq(r.ok, false, "not ok")
        t.eq(r.refused, "lockdown", "why")
        t.eq(r.button, {}, "no button attributes")
        t.eq(r.header, {}, "no header attributes")
        t.eq(r.driver, nil, "no driver")
        t.eq(r.plan, nil, "no plan")
        t.ok(type(r.reason) == "string" and #r.reason > 0, "a reason to show")
    end,

    ["attributes: not a key plan is refused, before the lockdown"] = function(t)
        t.eq(ns.cast.Attributes({ spell = "X" }, nil, nil, false).refused, "plan", "nil")
        t.eq(ns.cast.Attributes({ spell = "X" }, "x", nil, true).refused, "plan", "text")
    end,

    ["attributes: a suggestion that is not one is ignored"] = function(t)
        t.eq(ns.cast.Attributes("Moonfire", plan(), nil, false).source, "plan", "text")
        t.eq(ns.cast.Attributes({ spell = 7 }, plan(), nil, false).source, "plan", "a number for a spell")
        t.eq(ns.cast.Attributes({ spell = "" }, plan(), nil, false).source, "plan", "an empty name")
    end,

    ["attributes: pure, and the inputs are left alone"] = function(t)
        local s, p = { spell = "Moonfire", kind = "damage" }, plan()
        local r = ns.cast.Attributes(s, p, nil, false, 3)
        t.eq(r, ns.cast.Attributes(s, p, nil, false, 3), "same answer")
        t.eq(p, plan(), "plan not changed")
        t.eq(s, { spell = "Moonfire", kind = "damage" }, "suggestion not changed")
    end,

    ["attributes: the chooser and the druid key plan go straight in"] = function(t)
        local kp = ns.KeyPlan(ns.Packs.DRUID, { forms = {
            { name = "Bear Form", index = 1 }, { name = "Cat Form", index = 3 },
        } })
        local s = ns.Choose({ role = "dps", hostile = true, inCombat = false, dead = false,
                             spells = { Wrath = { known = true, onCooldown = false } } },
            ns.Packs.DRUID)
        t.ok(s and type(s.spell) == "string", "a suggestion")
        local r = ns.cast.Attributes(s, kp, nil, false)
        t.eq(r.ok, true, "ok")
        t.eq(r.spell, s.spell, "the suggestion is on the key")
        t.eq(r.header[1], { attr = "key-0", value = "Wrath" }, "the caster key in the header")
        t.eq(r.driver.condition, kp.condition, "condition carried")
    end,
}
