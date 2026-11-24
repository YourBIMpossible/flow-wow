local _, ns = ...

-- P-COACH L5 offline acceptance (DISPATCH 382-384): the profession arrow
-- stacked behind the quest arrow, separated (directly below on the first
-- separation), and restacked, with the profession lane fed by a C4 step.
-- Function only: the look is not seen offline.

local N = ns.Nav
local tests = {}

local CTX = { screenW = 1920, screenH = 1080, size = 56 }

local function fed()
    local steps = ns.ProfRecipes.Steps({ name = "Stylish Blue Shirt", profession = "Tailoring" }, {})
    return #steps > 0
end

local function layoutOf(saved)
    return N.ArrowLayout({ layout = saved, gate = "open", quest = { hasStep = true },
        prof = { hasStep = fed() }, screenW = 1920, screenH = 1080, size = 56 })
end

tests["prof arrow L5: the profession lane is fed and stands behind the quest arrow"] = function(t)
    t.eq(fed(), true, "the C4 lane gives a step")
    local l = layoutOf({})
    t.eq(l.stacked, true, "stacked by default")
    t.eq(l.prof.shown, true, "the profession arrow is shown")
    t.eq(l.prof.behind, true, "behind the quest arrow")
    t.eq(l.prof.anchor, "quest", "on the quest arrow")
    t.eq(l.prof.alpha, N.PROF_HOLDER_ALPHA, "translucent")
    t.eq(l.quest.alpha < 1, true, "the solid arrow eases over the needle")
end

tests["prof arrow L5: the first separation puts the profession arrow directly below"] = function(t)
    local saved = N.ArrowApply({}, { op = "mode", mode = "separate" }, CTX)
    local l = layoutOf(saved)
    t.eq(l.stacked, false, "separated")
    t.eq(l.prof.shown, true, "still shown")
    t.eq(l.prof.anchor, "screen", "on its own")
    local q, p = l.quest.position, l.prof.position
    local qx, px = N.ClampPoint(q, 56, 1920, 1080), N.ClampPoint(p, 56, 1920, 1080)
    t.ok(type(qx) == "table" and type(px) == "table", "both have a place")
    t.eq(p[1], "BOTTOMLEFT", "placed by corner")
    -- The quest arrow stands at TOP 0,-120: left 932, bottom 904.
    t.eq(p[3], 932, "same left edge: directly below")
    t.eq(p[4], 904 - 56 - N.ARROW_GAP, "one arrow and a gap lower")
end

tests["prof arrow L5: restacked, it stands behind again; a second separation keeps its place"] = function(t)
    local saved = N.ArrowApply({}, { op = "mode", mode = "separate" }, CTX)
    saved = N.ArrowApply(saved, { op = "move", key = "prof", point = { "BOTTOMLEFT", "BOTTOMLEFT", 100, 100 } }, CTX)
    saved = N.ArrowApply(saved, { op = "restack" }, CTX)
    local l = layoutOf(saved)
    t.eq(l.stacked, true, "restacked")
    t.eq(l.prof.behind, true, "behind again")
    t.eq(l.prof.shown, true, "and still fed")
    saved = N.ArrowApply(saved, { op = "mode", mode = "separate" }, CTX)
    t.eq(layoutOf(saved).prof.position[3], 100, "its own place is kept")
end

tests["prof arrow L5: dropped onto the quest arrow, it restacks"] = function(t)
    local saved = N.ArrowApply({}, { op = "mode", mode = "separate" }, CTX)
    saved = N.ArrowApply(saved, { op = "drop", key = "prof", point = { "TOP", "TOP", 4, -122 } }, CTX)
    t.eq(layoutOf(saved).stacked, true, "stacked by the drop")
end

return tests
