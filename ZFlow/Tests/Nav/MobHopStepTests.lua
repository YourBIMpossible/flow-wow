local _, ns = ...

-- Tests for ZFlow/Nav/MobHopStep.lua (FLOW-PARITY A2-25, the arrow hook's
-- logic, lead section 674): which kill target a step has, and which mob
-- group the arrow points at as the player works them. Pure parts. Made-up
-- quests, mobs and times.

local tests = {}

local function HS() return ns.Nav.MobHopStep end

tests["mob hop step: a kill objective's mob, from Questie's objective data"] = function(t)
    local quest = { ObjectiveData = { { Type = "monster", Id = 9101 }, { Type = "item", Id = 5 } } }
    t.eq(HS().NpcOf(quest, 1), 9101)
    t.eq(HS().NpcOf(quest, 2), nil, "an item to collect is not a kill target")
    t.eq(HS().NpcOf(quest, 3), nil)
    t.eq(HS().NpcOf(quest, nil), nil, "a turn-in has no objective")
    t.eq(HS().NpcOf(nil, 1), nil)
end

tests["mob hop step: nothing changes until the player first reaches a group"] = function(t)
    local s = {}
    t.eq(HS().Next(s, 3, { now = 10 }), nil, "not in any group yet: the arrow leads the usual way")
    t.eq(s.started, nil)
end

tests["mob hop step: reaching a group starts it; staying idle there moves on"] = function(t)
    local s = {}
    t.eq(HS().Next(s, 3, { inside = 2, now = 100 }), 2, "in group 2: it is the one being worked")
    t.eq(HS().Next(s, 3, { inside = 2, now = 110 }), 2, "still working it")
    local stay = ns.Nav.MobHop.STAY
    t.eq(HS().Next(s, 3, { inside = 2, now = 100 + stay }), 1, "idle a while: on to the first group not worked")
    t.eq(s.worked[2], true)
end

tests["mob hop step: a fight or a loot keeps the group being worked"] = function(t)
    local s = {}
    local stay = ns.Nav.MobHop.STAY
    HS().Next(s, 3, { inside = 1, now = 100 })
    t.eq(HS().Next(s, 3, { inside = 1, now = 100 + stay, busy = 100 + stay - 5 }), 1, "a fight just now: stay")
end

tests["mob hop step: walking out of the group moves on to the next not worked"] = function(t)
    local s = {}
    HS().Next(s, 3, { inside = 1, now = 100 })
    t.eq(HS().Next(s, 3, { now = 105 }), 2, "left group 1: on to group 2")
    t.eq(HS().Next(s, 3, { now = 106 }), 2, "walking to it")
    t.eq(HS().Next(s, 3, { inside = 2, now = 120 }), 2)
    t.eq(HS().Next(s, 3, { now = 125 }), 3)
    HS().Next(s, 3, { inside = 3, now = 130 })
    t.eq(HS().Next(s, 3, { now = 135 }), nil, "every group worked: the usual arrow again")
end

tests["mob hop step: the objective done ends the hop"] = function(t)
    local s = {}
    HS().Next(s, 3, { inside = 1, now = 100 })
    t.eq(HS().Next(s, 3, { inside = 1, now = 101, done = true }), nil)
end

tests["mob hop step: the step the arrow walks, pointed at the group"] = function(t)
    local step = { quest = 401, objective = 1, label = "Boars", place = { map = 1, x = 0.1, y = 0.1 } }
    local groups = { { map = 1, x = 0.6, y = 0.5, n = 4 }, { map = 1, x = 0.7, y = 0.5, n = 3 } }
    local out = HS().Point(step, groups, 2, 140)
    t.eq(out.place, { map = 1, x = 0.7, y = 0.5 })
    t.eq(out.hop, { n = 2, of = 2, yards = 140 })
    t.eq(out.label, "Boars", "the step keeps its own words")
    t.eq(step.place, { map = 1, x = 0.1, y = 0.1 }, "the step handed in is not changed")
end

return tests
