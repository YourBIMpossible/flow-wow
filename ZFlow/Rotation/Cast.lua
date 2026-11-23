local _, ns = ...

-- The cast plan: what has to change on the one key to go from the bindings
-- in place to a new key plan. Pure: plain tables in, a plain table out. It
-- binds nothing itself; the frame layer walks the list and does each step.
--
--   ns.cast.Apply(plan, applied, lockdown) -> result
--
-- plan      what ns.KeyPlan returned: { states, condition, stealthForm }
-- applied   the plan in place now (the `plan` field of the last result that
--           was carried out), or nil when nothing is bound yet
-- lockdown  true while the game refuses binding changes (in combat), false
--           when it takes them. Only a plain false lets a change through:
--           nil (not known) or any other value is refused.
--
-- result, when it can be done:
--   ok          true
--   ops         an ordered list, one row per state and slot that the new or
--               the old plan fills:
--                 { op = "set", state, slot, spell, was }   bind spell (was = the old one, or nil)
--                 { op = "clear", state, slot, was }        nothing goes here any more
--                 { op = "unchanged", state, slot, spell }  already right
--               Order: state 0, then the form states upward, the stealth
--               state last; within a state key, ctrl, shift, alt, more.
--   counts      { set, clear, unchanged }
--   changed     true when any op is a set or a clear, or the condition differs
--   condition   the state condition string to drive the states with
--   conditionChanged  true when it differs from the one in place
--   stealthForm the form the stealth state belongs to, 0 for no form (any form), or nil
--   plan        a copy of the new plan: hand it back as `applied` next time
--
-- result, when it is refused: { ok = false, refused, reason, ops = {} }
--   refused = "lockdown"  in combat: nothing may change; keep `applied` and
--                         ask again when the fight is over
--   refused = "lockdownUnknown"  lockdown was not a plain true or false: it is not
--                         known whether the game takes changes; keep
--                         `applied` and ask again once it is known
--   refused = "plan"      the plan is not a key plan

ns.cast = ns.cast or {}
ns.Rotation = ns.Rotation or {}
local C, R = ns.cast, ns.Rotation

C.SLOTS = { "key", "ctrl", "shift", "alt", "more" }
C.REFUSED = {
    lockdown = "In a fight: your keys change when it ends",
    lockdownUnknown = "Not known whether you are in a fight: your keys change once that is known",
    plan = "No key plan to apply",
}

local function refuse(why)
    return { ok = false, refused = why, reason = C.REFUSED[why], ops = {} }
end

-- The state numbers a plan can fill: 0, the forms, the stealth state.
local function lastState()
    return R.STEALTH_STATE or ((R.FORM_STATES or 8) + 1)
end

local function isPlan(p)
    return type(p) == "table" and type(p.states) == "table"
end

local function slotOf(states, state, slot)
    local row = states[state]
    if type(row) ~= "table" then return nil end
    local v = row[slot]
    return type(v) == "string" and v or nil
end

local function copyPlan(p)
    local states = {}
    for state = 0, lastState() do
        local row
        for _, slot in ipairs(C.SLOTS) do
            local v = slotOf(p.states, state, slot)
            if v then
                row = row or {}
                row[slot] = v
            end
        end
        states[state] = row
    end
    return {
        states = states,
        condition = type(p.condition) == "string" and p.condition or "0",
        stealthForm = type(p.stealthForm) == "number" and p.stealthForm or nil,
    }
end

