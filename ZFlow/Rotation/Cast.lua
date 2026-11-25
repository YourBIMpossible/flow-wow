local _, ns = ...

-- The cast plan: what has to change on the one key to go from the bindings
-- in place to a new key plan. Pure: plain tables in, a plain table out. It
-- binds nothing itself; the frame layer walks the list and does each step.
--
--   ns.cast.Apply(plan, applied, lockdown) -> result
--
-- plan      what ns.KeyPlan returned: { states, condition, stealthForm },
--           plus altItem (N8): an item id the Alt slot uses instead of its
--           spell, or nil. N8 stays PARTLY until seen in the client.
--           Plus action (P-KEYS slice D, Rotation/KeyActions.lua): what the
--           key itself holds instead of its slot spell, out of a fight only:
--           { spell, unit } (unit player, target or none) or { itemId }; the
--           spell or item type, never a macro (section 246).
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

-- N41 (P-KEYS slice B): a plan may name the unit a modifier slot casts on
-- (plan.units[slot], one of C.UNITS, or a group token: KC-1, the Ctrl heal
-- on the friend you target by its stable party or raid token, since
-- "target" re-resolves at the press); a slot with none casts on the target.
local function groupUnit(u)
    if u == "party1" or u == "party2" or u == "party3" or u == "party4" then return true end
    local n = tonumber(u:match("^raid(%d%d?)$") or "")
    return n ~= nil and n >= 1 and n <= 40
end

local function unitsOf(p)
    local out
    if type(p.units) ~= "table" then return nil end
    for _, slot in ipairs(C.MODIFIERS) do
        local u = p.units[slot]
        if type(u) == "string" and (C.UNITS[u] or groupUnit(u)) then
            out = out or {}
            out[slot] = u
        end
    end
    return out
end

-- P-KEYS slice D: a plan's key action, checked, as a fresh table; nil when
-- there is none or it is not one the key may hold.
local function actionOf(p)
    local a = p.action
    if type(a) ~= "table" then return nil end
    local id = a.itemId
    if type(id) == "number" and id > 0 and id % 1 == 0 then return { itemId = id } end
    if type(a.spell) ~= "string" or a.spell == "" then return nil end
    if a.unit ~= nil and a.unit ~= "player" and a.unit ~= "target" then return nil end
    return { spell = a.spell, unit = a.unit }
end

local function actionText(a)
    if type(a) ~= "table" then return "-" end
    return tostring(a.itemId) .. "|" .. tostring(a.spell) .. "|" .. tostring(a.unit)
end

