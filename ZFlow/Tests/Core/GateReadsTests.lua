-- The two reads the arrow gate needs, over a hand-built environment and on
-- the fake client: whether the player is dead or a ghost, and where their
-- corpse is on the player's map. No game client is involved.
local _, ns = ...

local function boom() error("the client refused") end

-- The player stands on map 1411; the corpse is on it at 0.25, 0.75.
local function deathEnv()
    local env = { here = 1411, dead = true, x = 0.25, y = 0.75 }
    env.UnitIsDeadOrGhost = function(unit)
        if unit ~= "player" then return nil end
        return env.dead
    end
    env.C_Map = { GetBestMapForUnit = function(unit) return unit == "player" and env.here or nil end }
    env.C_DeathInfo = {
        GetCorpseMapPosition = function(map)
            if map ~= env.here or not env.x then return nil end
            return { GetXY = function() return env.x, env.y end }
        end,
    }
    return env
end

return {
    ["dead: the client's own answer, for the player only"] = function(t)
        local env = deathEnv()
        local c = ns.make.client(env)
        t.eq(c.dead(), true)
        env.dead = false
        t.eq(c.dead(), false)
        local asked = {}
        env.UnitIsDeadOrGhost = function(unit)
            asked[#asked + 1] = unit
            return true
        end
        c.dead()
        t.eq(asked, { "player" })
    end,

    ["dead: unknown when the client gives no answer"] = function(t)
        local env = deathEnv()
        local c = ns.make.client(env)
        env.dead = nil
        t.eq(c.dead(), nil, "no answer")
        env.dead = 1
        t.eq(c.dead(), nil, "not a yes or no")
        env.UnitIsDeadOrGhost = boom
        t.eq(c.dead(), nil, "the read fails")
        env.UnitIsDeadOrGhost = nil
        t.eq(c.dead(), nil, "no such read")
        t.eq(ns.make.client({}).dead(), nil)
    end,

    ["dead: a hidden answer is unknown"] = function(t)
        local env = deathEnv()
        env.issecretvalue = function() return true end
        t.eq(ns.make.client(env).dead(), nil)
    end,

    ["corpse: the player's map and where the corpse is on it"] = function(t)
        local env = deathEnv()
        local c = ns.make.client(env)
        t.eq(c.corpse(), { map = 1411, x = 0.25, y = 0.75 })
        env.C_DeathInfo.GetCorpseMapPosition = function() return { x = 0.5, y = 0.125 } end
        t.eq(c.corpse(), { map = 1411, x = 0.5, y = 0.125 }, "a position with plain x and y")
    end,

    ["corpse: asked for the player's map alone"] = function(t)
        local env = deathEnv()
        local asked = {}
        env.C_DeathInfo.GetCorpseMapPosition = function(...)
            asked[#asked + 1] = { ... }
            return { x = 0.5, y = 0.5 }
        end
        ns.make.client(env).corpse()
        t.eq(asked, { { 1411 } })
    end,

    ["corpse: unknown when any part is missing or errors"] = function(t)
        local env = deathEnv()
        local c = ns.make.client(env)
        env.x = nil
        t.eq(c.corpse(), false, "the client answers: no corpse position here (C1)")
        env.x = 0.25
        env.C_DeathInfo.GetCorpseMapPosition = function() return { GetXY = function() return 0 / 0, 0.5 end } end
        t.eq(c.corpse(), nil, "not a number")
        env.C_DeathInfo.GetCorpseMapPosition = function() return { x = "left", y = 0.5 } end
        t.eq(c.corpse(), nil)
        env.C_DeathInfo.GetCorpseMapPosition = function() return 0.5 end
        t.eq(c.corpse(), nil, "not a position")
        env.C_DeathInfo.GetCorpseMapPosition = boom
        t.eq(c.corpse(), nil)
        env.C_DeathInfo.GetCorpseMapPosition = nil
        t.eq(c.corpse(), nil)
        env.C_DeathInfo = nil
        t.eq(c.corpse(), nil)
        env = deathEnv()
        env.C_Map.GetBestMapForUnit = boom
        t.eq(ns.make.client(env).corpse(), nil, "no map for the player")
        env.C_Map = nil
        t.eq(ns.make.client(env).corpse(), nil)
        t.eq(ns.make.client({}).corpse(), nil)
    end,

    ["corpse: a hidden answer is unknown"] = function(t)
        local env = deathEnv()
        env.issecretvalue = function(v) return type(v) == "number" end
        t.eq(ns.make.client(env).corpse(), nil)
    end,

    ["corpse: a hidden position is unknown, its numbers plain or not (H3)"] = function(t)
        local env = deathEnv()
        t.ok(ns.make.client(env).corpse() ~= nil, "plain: a place")
        env.issecretvalue = function(v) return type(v) == "table" end
        t.eq(ns.make.client(env).corpse(), nil)
    end,

    ["fake: dead and corpse are unknown until set, and can be unset"] = function(t)
        local c = ns.make.fakeClient()
        t.eq(c.dead(), nil)
        t.eq(c.corpse(), nil)
        c.setDead(true)
        t.eq(c.dead(), true)
        c.setDead(false)
        t.eq(c.dead(), false)
        c.setDead(nil)
        t.eq(c.dead(), nil)
        c.setCorpse(1411, 0.25, 0.75)
        local got = c.corpse()
        t.eq(got, { map = 1411, x = 0.25, y = 0.75 })
        got.x = 9
        t.eq(c.corpse().x, 0.25, "a copy is handed out")
        c.setCorpse(nil)
        t.eq(c.corpse(), nil)
    end,
}
