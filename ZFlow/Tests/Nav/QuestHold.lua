-- Tests for holding hard and elite quests off the solo route (C-12,
-- ZFlow/Nav/QuestHold.lua). Made-up levels, test only. Not tested in game.
local _, ns = ...

local tests = {}

local function held(over)
    local a = { level = 18, elite = false, myLevel = 18, grouped = false, on = true }
    for k, v in pairs(over or {}) do a[k] = v end
    return ns.Nav.QuestHold.Held(a)
end

tests["quest hold: the rule's numbers"] = function(t)
    t.eq(ns.Nav.QuestHold.HARD_ABOVE, 3)
    t.eq(ns.Nav.QuestHold.ELITE_SOLO_ABOVE, 3)
    t.eq(ns.Nav.QuestHold.SETTING, "nav.holdHard")
end

tests["quest hold: solo, a quest 3 levels above you is held until within 2"] = function(t)
    local h, why = held({ level = 21 })
    t.eq(h, true)
    t.eq(why, "hard: level 21, held until you are 19")
    t.eq((held({ level = 20 })), false)
end

tests["quest hold: solo, an elite quest is held until 3 levels above it"] = function(t)
    local h, why = held({ level = 17, elite = true })
    t.eq(h, true)
    t.eq(why, "elite: held until you are 20")
    t.eq((held({ level = 15, elite = true })), false)
end

tests["quest hold: grouped, nothing is held"] = function(t)
    t.eq((held({ level = 21, grouped = true })), false)
    t.eq((held({ level = 17, elite = true, grouped = true })), false)
end

tests["quest hold: setting off, nothing is held"] = function(t)
    t.eq((held({ level = 21, on = false })), false)
    t.eq((held({ level = 17, elite = true, on = false })), false)
end

tests["quest hold: an unknown tag or level is not held"] = function(t)
    local H = ns.Nav.QuestHold
    t.eq((H.Held({ level = 18, myLevel = 18 })), false)
    t.eq((H.Held({ elite = true, myLevel = 18 })), false)
    t.eq((H.Held({ level = 18, elite = true })), false)
    t.eq((ns.Nav.QuestHold.Held(nil)), false)
end

return tests
