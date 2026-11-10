-- Trip planner: orders ALL your nearby goals into one trip instead of just
-- chasing the nearest one. It answers questions like "turn in the bandanas
-- first, or go to the trainers first?" and "grab that quest before heading
-- out so I don't have to come back".
--
-- Stops: every goal with a location on your continent (quest objectives,
-- turn-ins, quests to pick up, trainers, gathering/fishing). Rules:
--   * a quest's turn-in comes after that quest's objectives (goal.deps)
--   * optional stops (goal.optional) stay only if they cost less than
--     OPTIONAL_DETOUR extra yards, i.e. they're roughly on the way
--   * a stop with many possible spots (mob spawns) uses whichever spot is
--     closest to where you'll be at that point in the trip
--   * finish this zone before leaving it: stops in another zone wait until
--     this zone's are done (Nav.lua decides which: quests too low or too
--     high for you don't hold you here, and a stop just over the border or
--     your class trainer is a short trip that doesn't wait)
-- Method: greedy nearest-first, then improved by moving single stops and
-- reversing segments while the trip gets shorter (and still obeys the rules).
-- This is a travelling-salesman problem with ordering rules, solved with a
-- standard heuristic (nearest neighbour, then relocate and 2-opt moves).
-- Distances are straight lines; the arrow then follows learned trails (A*).

local _, ns = ...
local P = {}
ns.planner = P

local MAX_STOPS = 30          -- nearest goals considered per plan
-- Only the first stops get the slow polish (improve() costs ~n^3); the rest
-- of the trip is nearest-next from there. It's planned again as you go, so
-- the far end gets polished by the time you reach it. 14 = what the whole
-- plan used to be, so a plan costs no more than before (/flow perf).
local IMPROVE_HEAD = 14
local MAX_POINTS = 25         -- spots per stop considered (nearest to you)
local OPTIONAL_DETOUR = 250   -- yards an optional stop may add
local MAX_PASSES = 6
-- Finish this area: stops within AREA yards of you come before the rest,
-- unless going elsewhere first saves at least AREA_SAVE yards or
-- AREA_SAVE_FRAC of the trip (whichever is more). Quests to pick up count
-- as the area out to AREA_PICKUP: their objectives are usually close by.
local AREA, AREA_PICKUP = 300, 600
local AREA_SAVE, AREA_SAVE_FRAC = 400, 0.25

