local _, ns = ...
-- Arrow view tests. NV1-NV3 are the three faults of the Flow source that the
-- new code must not repeat (target section 12).
local N = ns.Nav

local W, H = 1000, 800
-- The default point { "TOP", "TOP", 0, -120 } on this screen: left 472, bottom 624.
local STACK_LEFT, STACK_BOTTOM = 472, 624
local SEPARATE = { arrows = { mode = "separate" } }
-- How far the echo stands under the quest arrow in the stack: straight below
-- it (the two bearings apart or unknown), or tucked under it (spread = 0).
local SLID, NEST = 56 + N.ARROW_GAP, N.ECHO_NEST
local CTX = { screenW = W, screenH = H }

-- A state where the echo shows behind a pointing quest arrow. No spread is
-- given, so the echo stands straight below; spread = 0 tucks it under.
local function state(over, questOver, profOver)
    local s = {
        gate = "open", screenW = W, screenH = H, facingKnown = true,
        player = { cont = 1, zone = 10 },
        quest = { hasStep = true, target = { cont = 1, zone = 10 }, distance = 300 },
        prof = { hasStep = true, target = { cont = 1, zone = 10 }, distance = 200,
                 bearingKnown = true, own = { 0.2, 0.2, 0.2 } },
    }
    for k, v in pairs(over or {}) do s[k] = v end
    for k, v in pairs(questOver or {}) do s.quest[k] = v end
    for k, v in pairs(profOver or {}) do s.prof[k] = v end
    return s
end

