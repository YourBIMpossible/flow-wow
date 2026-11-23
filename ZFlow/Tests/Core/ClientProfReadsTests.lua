-- P-PROF (lead section 274 item 2): two more reads of a profession window
-- and a trainer. The real client over a hand-built environment, then the
-- fake.
--   c.tradeSkillTools(index) -> { { name =, has = true | false } } | nil
--       N24: the tools a classic recipe row needs (GetTradeSkillTools), and
--       whether the player carries each; {} when it needs none; nil when the
--       call is missing, raises, or any part can not be read.
--   c.trainer().services[i].skill
--       N23: the profession skill a trainer recipe needs
--       (GetTrainerServiceSkillReq, second answer); left out when not read.
-- Look only: nothing in the game is changed.
-- Needs game test: both calls and their answer shapes on 16001.
local _, ns = ...

local tests = {}

local function toolsEnv(fn)
    return { GetTradeSkillTools = fn }
end

tests["c.tradeSkillTools: each tool and whether it is carried"] = function(t)
    local asked = {}
    local c = ns.make.client(toolsEnv(function(i)
        asked[#asked + 1] = i
        return "Blacksmith Hammer", 1, "Arclight Spanner", nil
    end))
    if type(c.tradeSkillTools) ~= "function" then t.ok(false, "c.tradeSkillTools"); return end
    t.eq(c.tradeSkillTools(3), { { name = "Blacksmith Hammer", has = true }, { name = "Arclight Spanner", has = false } })
    t.eq(asked, { 3 }, "asked once, by the row")
    local d = ns.make.client(toolsEnv(function() return "Mining Pick", true, "Skinning Knife", false end))
    t.eq(d.tradeSkillTools(1), { { name = "Mining Pick", has = true }, { name = "Skinning Knife", has = false } })
    local e = ns.make.client(toolsEnv(function() return "Mining Pick", 0 end))
    t.eq(e.tradeSkillTools(1), { { name = "Mining Pick", has = false } }, "0 is not carried")
end

tests["c.tradeSkillTools: a recipe with no tool is an empty list"] = function(t)
    local c = ns.make.client(toolsEnv(function() return nil end))
    if type(c.tradeSkillTools) ~= "function" then t.ok(false, "c.tradeSkillTools"); return end
    t.eq(c.tradeSkillTools(2), {})
    local d = ns.make.client(toolsEnv(function() end))
    t.eq(d.tradeSkillTools(2), {})
end

tests["c.tradeSkillTools: no call, a raise, a bad row or an odd answer is nil"] = function(t)
    local none = ns.make.client({})
    if type(none.tradeSkillTools) ~= "function" then t.ok(false, "c.tradeSkillTools"); return end
    t.eq(none.tradeSkillTools(1), nil, "no call")
    t.eq(ns.make.client(toolsEnv(function() error("no") end)).tradeSkillTools(1), nil, "raised")
    local c = ns.make.client(toolsEnv(function() return "Hammer", 1 end))
    for _, bad in ipairs({ 0, -1, 1.5, "1", math.huge }) do
        t.eq(c.tradeSkillTools(bad), nil, "row " .. tostring(bad))
    end
    t.eq(ns.make.client(toolsEnv(function() return "", 1 end)).tradeSkillTools(1), nil, "no name")
    t.eq(ns.make.client(toolsEnv(function() return 12, 1 end)).tradeSkillTools(1), nil, "a number for a name")
    t.eq(ns.make.client(toolsEnv(function() return "Hammer", "yes" end)).tradeSkillTools(1), nil, "an odd carried")
    t.eq(ns.make.client(toolsEnv(function() return nil, 1 end)).tradeSkillTools(1), nil, "carried with no name")
end

tests["c.tradeSkillTools: a secret answer is nil"] = function(t)
    local env = toolsEnv(function() return "Hammer", 1 end)
    env.issecretvalue = function(v) return v == "Hammer" end
    local c = ns.make.client(env)
    if type(c.tradeSkillTools) ~= "function" then t.ok(false, "c.tradeSkillTools"); return end
    t.eq(c.tradeSkillTools(1), nil)
end

tests["c.tradeSkillTools: the fake gives copies of what was set"] = function(t)
    local c = ns.make.fakeClient()
    if type(c.setTradeSkillTools) ~= "function" or type(c.tradeSkillTools) ~= "function" then
        t.ok(false, "fake setTradeSkillTools and tradeSkillTools"); return
    end
    t.eq(c.tradeSkillTools(2), nil, "not set: not known")
    c.setTradeSkillTools(2, { { name = "Hammer", has = false } })
    local got = c.tradeSkillTools(2)
    t.eq(got, { { name = "Hammer", has = false } })
    got[1].has = true
    t.eq(c.tradeSkillTools(2), { { name = "Hammer", has = false } }, "a copy")
end

tests["c.tradeSkillTools: the calls are on the diag name list"] = function(t)
    local found = {}
    for _, name in ipairs(ns.Diag.NAMES) do found[name] = true end
    t.ok(found.GetTradeSkillTools == true, "GetTradeSkillTools")
    t.ok(found.GetTrainerServiceSkillReq == true, "GetTrainerServiceSkillReq")
end

-- A trainer window with these rows: { name, category, skill = the second
-- answer of GetTrainerServiceSkillReq }.
local function trainerEnv(rows, skillReq)
    local env = { frames = {} }
    function env.CreateFrame()
        local f = { scripts = {}, events = {} }
        function f:SetScript(name, fn) self.scripts[name] = fn end
        function f:RegisterEvent(event) self.events[event] = true end
        function f:UnregisterEvent(event) self.events[event] = nil end
        env.frames[#env.frames + 1] = f
        return f
    end
    function env.fire(event, ...)
        for _, f in ipairs(env.frames) do
            if f.events[event] then f.scripts.OnEvent(f, event, ...) end
        end
    end
    env.UnitName = function(unit) return unit == "npc" and "Brenda" or nil end
    env.UnitIsPlayer = function(unit) if unit == "npc" then return false end end
    env.GetTrainerServiceSkillLine = function() return "Tailoring" end
    env.GetNumTrainerServices = function() return #rows end
    env.GetTrainerServiceInfo = function(i) local r = rows[i] or {}; return r.name, nil, r.category end
    env.GetTrainerServiceSkillReq = skillReq or function(i)
        local r = rows[i] or {}
        return "Tailoring", r.skill, 1
    end
    env.GetTrainerServiceTypeFilter = function() return 1 end
    return env
end

local function trainerOf(env)
    local c = ns.make.client(env)
    c.watchTrainer()
    env.fire("TRAINER_SHOW")
    return c.trainer()
end

tests["c.trainer: the skill a trainer recipe needs (N23)"] = function(t)
    local r = trainerOf(trainerEnv({
        { name = "Linen Belt", category = "available", skill = 25 },
        { name = "Red Linen Robe", category = "unavailable", skill = 40 },
    }))
    if type(r) ~= "table" or type(r.services) ~= "table" then t.ok(false, "a trainer read"); return end
    t.eq(r.services[1].skill, 25)
    t.eq(r.services[2].skill, 40)
end

tests["c.trainer: a skill not read, or none needed, is left out; the row stays"] = function(t)
    local rows = {
        { name = "A", category = "available", skill = 2.5 },
        { name = "B", category = "available", skill = "40" },
        { name = "C", category = "available", skill = 0 },
        { name = "D", category = "available" },
    }
    local r = trainerOf(trainerEnv(rows))
    if type(r) ~= "table" or type(r.services) ~= "table" then t.ok(false, "a trainer read"); return end
    t.eq(#r.services, 4, "every row kept")
    for i = 1, 4 do t.eq(r.services[i].skill, nil, rows[i].name) end
    local raised = trainerOf(trainerEnv({ { name = "A", category = "available" } }, function() error("no") end))
    t.eq(#raised.services, 1, "a raise keeps the row")
    t.eq(raised.services[1].skill, nil)
    local env = trainerEnv({ { name = "A", category = "available" } })
    env.GetTrainerServiceSkillReq = nil
    t.eq(trainerOf(env).services[1].skill, nil, "no call")
end

return tests
