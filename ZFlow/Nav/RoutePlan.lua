local _, ns = ...
-- Z-Flow route planner (G42): puts a list of places into a short order to
-- visit them on one map. Pure Lua 5.1: no client calls, nothing saved,
-- nothing printed, no UI. It only orders what it is handed: places this
-- player learned. Nothing is authored here.
--
-- STRAIGHT LINES, unless the caller hands in the player's own trip times
-- (legs, S34). There is no path data: a distance is the straight line
-- between two places on the flat map, in yards, or what the player's own
-- trip between those two places took. Walls, water, hills and roads are
-- not known and not guessed. Every route says which (route.straight,
-- route.label) and whoever shows a route must show that too. The order is a short one, not promised to be the shortest.
-- Not tested in game.
--
-- N.ROUTE_STRAIGHT  the words that go with a straight-line route
-- N.ROUTE_LEARNED   the words when any leg was measured by a trip the
--                   player made (legs, below)
-- N.ROUTE_MAX       the most places one route takes
--
-- N.RoutePlan(places, map, size, from, legs) -> route, reason
--   places  a list; each { map, x, y, ... } with x, y shares 0..1 of map.
--           Read only: it is not changed and not copied.
--   map     the one map the route is on
--   size    { w, h }: the size of that map in yards
--   from    optional { map, x, y }: where the route starts (the player).
--           Not on this map, or with no x, y: the start is not known.
--   legs    optional (S34, lead section 169 A): the player's own trip
--           times, legs(a, b, d) -> yards, how, with a and b { x, y } in
--           yards on this map and d the straight yards between them
--           (Nav/Legs.lua). how "exact" (a trip made) is taken as it is;
--           how "area" (its neighbourhood) only ever stretches the line.
--           nil, another how, or an error: the straight line. Without
--           legs every distance is the straight line, as before.
--
--   route = {
--     map, straight, label,
--                  -- straight is true, and label N.ROUTE_STRAIGHT, when
--                  -- no leg was measured by legs; else false and
--                  -- N.ROUTE_LEARNED
--     fromKnown,   -- true when the route starts at `from`
--     stops = { { index, place, leg, how }, ... }   in the order to visit
--                  -- index: where the place is in `places`
--                  -- place: places[index] itself
--                  -- leg: yards from the stop before (from `from` for the
--                  --   first): the straight line, or what legs gave.
--                  --   Absent for the first stop when the start is not
--                  --   known: never 0 for that.
--                  -- how: "exact" or "area" when legs measured it, else nil
--     total,       -- the legs added up, in yards
--     left = { { index, reason }, ... }   places not in the route:
--                  -- "no place"   not a table, or no x, y in 0..1
--                  -- "other map"  on another map than `map`
--   }
--
--   No route, and the reason, for the first of these that holds:
--     "no map"           map is nil
--     "size unknown"     size has no w, h above 0: shares of a map cannot
--                        be compared without it, so no order is claimed
--     "no places"        places is not a list, or none of it is on the map
--     "too many places"  more than N.ROUTE_MAX of them are on the map
--
-- How the order is made: the nearest place next, from the start (from the
-- first place of the list when the start is not known); then, while it
-- makes the whole shorter, the best of turning one run of stops around or
-- moving one stop elsewhere. The same input always gives the same order.
ns.Nav = ns.Nav or {}
local N = ns.Nav

N.ROUTE_STRAIGHT = "straight lines, not paths"
N.ROUTE_LEARNED = "your own trip times where known, straight lines elsewhere"
N.ROUTE_MAX = 40

local EPS = 1e-9
local ROUNDS = 400

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function share(v)
    return finite(v) and v >= 0 and v <= 1
end