local function deep(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = deep(x) end
    return out
end

local function near(t, got, want, msg)
    t.ok(type(got) == "number" and math.abs(got - want) < 1e-9, msg)
end
local function colour(t, got, r, g, b, msg)
    near(t, got[1], r, msg .. " r"); near(t, got[2], g, msg .. " g"); near(t, got[3], b, msg .. " b")
end
local function full(t, ops, msg)
    t.eq(ops.scale, 1, msg .. ": scale 1")
    t.eq(ops.alpha, 1, msg .. ": alpha 1")
end
local function edge(p)
    local l, b = N.ArrowCorner(p, 56, W, H)
    return l, b
end

local T = {}

T["stacked: the quest arrow at full size and strength, the profession arrow its echo behind it"] = function(t)
    local v = N.ArrowView(state())
    t.eq(v.stacked, true, "stacked")
    t.eq(v.quest.shown, true, "quest shown")
    full(t, v.quest, "quest in front of the echo")
    t.eq(v.quest.mode, "arrow", "quest points")
    t.eq(v.prof.shown, true, "echo shown")
    t.eq(v.prof.look, "echo", "echo look")
    t.eq(v.prof.mode, "arrow", "echo points")
    t.eq(v.prof.behind, false, "slid below: not behind, it takes the mouse itself")
    t.eq(v.prof.above, nil, "never over it")
    t.eq(v.prof.slid, true, "bearings unknown: straight below")
    t.eq(v.prof.anchor, "screen", "on its own place")
    t.eq(v.prof.scale, 1, "echo scale")
    t.eq(v.prof.alpha, N.ECHO_ALPHA, "echo alpha")
    -- The echo's purple by its own distance, not the activity's own colour.
    local er, eg, eb = N.EchoColor("zone", 200)
    colour(t, v.prof.colour, er, eg, eb, "echo colour stacked")
    local l, b = edge(v.quest.point)
    t.eq(l, STACK_LEFT, "left"); t.eq(b, STACK_BOTTOM, "bottom")
    local pl, pb = edge(v.prof.point)
    t.eq(pl, STACK_LEFT, "echo: same column"); t.eq(pb, STACK_BOTTOM - SLID, "echo: one arrow and a gap down")
    -- Both steps the same way: tucked under, the quest arrow where it was.
    local n = N.ArrowView(state({ spread = 0 }))
    t.eq(n.prof.slid, false, "same bearing: tucked under")
    t.eq(n.prof.behind, true, "tucked: behind the quest arrow")
    full(t, n.quest, "quest in front of the tucked echo")
    local nl, nb = edge(n.prof.point)
    t.eq(nl, STACK_LEFT, "tucked: same column"); t.eq(nb, STACK_BOTTOM - NEST, "tucked: the nest down")
    local _, qb = edge(n.quest.point)
    t.eq(qb, STACK_BOTTOM, "the quest arrow does not move")
end

T["stacked: quest arrow is full size and alpha with or without a pointing needle"] = function(t)
    local cases = {
        { "no profession step", state(nil, nil, { hasStep = false }) },
        { "profession setting off", state(nil, nil, { on = false }) },
        { "bearing unknown", state(nil, nil, { bearingKnown = false }) },
        { "facing unknown", state({ facingKnown = false }) },
        { "inside the profession step", state(nil, nil, { here = true }) },
        { "within 24 yd of the profession step", state(nil, nil, { distance = 23.9 }) },
        { "profession arrow hidden by the player", state({ layout = { arrows = { hidden = { prof = true } } } }) },
    }
    for _, c in ipairs(cases) do
        local v = N.ArrowView(c[2])
        t.eq(v.quest.shown, true, c[1] .. ": quest shown")
        full(t, v.quest, c[1])
        t.ok(not (v.prof.shown and v.prof.mode == "arrow"), c[1] .. ": no pointing needle")
    end
    -- Exactly 24 yd is no longer "on the point": the needle points, and
    -- the quest arrow is as it was.
    local at24 = N.ArrowView(state(nil, nil, { distance = 24 }))
    full(t, at24.quest, "24 yd from the profession step")
    t.eq(at24.prof.mode, "arrow", "24 yd: the needle points")
    -- On the main step's point the profession arrow stays.
    local stop = N.ArrowView(state(nil, { distance = 10 }))
    full(t, stop.quest, "on the main step's point")
    t.ok(stop.prof.shown and stop.prof.mode == "arrow", "on the main step's point: the profession arrow stays")
end

T["NV1 corpse arrow is full size and alpha even if the needle was showing"] = function(t)
    local live = N.ArrowView(state())
    full(t, live.quest, "before dying")
    local dead = N.ArrowView(state({ gate = "corpse" }))
    t.eq(dead.quest.shown, true, "corpse arrow shown")
    t.eq(dead.quest.mode, "corpse", "corpse mode")
    full(t, dead.quest, "corpse arrow")
    colour(t, dead.quest.colour, 1, 0.2, 0.2, "corpse red")
    t.eq(dead.prof.shown, false, "no needle while dead")
    -- Same answer whatever was drawn before: nothing is remembered.
    local again = N.ArrowView(state({ gate = "corpse" }))
    t.eq(again.quest.scale, dead.quest.scale, "repeat scale")
    t.eq(again.quest.alpha, dead.quest.alpha, "repeat alpha")
    -- Separated too.
    full(t, N.ArrowView(state({ gate = "corpse", layout = SEPARATE })).quest, "corpse, separated")
end

T["NV2 arrived ring is full size and alpha inside the area but off the point"] = function(t)
    -- Inside the main step's area, 80 yd from its own point: the needle still
    -- points, the ring is not shrunk.
    local v = N.ArrowView(state(nil, { here = true, distance = 80 }))
    t.eq(v.quest.mode, "ring", "arrived ring")
    full(t, v.quest, "ring off the point")
    t.eq(v.prof.shown, true, "needle still shown")
    t.eq(v.prof.mode, "arrow", "needle still points")
    t.eq(v.prof.alpha, N.ECHO_ALPHA, "echo alpha")
    local th = N.ARROW_PALETTE.standard.here
    colour(t, v.quest.colour, th[1], th[2], th[3], "ring is the in-area colour")
    -- On the point: ring, full, and the profession arrow stays (it has its
    -- own place behind the quest arrow, so a quest stop does not switch it off).
    local on = N.ArrowView(state(nil, { here = true, distance = 5 }))
    t.eq(on.quest.mode, "ring", "ring on the point")
    full(t, on.quest, "ring on the point")
    t.eq(on.prof.shown, true, "the profession arrow stays at a quest stop")
    t.eq(on.prof.mode, "arrow", "and still points")
end

T["NV3 travel icon: scale and alpha are a pair, never scale 1 with alpha 0.7"] = function(t)
    local with = N.ArrowView(state(nil, { travel = true }))
    t.eq(with.quest.beside, true, "quest arrow stands beside the icon")
    t.eq(with.quest.scale, 0.5, "beside the icon: 0.5")
    t.eq(with.quest.alpha, 1, "beside the icon: alpha 1")
    -- Icon gone again: back to full, both values, with the echo behind it.
    local after = N.ArrowView(state(nil, { travel = false }))
    full(t, after.quest, "icon gone, echo behind it")
    -- Icon gone and needle gone: back to full, both values.
    full(t, N.ArrowView(state(nil, { travel = false }, { hasStep = false })).quest, "icon gone, no needle")
    -- No travel icon on the corpse arrow or the ring.
    local ring = N.ArrowView(state(nil, { travel = true, here = true }))
    t.eq(ring.quest.beside, false, "ring: not beside")
    full(t, ring.quest, "ring with a travel answer")
end

T["scale and alpha only ever take an allowed pair, over every combination"] = function(t)
    local bools = { false, true }
    local n = 0
    for _, gate in ipairs({ "open", "corpse", "intro", "off" }) do
        for _, mode in ipairs({ "stacked", "separate" }) do
            for _, qHere in ipairs(bools) do
                for _, qd in ipairs({ 5, 300 }) do
                    for _, travel in ipairs(bools) do
                        for _, pStep in ipairs(bools) do
                            for _, pHere in ipairs(bools) do
                                for _, can in ipairs(bools) do
                                    local v = N.ArrowView(state(
                                        { gate = gate, layout = { arrows = { mode = mode } } },
                                        { here = qHere, distance = qd, travel = travel },
                                        { hasStep = pStep, here = pHere, bearingKnown = can }))
                                    local s, a = v.quest.scale, v.quest.alpha
                                    -- The echo never makes the quest arrow smaller or fainter.
                                    local ok = (s == 1 and a == 1) or (s == 0.5 and a == 1 and v.quest.beside)
                                    n = n + 1
                                    if not ok then
                                        t.ok(false, string.format("bad pair %s/%s at %s %s here=%s d=%s travel=%s",
                                            tostring(s), tostring(a), gate, mode, tostring(qHere), tostring(qd), tostring(travel)))
                                    end
                                    if mode == "separate" and v.quest.shown and not v.quest.beside and s ~= 1 then
                                        t.ok(false, "separated quest arrow not full")
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    t.eq(n, 512, "combinations checked")
end

T["separated: quest arrow always full, profession arrow the see-through echo in its own purples"] = function(t)
    local v = N.ArrowView(state({ layout = SEPARATE }))
    t.eq(v.stacked, false, "separated")
    full(t, v.quest, "separated quest arrow")
    t.eq(v.prof.shown, true, "profession arrow shown")
    t.eq(v.prof.look, "echo", "still the echo")
    t.eq(v.prof.anchor, "screen", "its own place")
    t.eq(v.prof.behind, false, "not behind")
    t.eq(v.prof.slid, false, "no place in a stack")
    t.eq(v.prof.scale, 1, "full scale")
    t.eq(v.prof.alpha, N.ECHO_ALPHA, "lower opacity")
    -- Directly below the quest arrow: 56 + 8 lower.
    local l, b = edge(v.prof.point)
    t.eq(l, STACK_LEFT, "left"); t.eq(b, STACK_BOTTOM - 64, "bottom")
    -- The echo's purples at every state: never the quest palette, never the
    -- activity's own colour.
    local th = N.ECHO_PALETTE
    for _, d in ipairs({ 40, 320, 600, 2000 }) do
        local r, g, bl = N.EchoColor("zone", d)
        colour(t, N.ArrowView(state({ layout = SEPARATE }, nil, { distance = d })).prof.colour, r, g, bl, "at " .. d)
    end
    colour(t, N.ArrowView(state({ layout = SEPARATE }, nil, { distance = 40 })).prof.colour,
        th.near[1], th.near[2], th.near[3], "at 40: the near purple")
    colour(t, N.ArrowView(state({ layout = SEPARATE }, nil, { distance = 600 })).prof.colour,
        th.far[1], th.far[2], th.far[3], "at 600: the far purple")
    local away = N.ArrowView(state({ layout = SEPARATE }, nil, { target = { cont = 1, zone = 11 } }))
    colour(t, away.prof.colour, th.away[1], th.away[2], th.away[3], "another zone: greyed purple")
    t.eq(away.prof.alpha, N.ECHO_ALPHA, "greyed at lower opacity")
    local here = N.ArrowView(state({ layout = SEPARATE }, nil, { here = true }))
    colour(t, here.prof.colour, th.here[1], th.here[2], th.here[3], "in the area: the brightest purple")
    t.eq(here.prof.mode, "ring", "ring at its step")
    t.eq(here.prof.alpha, N.PROF_RING_ALPHA, "ring fainter still")
    t.eq(N.PROF_RING_ALPHA, 0.35)
    -- The main step's point does not switch a separated profession arrow off.
    local onMain = N.ArrowView(state({ layout = SEPARATE }, { distance = 5 }))
    t.eq(onMain.prof.shown, true, "still shown on the main point")
    full(t, onMain.quest, "quest full on its point")
    -- It cannot point: art off, quest arrow untouched.
    local blind = N.ArrowView(state({ layout = SEPARATE, facingKnown = false }))
    t.eq(blind.prof.shown, false, "cannot point: not drawn")
    full(t, blind.quest, "quest full")
end

T["quest colour: grey away, far to near, blue in the area"] = function(t)
    local th = N.ARROW_PALETTE.standard
    for _, lay in ipairs({ false, SEPARATE }) do
        local base = lay or nil
        local far = N.ArrowView(state({ layout = base }, { distance = 600 })).quest.colour
        colour(t, far, th.far[1], th.far[2], th.far[3], "600 yd")
        local nearC = N.ArrowView(state({ layout = base }, { distance = 40 })).quest.colour
        colour(t, nearC, th.near[1], th.near[2], th.near[3], "40 yd")
        local away = N.ArrowView(state({ layout = base }, { target = { cont = 2, zone = 10 } })).quest.colour
        colour(t, away, th.away[1], th.away[2], th.away[3], "another continent")
    end
    local cb = N.ARROW_PALETTE.colourBlind
    local v = N.ArrowView(state({ palette = cb }, { distance = 40 }))
    colour(t, v.quest.colour, cb.near[1], cb.near[2], cb.near[3], "colour-blind palette")
    -- Unknown player zone: not called away.
    local unknown = N.ArrowView(state({ player = false }, { distance = 600 })).quest.colour
    colour(t, unknown, th.far[1], th.far[2], th.far[3], "player zone unknown")
end

T["clamp: every point is on the screen, saved off-screen places are pulled back"] = function(t)
    local lay = { arrows = { mode = "separate", points = {
        quest = { "BOTTOMLEFT", "BOTTOMLEFT", -500, 5000 },
        prof = { "BOTTOMLEFT", "BOTTOMLEFT", 9000, -9000 } } } }
    local v = N.ArrowView(state({ layout = lay }))
    local ql, qb = edge(v.quest.point)
    t.eq(ql, 0, "quest left"); t.eq(qb, H - 56, "quest bottom")
    local pl, pb = edge(v.prof.point)
    t.eq(pl, W - 56, "prof left"); t.eq(pb, 0, "prof bottom")
    -- A smaller screen than the one the place was saved on.
    local keep = { arrows = { mode = "separate", points = {
        quest = { "BOTTOMLEFT", "BOTTOMLEFT", 900, 700 }, prof = { "BOTTOMLEFT", "BOTTOMLEFT", 700, 700 } } } }
    local s = state({ layout = keep, screenW = 640, screenH = 480 })
    local sv = N.ArrowView(s)
    for _, key in ipairs({ "quest", "prof" }) do
        local l, b = N.ArrowCorner(sv[key].point, 56, 640, 480)
        t.ok(l >= 0 and l <= 640 - 56, key .. " inside left to right")
        t.ok(b >= 0 and b <= 480 - 56, key .. " inside bottom to top")
    end
    -- Screen size unknown: the saved place is passed on untouched.
    local raw = N.ArrowView(state({ layout = keep, screenW = false, screenH = false }))
    t.eq(raw.quest.point[3], 900, "unclamped x"); t.eq(raw.quest.point[4], 700, "unclamped y")
end

T["reset returns the default stacked view; restack returns the stacked view"] = function(t)
    local moved = N.ArrowApply({}, { op = "move", key = "quest", point = { "BOTTOMLEFT", "BOTTOMLEFT", 100, 100 } }, CTX)
    moved = N.ArrowApply(moved, { op = "move", key = "prof", point = { "BOTTOMLEFT", "BOTTOMLEFT", 300, 300 } }, CTX)
    local apart = N.ArrowView(state({ layout = moved }))
    t.eq(apart.stacked, false, "moved apart")
    local l, b = edge(apart.prof.point)
    t.eq(l, 300, "prof own left"); t.eq(b, 300, "prof own bottom")

    local fresh = N.ArrowView(state())
    local reset = N.ArrowView(state({ layout = N.ArrowApply(moved, { op = "reset" }, CTX) }))
    t.eq(reset, fresh, "reset equals the default view, field by field")

    local restacked = N.ArrowView(state({ layout = N.ArrowApply(moved, { op = "restack" }, CTX) }))
    local wanted = N.ArrowView(state({ layout = { arrows = { points = {
        quest = { "BOTTOMLEFT", "BOTTOMLEFT", 100, 100 } } } } }))
    t.eq(restacked, wanted, "restack equals the stacked view at the quest arrow's place")
    full(t, restacked.quest, "restacked quest in front of the echo")
    t.eq(restacked.prof.anchor, "screen", "the profession arrow on its own place")
    t.eq(restacked.prof.look, "echo", "the echo again")
    t.eq(restacked.prof.behind, false, "slid below the quest arrow again (no spread): not behind")
    local ql, qb = edge(restacked.quest.point)
    local pl, pb = edge(restacked.prof.point)
    t.eq(ql, 100, "quest left kept"); t.eq(qb, 100, "quest bottom kept")
    t.eq(pl, ql, "same column"); t.eq(pb, qb - SLID, "one arrow and a gap under it")
end

T["text anchors: one arrow below or above by screen half; with the echo, quest above and echo below"] = function(t)
    -- Default place is in the top half and the lines fit above it.
    local plain = N.ArrowView(state(nil, nil, { hasStep = false }))
    t.eq(plain.quest.text.shown, true, "text shown")
    t.eq(plain.quest.text.to, "quest", "on the quest arrow")
    t.eq(plain.quest.text.side, "above", "top half: above")
    t.eq(plain.quest.text.point, { "BOTTOM", "TOP", 0, 4 }, "above, 4 clear")
    -- With the echo: the quest lines stay above the quest arrow, 4 clear.
    t.eq(N.TEXT_GAP_ABOVE, 4); t.eq(N.TEXT_GAP_BELOW, 2)
    local stacked = N.ArrowView(state())
    t.eq(stacked.quest.text.side, "above", "two arrows: the quest lines above")
    t.eq(stacked.quest.text.point, { "BOTTOM", "TOP", 0, N.TEXT_GAP_ABOVE }, "two arrows: the quest lines above, 4 clear")
    -- The echo's lines are on its own frame, below it, with the plain gap.
    t.eq(stacked.prof.text.to, "prof", "echo text is on its own frame")
    t.eq(stacked.prof.text.side, "below", "under the echo")
    t.eq(stacked.prof.text.point, { "TOP", "BOTTOM", 0, -N.TEXT_GAP_BELOW }, "under the echo, 2 clear")
    t.eq(stacked.prof.text.first, N.TEXT_GAP_BELOW, "no needle to clear")
    -- The same with the stack in the bottom half.
    local lowStack = N.ArrowView(state({ layout = { arrows = { points = {
        quest = { "BOTTOMLEFT", "BOTTOMLEFT", 100, 100 } } } } }))
    t.eq(lowStack.quest.text.point, { "BOTTOM", "TOP", 0, N.TEXT_GAP_ABOVE }, "bottom half: quest lines still above")
    t.eq(lowStack.prof.text.point, { "TOP", "BOTTOM", 0, -N.TEXT_GAP_BELOW }, "bottom half: echo lines still below")
    -- Bottom half: below.
    local low = { arrows = { points = { quest = { "BOTTOMLEFT", "BOTTOMLEFT", 100, 100 } } } }
    local below = N.ArrowView(state({ layout = low }, nil, { hasStep = false }))
    t.eq(below.quest.text.side, "below", "bottom half: below")
    t.eq(below.quest.text.point, { "TOP", "BOTTOM", 0, -2 }, "below, 2 clear")
    -- Top half but the lines do not fit above: below.
    local top = { arrows = { points = { quest = { "TOP", "TOP", 0, 0 } } } }
    local tight = N.ArrowView(state({ layout = top }, { textHeight = 30 }, { hasStep = false }))
    t.eq(tight.quest.text.side, "below", "no room above: below")
    -- Text switched off per arrow.
    local off = N.ArrowView(state({ layout = { arrows = { text = { quest = false } } } }))
    t.eq(off.quest.text.shown, false, "quest text off")
    t.eq(off.prof.text.shown, true, "profession text still on")
    -- Separated: the profession text hangs on its own arrow.
    local sep = N.ArrowView(state({ layout = SEPARATE }))
    t.eq(sep.prof.text.to, "prof", "own arrow")
    -- Its own arrow stands in the top half (bottom 560): above, the plain gap.
    t.eq(sep.prof.text.side, "above", "its own screen half")
    t.eq(sep.prof.text.first, N.TEXT_GAP_ABOVE, "its plain gap: no needle to clear")
    t.eq(sep.quest.text.first, 4, "quest text at its plain gap")
end

T["gate off and hidden arrows: nothing shown, values still computed"] = function(t)
    local off = N.ArrowView(state({ gate = "off" }))
    t.eq(off.quest.shown, false, "quest hidden"); t.eq(off.prof.shown, false, "prof hidden")
    full(t, off.quest, "hidden quest arrow still full")
    t.eq(off.quest.text.shown, false, "no text")
    local intro = N.ArrowView(state({ gate = "intro" }))
    t.eq(intro.quest.shown, true, "intro shown"); t.eq(intro.quest.mode, "intro", "intro mode")
    full(t, intro.quest, "intro")
    t.eq(intro.prof.shown, false, "no profession arrow in the intro")
    local hidden = N.ArrowView(state({ layout = { arrows = { hidden = { quest = true } } } }))
    t.eq(hidden.quest.shown, false, "quest hidden by the player")
    t.eq(hidden.prof.shown, true, "profession step takes the stack's place")
    t.eq(hidden.prof.look, "pointer", "as a pointer")
    t.eq(hidden.prof.alpha, 0.85, "still at lower opacity")
    local empty = N.ArrowView(nil)
    t.eq(empty.quest.shown, false, "no state: nothing shown")
    full(t, empty.quest, "no state")
end

T["pure: the state is not changed and the same state gives the same view"] = function(t)
    local s = state({ layout = { arrows = { mode = "separate",
        points = { prof = { "BOTTOMLEFT", "BOTTOMLEFT", 9000, 20 } } } } })
    local before = deep(s)
    local a = N.ArrowView(s)
    t.eq(s, before, "state untouched")
    -- A different state in between leaves no trace.
    N.ArrowView(state({ gate = "corpse" }))
    N.ArrowView(state(nil, { travel = true }))
    local b = N.ArrowView(s)
    t.eq(b, a, "same view")
    t.ok(a.quest.point ~= b.quest.point, "fresh tables each call")
    a.quest.point[3] = 12345
    t.ok(N.ArrowView(s).quest.point[3] ~= 12345, "a caller's edit does not leak back")
end


-- LD1, then owner decision D2: stacked, the echo's lines count toward the
-- room the text needs whenever they are shown, and they are shown while the
-- echo is "off" too (it is bare: its text without its art).
-- The top of the quest text and the bottom of the profession text.
local function reach(v, qNeed, pNeed)
    local _, pb = edge(v.prof.point)
    local _, qb = edge(v.quest.point)
    return qb + 56 + v.quest.text.first + qNeed, pb - v.prof.text.first - pNeed
end

T["stack of two: quest text above the quest arrow, profession text below the echo, never between"] = function(t)
    local v = N.ArrowView(state(nil, { textHeight = 14 }, { textHeight = 28 }))
    t.eq(v.prof.behind, false, "slid below (no spread): the echo is not behind")
    t.eq(v.prof.above, nil, "never the upper one")
    local ql, qb = edge(v.quest.point)
    local pl, pb = edge(v.prof.point)
    t.eq(qb, STACK_BOTTOM, "the quest arrow where the single arrow stands")
    t.eq(pl, ql, "one column"); t.eq(pb, qb - SLID, "one arrow and a gap under the quest arrow")
    t.eq(pb + 56 + N.ARROW_GAP, qb, "slid out, the two never overlap")
    t.eq(v.quest.text.to, "quest"); t.eq(v.quest.text.side, "above", "quest text above the quest arrow")
    t.eq(v.prof.text.to, "prof"); t.eq(v.prof.text.side, "below", "profession text below the echo")
    t.eq(v.quest.text.point, { "BOTTOM", "TOP", 0, N.TEXT_GAP_ABOVE }, "stands over the quest arrow")
    t.eq(v.prof.text.point, { "TOP", "BOTTOM", 0, -N.TEXT_GAP_BELOW }, "hangs under the echo")
    -- Tucked under: the same sides, the quest arrow in the same place.
    local n = N.ArrowView(state({ spread = 0 }, { textHeight = 14 }, { textHeight = 28 }))
    local _, nqb = edge(n.quest.point)
    local _, npb = edge(n.prof.point)
    t.eq(nqb, qb, "tucked: the quest arrow does not move"); t.eq(npb, qb - NEST, "tucked: the nest under it")
    t.eq(n.quest.text.point, { "BOTTOM", "TOP", 0, N.TEXT_GAP_ABOVE }, "tucked: quest text still above")
    t.eq(n.prof.text.point, { "TOP", "BOTTOM", 0, -N.TEXT_GAP_BELOW }, "tucked: profession text still below")
end

T["stack of two: lines of an echo that is not drawn stand right under the quest arrow (D2)"] = function(t)
    -- Arrow top 40 under the screen top: the quest line and its gap (18) fit
    -- above it, so the stack stays where it was saved.
    local top = { arrows = { points = { quest = { "TOP", "TOP", 0, -40 } } } }
    local drawn = N.ArrowView(state({ layout = top }, { textHeight = 14 }, { textHeight = 28 }))
    t.eq(drawn.prof.shown, true)
    t.eq(drawn.quest.text.side, "above", "the quest line is above")
    t.eq(drawn.prof.text.to, "prof", "section 341: on its own frame")
    t.eq(drawn.prof.text.side, "below", "echo drawn: its lines are under it")
    local _, dqb = edge(drawn.quest.point)
    t.eq(dqb, H - 40 - 56, "it fits: the stack is not moved")
    local topEdge, bottomEdge = reach(drawn, 14, 28)
    t.eq(topEdge, H - 40 + N.TEXT_GAP_ABOVE + 14, "the quest line ends on the screen")
    t.ok(topEdge <= H, "under the top edge")
    t.eq(bottomEdge, dqb - SLID - N.TEXT_GAP_BELOW - 28, "the profession lines end under the echo")
    t.ok(bottomEdge >= 0, "on the screen")
    -- The echo cannot point (no bearing): it is not drawn, its lines still are.
    local off = N.ArrowView(state({ layout = top }, { textHeight = 14 }, { textHeight = 28, bearingKnown = false }))
    t.eq(off.prof.mode, "off")
    t.eq(off.prof.shown, false)
    t.eq(off.prof.bare, true)
    t.eq(off.prof.text.shown, true)
    t.eq(off.prof.text.to, "prof")
    t.eq(off.prof.text.side, "below", "its lines are below, as when it is drawn")
    t.eq(off.prof.text.point, { "TOP", "BOTTOM", 0, -N.TEXT_GAP_BELOW }, "with the plain gap")
    t.eq(off.prof.point, off.quest.point, "its frame stands on the quest arrow's place")
    t.eq(off.quest.text.side, "above", "so the quest line is still above, never under the profession lines")
    -- The quest step at its point: the profession arrow is still drawn.
    local here = N.ArrowView(state({ layout = top }, { textHeight = 14, distance = 0 }, { textHeight = 28 }))
    t.eq(here.prof.mode, "arrow", "a quest stop does not switch it off")
    t.eq(here.prof.text.side, "below", "at the quest's point: its lines are under it")
end

-- Lead section 476 (it replaces section 341's mirror): with the echo the
-- sides are fixed. The quest lines stand above the quest arrow and the
-- echo's lines below the echo, whatever the screen half.
T["stacked text: the quest lines are above and the echo's lines below, in the bottom half too"] = function(t)
    local low = { arrows = { points = { quest = { "BOTTOMLEFT", "BOTTOMLEFT", 100, 100 } } } }
    local v = N.ArrowView(state({ layout = low }, { textHeight = 28 }, { textHeight = 28 }))
    t.eq(v.quest.text.side, "above", "bottom half: quest lines above")
    t.eq(v.quest.text.point, { "BOTTOM", "TOP", 0, N.TEXT_GAP_ABOVE })
    t.eq(v.prof.text.to, "prof")
    t.eq(v.prof.text.side, "below")
    t.eq(v.prof.text.point, { "TOP", "BOTTOM", 0, -N.TEXT_GAP_BELOW })
    -- The echo and its lines (64 + 2 + 28) fit under an arrow 100 up: not moved.
    local _, qb = edge(v.quest.point)
    t.eq(qb, 100, "it fits: the stack is not moved")
end

T["stack of two: at a screen edge the stack is moved so no text is cut off"] = function(t)
    -- Saved at the very top: the stack goes down by what the quest line
    -- over the quest arrow needs.
    local top = { arrows = { points = { quest = { "TOP", "TOP", 0, -5 } } } }
    local v = N.ArrowView(state({ layout = top }, { textHeight = 14 }, { textHeight = 28 }))
    t.eq(v.quest.text.side, "above"); t.eq(v.prof.text.to, "prof"); t.eq(v.prof.text.side, "below")
    local topEdge, bottomEdge = reach(v, 14, 28)
    t.eq(topEdge, H, "the quest line ends at the top edge")
    t.ok(bottomEdge >= 0, "the profession lines are on the screen")
    local _, qb = edge(v.quest.point)
    t.eq(qb, H - 14 - N.TEXT_GAP_ABOVE - 56, "down by the quest line and its gap")
    -- Saved at the very bottom: the stack goes up by what the echo and its
    -- lines need.
    local low = { arrows = { points = { quest = { "BOTTOM", "BOTTOM", 0, 0 } } } }
    v = N.ArrowView(state({ layout = low }, { textHeight = 14 }, { textHeight = 28 }))
    topEdge, bottomEdge = reach(v, 14, 28)
    t.eq(bottomEdge, 0, "the profession lines end at the bottom edge")
    t.ok(topEdge <= H, "the quest line is on the screen")
    _, qb = edge(v.quest.point)
    t.eq(qb, SLID + N.TEXT_GAP_BELOW + 28, "up by the echo's place and its lines")
    -- Tucked under, the room of the place below is still kept: the quest
    -- arrow stands where it stood, and nothing is cut off.
    local n = N.ArrowView(state({ layout = low, spread = 0 }, { textHeight = 14 }, { textHeight = 28 }))
    local _, nqb = edge(n.quest.point)
    t.eq(nqb, qb, "tucked: the quest arrow does not move")
    local _, nBottom = reach(n, 14, 28)
    t.eq(nBottom, SLID - NEST, "tucked: the profession lines end higher")
    -- With one arrow only the saved place is kept as it is.
    local one = N.ArrowView(state({ layout = top }, { textHeight = 14 }, { hasStep = false }))
    local _, b = edge(one.quest.point)
    t.eq(b, H - 5 - 56, "one arrow: where the single arrow stands")
end

T["stacked text: screen size unknown, the quest text still above its arrow, the echo's below"] = function(t)
    local v = N.ArrowView(state({ screenW = false, screenH = false }))
    t.eq(v.prof.text.to, "prof")
    t.eq(v.prof.text.side, "below")
    t.eq(v.prof.text.point, { "TOP", "BOTTOM", 0, -N.TEXT_GAP_BELOW })
    t.eq(v.quest.text.side, "above")
    t.eq(v.quest.text.point, { "BOTTOM", "TOP", 0, N.TEXT_GAP_ABOVE })
end

T["stacked text: quest text off, the echo's lines stay where they were"] = function(t)
    local hidden = { arrows = { text = { quest = false } } }
    local v = N.ArrowView(state({ layout = hidden }))
    t.eq(v.quest.text.shown, false)
    t.eq(v.prof.text.shown, true)
    t.eq(v.prof.text.to, "prof", "on its own arrow")
    t.eq(v.prof.text.side, "below", "below it, as with the quest text on")
    t.eq(v.prof.text.point, { "TOP", "BOTTOM", 0, -N.TEXT_GAP_BELOW })
end

-- R7 (lead section 564): the quest arrow takes its colour from RC.Of for the
-- step it points at, as the map lines do, so the two never disagree.
T["R7: the quest arrow's colour is RC.Of's for its step"] = function(t)
    local RC = ns.RouteColor
    local wr, wg, wb = RC.Of({ family = "waypoint" }, 300, "standard")
    colour(t, N.ArrowView(state(nil, { family = "waypoint" })).quest.colour, wr, wg, wb, "waypoint: green")
    local cr, cg, cb = RC.Of({ family = "waypoint" }, 300, "colourBlind")
    colour(t, N.ArrowView(state({ palette = N.ARROW_PALETTE.colourBlind }, { family = "waypoint" })).quest.colour,
        cr, cg, cb, "waypoint, colour-blind palette")
    local pr, pg, pb = RC.Of({ family = "profession" }, 300, "standard")
    colour(t, N.ArrowView(state(nil, { family = "profession" })).quest.colour, pr, pg, pb, "profession: purple")
    local dr, dg, db = RC.Of(nil, 300, "standard")
    colour(t, N.ArrowView(state()).quest.colour, dr, dg, db, "a route step: by distance")
end

-- A1-06 (lead sections 643 and 645): with the one-colour setting the arrow
-- is the one flat colour for every step, waypoint and profession too, as
-- the map's first leg is (Muse's one-colour fix to MRL.Paint).
T["A1-06: with the one-colour setting every arrow is the one flat colour"] = function(t)
    local flat = N.ArrowPaletteOf("standard", false)
    local fr, fg, fb = N.ArrowColor("zone", 300, flat)
    local MRL = ns.MapRouteLines
    local rr, rg, rb = MRL.Paint("first", { state = "zone" }, 300, "standard", false)
    colour(t, { fr, fg, fb }, rr, rg, rb, "the flat colour is the map's first leg for a route step")
    colour(t, N.ArrowView(state({ palette = flat })).quest.colour, fr, fg, fb, "route step")
    colour(t, N.ArrowView(state({ palette = flat }, { family = "waypoint" })).quest.colour, fr, fg, fb, "waypoint")
    colour(t, N.ArrowView(state({ palette = flat }, { family = "profession" })).quest.colour, fr, fg, fb,
        "profession step")
end

T["R7: a palette row gives back its palette word"] = function(t)
    t.eq(N.ArrowPaletteWord(N.ARROW_PALETTE.colourBlind), "colourBlind")
    t.eq(N.ArrowPaletteWord(N.ArrowPaletteOf("colourBlind", false)), "colourBlind")
    t.eq(N.ArrowPaletteWord(N.ARROW_PALETTE.standard), "standard")
    t.eq(N.ArrowPaletteWord(nil), "standard")
end

return T
