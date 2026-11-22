local _, ns = ...
-- Z-Flow trip timing (S34, LEDGER 153): how long the player's own trips
-- from one step to the next take, so a route can be ordered by what a trip
-- really costs and not by the straight line. A cliff or a river between
-- two steps then counts. Ported from legacy Flow 0.35.377
-- (Modules/Nav/Legs.lua). Research: WoW/from-zen/RESEARCH-S34.md.
--
-- THE PURE PART. Pure Lua 5.1: no client calls, nothing saved, nothing
-- printed. The module that feeds it (a look every second, the saved legs,
-- the word) comes after it and is not in this file yet. Not tested in game.
--
-- LOOK ONLY. It times and remembers the player's own trips. Nothing moves,
-- flies, mounts or acts for the player.
--
-- Two changes from legacy Flow, both because of what Z-Flow can read:
--   * Places are yards on ONE map (a map share times the map's size, the
--     unit Nav/RoutePlan.lua orders by), not world yards on a continent.
--     Legs are kept per map. A trip that ends on another map than it
--     started on is not learned.
--   * Unknown stays unknown (F-086). A look whose flight read is not known
--     drops the trip under way: a flight taken for a run would store a
--     false time. A look whose mounted read is not known counts as mounted:
--     a time is "on foot" only when the client said so.
--
-- A leg is one trip between two steps. Its ends are rounded to L.CELL-yard
-- squares; per pair of squares the quickest time is kept, and beside it
-- the quickest on foot (the store is shared by the account's characters,
-- and one of them may not ride).
--
-- L.Cell(x, y, size) -> "cx:cy", the square a spot is in. size: L.CELL
--   (default) or L.COARSE.
-- L.Spot(place, size) -> { map, x, y } in yards from a map place
--   { map, x, y as shares 0..1 } and that map's size { w, h }; nil when
--   either is not usable.
--
-- L.Look(st, s) -> a finished leg, or nil. One look at the player, about a
--   second after the last. st is changed in place.
--   st = { anchor = { map, x, y }, last = { map, x, y }, sec, ground,
--          taxi, ridden, looks }: the trip under way. {} to begin.
--   s  = { map, x, y,          where the player is, yards on map
--          dt,                 seconds since the last look (1 when absent)
--          combat, dead,       true when so
--          taxi,               true / false; nil = not known (see above)
--          mounted,            true / false; nil = not known (see above)
--          target = { map, x, y } }   the step being headed for, or nil
--   leg = { map, ax, ay, bx, by, sec, d, mode }: from the last step to this
--         one, the seconds spent travelling, the straight yards, and
--         "taxi", "mount" or "foot".
--   Seconds count only while moving (L.MIN_SPEED yards a second or more)
--   and out of combat; a flight always counts. No trip: dead, another map,
--   or more than L.JUMP yards in a second off a flight (a teleport).
--   Arriving (within L.ARRIVE yards of the target) ends the trip and starts
--   the next from the target's spot. The trip is a leg only when its
--   straight line is L.MIN_YARDS or more, some travelling was counted, and
--   the ground covered is at most L.WANDER times the line (a flight skips
--   that last test).
--
-- L.Keep(store, leg, now) -> entry, best
--   store = { [cellA] = { [cellB] = entry } }: one map's legs
--   entry = { s, d, n, m, at, bt, f, ft }: best seconds (to a tenth),
--     straight yards, count, how, time of the last trip, time the best was
--     set, best seconds on foot and when
--   best: true when this trip set the best. A best older than L.AGE is
--   replaced by the next trip, quicker or not. Both ends in one square:
--   nil, false.
-- L.SecondsFor(entry, how) -> seconds, or nil
--   how (optional) = { ride = false } for a character who cannot ride (only
--   a trip on foot or by flight times it), { now = time } to leave out a
--   best past L.AGE.
-- L.YardsOf(entry, d) -> what a trip of d straight yards between the same
--   two squares counts as, in yards at a run; held between L.FASTEST and
--   L.SLOWEST times d.
-- L.Ratio(coarse, entry, ax, ay, bx, by) -> ratio, or nil
--   Adds to coarse = { [KA] = { [KB] = ratio } }, both ways: the best
--   "run-yards over straight yards" seen between two L.COARSE-yard
--   neighbourhoods. A flight, a leg under L.COARSE_MIN yards or one inside
--   one neighbourhood says nothing.
-- L.Coarse(store) -> coarse, rebuilt from one map's legs (it is not saved)
-- L.Lookup(store, coarse, a, b, d, how) -> yards, "exact" | "area"; nil
--   a, b = { x, y } on the map, d = the straight yards between them. A trip
--   made between the two squares (either way; a flight only the way it
--   went), else the neighbourhoods' ratio, else nothing: the caller then
--   uses the straight line. Under L.MIN_YARDS nothing is looked up.
-- L.Count(store) -> how many legs
-- L.Prune(store, max) -> how many went: the ones used longest ago, until
--   max are left
ns.Nav = ns.Nav or {}
local N = ns.Nav

