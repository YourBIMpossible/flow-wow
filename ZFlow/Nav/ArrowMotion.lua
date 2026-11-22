-- Arrow motion: how a drawn arrow follows what it should show. Pure: no
-- client, no frames. UI/Arrow.lua keeps one motion per arrow, tells it each
-- frame where to point, what colour to be and whether the step is reached,
-- and hands the draw table it gets back to the client's arrow handle.
--
-- The look is the one the Flow arrow had: 128 turns of the body drawn in a
-- 16 x 8 sheet, turned the shortest way round, colour blended over about a
-- second, a quarter-second fade from the pointer to the arrived ring, the
-- body floating over its shadow.
local _, ns = ...

local N = ns.Nav

N.TURNS, N.ART_COLS, N.ART_ROWS = 128, 16, 8
N.TURN_RATE = 14       -- per second: how fast the drawn turn closes on the wanted one
N.COLOUR_RATE = 3      -- per second: the colour blend
N.FADE_RATE = 4        -- per second: pointer <-> arrived ring
N.MOTION_STEP = 0.1    -- seconds: a longer frame is taken as this long
N.HALO_W, N.HALO_H, N.HALO_Y = 58, 42, -4
N.ARROW_START_COLOUR = { 1, 0.62, 0 }

local TWO_PI = 2 * math.pi

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- The sheet cell for a turn of `angle` radians:
-- index (0..127), left, right, top, bottom.
function N.ArrowCell(angle)
    if not finite(angle) then angle = 0 end
    local i = math.floor(((angle % TWO_PI) / TWO_PI) * N.TURNS + 0.5) % N.TURNS
    local col, row = i % N.ART_COLS, math.floor(i / N.ART_COLS)
    return i, col / N.ART_COLS, (col + 1) / N.ART_COLS, row / N.ART_ROWS, (row + 1) / N.ART_ROWS
end

-- Tex coords of the beam: upward, or mirrored below the ring. The last
-- texel row is left out so the faded tip does not wrap round.
function N.BeamCoords(down)
    local edge = 1 - 1.5 / 128
    if down then return 0, 1, edge, 0 end
    return 0, 1, 0, edge
end

-- One frame of turning from `at` towards `want`, the shortest way round.
function N.TurnToward(at, want, dt)
    if not finite(at) then at = 0 end
    if not finite(want) then return at end
    local diff = (want - at + math.pi) % TWO_PI - math.pi
    if math.abs(diff) <= 0.001 then return want end
    return at + diff * (1 - math.exp(-dt * N.TURN_RATE))
end

-- A new motion, pointing north in the start colour, not arrived.
function N.ArrowMotion()
    local c = N.ARROW_START_COLOUR
    return { want = 0, at = 0, colour = { c[1], c[2], c[3] }, shown = { c[1], c[2], c[3] },
             arrived = false, fade = 0, wave = false }
end

-- What the arrow should show: turn (radians, clockwise on screen from up;
-- nil keeps the last), colour { r, g, b } (nil keeps it), arrived, wave
-- (right on the spot: faster, brighter ripples), snap (jump there now).
function N.ArrowAim(m, aim)
    aim = type(aim) == "table" and aim or {}
    if finite(aim.turn) then m.want = aim.turn end
    local c = aim.colour
    if type(c) == "table" and finite(c[1]) and finite(c[2]) and finite(c[3]) then
        m.colour = { c[1], c[2], c[3] }
    end
    m.arrived = aim.arrived and true or false
    m.wave = (aim.wave and m.arrived) and true or false
    if aim.snap then
        m.at = m.want
        m.shown = { m.colour[1], m.colour[2], m.colour[3] }
        m.fade = m.arrived and 1 or 0
    end
    return m
end

-- One drawn frame: moves m on by dt seconds (clock `now`, seconds) and
-- returns what to draw:
--   { turn, cell = { l, r, t, b }, colour = { r, g, b },
--     body, shine, shadow, pool  (alphas), bodyY (the float),
--     arrived (ring, ripple and beams shown), halo (alpha),
--     ripple = { w, h, alpha }, beam = { w, h, alpha } }
function N.ArrowStep(m, dt, now)
    dt = finite(dt) and math.max(0, math.min(dt, N.MOTION_STEP)) or 0
    now = finite(now) and now or 0
    m.at = N.TurnToward(m.at, m.want, dt)

    local k = 1 - math.exp(-dt * N.COLOUR_RATE)
    local s, c = m.shown, m.colour
    if math.abs(c[1] - s[1]) + math.abs(c[2] - s[2]) + math.abs(c[3] - s[3]) > 0.004 then
        s[1], s[2], s[3] = s[1] + (c[1] - s[1]) * k, s[2] + (c[2] - s[2]) * k, s[3] + (c[3] - s[3]) * k
    else
        s[1], s[2], s[3] = c[1], c[2], c[3]
    end

    local want = m.arrived and 1 or 0
    if m.fade ~= want then
        local step = dt * N.FADE_RATE
        m.fade = (want > m.fade) and math.min(want, m.fade + step) or math.max(want, m.fade - step)
    end

    local on, f = 1 - m.fade, m.fade
    local _, l, r, t, b = N.ArrowCell(m.at)
    local pulse = 0.5 + 0.5 * math.sin(now * 4)
    local u = (now * (m.wave and 1.4 or 0.7)) % 1
    local beamW, beamH = 18 + 4 * pulse, 50 + 8 * pulse
    return {
        turn = m.at, cell = { l, r, t, b }, colour = { s[1], s[2], s[3] },
        body = on, shine = on * 0.9, shadow = on * 0.75, pool = 0.35 * on,
        bodyY = (f < 1) and 1.5 * math.sin(now * 2.4) or 0,
        arrived = f > 0.01,
        halo = f * (0.6 + 0.4 * pulse),
        ripple = { N.HALO_W * (0.55 + 0.75 * u), N.HALO_H * (0.55 + 0.75 * u),
                   f * (1 - u) * (m.wave and 0.9 or 0.6) },
        beam = { beamW, beamH, f * (0.45 + 0.25 * pulse) },
    }
end
