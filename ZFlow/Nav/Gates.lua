local _, ns = ...
-- Z-Flow gates (S35): lifts and zone passes, the ways between maps the
-- player cannot walk between in a straight line. Ported from legacy Flow
-- 0.35.377 (Modules/Nav/Gates.lua): the top of Thunder Bluff and its foot
-- are a few yards apart on the map and a lift ride apart on foot, so a
-- straight arrow walks the player into the cliff. Pure. It only says so:
-- nothing moves the player. Not tested in game.
--
-- Gates are learned, never authored: when the player crosses from one map
-- into another on foot (or rides a lift), both sides of the crossing are
-- kept in map shares, so Z-Flow can lead to the gate on the player's own
-- map without world coordinates.
--
-- LEARNING IS OFF until the client gives a world position (CLIENT NEED
-- c.worldPosition()): legacy Flow told a walk from a teleport by the world
-- distance between the two positions, and without it a hearthstone or a
-- portal would be learned as a gate. N.GateLearn refuses with
-- "world unknown" until then.
--
-- N.GATE_WALLED  [uiMapID] = { why, lift } for the six capitals, as legacy
--                Flow has them; lift = true: reached only by lift
-- N.GATE_SAME, N.GATE_MAX_STEP, N.GATE_MAX  60 yd, 60 yd, 300 (legacy)
-- N.GATE_RIDE_STILL, N.GATE_RIDE_SPAN, N.GATE_RIDE_AFTER  1.5, 3, 2.5 s
--
-- N.GateLearnable(from, to, walledFrom, walledTo, liftOnly, rode) -> bool
-- N.GateRode(now, stillSince, lastSpan, endedAt) -> bool
-- N.GateLearn(list, cross, rode) -> list, added, reason
--   cross = { from = { map, x, y }, to = { map, x, y },
--             fromWorld = { cont, wx, wy }, toWorld = { cont, wx, wy } }
--   kept: { a, b, ax, ay, bx, by, cont, wx, wy } appended to list
--   reasons: "no place", "world unknown", "teleport", "not learnable",
--            "full", "known"
-- N.GateStep(gates, target, here, mapSize) -> step, reason
--   step = { label = "Way to <name>", point = { map, x, y } (the gate's
--            side on the player's map), gate = true }, or for a walled map
--          with no gate known { label = "No way in known yet", text = true,
--          detail = why }
--   reasons: "no target", "position unknown", "same map",
--            "no gate known" (with the text step), "straight line"
--   The nearest gate in yards when mapSize(map) gives { w, h }; otherwise
--   the first known (a nearest is not guessed).
ns.Nav = ns.Nav or {}
local N = ns.Nav

N.GATE_WALLED = {
    [1456] = { why = "Thunder Bluff: on a mesa, lifts only", lift = true },
    [1454] = { why = "Orgrimmar: behind walls, gates only" },
    [1458] = { why = "Undercity: underground, lifts and the sewers" },
    [1453] = { why = "Stormwind: behind walls, gates only" },
    [1455] = { why = "Ironforge: inside a mountain, gates only" },
    [1457] = { why = "Darnassus: on Teldrassil, a portal" },
}
N.GATE_SAME = 60
N.GATE_MAX_STEP = 60
N.GATE_MAX = 300
N.GATE_RIDE_STILL = 1.5
N.GATE_RIDE_SPAN = 3
N.GATE_RIDE_AFTER = 2.5
N.GATE_PLAIN = "Way to your next step"
N.GATE_UNKNOWN = "No way in known yet"

local function share(v) return type(v) == "number" and v >= 0 and v <= 1 end
local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

local function dist(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

local function world(p)
    return type(p) == "table" and p.cont ~= nil and finite(p.wx) and finite(p.wy)
end

local function walled(map) return N.GATE_WALLED[map] end

local function labelMax()
    return (N.Waypoint and N.Waypoint.LABEL_MAX) or (ns.Waypoint and ns.Waypoint.LABEL_MAX) or 40
end

-- Into a walled place: yes. Out of one into the open on foot: no. A place
-- only lifts reach: only when the player rode, and then either way.
function N.GateLearnable(from, to, walledFrom, walledTo, liftOnly, rode)
    if from == nil or to == nil or from == to then return false end
    if liftOnly then return rode == true end
    if walledFrom and not walledTo then return false end
    return true
end

function N.GateRode(now, stillSince, lastSpan, endedAt)
    if not finite(now) then return false end
    if finite(stillSince) and now - stillSince >= N.GATE_RIDE_STILL then return true end
    return (finite(lastSpan) and lastSpan or 0) >= N.GATE_RIDE_SPAN
        and finite(endedAt) and now - endedAt <= N.GATE_RIDE_AFTER
end

function N.GateLearn(list, cross, rode)
    if type(list) ~= "table" then list = {} end
    if type(cross) ~= "table" then return list, false, "no place" end
    local f, t = cross.from, cross.to
    if type(f) ~= "table" or type(t) ~= "table" or type(f.map) ~= "number" or type(t.map) ~= "number"
        or not (share(f.x) and share(f.y) and share(t.x) and share(t.y)) then
        return list, false, "no place"
    end
    local fw, tw = cross.fromWorld, cross.toWorld
    if not (world(fw) and world(tw)) then return list, false, "world unknown" end
    if fw.cont ~= tw.cont or dist(fw.wx, fw.wy, tw.wx, tw.wy) > N.GATE_MAX_STEP then
        return list, false, "teleport"
    end
    local wa, wb = walled(f.map), walled(t.map)
    local liftOnly = (wa and wa.lift == true) or (wb and wb.lift == true) or false
    if not N.GateLearnable(f.map, t.map, wa ~= nil, wb ~= nil, liftOnly, rode) then
        return list, false, "not learnable"
    end
    if #list >= N.GATE_MAX then return list, false, "full" end
    for _, g in ipairs(list) do
        if type(g) == "table" and g.cont == tw.cont and finite(g.wx) and finite(g.wy)
            and ((g.a == f.map and g.b == t.map) or (g.a == t.map and g.b == f.map))
            and dist(g.wx, g.wy, tw.wx, tw.wy) < N.GATE_SAME then
            return list, false, "known"
        end
    end
    list[#list + 1] = { a = f.map, b = t.map, ax = f.x, ay = f.y, bx = t.x, by = t.y,
                        cont = tw.cont, wx = tw.wx, wy = tw.wy }
    return list, true
end

-- The name a walled map's reason starts with ("Thunder Bluff"), or nil.
local function nameOf(map)
    local w = walled(map)
    if not w or type(w.why) ~= "string" then return nil end
    return w.why:match("^([^:]+):")
end

function N.GateStep(gates, target, here, mapSize)
    if type(target) ~= "table" or type(target.map) ~= "number" then return nil, "no target" end
    local pos = type(here) == "table" and here.position or nil
    if type(pos) ~= "table" or type(pos.map) ~= "number" then return nil, "position unknown" end
    if pos.map == target.map then return nil, "same map" end
    local size = type(mapSize) == "function" and mapSize(pos.map) or nil
    local sized = type(size) == "table" and finite(size.w) and finite(size.h) and size.w > 0 and size.h > 0
        and share(pos.x) and share(pos.y)
    local best, bestD
    for _, g in ipairs(type(gates) == "table" and gates or {}) do
        local x, y
        if type(g) == "table" and g.a == pos.map and g.b == target.map then
            x, y = g.ax, g.ay
        elseif type(g) == "table" and g.b == pos.map and g.a == target.map then
            x, y = g.bx, g.by
        end
        if share(x) and share(y) then
            if not best then
                best = { x = x, y = y }
                bestD = sized and dist(pos.x * size.w, pos.y * size.h, x * size.w, y * size.h) or nil
            elseif sized then
                local d = dist(pos.x * size.w, pos.y * size.h, x * size.w, y * size.h)
                if d < bestD then best, bestD = { x = x, y = y }, d end
            end
        end
    end
    if best then
        local name = nameOf(target.map)
        local label = name and ("Way to " .. name) or N.GATE_PLAIN
        if #label > labelMax() then label = N.GATE_PLAIN end
        return { label = label, point = { map = pos.map, x = best.x, y = best.y }, gate = true }
    end
    local w = walled(target.map) or walled(pos.map)
    if w then
        return { label = N.GATE_UNKNOWN, text = true, detail = w.why }, "no gate known"
    end
    return nil, "straight line"
end
