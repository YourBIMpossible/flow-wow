local _, ns = ...
-- Z-Flow route planner (G42): puts a list of places into a short order to
-- visit them on one map. Pure Lua 5.1: no client calls, nothing saved,
-- nothing printed, no UI. It only orders what it is handed: places this
-- player learned. Nothing is authored here.
--
-- STRAIGHT LINES ONLY. There is no path data: every distance is the
-- straight line between two places on the flat map, in yards. Walls,
-- water, hills and roads are not known and not guessed. Every route says
-- so (route.straight, route.label) and whoever shows a route must show
-- that too. The order is a short one, not promised to be the shortest.
-- Not tested in game.
--
-- N.ROUTE_STRAIGHT  the words that go with every route
-- N.ROUTE_MAX       the most places one route takes
--
-- N.RoutePlan(places, map, size, from) -> route, reason
--   places  a list; each { map, x, y, ... } with x, y shares 0..1 of map.
--           Read only: it is not changed and not copied.
--   map     the one map the route is on
--   size    { w, h }: the size of that map in yards
--   from    optional { map, x, y }: where the route starts (the player).
--           Not on this map, or with no x, y: the start is not known.
--
--   route = {
--     map, straight = true, label = N.ROUTE_STRAIGHT,
--     fromKnown,   -- true when the route starts at `from`
--     stops = { { index, place, leg }, ... }   in the order to visit
--                  -- index: where the place is in `places`
--                  -- place: places[index] itself
--                  -- leg: yards in a straight line from the stop before
--                  --   (from `from` for the first). Absent for the first
--                  --   stop when the start is not known: never 0 for that.
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
-- then stop to stop.
local function length(order, pts, start)
    local sum, last = 0, start
    for i = 1, #order do
        local p = pts[order[i]]
        if last then sum = sum + apart(last, p) end
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
local function nearestFirst(pts, start)
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
                local d = apart(last, pts[i])
                if bestD == nil or d < bestD - EPS then best, bestD = i, d end
            end
        end
        order[#order + 1], used[best], last = best, true, pts[best]
    end
    return order
end

-- While it makes the whole shorter: the best single change. The first
-- found wins a tie.
local function shorten(order, pts, start)
    local n = #order
    local len = length(order, pts, start)
    for _ = 1, ROUNDS do
        local best, bestLen = nil, len
        for i = 1, n - 1 do
            for j = i + 1, n do
                local try = turned(order, i, j)
                local l = length(try, pts, start)
                if l < bestLen - EPS then best, bestLen = try, l end
            end
        end
        for i = 1, n do
            for j = 1, n do
                if i ~= j then
                    local try = moved(order, i, j)
                    local l = length(try, pts, start)
                    if l < bestLen - EPS then best, bestLen = try, l end
                end
            end
        end
        if not best then break end
        order, len = best, bestLen
    end
    return order
end

function N.RoutePlan(places, map, size, from)
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

    local order = shorten(nearestFirst(pts, start), pts, start)

    local stops, total, last = {}, 0, start
    for i = 1, #order do
        local p = pts[order[i]]
        local stop = { index = p.index, place = places[p.index] }
        if last then
            stop.leg = apart(last, p)
            total = total + stop.leg
        end
        stops[i], last = stop, p
    end
    return {
        map = map, straight = true, label = N.ROUTE_STRAIGHT,
        fromKnown = start ~= nil, stops = stops, total = total, left = left,
    }
end