local function unitsText(units)
    local parts = {}
    for _, slot in ipairs(C.MODIFIERS) do
        if units then parts[#parts + 1] = slot .. "=" .. tostring(units[slot]) end
    end
    return table.concat(parts, ",")
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
        altItem = (type(p.altItem) == "number" and p.altItem > 0 and p.altItem % 1 == 0) and p.altItem or nil,
        units = unitsOf(p),
        action = actionOf(p),
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
    local unitsChanged = unitsText(new.units) ~= unitsText(old.units)
        or actionText(new.action) ~= actionText(old.action)
    return {
        ok = true,
        ops = ops,
        counts = counts,
        changed = (counts.set + counts.clear > 0 or conditionChanged or new.altItem ~= old.altItem or unitsChanged) and true or false,
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
-- suggestion  what ns.Choose returned ({ spell, kind, unit }), or nil; one
--             with look = true (P-PARTY) counts as nil: it is only shown
-- plan, applied, lockdown   as for Apply
-- form        the state you are in now (0 = no form; the stealth state while
--             stealthed in the stealth form); anything else reads as 0
--
-- result, when it can be done:
--   ok        true
--   button    an ordered list of { attr, value } for the button; a row with
--             no value clears that attribute. First the key itself (type,
--             spell, unit, item), then three per modifier slot
--             ("*type-ctrl", "*spell-ctrl", "*unit-ctrl", ...), then
--             "*item-alt", then "macrotext" and "*macrotext-alt", which are
--             only ever cleared.
--             The key casts the suggestion: a heal, an emergency or your own
--             buff on you, Attack as the Attack spell with no unit, an item
--             suggestion as the item type ("item:ID"), anything else with no
--             unit (the game's own target rules). With no suggestion it holds
--             the form's own key spell on your target. The modifier slots
--             always hold the form's row, on your target.
--             Section 246 (N63-E): no row ever gives the type "macro". A
--             macro-type secure button does not act on this client: the press
--             arrives with the right macro and nothing is cast (legacy Flow
--             moved Attack off the macro type for the same reason).
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
-- Parity row D-04 (lead section 697), as Flow's Modules/Rotation/Cast.lua
-- (:877-932): the state handler's secure code, run by the game when the
-- state driver on C.STATE changes state (a form change, in a fight too).
-- It copies the header rows of the state entered ("key-N", "ctrl-N", ...)
-- onto the key ("key" frame ref); "" clears a slot. Restricted code, given
-- to the handler out of a fight only; never a macro. A first guess: the
-- restricted calls are on warcraft.wiki.gg (SecureHandlerStateTemplate,
-- RestrictedEnvironment), not seen in this client.
-- D-04 CHANGES (Lazy, lead section 729), as Flow's Cast.lua (:797-815):
-- out of a fight it does nothing (the add-on sets the key there itself);
-- the key and each slot spell it copies are cast as a spell on your target.
C.FORM_SNIPPET = [=[
if not PlayerInCombat() then return end
local key = self:GetFrameRef("key")
if not key then return end
local v = self:GetAttribute("key-" .. newstate)
if v and v ~= "" then
    key:SetAttribute("type", "spell")
    key:SetAttribute("spell", v)
    key:SetAttribute("unit", "target")
    key:SetAttribute("item", nil)
end
v = self:GetAttribute("ctrl-" .. newstate)
if v == "" then v = nil end
key:SetAttribute("*spell-ctrl", v)
if v then
    key:SetAttribute("*type-ctrl", "spell")
    key:SetAttribute("*unit-ctrl", "target")
end
v = self:GetAttribute("shift-" .. newstate)
if v == "" then v = nil end
key:SetAttribute("*spell-shift", v)
if v then
    key:SetAttribute("*type-shift", "spell")
    key:SetAttribute("*unit-shift", "target")
end
v = self:GetAttribute("alt-" .. newstate)
if v == "" then v = nil end
key:SetAttribute("*spell-alt", v)
if v then
    key:SetAttribute("*type-alt", "spell")
    key:SetAttribute("*unit-alt", "target")
end
v = self:GetAttribute("more-" .. newstate)
if v == "" then v = nil end
key:SetAttribute("*spell-more", v)
if v then
    key:SetAttribute("*type-more", "spell")
    key:SetAttribute("*unit-more", "target")
end
]=]
C.MODIFIERS = { "ctrl", "shift", "alt", "more" }
C.ON_YOU = { heal = true, emergency = true, buff = true }
-- The only units a suggestion may name for the key. Anyone else (a party or
-- raid member, focus, mouseover) is never cast on: help for another player
-- is only shown (look = true, Rotation/Group.lua), never put on the key.
C.UNITS = { player = true, pet = true, target = true }
C.ATTACK = { ["Attack"] = true, ["Auto Attack"] = true }
-- Section 249 (CT-1): the one name the key casts the swing by. A suggestion
-- or a slot may say "Auto Attack" (the rows name either); the secure button
-- is always given "Attack", so a name the client cannot cast never leaves
-- the key doing nothing.
C.ATTACK_SPELL = "Attack"

-- A spell name as the button casts it: either swing name becomes "Attack".
local function castName(v)
    if v ~= nil and C.ATTACK[v] then return C.ATTACK_SPELL end
    return v
end

local function row(list, attr, value)
    list[#list + 1] = { attr = attr, value = value }
end

local function spellOf(suggestion)
    if type(suggestion) ~= "table" then return nil end
    local s = suggestion.spell
    return type(s) == "string" and s ~= "" and s or nil
end

-- Section 226 (CF-30): an item suggestion's item id (a whole number above
-- 0), or nil.
local function itemOf(suggestion)
    if type(suggestion) ~= "table" then return nil end
    local id = suggestion.itemId
    if type(id) ~= "number" or id <= 0 or id % 1 ~= 0 then return nil end
    return id
end

function C.Attributes(suggestion, plan, applied, lockdown, form)
    local apply = C.Apply(plan, applied, lockdown)
    if not apply.ok then
        apply.button, apply.header = {}, {}
        return apply
    end
    local states = apply.plan.states
    if type(form) ~= "number" or form < 0 or form > lastState() or form % 1 ~= 0 then form = 0 end

    -- P-PARTY: a look-only suggestion (look = true: for another player) is
    -- never put on the key. The key holds what it holds with no suggestion.
    if type(suggestion) == "table" and suggestion.look == true then suggestion = nil end

    local button = {}
    local spell, source = spellOf(suggestion), "suggestion"
    local kind, unit, item
    if spell and C.ATTACK[spell] then
        -- Section 246 (N63-E): the Attack spell itself under the name the
        -- suggestion gives, with no unit (the game's own target rules), as
        -- legacy Flow did; not a "/startattack" macro, which does not act
        -- on this client. Section 249 (CT-1): always under the name
        -- "Attack", whichever swing name the suggestion gives.
        spell, kind = C.ATTACK_SPELL, "spell"
    elseif spell then
        kind = "spell"
        unit = C.UNITS[suggestion.unit] and suggestion.unit or (C.ON_YOU[suggestion.kind] and "player") or nil
    elseif itemOf(suggestion) then
        -- Section 226 (CF-30): an item (Well Fed food) is used by its id on
        -- the player's press. Section 246 (N63-E): through the secure item
        -- type, item = "item:ID", as legacy Flow did; not a macro.
        item = itemOf(suggestion)
        kind = "item"
    elseif type(apply.plan.action) == "table" and apply.plan.action.itemId ~= nil then
        -- P-KEYS slice D: the plan's key action, an item (the item type).
        item, kind, source = apply.plan.action.itemId, "item", "plan"
    elseif type(apply.plan.action) == "table" then
        -- P-KEYS slice D: the plan's key action, a spell on its unit.
        spell, kind, unit, source = apply.plan.action.spell, "spell", apply.plan.action.unit, "plan"
    else
        spell, source = castName(slotOf(states, form, "key")), "plan"
        if spell then
            kind, unit = "spell", "target"
        else
            source = nil
        end
    end
    row(button, "type", kind)
    row(button, "spell", kind == "spell" and spell or nil)
    row(button, "unit", unit)
    row(button, "item", item and ("item:" .. item) or nil)
    -- N8: with plan.altItem the Alt slot uses that item instead of its
    -- spell. Section 246 (N63-E): as the item type, "*type-alt" = "item" and
    -- "*item-alt" = "item:ID", the modifier form legacy Flow's slots used.
    -- N8 stays PARTLY until seen in the client.
    local altItem = apply.plan.altItem
    for _, slot in ipairs(C.MODIFIERS) do
        if slot == "alt" and altItem then
            row(button, "*type-alt", "item")
            row(button, "*spell-alt", nil)
            row(button, "*unit-alt", nil)
        else
            local v = castName(slotOf(states, form, slot))
            -- N41: the plan's unit for the slot (plan.units), else the target.
            local slotUnit
            if v then
                slotUnit = "target"
                if apply.plan.units and apply.plan.units[slot] then slotUnit = apply.plan.units[slot] end
            end
            row(button, "*type-" .. slot, v and "spell" or nil)
            row(button, "*spell-" .. slot, v)
            row(button, "*unit-" .. slot, slotUnit)
        end
    end
    -- N8: last, so the rows above keep their places.
    row(button, "*item-alt", altItem and ("item:" .. altItem) or nil)
    -- Section 246 (N63-E): the macro text attributes are never given a value;
    -- their rows only clear anything left there, so nothing left over acts.
    row(button, "macrotext", nil)
    row(button, "*macrotext-alt", nil)

    local header = {}
    for state = 0, lastState() do
        for _, slot in ipairs(C.SLOTS) do
            row(header, slot .. "-" .. state, castName(slotOf(states, state, slot)) or "")
        end
    end

    return {
        ok = true,
        button = button,
        header = header,
        driver = { state = C.STATE, condition = apply.condition, changed = apply.conditionChanged },
        source = source,
        spell = spell,
        item = item,
        form = form,
        apply = apply,
        plan = apply.plan,
    }
end
