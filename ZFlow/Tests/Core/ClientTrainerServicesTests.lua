-- F8 Trainer and spell learning: the service rows and filter added to the
-- one trainer read, and onSpellLearned. The real client over a hand-built
-- environment (`env` stands in for the game's globals), then the fake.
-- Every call read here is a first guess, not seen in game on 16001.
local _, ns = ...

-- A trainer window with Bena behind it and `rows` on offer:
--   { name, rank, category, cost, level }
local function trainerEnv(rows, filter)
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
    env.UnitName = function(unit) return unit == "npc" and "Bena Winterhoof" or nil end
    env.UnitIsPlayer = function(unit) if unit == "npc" then return false end end
    env.GetTrainerServiceSkillLine = function() return nil end
    env.GetNumTrainerServices = function() return #rows end
    env.GetTrainerServiceInfo = function(i) local r = rows[i] or {}; return r.name, r.rank, r.category end
    env.GetTrainerServiceCost = function(i) return (rows[i] or {}).cost end
    env.GetTrainerServiceLevelReq = function(i) return (rows[i] or {}).level end
    filter = filter or { available = 1, unavailable = 1, used = 1 }
    env.GetTrainerServiceTypeFilter = function(kind) return filter[kind] end
    return env
end

local function opened(env)
    local c = ns.make.client(env)
    c.watchTrainer()
    env.fire("TRAINER_SHOW")
    return c
end

local ROWS = {
    { name = "Druid", category = "header" },
    { name = "Moonfire", rank = "Rank 2", category = "available", cost = 150, level = 10 },
    { name = "Thorns", rank = "Rank 1", category = "used", cost = 100, level = 6 },
    { name = "Rejuvenation", rank = "Rank 3", category = "unavailable", cost = 900, level = 16 },
}

return {
    ["F8 trainer(): the service rows, header rows left out, the game's used is known"] = function(t)
        local r = opened(trainerEnv(ROWS)).trainer()
        t.eq(r.npc, "Bena Winterhoof")
        t.eq(r.services, {
            { name = "Moonfire", rank = "Rank 2", state = "available", cost = 150, level = 10 },
            { name = "Thorns", rank = "Rank 1", state = "known", cost = 100, level = 6 },
            { name = "Rejuvenation", rank = "Rank 3", state = "unavailable", cost = 900, level = 16 },
        })
        t.eq(r.filter, { available = true, unavailable = true, known = true })
    end,

    ["F8 trainer(): a cost, level or rank not read is left out of that row"] = function(t)
        local rows = { { name = "Moonfire", rank = "", category = "available", cost = "150", level = 2.5 } }
        t.eq(opened(trainerEnv(rows)).trainer().services, { { name = "Moonfire", state = "available" } })
    end,

    ["F8 trainer(): one row that cannot be read drops the whole list, never a shorter one"] = function(t)
        for _, bad in ipairs({ { name = "", category = "available" }, { name = "X", category = "odd" },
            { name = "X" } }) do
            local rows = { ROWS[2], bad }
            local r = opened(trainerEnv(rows)).trainer()
            t.eq(r.services, nil)
            t.eq(r.npc, "Bena Winterhoof", "the trainer is still read")
        end
        local env = trainerEnv(ROWS)
        env.GetNumTrainerServices = nil
        t.eq(opened(env).trainer().services, nil, "no count read")
    end,

    ["F8 trainer(): the filter, with nothing from the old call meaning not shown"] = function(t)
        local r = opened(trainerEnv(ROWS, { available = 1 })).trainer()
        t.eq(r.filter, { available = true, unavailable = false, known = false })
        r = opened(trainerEnv(ROWS, { available = true, unavailable = false, used = true })).trainer()
        t.eq(r.filter, { available = true, unavailable = false, known = true })
        local env = trainerEnv(ROWS)
        env.GetTrainerServiceTypeFilter = nil
        t.eq(opened(env).trainer().filter, nil, "no call: not known")
        env.GetTrainerServiceTypeFilter = function() return "yes" end
        t.eq(opened(env).trainer().filter, nil, "an odd answer: not known")
    end,

    ["F8 trainer(): a secret value drops what it is part of"] = function(t)
        local env = trainerEnv(ROWS)
        env.issecretvalue = function(v) return v == "available" end
        t.eq(opened(env).trainer().services, nil)
    end,

    ["F8 onSpellLearned: the spell's id, name and rank"] = function(t)
        local env = trainerEnv({})
        env.GetSpellInfo = function(id) if id == 8921 then return "Moonfire", nil end end
        env.GetSpellSubtext = function(id) if id == 8921 then return "Rank 2" end end
        local c = ns.make.client(env)
        local told = {}
        local cancel = c.onSpellLearned(function(s) told[#told + 1] = s end)
        env.fire("LEARNED_SPELL_IN_TAB", 8921, 2)
        t.eq(told, { { id = 8921, name = "Moonfire", rank = "Rank 2" } })
        env.GetSpellSubtext = nil
        env.GetSpellInfo = function() return "Moonfire", "Rank 3" end
        env.fire("LEARNED_SPELL_IN_TAB", 8921, 2)
        t.eq(told[2].rank, "Rank 3", "an older client's second answer")
        cancel()
        env.fire("LEARNED_SPELL_IN_TAB", 8921, 2)
        t.eq(#told, 2)
    end,

    ["F8 onSpellLearned: no name, an odd id, or a listener that raises"] = function(t)
        local env = trainerEnv({})
        env.GetSpellInfo = function(id) if id == 1 then return "Wrath" end end
        local c = ns.make.client(env)
        local told = 0
        c.onSpellLearned(function() error("broken") end)
        c.onSpellLearned(function() told = told + 1 end)
        env.fire("LEARNED_SPELL_IN_TAB", 2, 1)
        env.fire("LEARNED_SPELL_IN_TAB", "1", 1)
        t.eq(told, 0)
        env.fire("LEARNED_SPELL_IN_TAB", 1, 1)
        t.eq(told, 1, "the raising listener costs only itself")
        t.eq(c.onSpellLearned("x"), nil)
    end,

    ["F8 fake: trainer() gives copies of the rows and filter; learnSpell tells listeners"] = function(t)
        local c = ns.make.fakeClient()
        local rows = { { name = "Moonfire", state = "available", cost = 150 } }
        c.setTrainer({ npc = "Bena", services = rows, filter = { available = true, unavailable = true, known = true } })
        local r = c.trainer()
        t.eq(r.services, rows)
        r.services[1].cost = 1
        t.eq(c.trainer().services[1].cost, 150)
        local got
        c.onSpellLearned(function(s) got = s end)
        c.learnSpell({ name = "Moonfire", rank = "Rank 2" })
        t.eq(got, { name = "Moonfire", rank = "Rank 2" })
    end,
}
