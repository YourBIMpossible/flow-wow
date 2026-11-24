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
-- cannot point, or when mainAtPoint is given; else "arrow". The arrow view
-- gives mainAtPoint false: the profession arrow has its own place over the
-- quest arrow, so it stays at a quest stop.
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

    local canPoint = (p.bearingKnown and state.facingKnown) and true or false
    local profHere = (p.here or N.AtPoint(p.distance)) and true or false
    local questHere = (q.here or N.AtPoint(q.distance)) and true or false
    -- The profession arrow has its own place, stacked or separated: the
    -- main step's point does not switch it off.
    local profMode = N.ProfArrowMode(false, profHere, canPoint)
    local profStep = (p.on ~= false and p.hasStep) and true or false
    local qNeed = finite(q.textHeight) and q.textHeight or 0
    local pNeed = finite(p.textHeight) and p.textHeight or 0
    -- The first gap of each text in the stack of two: the quest text under
    -- the quest arrow, the profession text over the profession arrow.
    local belowFirst = N.TEXT_GAP_BELOW
    if q.travel then belowFirst = math.max(belowFirst, (N.TRAVEL_ICON - size) / 2 + 4) end
    -- Lead section 447 item 5 (F3): the needle keeps its place in the stack
    -- while its step has a place to point at, even when the game gives no
    -- facing yet (at load, or for a moment after). Without that the frame
    -- stood on the quest arrow until the facing came back or the player
    -- restacked. A step in words only (no place) still has no room (D2).
    local slot = profMode ~= "off" or (p.bearingKnown and true or false)
    local aboveFirst = N.TEXT_GAP_ABOVE
    if slot then aboveFirst = N.NeedleClearance(size) end

    local L = N.ArrowLayout({
        layout = state.layout, gate = gate, screenW = sw, screenH = sh,
        size = state.size, defaultPoint = state.defaultPoint,
        quest = { hasStep = q.hasStep, overlay = q.overlay,
                  room = saved.text.quest ~= false and qNeed > 0 and qNeed + belowFirst or 0 },
        prof = { hasStep = profStep, mode = slot and "arrow" or "off",
                 room = saved.text.prof ~= false and pNeed > 0 and pNeed + aboveFirst or 0 },
    })
    local lq, lp = L.quest, L.prof
    local under = lp.shown and lp.anchor == "quest" and lq.shown   -- not laid out any more
    -- The stack of two: the profession arrow over the quest arrow.
    local over = (lp.shown and lp.above and lq.shown) and true or false

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
    local quest = {
        shown = lq.shown, anchor = "screen", point = point4(lq.position),
        scale = scale, alpha = alpha, colour = { qr, qg, qb },
        look = "pointer", mode = qMode, behind = false, beside = travel,
        text = textOps(lq.shown and lq.text, "quest", lq.position, size, sw, sh,
                       stackClear, qNeed, travel),
    }
    if over then
        -- Its text below it, always: the profession arrow stands above.
        quest.text = { shown = (lq.shown and lq.text) and true or false, to = "quest", side = "below",
                       point = { "TOP", "BOTTOM", 0, -belowFirst }, first = belowFirst }
    end

    -- ----------------------------------------------------- profession arrow
    local pState = N.ArrowState(state.player, p.target, profHere)
    local pr, pg, pb, pa = N.ArrowPaint(lp, pState, p.distance, state.palette, p.own)
    if profMode == "ring" then pa = N.PROF_RING_ALPHA end
    local pText
    if over then
        -- Its text above it, always: never between the two arrows. With no
        -- needle drawn its frame stands on the quest arrow's place, so the
        -- lines stand right over the quest arrow.
        pText = { shown = lp.text and true or false, to = "prof", side = "above",
                  point = { "BOTTOM", "TOP", 0, aboveFirst }, first = aboveFirst }
    elseif under then
        -- The fallback: one stack of lines on the quest arrow, same side,
        -- same first gap.
        -- The needle's lines are shown while the needle is "off" too (owner
        -- decision D2), so they take their room then as well.
        pText = textOps(lp.text, "quest", lq.position, size, sw, sh, stackClear, qNeed + pNeed, travel)
        -- Lead section 341: with the quest lines shown, the needle's lines
        -- stand on the other side of the arrow, on the needle's own frame,
        -- with the same first gap. Only when the screen is known and they
        -- fit there; otherwise the one stack above stays.
        -- Lead section 387 R2 (owner, the original look): stacked, the
        -- profession step's lines stand above the arrows and the quest lines
        -- below, wherever the stack is, when both fit there; else as 341.
        local qt = quest.text
        if qt.shown and pText.shown and knownScreen(sw, sh) and lq.position then
            local _, bottom = N.ArrowCorner(lq.position, size, sw, sh)
            local first = qt.first
            if bottom + size + first + pNeed <= sh and bottom - first - qNeed >= 0 then
                quest.text = { shown = true, to = "quest", side = "below",
                               point = { "TOP", "BOTTOM", 0, -first }, first = first }
                pText = { shown = true, to = "prof", side = "above",
                          point = { "BOTTOM", "TOP", 0, first }, first = first }
            elseif qt.side == "above" and bottom - first - pNeed >= 0 then
                pText = { shown = true, to = "prof", side = "below",
                          point = { "TOP", "BOTTOM", 0, -first }, first = first }
            elseif qt.side == "below" and bottom + size + first + pNeed <= sh then
                pText = { shown = true, to = "prof", side = "above",
                          point = { "BOTTOM", "TOP", 0, first }, first = first }
            end
        end
    else
        local clear = lp.look == "needle" and N.NeedleClearance(size) or nil
        pText = textOps(lp.shown and lp.text, "prof", lp.position, size, sw, sh, clear, pNeed, false)
    end
    local prof = {
        shown = (lp.shown and profMode ~= "off") and true or false,
        -- Bare (D2): there is a step and the needle is "off". No needle is
        -- drawn; its text still is, on the quest arrow or on its own frame.
        bare = (lp.shown and profMode == "off") and true or false,
        anchor = lp.anchor, point = point4(lp.position),
        scale = 1, alpha = pa, colour = { pr, pg, pb },
        look = lp.look, mode = profMode, behind = lp.behind and true or false, beside = false,
        above = over,
        text = pText,
    }
    return { quest = quest, prof = prof, stacked = L.stacked }
end
