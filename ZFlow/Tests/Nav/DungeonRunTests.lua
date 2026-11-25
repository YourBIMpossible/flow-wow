local _, ns = ...

-- Tests for ZFlow/Nav/DungeonRun.lua (FLOW-PARITY B-50 wiring): the
-- prepared run, whether you walk only its steps, and "get ready on the way",
-- changed by the dungeon route's choices. Pure parts. Made-up dungeon.

local tests = {}

local function DR() return ns.DungeonRun end

local RUN = { key = 7, name = "Test Mines", only = true, prep = true, total = 6 }

local function copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

tests["dungeon run: leave keeps the run and turns the route off"] = function(t)
    local s, effect = DR().Act(copy(RUN), "leave")
    t.eq(s.only, false); t.eq(s.key, 7); t.eq(effect, "off")
end

tests["dungeon run: back plans the run again, only its steps"] = function(t)
    local s, effect = DR().Act(copy(RUN), "leave")
    s, effect = DR().Act(s, "back")
    t.eq(s.only, true); t.eq(effect, "plan")
end

tests["dungeon run: get ready flips, and re-plans only while on the run"] = function(t)
    local s, effect = DR().Act(copy(RUN), "prep")
    t.eq(s.prep, false); t.eq(effect, "plan")
    local off = copy(RUN); off.only = false
    s, effect = DR().Act(off, "prep")
    t.eq(s.prep, false); t.eq(effect, nil)
end

tests["dungeon run: cancel drops the run and turns the route off"] = function(t)
    local s, effect = DR().Act(copy(RUN), "cancel")
    t.eq(s, nil); t.eq(effect, "off")
end

tests["dungeon run: nothing happens without a run or with an unknown choice"] = function(t)
    local s, effect = DR().Act(nil, "leave")
    t.eq(s, nil); t.eq(effect, nil)
    s, effect = DR().Act(copy(RUN), "fly")
    t.eq(s, RUN); t.eq(effect, nil)
end

tests["dungeon run: done is the planned steps less the ones still to walk"] = function(t)
    t.eq(DR().Done(6, 4), 2)
    t.eq(DR().Done(6, nil), 6, "the route walked to its end")
    t.eq(DR().Done(6, 9), 0)
    t.eq(DR().Done(nil, 3), 0)
end

tests["dungeon run: the mode state for the menu"] = function(t)
    local m = DR().ModeState(copy(RUN), true, { "Pick up: Boars" })
    t.eq(m.name, "Test Mines"); t.eq(m.on, true); t.eq(m.prep, true)
    t.eq(m.canAsk, nil, "asking the group (B-51) is held")
    t.eq(m.extra, { "Pick up: Boars" })
    t.eq(DR().ModeState(nil), nil)
    local off = copy(RUN); off.prep = nil
    t.eq(DR().ModeState(off).prep, true, "get ready is on unless turned off")
end

-- Lazy's review of 5531d93b (lead section 640): through DR.Declare and Act,
-- with a fake store, a stub planner and a stub trip route.
local function fakeStore()
    local data = { char = {} }
    return {
        data = data,
        get = function(_, scope, path) return data[scope][path] end,
        set = function(_, scope, path, v) data[scope][path] = v; return true end,
    }
end

local function declared()
    local store = fakeStore()
    local trip = { offs = 0 }
    function trip.Off() trip.offs = trip.offs + 1 end
    function trip.Current() return { stops = { {}, {}, {} } } end
    local k = { store = store, problems = { add = function() end },
                use = function(name) if name == "tripRoute" then return trip end end }
    function k.Module() end
    local api = DR().Declare(k)
    return api, store, trip
end

tests["dungeon run e2e: turning get-ready off plans again without it"] = function(t)
    local api, store = declared()
    local seen = {}
    api.SetPlanner(function(key, wing, prep)
        seen[#seen + 1] = { key = key, prep = prep, stored = api.PrepOn() }
        return 5
    end)
    api.Prepared(7, "Test Mines", nil, 8)
    api.Act("prep")
    t.eq(#seen, 1)
    t.eq(seen[1].prep, false, "the planner is told get-ready is off")
    t.eq(seen[1].stored, false, "and the saved choice already says so")
    t.eq(store.data.char[DR().PREP_PATH], false)
    t.eq(store.data.char[DR().PATH].total, 5)
end

tests["dungeon run e2e: leave turns the route off and keeps the run"] = function(t)
    local api, store, trip = declared()
    api.Prepared(7, "Test Mines", nil, 8)
    api.Act("leave")
    t.eq(trip.offs, 1)
    t.eq(store.data.char[DR().PATH].key, 7)
    t.eq(store.data.char[DR().PATH].only, false)
end

tests["dungeon run e2e: cancel clears the run"] = function(t)
    local api, store, trip = declared()
    api.Prepared(7, "Test Mines", nil, 8)
    api.Act("cancel")
    t.eq(store.data.char[DR().PATH], nil)
    t.eq(trip.offs, 1)
end

tests["dungeon run e2e: preparing keeps an earlier get-ready off"] = function(t)
    local api, store = declared()
    store.data.char[DR().PREP_PATH] = false
    api.Prepared(7, "Test Mines", nil, 8)
    t.eq(store.data.char[DR().PREP_PATH], false)
    t.eq(api.PrepOn(), false)
end

tests["dungeon run e2e: the menu shows the run's counts"] = function(t)
    local api = declared()
    api.SetCounter(function(key)
        if key == 7 then return { on = 2, missing = 1, inside = 0 } end
    end)
    api.Prepared(7, "Test Mines", nil, 8)
    local texts = {}
    for _, it in ipairs(api.Items()) do texts[#texts + 1] = it.text end
    local joined = table.concat(texts, "|")
    t.ok(joined:find("You're on 2 quests", 1, true) ~= nil, "the counts are listed: " .. joined)
    t.ok(joined:find("completed", 1, true) == nil, "no handed-in count when it is not known")
end

return tests
