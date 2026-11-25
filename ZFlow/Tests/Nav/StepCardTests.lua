local _, ns = ...
-- Parity row A1-13, the data half (lead section 825.2): the card for one
-- step, as Flow's Modules/Nav/Nav.lua N:ShowStop (:4232-4278) and its
-- links (buildCard :4188-4229): title, distance, body lines, and the
-- quest log, map and go-here-next links. Made-up steps. Pure. Not tested
-- in game. Fails before: no such file.
local tests = {}

local function SC() return ns.Nav and ns.Nav.StepCard end

local function step()
    return { label = "Kill Gnolls", title = "Wanted: Gnolls", detail = "Gnoll Paw: 2/8",
             quest = 176, objective = "Gnoll Paw: 2/8", kind = "quest",
             place = { map = 1429, x = 0.4, y = 0.6 } }
end

local function action(card, key)
    for _, a in ipairs(card.actions) do if a.key == key then return a end end
    return nil
end

tests["step card: title, what to do, distance and lines"] = function(t)
    t.eq(type(SC()), "table", "loaded")
    if type(SC()) ~= "table" then return end
    local card = SC().Card(step(), { distance = "120 yd" })
    t.eq(card.title, "Kill Gnolls", "title is the label")
    t.eq(card.sub, "Gnoll Paw: 2/8", "what to do is the objective")
    t.eq(card.distance, "120 yd", "distance from the caller")
    t.eq(card.lines, { "Wanted: Gnolls", "Gnoll Paw: 2/8" }, "body lines")
    t.eq(#card.actions, 3, "three actions")
    t.eq(card.actions[1].key, "questLog", "quest log first")
    t.eq(card.actions[2].key, "map", "map second")
    t.eq(card.actions[3].key, "first", "first third")
end

tests["step card: no step, no card"] = function(t)
    if type(SC()) ~= "table" then return t.ok(false, "not loaded") end
    t.eq(SC().Card(nil, {}), nil, "nil step")
    t.eq(SC().Card({}, {}), nil, "no label")
end

tests["step card: quest log only when the quest is in the log"] = function(t)
    if type(SC()) ~= "table" then return t.ok(false, "not loaded") end
    local off = action(SC().Card(step(), { inLog = {} }), "questLog")
    t.eq(off.enabled, false, "not in log")
    t.ok(type(off.why) == "string" and off.why ~= "", "says why")
    local noSeam = action(SC().Card(step(), { inLog = { [176] = true } }), "questLog")
    t.eq(noSeam.enabled, false, "in log, no way to select it yet")
    t.ok(type(noSeam.why) == "string" and noSeam.why ~= "", "says why")
    local on = action(SC().Card(step(), { inLog = { [176] = true }, canSelectQuest = true }), "questLog")
    t.eq(on.enabled, true, "in log and a way to select")
    t.eq(SC().Run("questLog", step(), { inLog = { [176] = true }, canSelectQuest = true }),
        { call = "questLog", quest = 176 }, "run selects the quest")
    t.eq(SC().Run("questLog", step(), { inLog = {} }), nil, "disabled runs nothing")
end

tests["step card: map only with a place"] = function(t)
    if type(SC()) ~= "table" then return t.ok(false, "not loaded") end
    t.eq(action(SC().Card(step(), {}), "map").enabled, true, "with a map")
    local s = step()
    s.place = nil
    local off = action(SC().Card(s, {}), "map")
    t.eq(off.enabled, false, "no place")
    t.ok(type(off.why) == "string" and off.why ~= "", "says why")
    t.eq(SC().Run("map", step(), {}), { call = "showMap", map = 1429 }, "run shows the map")
    t.eq(SC().Run("map", s, {}), nil, "no place runs nothing")
end

tests["step card: first only for a route step not already first"] = function(t)
    if type(SC()) ~= "table" then return t.ok(false, "not loaded") end
    t.eq(action(SC().Card(step(), { index = 1, canFirst = true }), "first").enabled, false, "already first")
    t.eq(action(SC().Card(step(), { canFirst = true }), "first").enabled, false, "not on the route")
    t.eq(action(SC().Card(step(), { index = 3 }), "first").enabled, false, "no way to move it yet")
    local on = action(SC().Card(step(), { index = 3, canFirst = true }), "first")
    t.eq(on.enabled, true, "third step")
    t.eq(SC().Run("first", step(), { index = 3, canFirst = true }), { call = "first", index = 3 }, "run")
    t.eq(SC().Run("first", step(), { index = 1, canFirst = true }), nil, "first runs nothing")
end

tests["step card: hand in says so"] = function(t)
    if type(SC()) ~= "table" then return t.ok(false, "not loaded") end
    local s = { label = "Hand in Wanted", turnIn = true, quest = 9 }
    local card = SC().Card(s, {})
    t.ok(type(card.sub) == "string" and card.sub ~= "", "a hand-in line")
    t.eq(card.distance, nil, "no distance given")
end

-- Lead section 826: "Do this next" runs through the planned route's own
-- First(n) (Nav/TripRoute.lua), as PartyRoute's api.First; SC.CanFirst says
-- whether the route offers it.
tests["step card: the route can put a step first"] = function(t)
    local T = ns.Nav.TripRoute
    t.eq(type(T.First), "function", "T.First")
    if type(T.First) ~= "function" then return end
    local stops = { { label = "A" }, { label = "B", gone = true }, { label = "C" }, { label = "D" } }
    t.eq(T.First(stops, 1, 3), true, "the third shown (D) goes first")
    t.eq({ stops[1].label, stops[2].label, stops[3].label, stops[4].label }, { "D", "A", "B", "C" })
    t.eq(T.First(stops, 1, 1), false, "already first")
    t.eq(T.First(stops, 1, 9), false, "no such step")
    t.eq(T.First(nil, 1, 2), false)
    local later = { { label = "done" }, { label = "X" }, { label = "Y" } }
    t.eq(T.First(later, 2, 2), true, "counted from the step the route is at")
    t.eq({ later[1].label, later[2].label, later[3].label }, { "done", "Y", "X" })
    t.eq(SC().CanFirst({ First = function() end }), true)
    t.eq(SC().CanFirst({}), false)
    t.eq(SC().CanFirst(nil), false)
end

return tests