-- Yards between two points given as yards east and south.
local function apart(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

-- The length of an order of points: from the start when there is one,
-- then stop to stop. far(p, q) is the cost of one leg.
local function length(order, pts, start, far)
    local sum, last = 0, start
    for i = 1, #order do
        local p = pts[order[i]]
        if last then sum = sum + far(last, p) end
        last = p
    end
    return sum
end

local function clone(order)
    local out = {}
    for i = 1, #order do out[i] = order[i] end
    return out
end

-- order with the run i..j turned around.
local function turned(order, i, j)
    local out = clone(order)
    while i < j do
        out[i], out[j] = out[j], out[i]
        i, j = i + 1, j - 1
    end
    return out
end

-- order with the stop at i taken out and put in at j.
local function moved(order, i, j)
    local out = clone(order)
    local v = table.remove(out, i)
    table.insert(out, j, v)
    return out
end

-- The nearest place next. Ties go to the place earlier in the list.
local function nearestFirst(pts, start, far)
    local n = #pts
    local used, order = {}, {}
    local last = start
    if not last then
        order[1], used[1], last = 1, true, pts[1]
    end
    while #order < n do
        local best, bestD
        for i = 1, n do
            if not used[i] then
                local d = far(last, pts[i])
                if bestD == nil or d < bestD - EPS then best, bestD = i, d end
            end
        end
        order[#order + 1], used[best], last = best, true, pts[best]
    end
    return order
end

-- While it makes the whole shorter: the best single change. The first
-- found wins a tie.
local function shorten(order, pts, start, far)
    local n = #order
    local len = length(order, pts, start, far)
    for _ = 1, ROUNDS do
        local best, bestLen = nil, len
        for i = 1, n - 1 do
            for j = i + 1, n do
                local try = turned(order, i, j)
                local l = length(try, pts, start, far)
                if l < bestLen - EPS then best, bestLen = try, l end
            end
        end
        for i = 1, n do
            for j = 1, n do
                if i ~= j then
                    local try = moved(order, i, j)
                    local l = length(try, pts, start, far)
                    if l < bestLen - EPS then best, bestLen = try, l end
                end
            end
        end
        if not best then break end
        order, len = best, bestLen
    end
    return order
end

-- The cost of a leg from p to q with the player's own trips (S34): what
-- legs(p, q, d) answers, asked once per pair and kept. An "exact" answer
-- (a trip the player made) is taken as it is, quicker than the line too
-- (a flight); an "area" answer only ever stretches the line. Anything
-- else, an error included: the straight line, and no how.
local function costs(legs)
    local memo, hows = {}, {}
    local function far(p, q)
        local row = memo[p]
        if not row then
            row = {}
            memo[p] = row
        end
        local v = row[q]
        if v ~= nil then return v end
        local d = apart(p, q)
        v = d
        local ok, yards, how = pcall(legs, { x = p.x, y = p.y }, { x = q.x, y = q.y }, d)
        if ok and finite(yards) and yards > 0 and (how == "exact" or how == "area") then
            if how == "area" then yards = math.max(d, yards) end
            v = yards
            hows[p] = hows[p] or {}
            hows[p][q] = how
        end
        row[q] = v
        return v
    end
    local function howOf(p, q)
        return hows[p] and hows[p][q] or nil
    end
    return far, howOf
end

function N.RoutePlan(places, map, size, from, legs)
    if map == nil then return nil, "no map" end
    if type(size) ~= "table" or not (finite(size.w) and finite(size.h) and size.w > 0 and size.h > 0) then
        return nil, "size unknown"
    end
    if type(places) ~= "table" then return nil, "no places" end

    -- pts[n] = { x, y (yards), index (in places) }
    local pts, left = {}, {}
    for i = 1, #places do
        local p = places[i]
        if type(p) ~= "table" or not (share(p.x) and share(p.y)) then
            left[#left + 1] = { index = i, reason = "no place" }
        elseif p.map ~= map then
            left[#left + 1] = { index = i, reason = "other map" }
        else
            pts[#pts + 1] = { x = p.x * size.w, y = p.y * size.h, index = i }
        end
    end
    if #pts == 0 then return nil, "no places" end
    if #pts > N.ROUTE_MAX then return nil, "too many places" end

    local start
    if type(from) == "table" and from.map == map and share(from.x) and share(from.y) then
        start = { x = from.x * size.w, y = from.y * size.h }
    end

    local far, howOf = apart, nil
    if type(legs) == "function" then far, howOf = costs(legs) end

    local order = shorten(nearestFirst(pts, start, far), pts, start, far)

    local stops, total, last = {}, 0, start
    local straight = true
    for i = 1, #order do
        local p = pts[order[i]]
        local stop = { index = p.index, place = places[p.index] }
        if last then
            stop.leg = far(last, p)
            stop.how = howOf and howOf(last, p) or nil
            if stop.how then straight = false end
            total = total + stop.leg
        end
        stops[i], last = stop, p
    end
    return {
        map = map, straight = straight, label = straight and N.ROUTE_STRAIGHT or N.ROUTE_LEARNED,
        fromKnown = start ~= nil, stops = stops, total = total, left = left,
    }
end
