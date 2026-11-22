local _, ns = ...

local function pack()
    return { keys = {
        none = { key = "A", ctrl = { "B", "C" }, shift = { "C", "D" }, alt = "E", more = { "B", "F" } },
        Cat = { key = { "G", "H" }, ctrl = { "G", "I" }, more = "J" },
        Bear = { key = "K", ctrl = "L" },
        stealth = { form = "Cat", key = { "M", "G" }, ctrl = "I" },
    } }
end

return {
    ["no forms: one row for no form and the condition is 0"] = function(t)
        local plan = ns.KeyPlan(pack(), nil)
        t.eq(plan.condition, "0", "condition")
        t.eq(plan.states, { [0] = { key = "A", ctrl = "B", more = "F" } }, "states")
        t.eq(plan.stealthForm, nil, "stealthForm")
    end,

    ["a slot takes the first spell you know that the row has not used"] = function(t)
        local plan = ns.KeyPlan(pack(), { known = { A = true, C = true, B = true } })
        t.eq(plan.states[0], { key = "A", ctrl = "B", more = nil }, "B on ctrl, so more has nothing left")
        plan = ns.KeyPlan(pack(), { known = { A = true, C = true, F = true } })
        t.eq(plan.states[0], { key = "A", ctrl = "C", more = "F" }, "C when B is not known")
    end,

    ["knowing nothing a row names gives no row"] = function(t)
        local plan = ns.KeyPlan(pack(), { known = {}, forms = { { name = "Cat", index = 3 } } })
        t.eq(plan.states, {}, "states")
        t.eq(plan.condition, "[form:3] 3; 0", "the form still has its state")
        t.eq(plan.stealthForm, nil, "no stealth row, so no stealth state")
    end,

    ["forms: a state per form, in the order given"] = function(t)
        local plan = ns.KeyPlan(pack(), { forms = { { name = "Bear", index = 1 }, { name = "Cat", index = 3 } } })
        t.eq(plan.condition, "[form:1] 1; [form:3,stealth] 9; [form:3] 3; 0", "condition")
        t.eq(plan.states[1], { key = "K", ctrl = "L" }, "bear")
        t.eq(plan.states[3], { key = "G", ctrl = "I", more = "J" }, "cat: G is on the key, so ctrl takes I")
        t.eq(plan.states[ns.Rotation.STEALTH_STATE], { key = "M", ctrl = "I" }, "stealth")
        t.eq(plan.stealthForm, 3, "stealthForm")
    end,

    ["the stealth state comes before its form in the condition"] = function(t)
        local plan = ns.KeyPlan(pack(), { forms = { { name = "Cat", index = 2 } } })
        t.eq(plan.condition, "[form:2,stealth] 9; [form:2] 2; 0", "condition")
        t.eq(ns.Rotation.STEALTH_STATE, ns.Rotation.FORM_STATES + 1, "one past the form states")
        t.eq(ns.Rotation.STEALTH_STATE, 9, "the stealth state is 9, the number in the condition")
        for state = 0, ns.Rotation.FORM_STATES do
            t.ok(state ~= ns.Rotation.STEALTH_STATE, "form state " .. state .. " is not the stealth state")
        end
        local first = string.find(plan.condition, "[form:2,stealth]", 1, true)
        local second = string.find(plan.condition, "[form:2]", 1, true)
        t.ok(first ~= nil and second ~= nil and first < second, "the stealth clause is written before the plain form clause")
    end,

    ["a form the pack has no row for keeps its state and gets no row"] = function(t)
        local plan = ns.KeyPlan(pack(), { forms = { { name = "Travel", index = 4 } } })
        t.eq(plan.condition, "[form:4] 4; 0", "condition")
        t.eq(plan.states[4], nil, "no row")
    end,

    ["a form number out of range, or a bad form entry, is left out"] = function(t)
        local plan = ns.KeyPlan(pack(), { forms = {
            { name = "Cat", index = 9 }, { name = "Bear", index = 0 }, { name = "Bear" }, "Bear",
        } })
        t.eq(plan.condition, "0", "condition")
        t.eq(plan.states, { [0] = { key = "A", ctrl = "B", more = "F" } }, "states")
    end,

    ["slots: only the modifiers asked for are filled"] = function(t)
        local plan = ns.KeyPlan(pack(), { slots = { "alt" } })
        t.eq(plan.states[0], { key = "A", alt = "E" }, "alt only")
        plan = ns.KeyPlan(pack(), { slots = {} })
        t.eq(plan.states[0], { key = "A" }, "the key alone")
    end,

    ["with shift filled, ctrl and shift change places"] = function(t)
        local plan = ns.KeyPlan(pack(), { slots = { "ctrl", "shift" } })
        t.eq(plan.states[0], { key = "A", ctrl = "C", shift = "B" }, "B was picked for ctrl and sits on shift")
    end,

    ["skip: a spell never to bind is passed over"] = function(t)
        local plan = ns.KeyPlan(pack(), { skip = { B = true, A = true } })
        t.eq(plan.states[0], { ctrl = "C", more = "F" }, "no key, C on ctrl")
    end,

    ["bad input gives an empty plan"] = function(t)
        t.eq(ns.KeyPlan(nil, nil), { states = {}, condition = "0" }, "nothing")
        t.eq(ns.KeyPlan({ keys = "x" }, "y"), { states = {}, condition = "0" }, "wrong kinds")
        t.eq(ns.KeyPlan({}, { forms = { { name = "Cat", index = 1 } } }), { states = {}, condition = "[form:1] 1; 0" }, "no keys")
    end,

    ["pure: the same input gives the same plan and nothing is changed"] = function(t)
        local p, prefs = pack(), { known = { A = true, B = true, G = true }, forms = { { name = "Cat", index = 3 } } }
        t.eq(ns.KeyPlan(p, prefs), ns.KeyPlan(p, prefs), "same answer")
        t.eq(p, pack(), "pack not changed")
        t.eq(prefs, { known = { A = true, B = true, G = true }, forms = { { name = "Cat", index = 3 } } }, "prefs not changed")
    end,

    ["druid pack: caster, bear, cat and prowl rows"] = function(t)
        local plan = ns.KeyPlan(ns.Packs.DRUID, { forms = {
            { name = "Bear Form", index = 1 }, { name = "Cat Form", index = 3 },
        } })
        t.eq(plan.condition, "[form:1] 1; [form:3,stealth] 9; [form:3] 3; 0", "condition")
        t.eq(plan.states[0].key, "Wrath", "caster key")
        t.eq(plan.states[0].ctrl, "Moonfire", "caster ctrl")
        t.eq(plan.states[1].key, "Maul", "bear key")
        t.eq(plan.states[3].key, "Claw", "cat key")
        t.eq(plan.states[3].ctrl, "Ferocious Bite", "cat ctrl")
        t.eq(plan.states[9].key, "Ravage", "prowl key")
        t.eq(plan.stealthForm, 3, "stealthForm")
    end,

    ["druid pack: a low level druid gets what is known"] = function(t)
        local plan = ns.KeyPlan(ns.Packs.DRUID, {
            known = { Wrath = true, ["Entangling Roots"] = true, Claw = true, Rake = true },
            forms = { { name = "Cat Form", index = 1 } },
        })
        t.eq(plan.states[0].key, "Wrath", "caster key")
        t.eq(plan.states[0].ctrl, "Entangling Roots", "Moonfire not known")
        t.eq(plan.states[1].key, "Claw", "cat key")
        t.eq(plan.states[1].ctrl, "Rake", "cat ctrl")
        t.eq(plan.states[9].key, "Rake", "prowl: no opener known, so Rake")
        t.eq(plan.condition, "[form:1,stealth] 9; [form:1] 1; 0", "condition")
    end,
}
