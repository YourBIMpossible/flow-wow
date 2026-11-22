local _, ns = ...
-- Z-Flow arrow layout: where the quest arrow and the profession arrow stand
-- and how each one looks, as plain data. Pure Lua 5.1: no client calls. All
-- the game supplies arrives as arguments; a caller with frames applies the
-- result. Target sections 4 and 5.
ns.Nav = ns.Nav or {}
local N = ns.Nav

-- Exact values carried over from Flow.
N.ARROW_SIZE, N.ARROW_ART = 56, 64              -- button, art
N.NEEDLE_W, N.NEEDLE_H = 25.6, 109.1            -- the profession needle
N.ON_NEEDLE_SCALE, N.ON_NEEDLE_ALPHA = 0.8, 0.7 -- quest arrow while over the needle
N.PROF_HOLDER_ALPHA = 0.85                      -- the profession arrow, always
N.COLOR_NEAR, N.COLOR_FAR = 40, 600             -- yards: green at, orange at
N.STACK_SNAP = 40                               -- drop this close to restack
N.ARROW_GAP = 8
N.ARROW_DEFAULT_POINT = { "TOP", "TOP", 0, -120 }
N.CORPSE_RED = { 1, 0.2, 0.2 }
N.ARROW_KEYS = { "quest", "prof" }

local function rgb(hex)
    return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255,
             tonumber(hex:sub(5, 6), 16) / 255 }
end
-- Colour meanings: grey heading away, orange far through yellow to green
-- near, blue inside the area.
N.ARROW_PALETTE = {
    standard = { away = rgb("9EA0A8"), far = rgb("FF8C1A"), mid = rgb("FFD91A"),
                 near = rgb("33F24D"), here = rgb("4DA6FF") },
    colourBlind = { away = rgb("9EA0A8"), far = rgb("E69F00"), mid = rgb("F0E442"),
                    near = rgb("009E73"), here = rgb("56B4E9") },
}
-- The palettes a player can pick (G56), in order: { key, label }. The first
-- is the one in use until another is picked. Each key is a row of
-- N.ARROW_PALETTE with a colour for every meaning: picking one changes the
-- colours only, never what a colour means.
N.ARROW_PALETTES = { { "standard", "Standard" }, { "colourBlind", "Colour-blind" } }

-- The key of a saved palette word: the word when it is one of
-- N.ARROW_PALETTES, else the first.
function N.ArrowPaletteKey(v)
    for i = 1, #N.ARROW_PALETTES do
        if N.ARROW_PALETTES[i][1] == v then return v end
    end
    return N.ARROW_PALETTES[1][1]
end

-- The colours of a saved palette word: the N.ARROW_PALETTE row that
-- N.ArrowColor and N.ArrowPaint take.
function N.ArrowPaletteOf(v)
    return N.ARROW_PALETTE[N.ArrowPaletteKey(v)]
end

-- ---------------------------------------------------------------- helpers
local SPOT = {
    TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 },
    LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
    BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
}

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
end

-- A saved point that can be used, or nil. { anchor, relative anchor, x, y }.
local function goodPoint(p)
    if type(p) ~= "table" or type(p[1]) ~= "string" or not SPOT[p[1]] then return nil end
    local r = p[2]
    if r == nil then
        r = p[1]
    elseif type(r) ~= "string" or not SPOT[r] then
        return nil
    end
    local x, y = p[3], p[4]
    if x == nil then x = 0 end
    if y == nil then y = 0 end
    if not finite(x) or not finite(y) then return nil end
    return { p[1], r, x, y }
end

-- Left and bottom edge of a box standing at a point: size wide and height
-- tall (size-square when no height is given).
local function corner(point, size, screenW, screenH, height)
    local a, r = SPOT[point[1]], SPOT[point[2]]
    return r[1] * screenW + point[3] - a[1] * size, r[2] * screenH + point[4] - a[2] * (height or size)
end

-- Left and bottom edge of a box at a point, for the other Nav files.
N.ArrowCorner = corner

