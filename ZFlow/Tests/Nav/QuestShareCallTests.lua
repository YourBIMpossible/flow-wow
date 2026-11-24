local _, ns = ...
-- G50 (ACTING): the client's share call (Core/Client.lua c.shareQuest) on a
-- made-up game, and the pure pick of Nav/QuestShare.lua. Not tested in game.
local tests = {}

-- A made-up game: quest id to log index, the selection, and what was pushed.
local function game(over)
    local g = { selected = 4, pushed = {}, selects = {} }
    local env = {
        GetQuestLogIndexByID = function(id) return ({ [11] = 2, [12] = 5 })[id] or 0 end,
        GetQuestLogSelection = function() return g.selected end,
        SelectQuestLogEntry = function(i)
            g.selected = i
            g.selects[#g.selects + 1] = i
        end,
        QuestLogPushQuest = function() g.pushed[#g.pushed + 1] = g.selected end,
    }
    for k, v in pairs(over or {}) do env[k] = v or nil end
    return ns.make.client(env), g
end

tests["share call: the log entry of the quest is picked, pushed, and the old pick put back"] = function(t)
    local c, g = game()
    t.eq(c.shareQuest(11), true)
    t.eq(g.pushed, { 2 })
    t.eq(g.selects, { 2, 4 })
    t.eq(g.selected, 4, "the log shows what it showed before")
end

tests["share call: a quest not in the log, or not a number, pushes nothing"] = function(t)
    local c, g = game()
    t.eq({ c.shareQuest(99) }, { nil, "notInLog" })
    t.eq({ c.shareQuest("x") }, { nil, "bad" })
    t.eq(g.pushed, {})
    t.eq(g.selects, {})
end

tests["share call: a client without the calls says so and touches nothing"] = function(t)
    local c, g = game({ QuestLogPushQuest = false })
    t.eq({ c.shareQuest(11) }, { nil, "noCall" })
    t.eq(g.selects, {})
    t.eq({ ns.make.client({}).shareQuest(11) }, { nil, "notInLog" })
end

tests["share call: a raise is said, and the old pick is still put back"] = function(t)
    local c, g = game({ QuestLogPushQuest = function() error("no") end })
    t.eq({ c.shareQuest(11) }, { nil, "raised" })
    t.eq(g.selected, 4)
end

tests["share call: the fake client keeps what was shared and can refuse"] = function(t)
    local c = ns.make.fakeClient()
    c.setQuestLog({ { id = 1, title = "Test wolves" } })
    t.eq(c.shareQuest(1), true)
    t.eq({ c.shareQuest(2) }, { nil, "notInLog" })
    c.setShareRefuse("raised")
    t.eq({ c.shareQuest(1) }, { nil, "raised" })
    t.eq(c.sharedQuests, { 1 })
end

tests["share pick: the first row not yet offered; all offered starts over"] = function(t)
    local S = ns.QuestShare
    local rows = { { id = 1, title = "A" }, { id = 3, title = "C" } }
    t.eq({ S.Pick(rows, {}) }, { rows[1], 1 })
    t.eq({ S.Pick(rows, { [1] = true }) }, { rows[2], 0 })
    t.eq({ S.Pick(rows, { [1] = true, [3] = true }) }, { rows[1], 1, true })
    t.eq(S.Pick({}, {}), nil)
    t.eq(S.Pick(nil, nil), nil)
end

tests["share rows: id and title of each shareable quest, as the advice line names them"] = function(t)
    local A = ns.QuestAdvice
    local rows = { { id = 1, title = "A" }, { id = 2, title = "B", complete = true }, { id = 3, title = "C" } }
    local function can() return true end
    t.eq(A.ShareRows(rows, can), { { id = 1, title = "A" }, { id = 3, title = "C" } })
    t.eq(A.Shareable(rows, can), { "A", "C" })
end

return tests
