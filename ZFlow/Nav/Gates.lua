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
-- LEARNING IS OFF until the client gives a world position and a taxi
-- read (CLIENT NEEDs c.worldPosition() and c.onTaxi()): legacy Flow told a
-- walk from a teleport by the world distance between the two positions,
-- and never took a flight for a walk. Without them a hearthstone, a portal
-- or a flight path would be learned as a gate, so N.GateLearn refuses with
-- "world unknown" or "taxi unknown" until then.
--
-- N.GATE_WALLED  [uiMapID] = { why, lift } for the six capitals, as legacy
--                Flow has them; lift = true: reached only by lift. Only
--                Thunder Bluff's number (1456) was seen in play by legacy
--                Flow; 1453, 1454, 1455, 1457 and 1458 are inferred from
--                its data and need the client to confirm.
-- N.GATE_SAME, N.GATE_MAX_STEP, N.GATE_MAX  60 yd, 60 yd, 300 (legacy)
-- N.GATE_RIDE_STILL, N.GATE_RIDE_SPAN, N.GATE_RIDE_AFTER  1.5, 3, 2.5 s
--
-- N.GateLearnable(from, to, walledFrom, walledTo, liftOnly, rode) -> bool
-- N.GateRode(now, stillSince, lastSpan, endedAt) -> bool
-- N.GateLearn(list, cross, rode, onTaxi) -> list, added, reason
--   cross = { from = { map, x, y }, to = { map, x, y },
--             fromWorld = { cont, wx, wy }, toWorld = { cont, wx, wy } }
--   onTaxi: client.onTaxi(); only a plain false lets it learn (true:
--   "carried", nil: "taxi unknown")
--   kept: { a, b, ax, ay, bx, by, cont, wx, wy } appended to list
--   reasons: "no place", "world unknown", "taxi unknown", "carried",
--            "teleport", "not learnable", "full", "known"
-- N.GateTracker() -> tracker; tracker:Sample(p, world, onTaxi, now) -> cross
--   or nil. The legacy G.Track sampler: fed each position tick, it returns
--   a cross (with rode, from N.GateRode) when the map changed since the
--   last sample. A taxi, an unknown taxi, no position or no world point
--   resets it. The caller hands it on: N.GateLearn(list, cross, cross.rode,
--   cross.onTaxi).
-- N.GateForget(list)  empties the learned list (legacy /flow gates forget)
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
N.GATE_STILL_SPEED = 1   -- world yards a second: slower is standing
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

function N.GateLearn(list, cross, rode, onTaxi)
    if type(list) ~= "table" then list = {} end
    if type(cross) ~= "table" then return list, false, "no place" end
    local f, t = cross.from, cross.to
    if type(f) ~= "table" or type(t) ~= "table" or type(f.map) ~= "number" or type(t.map) ~= "number"
        or not (share(f.x) and share(f.y) and share(t.x) and share(t.y)) then
        return list, false, "no place"
    end
    local fw, tw = cross.fromWorld, cross.toWorld
    if not (world(fw) and world(tw)) then return list, false, "world unknown" end
    if onTaxi == true then return list, false, "carried" end
    if onTaxi ~= false then return list, false, "taxi unknown" end
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

function N.GateForget(list)
    if type(list) ~= "table" then return end
    for i = #list, 1, -1 do list[i] = nil end
    for key in pairs(list) do list[key] = nil end
end

function N.GateTracker()
    local tr = { last = nil, still = { since = nil, lastSpan = 0, endedAt = nil } }
    local function reset()
        tr.last = nil
        tr.still.since, tr.still.lastSpan, tr.still.endedAt = nil, 0, nil
    end
    function tr:Sample(p, w, onTaxi, now)
        if type(p) ~= "table" or type(p.map) ~= "number" or not share(p.x) or not share(p.y)
            or not world(w) or onTaxi ~= false or not finite(now) then
            reset()
            return nil
        end
        local last, cross = self.last, nil
        if last and last.world.cont == w.cont then
            local moved = dist(w.wx, w.wy, last.world.wx, last.world.wy)
            local dt = math.max(now - last.t, 0.01)
            if moved / dt < N.GATE_STILL_SPEED then
                self.still.since = self.still.since or now
            else
                if self.still.since then self.still.lastSpan, self.still.endedAt = now - self.still.since, now end
                self.still.since = nil
            end
            if last.map ~= p.map then
                cross = { from = { map = last.map, x = last.x, y = last.y }, to = { map = p.map, x = p.x, y = p.y },
                          fromWorld = last.world, toWorld = { cont = w.cont, wx = w.wx, wy = w.wy }, onTaxi = false,
                          rode = N.GateRode(now, self.still.since, self.still.lastSpan, self.still.endedAt) }
            end
        end
        self.last = { map = p.map, x = p.x, y = p.y, t = now, world = { cont = w.cont, wx = w.wx, wy = w.wy } }
        return cross
    end
    return tr
