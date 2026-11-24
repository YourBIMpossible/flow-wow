-- Lead section 476 (it turns section 387 R2 round): with both arrows
-- stacked, the profession arrow is the echo behind and below the quest
-- arrow, so the quest text stands ABOVE the quest arrow and the profession
-- step's text BELOW the echo, wherever the stack is on the screen.
-- Separate arrows keep their own placement. Pure (N.ArrowView); made-up
-- sizes only. Not tested in game.
local _, ns = ...

local N = ns.Nav
local W, H = 1024, 768

local function state(layout)
    return {
        gate = "open", screenW = W, screenH = H, facingKnown = true, layout = layout,
        player = { cont = 1, zone = 10 },
        quest = { hasStep = true, target = { cont = 1, zone = 10 }, distance = 300, textHeight = 28 },
        prof = { hasStep = true, target = { cont = 1, zone = 10 }, distance = 200,
                 bearingKnown = true, own = { 0.2, 0.2, 0.2 }, textHeight = 28 },
    }
end

local T = {}

T["stacked: quest text above, profession text below, top or bottom half"] = function(t)
    local low = { arrows = { points = { quest = { "BOTTOMLEFT", "BOTTOMLEFT", 100, 100 } } } }
    for name, layout in pairs({ default = {}, ["bottom half"] = low }) do
        local v = N.ArrowView(state(layout))
        t.eq(v.stacked, true, name .. ": stacked")
        t.eq(v.prof.behind, true, name .. ": the echo is behind the quest arrow")
        t.eq(v.quest.point[4] - v.prof.point[4], 56 + N.ARROW_GAP, name .. ": and under it, not over it")
        t.eq(v.prof.text.shown, true, name)
        t.eq(v.prof.text.to, "prof", name .. ": on the echo's own frame")
        t.eq(v.prof.text.side, "below", name .. ": the profession step below")
        t.eq(v.prof.text.point, { "TOP", "BOTTOM", 0, -N.TEXT_GAP_BELOW }, name .. ": under the echo, the plain gap")
        t.eq(v.quest.text.side, "above", name .. ": the quest text above")
        t.eq(v.quest.text.point, { "BOTTOM", "TOP", 0, N.TEXT_GAP_ABOVE }, name .. ": over the quest arrow, the plain gap")
    end
end

T["separate: each arrow keeps its own placement"] = function(t)
    local v = N.ArrowView(state({ arrows = { mode = "separate" } }))
    t.eq(v.prof.text.to, "prof")
    t.eq(v.quest.text.side, "above", "the quest arrow in the top half: above, as before")
    t.eq(v.quest.text.first, 4, "its plain gap")
end

return T
