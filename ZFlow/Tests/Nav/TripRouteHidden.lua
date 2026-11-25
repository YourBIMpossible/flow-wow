local _, ns = ...

-- Parity row A1-28 (lead section 794): the route leaves out the steps the
-- player hid (Nav/TripRoute.lua T.Unhidden, through Nav/HiddenSteps.lua) and
-- the arrow's Hide this step keeps its step hidden (UI/Arrow.lua
-- Arrow.KeepHidden). A stand-in list module is put on ns.Nav for each test
-- and the one there before is put back. Not tested in game.

local tests = {}

local function T() return ns.Nav.TripRoute end

-- Runs fn with stand-in as ns.Nav.HiddenSteps (nil for none), then puts the
-- original back, also when fn fails.
local function withHidden(standIn, fn)
    local saved = ns.Nav.HiddenSteps
    ns.Nav.HiddenSteps = standIn
    local ok, err = pcall(fn)
    ns.Nav.HiddenSteps = saved
    if not ok then error(err, 0) end
end

-- Hides quest 1's first objective, whatever the store holds.
local function fakeList()
    local L = { hidden = {} }
    function L.KeyOf(s)
        if type(s) ~= "table" or s.quest == nil then return nil end
        return tostring(s.quest) .. ":" .. tostring(s.objective)
    end
    function L.Filter(steps, store)
        local out = {}
        for _, s in ipairs(steps) do
            if not (store and store.hide and L.KeyOf(s) == store.hide) then out[#out + 1] = s end
        end
        return out
    end
    function L.Hide(store, key, label)
        L.hidden[#L.hidden + 1] = { store = store, key = key, label = label }
        return true
    end
    return L
end

local function row(id, title, text)
    return { id = id, title = title, complete = false, failed = false,
             objectives = { { text = text, done = false } } }
end

local HERE = { map = 1, x = 0.5, y = 0.5, size = { w = 1000, h = 1000 } }
local ROWS = { row(1, "Boars", "Boars: 0/4"), row(2, "Wolves", "Wolves: 0/4") }
local PLACES = { [1] = { objectives = { [1] = { points = { { map = 1, x = 0.6, y = 0.5 } } } } },
                 [2] = { objectives = { [1] = { points = { { map = 1, x = 0.4, y = 0.5 } } } } } }
local STORE = { hide = "1:1" }

local function quests(route)
    local out = {}
    for _, s in ipairs(route and route.stops or {}) do out[#out + 1] = s.quest end
    table.sort(out)
    return out
end

tests["hidden steps: the route leaves out a step the list hides"] = function(t)
    withHidden(fakeList(), function()
        local r = T().Plan(ROWS, PLACES, HERE, nil, nil, nil, STORE)
        t.eq(quests(r), { 2 }, "quest 1's step is hidden")
    end)
end

tests["hidden steps: with no list module the route is as before"] = function(t)
    withHidden(nil, function()
        t.eq(quests(T().Plan(ROWS, PLACES, HERE, nil, nil, nil, STORE)), { 1, 2 })
        local stops = { { quest = 1, objective = 1 } }
        t.eq(T().Unhidden(stops, STORE), stops, "the same steps come back")
    end)
end

tests["hidden steps: no store, or a list that fails, keeps every step"] = function(t)
    local broken = fakeList()
    function broken.Filter() error("list broke") end
    withHidden(broken, function()
        t.eq(quests(T().Plan(ROWS, PLACES, HERE, nil, nil, nil, STORE)), { 1, 2 })
    end)
    withHidden(fakeList(), function()
        t.eq(quests(T().Plan(ROWS, PLACES, HERE)), { 1, 2 }, "no store: nothing is read")
    end)
end

tests["hidden steps: Hide this step keeps the route step hidden"] = function(t)
    local L = fakeList()
    withHidden(L, function()
        local store = {}
        t.eq(ns.Arrow.KeepHidden({ quest = 7, objective = 2, label = "Boars" }, store), true)
        t.eq(#L.hidden, 1)
        t.eq(L.hidden[1].key, "7:2")
        t.eq(L.hidden[1].label, "Boars")
        t.ok(L.hidden[1].store == store, "the character's store")
        t.eq(ns.Arrow.KeepHidden({ label = "no quest" }, store), false, "not a quest step: nothing kept")
        t.eq(#L.hidden, 1)
    end)
    withHidden(nil, function()
        t.eq(ns.Arrow.KeepHidden({ quest = 7, objective = 2 }, {}), false, "no list module: nothing")
    end)
end

return tests
