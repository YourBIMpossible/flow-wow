local _, ns = ...
-- Tests for ZFlow/Nav/QuestAdvice.lua (lead section 354 item 4, P-QUEST
-- groundwork): the pure parts, which quests are ready to hand in and the
-- words shown. Advice text only: nothing here accepts or hands in a quest.
local tests = {}
local function A() return ns.QuestAdvice or {} end
local function none() return nil end

local function row(id, title, complete, failed)
    return { id = id, title = title, complete = complete, failed = failed, objectives = {} }
end

tests["quest advice: the quests ready to hand in, in the order of the log"] = function(t)
    local ready = A().Ready or none
    local rows = {
        row(1, "First", true), row(2, "Second", false), row(3, "Third", true),
        row(4, "Failed", true, true), row(5, "Not known"),
    }
    t.eq(ready(rows), { "First", "Third" })
    t.eq(ready({}), {})
    t.eq(ready(nil), {}, "a log not read has nothing ready")
end

tests["quest advice: a title is said once, and a row without one is passed over"] = function(t)
    local ready = A().Ready or none
    t.eq(ready({ row(1, "Same", true), row(2, "Same", true), row(3, "", true), row(4, nil, true), "x" }), { "Same" })
end

tests["quest advice: the names in one line, then how many more"] = function(t)
    local names = A().Names or none
    t.eq(names({ "A" }), "A")
    t.eq(names({ "A", "B", "C" }), "A, B, C")
    t.eq(names({ "A", "B", "C", "D", "E" }), "A, B, C and 2 more")
    t.eq(names({ "A", "B", "C" }, 2), "A, B and 1 more")
    t.eq(names({}), nil)
    t.eq(names(nil), nil)
end

tests["quest advice: the hand-in line"] = function(t)
    local text = A().TurnInText or none
    t.eq(text({ row(1, "First", true), row(2, "Second", false) }), "Ready to hand in: First. Look for the yellow ? over who takes it.")
    t.eq(text({ row(1, "First", true), row(2, "Second", true) }), "Ready to hand in: First, Second. Look for the yellow ? over who takes it.")
    t.eq(text({ row(2, "Second", false) }), nil, "none ready: no line")
    t.eq(text(nil), nil)
end

return tests
