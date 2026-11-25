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

return tests
