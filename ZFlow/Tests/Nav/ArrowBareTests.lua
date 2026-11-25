-- A bare arrow (owner decision D2): the frame and its text stay, the arrow
-- art is not drawn. Asked for through N.ArrowAim (bare = true) when the
-- direction is not known; N.ArrowView says it of a profession arrow that
-- is "off" and still has its text to show. Pure: no game client.
local _, ns = ...

local N = ns.Nav

local W, H = 1000, 800
local SEPARATE = { arrows = { mode = "separate" } }

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

local T = {}

T["bare: the body, the shine and the shadow are not drawn, and the arrow does not float"] = function(t)
    local m = N.ArrowMotion()
    N.ArrowAim(m, { turn = 1, bare = true })
    local d = N.ArrowStep(m, 0.1, 3)
    t.eq(d.body, 0)
    t.eq(d.shine, 0)
    t.eq(d.shadow, 0)
    t.eq(d.bodyY, 0)
    t.eq(d.arrived, false, "no ring either: it has not arrived")
end

T["bare: the glow under the arrow stays as it was, so the place is still seen"] = function(t)
    local plain, bare = N.ArrowMotion(), N.ArrowMotion()
    N.ArrowAim(plain, { turn = 1 })
    N.ArrowAim(bare, { turn = 1, bare = true })
    local want = N.ArrowStep(plain, 0.1, 3).pool
    t.ok(type(want) == "number" and want > 0, "a plain arrow has a glow")
    t.eq(N.ArrowStep(bare, 0.1, 3).pool, want)
end

T["bare: an arrow that is not bare is drawn as before"] = function(t)
    local m = N.ArrowMotion()
    N.ArrowAim(m, { turn = 1 })
    local d = N.ArrowStep(m, 0.1, 3)
    t.eq(d.body, 1)
    t.ok(d.shine > 0 and d.shadow > 0)
end

T["bare: it is said afresh at each aim, and the art comes back"] = function(t)
    local m = N.ArrowMotion()
    N.ArrowAim(m, { turn = 1, bare = true })
    t.eq(N.ArrowStep(m, 0.1, 3).body, 0)
    N.ArrowAim(m, { turn = 1 })
    t.eq(N.ArrowStep(m, 0.1, 3.1).body, 1, "an aim without it: drawn again")
    N.ArrowAim(m, { bare = "yes" })
    t.eq(N.ArrowStep(m, 0.1, 3.2).body, 0, "any true value")
    N.ArrowAim(m, nil)
    t.eq(N.ArrowStep(m, 0.1, 3.3).body, 1, "no aim at all: not bare")
end

T["bare: the last turn is kept under it, nothing is made up"] = function(t)
    local m = N.ArrowMotion()
    N.ArrowAim(m, { turn = 1.25, snap = true })
    N.ArrowAim(m, { bare = true })
    t.eq(m.want, 1.25)
    t.eq(N.ArrowStep(m, 0.1, 3).turn, 1.25)
end

T["bare: the arrows drawn from lines draw nothing"] = function(t)
    for _, style in ipairs({ "3d", "flat" }) do
        local m = N.ArrowMotion()
        N.ArrowAim(m, { turn = 1 })
        local s = N.ArrowShapes(style, m, 0.1, 3)
        t.ok(s.nl + s.nd > 0, style .. ": a plain arrow is drawn")
        N.ArrowAim(m, { turn = 1, bare = true })
        s = N.ArrowShapes(style, m, 0.1, 3.1)
        t.eq({ s.nl, s.nd }, { 0, 0 }, style .. ": bare")
        N.ArrowAim(m, { turn = 1 })
        s = N.ArrowShapes(style, m, 0.1, 3.2)
        t.ok(s.nl + s.nd > 0, style .. ": and drawn again after")
    end
end

T["view: a profession arrow that is off with a step is bare, and is not drawn"] = function(t)
    local blind = N.ArrowView(state({ layout = SEPARATE, facingKnown = false }))
    t.eq(blind.prof.mode, "off")
    t.eq(blind.prof.shown, false, "no arrow")
    t.eq(blind.prof.bare, true)
    t.eq(blind.prof.text.shown, true, "its text is shown")
    t.eq(blind.prof.text.to, "prof", "on its own frame")