local function knownScreen(w, h)
    return finite(w) and finite(h) and w > 0 and h > 0
end

-- ------------------------------------------------------------------- gate
-- What the arrows may show at all: "off", "intro", "corpse" or "open".
function N.ArrowGate(enabled, revealShown, intro, hasPos, dead)
    if not enabled or not revealShown then return "off" end
    if intro then return "intro" end
    if not hasPos then return "off" end
    if dead then return "corpse" end
    return "open"
end

-- Dropped close enough to the other arrow to stack on it.
function N.StackSnap(dx, dy, snap)
    snap = snap or N.STACK_SNAP
    return dx * dx + dy * dy < snap * snap
end

-- A point moved back so the whole box is on the screen. A new table; the
-- same place when the screen size is unknown; nil for an unusable point.
-- The box is size-square unless a height is given (size is then its width).
function N.ClampPoint(point, size, screenW, screenH, height)
    local p = goodPoint(point)
    if not p then return nil end
    if not knownScreen(screenW, screenH) then return p end
    size = size or N.ARROW_SIZE
    height = finite(height) and height or size
    local left, bottom = corner(p, size, screenW, screenH, height)
    local cl = math.min(math.max(left, 0), math.max(screenW - size, 0))
    local cb = math.min(math.max(bottom, 0), math.max(screenH - height, 0))
    p[3], p[4] = p[3] + (cl - left), p[4] + (cb - bottom)
    return p
end

-- Where an arrow first stands on its own: directly below the leader, or
-- directly above it when there is no room below. Clamped to the screen.
function N.ArrowBeside(leaderPoint, size, screenW, screenH)
    if not knownScreen(screenW, screenH) then return nil end
    size = size or N.ARROW_SIZE
    local p = N.ClampPoint(leaderPoint, size, screenW, screenH)
    if not p then return nil end
    local left, bottom = corner(p, size, screenW, screenH)
    local step = size + N.ARROW_GAP
    local below = bottom - step
    if below < 0 then below = bottom + step end
    return N.ClampPoint({ "BOTTOMLEFT", "BOTTOMLEFT", left, below }, size, screenW, screenH)
end

-- ----------------------------------------------------------------- colour
-- p and pt are snapshots { cont, zone } of the player and the target.
function N.ArrowState(p, pt, here)
    if here then return "here" end
    if p and pt then
        if p.cont and pt.cont and p.cont ~= pt.cont then return "away" end
        if p.zone and pt.zone and p.zone ~= pt.zone then return "away" end
    end
    return "zone"
end

local function mix(a, b, t)
    return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t
end

-- The quest arrow's colour for a state and a distance in yards -> r, g, b.
-- state "corpse" is red whatever the distance.
function N.ArrowColor(state, d, palette)
    local th = palette or N.ARROW_PALETTE.standard
    if state == "corpse" then return N.CORPSE_RED[1], N.CORPSE_RED[2], N.CORPSE_RED[3] end
    if state == "away" then return th.away[1], th.away[2], th.away[3] end
    if state == "here" then return th.here[1], th.here[2], th.here[3] end
    if not finite(d) then d = N.COLOR_FAR end
    local near = 1 - math.min(1, math.max(0, (d - N.COLOR_NEAR) / (N.COLOR_FAR - N.COLOR_NEAR)))
    if near < 0.5 then return mix(th.far, th.mid, near * 2) end
    return mix(th.mid, th.near, near * 2 - 1)
end

-- The colour and opacity one arrow is drawn with -> r, g, b, a.
--   entry: one arrow from N.ArrowLayout. own: { r, g, b } used when the
--   entry's tint is "own" (the needle under the quest arrow).
-- A tint of "quest" means the quest arrow's colour meanings at the entry's
-- own (lower) opacity: never a colour of the activity.
function N.ArrowPaint(entry, state, d, palette, own)
    local a = entry and entry.alpha or 1
    if entry and entry.tint == "own" and own then return own[1], own[2], own[3], a end
    local r, g, b = N.ArrowColor(state, d, palette)
    return r, g, b, a
