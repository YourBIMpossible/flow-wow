local _, ns = ...
-- Z-Flow bearing: the direction and distance from one place to another, as
-- plain data. Pure Lua 5.1: no client calls. Unknown stays unknown: a place
-- that cannot be related to the other gives no number at all.
ns.Nav = ns.Nav or {}
local N = ns.Nav

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function goodPlace(p)
    return type(p) == "table" and finite(p.x) and finite(p.y)
end

local function unknown(reason)
    return { known = false, reason = reason }
end

-- A zone's entry in a link, or nil. { x, y }: where the zone's own origin
-- lies, in yards east and south, in a frame shared by every zone of the link.
local function origin(link, zone)
    local o = type(link) == "table" and zone ~= nil and link[zone] or nil
    if type(o) == "table" and finite(o.x) and finite(o.y) then return o end
    return nil
end

-- From one place to another.
--   from, to: { cont, zone, x, y }. x is yards east and y is yards south of
--     the zone's own origin.
--   link: optional, { [zone] = { x, y } }: each zone's origin in one shared
--     frame, so places in two zones of one continent can be related.
-- -> { known = true, distance = yards, bearing = radians clockwise from
--      north in [0, 2*pi), east = yards, south = yards }
--    bearing is nil when the two places are the same spot (distance 0).
-- -> { known = false, reason = "place" | "continent" | "zone" }
--    "place": a point is missing or has no usable x, y.
--    "continent": the continents are known and differ.
--    "zone": the zones differ, or one is unknown, and no link covers both.
function N.Bearing(from, to, link)
    if not goodPlace(from) or not goodPlace(to) then return unknown("place") end
    if from.cont ~= nil and to.cont ~= nil and from.cont ~= to.cont then return unknown("continent") end
    local fx, fy, tx, ty = from.x, from.y, to.x, to.y
    if from.zone == nil or to.zone == nil or from.zone ~= to.zone then
        local a, b = origin(link, from.zone), origin(link, to.zone)
        if not a or not b then return unknown("zone") end
        fx, fy, tx, ty = fx + a.x, fy + a.y, tx + b.x, ty + b.y
    end
    local east, south = tx - fx, ty - fy
    local distance = math.sqrt(east * east + south * south)
    local bearing
    if distance > 0 then
        bearing = math.atan2(east, -south)
        if bearing < 0 then bearing = bearing + 2 * math.pi end
    end
    return { known = true, distance = distance, bearing = bearing, east = east, south = south }
end

-- The compass word for a bearing (G40): which of eight points it is nearest.
-- Each point takes the eighth of the circle around it. These are the words
-- a player reads beside a distance; authored here.
N.COMPASS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

-- bearing: radians clockwise from north, as N.Bearing gives it. Any whole
-- turns over are taken off.
-- -> one of N.COMPASS; nil when the bearing is not a finite number (so a
-- place with no direction to it has no word).
function N.Compass(bearing)
    if not finite(bearing) then return nil end
    local eighth = math.pi / 4
    local i = math.floor(bearing / eighth + 0.5) % 8
    return N.COMPASS[i + 1]
end

-- How far an arrow turns to point along a bearing, for a player facing
-- `facing` (radians anticlockwise from north, as the client reports it).
-- -> radians anticlockwise from straight up, in (-pi, pi]; nil when either
-- value is unknown. Flow's rule: -(bearing + facing).
function N.ArrowTurn(bearing, facing)
    if not finite(bearing) or not finite(facing) then return nil end
    local turn = -(bearing + facing)
    turn = turn - 2 * math.pi * math.floor(turn / (2 * math.pi))   -- [0, 2*pi)
    if turn > math.pi then turn = turn - 2 * math.pi end
    return turn
end
