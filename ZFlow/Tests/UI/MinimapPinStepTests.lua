local _, ns = ...

-- Tests for FLOW-PARITY A2-23 in ZFlow/UI/MinimapPin.lua: the minimap pin
-- shows where the arrow points now (its step, any kind), as legacy Flow's
-- pin sits at the arrow's point (Modules/Nav/MinimapPin.lua P:Update), with
-- your own waypoint first. Made-up places.

local tests = {}

local Pin = ns.MinimapPin
local MAP = 1436
local ROUND = { size = 140, radius = 100, rotates = false }

local function client()
    local c = ns.make.fakeClient()
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 1)
    c.setMinimap(ROUND)
    return c
end

tests["minimap pin step: your waypoint first, else where the arrow points, else none"] = function(t)
    local wp = { map = MAP, x = 0.52, y = 0.47 }
    local step = { map = MAP, x = 0.6, y = 0.5 }
    t.eq(Pin.Target(wp, step), wp, "your waypoint wins")
    t.eq(Pin.Target(nil, step), step, "else the arrow's step")
    local none, why = Pin.Target(nil, nil)
    t.eq(none, nil)
    t.eq(why, Pin.NONE)
    t.eq((Pin.Target(nil, { map = MAP, x = 0 / 0, y = 0.5 })), nil, "a place that is not a number is none")
end

tests["minimap pin step: with no waypoint the pin goes where the arrow points"] = function(t)
    local c, state = client(), {}
    local r = Pin.Update(c, nil, state, { map = MAP, x = 0.52, y = 0.47 })
    t.eq(r.shown, true)
    t.ok(math.abs(r.x - 14) < 0.01 and math.abs(r.y - 21) < 0.01, "20 yd east, 30 north: " .. tostring(r.x))
end

tests["minimap pin step: an old caller with no step still pins nothing without a waypoint"] = function(t)
    local r = Pin.Update(client(), nil, {})
    t.eq(r.shown, false)
    t.eq(r.reason, Pin.NONE)
end

return tests
