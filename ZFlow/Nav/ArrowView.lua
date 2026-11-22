local _, ns = ...
-- Z-Flow arrow view: what a frame must be set to for each arrow, as plain
-- data. Pure Lua 5.1: no client calls and nothing remembered between calls.
-- Every value is worked out from the state handed in, on every update, so
-- nothing can be left over from the update before (target section 12).
-- Needs Nav/ArrowLayout.lua.
ns.Nav = ns.Nav or {}
local N = ns.Nav

-- Exact values carried over from Flow.
N.AT_POINT = 24                 -- yards: standing on a step's point
N.PROF_RING_ALPHA = 0.35        -- the faint ring at the profession step
N.PROF_LEN = 64.8               -- the needle's drawn length (54 * 0.8 * 1.5)
N.TRAVEL_ICON = 38              -- the travel icon's size
N.TRAVEL_ARROW_SCALE = 0.5      -- the quest arrow while it stands beside that icon
N.TEXT_GAP_BELOW, N.TEXT_GAP_ABOVE = 2, 4

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function knownScreen(w, h)
    return finite(w) and finite(h) and w > 0 and h > 0
end

-- Standing on a step's point (not just inside its area).
function N.AtPoint(d)
    return finite(d) and d < N.AT_POINT
end

-- What the profession arrow draws: "ring" at its own step; "off" when it
-- cannot point, or (stacked only) while the player stands on the main step's
-- point; else "arrow".
function N.ProfArrowMode(mainAtPoint, profHere, canPoint)
    if profHere then return "ring" end
    if mainAtPoint or not canPoint then return "off" end
    return "arrow"
end

-- How far the needle reaches past an arrow frame's edge, plus a little air.
function N.NeedleClearance(size)
    size = finite(size) and size or N.ARROW_SIZE
    return math.max(0, math.ceil(N.PROF_LEN / 2 - size / 2)) + 2
end

-- Which side of an arrow its text goes: above when the arrow is in the top
-- half of the screen and the lines fit there, else below.
function N.TextSide(centreY, screenH, top, need)
    if centreY < screenH / 2 then return "below" end
    if top + need > screenH then return "below" end
    return "above"
end

-- Where an arrow's text hangs. -> { shown, to, side, point, first }
--   to: "quest" or "prof", the arrow frame the point is relative to.
--   point: { anchor, relative anchor, x, y } on that frame.
local function textOps(shown, to, position, size, sw, sh, clear, need, travel)
    local side = "below"
    if knownScreen(sw, sh) and position then
        local _, bottom = N.ArrowCorner(position, size, sw, sh)
        side = N.TextSide(bottom + size / 2, sh, bottom + size, need + (clear or 4))
    end
    local first = clear or (side == "above" and N.TEXT_GAP_ABOVE or N.TEXT_GAP_BELOW)
    if travel then first = math.max(first, (N.TRAVEL_ICON - size) / 2 + 4) end
    local point
    if side == "above" then
        point = { "BOTTOM", "TOP", 0, first }
    else
        point = { "TOP", "BOTTOM", 0, -first }
    end
    return { shown = shown and true or false, to = to, side = side, point = point, first = first }
end

local function point4(p)
    return p and { p[1], p[2], p[3], p[4] } or nil
end

