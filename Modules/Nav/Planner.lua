-- Trip planner: orders ALL your nearby goals into one trip instead of just
-- chasing the nearest one. It answers questions like "turn in the bandanas
-- first, or go to the trainers first?" and "grab that quest before heading
-- out so I don't have to come back".
--
-- Steps: every goal with a location on your continent (quest objectives,
-- turn-ins, quests to pick up, trainers, gathering/fishing). Rules:
--   * a quest's turn-in comes after that quest's objectives (goal.deps)
--   * optional steps (goal.optional) stay only if they cost less than
--     OPTIONAL_DETOUR extra yards, i.e. they're roughly on the way
--   * a step with many possible spots (mob spawns) uses whichever spot is
--     closest to where you'll be at that point in the trip
--   * a kill or collect step whose spots lie in several groups is visited
--     group by group (0.35.329): each of its nearest groups is a visit of
--     its own in the order, so the trip threads through the groups of
--     several quests instead of counting each quest as one spot
--   * finish this zone before leaving it: steps in another zone wait until
--     this zone's are done (Nav.lua decides which: quests too low or too
--     high for you don't hold you here, and a step just over the border or
--     your class trainer is a short trip that doesn't wait)
-- Method: greedy nearest-first, then improved by moving single steps and
-- reversing segments while the trip gets shorter (and still obeys the rules).
-- This is a travelling-salesman problem with ordering rules, solved with a
-- standard heuristic (nearest neighbour, then relocate and 2-opt moves).
-- Distances are straight lines; the arrow then follows learned trails (A*).

local _, ns = ...
local P = {}
ns.planner = P

