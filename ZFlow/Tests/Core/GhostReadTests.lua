-- The read of whether the player is a ghost, over a hand-built environment
-- and on the fake client. No game client is involved.
local _, ns = ...

local function boom() error("the client refused") end

local function ghostEnv(answer)
    local env = { ghost = answer, asked = {} }
    env.UnitIsGhost = function(unit)
        env.asked[#env.asked + 1] = unit
        if unit ~= "player" then return nil end
        return env.ghost
    end
    return env
end

return {
    ["ghost: the client's own yes or no, for the player only"] = function(t)
        local env = ghostEnv(true)
        local c = ns.make.client(env)
        t.eq(c.ghost(), true)
        env.ghost = false
        t.eq(c.ghost(), false)
        t.eq(env.asked, { "player", "player" })
    end,

    ["ghost: a 1 is a yes, and no answer is unknown"] = function(t)
        local env = ghostEnv(1)
        local c = ns.make.client(env)
        t.eq(c.ghost(), true)
        env.ghost = nil
        t.eq(c.ghost(), nil, "nil is not read as a no")
    end,

    ["ghost: anything else is unknown"] = function(t)
        local env = ghostEnv(0)
        local c = ns.make.client(env)
        t.eq(c.ghost(), nil, "0")
        env.ghost = 2
        t.eq(c.ghost(), nil, "2")
        env.ghost = "yes"
        t.eq(c.ghost(), nil, "a string")
        env.ghost = {}
        t.eq(c.ghost(), nil, "a table")
    end,

    ["ghost: unknown when the read fails or is absent"] = function(t)
        local env = ghostEnv(true)
        local c = ns.make.client(env)
        env.UnitIsGhost = boom
        t.eq(c.ghost(), nil, "the read fails")
        env.UnitIsGhost = nil
        t.eq(c.ghost(), nil, "no such read")
        t.eq(ns.make.client({}).ghost(), nil)
    end,

    ["ghost: a hidden answer is unknown"] = function(t)
        local env = ghostEnv(true)
        env.issecretvalue = function() return true end
        t.eq(ns.make.client(env).ghost(), nil)
    end,

    ["fake: unknown until set; true, false and back to unknown"] = function(t)
        local c = ns.make.fakeClient()
        t.eq(c.ghost(), nil)
        c.setGhost(true)
        t.eq(c.ghost(), true)
        c.setGhost(false)
        t.eq(c.ghost(), false)
        c.setGhost(nil)
        t.eq(c.ghost(), nil)
    end,
}