function C.Apply(plan, applied, lockdown)
    if not isPlan(plan) then return refuse("plan") end
    if lockdown == true then return refuse("lockdown") end
    if lockdown ~= false then return refuse("lockdownUnknown") end
    local new = copyPlan(plan)
    local old = isPlan(applied) and copyPlan(applied) or { states = {} }
    local ops, counts = {}, { set = 0, clear = 0, unchanged = 0 }
    for state = 0, lastState() do
        for _, slot in ipairs(C.SLOTS) do
            local want, have = slotOf(new.states, state, slot), slotOf(old.states, state, slot)
            local op
            if want and want == have then
                op = { op = "unchanged", state = state, slot = slot, spell = want }
            elseif want then
                op = { op = "set", state = state, slot = slot, spell = want, was = have }
            elseif have then
                op = { op = "clear", state = state, slot = slot, was = have }
            end
            if op then
                ops[#ops + 1] = op
                counts[op.op] = counts[op.op] + 1
            end
        end
    end
    local conditionChanged = new.condition ~= old.condition
    return {
        ok = true,
        ops = ops,
        counts = counts,
        changed = (counts.set + counts.clear > 0 or conditionChanged) and true or false,
        condition = new.condition,
        conditionChanged = conditionChanged,
        stealthForm = new.stealthForm,
        plan = new,
    }
end

-- The secure attributes: what the one button and the state handler have to
-- hold for a suggestion and a key plan. Pure, like Apply: it names every
-- attribute and its value as plain data and sets nothing. The frame layer
-- walks the lists out of a fight and calls SetAttribute for each row.
--
--   ns.cast.Attributes(suggestion, plan, applied, lockdown, form) -> result
--
-- suggestion  what ns.Choose returned ({ spell, kind, unit }), or nil
-- plan, applied, lockdown   as for Apply
-- form        the state you are in now (0 = no form; the stealth state while
--             stealthed in the stealth form); anything else reads as 0
--
-- result, when it can be done:
--   ok        true
--   button    an ordered list of { attr, value } for the button; a row with
--             no value clears that attribute. First the key itself (type,
--             spell, unit, macrotext), then three per modifier slot
--             ("*type-ctrl", "*spell-ctrl", "*unit-ctrl", ...).
--             The key casts the suggestion: a heal, an emergency or your own
--             buff on you, Attack as "/startattack", anything else with no
--             unit (the game's own target rules). With no suggestion it holds
--             the form's own key spell on your target. The modifier slots
--             always hold the form's row, on your target.
--   header    an ordered list of { attr, value } for the state handler: for
--             each state 0 .. the stealth state, "key-N" then "ctrl-N",
--             "shift-N", "alt-N", "more-N"; "" where the plan has nothing.
--             In a fight the handler copies the row of the state you enter
--             onto the button (the game allows that; this code may not).
--   driver    { state, condition, changed }: the state name to watch, the
--             condition string, and whether it differs from the one in place
--   source    "suggestion", "plan" or nil: where the key's spell came from
--   spell     what the key casts, or nil
--   form      the state the button rows were taken from
--   apply     the Apply result for the same plan (ops, counts, changed)
--   plan      a copy of the plan: hand it back as `applied` next time
--
-- result, when it is refused: { ok = false, refused, reason, ops = {},
-- button = {}, header = {} } with the same two reasons as Apply.

C.STATE = "castform"
C.MODIFIERS = { "ctrl", "shift", "alt", "more" }
C.ON_YOU = { heal = true, emergency = true, buff = true }
-- The only units a suggestion may name. Anyone else (a party or raid member,
-- focus, mouseover) is never cast on: Z-Flow does not help other players.
C.UNITS = { player = true, pet = true, target = true }
C.ATTACK = { ["Attack"] = true, ["Auto Attack"] = true }

local function row(list, attr, value)
    list[#list + 1] = { attr = attr, value = value }
end

local function spellOf(suggestion)
    if type(suggestion) ~= "table" then return nil end
    local s = suggestion.spell
    return type(s) == "string" and s ~= "" and s or nil
end

function C.Attributes(suggestion, plan, applied, lockdown, form)
    local apply = C.Apply(plan, applied, lockdown)
    if not apply.ok then
        apply.button, apply.header = {}, {}
        return apply
    end
    local states = apply.plan.states
    if type(form) ~= "number" or form < 0 or form > lastState() or form % 1 ~= 0 then form = 0 end

    local button = {}
    local spell, source = spellOf(suggestion), "suggestion"
    local kind, unit, macro
    if spell and C.ATTACK[spell] then
        kind, macro = "macro", "/startattack"
    elseif spell then
        kind = "spell"
        unit = C.UNITS[suggestion.unit] and suggestion.unit or (C.ON_YOU[suggestion.kind] and "player") or nil
    else
        spell, source = slotOf(states, form, "key"), "plan"
        if spell then
            kind, unit = "spell", "target"
        else
            source = nil
        end
    end
    row(button, "type", kind)
    row(button, "spell", kind == "spell" and spell or nil)
    row(button, "unit", unit)
    row(button, "macrotext", macro)
    for _, slot in ipairs(C.MODIFIERS) do
        local v = slotOf(states, form, slot)
        row(button, "*type-" .. slot, v and "spell" or nil)
        row(button, "*spell-" .. slot, v)
        row(button, "*unit-" .. slot, v and "target" or nil)
    end

    local header = {}
    for state = 0, lastState() do
        for _, slot in ipairs(C.SLOTS) do
            row(header, slot .. "-" .. state, slotOf(states, state, slot) or "")
        end
    end

    return {
        ok = true,
        button = button,
        header = header,
        driver = { state = C.STATE, condition = apply.condition, changed = apply.conditionChanged },
        source = source,
        spell = spell,
        form = form,
        apply = apply,
        plan = apply.plan,
    }
end
