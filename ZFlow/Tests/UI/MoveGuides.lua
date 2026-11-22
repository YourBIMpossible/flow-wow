-- S29 alignment guides, the pure core (UI/MoveGuides.lua; ported from legacy
-- Flow's Modules/MoveGuides.lua). Hand-made rectangles only.
local _, ns = ...

local G = ns.MoveGuides
local tests = {}

local SCREEN = { w = 1000, h = 600 }

tests["guides: a rectangle's three places each way"] = function(t)
    local xs, ys = G.Marks({ l = 10, r = 30, b = 100, t = 140 })
    t.eq(xs, { 10, 20, 30 })
    t.eq(ys, { 100, 120, 140 })
end

tests["guides: the nearest line-up within the snap, and none beyond it"] = function(t)
    local move, at = G.Nearest({ 10, 20, 30 }, { 500, 25 }, 8)
    t.eq({ move, at }, { 5, 25 }, "the middle is 5 short of 25; the right edge, as near, comes later and does not win")
    t.eq(G.Nearest({ 10, 20, 30 }, { 500 }, 8), nil)
    local m2, _, src = G.Nearest({ 10 }, { { v = 12, src = "arrow" } }, 8)
    t.eq({ m2, src }, { 2, "arrow" })
end

tests["guides: the middle of the screen pulls both ways"] = function(t)
    local s = G.Snap({ l = 480, r = 516, b = 290, t = 306 }, SCREEN, {})
    t.eq({ s.dx, s.x }, { 2, 500 }, "its middle (498) settles on 500")
    t.eq({ s.dy, s.y }, { 2, 300 })
    t.eq(s.xSrc, nil, "the screen's middle has no source")
end

tests["guides: another thing's edges and middle; a middle-only thing offers its middle"] = function(t)
    local other = { l = 100, r = 200, b = 50, t = 80 }
    local s = G.Snap({ l = 203, r = 243, b = 400, t = 420 }, SCREEN, { other })
    t.eq({ s.dx, s.x }, { -3, 200 }, "left edge onto the other's right edge")
    t.ok(s.xSrc == other)
    local mid = { l = 100, r = 200, b = 50, t = 80, middle = true }
    s = G.Snap({ l = 203, r = 243, b = 400, t = 420 }, SCREEN, { mid })
    t.eq(s.dx, 0, "its edges are not offered")
end

tests["guides: nothing near moves nothing"] = function(t)
    local s = G.Snap({ l = 10, r = 40, b = 10, t = 30 }, SCREEN, {})
    t.eq({ s.dx, s.dy, s.x, s.y }, { 0, 0, nil, nil })
end

tests["guides: a rectangle or screen that is not read is left out, never guessed"] = function(t)
    t.eq(G.Snap({ l = 1, r = "2", b = 3, t = 4 }, SCREEN, {}), nil)
    local nan = 0 / 0
    local s = G.Snap({ l = 480, r = 516, b = 290, t = 306 }, { w = nan, h = 600 }, { { l = nan, r = 1, b = 1, t = 1 } })
    t.eq(s.dx, 0, "no screen middle to line up with")
end

tests["guides: a line to another thing runs past both ends"] = function(t)
    t.eq({ G.Span(100, 140, 200, 260, 14) }, { 86, 274 })
    t.eq({ G.Span(100, 140, 200, 260) }, { 100 - G.REACH, 260 + G.REACH })
end

tests["guides: only other things on the screen, never the one moved or one docked to it"] = function(t)
    local rects = {
        arrow = { l = 1, r = 2, b = 3, t = 4, middle = true },
        icon = { l = 5, r = 6, b = 7, t = 8 },
        needle = { l = 9, r = 10, b = 11, t = 12, dockedTo = "arrow" },
        hidden = { l = 1, r = "x", b = 1, t = 1 },
    }
    local out = G.Visible(rects, "arrow")
    t.eq(#out, 1)
    t.eq(out[1].name, "icon")
    out = G.Visible(rects, "icon")
    t.eq({ out[1].name, out[2].name }, { "arrow", "needle" })
    t.eq(out[1].middle, true)
end

return tests
