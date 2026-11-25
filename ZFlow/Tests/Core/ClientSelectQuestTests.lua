-- c.selectQuest(id) (A1-13, Nav/StepCard.lua "Quest log"): the real client
-- over a hand-built environment, then ClientFake's twin. Made-up quests,
-- test only. Not tested in game.
local _, ns = ...

local tests = {}

local function newEnv()
    local env = {}
    function env.issecretvalue(v)
        if v == nil then error("issecretvalue: nil") end
        return false
    end
    return env
end

tests["client selectQuest: C_QuestLog.SetSelectedQuest picks it"] = function(t)
    local env = newEnv()
    local got
    env.C_QuestLog = { SetSelectedQuest = function(id) got = id end }
    t.eq(ns.make.client(env).selectQuest(33), true)
    t.eq(got, 33)
end

tests["client selectQuest: else SelectQuestLogEntry with its place in the log"] = function(t)
    local env = newEnv()
    local got
    env.GetQuestLogIndexByID = function(id) if id == 33 then return 4 end return 0 end
    env.SelectQuestLogEntry = function(i) got = i end
    local c = ns.make.client(env)
    t.eq(c.selectQuest(33), true)
    t.eq(got, 4)
    t.eq({ c.selectQuest(99) }, { false, "notInLog" })
end

tests["client selectQuest: no call, a bad id, or a raise is false with why"] = function(t)
    t.eq({ ns.make.client(newEnv()).selectQuest(33) }, { false, "noCall" })
    t.eq({ ns.make.client(newEnv()).selectQuest("33") }, { false, "bad" })
    local env = newEnv()
    env.C_QuestLog = { SetSelectedQuest = function() error("no") end }
    t.eq({ ns.make.client(env).selectQuest(33) }, { false, "raised" })
end

tests["fake selectQuest: picks, or says the call is absent"] = function(t)
    local c = ns.make.fakeClient()
    t.eq(c.selectQuest(7), true)
    t.eq(c.selectedQuest(), 7)
    c.setSelectQuestCall(false)
    t.eq({ c.selectQuest(8) }, { false, "noCall" })
end

return tests