N.Legs = N.Legs or {}
local L = N.Legs

L.CELL = 40            -- yards: a step's spot, as a key
L.COARSE = 250         -- yards: a neighbourhood
L.ARRIVE = 30          -- yards from the step that count as arrived
L.MIN_YARDS = 60       -- shorter trips say nothing
L.MIN_SPEED = 1.5      -- yards a second: slower is standing about
L.JUMP = 70            -- yards in a second no legs or wings explain
L.WANDER = 2.5         -- ground covered over the straight line: more is wandering
L.RUN = 7              -- yards a second on foot: turns seconds into yards
L.FASTEST = 0.12       -- a leg never counts as less than this share of its line
L.SLOWEST = 5          -- nor as more than this many times it
L.COARSE_MIN = 150     -- yards: shorter legs say nothing about a neighbourhood
L.MAX = 3000           -- legs kept per map
L.AGE = 30 * 86400     -- seconds: an older best is replaced by the next trip

local floor, sqrt, max, min = math.floor, math.sqrt, math.max, math.min

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function dist(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return sqrt(dx * dx + dy * dy)
end

local function spot(p)
    return type(p) == "table" and p.map ~= nil and finite(p.x) and finite(p.y)
end

function L.Cell(x, y, size)
    size = size or L.CELL
    return floor(x / size) .. ":" .. floor(y / size)
end

function L.Spot(place, size)
    if type(place) ~= "table" or place.map == nil or not finite(place.x) or not finite(place.y) then return nil end
    if type(size) ~= "table" or not (finite(size.w) and finite(size.h) and size.w > 0 and size.h > 0) then
        return nil
    end
    return { map = place.map, x = place.x * size.w, y = place.y * size.h }
end

function L.Look(st, s)
    if type(st) ~= "table" or not spot(s) then return nil end
    local dt = finite(s.dt) and s.dt > 0 and s.dt or 1
    local last = st.last
    st.last = { map = s.map, x = s.x, y = s.y }
    -- Flying or not is not known: nothing about this trip can be trusted.
    if s.taxi == nil then st.anchor = nil return nil end
    -- Dead, another map, or a jump no legs or wings explain: no trip.
    if s.dead or (last and last.map ~= s.map) then st.anchor = nil return nil end
    local moved = last and dist(last.x, last.y, s.x, s.y) or 0
    if moved > L.JUMP * max(1, dt) and not s.taxi then st.anchor = nil return nil end
    if st.anchor then
        -- Travelling: moving, and not in a fight (a flight always counts).
        if s.taxi or (not s.combat and moved >= L.MIN_SPEED * dt) then
            st.sec = (st.sec or 0) + dt
            st.looks = (st.looks or 0) + 1
            -- (Mounted not known counts as mounted: never a foot time by default.)
            if s.mounted ~= false and not s.taxi then st.ridden = (st.ridden or 0) + 1 end
        end
        st.ground = (st.ground or 0) + moved
        if s.taxi then st.taxi = true end
    end
    local t = s.target
    if not (spot(t) and t.map == s.map and dist(s.x, s.y, t.x, t.y) <= L.ARRIVE) then return nil end
    -- Arrived. The trip that ends here, if there was one worth keeping.
    local a, leg = st.anchor, nil
    if a and a.map == s.map then
        local d = dist(a.x, a.y, t.x, t.y)
        local sec = st.sec or 0
        if d >= L.MIN_YARDS and sec > 0 and (st.taxi or (st.ground or 0) <= d * L.WANDER) then
            local mode = st.taxi and "taxi" or (((st.ridden or 0) * 2 > (st.looks or 0)) and "mount" or "foot")
            leg = { map = s.map, ax = a.x, ay = a.y, bx = t.x, by = t.y, sec = sec, d = d, mode = mode }
        end
    end
    st.anchor = { map = s.map, x = t.x, y = t.y }
    st.sec, st.ground, st.taxi, st.ridden, st.looks = 0, 0, nil, 0, 0
    return leg
end

function L.Keep(store, leg, now)
    local ka, kb = L.Cell(leg.ax, leg.ay), L.Cell(leg.bx, leg.by)
    if ka == kb then return nil, false end
    store[ka] = store[ka] or {}
    local e = store[ka][kb]
    local sec = floor(leg.sec * 10 + 0.5) / 10
    local function stale(t) return now and t and now - t > L.AGE end
    if leg.mode == "foot" and e and (not e.f or sec < e.f or stale(e.ft)) then e.f, e.ft = sec, now end
    if not e then
        e = { s = sec, d = floor(leg.d + 0.5), n = 1, m = leg.mode, at = now, bt = now }
        if leg.mode == "foot" then e.f, e.ft = sec, now end
        store[ka][kb] = e
        return e, true
    end
    e.n, e.at = (e.n or 1) + 1, now
    if sec < e.s or stale(e.bt or e.at) then
        e.s, e.d, e.m, e.bt = sec, floor(leg.d + 0.5), leg.mode, now
        return e, true
    end
    return e, false
end

function L.SecondsFor(e, how)
    if type(e) ~= "table" then return nil end
    local now = type(how) == "table" and how.now or nil
    local function stale(t) return now and t and now - t > L.AGE end
    local s, t = e.s, e.bt
    if type(how) == "table" and how.ride == false and e.m == "mount" then s, t = e.f, e.ft end
    if not s or stale(t) then return nil end
    return s
end

function L.YardsOf(e, d)
    if not (type(e) == "table" and e.s and e.d and e.d > 0 and d and d > 0) then return nil end
    -- (The ends differ a little within their squares: by the length's share.)
    local scale = max(0.7, min(1.4, d / e.d))
    local yards = e.s * L.RUN * scale
    return max(d * L.FASTEST, min(d * L.SLOWEST, yards))
end

function L.Ratio(coarse, e, ax, ay, bx, by)
    if not (type(e) == "table" and e.s and e.d and e.d >= L.COARSE_MIN and e.m ~= "taxi") then return nil end
    local ratio = (e.s * L.RUN) / e.d
    local KA, KB = L.Cell(ax, ay, L.COARSE), L.Cell(bx, by, L.COARSE)
    if KA == KB then return nil end
    for _, pair in ipairs({ { KA, KB }, { KB, KA } }) do
        coarse[pair[1]] = coarse[pair[1]] or {}
        local old = coarse[pair[1]][pair[2]]
        if not old or ratio < old then coarse[pair[1]][pair[2]] = ratio end
    end
    return ratio
end

-- A square's middle, back as a spot. nil for a key that is no square.
local function middle(key)
    if type(key) ~= "string" then return nil end
    local cx, cy = key:match("^(-?%d+):(-?%d+)$")
    if not cx then return nil end
    return (tonumber(cx) + 0.5) * L.CELL, (tonumber(cy) + 0.5) * L.CELL
end

function L.Coarse(store)
    local coarse = {}
    for ka, row in pairs(type(store) == "table" and store or {}) do
        local ax, ay = middle(ka)
        if ax and type(row) == "table" then
            for kb, e in pairs(row) do
                local bx, by = middle(kb)
                if bx then L.Ratio(coarse, e, ax, ay, bx, by) end
            end
        end
    end
    return coarse
end

function L.Lookup(store, coarse, a, b, d, how)
    if not (type(store) == "table" and type(a) == "table" and type(b) == "table" and finite(d) and d >= L.MIN_YARDS) then
        return nil
    end
    if not (finite(a.x) and finite(a.y) and finite(b.x) and finite(b.y)) then return nil end
    local ka, kb = L.Cell(a.x, a.y), L.Cell(b.x, b.y)
    local fw = store[ka] and store[ka][kb]
    local s = L.SecondsFor(fw, how)
    local e = s and { s = s, d = fw.d } or nil
    -- (The way back, when it was not a flight: a path is the same both ways.)
    local back = store[kb] and store[kb][ka]
    local sb = type(back) == "table" and back.m ~= "taxi" and L.SecondsFor(back, how) or nil
    if sb and (not e or sb < e.s) then e = { s = sb, d = back.d } end
    if e then
        local yards = L.YardsOf(e, d)
        if yards then return yards, "exact" end
    end
    if type(coarse) == "table" and d >= L.COARSE_MIN then
        local KA, KB = L.Cell(a.x, a.y, L.COARSE), L.Cell(b.x, b.y, L.COARSE)
        local r = coarse[KA] and coarse[KA][KB]
        if r then return max(d * L.FASTEST, min(d * L.SLOWEST, d * r)), "area" end
    end
    return nil
end

function L.Count(store)
    local n = 0
    for _, row in pairs(type(store) == "table" and store or {}) do
        if type(row) == "table" then
            for _ in pairs(row) do n = n + 1 end
        end
    end
    return n
end

function L.Prune(store, limit)
    if type(store) ~= "table" then return 0 end
    local all = {}
    for ka, row in pairs(store) do
        if type(row) == "table" then
            for kb, e in pairs(row) do
                all[#all + 1] = { ka, kb, type(e) == "table" and e.at or 0 }
            end
        end
    end
    if #all <= limit then return 0 end
    -- (Equal times: by the keys, so the same store always loses the same legs.)
    table.sort(all, function(x, y)
        if x[3] ~= y[3] then return x[3] < y[3] end
        if x[1] ~= y[1] then return x[1] < y[1] end
        return x[2] < y[2]
    end)
    local gone = #all - limit
    for i = 1, gone do
        local row = store[all[i][1]]
        row[all[i][2]] = nil
        if not next(row) then store[all[i][1]] = nil end
    end
    return gone
end
