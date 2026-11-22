-- The read of the player's own map waypoint, over a hand-built environment
-- and on the fake client. No game client is involved.
local _, ns = ...

local function boom() error("the client refused") end

-- A waypoint set on map 1411 at 0.25, 0.75.
local function pinEnv()
    local env = { has = true, map = 1411, x = 0.25, y = 0.75 }
    env.C_Map = {
        HasUserWaypoint = function() return env.has end,
        GetUserWaypoint = function()
            if not env.has then return nil end
            return { uiMapID = env.map, position = { GetXY = function() return env.x, env.y end } }
        end,
    }
    return env
end

return {
    ["waypoint: absent API is nil"] = function(t)
        t.eq(ns.make.client({}).waypoint(), nil, "no C_Map at all")
        t.eq(ns.make.client({ C_Map = {} }).waypoint(), nil, "C_Map without the two calls")
        t.eq(ns.make.client({ C_Map = "no" }).waypoint(), nil, "C_Map is not a table")
        local env = pinEnv()
        env.C_Map.GetUserWaypoint = nil
        t.eq(ns.make.client(env).waypoint(), nil, "asked whether, but no way to ask where")
    end,

    ["waypoint: none set is nil"] = function(t)
        local env = pinEnv()
        local c = ns.make.client(env)
        env.has = false
        t.eq(c.waypoint(), nil)
        env.has = true
        env.C_Map.GetUserWaypoint = function() return nil end
        t.eq(c.waypoint(), nil, "the client says yes but hands back nothing")
    end,

    ["waypoint: set gives the map and the two shares"] = function(t)
        local env = pinEnv()
        local c = ns.make.client(env)
        t.eq(c.waypoint(), { map = 1411, x = 0.25, y = 0.75 })
        env.map, env.x, env.y = 1412, 0, 1
        t.eq(c.waypoint(), { map = 1412, x = 0, y = 1 }, "the edges are places")
    end,

    ["waypoint: a position with plain x and y fields is read"] = function(t)
        local env = pinEnv()
        env.C_Map.GetUserWaypoint = function() return { uiMapID = 1411, position = { x = 0.4, y = 0.6 } } end
        t.eq(ns.make.client(env).waypoint(), { map = 1411, x = 0.4, y = 0.6 })
    end,

    ["waypoint: without the has call, the where call alone answers"] = function(t)
        local env = pinEnv()
        env.C_Map.HasUserWaypoint = nil
        local c = ns.make.client(env)
        t.eq(c.waypoint(), { map = 1411, x = 0.25, y = 0.75 })
        env.has = false
        t.eq(c.waypoint(), nil)
    end,

    ["waypoint: a malformed answer is nil"] = function(t)
        local env = pinEnv()
        local c = ns.make.client(env)
        local bad = {
            "a string", 7, true, {},
            { uiMapID = 1411 },
            { uiMapID = 1411, position = "there" },
            { uiMapID = 1411, position = {} },
            { uiMapID = "1411", position = { x = 0.5, y = 0.5 } },
            { position = { x = 0.5, y = 0.5 } },
            { uiMapID = 1411, position = { x = "left", y = 0.5 } },
            { uiMapID = 1411, position = { x = 0.5 } },
            { uiMapID = 1411, position = { x = 0 / 0, y = 0.5 } },
            { uiMapID = 1411, position = { x = 1.5, y = 0.5 } },
            { uiMapID = 1411, position = { x = 0.5, y = -0.1 } },
            { uiMapID = 1411, position = { GetXY = function() return "a", "b" end } },
        }
        for i = 1, #bad do
            env.C_Map.GetUserWaypoint = function() return bad[i] end
            t.eq(c.waypoint(), nil, "malformed answer " .. i)
        end
    end,

    ["waypoint: a has answer that is not a plain yes is nil"] = function(t)
        local env = pinEnv()
        local c = ns.make.client(env)
        env.has = 1
        t.eq(c.waypoint(), nil, "not a yes or no")
        env.has = nil
        env.C_Map.GetUserWaypoint = function()
            return { uiMapID = 1411, position = { x = 0.5, y = 0.5 } }
        end
        t.eq(c.waypoint(), nil, "no answer to whether")
    end,

    ["waypoint: a failing read is nil"] = function(t)
        local env = pinEnv()
        local c = ns.make.client(env)
        env.C_Map.HasUserWaypoint = boom
        t.eq(c.waypoint(), nil, "has fails")
        env = pinEnv()
        c = ns.make.client(env)
        env.C_Map.GetUserWaypoint = boom
        t.eq(c.waypoint(), nil, "where fails")
        env = pinEnv()
        c = ns.make.client(env)
        env.C_Map.GetUserWaypoint = function() return { uiMapID = 1411, position = { GetXY = boom } } end
        t.eq(c.waypoint(), nil, "GetXY fails and there are no plain fields")
    end,

    ["waypoint: a hidden answer is nil"] = function(t)
        local env = pinEnv()
        env.issecretvalue = function() return true end
        t.eq(ns.make.client(env).waypoint(), nil)
    end,

    ["fake: unknown until set, a copy each time, cleared with nil"] = function(t)
        local c = ns.make.fakeClient()
        t.eq(c.waypoint(), nil)
        c.setWaypoint(1411, 0.3, 0.6)
        t.eq(c.waypoint(), { map = 1411, x = 0.3, y = 0.6 })
        c.waypoint().x = 9
        t.eq(c.waypoint().x, 0.3, "the answer is a copy")
        c.setWaypoint(nil)
        t.eq(c.waypoint(), nil)
    end,
}
