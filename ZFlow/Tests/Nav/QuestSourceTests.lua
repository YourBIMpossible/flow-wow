-- The quest source (S43): which of the player's own quests the quest arrow
-- points at. Pure: hand-written quest-log rows and places, no game client,
-- no Questie.
local _, ns = ...

local N = ns.Nav
local Q = N.QuestSource

-- The player in the middle of map 1411, 1000 by 500 yards.
local HERE = { map = 1411, x = 0.5, y = 0.5, cont = 1, size = { w = 1000, h = 500 } }

local function boars(more)
    local row = { id = 101, title = "Boar Trouble", objectives = {
        { text = "Boars slain: 2/8", done = false },
        { text = "Tusks: 5/5", done = true },
    } }
    for key, v in pairs(more or {}) do row[key] = v end
    return row
end

local function letter(more)
    local row = { id = 202, title = "A Letter Home", complete = true, objectives = {
        { text = "Letter delivered: 1/1", done = true },
    } }
    for key, v in pairs(more or {}) do row[key] = v end
    return row
end

local function pt(x, y, map) return { map = map or 1411, x = x, y = y } end

local T = {}

T["quest source: the words are the ones agreed"] = function(t)
    t.eq(Q.SETTING, "quest.arrow")
    t.eq(Q.UNKNOWN_PLACE, "location unknown")
    t.eq(Q.ELSEWHERE, "on another map")
    t.eq(Q.TurnInLine(nil), "Turn in")
    t.eq(Q.TurnInLine(""), "Turn in")
    t.eq(Q.TurnInLine("Marshal Dughan"), "Turn in: Marshal Dughan")
end

T["quest source: no log, an empty log, a log with nothing left to do: no step"] = function(t)
    t.eq(Q.Pick(nil, nil, HERE), nil)
    t.eq(Q.Pick({}, {}, HERE), nil)
    t.eq(Q.Pick({ { id = 1, title = "Done", objectives = { { text = "x", done = true } } } }, nil, HERE), nil,
        "every objective done, not marked complete: nothing is made up")
end

T["quest source: the nearest point of an unfinished objective on this map"] = function(t)
    local places = { [101] = { objectives = {
        [1] = { points = { pt(0.5, 0.1), pt(0.5, 0.3), pt(0.9, 0.5) } },
        [2] = { points = { pt(0.5, 0.49) } },
    } } }
    local step = Q.Pick({ boars() }, places, HERE)
    t.eq(step, { quest = 101, objective = 1, turnIn = false, label = "Boar Trouble",
                 detail = "Boars slain: 2/8", place = { cont = 1, map = 1411, x = 0.5, y = 0.3 } },
        "100 yd north; the done objective right beside the player is not a step")
end

T["quest source: nearest is in yards when the map size is known"] = function(t)
    -- 0.15 of 1000 yd east is 150 yd; 0.2 of 500 yd north is 100 yd.
    local places = { [101] = { objectives = { [1] = { points = { pt(0.65, 0.5), pt(0.5, 0.3) } } } } }
    t.eq(Q.Pick({ boars() }, places, HERE).place, { cont = 1, map = 1411, x = 0.5, y = 0.3 })
    local noSize = { map = 1411, x = 0.5, y = 0.5, cont = 1 }
    t.eq(Q.Pick({ boars() }, places, noSize).place, { cont = 1, map = 1411, x = 0.65, y = 0.5 },
        "no size: by shares of the map")
end

T["quest source: the nearest objective across quests"] = function(t)
    local wolves = { id = 303, title = "Wolves at the Door", objectives = { { text = "Wolves slain: 0/4" } } }
    local places = {
        [101] = { objectives = { [1] = { points = { pt(0.5, 0.1) } } } },
        [303] = { objectives = { [1] = { points = { pt(0.5, 0.4) } } } },
    }
    local step = Q.Pick({ boars(), wolves }, places, HERE)
    t.eq(step.quest, 303)
    t.eq(step.label, "Wolves at the Door")
    t.eq(step.detail, "Wolves slain: 0/4")
end

T["quest source: an objective wins over a turn-in, however near the turn-in is"] = function(t)
    local places = {
        [101] = { objectives = { [1] = { points = { pt(0.1, 0.1) } } } },
        [202] = { turnIn = { points = { pt(0.5, 0.5) }, name = "Marshal Dughan" } },
    }
    t.eq(Q.Pick({ letter(), boars() }, places, HERE).quest, 101)
end