-- state = {
--   layout, screenW, screenH, size, defaultPoint,   -- as N.ArrowLayout
--   gate,                    -- N.ArrowGate's answer
--   palette,                 -- N.ARROW_PALETTE row, nil = standard
--   player = { cont, zone }, -- nil = unknown
--   facingKnown,             -- the player's facing can be read
--   quest = { hasStep, overlay, target = { cont, zone }, here, distance,
--             travel, textHeight },
--   prof  = { on, hasStep, target = { cont, zone }, here, distance,
--             bearingKnown, own = { r, g, b }, textHeight },
-- }
--   here: inside the step's area. distance: yards to the step's own point,
--   nil = unknown. travel: the travel icon is shown. prof.on == false: the
--   profession arrow setting is off.
-- -> { quest = ops, prof = ops, stacked = bool }, ops:
--   shown, anchor ("screen" or "quest"), point { a, r, x, y } on the screen,
--   scale, alpha, colour { r, g, b }, look ("pointer" or "needle"),
--   mode ("arrow", "ring", "off", "corpse", "intro"), behind, beside,
--   text { shown, to, side, point, first }.
function N.ArrowView(state)
    state = type(state) == "table" and state or {}
    local q = type(state.quest) == "table" and state.quest or {}
    local p = type(state.prof) == "table" and state.prof or {}
    local gate = state.gate or "off"
    local size = finite(state.size) and state.size or N.ARROW_SIZE
    local sw, sh = state.screenW, state.screenH
    local saved = N.ArrowSaved(state.layout)
    local separate = saved.mode == "separate"

    local canPoint = (p.bearingKnown and state.facingKnown) and true or false
    local profHere = (p.here or N.AtPoint(p.distance)) and true or false
    local questHere = (q.here or N.AtPoint(q.distance)) and true or false
    -- Separated, the profession arrow has its own place: the main step's
    -- point does not switch it off.
    local profMode = N.ProfArrowMode(not separate and N.AtPoint(q.distance), profHere, canPoint)
    local profStep = (p.on ~= false and p.hasStep) and true or false

    local L = N.ArrowLayout({
        layout = state.layout, gate = gate, screenW = sw, screenH = sh,
        size = state.size, defaultPoint = state.defaultPoint,
        quest = { hasStep = q.hasStep, overlay = q.overlay },
        prof = { hasStep = profStep, mode = profMode },
    })
    local lq, lp = L.quest, L.prof
    local under = lp.shown and lp.anchor == "quest" and lq.shown   -- stacked behind the quest arrow

    -- ---------------------------------------------------------- quest arrow
    local qMode = "arrow"
    if gate == "corpse" then
        qMode = "corpse"
    elseif gate == "intro" then
        qMode = "intro"
    elseif questHere then
        qMode = "ring"
    end
    local travel = (lq.shown and qMode == "arrow" and q.travel) and true or false
    -- 0.8 / 0.7 only while the needle really is drawn under a pointing quest
    -- arrow. Never for the corpse arrow, the arrived ring or the intro, and
    -- never beside the travel icon. Scale and alpha are always set together.
    local scale, alpha = 1, 1
    if travel then
        scale = N.TRAVEL_ARROW_SCALE
    elseif under and profMode == "arrow" and qMode == "arrow" then
        scale, alpha = N.ON_NEEDLE_SCALE, N.ON_NEEDLE_ALPHA
    end
    local qState = qMode == "corpse" and "corpse" or N.ArrowState(state.player, q.target, questHere)
    local qr, qg, qb = N.ArrowColor(qState, q.distance, state.palette)
    local stackClear = under and N.NeedleClearance(size) or nil
    local qNeed = finite(q.textHeight) and q.textHeight or 0
    local quest = {
        shown = lq.shown, anchor = "screen", point = point4(lq.position),
        scale = scale, alpha = alpha, colour = { qr, qg, qb },
        look = "pointer", mode = qMode, behind = false, beside = travel,
        text = textOps(lq.shown and lq.text, "quest", lq.position, size, sw, sh,
                       stackClear, qNeed, travel),
    }

    -- ----------------------------------------------------- profession arrow
    local pState = N.ArrowState(state.player, p.target, profHere)
    local pr, pg, pb, pa = N.ArrowPaint(lp, pState, p.distance, state.palette, p.own)
    if profMode == "ring" then pa = N.PROF_RING_ALPHA end
    local pNeed = finite(p.textHeight) and p.textHeight or 0
    local pText
    if under then
        -- One stack of lines on the quest arrow: same side, same first gap.
        pText = textOps(lp.text, "quest", lq.position, size, sw, sh, stackClear, qNeed + pNeed, travel)
    else
        local clear = lp.look == "needle" and N.NeedleClearance(size) or nil
        pText = textOps(lp.shown and lp.text, "prof", lp.position, size, sw, sh, clear, pNeed, false)
    end
    local prof = {
        shown = (lp.shown and profMode ~= "off") and true or false,
        anchor = lp.anchor, point = point4(lp.position),
        scale = 1, alpha = pa, colour = { pr, pg, pb },
        look = lp.look, mode = profMode, behind = lp.behind and true or false, beside = false,
        text = pText,
    }
    return { quest = quest, prof = prof, stacked = L.stacked }
end
