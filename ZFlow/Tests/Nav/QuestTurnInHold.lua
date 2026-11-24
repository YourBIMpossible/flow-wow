-- F-028 (lead DISPATCH section 371, P-HOLD): a turn-in is never routed as
-- ready when the quest's objectives are not read yet (an empty list Questie
-- says should not be empty, or an objective whose text has not come), or a
-- quest before it (Questie preQuestSingle / preQuestGroup, asked at runtime)
-- is not done. Such a turn-in is held and says why, in words, with no place;
-- it is never dropped. Pure picks, then the golden fixture through the real
-- quest watch (N.QuestWatch: log, Questie, Q.Pick) and the quest route
-- (TripRoute.Stops). Made-up quests and a hand-written Questie stand-in.
-- Fails before the change: Q.TurnInHold and Q.HeldLine are nil, the held
-- quests are routed as ready turn-ins. Not tested in game.
local _, ns = ...

local N = ns.Nav
local Q = N.QuestSource

local HERE = { map = 1411, x = 0.5, y = 0.5, cont = 1 }
local NEAR = { points = { { map = 1411, x = 0.5, y = 0.55 } }, name = "Marshal Dughan" }
local FAR = { points = { { map = 1411, x = 0.9, y = 0.9 } }, name = "Gruk" }

local function row(id, title, objectives)
    return { id = id, title = title, complete = true, failed = false, objectives = objectives }
end

local T = {}

T["turn-in hold: the words"] = function(t)
    t.eq(Q.HELD_NOT_READ, "objectives not read yet")
    t.eq(Q.HELD_PREREQ, "a quest before it is not done")
    t.eq(Q.HeldLine(Q.HELD_NOT_READ), "Turn-in held: objectives not read yet")
end

T["turn-in hold: no objectives read yet is held, in words, not ready"] = function(t)
    local r = row(501, "Empty Log", {})
    t.eq(Q.TurnInHold(r, nil), Q.HELD_NOT_READ, "Questie not asked: not known")
    t.eq(Q.TurnInHold(r, { [501] = { objectiveCount = 2 } }), Q.HELD_NOT_READ, "Questie says it has two")
    local step = Q.Pick({ r }, { [501] = { turnIn = NEAR } }, HERE)
    t.eq(step, { quest = 501, objective = nil, turnIn = true, held = true, label = "Empty Log",
                 detail = Q.HeldLine(Q.HELD_NOT_READ), lines = { "Empty Log", Q.HeldLine(Q.HELD_NOT_READ) },
                 still = true }, "held and visible, no place")
end

T["turn-in hold: a quest Questie says has no objectives is a ready turn-in"] = function(t)
    local r = row(502, "A Letter", {})
    t.eq(Q.TurnInHold(r, { [502] = { objectiveCount = 0 } }), nil)
    local step = Q.Pick({ r }, { [502] = { objectiveCount = 0, turnIn = NEAR } }, HERE)
    t.eq(step.turnIn, true)
    t.eq(step.held, nil)
    t.eq(step.detail, "Turn in: Marshal Dughan")
    t.ok(step.place ~= nil, "pointed")
end

T["turn-in hold: an objective whose text has not come is held"] = function(t)
    local r = row(503, "Delayed", { { text = "Tusks: 5/5", done = true }, { done = true } })
    t.eq(Q.TurnInHold(r, nil), Q.HELD_NOT_READ)
    local step = Q.Pick({ r }, { [503] = { turnIn = NEAR } }, HERE)
    t.eq(step.held, true)
    t.eq(step.place, nil)
end

T["turn-in hold: a quest before it not done is held"] = function(t)
    local r = row(504, "Second Part", { { text = "Crate: 1/1", done = true } })
    t.eq(Q.TurnInHold(r, { [504] = { prereqMissing = true } }), Q.HELD_PREREQ)
    local step = Q.Pick({ r }, { [504] = { prereqMissing = true, turnIn = NEAR } }, HERE)
    t.eq(step.held, true)
    t.eq(step.detail, Q.HeldLine(Q.HELD_PREREQ))
end

