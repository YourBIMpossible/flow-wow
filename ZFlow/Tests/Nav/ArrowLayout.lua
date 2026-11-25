local _, ns = ...
-- Arrow layout tests. Rows O1-O9 are the arrow acceptance list; a test named
-- "O<n> ..." decides the part of that row that needs no frames.
local N = ns.Nav

local W, H = 1000, 800
-- The default point { "TOP", "TOP", 0, -120 } on this screen: left 472, bottom 624.
local STACK_LEFT, STACK_BOTTOM = 472, 624
-- How far the profession arrow (the echo) stands under the quest arrow in the
-- stack: tucked under it, or slid straight below (one arrow and a gap).
local NEST = N.ECHO_NEST
local SLIDE = 56 + N.ARROW_GAP

local function state(layout, over)
    local s = { layout = layout, gate = "open", screenW = W, screenH = H,
                quest = { hasStep = true }, prof = { hasStep = true } }
    for k, v in pairs(over or {}) do s[k] = v end
    return s
end
local CTX = { screenW = W, screenH = H }

local function deep(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = deep(x) end
    return out
end

-- Left and bottom edge of a 56 box at a point, worked out here on its own.
local AX = { TOPLEFT = 0, TOP = 0.5, TOPRIGHT = 1, LEFT = 0, CENTER = 0.5, RIGHT = 1,
             BOTTOMLEFT = 0, BOTTOM = 0.5, BOTTOMRIGHT = 1 }
local AY = { TOPLEFT = 1, TOP = 1, TOPRIGHT = 1, LEFT = 0.5, CENTER = 0.5, RIGHT = 0.5,
             BOTTOMLEFT = 0, BOTTOM = 0, BOTTOMRIGHT = 0 }
local function edge(p)
    return AX[p[2]] * W + p[3] - AX[p[1]] * 56, AY[p[2]] * H + p[4] - AY[p[1]] * 56
end
local function at(t, p, left, bottom, msg)
    t.ok(p ~= nil, msg .. ": has a position")
    if not p then return end
    local l, b = edge(p)
    t.eq(l, left, msg .. ": left")
    t.eq(b, bottom, msg .. ": bottom")
end
local function near(t, got, want, msg)
    t.ok(type(got) == "number" and math.abs(got - want) < 1e-9, msg)
end
local function colour(t, r, g, b, want, msg)
    near(t, r, want[1], msg .. " r"); near(t, g, want[2], msg .. " g"); near(t, b, want[3], msg .. " b")
end

local FIELDS = { "shown", "anchor", "look", "behind", "small", "scale", "alpha", "tint",
                 "faint", "emphasis", "text" }
local function sameLayout(t, got, want, msg)
    t.eq(got.stacked, want.stacked, msg .. ": stacked")
    for _, key in ipairs({ "quest", "prof" }) do
        for _, f in ipairs(FIELDS) do
            t.eq(got[key][f], want[key][f], msg .. ": " .. key .. "." .. f)
        end
        for i = 1, 4 do
            t.eq(got[key].position[i], want[key].position[i], msg .. ": " .. key .. ".position[" .. i .. "]")
        end
    end
end

local function separated()
    return N.ArrowApply(nil, { op = "mode", mode = "separate" }, CTX)
end

return {
    -- Two arrows (lead section 476): the profession arrow is the echo of the
    -- quest arrow: the same arrow, purple and see-through, behind and below
    -- it. The quest arrow keeps its size and strength.
    ["O1 stacked look: the profession arrow is the echo behind the quest arrow, which stays at full strength"] = function(t)
        local L = N.ArrowLayout(state(nil))
        t.eq(L.stacked, true, "stacked is the default")
        t.eq(L.quest.shown, true, "quest shown")
        t.eq(L.quest.alpha, 1, "quest alpha: not dimmed by the profession arrow")
        t.eq(L.quest.scale, 1, "quest scale: not shrunk")
        t.eq(L.quest.small, false, "quest not small")
        t.eq(L.quest.look, "pointer", "quest look")
        t.eq(L.prof.shown, true, "prof shown")
        t.eq(L.prof.alpha, N.ECHO_ALPHA, "prof see-through")
        t.eq(L.prof.scale, 1, "prof scale")
        t.eq(L.prof.look, "echo", "prof is the echo")
        t.eq(L.prof.anchor, "screen", "the profession arrow has its own place")
        t.eq(L.prof.behind, true, "behind the quest arrow")
        t.eq(L.prof.echo, true, "said to be the echo")
        t.eq(L.prof.above, nil, "no longer over the quest arrow")
        t.eq(L.prof.tint, "echo", "the echo's own purple")
        t.eq(L.prof.slid, false, "no slid in the state: tucked under")
        at(t, L.quest.position, STACK_LEFT, STACK_BOTTOM, "quest at the default place")
        at(t, L.prof.position, STACK_LEFT, STACK_BOTTOM - NEST, "the echo tucked under it")
        local S = N.ArrowLayout(state(nil, { slid = true }))
        t.eq(S.prof.slid, true, "slid in the state")
        at(t, S.quest.position, STACK_LEFT, STACK_BOTTOM, "slid: the quest arrow does not move")
        at(t, S.prof.position, STACK_LEFT, STACK_BOTTOM - SLIDE, "slid: one arrow and a gap below")
        t.eq(N.ECHO_NEST, 12, "constant nest"); t.eq(N.ECHO_ALPHA, 0.7, "constant echo alpha")
        t.eq(SLIDE, 64, "the slid drop"); t.eq(N.EchoDrop(56, true), SLIDE, "EchoDrop slid")
        t.eq(N.EchoDrop(56, false), NEST, "EchoDrop tucked")
        t.eq(N.PROF_HOLDER_ALPHA, 0.85, "constant holder alpha")
        t.eq(N.NEEDLE_W, 25.6, "needle width"); t.eq(N.NEEDLE_H, 109.1, "needle height")
    end,

    ["stack of two: one arrow stands where the single arrow stands; text room keeps both on the screen"] = function(t)
        local one = N.ArrowLayout(state(nil, { prof = { hasStep = false } }))
        at(t, one.quest.position, STACK_LEFT, STACK_BOTTOM, "quest alone: the stack's place")
        local only = N.ArrowLayout(state(nil, { quest = { hasStep = false } }))
        at(t, only.prof.position, STACK_LEFT, STACK_BOTTOM, "profession alone: the stack's place")
        t.eq(only.prof.look, "pointer", "alone it is drawn as the one arrow")
        -- Only its text (mode off): its frame is on the quest arrow's place.
        local bare = N.ArrowLayout(state(nil, { prof = { hasStep = true, mode = "off" } }))
        at(t, bare.quest.position, STACK_LEFT, STACK_BOTTOM, "bare: quest stays")
        at(t, bare.prof.position, STACK_LEFT, STACK_BOTTOM, "bare: the text frame on the quest arrow's place")
        -- N.ArrowStack on its own: two points, the second lower by the nest,
        -- or by one arrow and a gap when slid. 20 is the quest text's room
        -- (over the quest arrow), 30 the profession text's (under the echo).
        local q, p = N.ArrowStack({ "BOTTOMLEFT", "BOTTOMLEFT", 300, 300 }, 56, W, H, 20, 30, true)
        at(t, q, 300, 300, "room on both sides: not moved"); at(t, p, 300, 300 - NEST, "the echo tucked under it")
        q, p = N.ArrowStack({ "BOTTOMLEFT", "BOTTOMLEFT", 300, 300 }, 56, W, H, 20, 30, true, true)
        at(t, q, 300, 300, "slid: not moved"); at(t, p, 300, 300 - SLIDE, "slid: the echo straight below")
        -- The slid place and the profession text would leave the bottom: the
        -- stack goes up, as one. The room is kept tucked or slid, so the
        -- quest arrow stands the same either way.
        q, p = N.ArrowStack({ "BOTTOMLEFT", "BOTTOMLEFT", 300, 10 }, 56, W, H, 20, 30, true)
        at(t, q, 300, SLIDE + 30, "up by the slid place and what the profession text needs")
        at(t, p, 300, SLIDE + 30 - NEST, "the echo with it")
        q, p = N.ArrowStack({ "BOTTOMLEFT", "BOTTOMLEFT", 300, 10 }, 56, W, H, 20, 30, true, true)
        at(t, q, 300, SLIDE + 30, "slid: the quest arrow at the same place")
        at(t, p, 300, 30, "slid: its text ends at the bottom edge")
        -- No echo drawn: only its text takes room, on the quest arrow's place.
        q, p = N.ArrowStack({ "BOTTOMLEFT", "BOTTOMLEFT", 300, 10 }, 56, W, H, 20, 30, false)
        at(t, q, 300, 30, "not drawn: up by the profession text alone"); at(t, p, 300, 30, "not drawn: the same place")
        -- Quest text would leave the top: the stack goes down.
        q, p = N.ArrowStack({ "BOTTOMLEFT", "BOTTOMLEFT", 300, H - 56 }, 56, W, H, 20, 30, true)
        at(t, q, 300, H - 56 - 20, "its text ends at the top edge"); at(t, p, 300, H - 56 - 20 - NEST, "the echo under it")
        -- Screen size unknown: nothing is moved, only the drop.
        q, p = N.ArrowStack({ "CENTER", "CENTER", 0, 0 }, 56, nil, nil, 20, 30, true)
        t.eq(q, { "CENTER", "CENTER", 0, 0 }, "unknown screen: quest as given")
        t.eq(p, { "CENTER", "CENTER", 0, -NEST }, "unknown screen: the echo under it")
        q, p = N.ArrowStack({ "CENTER", "CENTER", 0, 0 }, 56, nil, nil, 20, 30, true, true)
        t.eq(q, { "CENTER", "CENTER", 0, 0 }, "unknown screen, slid: quest as given")
        t.eq(p, { "CENTER", "CENTER", 0, -SLIDE }, "unknown screen, slid: straight below")
    end,

    ["O1 quest arrow is full size when no echo is behind it"] = function(t)
        local L = N.ArrowLayout(state(nil, { prof = { hasStep = false } }))
        t.eq(L.quest.alpha, 1, "alpha"); t.eq(L.quest.scale, 1, "scale"); t.eq(L.quest.small, false, "small")
        t.eq(L.prof.shown, false, "prof hidden")
        L = N.ArrowLayout(state(nil, { prof = { hasStep = true, mode = "text" } }))
        t.eq(L.quest.alpha, 1, "text-only profession lane leaves the quest arrow alone")
        L = N.ArrowLayout(state({ arrows = { hidden = { prof = true } } }))
        t.eq(L.quest.scale, 1, "hidden echo leaves the quest arrow alone")
    end,

    ["O1 stacked with no quest step: profession step takes the stack's place"] = function(t)
        local L = N.ArrowLayout(state(nil, { quest = {} }))
        t.eq(L.quest.shown, false, "quest hidden")
        t.eq(L.prof.shown, true, "prof shown")
        t.eq(L.prof.look, "pointer", "as a pointer"); t.eq(L.prof.anchor, "screen", "on the screen")
        t.eq(L.prof.tint, "quest", "quest colour meanings"); t.eq(L.prof.alpha, 0.85, "alpha")
        at(t, L.prof.position, STACK_LEFT, STACK_BOTTOM, "stack place")
    end,

    ["O3 stacked text: each arrow's text switch, each text on its own arrow"] = function(t)
        local L = N.ArrowLayout(state(nil))
        t.eq(L.quest.text, true, "quest text on by default"); t.eq(L.prof.text, true, "prof text on by default")
        t.eq(L.prof.anchor, "screen", "prof text placed from its own arrow")
        local saved = N.ArrowApply(nil, { op = "text", key = "prof", on = false }, CTX)
        L = N.ArrowLayout(state(saved))
        t.eq(L.prof.text, false, "prof text off"); t.eq(L.quest.text, true, "quest text untouched")
        t.eq(L.quest.alpha, 1, "stack values unchanged by the text switch")
        saved = N.ArrowApply(saved, { op = "text", key = "prof", on = true }, CTX)
        t.eq(saved.arrows, nil, "text back on leaves nothing saved")
    end,

    ["O4 quest arrow untouched: size, look and colour rule the same in every mode"] = function(t)
        t.eq(N.ARROW_SIZE, 56, "button 56"); t.eq(N.ARROW_ART, 64, "art 64")
        local alone = N.ArrowLayout(state(nil, { prof = {} })).quest
        local sep = N.ArrowLayout(state(separated())).quest
        for _, f in ipairs(FIELDS) do t.eq(sep[f], alone[f], "separate vs alone: " .. f) end
        t.eq(sep.alpha, 1, "full opacity when separate"); t.eq(sep.scale, 1, "full size when separate")
        t.eq(sep.tint, "quest", "tint"); t.eq(sep.faint, false, "not faint"); t.eq(sep.emphasis, "primary", "primary")
        at(t, sep.position, STACK_LEFT, STACK_BOTTOM, "separating does not move the quest arrow")
    end,

    ["O4 colour meanings: grey away, orange 600 yd to green 40 yd, blue inside, red corpse"] = function(t)
        local P = N.ARROW_PALETTE.standard
        t.eq(N.COLOR_NEAR, 40, "near yards"); t.eq(N.COLOR_FAR, 600, "far yards")
        colour(t, P.far[1], P.far[2], P.far[3], { 1, 140 / 255, 26 / 255 }, "orange")
        colour(t, P.near[1], P.near[2], P.near[3], { 51 / 255, 242 / 255, 77 / 255 }, "green")
        colour(t, P.mid[1], P.mid[2], P.mid[3], { 1, 217 / 255, 26 / 255 }, "yellow")
        colour(t, P.away[1], P.away[2], P.away[3], { 158 / 255, 160 / 255, 168 / 255 }, "grey")
        colour(t, P.here[1], P.here[2], P.here[3], { 77 / 255, 166 / 255, 1 }, "blue")
        local r, g, b = N.ArrowColor("zone", 600); colour(t, r, g, b, P.far, "600 yd")
        r, g, b = N.ArrowColor("zone", 5000); colour(t, r, g, b, P.far, "beyond 600 yd")
        r, g, b = N.ArrowColor("zone", 320); colour(t, r, g, b, P.mid, "320 yd")
        r, g, b = N.ArrowColor("zone", 40); colour(t, r, g, b, P.near, "40 yd")
        r, g, b = N.ArrowColor("zone", 0); colour(t, r, g, b, P.near, "inside 40 yd")
        r, g, b = N.ArrowColor("zone", nil); colour(t, r, g, b, P.far, "no distance")
        r, g, b = N.ArrowColor("away", 10); colour(t, r, g, b, P.away, "away")
        r, g, b = N.ArrowColor("here", 900); colour(t, r, g, b, P.here, "here")
        r, g, b = N.ArrowColor("corpse", 100); colour(t, r, g, b, { 1, 0.2, 0.2 }, "corpse")
        r, g, b = N.ArrowColor("zone", 40, N.ARROW_PALETTE.colourBlind)
        colour(t, r, g, b, { 0, 158 / 255, 115 / 255 }, "colour-blind green")
    end,

    ["O4 arrow state: here, away by continent or zone, else zone"] = function(t)
        t.eq(N.ArrowState({ cont = 1, zone = 5 }, { cont = 1, zone = 5 }, true), "here", "here wins")
        t.eq(N.ArrowState({ cont = 1, zone = 5 }, { cont = 2, zone = 5 }), "away", "other continent")
        t.eq(N.ArrowState({ cont = 1, zone = 5 }, { cont = 1, zone = 6 }), "away", "other zone")
        t.eq(N.ArrowState({ cont = 1, zone = 5 }, { cont = 1, zone = 5 }), "zone", "same zone")
        t.eq(N.ArrowState(nil, nil), "zone", "nothing known")
        t.eq(N.ArrowState({ cont = 1 }, { cont = 1, zone = 6 }), "zone", "zone unknown on one side")
    end,

    ["O5 independent placement: each arrow keeps its own saved place"] = function(t)
        local s = separated()
        s = N.ArrowApply(s, { op = "move", key = "prof", point = { "BOTTOMLEFT", "BOTTOMLEFT", 100, 200 } }, CTX)
        local L = N.ArrowLayout(state(s))
        t.eq(L.stacked, false, "separate")
        at(t, L.prof.position, 100, 200, "prof moved")
        at(t, L.quest.position, STACK_LEFT, STACK_BOTTOM, "quest did not move")
        s = N.ArrowApply(s, { op = "move", key = "quest", point = { "BOTTOMLEFT", "BOTTOMLEFT", 700, 300 } }, CTX)
        L = N.ArrowLayout(state(s))
        at(t, L.quest.position, 700, 300, "quest moved")
        at(t, L.prof.position, 100, 200, "prof did not move")
        t.eq(L.prof.anchor, "screen", "prof stands on the screen"); t.eq(L.quest.anchor, "screen", "quest too")
    end,

    ["O5 moving the profession arrow separates it; moving the quest arrow moves the stack"] = function(t)
        local s = N.ArrowApply(nil, { op = "move", key = "quest", point = { "BOTTOMLEFT", "BOTTOMLEFT", 300, 300 } }, CTX)
        local L = N.ArrowLayout(state(s))
        t.eq(L.stacked, true, "still stacked")
        at(t, L.quest.position, 300, 300, "stack moved"); at(t, L.prof.position, 300, 300 - NEST, "the profession arrow went with it")
        s = N.ArrowApply(s, { op = "move", key = "prof", point = { "BOTTOMLEFT", "BOTTOMLEFT", 600, 100 } }, CTX)
        L = N.ArrowLayout(state(s))
        t.eq(L.stacked, false, "now separate"); at(t, L.prof.position, 600, 100, "prof own place")
    end,

    ["O5 first separation stands directly below the quest arrow"] = function(t)
        local s = separated()
        local L = N.ArrowLayout(state(s))
        at(t, L.prof.position, STACK_LEFT, STACK_BOTTOM - 56 - 8, "below, one gap down")
        t.eq(s.arrows.mode, "separate", "mode saved")
        t.ok(s.arrows.points and s.arrows.points.prof ~= nil, "first place saved")
        -- No room below: directly above instead.
        local low = N.ArrowApply(nil, { op = "move", key = "quest", point = { "BOTTOMLEFT", "BOTTOMLEFT", 200, 10 } }, CTX)
        low = N.ArrowApply(low, { op = "mode", mode = "separate" }, CTX)
        at(t, N.ArrowLayout(state(low)).prof.position, 200, 10 + 56 + 8, "above when the bottom edge is in the way")
        -- Separate with no saved place at all still lands below.
        at(t, N.ArrowLayout(state({ arrows = { mode = "separate" } })).prof.position,
            STACK_LEFT, STACK_BOTTOM - 64, "no saved place")
    end,

    ["O6 restack from the menu returns the exact stacked layout"] = function(t)
        local want = N.ArrowLayout(state(nil))
        local s = separated()
        s = N.ArrowApply(s, { op = "move", key = "prof", point = { "CENTER", "CENTER", 250, -90 } }, CTX)
        t.eq(N.ArrowLayout(state(s)).stacked, false, "was separate")
        local r = N.ArrowApply(s, { op = "restack" }, CTX)
        sameLayout(t, N.ArrowLayout(state(r)), want, "restack")
        local m = N.ArrowApply(s, { op = "mode", mode = "stacked" }, CTX)
        sameLayout(t, N.ArrowLayout(state(m)), want, "mode stacked")
        t.ok(r.arrows.points.prof ~= nil, "the separate place is kept for next time")
        local again = N.ArrowApply(r, { op = "mode", mode = "separate" }, CTX)
        local p = N.ArrowLayout(state(again)).prof.position
        local q = N.ArrowLayout(state(s)).prof.position
        for i = 1, 4 do t.eq(p[i], q[i], "separating again returns to the kept place [" .. i .. "]") end
    end,

    ["O6 restack by dropping one arrow on the other (snap 40)"] = function(t)
        local want = N.ArrowLayout(state(nil))
        local s = separated()
        -- 30 px off the quest arrow: inside the snap.
        local r = N.ArrowApply(s, { op = "drop", key = "prof",
            point = { "BOTTOMLEFT", "BOTTOMLEFT", STACK_LEFT + 30, STACK_BOTTOM } }, CTX)
        sameLayout(t, N.ArrowLayout(state(r)), want, "prof dropped on quest")
        -- 40 px off: not inside (strictly less than 40), stays separate there.
        local o = N.ArrowApply(s, { op = "drop", key = "prof",
            point = { "BOTTOMLEFT", "BOTTOMLEFT", STACK_LEFT + 40, STACK_BOTTOM } }, CTX)
        local L = N.ArrowLayout(state(o))
        t.eq(L.stacked, false, "40 px away stays separate")
        at(t, L.prof.position, STACK_LEFT + 40, STACK_BOTTOM, "and stands where dropped")
        -- The echo's slid place, straight below the quest arrow, belongs to
        -- the stack: let go within the snap of it, the two are stacked.
        r = N.ArrowApply(s, { op = "drop", key = "prof",
            point = { "BOTTOMLEFT", "BOTTOMLEFT", STACK_LEFT, STACK_BOTTOM - SLIDE - 39 } }, CTX)
        sameLayout(t, N.ArrowLayout(state(r)), want, "prof dropped 39 px under the slid place")
        o = N.ArrowApply(s, { op = "drop", key = "prof",
            point = { "BOTTOMLEFT", "BOTTOMLEFT", STACK_LEFT, STACK_BOTTOM - SLIDE - 40 } }, CTX)
        L = N.ArrowLayout(state(o))
        t.eq(L.stacked, false, "40 px under the slid place stays separate")
        at(t, L.prof.position, STACK_LEFT, STACK_BOTTOM - SLIDE - 40, "and stands where dropped")
        -- Over the quest arrow there is no place of the stack any more.
        o = N.ArrowApply(s, { op = "drop", key = "prof",
            point = { "BOTTOMLEFT", "BOTTOMLEFT", STACK_LEFT, STACK_BOTTOM + SLIDE } }, CTX)
        t.eq(N.ArrowLayout(state(o)).stacked, false, "one arrow and a gap above: separate")
        -- The quest arrow dropped on the separated profession arrow stacks too.
        local q = N.ArrowApply(s, { op = "drop", key = "quest",
            point = { "BOTTOMLEFT", "BOTTOMLEFT", STACK_LEFT + 10, STACK_BOTTOM - 64 + 10 } }, CTX)
        t.eq(N.ArrowLayout(state(q)).stacked, true, "quest dropped on prof")
        -- While stacked, dropping the quest arrow anywhere just moves the stack.
        local mv = N.ArrowApply(nil, { op = "drop", key = "quest", point = { "BOTTOMLEFT", "BOTTOMLEFT", 50, 100 } }, CTX)
        L = N.ArrowLayout(state(mv))
        t.eq(L.stacked, true, "stack stays a stack"); at(t, L.quest.position, 50, 100, "stack moved")
        at(t, L.prof.position, 50, 100 - NEST, "the echo with it")
        -- Let go too low for the echo's slid place: the place dropped at is
        -- saved, and the two are drawn up from it by what is missing.
        mv = N.ArrowApply(nil, { op = "drop", key = "quest", point = { "BOTTOMLEFT", "BOTTOMLEFT", 50, 50 } }, CTX)
        t.eq(mv.arrows.points.quest, { "BOTTOMLEFT", "BOTTOMLEFT", 50, 50 }, "the dropped place is saved as it is")
        L = N.ArrowLayout(state(mv))
        t.eq(L.stacked, true, "low: stack stays a stack"); at(t, L.quest.position, 50, SLIDE, "low: room kept for the slid place")
        at(t, N.ArrowLayout(state(mv, { prof = { hasStep = false } })).quest.position, 50, 50, "low, quest alone: where dropped")
        t.eq(N.StackSnap(39, 0), true, "39 snaps"); t.eq(N.StackSnap(40, 0), false, "40 does not")
        t.eq(N.StackSnap(30, 30), false, "diagonal 42 does not"); t.eq(N.StackSnap(5, 5, 8), true, "own snap")
    end,

    ["O6 reset returns both arrows to the default stack and keeps text choices"] = function(t)
        local s = separated()
        s = N.ArrowApply(s, { op = "move", key = "quest", point = { "BOTTOMLEFT", "BOTTOMLEFT", 10, 10 } }, CTX)
        s = N.ArrowApply(s, { op = "hide", key = "prof", on = true }, CTX)
        s = N.ArrowApply(s, { op = "text", key = "quest", on = false }, CTX)
        local r = N.ArrowApply(s, { op = "reset" }, CTX)
        local L = N.ArrowLayout(state(r))
        t.eq(L.stacked, true, "stacked"); t.eq(L.prof.shown, true, "shown again")
        at(t, L.quest.position, STACK_LEFT, STACK_BOTTOM, "default place")
        t.eq(L.quest.text, false, "text choice kept")
        t.eq(r.arrows.points, nil, "no saved places"); t.eq(r.arrows.mode, nil, "no saved mode")
    end,

    ["O7 the profession arrow wears the echo's purples by distance, separated or stacked"] = function(t)
        local L = N.ArrowLayout(state(separated()))
        t.eq(L.prof.tint, "echo", "tint"); t.eq(L.prof.pinTint, nil, "the layout has no pinTint field")
        -- Neither entry has a field for map pins or paths, stacked or
        -- separated: the layout says nothing about them.
        for name, layout in pairs({ separated = L, stacked = N.ArrowLayout(state(nil)) }) do
            for _, key in ipairs({ "quest", "prof" }) do
                t.eq(type(layout[key]), "table", name .. ": an entry for " .. key)
                for field in pairs(layout[key]) do
                    local lower = string.lower(tostring(field))
                    t.ok(string.find(lower, "pin", 1, true) == nil and string.find(lower, "path", 1, true) == nil
                        and string.find(lower, "map", 1, true) == nil,
                        name .. ": " .. key .. "." .. tostring(field) .. " is not map or path styling")
                end
            end
        end
        local own = { 0.9, 0.1, 0.9 }
        local P = N.ARROW_PALETTE.standard
        local E = N.ECHO_PALETTE
        -- Lead section 529: Muse's profession purples (RC.PROFESSION).
        colour(t, E.far[1], E.far[2], E.far[3], { 123 / 255, 75 / 255, 166 / 255 }, "echo far purple")
        colour(t, E.mid[1], E.mid[2], E.mid[3], { 143 / 255, 64 / 255, 202 / 255 }, "echo mid purple")
        colour(t, E.near[1], E.near[2], E.near[3], { 163 / 255, 53 / 255, 238 / 255 }, "echo near purple")
        colour(t, E.away[1], E.away[2], E.away[3], { 123 / 255, 75 / 255, 166 / 255 }, "echo away: the dim far purple")
        colour(t, E.here[1], E.here[2], E.here[3], { 163 / 255, 53 / 255, 238 / 255 }, "echo here: the bright near purple")
        local r, g, b, a = N.ArrowPaint(L.prof, "zone", 40, nil, own)
        colour(t, r, g, b, E.near, "bright purple at 40 yd, not the activity's colour"); t.eq(a, N.ECHO_ALPHA, "at the echo's alpha")
        r, g, b = N.ArrowPaint(L.prof, "zone", 600, nil, own); colour(t, r, g, b, E.far, "dim purple at 600 yd")
        r, g, b = N.ArrowPaint(L.prof, "away", 100, nil, own); colour(t, r, g, b, E.away, "greyed away")
        r, g, b = N.ArrowPaint(L.prof, "here", 0, nil, own); colour(t, r, g, b, E.here, "brightest inside")
        -- 250 yd is 0.625 of the way from far to near: a quarter from mid to near.
        local qr, qg, qb, qa = N.ArrowPaint(L.quest, "zone", 250, nil, own)
        colour(t, qr, qg, qb, { P.mid[1] + (P.near[1] - P.mid[1]) * 0.25, P.mid[2] + (P.near[2] - P.mid[2]) * 0.25,
            P.mid[3] + (P.near[3] - P.mid[3]) * 0.25 }, "the quest arrow keeps its own palette")
        t.eq(qa, 1, "quest at full opacity")
        r, g, b = N.ArrowPaint(L.prof, "zone", 250, nil, own)
        local mid250 = { E.mid[1] + (E.near[1] - E.mid[1]) * 0.25, E.mid[2] + (E.near[2] - E.mid[2]) * 0.25,
                         E.mid[3] + (E.near[3] - E.mid[3]) * 0.25 }
        colour(t, r, g, b, mid250, "the same far-to-near step as the quest arrow, in the echo's purples")
        local er, eg, eb = N.EchoColor("zone", 250)
        colour(t, er, eg, eb, mid250, "which is N.EchoColor")
        r, g, b = N.ArrowPaint(L.prof, "zone", 250, N.ARROW_PALETTE.colourBlind, own)
        colour(t, r, g, b, mid250, "whatever the palette")
        -- Stacked, the echo is the same purple at the same alpha.
        local S = N.ArrowLayout(state(nil))
        t.eq(S.prof.tint, "echo", "stacked tint")
        r, g, b, a = N.ArrowPaint(S.prof, "zone", 40, nil, own)
        colour(t, r, g, b, E.near, "stacked echo: purple, not the activity's colour"); t.eq(a, N.ECHO_ALPHA, "stacked echo at its alpha")
        -- With no quest step it is the one pointer, in the quest arrow's colours.
        local alone = N.ArrowLayout(state(nil, { quest = {} }))
        r, g, b, a = N.ArrowPaint(alone.prof, "zone", 40, nil, own)
        colour(t, r, g, b, P.near, "alone: green at 40 yd"); t.eq(a, N.PROF_HOLDER_ALPHA, "alone: at 0.85")
    end,

    ["O8 separated profession arrow stays faint and secondary"] = function(t)
        local L = N.ArrowLayout(state(separated()))
        t.eq(L.prof.faint, true, "faint"); t.eq(L.prof.alpha, N.ECHO_ALPHA, "the echo's alpha")
        t.ok(L.prof.alpha < L.quest.alpha, "lower opacity than the quest arrow")
        t.eq(L.prof.look, "echo", "still the echo"); t.eq(L.prof.emphasis, "secondary", "secondary")
        t.eq(L.prof.scale, 1, "scale"); t.eq(L.prof.behind, false, "not behind anything")
        t.eq(L.quest.faint, false, "quest not faint"); t.eq(L.quest.emphasis, "primary", "quest primary")
    end,

    ["saved layout: round trip through a ZFlowDB.layout-shaped table"] = function(t)
        local db = { schema = 1, settings = {}, layout = { tracker = { x = 4 } } }
        local s = N.ArrowApply(db.layout, { op = "mode", mode = "separate" }, CTX)
        s = N.ArrowApply(s, { op = "move", key = "prof", point = { "TOPRIGHT", "TOPRIGHT", -80, -300 } }, CTX)
        s = N.ArrowApply(s, { op = "move", key = "quest", point = { "CENTER", "CENTER", 0, 100 } }, CTX)
        s = N.ArrowApply(s, { op = "text", key = "prof", on = false }, CTX)
        t.eq(db.layout.arrows, nil, "the table handed in is not touched")
        t.eq(s.tracker.x, 4, "other layout keys are kept")
        local before = N.ArrowLayout(state(s))
        db.layout = deep(s)                      -- what a reload hands back
        local after = N.ArrowLayout(state(db.layout))
        sameLayout(t, after, before, "after reload")
        t.eq(after.stacked, false, "separate survives"); t.eq(after.prof.text, false, "text off survives")
        local a = db.layout.arrows
        t.eq(a.points.prof[1], "TOPRIGHT", "saved anchor"); t.eq(a.points.prof[3], -80, "saved x")
        t.eq(a.points.prof[4], -300, "saved y"); t.eq(a.points.quest[1], "CENTER", "quest anchor")
        t.eq(type(a.mode), "string", "plain values only")
        local function plain(v, path)
            local kind = type(v)
            if kind == "table" then
                for key, value in pairs(v) do
                    t.ok(type(key) == "string" or type(key) == "number", path .. ": a plain key")
                    plain(value, path .. "." .. tostring(key))
                end
            else
                t.ok(kind == "string" or kind == "number" or kind == "boolean", path .. " is a plain value, not a " .. kind)
            end
        end
        plain(db.layout, "layout")
        -- A second pass through read and write changes nothing.
        local again = N.ArrowApply(db.layout, {}, CTX)
        sameLayout(t, N.ArrowLayout(state(again)), before, "idempotent")
    end,

    ["saved layout: missing"] = function(t)
        local want = N.ArrowLayout(state(nil))
        sameLayout(t, N.ArrowLayout(state({})), want, "empty layout")
        sameLayout(t, N.ArrowLayout(state({ arrows = {} })), want, "empty arrows")
        sameLayout(t, N.ArrowLayout(state("junk")), want, "layout not a table")
        sameLayout(t, N.ArrowLayout(state({ arrows = 7 })), want, "arrows not a table")
        local L = N.ArrowLayout(nil)
        t.eq(L.quest.shown, false, "no state: nothing shown"); t.eq(L.stacked, true, "no state: stacked")
        t.ok(L.quest.position ~= nil, "no state: still a position")
        t.eq(L.quest.position, { "TOP", "TOP", 0, -120 }, "no state: the default place")
        t.eq(L.quest.position, N.ARROW_DEFAULT_POINT, "which is the default point of the module")
        local s = N.ArrowSaved(nil)
        t.eq(s.mode, "stacked", "default mode"); t.eq(next(s.points), nil, "no points")
        t.eq(N.ArrowApply(nil, nil, nil).arrows, nil, "apply with nothing at all")
    end,

    ["saved layout: partial"] = function(t)
        local L = N.ArrowLayout(state({ arrows = { mode = "separate", points = { quest = { "BOTTOMLEFT", "BOTTOMLEFT", 300, 400 } } } }))
        at(t, L.quest.position, 300, 400, "quest from saved")
        at(t, L.prof.position, 300, 400 - 64, "prof with no saved place: below the quest arrow")
        L = N.ArrowLayout(state({ arrows = { mode = "separate", points = { prof = { "BOTTOMLEFT", "BOTTOMLEFT", 20, 30 } } } }))
        at(t, L.quest.position, STACK_LEFT, STACK_BOTTOM, "quest default"); at(t, L.prof.position, 20, 30, "prof from saved")
        L = N.ArrowLayout(state({ arrows = { points = { prof = { "BOTTOMLEFT", "BOTTOMLEFT", 20, 30 } } } }))
        t.eq(L.stacked, true, "a saved place without a mode is still stacked")
        at(t, L.prof.position, STACK_LEFT, STACK_BOTTOM - NEST, "and stands with the stack")
        -- At the very top the quest arrow stays at the top edge: the echo
        -- is under it, so nothing of the two leaves the screen.
        L = N.ArrowLayout(state({ arrows = { points = { quest = { "TOP" } } } }))
        at(t, L.quest.position, 472, 744, "anchor only: relative anchor and offsets default")
        at(t, L.prof.position, 472, 744 - NEST, "the echo under the top edge's arrow")
        L = N.ArrowLayout(state({ arrows = { points = { quest = { "TOP", nil, 10 } } } }))
        at(t, L.quest.position, 482, 744, "x only")
        -- At the very bottom the two are moved up, as one, by the slid place.
        L = N.ArrowLayout(state({ arrows = { points = { quest = { "BOTTOM" } } } }))
        at(t, L.quest.position, 472, SLIDE, "bottom edge: up by one arrow and a gap")
        at(t, L.prof.position, 472, SLIDE - NEST, "the echo under it, on the screen")
        L = N.ArrowLayout(state({ arrows = { points = { quest = { "TOP" } } } }, { prof = { hasStep = false } }))
        at(t, L.quest.position, 472, 744, "one arrow: where the single arrow stands")
        L = N.ArrowLayout(state({ arrows = { hidden = { prof = true } } }))
        t.eq(L.prof.shown, false, "hidden alone"); t.eq(L.quest.shown, true, "quest still shown")
    end,

    ["saved layout: out-of-range and unusable values"] = function(t)
        local want = N.ArrowLayout(state(nil))
        local bad = {
            { "NOWHERE", "TOP", 0, 0 }, { "TOP", "NOWHERE", 0, 0 }, { "TOP", "TOP", "left", 0 },
            { "TOP", "TOP", 0, 0 / 0 }, { "TOP", "TOP", math.huge, 0 }, { "TOP", "TOP", 0, -math.huge },
            { 5, "TOP", 0, 0 }, { "TOP", {}, 0, 0 }, "TOP", 12, true, {},
        }
        for i, p in ipairs(bad) do
            local L = N.ArrowLayout(state({ arrows = { points = { quest = p } } }))
            at(t, L.quest.position, STACK_LEFT, STACK_BOTTOM, "bad quest point " .. i .. " reads as the default")
            L = N.ArrowLayout(state({ arrows = { mode = "separate", points = { prof = p } } }))
            at(t, L.prof.position, STACK_LEFT, STACK_BOTTOM - 64, "bad prof point " .. i .. " reads as first separation")
        end
        sameLayout(t, N.ArrowLayout(state({ arrows = { mode = "sideways" } })), want, "unknown mode")
        sameLayout(t, N.ArrowLayout(state({ arrows = { mode = 3, points = "x", hidden = 1, text = "no" } })), want, "wrong types")
        sameLayout(t, N.ArrowLayout(state({ arrows = { hidden = { prof = "yes" }, text = { prof = 0 } } })), want, "only true hides, only false mutes")
        local s = N.ArrowApply({ arrows = { points = { quest = { "TOP", "TOP", 0 / 0, 0 }, other = { "TOP", "TOP", 1, 1 } } } }, {}, CTX)
        t.eq(s.arrows, nil, "unusable values are not written back")
        s = N.ArrowApply(nil, { op = "move", key = "prof", point = { "TOP", "TOP", 0 / 0, 0 } }, CTX)
        t.eq(s.arrows, nil, "a move to an unusable point is ignored")
        s = N.ArrowApply(nil, { op = "move", key = "pet", point = { "TOP", "TOP", 0, 0 } }, CTX)
        t.eq(s.arrows, nil, "an unknown arrow is ignored")
        s = N.ArrowApply(nil, { op = "dance" }, CTX)
        t.eq(s.arrows, nil, "an unknown action is ignored")
    end,

    ["saved layout: an off-screen saved place is clamped back"] = function(t)
        local L = N.ArrowLayout(state({ arrows = { mode = "separate", points = {
            quest = { "BOTTOMLEFT", "BOTTOMLEFT", 5000, 9000 }, prof = { "BOTTOMLEFT", "BOTTOMLEFT", -400, -50 } } } }))
        at(t, L.quest.position, W - 56, H - 56, "quest back to the top right corner")
        at(t, L.prof.position, 0, 0, "prof back to the bottom left corner")
        -- A place saved on a bigger screen, read on this one.
        L = N.ArrowLayout(state({ arrows = { mode = "separate", points = { prof = { "BOTTOMLEFT", "BOTTOMLEFT", 1800, 300 } } } }))
        at(t, L.prof.position, W - 56, 300, "only the off-screen axis moves")
        local p = N.ClampPoint({ "CENTER", "CENTER", 0, 0 }, 56, W, H)
        t.eq(p[1], "CENTER", "anchor kept"); t.eq(p[3], 0, "on-screen x untouched"); t.eq(p[4], 0, "on-screen y untouched")
        p = N.ClampPoint({ "TOPRIGHT", "TOPRIGHT", 30, 30 }, 56, W, H)
        t.eq(p[3], 0, "pulled in x"); t.eq(p[4], 0, "pulled in y")
        local src = { "BOTTOMLEFT", "BOTTOMLEFT", -9, -9 }
        p = N.ClampPoint(src, 56, W, H)
        t.eq(src[3], -9, "the saved table is not changed"); t.ok(p ~= src, "a new table")
        p = N.ClampPoint({ "BOTTOMLEFT", "BOTTOMLEFT", -9, 7000 }, 56)
        t.eq(p[3], -9, "screen unknown: unchanged x"); t.eq(p[4], 7000, "screen unknown: unchanged y")
        t.eq(N.ClampPoint(nil, 56, W, H), nil, "no point")
        -- The saved value itself is clamped when it is written.
        local s = N.ArrowApply(nil, { op = "move", key = "prof", point = { "BOTTOMLEFT", "BOTTOMLEFT", 99999, 10 } }, CTX)
        t.eq(s.arrows.points.prof[3], W - 56, "written clamped")
    end,

    ["gate: off, intro, corpse, open"] = function(t)
        t.eq(N.ArrowGate(false, true, false, true, false), "off", "disabled")
        t.eq(N.ArrowGate(true, false, false, true, false), "off", "not revealed")
        t.eq(N.ArrowGate(true, true, true, false, false), "intro", "intro before position")
        t.eq(N.ArrowGate(true, true, false, false, false), "off", "no position")
        t.eq(N.ArrowGate(true, true, false, true, true), "corpse", "dead")
        t.eq(N.ArrowGate(true, true, false, true, false), "open", "open")
        local L = N.ArrowLayout(state(separated(), { gate = "corpse" }))
        t.eq(L.quest.shown, true, "dead: quest arrow shows"); t.eq(L.prof.shown, false, "dead: profession arrow hides, even separate")
        L = N.ArrowLayout(state(nil, { gate = "corpse" }))
        t.eq(L.quest.alpha, 1, "dead: quest arrow full"); t.eq(L.quest.scale, 1, "dead: quest arrow full size")
        L = N.ArrowLayout(state(nil, { gate = "off" }))
        t.eq(L.quest.shown, false, "off: quest"); t.eq(L.prof.shown, false, "off: prof")
        L = N.ArrowLayout(state(nil, { gate = "intro", quest = {}, prof = {} }))
        t.eq(L.quest.shown, true, "intro shows the quest arrow")
        L = N.ArrowLayout(state(nil, { quest = { overlay = true } }))
        t.eq(L.quest.shown, true, "an overlay alone shows the quest arrow")
    end,

    ["hide: one arrow hidden, the other untouched, and back"] = function(t)
        local s = N.ArrowApply(separated(), { op = "hide", key = "prof", on = true }, CTX)
        local L = N.ArrowLayout(state(s))
        t.eq(L.prof.shown, false, "prof hidden"); t.eq(L.quest.shown, true, "quest shown")
        s = N.ArrowApply(s, { op = "hide", key = "prof", on = false }, CTX)
        t.eq(N.ArrowLayout(state(s)).prof.shown, true, "shown again")
        t.eq(s.arrows.hidden, nil, "nothing left saved for it")
        s = N.ArrowApply(nil, { op = "hide", key = "quest", on = true }, CTX)
        L = N.ArrowLayout(state(s))
        t.eq(L.quest.shown, false, "quest hidden"); t.eq(L.prof.look, "pointer", "profession step stands in")
    end,
}
