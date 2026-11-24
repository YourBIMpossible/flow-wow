local _, ns = ...
-- Arrow view tests. NV1-NV3 are the three faults of the Flow source that the
-- new code must not repeat (target section 12).
local N = ns.Nav

local W, H = 1000, 800
-- The default point { "TOP", "TOP", 0, -120 } on this screen: left 472, bottom 624.
local STACK_LEFT, STACK_BOTTOM = 472, 624
local SEPARATE = { arrows = { mode = "separate" } }
-- How far the profession arrow stands over the quest arrow in the stack.
local RISE = 56 + N.NeedleClearance(56) + N.STACK_GAP
local CTX = { screenW = W, screenH = H }

-- A state where the needle shows under a pointing quest arrow.
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

T["stacked: both arrows at full size and strength, the profession arrow over the quest arrow"] = function(t)
    local v = N.ArrowView(state())
    t.eq(v.stacked, true, "stacked")
    t.eq(v.quest.shown, true, "quest shown")
    full(t, v.quest, "quest under the profession arrow")
    t.eq(v.quest.mode, "arrow", "quest points")
    t.eq(v.prof.shown, true, "needle shown")
    t.eq(v.prof.look, "needle", "needle look")
    t.eq(v.prof.mode, "arrow", "needle points")
    t.eq(v.prof.behind, false, "not behind the quest arrow")
    t.eq(v.prof.above, true, "over it")
    t.eq(v.prof.anchor, "screen", "on its own place")
    t.eq(v.prof.scale, 1, "needle scale")
    t.eq(v.prof.alpha, 1, "needle alpha")
    colour(t, v.prof.colour, 0.2, 0.2, 0.2, "needle keeps its own colour stacked")
    local l, b = edge(v.quest.point)
    t.eq(l, STACK_LEFT, "left"); t.eq(b, STACK_BOTTOM, "bottom")
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
    t.eq(v.prof.alpha, 1, "needle alpha")
    local th = N.ARROW_PALETTE.standard.here
    colour(t, v.quest.colour, th[1], th[2], th[3], "ring is the in-area colour")
    -- On the point: ring, full, and the profession arrow stays (it stands
    -- over the quest arrow, so a quest stop does not switch it off).
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
    -- Icon gone again: back to full, both values, with the profession
    -- arrow over it.
    local after = N.ArrowView(state(nil, { travel = false }))
    full(t, after.quest, "icon gone, profession arrow over it")
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
                                    local needle = v.stacked and v.prof.shown and v.prof.mode == "arrow"
                                        and v.prof.anchor == "quest"
                                    local ok = (s == 1 and a == 1) or (s == 0.5 and a == 1 and v.quest.beside)
                                        or (s == 0.8 and a == 0.7 and needle and v.quest.mode == "arrow")
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

T["separated: quest arrow always full, profession arrow faint with quest colour meanings"] = function(t)
    local v = N.ArrowView(state({ layout = SEPARATE }))
    t.eq(v.stacked, false, "separated")
    full(t, v.quest, "separated quest arrow")
    t.eq(v.prof.shown, true, "profession arrow shown")
    t.eq(v.prof.anchor, "screen", "its own place")
    t.eq(v.prof.behind, false, "not behind")
    t.eq(v.prof.scale, 1, "full scale")
    t.eq(v.prof.alpha, 0.85, "lower opacity")
    -- Directly below the quest arrow: 56 + 8 lower.
    local l, b = edge(v.prof.point)
    t.eq(l, STACK_LEFT, "left"); t.eq(b, STACK_BOTTOM - 64, "bottom")
    -- Quest colour meanings at every state, never its own colour.
    local th = N.ARROW_PALETTE.standard
    for _, d in ipairs({ 40, 320, 600, 2000 }) do
        local r, g, bl = N.ArrowColor("zone", d)
        colour(t, N.ArrowView(state({ layout = SEPARATE }, nil, { distance = d })).prof.colour, r, g, bl, "at " .. d)
    end
    local away = N.ArrowView(state({ layout = SEPARATE }, nil, { target = { cont = 1, zone = 11 } }))
    colour(t, away.prof.colour, th.away[1], th.away[2], th.away[3], "another zone: grey")
    t.eq(away.prof.alpha, 0.85, "grey at lower opacity")
    local here = N.ArrowView(state({ layout = SEPARATE }, nil, { here = true }))
    colour(t, here.prof.colour, th.here[1], th.here[2], th.here[3], "in the area: blue")
    t.eq(here.prof.mode, "ring", "ring at its step")
    t.eq(here.prof.alpha, 0.35, "ring fainter still")
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
    full(t, restacked.quest, "restacked quest under the profession arrow")
    t.eq(restacked.prof.anchor, "screen", "the profession arrow on its own place")
    t.eq(restacked.prof.above, true, "over the quest arrow again")
    local ql, qb = edge(restacked.quest.point)
    local pl, pb = edge(restacked.prof.point)
    t.eq(pl, ql, "same column"); t.eq(pb, qb + RISE, "one rise over it")
