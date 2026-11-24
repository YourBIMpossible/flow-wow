local _, ns = ...

-- End to end (lead section 481, parity rows A1-44 and A1-45): the arrow
-- menu's step level offers "Go here next" for a step with a quest, and,
-- once that quest is on a custom route line, the two Remove rows with
-- Flow's words. Choosing a row asks for the matching Nav/Focus.lua call.
-- Made-up names. Not tested in game.
-- Fails before: the step level has no custom route rows and M.Action
-- returns nil for their keys.

local tests = {}

local function stepLevel(state)
    local M = ns.ArrowMenu
    for _, row in ipairs(M.Items(state)) do
        if row.key == M.STEP then return row.children end
    end
    return {}
end

local function texts(rows)
    local out = {}
    for i, row in ipairs(rows) do out[i] = tostring(row.text) end
    return out
end

local function has(rows, text)
    for _, row in ipairs(rows) do if row.text == text then return true end end
    return false
end

tests["focus menu e2e: a quest step offers Go here next"] = function(t)
    local M = ns.ArrowMenu
    local state = { step = { name = "Wolf Pelts", from = "your route", quest = 701 } }
    local rows = stepLevel(state)
    t.ok(has(rows, M.FOCUS_ADD_TEXT), table.concat(texts(rows), " | "))
    t.ok(not has(rows, M.FOCUS_FROM_TEXT), "no remove row before the quest is on a line")
    t.eq(M.Action(M.FOCUS_ADD, state), { focus = "add", quest = 701 })
end

tests["focus menu e2e: a step on a custom route line offers the two Remove rows"] = function(t)
    local M = ns.ArrowMenu
    local state = { step = { name = "Wolf Pelts", quest = 702 }, focus = { has = true, title = "Last Steps" } }
    local rows = stepLevel(state)
    t.ok(not has(rows, M.FOCUS_ADD_TEXT), table.concat(texts(rows), " | "))
    t.ok(has(rows, "Remove this step and what follows it (custom route)"), table.concat(texts(rows), " | "))
    t.ok(has(rows, "Remove its whole quest line: Last Steps"), table.concat(texts(rows), " | "))
    t.eq(M.Action(M.FOCUS_FROM, state), { focus = "from", quest = 702 })
    t.eq(M.Action(M.FOCUS_LINE, state), { focus = "line", quest = 702 })
end

tests["focus menu e2e: a step with no quest offers no custom route row"] = function(t)
    local M = ns.ArrowMenu
    local state = { step = { name = "Bank", from = "an errand stop" } }
    local rows = stepLevel(state)
    t.ok(not has(rows, M.FOCUS_ADD_TEXT) and not has(rows, M.FOCUS_FROM_TEXT), table.concat(texts(rows), " | "))
    t.eq(M.Action(M.FOCUS_ADD, state), nil)
    t.eq(M.Action(M.FOCUS_LINE, { step = { quest = 9 } }), nil, "remove is not offered off a line")
end

tests["focus menu e2e: the step level stays within the menu's row limit"] = function(t)
    local M = ns.ArrowMenu
    local state = { step = { name = "Wolf Pelts", quest = 702 }, focus = { has = true, title = "Last Steps" } }
    local level = M.Level(M.Items(state), { M.STEP })
    t.ok(#level <= ns.Settings.Topics.MENU_MAX, tostring(#level))
end

return tests
