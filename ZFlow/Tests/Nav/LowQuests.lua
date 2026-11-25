-- Tests for the low-level quests route option (ZFlow/Nav/LowQuests.lua,
-- A2-05): off by default, grey pick-ups stay off the route; on, they are
-- kept. Made-up quests, test only. Not tested in game.
local _, ns = ...

local N = ns.Nav
local tests = {}

local function ctx(over)
    local c = { level = 18, log = {}, me = { raceId = 1, classId = 1, faction = "Alliance" },
                done = function() return nil end }
    for k, v in pairs(over or {}) do c[k] = v end
    return c
end

local function q(over)
    local out = { Id = 700, name = "Old Errand", level = 8, requiredLevel = 4 }
    for k, v in pairs(over or {}) do out[k] = v end
    return out
end

tests["low quests: the setting's key"] = function(t)
    t.ok(N.LowQuests ~= nil, "the module is loaded")
    t.eq(N.LowQuests.SETTING, "nav.lowQuests")
    t.eq(N.LowQuests.NAME, "lowQuests")
end

tests["low quests: off (unset or false), a far-below quest is not a candidate"] = function(t)
    local P = N.RoutePickups
    local ok, why = P.Candidate(q(), ctx())
    t.eq(ok, false)
    t.eq(why, "far below you")
    t.eq((P.Candidate(q(), ctx({ lowOn = false }))), false)
end

tests["low quests: on, a far-below quest is a candidate"] = function(t)
    local P = N.RoutePickups
    t.eq((P.Candidate(q(), ctx({ lowOn = true }))), true)
    t.eq((P.Candidate(q({ level = 1, requiredLevel = 1 }), ctx({ lowOn = true }))), true)
end

tests["low quests: on, the other cuts still hold"] = function(t)
    local P = N.RoutePickups
    t.eq((P.Candidate(q({ level = 26, requiredLevel = 25 }), ctx({ lowOn = true }))), false)
    t.eq((P.Candidate(q(), ctx({ lowOn = true, log = { [700] = true } }))), false)
    t.eq((P.Candidate(q(), ctx({ lowOn = true, done = function(id) return id == 700 end }))), false)
end

tests["low quests: On is false with no add-on running"] = function(t)
    t.eq(N.LowQuests.On(), false)
end

return tests
