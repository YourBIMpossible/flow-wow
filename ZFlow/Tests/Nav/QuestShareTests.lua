local _, ns = ...
-- Tests for the quest share advice of ZFlow/Nav/QuestAdvice.lua (lead
-- section 354 item 4, P-QUEST groundwork) and the client read it asks,
-- questShareable. Advice text only: nothing here shares a quest.
local tests = {}
local function A() return ns.QuestAdvice or {} end
local function none() return nil end

local function row(id, title, complete, failed)
    return { id = id, title = title, complete = complete, failed = failed, objectives = {} }
end

local function can(map)
    return function(id) return map[id] end
end

tests["quest share: the quests the client says can be shared, in the order of the log"] = function(t)
    local shareable = A().Shareable or none
    local rows = { row(1, "First"), row(2, "Second"), row(3, "Third"), row(4, "Fourth") }
    t.eq(shareable(rows, can({ [1] = true, [2] = false, [4] = true })), { "First", "Fourth" },
        "not known (3) is never said to be shareable")
    t.eq(shareable(rows, nil), {}, "no read: nothing")
    t.eq(shareable(nil, can({})), {})
end

tests["quest share: a complete or failed quest is not offered; a read that raises says nothing"] = function(t)
    local shareable = A().Shareable or none
    local rows = { row(1, "Done", true), row(2, "Failed", false, true), row(3, "Open", false) }
    t.eq(shareable(rows, can({ [1] = true, [2] = true, [3] = true })), { "Open" })
    t.eq(shareable(rows, function() error("Wolves") end), {})
end

tests["quest share: the line only while you are known to be in a group"] = function(t)
    local text = A().ShareText or none
    local rows = { row(1, "First"), row(2, "Second") }
    local both = can({ [1] = true, [2] = true })
    t.eq(text(rows, both, true), "You can share with your group: First, Second. Type " .. ns.id.slash .. " share to offer one.")
    t.eq(text(rows, both, false), nil, "alone")
    t.eq(text(rows, both, nil), nil, "not known whether grouped")
    t.eq(text(rows, can({}), true), nil, "nothing shareable")
end

tests["quest share: the fake client answers what it was told"] = function(t)
    local c = ns.make.fakeClient()
    t.ok(type(c.questShareable) == "function", "the read is there")
    if type(c.questShareable) ~= "function" then return end
    t.eq(c.questShareable(1), nil, "not set: not known")
    c.setQuestShareable(1, true)
    c.setQuestShareable(2, false)
    t.eq(c.questShareable(1), true)
    t.eq(c.questShareable(2), false)
    t.eq(c.questShareable("x"), nil)
end

tests["quest share: the client asks C_QuestLog.IsPushableQuest and nothing else"] = function(t)
    local asked = {}
    local env = { C_QuestLog = { IsPushableQuest = function(id)
        asked[#asked + 1] = id
        if id == 1 then return true end
        if id == 2 then return false end
        if id == 3 then error("refused") end
        return "yes"
    end } }
    local c = ns.make.client(env)
    t.ok(type(c.questShareable) == "function", "the read is there")
    if type(c.questShareable) ~= "function" then return end
    t.eq(c.questShareable(1), true)
    t.eq(c.questShareable(2), false)
    t.eq(c.questShareable(3), nil, "a raise is not known")
    t.eq(c.questShareable(4), nil, "not a yes or no: not known")
    t.eq(c.questShareable("x"), nil)
    t.eq(asked, { 1, 2, 3, 4 })
    t.eq(ns.make.client({}).questShareable(1), nil, "a client without the call: not known")
end

return tests