end

T["text anchors: below or above by screen half, clear of the needle"] = function(t)
    -- Default place is in the top half and the lines fit above it.
    local plain = N.ArrowView(state(nil, nil, { hasStep = false }))
    t.eq(plain.quest.text.shown, true, "text shown")
    t.eq(plain.quest.text.to, "quest", "on the quest arrow")
    t.eq(plain.quest.text.side, "above", "top half: above")
    t.eq(plain.quest.text.point, { "BOTTOM", "TOP", 0, 4 }, "above, 4 clear")
    -- With the needle: the lines move out by its clearance (7 on a 56 frame).
    t.eq(N.NeedleClearance(56), 7, "needle clearance")
    local stacked = N.ArrowView(state())
    t.eq(stacked.quest.text.point, { "TOP", "BOTTOM", 0, -2 }, "two arrows: the quest lines below, 2 clear")
    -- The needle's lines are on its own frame, above it, clear of the needle.
    t.eq(stacked.prof.text.to, "prof", "needle text is on its own frame")
    t.eq(stacked.prof.text.side, "above", "over the profession arrow")
    t.eq(stacked.prof.text.point, { "BOTTOM", "TOP", 0, 7 }, "clear of the needle")
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
    t.eq(sep.prof.text.first, 7, "clear of its own needle")
    t.eq(sep.quest.text.first, 4, "quest text back to its plain gap")
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


-- LD1, then owner decision D2: stacked, the needle's lines count toward the
-- room the text needs whenever they are shown, and they are shown while the
-- needle is "off" too (it is bare: its text without its art).
-- The top of the profession text and the bottom of the quest text.
local function reach(v, qNeed, pNeed)
    local _, pb = edge(v.prof.point)
    local _, qb = edge(v.quest.point)
    return pb + 56 + v.prof.text.first + pNeed, qb - v.quest.text.first - qNeed
end

T["stack of two: profession text above its arrow, quest text below its arrow, never between"] = function(t)
    local v = N.ArrowView(state(nil, { textHeight = 14 }, { textHeight = 28 }))
    t.eq(v.prof.above, true, "the profession arrow is the upper one")
    local ql, qb = edge(v.quest.point)
    local pl, pb = edge(v.prof.point)
    t.eq(pl, ql, "one column"); t.eq(pb, qb + RISE, "one rise over the quest arrow")
    t.ok(pb >= qb + 56 + N.NeedleClearance(56), "the two never overlap")
    t.eq(v.quest.text.to, "quest"); t.eq(v.quest.text.side, "below", "quest text below the quest arrow")
    t.eq(v.prof.text.to, "prof"); t.eq(v.prof.text.side, "above", "profession text above the profession arrow")
    t.eq(v.quest.text.point, { "TOP", "BOTTOM", 0, -N.TEXT_GAP_BELOW }, "hangs under the quest arrow")
    t.eq(v.prof.text.point, { "BOTTOM", "TOP", 0, N.NeedleClearance(56) }, "stands over the needle")
end

