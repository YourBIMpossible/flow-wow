local _, ns = ...

-- Lead section 187: the setting nav.zoneFirst (N.LEAVING_SETTING) gets a
-- reader. Q.Pick takes it as opts.zoneFirst. On, or not said: the rules as
-- before, so what is left on the map the player is on comes first. A plain
-- false: the first quest in the log with something left is the step, even
-- when its place is on another map; a point of it on this map is still
-- used when it has one. The quest the player picked out is not changed by
-- it. Made-up quests and places. Not tested in game.

local Q = ns.Nav.QuestSource
local tests = {}

-- Wolves (first in the log) only on map 1420; Boars (second) on 1411,
-- the map the player is on.
local function rows()
    return {
        { id = 303, title = "Wolves", objectives = { { text = "Wolves slain: 0/4" } } },
        { id = 304, title = "Boars", objectives = { { text = "Boars slain: 0/4" } } },
    }
end

local function places()
    return {
        [303] = { objectives = { [1] = { points = {}, elsewhere = true, away = { map = 1420, x = 0.5, y = 0.5 } } } },
        [304] = { objectives = { [1] = { points = { { map = 1411, x = 0.5, y = 0.3 } } } } },
    }
end

local HERE = { map = 1411, x = 0.5, y = 0.5, cont = 1, size = { w = 1000, h = 500 } }

tests["zone first: not said, what is on this map comes first"] = function(t)
    local s, from = Q.Pick(rows(), places(), HERE)
    t.eq(s.quest, 304)
    t.eq(from, "log")
end

tests["zone first: on, what is on this map comes first"] = function(t)
    local s = Q.Pick(rows(), places(), HERE, nil, { zoneFirst = true })
    t.eq(s.quest, 304)
    t.eq(s.place, { cont = 1, map = 1411, x = 0.5, y = 0.3 })
end

tests["zone first: off, the first quest in the log, on another map"] = function(t)
    local s, from = Q.Pick(rows(), places(), HERE, nil, { zoneFirst = false })
    t.eq(s.quest, 303)
    t.eq(s.label, "Wolves")
    t.eq(s.detail, "Wolves slain: 0/4")
    t.eq(s.place, { map = 1420, x = 0.5, y = 0.5 })
    t.eq(from, "log")
end

tests["zone first: off, the first quest with a point here uses its nearest point"] = function(t)
    local r = rows()
    r[1], r[2] = r[2], r[1]
    local p = places()
    p[304].objectives[1].points[2] = { map = 1411, x = 0.5, y = 0.45 }
    local s = Q.Pick(r, p, HERE, nil, { zoneFirst = false })
    t.eq(s.quest, 304)
    t.eq(s.place, { cont = 1, map = 1411, x = 0.5, y = 0.45 })
end

tests["zone first: off, a complete quest first in the log is its turn-in"] = function(t)
    local r = rows()
    r[1].complete = true
    local p = places()
    p[303].turnIn = { points = { { map = 1411, x = 0.1, y = 0.1 } }, name = "Gruk" }
    local s = Q.Pick(r, p, HERE, nil, { zoneFirst = false })
    t.eq(s.quest, 303)
    t.eq(s.turnIn, true)
    t.eq(s.detail, "Turn in: Gruk")
end

tests["zone first: off, a failed or finished quest is passed over"] = function(t)
    local r = rows()
    r[1].failed = true
    t.eq((Q.Pick(r, places(), HERE, nil, { zoneFirst = false })).quest, 304)
    r = rows()
    r[1].objectives[1].done = true
    t.eq((Q.Pick(r, places(), HERE, nil, { zoneFirst = false })).quest, 304)
end

tests["zone first: off, the quest the player picked out still comes first"] = function(t)
    local s, from = Q.Pick(rows(), places(), HERE, { quest = 304 }, { zoneFirst = false })
    t.eq(s.quest, 304)
    t.eq(from, "picked")
end

tests["zone first: off, the watch list in log order"] = function(t)
    local r = rows()
    r[3] = { id = 305, title = "Bats", objectives = { { text = "Bats slain: 0/2" } } }
    local s, from = Q.Pick(r, places(), HERE, { watched = { 304, 303 } }, { zoneFirst = false })
    t.eq(s.quest, 303)
    t.eq(from, "watched")
end

tests["zone first: off, with the player not placed, words as before"] = function(t)
    local s = Q.Pick(rows(), places(), { cont = 1 }, nil, { zoneFirst = false })
    t.eq(s.quest, 303)
    t.eq(s.still, true)
end

tests["zone first: nothing handed in is changed"] = function(t)
    local r, p = rows(), places()
    Q.Pick(r, p, HERE, nil, { zoneFirst = false })
    t.eq(r, rows())
    t.eq(p, places())
end

tests["zone first: the setting name is the one Nav/Leaving.lua names"] = function(t)
    t.eq(ns.Nav.LEAVING_SETTING, "nav.zoneFirst")
end

return tests