end

-- ------------------------------------------------------------ saved layout
-- Shape, under ZFlowDB.layout (arrow places are per account):
--   layout.arrows = {
--     mode   = "stacked" | "separate",        -- nil = stacked
--     points = { quest = { a, r, x, y }, prof = { a, r, x, y } },
--     hidden = { prof = true },               -- nil = shown
--     text   = { quest = false },             -- nil = shown
--   }
-- points.quest is the stack's place too. Anything missing, half-written or
-- unusable reads as its default; nothing here raises.
function N.ArrowSaved(layout)
    local a = type(layout) == "table" and layout.arrows
    if type(a) ~= "table" then a = {} end
    local out = { mode = (a.mode == "separate") and "separate" or "stacked",
                  points = {}, hidden = {}, text = {} }
    for _, key in ipairs(N.ARROW_KEYS) do
        if type(a.points) == "table" then out.points[key] = goodPoint(a.points[key]) end
        if type(a.hidden) == "table" and a.hidden[key] == true then out.hidden[key] = true end
        if type(a.text) == "table" and a.text[key] == false then out.text[key] = false end
    end
    return out
end

-- A copy of layout with its arrows replaced by saved, written sparsely
-- (defaults are left out), every other key of layout kept.
local function withArrows(layout, saved)
    local out = type(layout) == "table" and copy(layout) or {}
    local a = {}
    if saved.mode == "separate" then a.mode = "separate" end
    if next(saved.points) then a.points = copy(saved.points) end
    if next(saved.hidden) then a.hidden = copy(saved.hidden) end
    if next(saved.text) then a.text = copy(saved.text) end
    out.arrows = next(a) and a or nil
    return out
end

local function stackPointOf(saved, defaultPoint, size, sw, sh)
    return N.ClampPoint(saved.points.quest, size, sw, sh)
        or N.ClampPoint(defaultPoint, size, sw, sh)
        or N.ClampPoint(N.ARROW_DEFAULT_POINT, size, sw, sh)
end

-- ------------------------------------------------------------------ layout
-- state = {
--   layout  = the saved table (see above),
--   gate    = N.ArrowGate's answer,
--   quest   = { hasStep, overlay },   -- overlay: follow, waypoint
--   prof    = { hasStep, mode },      -- mode nil or "arrow": needle drawn
--   screenW, screenH, size, defaultPoint,
-- }
-- -> { quest = {...}, prof = {...}, stacked = bool }, each arrow:
--   shown, anchor ("screen" or "quest"), position { a, r, x, y } on the
--   screen, look ("pointer" or "needle"), behind, small, scale, alpha,
--   tint ("quest" or "own"), faint, emphasis, text. Map and path styling is
--   not decided here: it does not change when the arrows are separated.
function N.ArrowLayout(state)
    state = type(state) == "table" and state or {}
    local saved = N.ArrowSaved(state.layout)
    local size = finite(state.size) and state.size or N.ARROW_SIZE
    local sw, sh = state.screenW, state.screenH
    local gate = state.gate or "off"
    local q = type(state.quest) == "table" and state.quest or {}
    local p = type(state.prof) == "table" and state.prof or {}

    local stackPoint = stackPointOf(saved, state.defaultPoint, size, sw, sh)

    local questShown = gate == "intro" or gate == "corpse"
        or (gate == "open" and not saved.hidden.quest and (q.hasStep or q.overlay) and true)
        or false
    local profShown = (gate == "open" and not saved.hidden.prof and p.hasStep and true) or false

    local quest = {
        shown = questShown, anchor = "screen", position = stackPoint, look = "pointer",
        behind = false, small = false, scale = 1, alpha = 1,
        tint = "quest", faint = false, emphasis = "primary",
        text = saved.text.quest ~= false,
    }
    local prof = {
        shown = profShown, position = stackPoint, behind = false, small = false,
        scale = 1, alpha = N.PROF_HOLDER_ALPHA, faint = true, emphasis = "secondary",
        text = saved.text.prof ~= false,
    }

    local separate = saved.mode == "separate"
    if separate then
        -- On its own: still the needle, still faint, quest colour meanings.
        prof.anchor, prof.look, prof.tint = "screen", "needle", "quest"
        prof.position = N.ClampPoint(saved.points.prof, size, sw, sh)
            or N.ArrowBeside(stackPoint, size, sw, sh) or stackPoint
    elseif not questShown then
        -- Nothing to stand under: the profession step takes the stack's place.
        prof.anchor, prof.look, prof.tint = "screen", "pointer", "quest"
    else
        prof.anchor, prof.look, prof.tint = "quest", "needle", "own"
        prof.behind = true
        if profShown and (p.mode == nil or p.mode == "arrow") then
            quest.small, quest.scale, quest.alpha = true, N.ON_NEEDLE_SCALE, N.ON_NEEDLE_ALPHA
        end
    end
    return { quest = quest, prof = prof, stacked = not separate }
