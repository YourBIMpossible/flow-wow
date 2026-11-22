local _, ns = ...

-- The modifier queue (S13): what each modifier + the key casts in the form
-- you are in, as plain values a display can draw. Ported from Flow 0.35.377
-- Modules/Rotation/Queue.lua and the deck drawing in Display.lua.
--
-- Pure: tables in, tables out. Nothing here reads the client, and nothing
-- here presses, binds or casts.
local Q = {}
ns.Queue = Q

-- The slots, nearest the big icon first, and the words drawn over them.
Q.ORDER = { "shift", "ctrl", "alt", "more" }
Q.LABEL = { ctrl = "CTRL", shift = "SHIFT", alt = "ALT", more = "C+S" }
Q.SIZES = { 36, 30, 25, 22 }
Q.GAP_FIRST = 10 -- between the big icon and the first slot
Q.GAP = 6        -- between two slots

local SPOT = {
    TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 },
    LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
    BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
}

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function spellOf(v)
    if type(v) == "string" and v ~= "" then return v end
    return nil
end

-- The key plan row for the form you are in: { key, ctrl, shift, alt, more },
-- or nil when the plan or the form is not known. Stealthed in the stealth
-- form, the stealth row where the plan has one.
function Q.Row(plan, form, stealthed, stealthForm)
    if type(plan) ~= "table" or type(plan.states) ~= "table" or type(form) ~= "number" then return nil end
    local row
    if stealthed == true and stealthForm == form then
        local R = ns.Rotation
        row = R and R.STEALTH_STATE and plan.states[R.STEALTH_STATE] or nil
    end
    if type(row) ~= "table" then row = plan.states[form] end
    if type(row) ~= "table" then return nil end
    return row
end

-- The slots of a row with nothing drawn twice: a slot that casts what the
-- key or a nearer slot already casts is left empty. { [slot] = spell }.
function Q.NoRepeats(row)
    local out = {}
    if type(row) ~= "table" then return out end
    local seen = {}
    local key = spellOf(row.key)
    if key then seen[key] = true end
    for _, slot in ipairs(Q.ORDER) do
        local spell = spellOf(row[slot])
        if spell and not seen[spell] then
            seen[spell] = true
            out[slot] = spell
        end
    end
    return out
end

-- Which press casts the suggested spell: "key", "ctrl", "shift", "alt",
-- "more", or nil (none of them: it is on your bar).
function Q.AdviceSlot(spell, row)
    spell = spellOf(spell)
    if not spell or type(row) ~= "table" then return nil end
    for _, name in ipairs({ "key", "ctrl", "shift", "alt", "more" }) do
        if row[name] == spell then return name end
    end
    return nil
end

-- The slot whose modifiers are held: "ctrl", "shift", "alt", or "more" for
-- Ctrl + Shift together; nil for none or any other combination. A modifier
-- the client did not answer for (not true and not false) is not known, and
-- then nothing is held: unknown is never read as "up".
function Q.HeldMod(ctrl, shift, alt)
    if type(ctrl) ~= "boolean" or type(shift) ~= "boolean" or type(alt) ~= "boolean" then return nil end
    if ctrl and shift and not alt then return "more" end
    local n = (ctrl and 1 or 0) + (shift and 1 or 0) + (alt and 1 or 0)
    if n ~= 1 then return nil end
    return (ctrl and "ctrl") or (shift and "shift") or "alt"
end

-- Is the queue on screen at all: in a fight, with an enemy targeted, or
-- while a modifier is held.
function Q.Shows(inCombat, hostile, mod)
    return inCombat == true or hostile == true or mod ~= nil
end