end

T["view: stacked and off, the text is on the profession arrow's own frame, below; the quest lines above"] = function(t)
    local off = N.ArrowView(state(nil, nil, { bearingKnown = false }))
    t.eq(off.prof.mode, "off")
    t.eq(off.prof.shown, false)
    t.eq(off.prof.bare, true)
    t.eq(off.prof.text.shown, true)
    t.eq(off.prof.text.to, "prof")
    t.eq(off.prof.text.side, "below", "its lines below")
    t.eq(off.prof.text.point, { "TOP", "BOTTOM", 0, -N.TEXT_GAP_BELOW }, "hung under its frame")
    t.eq(off.quest.text.side, "above", "the quest lines above")
    t.eq(off.quest.text.point, { "BOTTOM", "TOP", 0, N.TEXT_GAP_ABOVE }, "stood over the quest arrow")
    t.eq(off.prof.point, off.quest.point, "no echo drawn: its frame on the quest arrow's place")
    -- A quest stop no longer switches the profession arrow off: not bare.
    local onPoint = N.ArrowView(state(nil, { distance = 5 }))
    t.eq(onPoint.prof.mode, "arrow", "the quest step is at its point: it still points")
    t.eq(onPoint.prof.bare, false)
    t.eq(onPoint.prof.text.shown, true)
end

T["view: a profession arrow that points or stands as the ring is not bare"] = function(t)
    t.eq(N.ArrowView(state()).prof.bare, false)
    t.eq(N.ArrowView(state(nil, nil, { here = true })).prof.bare, false)
end

T["view: no step, the setting off, or a shut gate: not bare"] = function(t)
    t.eq(N.ArrowView(state(nil, nil, { hasStep = false, bearingKnown = false })).prof.bare, false)
    t.eq(N.ArrowView(state(nil, nil, { on = false, bearingKnown = false })).prof.bare, false)
    t.eq(N.ArrowView(state({ gate = "off" }, nil, { bearingKnown = false })).prof.bare, false)
    t.eq(N.ArrowView(state({ gate = "corpse" }, nil, { bearingKnown = false })).prof.bare, false)
end

T["view: hidden by the player, an off profession arrow is not bare"] = function(t)
    local hidden = { arrows = { hidden = { prof = true } } }
    t.eq(N.ArrowView(state({ layout = hidden }, nil, { bearingKnown = false })).prof.bare, false)
end

T["view: the quest arrow is never said to be bare here"] = function(t)
    t.eq(N.ArrowView(state()).quest.bare, nil)
end

T["view: stacked and off, the profession arrow's lines take room"] = function(t)
    -- Arrow bottom 20 over the screen bottom: the profession step's two
    -- lines (28) and their gap do not fit under it, so the arrow is moved
    -- up for them. No echo is drawn, so no room is kept for one.
    local low = { arrows = { points = { quest = { "BOTTOM", "BOTTOM", 0, 20 } } } }
    local off = N.ArrowView(state({ layout = low }, { textHeight = 14 }, { textHeight = 28, bearingKnown = false }))
    t.eq(off.prof.mode, "off")
    t.eq(off.prof.text.side, "below", "under the quest arrow")
    t.eq(off.quest.text.side, "above", "the quest line over it")
    t.eq(off.quest.point[4], 28 + N.TEXT_GAP_BELOW, "moved up by the lines and their gap")
    t.eq(off.prof.point, off.quest.point, "the text frame with it")
    -- Arrow top 10 under the screen top: the quest line (14) and its gap
    -- do not fit over it, so the arrow is moved down for them.
    local top = { arrows = { points = { quest = { "TOP", "TOP", 0, -10 } } } }
    off = N.ArrowView(state({ layout = top }, { textHeight = 14 }, { textHeight = 28, bearingKnown = false }))
    t.eq(off.quest.point[4], -(14 + N.TEXT_GAP_ABOVE), "moved down by the quest line and its gap")
    t.eq(off.prof.point, off.quest.point, "the text frame with it")
end

return T
