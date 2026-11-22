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

tests["guides: where the lines go, to another thing past both, to the middle across the screen"] = function(t)
    local other = { l = 100, r = 156, b = 50, t = 106, middle = true }
    local s = G.Snap({ l = 125, r = 165, b = 400, t = 440 }, SCREEN, { other })
    t.eq({ G.Lines(s, SCREEN) }, { 128, 36, 454 }, "up at the other's middle, past both; nothing across")
    s = G.Snap({ l = 480, r = 516, b = 290, t = 306 }, SCREEN, {})
    t.eq({ G.Lines(s, SCREEN) }, { 500, 0, 600, 300, 0, 1000 })
    t.eq(G.Lines(nil, SCREEN), nil)
end

local ICON, QUEST, PROF = ns.id.framePrefix .. "RotationIcon", ns.id.framePrefix .. "QuestArrow", ns.id.framePrefix .. "ProfArrow"

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setScreen(1000, 600)
    if not opts.noIcon then c.setFrameRect(ICON, { l = 700, r = 748, b = 100, t = 148 }) end
    c.setFrameRect(QUEST, { l = 100, r = 156, b = 50, t = 106 })
    c.setFrameRect(PROF, opts.prof)
    local k = ns.Kernel({}, c)
    local api = G.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api
end

local function last(c) return c.guideShows()[#c.guideShows()] end

tests["guides module: the icon and the arrows are watched once there"] = function(t)
    local _, c, api = start({ prof = { l = 900, r = 956, b = 500, t = 556 } })
    t.eq(api.watched(), { [ICON] = true, [QUEST] = true, [PROF] = true })
    t.ok(c.watched(ICON))
end

tests["guides module: a line while it moves near the middle, and it settles there at the release"] = function(t)
    local _, c = start()
    c.moveFrame(ICON, { l = 480, r = 516, b = 290, t = 306 })
    local s = last(c)
    t.eq({ s[1], s[2], s[3], s[4], s[5], s[6] }, { 500, 0, 600, 300, 0, 1000 })
    t.eq(c.guidesUp(), true)
    t.eq({ c.dropFrame(ICON, { l = 480, r = 516, b = 290, t = 306 }) }, { 2, 2 })
    t.eq(c.guidesUp(), false, "the lines go at the release")
end

tests["guides module: an arrow offers only its middle"] = function(t)
    local _, c = start()
    c.moveFrame(ICON, { l = 125, r = 165, b = 400, t = 440 })
    local s = last(c)
    t.eq({ s[1], s[2], s[3], s[4] }, { 128, 36, 454, nil })
    t.eq({ c.dropFrame(ICON, { l = 125, r = 165, b = 400, t = 440 }) }, { 3, 0 })
    t.eq({ c.dropFrame(ICON, { l = 97, r = 111, b = 400, t = 440 }) }, { 0, 0 }, "its edge (100) is not offered")
end

tests["guides module: nothing near, no line and no move"] = function(t)
    local _, c = start()
    local before = #c.guideShows()
    c.moveFrame(ICON, { l = 10, r = 40, b = 400, t = 430 })
    t.eq(#c.guideShows(), before)
    t.eq({ c.dropFrame(ICON, { l = 10, r = 40, b = 400, t = 430 }) }, { 0, 0 })
end

tests["guides module: never the arrow docked to the one moved"] = function(t)
    local _, c = start({ prof = { l = 300, r = 356, b = 200, t = 256, dockedTo = QUEST } })
    t.eq({ c.dropFrame(QUEST, { l = 303, r = 359, b = 500, t = 556 }) }, { 0, 0 })
    c.setFrameRect(QUEST, { l = 303, r = 359, b = 500, t = 556 })
    t.eq({ c.dropFrame(PROF, { l = 300, r = 356, b = 200, t = 256 }) }, { 0, 0 }, "nor the one it hangs from")
end

tests["guides module: switched off, no lines and no snap"] = function(t)
    local k, c = start()
    t.eq(k.settings:set(G.SETTING, false), true)
    local before = #c.guideShows()
    c.moveFrame(ICON, { l = 480, r = 516, b = 290, t = 306 })
    t.eq(#c.guideShows(), before)
    t.eq(c.guidesUp(), false)
    t.eq({ c.dropFrame(ICON, { l = 480, r = 516, b = 290, t = 306 }) }, { 0, 0 })
end

tests["guides module: a frame made later is watched when it appears"] = function(t)
    local _, c, api = start({ noIcon = true })
    t.eq(api.watched()[ICON], nil)
    c.setFrameRect(ICON, { l = 700, r = 748, b = 100, t = 148 })
    c.advance(G.RETRY)
    t.eq(api.watched()[ICON], true)
end

return tests
