-- c.worldPosition() and c.onTaxi() (S35, LEDGER 150/153): the two reads
-- Nav/Gates.lua needs before it may learn a gate. The real client over a
-- hand-built environment; ClientFake's own versions are checked at the end.
--   c.worldPosition() -> { cont, wx, wy } in world yards, or nil
--   c.onTaxi()        -> true / false, or nil when the client will not say
-- Unknown stays unknown: a read that fails, answers the wrong shape or is
-- marked secret gives nil, never a made-up place and never "not on a taxi".
local _, ns = ...

local tests = {}

-- A client whose map calls answer from `at` ({ map, x, y, cont, wx, wy }).
local function mapEnv(at, extra)
    local env = {}
    local pos = { GetXY = function() return at.x, at.y end }
    env.C_Map = {
        GetBestMapForUnit = function(unit) return unit == "player" and at.map or nil end,
        GetPlayerMapPosition = function(map, unit)
            if map ~= at.map or unit ~= "player" then return nil end
            return pos
        end,
        GetWorldPosFromMapPos = function(map, p)
            env.askedWorld = { map = map, pos = p }
            if at.noWorld then return nil end
            return at.cont, { GetXY = function() return at.wx, at.wy end }
        end,
    }
    for k, v in pairs(extra or {}) do env[k] = v end
    return env, pos
end

tests["c.worldPosition: the continent and world yards of where the player stands"] = function(t)
    local env, pos = mapEnv({ map = 1411, x = 0.5, y = 0.25, cont = 1, wx = -4000.5, wy = 1200 })
    local c = ns.make.client(env)
    t.eq(c.worldPosition(), { cont = 1, wx = -4000.5, wy = 1200 })
    t.eq(env.askedWorld.map, 1411, "asked for the map the player is on")
    t.ok(env.askedWorld.pos == pos, "with the client's own position value")
end

tests["c.worldPosition: nil when any part is not known"] = function(t)
    t.eq(ns.make.client({}).worldPosition(), nil, "no map calls at all")
    local noWorld = mapEnv({ map = 1411, x = 0.5, y = 0.5, cont = 1, wx = 1, wy = 1, noWorld = true })
    t.eq(ns.make.client(noWorld).worldPosition(), nil, "the client gives no world point")
    local noCont = mapEnv({ map = 1411, x = 0.5, y = 0.5, cont = nil, wx = 1, wy = 1 })
    t.eq(ns.make.client(noCont).worldPosition(), nil, "no continent: not a world position")
    local nan = mapEnv({ map = 1411, x = 0.5, y = 0.5, cont = 1, wx = 0 / 0, wy = 1 })
    t.eq(ns.make.client(nan).worldPosition(), nil, "a coordinate that is not a number")
    local text = mapEnv({ map = 1411, x = 0.5, y = 0.5, cont = 1, wx = "x", wy = 1 })
    t.eq(ns.make.client(text).worldPosition(), nil)
    local noMap = mapEnv({ map = nil, x = 0.5, y = 0.5, cont = 1, wx = 1, wy = 1 })
    t.eq(ns.make.client(noMap).worldPosition(), nil, "no map for the player")
end

tests["c.worldPosition: a call that raises, or a vector with fields, is handled"] = function(t)
    local env = mapEnv({ map = 1411, x = 0.5, y = 0.5, cont = 1, wx = 1, wy = 1 })
    env.C_Map.GetWorldPosFromMapPos = function() error("refused") end
    t.eq(ns.make.client(env).worldPosition(), nil, "raised: not known")
    local fields = mapEnv({ map = 1411, x = 0.5, y = 0.5, cont = 0, wx = 1, wy = 1 })
    fields.C_Map.GetWorldPosFromMapPos = function() return 0, { x = 10, y = -20 } end
    t.eq(ns.make.client(fields).worldPosition(), { cont = 0, wx = 10, wy = -20 }, "a vector with x and y and no GetXY")
end

tests["c.worldPosition: a secret answer is not known"] = function(t)
    local env = mapEnv({ map = 1411, x = 0.5, y = 0.5, cont = 1, wx = 777, wy = 1 })
    env.issecretvalue = function(v)
        if v == nil then error("issecretvalue: nil") end
        return v == 777
    end
    t.eq(ns.make.client(env).worldPosition(), nil, "one secret coordinate: no position")
end

tests["c.onTaxi: true, false, or not known"] = function(t)
    local asked
    local c = ns.make.client({ UnitOnTaxi = function(unit) asked = unit return true end })
    t.eq(c.onTaxi(), true)
    t.eq(asked, "player", "only the player is asked about")
    t.eq(ns.make.client({ UnitOnTaxi = function() return false end }).onTaxi(), false)
    t.eq(ns.make.client({}).onTaxi(), nil, "no such call: not known, never false")
    t.eq(ns.make.client({ UnitOnTaxi = function() error("no") end }).onTaxi(), nil, "raised")
    t.eq(ns.make.client({ UnitOnTaxi = function() return nil end }).onTaxi(), nil, "no answer")
    t.eq(ns.make.client({ UnitOnTaxi = function() return 1 end }).onTaxi(), nil, "not a plain yes or no")
    local secret = ns.make.client({ UnitOnTaxi = function() return false end, issecretvalue = function() return true end })
    t.eq(secret.onTaxi(), nil, "a secret answer")
end

tests["fake client: worldPosition and onTaxi are unknown until set"] = function(t)
    local c = ns.make.fakeClient()
    t.eq(c.worldPosition(), nil)
    t.eq(c.onTaxi(), nil)
    c.setWorldPosition(1, 100, -200)
    c.setOnTaxi(false)
    t.eq(c.worldPosition(), { cont = 1, wx = 100, wy = -200 })
    t.eq(c.onTaxi(), false)
    local got = c.worldPosition()
    got.wx = 5
    t.eq(c.worldPosition().wx, 100, "a copy each time")
    c.setOnTaxi(true)
    t.eq(c.onTaxi(), true)
    c.setWorldPosition(nil)
    c.setOnTaxi(nil)
    t.eq(c.worldPosition(), nil)
    t.eq(c.onTaxi(), nil)
end

return tests
