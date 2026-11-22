local _, ns = ...

-- Alignment guides while the player moves Z-Flow's things on the screen
-- (S29): the middle of the screen both ways, and the edges and middle of the
-- other things that are on the screen. Closer than SNAP pixels lines up; at
-- the release the thing settles exactly on the line.
--
-- This file is the pure core, ported from legacy Flow's Modules/MoveGuides.lua
-- (0.35.327 and 0.35.330), which ran on this client: the same marks, the
-- same nearest rule, the same snap and line reach. Research:
-- WoW/from-plexy/RESEARCH-move-guides.md. Drawing the lines and taking the
-- rectangles during a drag need the arrow's and the rotation icon's client
-- handles to say where they are while they move; that wiring is proposed to
-- the lead in the note, not done here.
--
--   MoveGuides.Marks(rect) -> xs { l, c, r }, ys { b, c, t }
--   MoveGuides.Nearest(mine, theirs, snap) -> move, at, src   (nil: none near)
--   MoveGuides.Snap(rect, screen, others, snap) -> { dx, dy, x, y, xSrc, ySrc, rect }
--   MoveGuides.Span(lo1, hi1, lo2, hi2, reach) -> from, to
--   MoveGuides.Visible(rects, moving) -> others: the rectangles to line up with
--
--   rect    { l, r, b, t } in the screen's own units; `middle = true` offers
--           only its middle (a frame whose box the player cannot see)
--   screen  { w, h }
-- A rectangle with any side that is not a plain number is left out, never
-- guessed.
local G = {}
ns.MoveGuides = G

G.SNAP = 8      -- pixels: closer than this lines up
G.REACH = 14    -- how far a line to another thing runs past the two

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function usable(r)
    return type(r) == "table" and finite(r.l) and finite(r.r) and finite(r.b) and finite(r.t)
end

function G.Marks(r)
    return { r.l, (r.l + r.r) / 2, r.r }, { r.b, (r.b + r.t) / 2, r.t }
end

function G.Nearest(mine, theirs, snap)
    snap = finite(snap) and snap or G.SNAP
    local best, bestAt, bestSrc
    for _, m in ipairs(mine or {}) do
        for _, at in ipairs(theirs or {}) do
            local v = type(at) == "table" and at.v or at
            if finite(v) and finite(m) then
                local d = v - m
                if math.abs(d) <= snap and (not best or math.abs(d) < math.abs(best)) then
                    best, bestAt, bestSrc = d, v, type(at) == "table" and at.src or nil
                end
            end
        end
    end
    return best, bestAt, bestSrc
end

function G.Snap(rect, screen, others, snap)
    if not usable(rect) then return nil end
    local xs, ys = {}, {}
    if type(screen) == "table" and finite(screen.w) and finite(screen.h) then
        xs[1], ys[1] = screen.w / 2, screen.h / 2
    end
    for _, o in ipairs(type(others) == "table" and others or {}) do
        if usable(o) then
            local ox, oy = G.Marks(o)
            for i = 1, 3 do
                if not o.middle or i == 2 then
                    xs[#xs + 1] = { v = ox[i], src = o }
                    ys[#ys + 1] = { v = oy[i], src = o }
                end
            end
        end
    end
    local mx, my = G.Marks(rect)
    local dx, x, xSrc = G.Nearest(mx, xs, snap)
    local dy, y, ySrc = G.Nearest(my, ys, snap)
    return { dx = dx or 0, dy = dy or 0, x = x, y = y, xSrc = xSrc, ySrc = ySrc, rect = rect }
end

function G.Span(lo1, hi1, lo2, hi2, reach)
    reach = finite(reach) and reach or G.REACH
    return math.min(lo1, lo2) - reach, math.max(hi1, hi2) + reach
end

-- What the moving thing may line up with: every other rectangle handed in
-- that is usable, by name. Legacy Flow's 0.35.330 lesson: only what is on
-- the screen, never the thing being moved, and never something docked to it
-- (rect.dockedTo == moving).
--   rects   { [name] = rect }   moving   the name of the thing being moved
function G.Visible(rects, moving)
    local names = {}
    for name in pairs(type(rects) == "table" and rects or {}) do
        if type(name) == "string" then names[#names + 1] = name end
    end
    table.sort(names)
    local out = {}
    for _, name in ipairs(names) do
        local r = rects[name]
        if name ~= moving and usable(r) and r.dockedTo ~= moving then
            out[#out + 1] = { l = r.l, r = r.r, b = r.b, t = r.t, middle = r.middle == true, name = name }
        end
    end
    return out
end
