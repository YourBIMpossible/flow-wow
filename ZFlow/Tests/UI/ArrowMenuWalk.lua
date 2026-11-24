local _, ns = ...
-- Parity B-30 (lead section 455): the arrow menu's "Walk there instead"
-- row, under the step row. Plain tables only (UI/ArrowMenu.lua); the click
-- reaches Nav/Travel.lua through UI/Arrow.lua. Not tested in game.
local tests = {}
local M = ns.ArrowMenu

local function stepLevel(travel)
    return M.StepRow({ step = { name = "Rats" }, travel = travel }).children
end

local function find(rows, key)
    for _, r in ipairs(rows) do if r.key == key then return r end end
    return nil
end

tests["arrow menu walk: a step with a shortcut offers to walk there instead"] = function(t)
    local rows = stepLevel({ how = "flight", skipped = false })
    t.eq(rows[#rows], { key = M.WALK, text = "Walk there instead" }, "last in the step's level")
    t.eq(M.Action(M.WALK, { travel = { how = "flight" } }), { walk = true })
end

tests["arrow menu walk: walking past it offers the shortcut back"] = function(t)
    local rows = stepLevel({ how = nil, skipped = true })
    t.eq(rows[#rows], { key = M.WALK, text = "Show the shortcut again" })
    t.eq(M.Action(M.WALK, { travel = { skipped = true } }), { walk = false })
end

tests["arrow menu walk: no shortcut, no row, and the key asks for nothing"] = function(t)
    t.eq(find(stepLevel({ how = nil, skipped = false }), M.WALK), nil)
    t.eq(find(stepLevel(nil), M.WALK), nil, "no step read")
    t.eq(M.Action(M.WALK, {}), nil)
end

tests["arrow menu walk: the step's level stays within the menu's size"] = function(t)
    t.ok(#stepLevel({ how = "spell" }) + 2 <= ns.Settings.Topics.MENU_MAX, "with its heading and the way back")
end

return tests