T["turn-in hold: the nearest ready turn-in wins over a nearer held one"] = function(t)
    local held = row(505, "Held", {})
    local ready = row(506, "Ready", { { text = "Crate: 1/1", done = true } })
    local step = Q.Pick({ held, ready }, { [505] = { turnIn = NEAR }, [506] = { turnIn = FAR } }, HERE)
    t.eq(step.quest, 506)
    t.eq(step.held, nil)
    local log = Q.Pick({ held, ready }, { [505] = { turnIn = NEAR }, [506] = { turnIn = FAR } }, HERE, nil,
        { zoneFirst = false })
    t.eq(log.quest, 505, "log order: the first quest is shown, held")
    t.eq(log.held, true)
end

T["turn-in hold: the quest route keeps a held turn-in as a line, not a stop"] = function(t)
    local stops, left = N.TripRoute.Stops({ row(507, "Held", {}) }, { [507] = { turnIn = NEAR } }, HERE)
    t.eq(#stops, 0, "not routed")
    t.eq(left, { { quest = 507, label = "Held", detail = Q.HeldLine(Q.HELD_NOT_READ), why = Q.HeldLine(Q.HELD_NOT_READ) } })
end

-- The golden fixture: a fake client and a Questie stand-in through the real
-- quest watch.
local function questie()
    local quests = {
        [601] = { ObjectiveData = { { Type = "monster", Id = 9001 } }, Finisher = { NPC = { 9100 } } },
        [602] = { ObjectiveData = { { Type = "monster", Id = 9001 } }, Finisher = { NPC = { 9100 } },
                  preQuestGroup = { 600 } },
        [603] = { ObjectiveData = {}, Finisher = { NPC = { 9100 } }, preQuestSingle = { 598, 599 } },
    }
    local npcs = {
        [9001] = { name = "Young Boar", spawns = { [12] = { { 40, 40 } } } },
        [9100] = { name = "Marshal Dughan", spawns = { [12] = { { 50, 60 } } } },
    }
    local db = {}
    function db.GetQuest(id) return quests[id] end
    function db:GetNPC(id) return npcs[id] end
    function db:GetObject() return nil end
    function db:GetItem() return nil end
    local zones = {}
    function zones:GetUiMapIdByAreaId(area) if area == 12 then return 1411 end return nil end
    local mods = { QuestieDB = db, ZoneDB = zones }
    return function(name) return mods[name] end
end

local function watch(log)
    local c = ns.make.fakeClient()
    c.setZone(1, 1411)
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    c.questLog = function() return log end
    c.questieModule = questie()
    return c, N.QuestWatch(c)
end

T["turn-in hold golden: an empty objective list Questie says has one is held"] = function(t)
    local _, w = watch({ row(601, "Boar Trouble", {}) })
    local step = w.step()
    t.eq(step.quest, 601)
    t.eq(step.held, true)
    t.eq(step.lines, { "Boar Trouble", Q.HeldLine(Q.HELD_NOT_READ) })
    t.eq(step.place, nil, "no needle to a turn-in that may not be ready")
end

T["turn-in hold golden: a prerequisite not done holds; done, it is the turn-in"] = function(t)
    local log = { row(602, "Boar Trouble II", { { text = "Boars slain: 8/8", done = true } }) }
    local c, w = watch(log)
    c.setQuestDone(600, false)
    local step = w.step()
    t.eq(step.held, true)
    t.eq(step.detail, Q.HeldLine(Q.HELD_PREREQ))
    c.setQuestDone(600, true)
    w.refresh()
    step = w.step()
    t.eq(step.held, nil)
    t.eq(step.detail, "Turn in: Marshal Dughan")
    t.eq(step.place, { cont = 1, map = 1411, x = 0.5, y = 0.6 })
end

T["turn-in hold golden: a prerequisite not known is not a hold"] = function(t)
    local _, w = watch({ row(602, "Boar Trouble II", { { text = "Boars slain: 8/8", done = true } }) })
    local step = w.step()
    t.eq(step.held, nil, "the done read gave nothing: not known, not missing")
    t.eq(step.detail, "Turn in: Marshal Dughan")
end

T["turn-in hold golden: one of several before it done is enough; none done holds"] = function(t)
    local c, w = watch({ row(603, "A Letter", {}) })
    c.setQuestDone(598, false); c.setQuestDone(599, false)
    t.eq(w.step().detail, Q.HeldLine(Q.HELD_PREREQ), "no objectives, none before it done")
    c.setQuestDone(599, true)
    w.refresh()
    local step = w.step()
    t.eq(step.held, nil, "Questie says no objectives and one before it is done: ready")
    t.eq(step.detail, "Turn in: Marshal Dughan")
end

return T
