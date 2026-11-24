local _, ns = ...

-- Lead section 375 item 2: the quest arrow's target. Q.Pick (rule 1 of
-- Nav/QuestSource.lua) points at the nearest open objective on this map:
-- not a done one, not one of a failed quest. On an exact tie the choice is
-- stable: the scan keeps the first point found and replaces it only when a
-- later one is strictly nearer (`d < bestD`), so the first in log order,
-- then in objective order, wins. The header does not promise more than
-- that, so the tie follows the log order and these tests pin it so.
-- Made-up quests and places. Not tested in game.

local Q = ns.Nav.QuestSource
local tests = {}

-- The player in the middle of map 1411, 1000 by 1000 yards.
local HERE = { map = 1411, x = 0.5, y = 0.5, cont = 1, size = { w = 1000, h = 1000 } }

local function pt(x, y) return { map = 1411, x = x, y = y } end

local function quest(id, objectives, more)
    local row = { id = id, title = "Quest " .. id, objectives = objectives }
    for key, v in pairs(more or {}) do row[key] = v end
    return row
end

local function at(x, y) return { points = { pt(x, y) } } end

tests["quest pick: the nearest open objective among several quests"] = function(t)
    local rows = {
        quest(1, { { text = "A" } }),
        quest(2, { { text = "B" }, { text = "C" } }),
        quest(3, { { text = "D" } }),
    }
    local places = {
        [1] = { objectives = { [1] = at(0.5, 0.1) } },
        [2] = { objectives = { [1] = at(0.9, 0.5), [2] = at(0.5, 0.42) } },
        [3] = { objectives = { [1] = at(0.3, 0.5) } },
    }
    local step = Q.Pick(rows, places, HERE)
    t.eq(step.quest, 2)
    t.eq(step.objective, 2)
    t.eq(step.detail, "C")
end

tests["quest pick: a done objective is passed over, however near"] = function(t)
    local rows = { quest(1, { { text = "Done", done = true }, { text = "Open" } }),
                   quest(2, { { text = "Far" } }) }
    local places = {
        [1] = { objectives = { [1] = at(0.5, 0.5), [2] = at(0.5, 0.2) } },
        [2] = { objectives = { [1] = at(0.5, 0.9) } },
    }
    local step = Q.Pick(rows, places, HERE)
    t.eq(step.quest, 1)
    t.eq(step.objective, 2, "the open objective, 300 yd; not the done one under the player")
end

tests["quest pick: a failed quest is passed over, however near"] = function(t)
    local rows = { quest(1, { { text = "Failed" } }, { failed = true }),
                   quest(2, { { text = "Open" } }) }
    local places = {
        [1] = { objectives = { [1] = at(0.5, 0.49) } },
        [2] = { objectives = { [1] = at(0.5, 0.1) } },
    }
    t.eq(Q.Pick(rows, places, HERE).quest, 2)
end

tests["quest pick: an exact tie is the same answer on every call"] = function(t)
    local rows = { quest(1, { { text = "North" } }), quest(2, { { text = "South" } }) }
    local places = {
        [1] = { objectives = { [1] = at(0.5, 0.25) } },
        [2] = { objectives = { [1] = at(0.5, 0.75) } },
    }
    local first = Q.Pick(rows, places, HERE)
    t.eq(first.quest, 1, "the first in the log")
    for _ = 1, 5 do t.eq(Q.Pick(rows, places, HERE), first) end
end

tests["quest pick: an exact tie follows the log order, as the code does"] = function(t)
    local north, south = quest(1, { { text = "North" } }), quest(2, { { text = "South" } })
    local places = {
        [1] = { objectives = { [1] = at(0.5, 0.25) } },
        [2] = { objectives = { [1] = at(0.5, 0.75) } },
    }
    t.eq(Q.Pick({ north, south }, places, HERE).quest, 1)
    t.eq(Q.Pick({ south, north }, places, HERE).quest, 2, "log order flipped: the other one")
end

tests["quest pick: a tie inside one quest is its first objective"] = function(t)
    local rows = { quest(1, { { text = "East" }, { text = "West" } }) }
    local places = { [1] = { objectives = { [1] = at(0.75, 0.5), [2] = at(0.25, 0.5) } } }
    t.eq(Q.Pick(rows, places, HERE).objective, 1)
end

return tests
