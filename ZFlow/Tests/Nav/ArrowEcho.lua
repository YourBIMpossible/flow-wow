local _, ns = ...
-- The profession arrow as an echo of the quest arrow (lead section 476,
-- from-muse/SECONDARY-ARROW-ECHO.md sections 3 and 5). The same arrow, the
-- same size, purple and see-through, behind the quest arrow: tucked 12 px
-- under it while both point within 30 degrees of each other, slid straight
-- down to a fixed place below it beyond that. The quest arrow keeps its
-- colours by distance; the echo goes dim far to bright near in its own
-- purples. Pure: layout, view and colour as plain data.
local N = ns.Nav

local W, H = 1000, 800
local SIZE = 56
local DEG = math.pi / 180

local function state(spread, over, profOver)
    local s = {
        gate = "open", screenW = W, screenH = H, facingKnown = true, spread = spread,
        player = { cont = 1, zone = 10 },
        quest = { hasStep = true, target = { cont = 1, zone = 10 }, distance = 300, textHeight = 24 },
        prof = { hasStep = true, target = { cont = 1, zone = 10 }, distance = 200,
                 bearingKnown = true, textHeight = 12 },
    }
    for k, v in pairs(over or {}) do s[k] = v end
    for k, v in pairs(profOver or {}) do s.prof[k] = v end
    return s
end

local function near(t, got, want, msg)
    t.ok(type(got) == "number" and math.abs(got - want) < 1e-9, msg .. " (got " .. tostring(got) .. ")")
end

local function bright(r, g, b) return r + g + b end

local T = {}

T["echo: within 30 degrees it is tucked 12 px under the quest arrow, behind it"] = function(t)
    for _, deg in ipairs({ 0, 12, 30 }) do
        local v = N.ArrowView(state(deg * DEG))
        local q, p = v.quest, v.prof
        t.eq(p.shown, true, deg .. ": the echo is shown")
        t.eq(p.look, "echo", deg .. ": the same arrow, as an echo")
        t.eq(p.behind, true, deg .. ": behind the quest arrow")
        t.eq(p.slid, false, deg .. ": not slid out")
        t.eq(p.point[3], q.point[3], deg .. ": same column")
        t.eq(q.point[4] - p.point[4], N.ECHO_NEST, deg .. ": 12 px down")
        t.eq(p.scale, 1, deg .. ": the same size")
        t.eq(q.scale, 1, deg .. ": the quest arrow keeps its size")
        t.eq(q.alpha, 1, deg .. ": the quest arrow keeps its strength")
    end
    t.eq(N.ECHO_NEST, 12)
    t.eq(N.ECHO_SPREAD, 30 * DEG)
end

T["echo: beyond 30 degrees it slides straight down to a fixed place below"] = function(t)
    local first
    for _, deg in ipairs({ 31, 90, 180 }) do
        local v = N.ArrowView(state(deg * DEG))
        local q, p = v.quest, v.prof
        t.eq(p.look, "echo", deg .. ": still the echo")
        t.eq(p.slid, true, deg .. ": slid out")
        t.eq(p.behind, true, deg .. ": never in front of the quest arrow")
        t.eq(p.point[3], q.point[3], deg .. ": straight down, same column")
        t.eq(q.point[4] - p.point[4], SIZE + N.ARROW_GAP, deg .. ": one arrow and a gap down")
        first = first or p.point[4]
        t.eq(p.point[4], first, deg .. ": the place is fixed")
    end
end

T["echo: the quest arrow does not move when the echo slides out or back"] = function(t)
    local a, b = N.ArrowView(state(5 * DEG)), N.ArrowView(state(120 * DEG))
    t.eq(a.quest.point[3], b.quest.point[3])
    t.eq(a.quest.point[4], b.quest.point[4])
    -- Low on the screen too, where the room below is made by moving up.
    local low = { arrows = { points = { quest = { "BOTTOM", "BOTTOM", 0, 10 } } } }
    a, b = N.ArrowView(state(5 * DEG, { layout = low })), N.ArrowView(state(120 * DEG, { layout = low }))
    t.eq(a.quest.point[4], b.quest.point[4], "low: the same place")
    local _, bottom = N.ArrowCorner(b.prof.point, SIZE, W, H)
    t.ok(bottom - 12 - N.TEXT_GAP_BELOW >= 0, "low: the echo and its line stay on the screen")
end

