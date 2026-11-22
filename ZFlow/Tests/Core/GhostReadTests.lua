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

-- The player stands on map 1411; `answer` is what the client says of the
-- corpse there (a function is called for it).
local function corpseEnv(answer)
    local env = { here = 1411 }
    env.C_Map = { GetBestMapForUnit = function(unit) return unit == "player" and env.here or nil end }
    env.C_DeathInfo = { GetCorpseMapPosition = function()
        if type(answer) == "function" then return answer() end
        return answer
    end }
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

    ["corpse: the client answers with no position on the player's map: false, not unknown (C1)"] = function(t)
        t.eq(ns.make.client(corpseEnv(nil)).corpse(), false)
        t.eq(ns.make.client(corpseEnv({ x = 0.25, y = 0.75 })).corpse(), { map = 1411, x = 0.25, y = 0.75 },
            "a position is still a place")
    end,

    ["corpse: cannot tell is nil, never false (C1)"] = function(t)
        local env = corpseEnv(nil)
        env.here = nil
        t.eq(ns.make.client(env).corpse(), nil, "no map for the player")
        env = corpseEnv(nil)
        env.C_DeathInfo.GetCorpseMapPosition = nil
        t.eq(ns.make.client(env).corpse(), nil, "no such read")
        env.C_DeathInfo = nil
        t.eq(ns.make.client(env).corpse(), nil, "no such group")
        t.eq(ns.make.client(corpseEnv(boom)).corpse(), nil, "the read raised")
        t.eq(ns.make.client(corpseEnv({})).corpse(), nil, "a position with no x or y")
        t.eq(ns.make.client(corpseEnv({ x = "left", y = 0.5 })).corpse(), nil, "x is no number")
        t.eq(ns.make.client(corpseEnv(false)).corpse(), nil, "an answer that is neither nothing nor a position")
        t.eq(ns.make.client(corpseEnv(0.5)).corpse(), nil, "a number")
        env = corpseEnv({ x = 0.25, y = 0.75 })
        env.issecretvalue = function(v) return type(v) == "number" end
        t.eq(ns.make.client(env).corpse(), nil, "x and y hidden")
    end,

    ["fake: the corpse is unknown until set; a place, on no position of this map, and unknown again (C1)"] = function(t)
        local c = ns.make.fakeClient()
        t.eq(c.corpse(), nil)
        c.setCorpse(false)
        t.eq(c.corpse(), false)
        c.setCorpse(1411, 0.25, 0.75)
        t.eq(c.corpse(), { map = 1411, x = 0.25, y = 0.75 })
        c.setCorpse(nil)
        t.eq(c.corpse(), nil)
    end,

    -- H3: the answer itself may be hidden. It is asked about before it is
    -- compared or read.
    ["corpse: a hidden answer is nil, and is not looked into (H3)"] = function(t)
        local read = 0
        local pos = setmetatable({}, { __index = function(_, k)
            read = read + 1
            if k == "x" then return 0.25 end
            if k == "y" then return 0.75 end
            return nil
        end })
        local env = corpseEnv(pos)
        t.eq(ns.make.client(env).corpse(), { map = 1411, x = 0.25, y = 0.75 }, "not hidden: the place")
        read = 0
        env.issecretvalue = function(v) return v == pos end
        t.eq(ns.make.client(env).corpse(), nil, "hidden: cannot tell")
        t.eq(read, 0, "nothing of a hidden answer is read")
        env.issecretvalue = function(v)
            if v == pos then error("the client refused") end
            return false
        end
        t.eq(ns.make.client(env).corpse(), nil, "the hidden check itself fails: treated as hidden")
        env = corpseEnv(nil)
        env.issecretvalue = function() return false end
        t.eq(ns.make.client(env).corpse(), false, "a plain nothing, not hidden, is still false")
    end,
}