end

-- ---------------------------------------------------------------- module
-- The watcher and the step kind (LEDGER 150/153). Now that the client gives
-- a world position and a taxi read (Core/Client.lua: c.worldPosition,
-- c.onTaxi), learning can run: every N.Gates.EVERY seconds the tracker is
-- fed where the player is, and a crossing it reports goes to N.GateLearn.
-- Everything N.GateLearn and the tracker refuse is still refused: with
-- either read unknown nothing is learned, and nothing is ever guessed.
--
-- LOOK ONLY. It reads the player's place and writes Z-Flow's own saved
-- data (account "learned.places.gates", where Flow's imported gates also
-- are). It never moves, flies, clicks or casts for the player.
--
--   N.Gates.Declare(k) -> api
--     api.sample()       one watcher tick now -> report, or nil when no
--                        crossing was seen: { added, reason, cross }. Asked
--                        twice at one moment it answers once.
--     api.step(target)   target = { map }: the way to it -> step, reason
--     api.count()        how many learned gates name both their maps
--   ns.use("gates") -> { Step = api.step, Count = api.count }
--   step = { kind = "gate", label, place = { cont, map, x, y }, radius } in
--          the shape Nav/ProfStep.lua gives the guide (a new step kind), or
--          for a walled map with no gate known the text step
--          { kind = "gate", label = N.GATE_UNKNOWN, text = true, detail }.
--   Nav/RoutePlan.lua and Nav/Guide.lua are not changed: whoever plans or
--   draws takes the step from ns.use("gates").Step(target).
-- No setting is read here. A row to turn learning off ("nav.gates") is the
-- lead's to add with the settings model; until then it runs whenever both
-- reads answer.
N.Gates = N.Gates or {}
local Gates = N.Gates

Gates.NAME = "gates"
Gates.KIND = "gate"
Gates.PATH = "learned.places.gates"
Gates.EVERY = 0.5      -- seconds between watcher ticks (a first guess)
Gates.NEAR = 10        -- yards from the gate that count as there (as N.PROF_NEAR)

-- One read of the client, or nil when it has no such read or it fails.
local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if not ok then return nil end
    return v
end

function Gates.Declare(k)
    local api = {}
    local ctx
    local tracker = N.GateTracker()
    local sampledAt, lastReport = nil, nil

    local function saved()
        local ok, list = pcall(ctx.store.get, ctx.store, "account", Gates.PATH)
        if ok and type(list) == "table" then return list end
        return nil
    end

    function api.sample()
        if not ctx then return nil end
        local now = ask(ctx.client, "uptime")
        -- Asked again at the same moment: the same answer, no second sample.
        if now ~= nil and now == sampledAt then return lastReport end
        sampledAt, lastReport = now, nil
        local cross = tracker:Sample(ask(ctx.client, "position"), ask(ctx.client, "worldPosition"),
            ask(ctx.client, "onTaxi"), now)
        if not cross then return nil end
        local list = saved()
        local made = list == nil
        local into, added, reason = N.GateLearn(list or {}, cross, cross.rode, cross.onTaxi)
        -- The saved table is made only when there is a gate to put in it.
        if added and made then
            local ok = ctx.store:set("account", Gates.PATH, into)
            if not ok then added, reason = false, "not saved" end
        end
        lastReport = { added = added and true or false, reason = reason, cross = cross }
        return lastReport
    end

    function api.step(target)
        if not ctx then return nil, "not started" end
        local here = { position = ask(ctx.client, "position") }
        local step, reason = N.GateStep(saved(), target, here, function(map) return ask(ctx.client, "mapSize", map) end)
        if not step then return nil, reason end
        if step.text then
            return { kind = Gates.KIND, label = step.label, text = true, detail = step.detail }, reason
        end
        local zone = ask(ctx.client, "zone")
        return {
            kind = Gates.KIND, label = step.label,
            place = { cont = type(zone) == "table" and zone.cont or nil,
                      map = step.point.map, x = step.point.x, y = step.point.y },
            radius = Gates.NEAR,
        }, reason
    end

    function api.count()
        local n = 0
        for _, g in ipairs(ctx and saved() or {}) do
            if type(g) == "table" and type(g.a) == "number" and type(g.b) == "number" then n = n + 1 end
        end
        return n
    end

    k:Module({
        name = Gates.NAME,
        needs = { "client", "store", "sched" },
        provides = { Step = function(target) return api.step(target) end, Count = function() return api.count() end },
        ticks = { { every = Gates.EVERY, when = "always", run = function() api.sample() end } },
        start = function(c) ctx = c end,
        stop = function() tracker = N.GateTracker() end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.gates = Gates.Declare(ns)