-- What to draw: one entry per slot in Q.ORDER,
--   { slot, label, size, spell (nil: draw nothing), state }
-- state is "held" (its modifier is down), "advised" (it casts what is
-- suggested: hold that modifier), or nil.
function Q.Slots(row, suggested, held)
    local slots = Q.NoRepeats(row)
    local advised = Q.AdviceSlot(suggested, row)
    local out = {}
    for i, slot in ipairs(Q.ORDER) do
        local spell = slots[slot]
        local state
        if spell then
            if held == slot then state = "held" elseif advised == slot then state = "advised" end
        end
        out[i] = { slot = slot, label = Q.LABEL[slot], size = Q.SIZES[i], spell = spell, state = state }
    end
    return out
end

-- Which way the slots run from the big icon: "right" when its middle is in
-- the right half of the screen, else "left" (also when the screen or the
-- point is not known).
function Q.Side(point, size, screenW)
    if type(point) ~= "table" or not finite(size) or not finite(screenW) or screenW <= 0 then return "left" end
    local a, r = SPOT[point[1]], SPOT[point[2]]
    if not a or not r or not finite(point[3]) then return "left" end
    local centre = r[1] * screenW + point[3] - a[1] * size + size / 2
    return centre > screenW / 2 and "right" or "left"
end

-- Where each slot stands: a list of points against the same two anchors as
-- the big icon's own point, bottoms level with it, out to `side`, nearest
-- first. nil for a point that cannot be used.
function Q.Place(point, size, side)
    if type(point) ~= "table" or not finite(size) then return nil end
    local a = SPOT[point[1]]
    if not a or not SPOT[point[2]] or not finite(point[3]) or not finite(point[4]) then return nil end
    local fx, fy = a[1], a[2]
    local out, run = {}, Q.GAP_FIRST
    for i, w in ipairs(Q.SIZES) do
        local x
        if side == "right" then
            x = point[3] + (1 - fx) * size + run + fx * w
        else
            x = point[3] - fx * size - run - (1 - fx) * w
        end
        out[i] = { point[1], point[2], x, point[4] - fy * (size - w) }
        run = run + w + Q.GAP
    end
    return out
end

-- The same points with every slot moved onto the screen: a slot whose box
-- would cross an edge is moved in by just that much. Points against a
-- screen that is not known, or that cannot be read, come back as they are.
function Q.Clamp(points, screenW, screenH)
    if type(points) ~= "table" then return points end
    if not finite(screenW) or not finite(screenH) or screenW <= 0 or screenH <= 0 then return points end
    local out = {}
    for i, p in ipairs(points) do
        local w = Q.SIZES[i]
        local a = type(p) == "table" and SPOT[p[1]] or nil
        local r = type(p) == "table" and SPOT[p[2]] or nil
        if not w or not a or not r or not finite(p[3]) or not finite(p[4]) then
            out[i] = p
        else
            local left = r[1] * screenW + p[3] - a[1] * w
            local bottom = r[2] * screenH + p[4] - a[2] * w
            local dx = math.max(0, math.min(left, screenW - w)) - left
            local dy = math.max(0, math.min(bottom, screenH - w)) - bottom
            out[i] = { p[1], p[2], p[3] + dx, p[4] + dy }
        end
    end
    return out
end

-- Does the whole run of slots fit on the screen out to `side`? true or
-- false; nil when the screen or the point is not known.
function Q.Fits(point, size, side, screenW)
    if type(point) ~= "table" or not finite(size) or not finite(screenW) or screenW <= 0 then return nil end
    local a, r = SPOT[point[1]], SPOT[point[2]]
    if not a or not r or not finite(point[3]) then return nil end
    local run = Q.GAP_FIRST
    for i, w in ipairs(Q.SIZES) do run = run + w + (i > 1 and Q.GAP or 0) end
    local left = r[1] * screenW + point[3] - a[1] * size
    if side == "right" then return left + size + run <= screenW end
    return left - run >= 0
end

-- The side the slots run to: `side` when they fit there or the screen is
-- not known, else the other side when they fit there, else `side`.
function Q.FitSide(point, size, side, screenW)
    if Q.Fits(point, size, side, screenW) ~= false then return side end
    local other = side == "right" and "left" or "right"
    if Q.Fits(point, size, other, screenW) == true then return other end
    return side
end