local sqrt = math.sqrt
local function dist(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return sqrt(dx * dx + dy * dy)
end

-- Options for the plan being built (set by P:Plan):
--   first = goal key that must be the first stop (your choice)
--   tour  = { [key] = true } stops that must all come before anything else
--           (e.g. "pick up all these quests first")
--   here  = { [key] = true } this zone's stops you should finish first
--   away  = { [key] = true } stops in another zone: they wait until every
--           `here` stop is done
--   near  = { [key] = true } the area around you (set by P:Plan): the rest
--           waits until these are done
--   areaFirst = false: no area rule (nil: Flow's setting)
local OPT = {}

-- Finish the zone first: an away stop may not come while a here stop is left.
local function waits(key, hereLeft)
    return hereLeft and OPT.away and OPT.away[key] and not (OPT.tour and OPT.tour[key]) and key ~= OPT.first
end

local function forced(key) return OPT.first == key or (OPT.tour and OPT.tour[key]) end

-- Finish the area first: a stop outside it waits while an area stop is left
-- (your own pick and milestones like class training never wait).
local function waitsArea(s, nearLeft)
    return nearLeft and OPT.near and not OPT.near[s.key] and not forced(s.key) and not s.goal.milestone
end

-- The nearest spot of stop s from `from` (you, or a spot of another stop),
-- and how far. The polish below asks this same question thousands of times
-- per plan (every order it tries walks the whole trip), so each answer is
-- worked out once per plan and kept. Same answer as looking every time.
local nearPt, nearD = {}, {}
local function nearest(from, s)
    local m = nearPt[from]
    if m then
        local best = m[s]
        if best then return best, nearD[from][s] end
    else
        m = {}
        nearPt[from], nearD[from] = m, {}
    end
    local x, y = from.wx, from.wy
    local best, bd
    for _, pt in ipairs(s.points) do
        local d = dist(x, y, pt.wx, pt.wy)
        if not bd or d < bd then best, bd = pt, d end
    end
    m[s], nearD[from][s] = best, bd
    return best, bd
end

local dk = {}   -- (candidates: each spot's distance from you)
local function byNear(a, b) return dk[a] < dk[b] end
local NONE = {}

local function candidates(p, goals)
    local stops = {}
    for _, g in ipairs(goals) do
        -- This stop's spots on your continent, nearest first, at most MAX_POINTS.
        local pts, n = {}, 0
        for _, pt in ipairs(g.points or NONE) do
            if pt.wx and pt.cont == p.cont then
                n = n + 1
                pts[n], dk[pt] = pt, dist(p.wx, p.wy, pt.wx, pt.wy)
            end
        end
        if n > 0 then
            if n > 1 then table.sort(pts, byNear) end
            local near = dk[pts[1]]
            for i = 1, n do dk[pts[i]] = nil end
            for i = n, MAX_POINTS + 1, -1 do pts[i] = nil end
            stops[#stops + 1] = { goal = g, key = g.key, points = pts, near = near }
        end
    end
    -- Chosen stops always make the cut, then milestones (class training: it
    -- changes every fight after it), then the rest by (weighted) nearness.
    -- A milestone is never dropped as "too far", but it doesn't jump the
    -- queue either: its weight puts it where it costs the least detour.
    table.sort(stops, function(a, b)
        local fa, fb = forced(a.key) and 2 or (a.goal.milestone and 1 or 0), forced(b.key) and 2 or (b.goal.milestone and 1 or 0)
        if fa ~= fb then return fa > fb end
        return a.near * (a.goal.weight or 1) < b.near * (b.goal.weight or 1)
    end)

    local kept, keptKeys, allKeys = {}, {}, {}
    for _, s in ipairs(stops) do allKeys[s.key] = true end
    for i = 1, #stops do
        if i <= MAX_STOPS or forced(stops[i].key) then
            kept[#kept + 1] = stops[i]; keptKeys[stops[i].key] = true
        end
    end
    -- Turn-ins follow their quest: when every objective of a quest made the
    -- cut, its turn-in comes too, even past MAX_STOPS (a few extra at most),
    -- so the route finishes what it starts instead of stopping at the last
    -- objective.
    local extra = 0
    for i = 1, #stops do
        local s = stops[i]
        local deps = s.goal.deps
        if not keptKeys[s.key] and deps and #deps > 0 and extra < 8 then
            local all = true
            for _, dep in ipairs(deps) do
                if allKeys[dep] and not keptKeys[dep] then all = false end
            end
            if all then kept[#kept + 1] = s; keptKeys[s.key] = true; extra = extra + 1 end
        end
    end
    -- A turn-in whose objectives didn't make the cut would be planned too
    -- early; leave it out until they're in range.
    local out = {}
    for _, s in ipairs(kept) do
        local ok = true
        for _, dep in ipairs(s.goal.deps or {}) do
            if allKeys[dep] and not keptKeys[dep] then ok = false end
        end
        if ok then out[#out + 1] = s end
    end
    return out
end

-- Walks an order from your position. Returns weighted cost, legs, points.
local function walk(p, order)
    local from, total = p, 0
    local legs, pts = {}, {}
    for i, s in ipairs(order) do
        local best, bd = nearest(from, s)
        legs[i], pts[i] = bd, best
        total = total + bd * (s.goal.weight or 1)
        from = best
    end
    return total, legs, pts
end

-- The same weighted cost, without the lists (the polish only needs this).
local function cost(p, order)
    local from, total = p, 0
    for i = 1, #order do
        local s = order[i]
        local best, bd = nearest(from, s)
        total = total + bd * (s.goal.weight or 1)
        from = best
    end
    return total
end

local posOf = {}   -- (valid: each stop's place in the order; reused)
local function valid(order)
    local pos = posOf
    for k in pairs(pos) do pos[k] = nil end
    for i, s in ipairs(order) do pos[s.key] = i end
    if OPT.first and pos[OPT.first] and pos[OPT.first] ~= 1 then return false end
    local lastTour, firstOther = 0, math.huge
    for i, s in ipairs(order) do
        for _, dep in ipairs(s.goal.deps or {}) do
            if pos[dep] and pos[dep] > i then return false end
        end
        if OPT.tour then
            if OPT.tour[s.key] or s.key == OPT.first then lastTour = i
            elseif i < firstOther then firstOther = i end
        end
    end
    if lastTour >= firstOther then return false end
    -- This zone's stops before the next zone's.
    if OPT.here and OPT.away then
        local lastHere, firstAway = 0, math.huge
        for i, s in ipairs(order) do
            if OPT.here[s.key] then lastHere = i
            elseif waits(s.key, true) and i < firstAway then firstAway = i end
        end
        if lastHere > firstAway then return false end
    end
    -- The area around you before the rest.
    if OPT.near then
        local lastNear, firstFar = 0, math.huge
        for i, s in ipairs(order) do
            if OPT.near[s.key] then lastNear = i
            elseif waitsArea(s, true) and i < firstFar then firstFar = i end
        end
        if lastNear > firstFar then return false end
    end
    return true
end
P._valid = function(order, opt) local old = OPT; OPT = opt or {}; local r = valid(order); OPT = old; return r end   -- (tests)

local function greedy(p, stops)
    local remaining, order, left = {}, {}, {}
    for _, s in ipairs(stops) do remaining[#remaining + 1] = s end
    local from = p   -- where you are at this point of the trip
    while #remaining > 0 do
        for k in pairs(left) do left[k] = nil end
        local tourLeft, firstLeft, hereLeft, nearLeft = false, false, false, false
        for _, s in ipairs(remaining) do
            left[s.key] = true
            if OPT.tour and OPT.tour[s.key] then tourLeft = true end
            if s.key == OPT.first then firstLeft = true end
            if OPT.here and OPT.here[s.key] then hereLeft = true end
            if OPT.near and OPT.near[s.key] then nearLeft = true end
        end
        local bestI, bestScore
        for i, s in ipairs(remaining) do
            local ready = true
            for _, dep in ipairs(s.goal.deps or {}) do if left[dep] then ready = false end end
            -- Your chosen stop first, then the rest of the tour, then the others.
            if firstLeft and s.key ~= OPT.first then ready = false end
            if tourLeft and not (OPT.tour[s.key] or s.key == OPT.first) then ready = false end
            if waits(s.key, hereLeft) then ready = false end   -- this zone first
            if waitsArea(s, nearLeft) then ready = false end   -- this area first
            if ready then
                local _, bd = nearest(from, s)
                local score = bd * (s.goal.weight or 1)
                if not bestScore or score < bestScore then bestI, bestScore = i, score end
            end
        end
        if not bestI then bestI = 1 end  -- broken deps: don't loop forever
        local s = table.remove(remaining, bestI)
        order[#order + 1] = s
        from = nearest(from, s)
    end
    return order
end

local function copy(t) local c = {} for i, v in ipairs(t) do c[i] = v end return c end

local function reverse(o, i, j)
    for k = 0, math.floor((j - i) / 2) do o[i + k], o[j - k] = o[j - k], o[i + k] end
end

-- Tries each change in place and undoes it unless it's kept (no copy of
-- the whole trip per try). Keeps the first change that saves over a yard,
-- then carries on from there, until a pass finds nothing (or MAX_PASSES).
local function improve(p, order)
    local best = cost(p, order)
    local n = #order
    for _ = 1, MAX_PASSES do
        local improved = false
        -- Move one stop elsewhere.
        for i = 1, n do
            for j = 1, n do
                if i ~= j then
                    local s = table.remove(order, i)
                    table.insert(order, j, s)
                    local keep = false
                    if valid(order) then
                        local c = cost(p, order)
                        if c < best - 1 then best, improved, keep = c, true, true end
                    end
                    if not keep then table.remove(order, j); table.insert(order, i, s) end
                end
            end
        end
        -- Reverse a segment.
        for i = 1, n - 1 do
            for j = i + 1, n do
                reverse(order, i, j)
                local keep = false
                if valid(order) then
                    local c = cost(p, order)
                    if c < best - 1 then best, improved, keep = c, true, true end
                end
                if not keep then reverse(order, i, j) end
            end
        end
        if not improved then break end
    end
    return order
end
P._cost = function(p, order) nearPt, nearD = {}, {}; return cost(p, order) end   -- (tests)

-- Drop optional stops that add more than OPTIONAL_DETOUR yards.
local function prune(p, order)
    local dropped = {}
    local i = 1
    while i <= #order do
        local s = order[i]
        if s.goal.optional and not forced(s.key) then
            local o = copy(order)
            table.remove(o, i)
            local _, withLegs = walk(p, order)
            local _, withoutLegs = walk(p, o)
            local with, without = 0, 0
            for _, l in ipairs(withLegs) do with = with + l end
            for _, l in ipairs(withoutLegs) do without = without + l end
            if with - without > OPTIONAL_DETOUR and valid(o) then
                dropped[#dropped + 1] = s.goal.text or s.goal.title or s.key
                order = o
            else
                i = i + 1
            end
        else
            i = i + 1
        end
    end
    return order, dropped
end

-- The area around you (OPT.near): stops within AREA yards (quest pickups
-- AREA_PICKUP) that aren't in another zone. A stop whose quest objectives
-- are outside the area isn't in it (it can't be finished here). nil when
-- the area is empty or is everything (no rule needed).
local function areaSet(stops)
    local near, keyed, far = {}, {}, false
    for _, s in ipairs(stops) do
        keyed[s.key] = true
        local r = s.key:find("^pickup:") and AREA_PICKUP or AREA
        if s.near <= r and not (OPT.away and OPT.away[s.key]) then near[s.key] = true end
    end
    local changed = true
    while changed do
        changed = false
        for _, s in ipairs(stops) do
            if near[s.key] then
                for _, dep in ipairs(s.goal.deps or NONE) do
                    if keyed[dep] and not near[dep] then near[s.key], changed = nil, true break end
                end
            end
        end
    end
    for _, s in ipairs(stops) do
        if not near[s.key] and not forced(s.key) and not s.goal.milestone then far = true end
    end
    if not (next(near) and far) then return nil end
    return near
end

-- Keep the free order (leaving the area early) only when it saves a lot:
-- free and kept are the two trips' costs.
function P.AreaKeepsFree(free, kept)
    return free < kept - math.max(AREA_SAVE, AREA_SAVE_FRAC * kept)
end

-- Nearest-next, then polished (the near part only on a long trip).
local function build(p, stops)
    local order = greedy(p, stops)
    if #order > IMPROVE_HEAD then
        -- Polish the near part, then carry on nearest-next from its last stop.
        local head, rest = {}, {}
        for i, s in ipairs(order) do
            if i <= IMPROVE_HEAD then head[#head + 1] = s else rest[#rest + 1] = s end
        end
        head = improve(p, head)
        local _, _, pts = walk(p, head)
        local last = pts[#pts]
        order = head
        for _, s in ipairs(greedy(last, rest)) do order[#order + 1] = s end
    else
        order = improve(p, order)
    end
    return order
end

-- Returns the trip: { { goal, point, leg, cum }, ..., dropped = { text } }
function P:Plan(p, goals, opts)
    OPT = {}   -- (a copy: the area rule adds to it)
    for k, v in pairs(opts or {}) do OPT[k] = v end
    OPT.near = nil
    nearPt, nearD = {}, {}   -- the nearest-spot answers are for this plan only
    local stops = candidates(p, goals)
    if #stops == 0 then return nil end
    local order = build(p, stops)
    -- Finish this area: if the best trip leaves the area before it's done,
    -- plan one that doesn't, and keep that unless it costs a lot more.
    local areaFirst = OPT.areaFirst
    if areaFirst == nil then areaFirst = not (ns.db and ns.db.nav and ns.db.nav.areaFirst == false) end
    if areaFirst then
        OPT.near = areaSet(stops)
        if OPT.near and not valid(order) then
            local inArea = build(p, stops)
            if P.AreaKeepsFree(cost(p, order), cost(p, inArea)) then OPT.near = nil
            else order = inArea end
        end
    end
    local dropped
    order, dropped = prune(p, order)
    local _, legs, pts = walk(p, order)
    local plan, cum = { dropped = dropped }, 0
    for i, s in ipairs(order) do
        cum = cum + legs[i]
        plan[i] = { goal = s.goal, point = pts[i], leg = legs[i], cum = cum }
    end
    nearPt, nearD = {}, {}
    return plan
end

-- Timed for /flow perf.
P.Plan = ns.perf.Wrap("route: order stops", P.Plan)
