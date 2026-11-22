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
}
