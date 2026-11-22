-- The arrow styles. Pure: no client, no frames. "modern" is the arrow drawn
-- from its pictures (Nav/ArrowMotion.lua). "3d" and "flat" are the two older
-- looks, drawn from lines and dots: N.ArrowShapes answers what to draw this
-- frame and the client's arrow handle draws it (h.shapes).
--
-- Both older looks snap: no turning over time, no colour blend, no fade.
local _, ns = ...

local N = ns.Nav

-- In menu order: { key, label }.
N.ARROW_STYLES = { { "modern", "Modern" }, { "3d", "3D (pillars)" }, { "flat", "Flat lines" } }

local TWO_PI = 2 * math.pi
local RING_R, RING_DOTS = 27, 16
local FLAT = { { 0, 22 }, { -15, -14 }, { 0, -5 }, { 15, -14 } }
local SLAB = { { 0, 26 }, { -18, -16 }, { 0, -6 }, { 18, -16 } }
local TILT_SIN, TILT_COS = math.sin(math.rad(52)), math.cos(math.rad(52))
local DEPTH = 150
local SLICES, FILL, THICK = 5, 7, 1.4   -- slices of the slab, fills of its top, pixels between slices
local SKIP_TURN = 0.003                 -- radians: a smaller change is not redrawn (3D)
local POP, POP_SECS = 11, 0.5           -- the pillars' bounce on arriving
local WAVE_AMP, WAVE_SPEED, WAVE_CRESTS = 5, 5, 2

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- The style a saved value stands for: "3d", "flat", else "modern".
function N.ArrowStyle(v)
    if v == "3d" or v == "flat" then return v end
    return "modern"
end

function N.ArrowStyleLabel(key)
    key = N.ArrowStyle(key)
    for i = 1, #N.ARROW_STYLES do
        if N.ARROW_STYLES[i][1] == key then return N.ARROW_STYLES[i][2] end
    end
    return N.ARROW_STYLES[1][2]
end

-- The one-time move to the modern arrow. style: the saved style; seen: the
-- saved mark (true once this has run). Returns the style to use and whether
-- the mark is to be set now. A "3d" saved before the mark was the old
-- default, not a choice: it becomes "modern". "flat" was always a choice.
function N.ArrowStyleMigrate(style, seen)
    style = N.ArrowStyle(style)
    if seen == true then return style, false end
    if style == "3d" then style = "modern" end
    return style, true
end

-- A point on the ground (x right, z ahead), turned by angle (radians,
-- counter-clockwise) and seen from above at 52 degrees: screen x, y and the
-- scale at that depth (below 1 further away).
function N.Project3D(x, z, angle)
    local c, s = math.cos(angle), math.sin(angle)
    local gx, gz = x * c - z * s, x * s + z * c
    local k = DEPTH / (DEPTH + gz * TILT_SIN)
    return gx * k, gz * TILT_COS * k, k
end

-- Brightness of a slice of the 3D slab (0 = bottom): the top is the colour
-- itself, the sides below it darker.
function N.ArrowSliceShade(slice)
    if slice >= SLICES - 1 then return 1 end
    return 0.55 + 0.3 * slice / (SLICES - 1)
end

-- The shapes table of a motion: made once, refilled each frame.
local function begin(m)
    local s = m.shapes
    if not s then
        s = { lines = {}, nl = 0, dots = {}, nd = 0 }
        m.shapes = s
    end
    s.nl, s.nd = 0, 0
    return s
end

local function line(s, x1, y1, x2, y2, thick, r, g, b, a, layer, sub)
    local n = s.nl + 1
    s.nl = n
    local e = s.lines[n]
    if not e then
        e = {}
        s.lines[n] = e
    end
    e.x1, e.y1, e.x2, e.y2, e.thick = x1, y1, x2, y2, thick
    e.r, e.g, e.b, e.a, e.layer, e.sub = r, g, b, a, layer, sub or 0
end

local function dot(s, x, y, w, h, r, g, b, a, round, layer, sub, tex)
    local n = s.nd + 1
    s.nd = n
    local e = s.dots[n]
    if not e then
        e = {}
        s.dots[n] = e
    end
    e.x, e.y, e.w, e.h = x, y, w, h
    e.r, e.g, e.b, e.a = r, g, b, a
    e.round, e.layer, e.sub, e.tex = round and true or false, layer, sub or 0, tex
end

-- The four corners of the chevron being drawn; refilled each frame.
local xs, ys = {}, {}

-- The closed outline of xs, ys, shrunk by f about (cx, cy) and moved by
-- (dx, dy).
local function outline(s, cx, cy, f, dx, dy, thick, r, g, b, a, layer)
    for i = 1, 4 do
        local j = i % 4 + 1
        line(s, cx + (xs[i] - cx) * f + dx, cy + (ys[i] - cy) * f + dy,
            cx + (xs[j] - cx) * f + dx, cy + (ys[j] - cy) * f + dy, thick, r, g, b, a, layer, 0)
    end
