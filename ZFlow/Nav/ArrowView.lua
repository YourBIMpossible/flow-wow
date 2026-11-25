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
N.AREA_YARDS = 45               -- yards: in an area step's area (A1-09, Flow AREA)
N.PROF_RING_ALPHA = 0.35        -- the faint ring at the profession step
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
-- gives mainAtPoint false: the profession arrow has its own place behind
-- the quest arrow, so it stays at a quest stop.
function N.ProfArrowMode(mainAtPoint, profHere, canPoint)
    if profHere then return "ring" end
    if mainAtPoint or not canPoint then return "off" end
    return "arrow"
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

-- The echo stands straight below the quest arrow (true) or tucked under it
-- (false). spread: radians between the two bearings, nil = unknown, which
-- reads as apart. was: the answer of the update before (nil = none): the
-- edge moves by N.ECHO_BAND towards the other side, so an echo at the edge
-- does not flicker.
function N.EchoSlid(spread, was)
    if not finite(spread) then return true end
    local edge = N.ECHO_SPREAD
    if was == true then edge = edge - N.ECHO_BAND elseif was == false then edge = edge + N.ECHO_BAND end
    return math.abs(spread) > edge
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
--   spread,                  -- radians between the two steps' bearings, nil = unknown
--   echoSlid,                -- prof.slid of the update before, nil = none
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
--   scale, alpha, colour { r, g, b }, look ("pointer" or "echo"),
--   mode ("arrow", "ring", "off", "corpse", "intro"), behind, beside,
--   text { shown, to, side, point, first }; prof.slid: the echo stands
--   straight below the quest arrow.
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
    -- The first gap of each text with the echo: the quest text over the
    -- quest arrow, the profession text under the echo.
    local aboveFirst = N.TEXT_GAP_ABOVE
    if q.travel then aboveFirst = math.max(aboveFirst, (N.TRAVEL_ICON - size) / 2 + 4) end
    local belowFirst = N.TEXT_GAP_BELOW
    -- Lead section 447 item 5 (F3): the profession arrow keeps its place
    -- while its step has a place to point at, even when the game gives no
    -- facing yet (at load, or for a moment after). A step in words only (no
    -- place) has no arrow and no room (D2).
    local slot = profMode ~= "off" or (p.bearingKnown and true or false)

    local L = N.ArrowLayout({
        layout = state.layout, gate = gate, screenW = sw, screenH = sh,
        size = state.size, defaultPoint = state.defaultPoint,
        slid = N.EchoSlid(state.spread, state.echoSlid),
        quest = { hasStep = q.hasStep, overlay = q.overlay,
                  room = saved.text.quest ~= false and qNeed > 0 and qNeed + aboveFirst or 0 },
        prof = { hasStep = profStep, mode = slot and "arrow" or "off",
                 room = saved.text.prof ~= false and pNeed > 0 and pNeed + belowFirst or 0 },
    })
    local lq, lp = L.quest, L.prof
    -- The two together: the echo behind the quest arrow.
    local echo = (lp.shown and lp.echo and lq.shown) and true or false

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
    -- The quest arrow keeps its size and strength with the echo behind it;
    -- only the travel icon makes it smaller.
    local scale, alpha = 1, 1
    if travel then scale = N.TRAVEL_ARROW_SCALE end
    local qState = qMode == "corpse" and "corpse" or N.ArrowState(state.player, q.target, questHere)
    -- R7 (lead section 564): a waypoint or profession step takes RC.Of's
    -- colour, as the map lines do; a route step keeps N.ArrowColor with the
    -- palette row (RC.Of's distance colour is the same sum, and the row keeps
    -- the one-colour choice).
    local qr, qg, qb
    local RC = ns.RouteColor
    local qFamily = q.family
    if RC and RC.FAMILIES[qFamily] and qState ~= "corpse" then
        qr, qg, qb = RC.Of({ family = qFamily, state = qState }, q.distance, N.ArrowPaletteWord(state.palette))
    else
        qr, qg, qb = N.ArrowColor(qState, q.distance, state.palette)
    end
    local quest = {
        shown = lq.shown, anchor = "screen", point = point4(lq.position),
        scale = scale, alpha = alpha, colour = { qr, qg, qb },
        look = "pointer", mode = qMode, behind = false, beside = travel,
        text = textOps(lq.shown and lq.text, "quest", lq.position, size, sw, sh,
                       nil, qNeed, travel),
    }
    if echo then
        -- Its text above it, always: the echo and its text are below.
        quest.text = { shown = (lq.shown and lq.text) and true or false, to = "quest", side = "above",
                       point = { "BOTTOM", "TOP", 0, aboveFirst }, first = aboveFirst }
    end

    -- ----------------------------------------------------- profession arrow
    local pState = N.ArrowState(state.player, p.target, profHere)
    local pr, pg, pb, pa = N.ArrowPaint(lp, pState, p.distance, state.palette, p.own)
    if profMode == "ring" then pa = N.PROF_RING_ALPHA end
    local pText
    if echo then
        -- Its text under it, always: the other side from the quest text.
        -- With no echo drawn its frame stands on the quest arrow's place,
        -- so the lines stand right under the quest arrow.
        pText = { shown = lp.text and true or false, to = "prof", side = "below",
                  point = { "TOP", "BOTTOM", 0, -belowFirst }, first = belowFirst }
    else
        pText = textOps(lp.shown and lp.text, "prof", lp.position, size, sw, sh, nil, pNeed, false)
    end
    local prof = {
        shown = (lp.shown and profMode ~= "off") and true or false,
        -- Bare (D2): there is a step and the arrow is "off". No echo is
        -- drawn; its text still is, on the quest arrow or on its own frame.
        bare = (lp.shown and profMode == "off") and true or false,
        anchor = lp.anchor, point = point4(lp.position),
        scale = 1, alpha = pa, colour = { pr, pg, pb },
        look = lp.look, mode = profMode, behind = lp.behind and true or false, beside = false,
        slid = (lp.slid and lp.shown) and true or false,
        text = pText,
    }
    return { quest = quest, prof = prof, stacked = L.stacked }
end
