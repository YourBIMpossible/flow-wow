local _, ns = ...

-- P-COACH L5 offline acceptance (DISPATCH 382-384): the profession arrow
-- stacked with the quest arrow, separated (directly below on the first
-- separation), and restacked, with the profession lane fed by a C4 step.
-- Function only: the look is not seen offline.
--
-- Stacked means one over the other, not one behind the other (DISPATCH 407
-- item 2). These rows were written for the first stack, where the
-- profession needle stood behind the quest arrow on the same spot. The
-- profession stack (41a906f7, Nav/ArrowLayout.lua) stands it above the
-- quest arrow on its own, in its own colour and at full strength, so the
-- two never overlap or read as one. That is the layout kept (section 405
-- item 5: stacked or separate, profession text one side, levelling text
-- the other), so the rows below hold the stack as it is drawn now.

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

tests["prof arrow L5: the profession lane is fed and stands over the quest arrow"] = function(t)
    t.eq(fed(), true, "the C4 lane gives a step")
    local l = layoutOf({})
    t.eq(l.stacked, true, "stacked by default")
    t.eq(l.prof.shown, true, "the profession arrow is shown")
    t.eq(l.prof.above, true, "over the quest arrow")
    t.eq(l.prof.behind, false, "not behind it")
    t.eq(l.prof.anchor, "screen", "on its own place")
    t.eq(l.prof.look, "needle", "still the needle")
    t.eq(l.prof.tint, "own", "in its own colour")
    t.eq(l.prof.alpha, 1, "at full strength")
    t.eq(l.quest.small, false, "the quest arrow keeps its size")
    local q, p = l.quest.position, l.prof.position
    t.eq(p[3], q[3], "same column")
    t.eq(p[4] - q[4], 56 + N.NeedleClearance(56) + N.STACK_GAP,
        "one arrow, the needle's turning room and a gap higher: the two never overlap")
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

tests["prof arrow L5: restacked, it stands over the quest arrow again; a second separation keeps its place"] = function(t)
    local saved = N.ArrowApply({}, { op = "mode", mode = "separate" }, CTX)
    saved = N.ArrowApply(saved, { op = "move", key = "prof", point = { "BOTTOMLEFT", "BOTTOMLEFT", 100, 100 } }, CTX)
    saved = N.ArrowApply(saved, { op = "restack" }, CTX)
    local l = layoutOf(saved)
    t.eq(l.stacked, true, "restacked")
    t.eq(l.prof.above, true, "over the quest arrow again")
    t.eq(l.prof.anchor, "screen", "on its own place")
    t.eq(l.prof.position[4] > l.quest.position[4], true, "higher than the quest arrow")
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
