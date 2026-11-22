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
-- lockdown  true while the game refuses binding changes (in combat)
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
--   stealthForm the form the stealth state belongs to, or nil
--   plan        a copy of the new plan: hand it back as `applied` next time
--
-- result, when it is refused: { ok = false, refused, reason, ops = {} }
--   refused = "lockdown"  in combat: nothing may change; keep `applied` and
--                         ask again when the fight is over
--   refused = "plan"      the plan is not a key plan

ns.cast = ns.cast or {}
ns.Rotation = ns.Rotation or {}
local C, R = ns.cast, ns.Rotation

C.SLOTS = { "key", "ctrl", "shift", "alt", "more" }
C.REFUSED = {
    lockdown = "In a fight: your keys change when it ends",
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
    if lockdown then return refuse("lockdown") end
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
