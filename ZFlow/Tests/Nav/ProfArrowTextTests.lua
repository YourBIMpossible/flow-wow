-- A1-22: the profession arrow's text: what a click and a hover on it do
-- (Nav/ProfArrowText.lua). Pure: no game client.
local _, ns = ...

local tests = {}

local function PT() return ns.Nav.ProfArrowText end

local STEP = { lines = { "Train Journeyman Skinning", "120 yards" } }

tests["prof text: a left click with a step opens it"] = function(t)
    t.eq(PT().Click("LeftButton", { step = STEP }), "open", "left opens the step")
    t.eq(PT().Click("left", { step = STEP }), "open", "the short name too")
end

tests["prof text: a left click without a step does nothing"] = function(t)
    t.eq(PT().Click("LeftButton", {}), nil, "no step")
    t.eq(PT().Click("LeftButton", nil), nil, "no state")
end

tests["prof text: a right click opens the menu"] = function(t)
    t.eq(PT().Click("RightButton", { step = STEP }), "menu", "with a step")
    t.eq(PT().Click("right", {}), "menu", "without a step too")
end

tests["prof text: another button does nothing"] = function(t)
    t.eq(PT().Click("MiddleButton", { step = STEP }), nil, "middle")
    t.eq(PT().Click(nil, { step = STEP }), nil, "none")
end

tests["prof text: no tooltip without a step"] = function(t)
    t.eq(PT().Tip({}), nil, "no step")
    t.eq(PT().Tip(nil), nil, "no state")
end

-- Plexy CHANGES-1 (section 852): the left click is named only when the
-- caller says opening works; else the hint is the right click alone.
tests["prof text: the tooltip is the header, the step lines, then the hint"] = function(t)
    local out = PT().Tip({ step = STEP }, true)
    t.ok(type(out) == "table", "lines")
    t.eq(#out, 4, "four lines")
    t.eq(out[1], PT().HEADER, "header")
    t.eq(out[2], "Train Journeyman Skinning", "first step line")
    t.eq(out[3], "120 yards", "second step line")
    t.eq(out[4], PT().HINT_OPEN, "hint names both clicks")
end

tests["prof text: with nothing to open the hint names the right click only"] = function(t)
    for _, canOpen in ipairs({ false, "yes" }) do
        local out = PT().Tip({ step = STEP }, canOpen)
        t.eq(out and out[#out], PT().HINT_MENU, "right click only")
    end
    local plain = PT().Tip({ step = STEP })
    t.eq(plain and plain[#plain], PT().HINT_MENU, "not said: right click only")
    t.ok(type(PT().HINT_MENU) == "string" and PT().HINT_MENU ~= PT().HINT_OPEN, "two hints")
end

tests["prof text: no hit while the text is off"] = function(t)
    local view = { prof = { shown = true, text = { shown = false, to = "prof",
        point = { "TOP", "BOTTOM", 0, -2 } } } }
    t.eq(PT().Hit(view).shown, false, "text off")
    t.eq(PT().Hit(nil).shown, false, "no view")
    view.prof.text.shown = true
    view.prof.shown = false
    t.eq(PT().Hit(view).shown, false, "arrow hidden and not bare")
end

tests["prof text: the hit sits where the text hangs, bare included"] = function(t)
    local view = { prof = { shown = false, bare = true, text = { shown = true, to = "quest",
        point = { "BOTTOM", "TOP", 0, 4 } } } }
    local hit = PT().Hit(view)
    t.eq(hit.shown, true, "bare arrow with text")
    t.eq(hit.to, "quest", "stacked: on the quest frame")
    t.eq(hit.point[1], "BOTTOM", "above")
    t.eq(hit.point[4], 2, "two lower than the text, as Flow")
    t.eq(hit.w, 240, "width")
    t.eq(hit.h, 16, "height")
end

return tests