T["echo: with the two bearings unknown it stands slid out, not on the quest arrow"] = function(t)
    local v = N.ArrowView(state(nil))
    t.eq(v.prof.slid, true)
    t.eq(v.quest.point[4] - v.prof.point[4], SIZE + N.ARROW_GAP)
end

T["echo: near 30 degrees it keeps the side it was on, so it does not flicker"] = function(t)
    t.eq(N.ArrowView(state(33 * DEG, { echoSlid = false })).prof.slid, false, "was tucked: stays to 35")
    t.eq(N.ArrowView(state(36 * DEG, { echoSlid = false })).prof.slid, true, "past 35: out")
    t.eq(N.ArrowView(state(27 * DEG, { echoSlid = true })).prof.slid, true, "was out: stays to 25")
    t.eq(N.ArrowView(state(24 * DEG, { echoSlid = true })).prof.slid, false, "under 25: back")
end

T["echo: the quest lines stand above the quest arrow, the echo's lines below the echo"] = function(t)
    for _, deg in ipairs({ 10, 90 }) do
        local v = N.ArrowView(state(deg * DEG))
        t.eq(v.quest.text.to, "quest"); t.eq(v.quest.text.side, "above", deg .. ": quest lines above")
        t.eq(v.prof.text.to, "prof"); t.eq(v.prof.text.side, "below", deg .. ": echo lines below")
        t.eq(v.prof.text.shown, true)
    end
end

T["echo: a step in words only draws no echo and its lines stand under the quest arrow"] = function(t)
    local v = N.ArrowView(state(nil, nil, { bearingKnown = false }))
    t.eq(v.prof.shown, false); t.eq(v.prof.bare, true)
    t.eq(v.prof.point[4], v.quest.point[4], "its frame on the quest arrow's place")
    t.eq(v.prof.text.side, "below")
end

T["echo: separated it is still the echo, at its own place, in front of nothing"] = function(t)
    local v = N.ArrowView(state(10 * DEG, { layout = { arrows = { mode = "separate" } } }))
    t.eq(v.prof.look, "echo"); t.eq(v.prof.behind, false); t.eq(v.prof.slid, false)
    t.eq(v.stacked, false)
end

T["echo: with no quest arrow the profession step is the one plain arrow"] = function(t)
    local s = state(nil); s.quest.hasStep = false
    local v = N.ArrowView(s)
    t.eq(v.quest.shown, false); t.eq(v.prof.shown, true)
    t.eq(v.prof.look, "pointer"); t.eq(v.prof.behind, false)
end

