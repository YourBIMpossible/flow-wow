local _, ns = ...
-- Parity A1-40 (lead section 864.3): the arrow menu's "Set a waypoint..."
-- row, in the step's level beside "Your waypoint". Plain tables only
-- (UI/ArrowMenu.lua); the click reaches Nav/WayWords.lua api.Prompt
-- through UI/Arrow.lua. Not tested in game.
local tests = {}
local M = ns.ArrowMenu
local T = ns.Settings.Topics

local function find(rows, key)
    for _, r in ipairs(rows) do if r.key == key then return r end end
    return nil
end

tests["arrow menu way box: the step's level offers to set a waypoint"] = function(t)
    local rows = M.StepRow({ step = { name = "Rats" } }).children
    t.eq(find(rows, M.WAY_SET), { key = M.WAY_SET, text = "Set a waypoint (coordinates, or a party member's name)..." })
    t.eq(find(M.StepRow({}).children, M.WAY_SET) ~= nil, true, "also with no step")
end

tests["arrow menu way box: the row asks for the box"] = function(t)
    t.eq(M.Action(M.WAY_SET, {}), { wayPrompt = true })
end

tests["arrow menu way box: every level stays within MENU_MAX"] = function(t)
    local items = M.Items({ step = { name = "Rats" }, travel = { how = "flight" } })
    for _, level in ipairs(M.Counts(items)) do
        t.ok(level.rows <= T.MENU_MAX, level.path .. ": " .. level.rows)
    end
end

return tests