T["stack of two: lines of a needle that is off stand right over the quest arrow (D2)"] = function(t)
    -- Arrow top 40 under the screen top: the stack is moved down so the
    -- profession arrow and its two lines stay on the screen.
    local top = { arrows = { points = { quest = { "TOP", "TOP", 0, -40 } } } }
    local drawn = N.ArrowView(state({ layout = top }, { textHeight = 14 }, { textHeight = 28 }))
    t.eq(drawn.prof.shown, true)
    t.eq(drawn.quest.text.side, "below", "the quest line is below")
    t.eq(drawn.prof.text.to, "prof", "section 341: on its own frame")
    t.eq(drawn.prof.text.side, "above", "needle drawn: its lines are over it")
    local topEdge, bottomEdge = reach(drawn, 14, 28)
    t.ok(topEdge <= H, "the profession lines end on the screen")
    t.ok(bottomEdge >= 0, "the quest line ends on the screen")
    -- The needle cannot point (no bearing): it is not drawn, its lines still are.
    local off = N.ArrowView(state({ layout = top }, { textHeight = 14 }, { textHeight = 28, bearingKnown = false }))
    t.eq(off.prof.mode, "off")
    t.eq(off.prof.shown, false)
    t.eq(off.prof.text.shown, true)
    t.eq(off.prof.text.to, "prof")
    t.eq(off.prof.text.side, "above", "its lines are above, as when it is drawn")
    t.eq(off.prof.text.point, { "BOTTOM", "TOP", 0, N.TEXT_GAP_ABOVE }, "with the plain gap: no needle to clear")
    t.eq(off.prof.point, off.quest.point, "its frame stands on the quest arrow's place")
    t.eq(off.quest.text.side, "below", "so the quest line is still below, never under the profession lines")
    -- The quest step at its point: the profession arrow is still drawn.
    local here = N.ArrowView(state({ layout = top }, { textHeight = 14, distance = 0 }, { textHeight = 28 }))
    t.eq(here.prof.mode, "arrow", "a quest stop does not switch it off")
    t.eq(here.prof.text.side, "above", "at the quest's point: its lines are over it")
end

-- Lead section 341. The needle's lines go on the other side only when that
-- can be worked out and they fit there; otherwise the one stack on the quest
-- arrow, as before.
T["stacked text: the needle's lines mirror the quest lines, above when those are below"] = function(t)
    local low = { arrows = { points = { quest = { "BOTTOMLEFT", "BOTTOMLEFT", 100, 100 } } } }
    local v = N.ArrowView(state({ layout = low }, { textHeight = 28 }, { textHeight = 28 }))
    t.eq(v.quest.text.side, "below", "bottom half: quest lines below")
    t.eq(v.prof.text.to, "prof")
    t.eq(v.prof.text.side, "above")
    t.eq(v.prof.text.point, { "BOTTOM", "TOP", 0, 7 })
end

T["stack of two: at a screen edge the stack is moved so no text is cut off"] = function(t)
    -- Saved at the very top: the stack goes down by what the profession
    -- arrow and its lines need.
    local top = { arrows = { points = { quest = { "TOP", "TOP", 0, -5 } } } }
    local v = N.ArrowView(state({ layout = top }, { textHeight = 14 }, { textHeight = 28 }))
    t.eq(v.quest.text.side, "below"); t.eq(v.prof.text.to, "prof"); t.eq(v.prof.text.side, "above")
    local topEdge, bottomEdge = reach(v, 14, 28)
    t.eq(topEdge, H, "the profession lines end at the top edge")
    t.ok(bottomEdge >= 0, "the quest line is on the screen")
    -- Saved at the very bottom: the stack goes up by what the quest line needs.
    local low = { arrows = { points = { quest = { "BOTTOM", "BOTTOM", 0, 0 } } } }
    v = N.ArrowView(state({ layout = low }, { textHeight = 14 }, { textHeight = 28 }))
    topEdge, bottomEdge = reach(v, 14, 28)
    t.eq(bottomEdge, 0, "the quest line ends at the bottom edge")
    t.ok(topEdge <= H, "the profession lines are on the screen")
    -- With one arrow only the saved place is kept as it is.
    local one = N.ArrowView(state({ layout = top }, { textHeight = 14 }, { hasStep = false }))
    local _, b = edge(one.quest.point)
    t.eq(b, H - 5 - 56, "one arrow: where the single arrow stands")
end

T["stacked text: screen size unknown, each text still on its own arrow's outer side"] = function(t)
    local v = N.ArrowView(state({ screenW = false, screenH = false }))
    t.eq(v.prof.text.to, "prof")
    t.eq(v.prof.text.side, "above")
    t.eq(v.quest.text.side, "below")
end

T["stacked text: quest text off, the needle's lines stay where they were"] = function(t)
    local hidden = { arrows = { text = { quest = false } } }
    local v = N.ArrowView(state({ layout = hidden }))
    t.eq(v.quest.text.shown, false)
    t.eq(v.prof.text.shown, true)
    t.eq(v.prof.text.to, "prof", "on its own arrow")
    t.eq(v.prof.text.side, "above", "above it, as with the quest text on")
end

return T
