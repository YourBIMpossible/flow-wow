local _, ns = ...
-- The profession (faint) arrow's text: what a click and a hover on it do
-- (A1-22, section 844). Pure Lua 5.1: no client calls; the frame that takes
-- the mouse is drawn elsewhere and asks here.
-- Flow b657e6e5 Modules/Nav/Nav.lua:4415-4431: a left click opened the
-- profession step (N:OpenStop), a right click the arrow's menu, a hover
-- the step's tooltip; all only while there was a profession step.
ns.Nav = ns.Nav or {}
local PT = {}
ns.Nav.ProfArrowText = PT

-- The hit's size and its drop below the text (Flow Nav.lua:4418-4419).
PT.HIT_W, PT.HIT_H, PT.HIT_DROP = 240, 16, 2

local LEFT = { LeftButton = true, left = true }
local RIGHT = { RightButton = true, right = true }

-- state = { step = { lines = { ... } } or nil }.
-- -> "open" (the step card), "menu" (the arrow menu) or nil.
-- Flow Nav.lua:4421-4424: right always opens the menu; left only with a step.
function PT.Click(button, state)
    if button == nil then return nil end
    if RIGHT[button] then return "menu" end
    if LEFT[button] and type(state) == "table" and state.step ~= nil then return "open" end
    return nil
end

-- The tooltip's lines, or nil without a step (Flow Nav.lua:4425-4426).
function PT.Tip(state)
    if type(state) ~= "table" or type(state.step) ~= "table" then return nil end
    local out = { "Profession step" }
    local lines = state.step.lines
    if type(lines) == "table" then
        for i = 1, #lines do out[#out + 1] = tostring(lines[i]) end
    end
    out[#out + 1] = "Left-click: open the step. Right-click: menu."
    return out
end

-- Where the hit goes, from the arrow view (Nav/ArrowView.lua view.prof.text):
-- { shown, to, point, w, h }. Shown while the needle or its bare text shows.
function PT.Hit(view)
    local off = { shown = false, w = PT.HIT_W, h = PT.HIT_H }
    if type(view) ~= "table" or type(view.prof) ~= "table" then return off end
    local p = view.prof
    local text = p.text
    if type(text) ~= "table" or text.shown ~= true or type(text.point) ~= "table" then return off end
    if p.shown ~= true and p.bare ~= true then return off end
    local tp = text.point
    local y = tp[4] or 0
    -- Flow put the hit 2 below the text's own spot; below the arrow it
    -- hangs downwards, so the same 2 is towards the arrow there.
    if tp[1] == "BOTTOM" then y = y - PT.HIT_DROP else y = y + PT.HIT_DROP end
    return { shown = true, to = text.to, point = { tp[1], tp[2], tp[3] or 0, y },
             w = PT.HIT_W, h = PT.HIT_H }
end

return PT