end

-- ------------------------------------------------------------------- apply
local function centre(point, size, sw, sh)
    local left, bottom = corner(point, size, sw, sh)
    return left + size / 2, bottom + size / 2
end

-- One user action on the saved layout -> a new layout table (the old one is
-- not touched). action = { op = ..., key = "quest" | "prof", ... }:
--   "reset"                  both arrows back to the default stack; text kept
--   "mode", mode             "separate" (first time: prof directly below the
--                            quest arrow) or "stacked" (places kept)
--   "restack"                the same as mode "stacked"
--   "move", key, point       quest: moves the stack / the quest arrow;
--                            prof: its own place, and separates it
--   "drop", key, point       as move, but an arrow let go within the snap of
--                            the other one stacks them again
--   "hide", key, on          "text", key, on
-- ctx = { screenW, screenH, size, snap, defaultPoint }
function N.ArrowApply(layout, action, ctx)
    ctx = type(ctx) == "table" and ctx or {}
    action = type(action) == "table" and action or {}
    local s = N.ArrowSaved(layout)
    local size = finite(ctx.size) and ctx.size or N.ARROW_SIZE
    local sw, sh = ctx.screenW, ctx.screenH
    local op, key = action.op, action.key
    local known = key == "quest" or key == "prof"

    local function move(point)
        local to = N.ClampPoint(point, size, sw, sh)
        if not to then return end
        s.points[key] = to
        if key == "prof" then s.mode = "separate" end
    end

    if op == "reset" then
        s.mode, s.points, s.hidden = "stacked", {}, {}
    elseif op == "restack" or (op == "mode" and action.mode ~= "separate") then
        s.mode = "stacked"
    elseif op == "mode" then
        s.mode = "separate"
        if not s.points.prof then
            s.points.prof = N.ArrowBeside(stackPointOf(s, ctx.defaultPoint, size, sw, sh), size, sw, sh)
        end
    elseif op == "move" and known then
        move(action.point)
    elseif op == "drop" and known then
        local to = N.ClampPoint(action.point, size, sw, sh)
        local other
        if key == "prof" then
            other = stackPointOf(s, ctx.defaultPoint, size, sw, sh)
        elseif s.mode == "separate" then
            other = N.ClampPoint(s.points.prof, size, sw, sh)
        end
        if to and other and knownScreen(sw, sh) then
            local ax, ay = centre(to, size, sw, sh)
            local bx, by = centre(other, size, sw, sh)
            if N.StackSnap(ax - bx, ay - by, ctx.snap) then
                -- Stacked again where the quest arrow stands; places kept.
                s.mode = "stacked"
                return withArrows(layout, s)
            end
        end
        move(action.point)
    elseif op == "hide" and known then
        s.hidden[key] = action.on and true or nil
    elseif op == "text" and known then
        if action.on == false then s.text[key] = false else s.text[key] = nil end
    end
    return withArrows(layout, s)
end