T["echo: never a third arrow: the layout has the quest arrow and the echo, no needle"] = function(t)
    t.eq(#N.ARROW_KEYS, 2)
    for _, layout in ipairs({ false, { arrows = { mode = "separate" } } }) do
        for _, deg in ipairs({ 0, 90 }) do
            local v = N.ArrowView(state(deg * DEG, { layout = layout or nil }))
            local n = 0
            for key, ops in pairs(v) do
                if type(ops) == "table" then
                    n = n + 1
                    t.ok(key == "quest" or key == "prof", "only the two")
                    t.ok(ops.look ~= "needle", "no needle")
                end
            end
            t.eq(n, 2)
        end
    end
end

T["echo colour: dim far to bright near in purple, never one flat colour"] = function(t)
    local last
    for _, d in ipairs({ 900, 600, 450, 320, 180, 40, 10 }) do
        local r, g, b = N.EchoColor("zone", d)
        t.ok(g < r and r < b, d .. " yd: purple (green lowest, blue highest)")
        local now = bright(r, g, b)
        if last then t.ok(now >= last, d .. " yd: no dimmer than farther away") end
        last = now
    end
    local fr, fg, fb = N.EchoColor("zone", N.COLOR_FAR)
    local mr, mg, mb = N.EchoColor("zone", (N.COLOR_FAR + N.COLOR_NEAR) / 2)
    local nr, ng, nb = N.EchoColor("zone", N.COLOR_NEAR)
    t.ok(bright(mr, mg, mb) > bright(fr, fg, fb) + 0.2, "half way is clearly brighter than far")
    t.ok(bright(nr, ng, nb) > bright(mr, mg, mb) + 0.2, "near is clearly brighter than half way")
    local hr, hg, hb = N.EchoColor("here", 0)
    t.ok(hg < hr and hr <= hb, "at its own step: still purple")
    t.ok(bright(hr, hg, hb) >= bright(nr, ng, nb), "and the brightest")
    local ar, ag, ab = N.EchoColor("away", 100)
    t.ok(ag < ar and ar < ab, "another zone: a greyed purple")
end

T["echo colour: the view paints the echo by its own distance, the ring at its own step"] = function(t)
    local far = N.ArrowView(state(10 * DEG, nil, { distance = 600 })).prof
    local close = N.ArrowView(state(10 * DEG, nil, { distance = 40 })).prof
    local fr, fg, fb = N.EchoColor("zone", 600)
    local nr, ng, nb = N.EchoColor("zone", 40)
    near(t, far.colour[1], fr, "far r"); near(t, far.colour[2], fg, "far g"); near(t, far.colour[3], fb, "far b")
    near(t, close.colour[1], nr, "near r"); near(t, close.colour[2], ng, "near g"); near(t, close.colour[3], nb, "near b")
    t.eq(far.alpha, N.ECHO_ALPHA, "see-through"); t.ok(N.ECHO_ALPHA < 1 and N.ECHO_ALPHA >= 0.5)
    -- A colour of the activity no longer replaces it.
    local own = N.ArrowView(state(10 * DEG, nil, { distance = 600, own = { 0.2, 0.9, 0.2 } })).prof
    near(t, own.colour[2], fg, "own colour not used")
    local ring = N.ArrowView(state(10 * DEG, nil, { distance = 5 })).prof
    local hr, hg, hb = N.EchoColor("here", 5)
    t.eq(ring.mode, "ring"); t.eq(ring.alpha, N.PROF_RING_ALPHA)
    near(t, ring.colour[1], hr, "ring r"); near(t, ring.colour[2], hg, "ring g"); near(t, ring.colour[3], hb, "ring b")
end

T["echo colour: the quest arrow's colours by distance are what they were"] = function(t)
    local P = N.ARROW_PALETTE.standard
    local function is(d, want, msg)
        local r, g, b = N.ArrowColor("zone", d)
        near(t, r, want[1], msg .. " r"); near(t, g, want[2], msg .. " g"); near(t, b, want[3], msg .. " b")
    end
    is(600, P.far, "600 yd orange"); is(320, P.mid, "320 yd yellow"); is(40, P.near, "40 yd green")
    near(t, P.far[1], 1, "FF"); near(t, P.far[2], 0x8C / 255, "8C"); near(t, P.far[3], 0x1A / 255, "1A")
    near(t, P.near[1], 0x33 / 255, "33"); near(t, P.near[2], 0xF2 / 255, "F2"); near(t, P.near[3], 0x4D / 255, "4D")
    -- With the echo beside it, the same.
    for _, d in ipairs({ 600, 320, 40 }) do
        local s = state(90 * DEG); s.quest.distance = d
        local c = N.ArrowView(s).quest.colour
        local r, g, b = N.ArrowColor("zone", d)
        near(t, c[1], r, d .. " r"); near(t, c[2], g, d .. " g"); near(t, c[3], b, d .. " b")
    end
end

T["echo: let go near the quest arrow or near its place below, it is stacked again"] = function(t)
    local ctx = { screenW = W, screenH = H }
    local apart = { arrows = { mode = "separate", points = { prof = { "BOTTOMLEFT", "BOTTOMLEFT", 100, 100 } } } }
    -- The default stack: left 472, bottom 624.
    local onQuest = N.ArrowApply(apart, { op = "drop", key = "prof", point = { "BOTTOMLEFT", "BOTTOMLEFT", 480, 630 } }, ctx)
    t.eq(N.ArrowSaved(onQuest).mode, "stacked", "near the quest arrow")
    local slot = 624 - (SIZE + N.ARROW_GAP)
    local onSlot = N.ArrowApply(apart, { op = "drop", key = "prof", point = { "BOTTOMLEFT", "BOTTOMLEFT", 480, slot - 10 } }, ctx)
    t.eq(N.ArrowSaved(onSlot).mode, "stacked", "near its place below")
    local off = N.ArrowApply(apart, { op = "drop", key = "prof", point = { "BOTTOMLEFT", "BOTTOMLEFT", 472, slot - 60 } }, ctx)
    t.eq(N.ArrowSaved(off).mode, "separate", "farther than the snap: its own place")
    t.eq(N.STACK_SNAP, 40)
end

return T
