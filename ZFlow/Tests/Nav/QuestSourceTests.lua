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
                 detail = "Boars slain: 2/8", place = { cont = 1, map = 1411, x = 0.5, y = 0.3 }, area = true },
        "100 yd north; the done objective right beside the player is not a step; three points: an area")
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

-- Section 131: the quest the player picked out. Boars (101) are 25 yd
-- away, the scouting (303) 400 yd away, the letter (202) is handed in 50 yd
-- away.
local function scout(more)
    local row = { id = 303, title = "Scout the Ridge", objectives = { { text = "Ridge scouted: 0/1", done = false } } }
    for key, v in pairs(more or {}) do row[key] = v end
    return row
end

local function spots()
    return {
        [101] = { objectives = { { points = { pt(0.5, 0.45) } } } },
        [202] = { turnIn = { points = { pt(0.5, 0.6) }, name = "Marshal Dughan" } },
        [303] = { objectives = { { points = { pt(0.9, 0.5) } } } },
    }
end

T["quest focus: the picked quest wins over a nearer one"] = function(t)
    local rows = { boars(), scout() }
    t.eq(Q.Pick(rows, spots(), HERE).quest, 101, "nothing picked: the nearest")
    local step = Q.Pick(rows, spots(), HERE, { quest = 303 })
    t.eq(step.quest, 303)
    t.eq(step.objective, 1)
    t.eq(step.detail, "Ridge scouted: 0/1")
    t.eq(step.place, { cont = 1, map = 1411, x = 0.9, y = 0.5 })
end

T["quest focus: nothing picked is the old answer"] = function(t)
    local rows = { boars(), scout(), letter() }
    local old = Q.Pick(rows, spots(), HERE)
    t.eq(old.quest, 101)
    t.eq(Q.Pick(rows, spots(), HERE, nil), old)
    t.eq(Q.Pick(rows, spots(), HERE, {}), old, "a read that says none")
    t.eq(Q.Pick(rows, spots(), HERE, { watched = {} }), old, "nothing watched")
    t.eq(Q.Pick(rows, spots(), HERE, "junk"), old)
    t.eq(Q.Pick(rows, nil, {}, {}), Q.Pick(rows, nil, {}), "words only too")
end

T["quest focus: a picked quest that is handed in or abandoned falls back"] = function(t)
    local rows = { boars(), scout() }
    local old = Q.Pick(rows, spots(), HERE)
    t.eq(Q.Pick(rows, spots(), HERE, { quest = 999 }), old, "not in the log")
    t.eq(Q.Pick({ boars(), scout({ failed = true }) }, spots(), HERE, { quest = 303 }), old, "failed")
    local done = scout({ objectives = { { text = "Ridge scouted: 1/1", done = true } } })
    t.eq(Q.Pick({ boars(), done }, spots(), HERE, { quest = 303 }), old, "nothing left and not ready to hand in")
    t.eq(Q.Pick({}, spots(), HERE, { quest = 303 }), nil, "an empty log has no step")
end

T["quest focus: a picked quest that is complete points at its turn-in"] = function(t)
    local rows = { boars(), letter() }
    t.eq(Q.Pick(rows, spots(), HERE).quest, 101, "nothing picked: an objective wins over a turn-in")
    local step = Q.Pick(rows, spots(), HERE, { quest = 202 })
    t.eq(step.quest, 202)
    t.eq(step.turnIn, true)
    t.eq(step.detail, "Turn in: Marshal Dughan")
    t.eq(step.place, { cont = 1, map = 1411, x = 0.5, y = 0.6 })
end

T["quest focus: a picked quest with no place on this map is that quest in words"] = function(t)
    local rows = { boars(), scout() }
    local places = spots()
    places[303] = { objectives = { { points = {}, elsewhere = true } } }
    local step = Q.Pick(rows, places, HERE, { quest = 303 })
    t.eq(step.place, nil)
    t.eq(step.lines, { "Scout the Ridge", "Ridge scouted: 0/1", Q.ELSEWHERE })
    places[303] = nil
    t.eq(Q.Pick(rows, places, HERE, { quest = 303 }).lines, { "Scout the Ridge", "Ridge scouted: 0/1", Q.UNKNOWN_PLACE })
    t.eq(Q.Pick(rows, spots(), {}, { quest = 303 }).lines, { "Scout the Ridge", "Ridge scouted: 0/1", Q.UNKNOWN_PLACE },
        "where the player is not known")
    places[202] = nil
    t.eq(Q.Pick({ boars(), letter() }, places, HERE, { quest = 202 }).lines, { "A Letter Home", "Turn in", Q.UNKNOWN_PLACE })
end

T["quest focus: of the picked quest, the nearest unfinished objective"] = function(t)
    local row = { id = 404, title = "Two Things", objectives = {
        { text = "Far: 0/1" }, { text = "Near: 0/1" }, { text = "Done: 1/1", done = true } } }
    local places = spots()
    places[404] = { objectives = {
        { points = { pt(0.1, 0.5) } }, { points = { pt(0.6, 0.5) } }, { points = { pt(0.5, 0.5) } } } }
    local step = Q.Pick({ boars(), row }, places, HERE, { quest = 404 })
    t.eq(step.objective, 2)
    t.eq(step.place, { cont = 1, map = 1411, x = 0.6, y = 0.5 })
end

T["quest focus: watched quests come before the rest of the log"] = function(t)
    local rows = { boars(), scout(), letter() }
    t.eq(Q.Pick(rows, spots(), HERE, { watched = { 303 } }).quest, 303)
    t.eq(Q.Pick(rows, spots(), HERE, { watched = { 303, 202 } }).quest, 303, "an objective before a turn-in, among the watched")
    t.eq(Q.Pick(rows, spots(), HERE, { watched = { 202 } }).quest, 202)
    t.eq(Q.Pick(rows, spots(), HERE, { watched = { 999 } }).quest, 101, "none of the watched is in the log: the whole log")
    local done = scout({ objectives = { { text = "Ridge scouted: 1/1", done = true } } })
    t.eq(Q.Pick({ boars(), done }, spots(), HERE, { watched = { 303 } }).quest, 101, "the watched have nothing left: the whole log")
    t.eq(Q.Pick(rows, spots(), HERE, { quest = 101, watched = { 303 } }).quest, 101, "the picked quest before the watched")
    t.eq(Q.Pick(rows, spots(), HERE, { quest = 999, watched = { 303 } }).quest, 303, "a picked quest that is gone: the watched")
end

T["quest focus: Pick says where the step came from"] = function(t)
    local rows = { boars(), scout() }
    local _, from = Q.Pick(rows, spots(), HERE, nil)
    t.eq(from, "log")
    _, from = Q.Pick(rows, spots(), HERE, { quest = 303 })
    t.eq(from, "picked")
    _, from = Q.Pick(rows, spots(), HERE, { watched = { 303 } })
    t.eq(from, "watched")
    _, from = Q.Pick(rows, spots(), HERE, { quest = 999, watched = { 999 } })
    t.eq(from, "log", "neither is in the log")
    local step
    step, from = Q.Pick({}, spots(), HERE, { quest = 303 })
    t.eq(step, nil)
    t.eq(from, nil, "no step: no source")
end

T["quest focus: the focus handed in is not changed"] = function(t)
    local focus = { quest = 303, watched = { 303, 101 } }
    Q.Pick({ boars(), scout() }, spots(), HERE, focus)
    t.eq(focus, { quest = 303, watched = { 303, 101 } })
end

return T