T["quest source: with no objective on this map, the nearest turn-in of a complete quest"] = function(t)
    local places = {
        [101] = { objectives = { [1] = { points = {}, elsewhere = true } } },
        [202] = { turnIn = { points = { pt(0.5, 0.9), pt(0.5, 0.6) }, name = "Marshal Dughan" } },
    }
    local step = Q.Pick({ boars(), letter() }, places, HERE)
    t.eq(step, { quest = 202, turnIn = true, label = "A Letter Home", detail = "Turn in: Marshal Dughan",
                 place = { cont = 1, map = 1411, x = 0.5, y = 0.6 } })
end

T["quest source: a turn-in with no name known says only that"] = function(t)
    local places = { [202] = { turnIn = { points = { pt(0.5, 0.6) } } } }
    t.eq(Q.Pick({ letter() }, places, HERE).detail, "Turn in")
end

T["quest source: a quest that is not complete has no turn-in step"] = function(t)
    local places = { [101] = { turnIn = { points = { pt(0.5, 0.6) } } } }
    local step = Q.Pick({ boars() }, places, HERE)
    t.eq(step.place, nil)
    t.eq(step.lines, { "Boar Trouble", "Boars slain: 2/8", Q.UNKNOWN_PLACE })
end

T["quest source: no places at all: the first quest in words, location unknown, no place"] = function(t)
    local step = Q.Pick({ boars(), letter() }, nil, HERE)
    t.eq(step, { quest = 101, objective = 1, turnIn = false, label = "Boar Trouble", detail = "Boars slain: 2/8",
                 lines = { "Boar Trouble", "Boars slain: 2/8", "location unknown" }, still = true })
end

T["quest source: an objective on another map is words only, and says so"] = function(t)
    local places = { [101] = { objectives = { [1] = { points = {}, elsewhere = true } } } }
    local step = Q.Pick({ boars() }, places, HERE)
    t.eq(step.place, nil)
    t.eq(step.still, true)
    t.eq(step.lines, { "Boar Trouble", "Boars slain: 2/8", "on another map" })
end

T["quest source: a point on another map is never pointed at"] = function(t)
    local places = { [101] = { objectives = { [1] = { points = { pt(0.5, 0.5, 1412) } } } } }
    local step = Q.Pick({ boars() }, places, HERE)
    t.eq(step.place, nil)
    t.eq(step.lines[3], Q.UNKNOWN_PLACE, "the reader did not say elsewhere, so it is not said")
end

T["quest source: a complete quest in words"] = function(t)
    t.eq(Q.Pick({ letter() }, nil, HERE).lines, { "A Letter Home", "Turn in", "location unknown" })
    local places = { [202] = { turnIn = { points = {}, elsewhere = true, name = "Marshal Dughan" } } }
    t.eq(Q.Pick({ letter() }, places, HERE).lines, { "A Letter Home", "Turn in: Marshal Dughan", "on another map" })
end

T["quest source: an objective with no text has no line of its own"] = function(t)
    local row = { id = 7, title = "Quiet", objectives = { { done = false } } }
    t.eq(Q.Pick({ row }, nil, HERE).lines, { "Quiet", "location unknown" })
end

T["quest source: a failed quest is never a step"] = function(t)
    local places = { [101] = { objectives = { [1] = { points = { pt(0.5, 0.3) } } } } }
    t.eq(Q.Pick({ boars({ failed = true }) }, places, HERE), nil)
    t.eq(Q.Pick({ boars({ failed = true }), letter() }, nil, HERE).quest, 202)
end

T["quest source: where the player is not known, no point is chosen"] = function(t)
    local places = { [101] = { objectives = { [1] = { points = { pt(0.5, 0.3) } } } } }
    local step = Q.Pick({ boars() }, places, { map = 1411 })
    t.eq(step.place, nil)
    t.eq(step.lines, { "Boar Trouble", "Boars slain: 2/8", "location unknown" })
    t.eq(Q.Pick({ boars() }, places, nil).place, nil)
end

T["quest source: rows and points that are not usable are passed over"] = function(t)
    local places = { [101] = { objectives = { [1] = { points = {
        "junk", { map = 1411, x = "a", y = 0.3 }, { map = 1411, x = 0 / 0, y = 0.3 }, pt(0.5, 0.2),
    } } } } }
    local step = Q.Pick({ "junk", { title = "no id" }, { id = 9 }, boars() }, places, HERE)
    t.eq(step.quest, 101)
    t.eq(step.place, { cont = 1, map = 1411, x = 0.5, y = 0.2 })
end

T["quest source: nothing handed in is changed"] = function(t)
    local rows = { boars() }
    local places = { [101] = { objectives = { [1] = { points = { pt(0.5, 0.3) } } } } }
    local step = Q.Pick(rows, places, HERE)
    step.place.x = 9
    t.eq(rows, { boars() })
    t.eq(places[101].objectives[1].points[1], pt(0.5, 0.3))
    t.eq(HERE.x, 0.5)
end

return T