local MAX_STOPS = 30          -- nearest goals considered per plan
-- Only the first steps get the slow polish (improve() costs ~n^3); the rest
-- of the trip is nearest-next from there. It's planned again as you go, so
-- the far end gets polished by the time you reach it. 14 = what the whole
-- plan used to be, so a plan costs no more than before (/flow perf).
local IMPROVE_HEAD = 14
local MAX_POINTS = 25         -- spots per step considered (nearest to you)
local OPTIONAL_DETOUR = 250   -- yards an optional step may add
local MAX_PASSES = 6
-- Finish this area: steps within AREA yards of you come before the rest,
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
--   first = goal key that must be the first step (your choice)
--   tour  = { [key] = true } steps that must all come before anything else
--           (e.g. "pick up all these quests first")
--   here  = { [key] = true } this zone's steps you should finish first
--   away  = { [key] = true } steps in another zone: they wait until every
--           `here` step is done
--   near  = { [key] = true } the area around you (set by P:Plan): the rest
--           waits until these are done
--   areaFirst = true/false: the area rule on or off (nil: Flow's setting, off unless ticked)
--   air   = function(a, b) -> yards: the trip from spot a to spot b by
--           flight (the walks to and from the flight masters plus the
--           flight, as the yards you'd run in that time), nil if none.
--           Steps are then picked by the time they take, not the straight
--           line (Nav sets it: N.TravelYards).
--   port  = function(a, b) -> yards: spot b is one cast away from spot a (a
--           travel spell you know: TravelSpells.lua), nil when it isn't.
--   walk  = function(a, b) -> yards: the walk from spot a to spot b when it
--           goes by a gate (two spots in different regions: Gates.lua), nil
--           when it's the straight line.
--   legs  = function(a, b, d) -> yards, "exact" | "area": the trip from spot
--           a to spot b as you've travelled it (Legs.lua), nil when Flow has
--           learned nothing about it. "exact": you made this trip, and what
--           it took is the answer. "area": trips between these two
--           neighbourhoods took that much longer than the straight line.
local OPT = {}

-- A flight never beats a short walk: below this the straight line is the
-- answer (and the flight sum isn't worked out).
local AIR_MIN = 300

-- How far it is from spot a to spot b in running yards: the straight line,
-- or by flight when that's quicker.
local function far(a, b)
    local d = dist(a.wx, a.wy, b.wx, b.wy)
    -- A trip you've made (0.35.350): what it took you is the answer, flight,
    -- gate, cliff and all. One between the same two neighbourhoods: the
    -- straight line, stretched as those trips were (never shortened: the
    -- flight and the travel spell below still get their say).
    if OPT.legs then
        local ok, yards, how = pcall(OPT.legs, a, b, d)
        if ok and type(yards) == "number" then
            if how == "exact" then return yards end
            if yards > d then d = yards end
        end
    end
    -- A cast away (a druid's Teleport: Moonglade): near, however far it is on foot.
    if OPT.port and a.map ~= b.map then
        local ok, t = pcall(OPT.port, a, b)
        if ok and type(t) == "number" and t < d then return t end
    end
    -- Out of a zone someone carries you from (a druid in Moonglade: the
    -- flight to Thunder Bluff): to them, the ride, and on from the landing.
    if OPT.ride and a.map ~= b.map then
        local ok, t = pcall(OPT.ride, a, b)
        if ok and type(t) == "number" and t < d then return t end
    end
    -- On different maps (one up on Thunder Bluff, one at its foot; the next
    -- zone): the walk goes by a gate, not through the cliff (Gates.lua).
    if OPT.walk and a.map ~= b.map then
        local ok, w = pcall(OPT.walk, a, b)
        if ok and type(w) == "number" and w > d then d = w end
    end
    if OPT.air and d > AIR_MIN then
        local ok, t = pcall(OPT.air, a, b)
        if ok and type(t) == "number" and t < d then return t end
    end
    return d
end
-- (for the tests)
function P._Far(a, b, opts)
    local keep = OPT
    OPT = opts or {}
    local d = far(a, b)
    OPT = keep
    return d
end

-- Finish the zone first: an away step may not come while a here step is left.
local function waits(key, hereLeft)
    return hereLeft and OPT.away and OPT.away[key] and not (OPT.tour and OPT.tour[key]) and key ~= OPT.first
end

local function forced(key) return OPT.first == key or (OPT.tour and OPT.tour[key]) end

-- A dep the plan obeys: every one, except the dep that closes a loop
-- (P.FindCycles: OPT.broken). The order is checked against all of them after.
local function binds(key, dep)
    local b = OPT.broken and OPT.broken[key]
    return not (b and b[dep])
end

-- Finish the area first: a step outside it waits while an area step is left
-- (your own pick and milestones like class training never wait).
local function waitsArea(s, nearLeft)
    return nearLeft and OPT.near and not OPT.near[s.key] and not forced(s.key) and not s.goal.milestone
end

-- The nearest spot of step s from `from` (you, or a spot of another step),
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
    local best, bd
    for _, pt in ipairs(s.points) do
        local d = far(from, pt)
        if not bd or d < bd then best, bd = pt, d end
    end
    m[s], nearD[from][s] = best, bd
    return best, bd
end

local dk = {}   -- (candidates: each spot's distance from you)
local function byNear(a, b) return dk[a] < dk[b] end
local NONE = {}

-- Is spot b near spot a only by a travel spell (a druid's Teleport:
-- Moonglade), not on foot?
local function byPort(a, b)
    if not (OPT.port and a.map ~= b.map) then return false end
    local ok, t = pcall(OPT.port, a, b)
    return ok and type(t) == "number" and t < dist(a.wx, a.wy, b.wx, b.wy)
end

-- Pure: of a step's spots, the ones to consider. A spot that's only near by
-- a travel spell is no place for an errand that can be done on foot: with
-- full bags, the "nearest" merchant was the one in Moonglade, one cast away
-- and 10,000 yards from everything else on the route (found by
-- tools\route-check.ps1, 0.35.198). So when some of a step's spots are
-- reached on foot, the ones reached only by the spell are left out. A step
-- whose every spot is there (the class quest in Moonglade) keeps them.
--   pts: the spots; ported(pt) -> it's near only by a travel spell
function P.OnFoot(pts, ported)
    local walk = {}
    for _, pt in ipairs(pts) do
        if not ported(pt) then walk[#walk + 1] = pt end
    end
    if #walk == 0 or #walk == #pts then return pts end
    return walk
end

local function candidates(p, goals)
    local stops = {}
    for _, g in ipairs(goals) do
        -- This step's spots on your continent, nearest first, at most MAX_POINTS.
        local pts, n = {}, 0
        for _, pt in ipairs(g.points or NONE) do
            if pt.wx and pt.cont == p.cont then
                n = n + 1
                pts[n] = pt
            end
        end
        if n > 1 and OPT.port then
            pts = P.OnFoot(pts, function(pt) return byPort(p, pt) end)
            n = #pts
        end
        for i = 1, n do dk[pts[i]] = far(p, pts[i]) end
        if n > 0 then
            if n > 1 then table.sort(pts, byNear) end
            local near = dk[pts[1]]
            for i = 1, n do dk[pts[i]] = nil end
            for i = n, MAX_POINTS + 1, -1 do pts[i] = nil end
            stops[#stops + 1] = { goal = g, key = g.key, points = pts, near = near }
        end
    end
    -- Chosen steps always make the cut, then milestones (class training: it
    -- changes every fight after it), then the rest by (weighted) nearness.
    -- A milestone is never dropped as "too far", but it doesn't jump the
    -- queue either: its weight puts it where it costs the least detour.
    table.sort(stops, function(a, b)
        -- (goal.keep: a finished quest's hand-in that frees bag slots while
        -- your bags are nearly full, QuestBags.lua, 0.35.344. With 130 quests
        -- to pick up nearer by it never made the 30, and its items stayed.)
        local fa = forced(a.key) and 2 or ((a.goal.milestone or a.goal.keep) and 1 or 0)
        local fb = forced(b.key) and 2 or ((b.goal.milestone or b.goal.keep) and 1 or 0)
        if fa ~= fb then return fa > fb end
        return a.near * (a.goal.weight or 1) < b.near * (b.goal.weight or 1)
    end)

    local kept, keptKeys, allKeys = {}, {}, {}
    for _, s in ipairs(stops) do allKeys[s.key] = true end
    for i = 1, #stops do
        if i <= MAX_STOPS or forced(stops[i].key) or stops[i].goal.keep then
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
    -- A chosen step or a milestone (class training) that needs another step
    -- first (Needs.lua: train after the Bear Form quest) pulls that step in,
    -- rather than being left out for it: a few extra at most, and the steps
    -- those need in turn. (0.35.142: training could vanish from the route
    -- when the quest it waits for was too far for the cut.)
    local byKey = {}
    for _, s in ipairs(stops) do byKey[s.key] = s end
    local pulled, changed = 0, true
    while changed and pulled < 8 do
        changed = false
        for _, s in ipairs(kept) do
            if forced(s.key) or s.goal.milestone or s.pulled then
                for _, dep in ipairs(s.goal.deps or {}) do
                    local d = byKey[dep]
                    if d and not keptKeys[dep] and pulled < 8 then
                        d.pulled = true
                        kept[#kept + 1] = d; keptKeys[dep] = true
                        pulled, changed = pulled + 1, true
                    end
                end
            end
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

-------------------------------------------------------------------------------
-- Group visits (0.35.329). "As it is planning the next route, is it smart
-- enough to consider all the clouds, or does it only consider one or two of
-- the points in the quest? I would prefer the former."
--
-- A kill or collect step was one visit to one spot (whichever of its spots
-- was nearest to where you'd be). Ten boars aren't at one spot: you work one
-- group, then the next. So such a step now becomes up to MAX_VISITS visits,
-- one for each of its nearest groups of spots, as many as what's left to get
-- is likely to need (PER_GROUP a group). Each visit is ordered like any
-- step, so another quest's group that lies between two of them comes in
-- between. The step is still one line on your route (at its first visit);
-- what depends on it (the turn-in) comes after its last visit.
-- Flow can't see what's alive: how many a group yields is a guess, and the
-- plan is made again as you go.
-------------------------------------------------------------------------------
P.GROUP_YARDS = 60     -- spots this close to a group's middle are one group
P.PER_GROUP = 4        -- what one group is taken to yield
P.MAX_VISITS = 3       -- visits planned for one step
P.MAX_EXTRA = 8        -- extra visits in one plan (the order's size is what costs time)
P.GROUP_SPOTS = 60     -- a step's nearest spots looked at

function P.GroupsOn() return not (ns.db and ns.db.nav and ns.db.nav.groupVisits == false) end

-- Pure: spots into groups, in the order given (nearest first: so the groups
-- come out nearest first too). -> { { x, y, points = { pt } } }
function P.Groups(points, yards)
    local out = {}
    for _, pt in ipairs(points or NONE) do
        local home
        for _, grp in ipairs(out) do
            if dist(pt.wx, pt.wy, grp.x, grp.y) <= (yards or P.GROUP_YARDS) then home = grp break end
        end
        if not home then
            home = { x = pt.wx, y = pt.wy, points = {} }
            out[#out + 1] = home
        end
        local n = #home.points
        home.x, home.y = (home.x * n + pt.wx) / (n + 1), (home.y * n + pt.wy) / (n + 1)
        home.points[n + 1] = pt
    end
    return out
end

-- Pure: how many visits a step gets. left: how many are still to get (nil:
-- not known); groups: how many groups its spots lie in.
function P.VisitsFor(left, groups)
    if (groups or 0) < 2 then return 1 end
    local want = left and math.ceil(left / P.PER_GROUP) or 2
    return math.max(1, math.min(want, P.MAX_VISITS, groups))
end

-- Splits the kept steps' kill and collect steps into visits (in place).
local function expand(p, stops)
    local N = ns.nav
    local extra, n = 0, #stops
    for i = 1, n do
        local s = stops[i]
        local goal = s.goal
        if extra < P.MAX_EXTRA and goal.area and goal.points and #goal.points > 1
            and not (N and N.GatherSpots and N.GatherSpots(goal)) then
            local pts = {}
            for _, pt in ipairs(goal.points) do
                if pt.wx and pt.cont == p.cont then pts[#pts + 1] = pt end
            end
            for _, pt in ipairs(pts) do dk[pt] = dist(p.wx, p.wy, pt.wx, pt.wy) end
            table.sort(pts, byNear)
            for j = #pts, P.GROUP_SPOTS + 1, -1 do dk[pts[j]] = nil; pts[j] = nil end
            local groups = P.Groups(pts)
            local visits = math.min(P.VisitsFor(goal.left, #groups), 1 + (P.MAX_EXTRA - extra))
            if visits >= 2 then
                for j = 1, visits do
                    local grp = groups[j]
                    for k = #grp.points, MAX_POINTS + 1, -1 do grp.points[k] = nil end
                    if j == 1 then
                        s.points, s.visit, s.gx, s.gy = grp.points, 1, grp.x, grp.y
                    else
                        stops[#stops + 1] = { goal = goal, key = s.key, points = grp.points, near = dk[grp.points[1]] or s.near,
                                              visit = j, gx = grp.x, gy = grp.y }
                        extra = extra + 1
                    end
                end
            end
            for _, pt in ipairs(pts) do dk[pt] = nil end
        end
    end
    return extra
end
P._expand = function(p, stops) return expand(p, stops) end   -- (tests)

-- Walks an order from your position. Returns weighted cost, legs, points.
-- (The legs are straight yards, what the route shows; the cost counts flights.)
local function walk(p, order)
    local from, total = p, 0
    local legs, pts = {}, {}
    for i, s in ipairs(order) do
        local best, bd = nearest(from, s)
        legs[i], pts[i] = dist(from.wx, from.wy, best.wx, best.wy), best
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

local posOf = {}   -- (valid: each step's place in the order; reused)
local function valid(order)
    local pos = posOf
    for k in pairs(pos) do pos[k] = nil end
    -- (A step with several visits: its place is its last one, so what waits
    -- for it waits for all of them. Your own first pick goes by its first.)
    local firstAt
    for i, s in ipairs(order) do
        pos[s.key] = i
        if not firstAt and s.key == OPT.first then firstAt = i end
    end
    if OPT.first and firstAt and firstAt ~= 1 then return false end
    local lastTour, firstOther = 0, math.huge
    for i, s in ipairs(order) do
        for _, dep in ipairs(s.goal.deps or {}) do
            if pos[dep] and pos[dep] > i and binds(s.key, dep) then return false end
        end
        if OPT.tour then
            if OPT.tour[s.key] or s.key == OPT.first then lastTour = i
            elseif i < firstOther then firstOther = i end
        end
    end
    if lastTour >= firstOther then return false end
    -- This zone's steps before the next zone's.
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
            for _, dep in ipairs(s.goal.deps or {}) do if left[dep] and binds(s.key, dep) then ready = false end end
            -- Your chosen step first, then the rest of the tour, then the others.
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
        if not bestI then
            -- Nothing may come next (your pick, or a tour step, waits for a
            -- step): your pick / the tour still goes first, its deps aside.
            -- P:Plan flags each dep the order breaks ("forced").
            for i, s in ipairs(remaining) do
                local ready = not ((firstLeft and s.key ~= OPT.first)
                    or (tourLeft and not (OPT.tour[s.key] or s.key == OPT.first)))
                if ready then
                    local _, bd = nearest(from, s)
                    local score = bd * (s.goal.weight or 1)
                    if not bestScore or score < bestScore then bestI, bestScore = i, score end
                end
            end
        end
        if not bestI then bestI = 1 end  -- (can't happen once loops are broken; never loop forever)
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
        -- Move one step elsewhere.
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

-- Drop optional steps that add more than OPTIONAL_DETOUR yards.
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

-- The area around you (OPT.near): steps within AREA yards (quest pickups
-- AREA_PICKUP) that aren't in another zone. A step whose quest objectives
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
                    if keyed[dep] and not near[dep] and binds(s.key, dep) then near[s.key], changed = nil, true break end
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
        -- Polish the near part, then carry on nearest-next from its last step.
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

-- Pure: loops among the steps' deps (a waits for b, b waits for a: no order
-- can keep both). Each loop is broken at one dep, the same one every time
-- (steps and their deps are walked in key order): the dep that closes it.
-- -> broken ({ [key] = { [dep] = true } }, or nil), loops ({ { key, dep, ..., key } }).
function P.FindCycles(stops)
    local deps, keys = {}, {}
    for _, s in ipairs(stops or NONE) do
        if not deps[s.key] then deps[s.key] = {}; keys[#keys + 1] = s.key end
    end
    for _, s in ipairs(stops or NONE) do
        local list = deps[s.key]
        for _, d in ipairs(s.goal.deps or NONE) do
            if deps[d] then
                local has = false
                for _, x in ipairs(list) do if x == d then has = true end end
                if not has then list[#list + 1] = d end
            end
        end
    end
    table.sort(keys)
    for _, list in pairs(deps) do table.sort(list) end
    local state, stack, broken, loops = {}, {}, nil, {}
    local function visit(k)
        state[k] = 1
        stack[#stack + 1] = k
        for _, d in ipairs(deps[k]) do
            if state[d] == 1 then
                local loop, on = {}, false
                for _, x in ipairs(stack) do
                    if x == d then on = true end
                    if on then loop[#loop + 1] = x end
                end
                loop[#loop + 1] = d
                loops[#loops + 1] = loop
                broken = broken or {}
                broken[k] = broken[k] or {}
                broken[k][d] = true
            elseif not state[d] then
                visit(d)
            end
        end
        stack[#stack] = nil
        state[k] = 2
    end
    for _, k in ipairs(keys) do if not state[k] then visit(k) end end
    return broken, loops
end

-- Pure: every dep the order breaks (a step planned before one it waits for),
-- flagged on its entry (entry.outOfOrder = { dep, ... }) and listed on the
-- plan (plan.outOfOrder = { { key, dep, why = "loop" | "forced", text } }).
-- An order is never wrong in silence. byKey: key -> goal, for the names.
function P.FlagOrder(plan, order, broken, byKey)
    local first, last = {}, {}
    for i, s in ipairs(order) do
        first[s.key] = first[s.key] or i
        last[s.key] = i
    end
    local function name(key)
        local g = byKey and byKey[key]
        return g and (g.text or g.title) or tostring(key)
    end
    for _, e in ipairs(plan) do
        local key = e.goal.key
        for _, dep in ipairs(e.goal.deps or NONE) do
            if first[key] and last[dep] and last[dep] > first[key] then
                local loop = broken and broken[key] and broken[key][dep]
                e.outOfOrder = e.outOfOrder or {}
                e.outOfOrder[#e.outOfOrder + 1] = dep
                plan.outOfOrder = plan.outOfOrder or {}
                plan.outOfOrder[#plan.outOfOrder + 1] = {
                    key = key, dep = dep, why = loop and "loop" or "forced",
                    text = string.format("%s comes before %s, which it waits for (%s)", name(key), name(dep),
                        loop and "each waits for the other: a loop in the steps' data" or "the step you chose goes first"),
                }
            end
        end
    end
    return plan
end

local lastFlags   -- (what was last logged, so a replan doesn't repeat it)

-- Returns the trip: { { goal, point, leg, cum }, ..., dropped = { text },
-- loops = { { key, ... } } (P.FindCycles), outOfOrder (P.FlagOrder) }
function P:Plan(p, goals, opts)
    OPT = {}   -- (a copy: the area rule adds to it)
    for k, v in pairs(opts or {}) do OPT[k] = v end
    OPT.near = nil
    nearPt, nearD = {}, {}   -- the nearest-spot answers are for this plan only
    local stops = candidates(p, goals)
    if #stops == 0 then return nil end
    if OPT.groups ~= false and P.GroupsOn() then expand(p, stops) end
    local loops
    OPT.broken, loops = P.FindCycles(stops)
    local order = build(p, stops)
    -- Finish this area: if the best trip leaves the area before it's done,
    -- plan one that doesn't, and keep that unless it costs a lot more.
    local areaFirst = OPT.areaFirst
    -- Off unless you tick it: the arrow follows the shortest whole trip, not
    -- whatever is closest (on by default, it sent you to the near steps first).
    if areaFirst == nil then areaFirst = (ns.db and ns.db.nav and ns.db.nav.areaFirst == true) or false end
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
    -- One line a step, at its first visit; its later visits ride on it
    -- (entry.visits) and on plan.hops, the groups in the order they're
    -- planned (the arrow leads from one to the next: AreaHop.lua).
    local plan, cum, seen = { dropped = dropped, hops = {} }, 0, {}
    for i, s in ipairs(order) do
        cum = cum + legs[i]
        local e = seen[s.key]
        if not e then
            e = { goal = s.goal, point = pts[i], leg = legs[i], cum = cum }
            plan[#plan + 1] = e
            seen[s.key] = e
        else
            e.visits = e.visits or { e.point }
            e.visits[#e.visits + 1] = pts[i]
        end
        if s.visit then plan.hops[#plan.hops + 1] = { key = s.key, wx = s.gx, wy = s.gy, visit = s.visit } end
    end
    local byKey = {}
    for _, s in ipairs(stops) do byKey[s.key] = s.goal end
    if #loops > 0 then plan.loops = loops end
    P.FlagOrder(plan, order, OPT.broken, byKey)
    local flags = {}
    for _, l in ipairs(loops) do flags[#flags + 1] = "loop: " .. table.concat(l, " > ") end
    for _, o in ipairs(plan.outOfOrder or NONE) do flags[#flags + 1] = o.text end
    local sig = table.concat(flags, "; ")
    if sig ~= "" and sig ~= lastFlags and ns.Log then ns:Log("route", "order: " .. sig) end
    lastFlags = sig
    nearPt, nearD = {}, {}
    return plan
end

if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck({
        group = "route",
        label = "Plan a visit to each group of a quest's mobs",
        note = "(not just its nearest spot)",
        tip = "A kill or collect step whose spots lie in several groups is planned as a visit to each of its nearest groups (up to three), so the route "
            .. "threads through the groups of several quests. Off: each such step counts as one spot, as it used to.",
        get = function() return P.GroupsOn() end,
        set = function(on)
            ns.db.nav.groupVisits = on and true or false
            if ns.nav and ns.nav.RequestCollect then ns.nav.RequestCollect("group visits") end
        end,
    })
end

-- Timed for /flow perf.
P.Plan = ns.perf.Wrap("route: order steps", P.Plan)
