-- Tests for the quest route's pick-ups (ZFlow/Nav/RoutePickups.lua; lead
-- section 375 item 7, TN-1): which quests the player can take now, and the
-- nearest few kept. Made-up quests and places, test only. Not tested in game.
local _, ns = ...

local N = ns.Nav
local tests = {}

local MAP = 1436

local function ctx(over)
    local c = { level = 18, log = {}, me = { raceId = 1, classId = 1, faction = "Alliance" },
                done = function() return nil end }
    for k, v in pairs(over or {}) do c[k] = v end
    return c
end

local function q(over)
    local out = { Id = 700, name = "Lost Pages", level = 17, requiredLevel = 12 }
    for k, v in pairs(over or {}) do out[k] = v end
    return out
end

tests["route pickups: a quest at your level, not taken, not done, is a candidate"] = function(t)
    t.eq((N.RoutePickups.Candidate(q(), ctx())), true)
end

tests["route pickups: in the log or done is not a candidate"] = function(t)
    local P = N.RoutePickups
    t.eq((P.Candidate(q(), ctx({ log = { [700] = true } }))), false)
    t.eq((P.Candidate(q(), ctx({ done = function(id) return id == 700 end }))), false)
end

tests["route pickups: above you or far below you is not a candidate"] = function(t)
    local P = N.RoutePickups
    t.eq((P.Candidate(q({ requiredLevel = 19 }), ctx())), false)
    t.eq((P.Candidate(q({ level = 18 + ns.DungeonStates.LEVEL_ABOVE + 1 }), ctx())), false)
    t.eq((P.Candidate(q({ level = 18 - P.BELOW - 1, requiredLevel = 1 }), ctx())), false)
    t.eq((P.Candidate(q({ level = 18 - P.BELOW, requiredLevel = 1 }), ctx())), true)
end

tests["route pickups: another race, class or faction is not a candidate"] = function(t)
    local P = N.RoutePickups
    t.eq((P.Candidate(q({ requiredRaces = 2 }), ctx())), false)
    t.eq((P.Candidate(q({ requiredClasses = 2 }), ctx())), false)
    t.eq((P.Candidate(q({ giverFaction = "H" }), ctx())), false)
end

tests["route pickups: an earlier quest known not done rules it out; not known is kept"] = function(t)
    local P = N.RoutePickups
    local notDone = function(id) if id == 699 then return false end return nil end
    t.eq((P.Candidate(q({ preQuestGroup = { 699 } }), ctx({ done = notDone }))), false)
    t.eq((P.Candidate(q({ preQuestSingle = { 699 } }), ctx({ done = notDone }))), false)
    t.eq((P.Candidate(q({ preQuestSingle = { 699, 698 } }), ctx({ done = notDone }))), true)
    t.eq((P.Candidate(q({ preQuestGroup = { 698 } }), ctx({ done = notDone }))), true)
    t.eq((P.Candidate(q({ exclusiveTo = { 697 } }), ctx({ log = { [697] = true } }))), false)
end

tests["route pickups: the nearest few are kept, nearest first"] = function(t)
    local P = N.RoutePickups
    t.eq(P.MAX, 8)
    local here = { map = MAP, x = 0.5, y = 0.5, size = { w = 1000, h = 1000 } }
    local list = {}
    for i = 1, 10 do list[i] = { quest = i, place = { map = MAP, x = 0.5 + i / 100, y = 0.5 } } end
    list[11] = { quest = 11, place = { map = MAP + 1, x = 0.5, y = 0.5 } }
    local near = P.Nearest(list, here, 3)
    t.eq(#near, 3)
    t.eq({ near[1].quest, near[2].quest, near[3].quest }, { 1, 2, 3 })
    t.eq(#P.Nearest(list, here, P.MAX), 8)
end

tests["route pickups: the stop's words"] = function(t)
    local P = N.RoutePickups
    t.eq(P.LABEL:format("Lost Pages", "Marshal"), "Pick up: Lost Pages (Marshal)")
    t.eq(P.SKIPPED, "skipped: more than 250 yd off the way")
end

-- Class quests (row A2-04; Questie's requiredClasses bitmask, bit n - 1 for
-- class n): one for only the player's class counts whatever the level window.
tests["route pickups: a class quest below the window is a candidate, marked"] = function(t)
    local P = N.RoutePickups
    local cq = q({ level = 18 - P.BELOW - 4, requiredLevel = 1, requiredClasses = 1 })
    t.eq((P.Candidate(cq, ctx())), true)
    t.eq(P.IsClassQuest(cq, ctx().me), true)
    t.eq(P.IsClassQuest(q({ requiredClasses = 1 + 2 }), ctx().me), false)
    t.eq(P.IsClassQuest(q(), ctx().me), false)
end

tests["route pickups: another class's quest, or one waiting on an earlier quest, is not"] = function(t)
    local P = N.RoutePickups
    t.eq((P.Candidate(q({ level = 5, requiredLevel = 1, requiredClasses = 2 }), ctx())), false)
    local notDone = function(id) if id == 699 then return false end return nil end
    t.eq((P.Candidate(q({ level = 5, requiredLevel = 1, requiredClasses = 1, preQuestSingle = { 699 } }),
        ctx({ done = notDone }))), false)
    t.eq((P.Candidate(q({ level = 20, requiredLevel = 19, requiredClasses = 1 }), ctx())), false)
end

tests["route pickups: a class quest is kept past the most plain ones"] = function(t)
    local P = N.RoutePickups
    local here = { map = MAP, x = 0.5, y = 0.5, size = { w = 1000, h = 1000 } }
    local list = {}
    for i = 1, 10 do list[i] = { quest = i, place = { map = MAP, x = 0.5 + i / 100, y = 0.5 } } end
    list[11] = { quest = 11, classQuest = true, place = { map = MAP, x = 0.9, y = 0.9 } }
    local near = P.Nearest(list, here, 3)
    t.eq(#near, 4)
    t.eq(near[1].quest, 11)
    t.eq(P.CLASS_LABEL:format("Lost Pages", "Marshal"), "Pick up your class quest: Lost Pages (Marshal)")
end

return tests
