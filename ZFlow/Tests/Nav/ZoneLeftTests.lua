local _, ns = ...

-- Tests for ZFlow/Nav/ZoneLeft.lua (S37): what is still worth doing on the
-- player's map before they leave. Pure parts only; made-up quests and
-- places. Not tested in game.

local tests = {}

local function Z() return ns.Nav.ZoneLeft end

local function row(id, title, texts, complete)
    local r = { id = id, title = title, complete = complete == true, failed = false, objectives = {} }
    for i, text in ipairs(texts or {}) do r.objectives[i] = { text = text, done = false } end
    return r
end

local function at(x, y) return { points = { { map = 1, x = x, y = y } } } end

local HERE = { map = 1, x = 0.5, y = 0.5, size = { w = 1000, h = 1000 } }

local function world()
    local rows = { row(1, "Boars", { "Boars: 0/4", "Tusks: 0/2" }), row(2, "Bandages", { "Linen: 4/4" }, true),
                   row(3, "Far", { "Far: 0/1" }), row(4, "Herbs", { "Herbs: 0/5" }),
                   row(5, "Farther", { "Farther: 0/1" }) }
    local places = { [1] = { objectives = { [1] = at(0.6, 0.5), [2] = at(0.7, 0.5) } },
                     [2] = { turnIn = { points = { { map = 1, x = 0.55, y = 0.5 } }, name = "Smith" } },
                     [3] = { objectives = { [1] = { points = {}, elsewhere = true } } },
                     [4] = { objectives = { [1] = at(0.2, 0.5) } } }
    return rows, places
end

tests["zone left: quests with something on this map, in log order, and the count for elsewhere"] = function(t)
    local rows, places = world()
    local list, elsewhere = Z().Left(rows, places, HERE)
    t.eq(#list, 3)
    t.eq(list[1].title, "Boars"); t.eq(list[1].steps, 2); t.eq(list[1].turnIn, false)
    t.eq(list[2].title, "Bandages"); t.eq(list[2].turnIn, true)
    t.eq(list[3].title, "Herbs"); t.eq(list[3].steps, 1)
    t.eq(elsewhere, 2, "the two quests with no place here")
end

tests["zone left: a quest partly here is not counted as elsewhere; a failed or done one is not listed"] = function(t)
    local rows = { row(1, "Boars", { "Boars: 0/4", "Tusks: 0/2" }), row(2, "Lost", { "x" }), row(3, "Done", { "y" }) }
    rows[2].failed = true
    rows[3].objectives[1].done = true
    local places = { [1] = { objectives = { [1] = at(0.6, 0.5) } }, [2] = { objectives = { [1] = at(0.1, 0.1) } },
                     [3] = { objectives = { [1] = at(0.1, 0.1) } } }
    local list, elsewhere = Z().Left(rows, places, HERE)
    t.eq(#list, 1); t.eq(list[1].steps, 1)
    t.eq(elsewhere, 0)
end

tests["zone left: nothing handed in, odd things handed in: empty, never an error"] = function(t)
    local list, elsewhere = Z().Left(nil, nil, nil)
    t.eq(#list, 0); t.eq(elsewhere, 0)
    list = Z().Left({ "x", {}, row(1, "Boars", { "a" }) }, "x", { map = 1 })
    t.eq(#list, 0)
    t.eq(Z().Notice(nil), nil); t.eq(Z().Notice({}), nil)
    t.eq(Z().Lines(nil, nil)[1], Z().NONE)
end

tests["zone left: the word's lines read plainly"] = function(t)
    local rows, places = world()
    local lines = Z().Lines(Z().Left(rows, places, HERE))
    t.eq(lines[1], "Still worth doing here before you leave: 3 quests")
    t.eq(lines[2], "  Boars: 2 steps left here")
    t.eq(lines[3], "  Bandages: ready to hand in here")
    t.eq(lines[4], "  Herbs: 1 step left here")
    t.eq(lines[5], "2 other quests are for somewhere else (after this zone).")
    t.eq(#lines, 5)
    local one = Z().Lines({ { title = "Boars", steps = 1 } }, 1)
    t.eq(one[1], Z().HEADER_ONE)
    t.eq(one[3], "1 other quest is for somewhere else (after this zone).")
    local none = Z().Lines({}, 0)
    t.eq(#none, 1); t.eq(none[1], Z().NONE)
end

tests["zone left: the line on leaving names up to three quests"] = function(t)
    t.eq(Z().Notice({ { title = "Boars" } }),
        "You left 1 quest unfinished in the zone behind you: Boars. Go back for it, or carry on.")
    t.eq(Z().Notice({ { title = "A" }, { title = "B" }, { title = "C" }, { title = "D" }, { title = "E" } }),
        "You left 5 quests unfinished in the zone behind you: A, B, C and 2 more. Go back for them, or carry on.")
end

return tests
