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
    t.eq((Pin.Target(wp, step)), wp, "your waypoint wins")
    t.eq((Pin.Target(nil, step)), step, "else the arrow's step")
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

-- Builder 1's review (A2-23): the report says what the pin stands for, so
-- the drawing lane can colour it as Flow did (MinimapPin.lua :397-398: your
-- waypoint or a party member you follow green, a route step the route's).
tests["minimap pin step: the report says waypoint or step; a followed member is a waypoint"] = function(t)
    local c = client()
    local step = { map = MAP, x = 0.52, y = 0.47 }
    t.eq(Pin.Update(c, nil, {}, step).source, "step", "the arrow's step")
    t.eq(Pin.Update(c, nil, {}, step, true).source, "waypoint", "a party member you follow")
    local _, src = Pin.Target(step, nil)
    t.eq(src, "waypoint", "your own waypoint")
end

-- Lead section 749 (builder 1's A2-23 note): Nav/Follow.lua's Step reads
-- the party (client.party) on every call, so the pin asks it at most every
-- Pin.FOLLOW_EVERY seconds, and in a fight (or a fight not known) not at
-- all beyond the answer it holds. Fails before: asked on every look.
tests["minimap pin step: the follow read is kept for a while, and not made in a fight"] = function(t)
    t.eq(Pin.FOLLOW_EVERY, 0.5)
    t.eq(type(Pin.Followed), "function")
    if type(Pin.Followed) ~= "function" then return end
    local reads = 0
    local function read() reads = reads + 1 return true end
    local memo = {}
    t.eq(Pin.Followed(memo, 10, false, read), true, "first look: read")
    t.eq(reads, 1)
    t.eq(Pin.Followed(memo, 10.3, false, read), true, "within half a second: kept")
    t.eq(reads, 1)
    t.eq(Pin.Followed(memo, 10.6, false, read), true, "after it: read again")
    t.eq(reads, 2)
    t.eq(Pin.Followed(memo, 20, true, read), true, "in a fight: the kept answer, no read")
    t.eq(Pin.Followed(memo, 30, nil, read), true, "a fight not known: no read")
    t.eq(reads, 2)
    local fresh = {}
    t.eq(Pin.Followed(fresh, 5, true, read), false, "in a fight with nothing kept: not followed, no read")
    t.eq(reads, 2)
    t.eq(Pin.Followed({}, nil, false, read), true, "no clock: read each time")
    t.eq(reads, 3)
    t.eq(Pin.Followed({}, 1, false, function() error("refused") end), false, "a read that raises: not followed")
end

return tests
