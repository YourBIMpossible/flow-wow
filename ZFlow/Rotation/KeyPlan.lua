local _, ns = ...

-- The key plan: which spell each modifier of the one key holds in each
-- shapeshift form. Pure: the pack and the prefs in, a plain table out. The
-- cast layer turns the plan into real bindings (ns.cast.Apply); nothing here
-- touches the game.
--
--   ns.KeyPlan(pack, prefs) -> bindings
--
-- pack.keys: { [formName or "none"] = { key, ctrl, shift, alt, more },
--              stealth = { form = formName, key, ... } }
--   Each slot is a spell name or a list of names: the first one you know
--   that the row has not used already.
--
-- prefs (all optional):
--   known  { [spell] = true }   the spells you know; nil = take the first named
--   forms  { { name, index }, ... }  your forms in the game's order
--   slots  { "ctrl", "more" }   the modifiers a form fills (this is the default)
--   skip   { [spell] = true }   spells never to bind
--
-- bindings:
--   states     { [0] = row for no form, [index] = row for that form,
--                [STEALTH_STATE] = row while stealthed in the stealth form }
--              a row is { key, ctrl, shift, alt, more } of spell names; a
--              state with nothing to cast has no row
--   condition  the state condition string, stealth first ("[form:3,stealth] 9; [form:3] 3; 0")
--   stealthForm  the index of the form the stealth row belongs to, or nil
--
-- The logic is the pure form plan of Modules/Rotation/Cast.lua (C.FormPlan).

ns.Rotation = ns.Rotation or {}
local R = ns.Rotation

R.FORM_STATES = 8                       -- form numbers a state can be (0 = no form)
R.STEALTH_STATE = R.FORM_STATES + 1     -- one more: stealthed in a form
R.KEY_SLOTS = { "ctrl", "more" }

local function entry(e, slots, known, skip)
    if type(e) ~= "table" then return nil end
    local used, any = {}, false
    local function pick(v)
        if type(v) == "string" then v = { v } end
        if type(v) ~= "table" then return nil end
        for _, spell in ipairs(v) do
            if not used[spell] and not (skip and skip[spell]) and (not known or known[spell]) then
                used[spell] = true
                any = true
                return spell
            end
        end
    end
    local out = { key = pick(e.key) }
    local hasShift = false
    for _, slot in ipairs(slots) do
        out[slot] = pick(e[slot])
        if slot == "shift" then hasShift = true end
    end
    -- Where Shift is filled, the second attack sits on Shift and what Shift
    -- had goes to Ctrl (as the queue shows them).
    if hasShift then out.ctrl, out.shift = out.shift, out.ctrl end
    return any and out or nil
end

function ns.KeyPlan(pack, prefs)
    prefs = type(prefs) == "table" and prefs or {}
    local keys = type(pack) == "table" and type(pack.keys) == "table" and pack.keys or {}
    local slots = type(prefs.slots) == "table" and prefs.slots or R.KEY_SLOTS
    local known, skip = prefs.known, prefs.skip
    local cond, states = {}, { [0] = entry(keys.none, slots, known, skip) }
    local out = { states = states }
    for _, f in ipairs(prefs.forms or {}) do
        if type(f) == "table" and type(f.index) == "number" and f.index >= 1 and f.index <= R.FORM_STATES then
            -- Stealthed in this form first: the first condition that holds is taken.
            local st = keys.stealth
            if type(st) == "table" and st.form == f.name then
                local e = entry(st, slots, known, skip)
                if e then
                    cond[#cond + 1] = string.format("[form:%d,stealth] %d", f.index, R.STEALTH_STATE)
                    states[R.STEALTH_STATE] = e
                    out.stealthForm = f.index
                end
            end
            cond[#cond + 1] = string.format("[form:%d] %d", f.index, f.index)
            states[f.index] = entry(keys[f.name], slots, known, skip)
        end
    end
    cond[#cond + 1] = "0"
    out.condition = table.concat(cond, "; ")
    return out
end