end

local function icon(m)
    local v = m.icon
    if type(v) == "string" or type(v) == "number" then return v end
    return nil
end

local function flat(s, m, now)
    local col = m.colour
    local r, g, b = col[1], col[2], col[3]
    if m.arrived then
        -- The chevron is gone: the ring lights up in the colour and pulses,
        -- with a dot (or the step's icon) in the middle.
        local pulse = 0.6 + 0.4 * math.sin(now * 4)
        for i = 1, RING_DOTS do
            local t = (i - 1) / RING_DOTS * TWO_PI
            dot(s, RING_R * math.sin(t), RING_R * math.cos(t), 4, 4, r, g, b, pulse, false, "BACKGROUND", 0)
        end
        local tex = icon(m)
        if tex ~= nil then
            dot(s, 0, 0, 18, 18, 1, 1, 1, 1, false, "OVERLAY", 0, tex)
        else
            dot(s, 0, 0, 10, 10, r, g, b, 0.5 + 0.5 * pulse, true, "OVERLAY", 0)
        end
        return
    end
    local c, sn = math.cos(m.want), math.sin(m.want)
    for i = 1, 4 do
        local p = FLAT[i]
        xs[i], ys[i] = p[1] * c + p[2] * sn, p[2] * c - p[1] * sn
    end
    outline(s, 0, 0, 1, 0, 0, 7, r, g, b, 0.25, "BACKGROUND")
    outline(s, 0, 0, 1, 0, 0, 2.5, r, g, b, 1, "ARTWORK")
    line(s, xs[1], ys[1], xs[3], ys[3], 1, 1, 1, 1, 0.85, "OVERLAY", 0)
    for i = 1, RING_DOTS do
        local t = (i - 1) / RING_DOTS * TWO_PI
        dot(s, RING_R * math.sin(t), RING_R * math.cos(t), 2, 2, 1, 1, 1, 0.22, false, "BACKGROUND", 0)
    end
    -- The bright dot on the ring where the arrow points.
    dot(s, RING_R * sn, RING_R * c, 5, 5, r, g, b, 1, true, "OVERLAY", 0)
end

-- The pillars' height at `now`: 3.5 while pointing, 5 once arrived, a
-- bounce up over half a second on arriving, and a settle back on leaving.
local function height(m, arrived, now)
    local base = arrived and 5 or 3.5
    if not m.pillarStart then return base end
    local u = (now - m.pillarStart) / POP_SECS
    if u >= 1 or u < 0 then return base end
    if arrived then return base + POP * math.sin(math.pi * u) * (1 - u) end
    return base + ((m.pillarFrom or base) - base) * (1 - u)
end

local function pillars(m, now)
    local arrived = m.arrived and true or false
    if m.pillarArrived == nil then
        -- The first frame of this motion: no bounce.
        m.pillarArrived, m.pillarStart, m.pillarFrom = arrived, nil, nil
    elseif m.pillarArrived ~= arrived then
        m.pillarFrom = height(m, m.pillarArrived, now)
        m.pillarStart, m.pillarArrived = now, arrived
    end
    return height(m, arrived, now)
end

local function solid(s, m, now)
    local col = m.colour
    local r, g, b = col[1], col[2], col[3]
    local arrived = m.arrived and true or false

    -- A turn too small to see is not taken: the lines do not shimmer.
    local turn = m.drawn3d
    if turn == nil or math.abs((m.want - turn + math.pi) % TWO_PI - math.pi) >= SKIP_TURN then
        turn = m.want
        m.drawn3d = turn
    end

    if not arrived then
        local cx, cy = 0, 0
        for i = 1, 4 do
            local p = SLAB[i]
            local x, y = N.Project3D(p[1], p[2], -turn)
            xs[i], ys[i] = x, y
            cx, cy = cx + x / 4, cy + y / 4
        end
        -- The shadow on the ground: soft, down and to the right. It does
        -- not float with the slab.
        outline(s, cx, cy, 1, 3, -5, 7, 0, 0, 0, 0.22, "BACKGROUND")
        outline(s, cx, cy, 0.5, 3, -5, 7, 0, 0, 0, 0.22, "BACKGROUND")
        -- The slab, from the bottom up: the sides as outlines, a little
        -- darker; the top filled, in the colour exactly.
        local bob = math.floor(1.5 * math.sin(now * 2.4) * 4 + 0.5) / 4
        local lift = 4 + bob
        for sl = 0, SLICES - 1 do
            local top = sl == SLICES - 1
            local shade = N.ArrowSliceShade(sl)
            local dy = lift + sl * THICK
            for f = 1, top and FILL or 1 do
                outline(s, cx, cy, 1 - (f - 1) / FILL, 0, dy, top and 2.6 or 2.5,
                    r * shade, g * shade, b * shade, 1, top and "ARTWORK" or "BORDER")
            end
        end
        -- A faint ridge along the middle of the top.
        local dy = lift + (SLICES - 1) * THICK
        line(s, xs[1], ys[1] + dy, xs[3], ys[3] + dy, 1.2, 1, 1, 1, 0.3, "OVERLAY", 0)
    end

    -- The ring lies on the ground; its pillars stand up from it. Those at
    -- the back are behind the slab, those near you in front of it.
    local pulse = 0.5 + 0.5 * math.sin(now * 4)
    local hgt = pillars(m, now)
    local wave = arrived and m.wave
    for i = 1, RING_DOTS do
        local t = (i - 1) / RING_DOTS * TWO_PI
        local x, y, k = N.Project3D(RING_R * math.sin(t), RING_R * math.cos(t), 0)
        local h = hgt
        if wave then
            h = h + WAVE_AMP * (0.5 + 0.5 * math.sin(now * WAVE_SPEED - (i - 1) / RING_DOTS * WAVE_CRESTS * TWO_PI))
        end
        h = h * k
        local layer = math.cos(t) < 0 and "ARTWORK" or "BACKGROUND"
        if arrived then
            local depth = 0.55 + 0.45 * math.min(1, math.max(0, (k - 0.85) * 3))
            line(s, x, y, x, y + h, 2, r * depth, g * depth, b * depth, 0.55 + 0.4 * pulse,
                layer, layer == "ARTWORK" and 7 or 0)
            dot(s, x, y + h, 4, 3, math.min(1, r + 0.45), math.min(1, g + 0.45), math.min(1, b + 0.45),
                0.7 + 0.3 * pulse, true, layer, 7)
        else
            line(s, x, y, x, y + h, 2, 1, 1, 1, 0.22, layer, layer == "ARTWORK" and 7 or 0)
            dot(s, x, y + h, 3, 2, 1, 1, 1, 0.35, true, layer, 7)
        end
    end

    if not arrived then return end
    local tex = icon(m)
    if tex ~= nil then
        -- The step's icon on a dark disc, hopping over its shadow.
        local hop = math.abs(math.sin(now * 3.2)) * 5
        dot(s, 0, -1, 15 - hop, math.max(2, 4 - hop * 0.3), 0, 0, 0, 0.45, true, "BACKGROUND", 2)
        dot(s, 0, 9 + hop, 22, 22, r * 0.35, g * 0.35, b * 0.35, 1, true, "OVERLAY", 1)
        dot(s, 0, 9 + hop, 18, 18, 1, 1, 1, 1, false, "OVERLAY", 4, tex)
        return
    end
    -- The ball: a dark base, a lit body and a highlight up and to the left,
    -- floating over its shadow.
    local lift = 7 + 1.5 * math.sin(now * 2.4)
    dot(s, 0, -1, 13, 4, 0, 0, 0, 0.45, true, "BACKGROUND", 2)
    dot(s, 0, lift, 12, 12, r * 0.35, g * 0.35, b * 0.35, 1, true, "OVERLAY", 1)
    dot(s, -0.8, lift + 0.8, 9, 9, math.min(1, r * 0.9 + 0.1), math.min(1, g * 0.9 + 0.1),
        math.min(1, b * 0.9 + 0.1), 1, true, "OVERLAY", 2)
    dot(s, -2.4, lift + 2.6, 3, 3, 1, 1, 1, 0.85, true, "OVERLAY", 3)
end

-- What the arrow of motion m is drawn from this frame in `style`, at clock
-- `now` (seconds): nil for the modern arrow (it is drawn from pictures),
-- else the motion's own table, refilled on the next call:
--   { lines = { { x1, y1, x2, y2, thick, r, g, b, a, layer, sub } ... }, nl,
--     dots  = { { x, y, w, h, r, g, b, a, round, layer, sub, tex } ... }, nd }
-- by field name; only the first nl lines and nd dots count. Points are in
-- pixels from the arrow's centre, y up. A dot is a filled square, a disc
-- (round), or the picture tex.
-- The motion is left where the modern arrow can take over from it: turned
-- to where it should point, in its colour, its fade at its end.
function N.ArrowShapes(style, m, _, now)
    style = N.ArrowStyle(style)
    if style == "modern" then return nil end
    now = finite(now) and now or 0
    local s = begin(m)
    if style == "flat" then flat(s, m, now) else solid(s, m, now) end
    m.at = m.want
    m.fade = m.arrived and 1 or 0
    m.shown[1], m.shown[2], m.shown[3] = m.colour[1], m.colour[2], m.colour[3]
    return s
end
