-- Gates (S35): lifts and zone passes. Ported from legacy Flow 0.35.377
-- Modules/Nav/Gates.lua. Hand-written tables, made-up spots, test only.
-- Not tested in game.
local _, ns = ...

local N = ns.Nav

local MULGORE, TB, BARRENS = 1412, 1456, 1413

local function w(cont, wx, wy) return { cont = cont, wx = wx, wy = wy } end

local function cross(fromMap, toMap, fw, tw)
    return { from = { map = fromMap, x = 0.40, y = 0.50 }, to = { map = toMap, x = 0.60, y = 0.55 },
             fromWorld = fw, toWorld = tw }
end

local T = {}

T["data: the six walled capitals as legacy Flow has them"] = function(t)
    t.eq(N.GATE_WALLED[TB].lift, true)
    t.eq(N.GATE_WALLED[TB].why, "Thunder Bluff: on a mesa, lifts only")
    t.eq(N.GATE_WALLED[1454].why, "Orgrimmar: behind walls, gates only")
    local n = 0
    for _ in pairs(N.GATE_WALLED) do n = n + 1 end
    t.eq(n, 6)
    t.eq(N.GATE_SAME, 60); t.eq(N.GATE_MAX_STEP, 60); t.eq(N.GATE_MAX, 300)
end

T["learnable: the legacy rules"] = function(t)
    t.eq(N.GateLearnable(MULGORE, 1454, false, true, false, false), true, "into a walled place")
    t.eq(N.GateLearnable(1454, MULGORE, true, false, false, false), false, "out of one on foot: no")
    t.eq(N.GateLearnable(MULGORE, BARRENS, false, false, false, false), true, "between open zones")
    t.eq(N.GateLearnable(MULGORE, TB, false, true, true, false), false, "lift-only, walked the rim: no")
    t.eq(N.GateLearnable(TB, MULGORE, true, false, true, true), true, "lift-only, rode down: yes")
    t.eq(N.GateLearnable(MULGORE, MULGORE, false, false, false, false), false, "same map")
    t.eq(N.GateLearnable(nil, TB, false, true, false, false), false)
end

T["rode: still as the map changed, or a long standstill just ended"] = function(t)
    t.eq(N.GateRode(10, 8, 0, nil), true)
    t.eq(N.GateRode(10, 9.5, 0, nil), false)
    t.eq(N.GateRode(10, nil, 4, 8), true)
    t.eq(N.GateRode(10, nil, 4, 6), false, "ended too long ago")
    t.eq(N.GateRode(10, nil, 1, 9.9), false, "too short")
end

T["learn: refused while the world position is not known"] = function(t)
    local list, added, why = N.GateLearn({}, cross(MULGORE, BARRENS, nil, nil), false)
    t.eq(added, false); t.eq(why, "world unknown"); t.eq(#list, 0)
end

T["learn: a jump over 60 world yards is a teleport, not a walk"] = function(t)
    local _, added, why = N.GateLearn({}, cross(MULGORE, BARRENS, w(1, 0, 0), w(1, 100, 0)), false)
    t.eq(added, false); t.eq(why, "teleport")
    local _, a2, why2 = N.GateLearn({}, cross(MULGORE, BARRENS, w(1, 0, 0), w(0, 1, 0)), false)
    t.eq(a2, false); t.eq(why2, "teleport", "another continent")
end

T["learn: a good crossing keeps both sides"] = function(t)
    local list, added = N.GateLearn({}, cross(MULGORE, BARRENS, w(1, 100, 200), w(1, 105, 200)), false)
    t.eq(added, true)
    t.eq(list[1], { a = MULGORE, b = BARRENS, ax = 0.40, ay = 0.50, bx = 0.60, by = 0.55, cont = 1, wx = 105, wy = 200 })
end

T["learn: not learnable, a duplicate within 60 yards, and the cap"] = function(t)
    local _, a1, why1 = N.GateLearn({}, cross(1454, MULGORE, w(1, 0, 0), w(1, 5, 0)), false)
    t.eq(a1, false); t.eq(why1, "not learnable")
    local list = N.GateLearn({}, cross(MULGORE, BARRENS, w(1, 100, 200), w(1, 105, 200)), false)
    local _, a2, why2 = N.GateLearn(list, cross(BARRENS, MULGORE, w(1, 120, 200), w(1, 125, 200)), false)
    t.eq(a2, false); t.eq(why2, "known")
    local full = {}
    for i = 1, N.GATE_MAX do full[i] = { a = 1, b = 2, cont = 9, wx = i * 1000, wy = 0 } end
    local _, a3, why3 = N.GateLearn(full, cross(MULGORE, BARRENS, w(1, 0, 0), w(1, 5, 0)), false)
    t.eq(a3, false); t.eq(why3, "full")
end

local GATES = {
    { a = MULGORE, b = TB, ax = 0.30, ay = 0.30, bx = 0.5, by = 0.5 },
    { a = TB, b = MULGORE, ax = 0.5, ay = 0.6, bx = 0.70, by = 0.70 },
}

T["step: lead to the gate's side on the player's map, the nearest one"] = function(t)
    local here = { position = { map = MULGORE, x = 0.68, y = 0.68 } }
    local size = function(m) return m == MULGORE and { w = 1000, h = 1000 } or nil end
    local step = N.GateStep(GATES, { map = TB, x = 0.5, y = 0.5 }, here, size)
    t.eq(step, { label = "Way to Thunder Bluff", point = { map = MULGORE, x = 0.70, y = 0.70 }, gate = true })
    local first = N.GateStep(GATES, { map = TB, x = 0.5, y = 0.5 }, here, nil)
    t.eq(first.point, { map = MULGORE, x = 0.30, y = 0.30 }, "no size: the first known, not a guessed nearest")
end

T["step: a walled map with no gate known says so"] = function(t)
    local step, why = N.GateStep({}, { map = TB, x = 0.5, y = 0.5 }, { position = { map = MULGORE, x = 0.5, y = 0.5 } }, nil)
    t.eq(why, "no gate known")
    t.eq(step, { label = "No way in known yet", text = true, detail = "Thunder Bluff: on a mesa, lifts only" })
end

T["step: none for open zones, the same map, or unknown places"] = function(t)
    local here = { position = { map = MULGORE, x = 0.5, y = 0.5 } }
    t.eq(select(2, N.GateStep({}, { map = BARRENS, x = 0.5, y = 0.5 }, here, nil)), "straight line")
    t.eq(select(2, N.GateStep(GATES, { map = MULGORE, x = 0.1, y = 0.1 }, here, nil)), "same map")
    t.eq(select(2, N.GateStep(GATES, { x = 0.5 }, here, nil)), "no target")
    t.eq(select(2, N.GateStep(GATES, { map = TB, x = 0.5, y = 0.5 }, {}, nil)), "position unknown")
end

return T
