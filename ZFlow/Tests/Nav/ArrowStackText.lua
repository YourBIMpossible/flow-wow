-- Lead section 387 R2 (zflow-prof-feed): with both arrows stacked, the
-- profession step's text stands ABOVE the stacked arrows and the quest text
-- BELOW, wherever the stack is on the screen, when the lines fit there.
-- Separate arrows keep their own placement. Pure (N.ArrowView); made-up
-- sizes only. Not tested in game.
--
-- Red before the code: stacked, the quest lines went above in the top half
-- of the screen and the profession lines took the other side (section 341).
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

T["stacked: profession text above, quest text below, top or bottom half"] = function(t)
    local low = { arrows = { points = { quest = { "BOTTOMLEFT", "BOTTOMLEFT", 100, 100 } } } }
    for name, layout in pairs({ default = {}, ["bottom half"] = low }) do
        local v = N.ArrowView(state(layout))
        t.eq(v.stacked, true, name .. ": stacked")
        t.eq(v.prof.text.shown, true, name)
        t.eq(v.prof.text.to, "prof", name .. ": on the needle's own frame")
        t.eq(v.prof.text.side, "above", name .. ": the profession step above")
        t.eq(v.prof.text.point, { "BOTTOM", "TOP", 0, 7 }, name .. ": clear of the needle")
        t.eq(v.quest.text.side, "below", name .. ": the quest text below")
        t.eq(v.quest.text.point, { "TOP", "BOTTOM", 0, -7 }, name)
    end
end

T["separate: each arrow keeps its own placement"] = function(t)
    local v = N.ArrowView(state({ arrows = { mode = "separate" } }))
    t.eq(v.prof.text.to, "prof")
    t.eq(v.quest.text.side, "above", "the quest arrow in the top half: above, as before")
    t.eq(v.quest.text.first, 4, "its plain gap")
end

return T
