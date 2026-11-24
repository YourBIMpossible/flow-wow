local _, ns = ...

-- Tests for ZFlow/Nav/TripRoute.lua (S39/S43/S40): the quest route and the
-- dungeon run as ordered stops. Pure parts only; made-up places.

local tests = {}

local function T() return ns.Nav.TripRoute end

local function row(id, title, texts, complete)
    local r = { id = id, title = title, complete = complete == true, failed = false, objectives = {} }
    for i, text in ipairs(texts or {}) do r.objectives[i] = { text = text, done = false } end
    return r
end

local function pts(...)
    local out = {}
    for i, p in ipairs({ ... }) do out[i] = { map = 1, x = p[1], y = p[2] } end
    return { points = out }
end

local HERE = { map = 1, x = 0.5, y = 0.5, size = { w = 1000, h = 1000 } }

tests["trip route: stops are open objectives and turn-ins with a place on this map"] = function(t)
    local rows = { row(1, "Boars", { "Boars: 0/4" }), row(2, "Bandages", { "Linen: 4/4" }, true),
                   row(3, "Far", { "Far: 0/1" }) }
    local places = { [1] = { objectives = { [1] = pts({ 0.6, 0.5 }, { 0.9, 0.9 }) } },
                     [2] = { turnIn = { points = { { map = 1, x = 0.55, y = 0.5 } }, name = "Smith" } },
                     [3] = { objectives = { [1] = { points = {}, elsewhere = true } } } }
    local stops, left = T().Stops(rows, places, HERE)
    t.eq(#stops, 2)
    t.eq(stops[1].quest, 1)
    t.eq(stops[1].place, { map = 1, x = 0.6, y = 0.5 }, "the objective's point nearest the player")
    t.eq(stops[2].turnIn, true)
    t.eq(stops[2].detail, ns.Nav.QuestSource.TurnInLine("Smith"))
    t.eq(#left, 1, "the quest with no place here is said, not routed")
    t.eq(left[1].label, "Far")
end

tests["trip route: order is nearest next from where the player stands, with yards"] = function(t)
    local rows = { row(1, "Boars", { "Boars: 0/4" }), row(2, "Bandages", { "Linen: 4/4" }, true),
                   row(3, "Herbs", { "Herbs: 0/5" }) }
    local places = { [1] = { objectives = { [1] = pts({ 0.6, 0.5 }) } },
                     [2] = { turnIn = { points = { { map = 1, x = 0.55, y = 0.5 } } } },
                     [3] = { objectives = { [1] = pts({ 0.2, 0.5 }) } } }
    local route, why = T().Plan(rows, places, HERE)
    t.ok(route ~= nil, tostring(why))
    local order, legs = {}, {}
    for i, s in ipairs(route and route.stops or {}) do
        order[i], legs[i] = s.label, s.leg and math.floor(s.leg + 0.5)
    end
    t.eq(order, { "Bandages", "Boars", "Herbs" })
    t.eq(legs, { 50, 50, 400 })
    t.eq(route and route.yards, true)
end

tests["trip route: no stops and no map say why"] = function(t)
    local route, why = T().Plan({}, {}, HERE)
    t.eq(route, nil)
    t.ok(type(why) == "string" and why ~= "", "why")
    route, why = T().Plan({ row(1, "Boars", { "Boars: 0/4" }) }, {}, {})
    t.eq(route, nil)
    t.ok(type(why) == "string", "why")
end

tests["trip route: a stop is live while its objective is open or its quest is in the log"] = function(t)
    local rows = { row(1, "Boars", { "Boars: 0/4" }), row(2, "Bandages", { "x" }, true) }
    t.eq(T().Live({ quest = 1, objective = 1 }, rows), true)
    rows[1].objectives[1].done = true
    t.eq(T().Live({ quest = 1, objective = 1 }, rows), false, "objective done")
    t.eq(T().Live({ quest = 2, turnIn = true }, rows), true)
    t.eq(T().Live({ quest = 9, turnIn = true }, rows), false, "handed in")
    t.eq(T().Live({ kind = "giver", place = {} }, rows), true, "a run stop is not the log's")
end

tests["trip route: the lines list every stop in order with distances and the current one marked"] = function(t)
    local route = { yards = true, label = ns.Nav.ROUTE_STRAIGHT, stops = {
        { label = "Bandages", detail = "Turn in", leg = 50 },
        { label = "Boars", detail = "Boars: 0/4", leg = 50.4 },
    } }
    local lines = T().Lines(route, 2)
    t.ok(lines[1]:find("2 stops", 1, true) ~= nil, lines[1])
    t.ok(lines[2]:find("1. Bandages", 1, true) ~= nil and lines[2]:find("50 yd", 1, true) ~= nil, lines[2])
    t.ok(lines[3]:find("> 2. Boars", 1, true) ~= nil, lines[3])
end

-- Lead section 372: a turn-in stop already on the route is checked again
-- each re-read; one no longer ready is held with its reason.
tests["trip route: a turn-in stop no longer complete is held, and is ready again once complete"] = function(t)
    local rows = { row(2, "Bandages", { "x" }, true) }
    t.eq(T().Held({ quest = 2, turnIn = true }, rows), nil, "complete: ready")
    rows[1].complete = false
    t.eq(T().Held({ quest = 2, turnIn = true }, rows), T().HELD_NOT_COMPLETE)
    t.eq(T().Held({ quest = 2, objective = 1 }, rows), nil, "an objective stop is never held")
    t.eq(T().Held({ quest = 9, turnIn = true }, rows), nil, "not in the log: Live drops it")
    t.eq(T().Held({ kind = "trip", turnIn = true }, rows), nil, "a run stop is not the log's")
end

return tests
