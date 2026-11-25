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

-- Battleground quests (row A2-06; Questie's zoneOrSort): off the route
-- unless the setting is on.
tests["route pickups: a battleground quest is known by its zone or sort"] = function(t)
    local B = N.BattlegroundQuests
    t.eq(B.Is(q({ zoneOrSort = 3277 })), true)
    t.eq(B.Is(q({ zoneOrSort = 2597 })), true)
    t.eq(B.Is(q({ zoneOrSort = 3358 })), true)
    t.eq(B.Is(q({ zoneOrSort = -25 })), true)
    t.eq(B.Is(q({ zoneOrSort = 17 })), false)
    t.eq(B.Is(q()), false)
    t.eq(B.Is(nil), false)
end

tests["route pickups: a battleground quest is a candidate only with the setting on"] = function(t)
    local P = N.RoutePickups
    local bg = q({ zoneOrSort = 3277 })
    local ok, why = P.Candidate(bg, ctx())
    t.eq(ok, false)
    t.eq(why, P.WHY_BATTLEGROUND)
    t.eq((P.Candidate(bg, ctx({ battlegrounds = false }))), false)
    t.eq((P.Candidate(bg, ctx({ battlegrounds = true }))), true)
    t.eq((P.Candidate(q({ zoneOrSort = 17 }), ctx())), true)
end

-- Row A2-03 (lead section 667): pick-ups off the planned route become
-- candidate next steps, nearest first.
local function pick(id, x, y, label)
    return { kind = "pickup", quest = id, label = label or ("Pick up: Q" .. id .. " (Giver)"),
             place = { map = MAP, x = x, y = y } }
end
local HERE = { map = MAP, x = 0.5, y = 0.5, size = { w = 1000, h = 1000 } }

tests["next steps: pick-ups already on the route are left out"] = function(t)
    local route = { stops = { { quest = 801, label = "Pick up: Q801 (Giver)" }, { quest = 5, label = "Rats" } } }
    local out = N.RoutePickups.NextSteps(route, { pick(801, 0.5, 0.6), pick(802, 0.5, 0.7) }, HERE)
    t.eq(#out, 1)
    t.eq(out[1].quest, 802)
end

tests["next steps: nearest first, each with a label and a place"] = function(t)
    local out = N.RoutePickups.NextSteps({ stops = {} },
        { pick(811, 0.9, 0.5), pick(812, 0.55, 0.5), pick(813, 0.7, 0.5) }, HERE)
    t.eq(#out, 3)
    t.eq(out[1].quest, 812)
    t.eq(out[2].quest, 813)
    t.eq(out[3].quest, 811)
    t.eq(out[1].kind, "next")
    t.eq(out[1].label, "Pick up: Q812 (Giver)")
    t.eq(out[1].why, N.RoutePickups.OFF_ROUTE)
    t.eq(out[1].place.x, 0.55)
end

tests["next steps: a pick-up on another map or with no place is not a step"] = function(t)
    local other = pick(821, 0.5, 0.5); other.place.map = MAP + 1
    local none = { kind = "pickup", quest = 822, label = "Pick up: Q822 (Giver)" }
    local out = N.RoutePickups.NextSteps({ stops = {} }, { other, none, pick(823, 0.6, 0.5) }, HERE)
    t.eq(#out, 1)
    t.eq(out[1].quest, 823)
end

tests["next steps: no route keeps every pick-up; bad input gives none"] = function(t)
    t.eq(#N.RoutePickups.NextSteps(nil, { pick(831, 0.6, 0.5) }, HERE), 1)
    t.eq(#N.RoutePickups.NextSteps({ stops = {} }, nil, HERE), 0)
    t.eq(#N.RoutePickups.NextSteps({ stops = {} }, { pick(832, 0.6, 0.5) }, nil), 0)
end

tests["next steps: at most max, ties by quest id"] = function(t)
    local out = N.RoutePickups.NextSteps({ stops = {} },
        { pick(843, 0.6, 0.5), pick(842, 0.4, 0.5), pick(841, 0.5, 0.9) }, HERE, 2)
    t.eq(#out, 2)
    t.eq(out[1].quest, 842)
    t.eq(out[2].quest, 843)
end

-- A2-17 hook (lead sections 667, 680, 820.3): a pick-up an earlier quest or
-- a spell still holds says which, in Nav/StepNeeds.lua words; a need the game
-- cannot answer (SN.UNKNOWN) holds nothing and is never read as "not locked".
tests["route pickups A2-17: the reason names the earlier quest or the spell"] = function(t)
    local P = N.RoutePickups
    local SN = N.StepNeeds
    local names = { [600] = "Old Letters" }
    local why, words
    why, words = P.Candidate(q({ preQuestGroup = { 600 } }), ctx({
        done = function(id) if id == 600 then return false end return nil end,
        questName = function(id) return names[id] end }))
    t.eq(why, false)
    t.eq(words, SN.AFTER:format("Old Letters"), "after the earlier quest, by name")
    why, words = P.Candidate(q({ requiredSpell = 5487 }), ctx({
        spellKnown = function() return false end, spellName = function() return "Bear Form" end }))
    t.eq(why, false)
    t.eq(words, SN.LEARN:format("Bear Form"), "a spell the player does not know holds it, and says which")
    t.eq((P.Candidate(q({ requiredSpell = 5487 }), ctx({ spellKnown = function() return nil end }))), true,
        "a spell the game does not answer for holds nothing")
    t.eq((P.Candidate(q({ preQuestGroup = { 600 } }), ctx())), true,
        "an earlier quest not known holds nothing")
    t.eq((P.Candidate(q({ requiredSpell = 5487 }), ctx({ spellKnown = function() return true end }))), true)
end

return tests
