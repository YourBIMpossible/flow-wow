-- trainer() inside a TRAINER_SHOW listener (Plexy CR1): whoever listens,
-- and in whatever order the listeners were added, the client already knows
-- the window is open when the first of them runs. The real client over a
-- hand-built environment; ClientFake is not used.
local _, ns = ...

local WHO = { profession = "Alchemy", npc = "Bena Winterhoof" }

-- Frames that take events, and a trainer window with Bena behind it.
local function trainerEnv()
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
    env.UnitName = function(unit) return unit == "npc" and WHO.npc or nil end
    env.UnitIsPlayer = function(unit)
        if unit ~= "npc" then return nil end
        return false
    end
    env.GetTrainerServiceSkillLine = function(index) return index == 1 and WHO.profession or nil end
    return env
end

return {
    ["a listener added before the first watchTrainer call sees the trainer inside TRAINER_SHOW"] = function(t)
        local env = trainerEnv()
        local c = ns.make.client(env)
        local seen, n = {}, 0
        c.listen("TRAINER_SHOW", function()
            n = n + 1
            seen[n] = c.trainer() or false
        end)
        c.watchTrainer()
        env.fire("TRAINER_SHOW")
        t.eq(n, 1, "the listener ran once")
        t.eq(seen[1], WHO, "open inside the first TRAINER_SHOW")
        env.fire("TRAINER_CLOSED")
        t.eq(c.trainer(), nil, "closed")
        env.fire("TRAINER_SHOW")
        t.eq(n, 2)
        t.eq(seen[2], WHO, "open inside the second TRAINER_SHOW")
    end,

    ["a listener that never calls watchTrainer sees the trainer inside TRAINER_SHOW"] = function(t)
        local env = trainerEnv()
        local c = ns.make.client(env)
        local seen, n = {}, 0
        c.listen("TRAINER_SHOW", function()
            n = n + 1
            seen[n] = c.trainer() or false
        end)
        env.fire("TRAINER_SHOW")
        t.eq(seen[1], WHO, "the first call of trainer() is the one inside the event")
        env.fire("TRAINER_CLOSED")
        t.eq(c.trainer(), nil, "closed")
        env.fire("TRAINER_SHOW")
        t.eq(n, 2)
        t.eq(seen[2], WHO)
    end,

    ["a listener added before watchTrainer sees the window closed inside TRAINER_CLOSED"] = function(t)
        local env = trainerEnv()
        local c = ns.make.client(env)
        local seen, n = {}, 0
        c.listen("TRAINER_CLOSED", function()
            n = n + 1
            seen[n] = c.trainer() or false
        end)
        c.watchTrainer()
        env.fire("TRAINER_SHOW")
        t.eq(c.trainer(), WHO)
        env.fire("TRAINER_CLOSED")
        t.eq(n, 1)
        t.eq(seen[1], false, "closed inside TRAINER_CLOSED")
    end,

    ["a listener added after watchTrainer still sees the trainer"] = function(t)
        local env = trainerEnv()
        local c = ns.make.client(env)
        c.watchTrainer()
        local seen
        c.listen("TRAINER_SHOW", function() seen = c.trainer() or false end)
        env.fire("TRAINER_SHOW")
        t.eq(seen, WHO)
    end,

    ["making the client listens to nothing and makes no frame"] = function(t)
        local env = trainerEnv()
        local c = ns.make.client(env)
        t.eq(#env.frames, 0, "no frame until something listens")
        t.eq(c.trainer(), nil, "no event and no frame: not known")
        t.eq(env.frames[1].events.TRAINER_SHOW, true)
        t.eq(env.frames[1].events.TRAINER_CLOSED, true)
    end,
}
