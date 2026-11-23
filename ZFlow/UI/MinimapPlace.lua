-- Where the minimap button sits on the minimap's rim (lead DISPATCH section
-- 340). Pure: no client, no state.
--   MinimapPlace.DEFAULT                 the angle before any drag (bottom left)
--   MinimapPlace.Normalize(a) -> a in [0, 360), or nil for anything not a number
--   MinimapPlace.Radius(size) -> how far from the middle the button sits:
--     half the minimap's width and 10 past it; 80 without a size
--   MinimapPlace.Offset(angle, radius, square) -> x, y from the middle,
--     x right and y up; 0 degrees is right, 90 is up. On a square minimap
--     the place is pushed out to the square's edge, so 45 is the corner.
--   MinimapPlace.Angle(dx, dy) -> the angle of a cursor offset from the
--     middle, or nil at the middle itself
local _, ns = ...

local MP = {}
ns.MinimapPlace = MP

MP.DEFAULT = 225
MP.PAST_EDGE = 10
MP.SIZE = 140

function MP.Normalize(a)
    if type(a) ~= "number" or a ~= a or a == math.huge or a == -math.huge then return nil end
    a = a % 360
    if a < 0 then a = a + 360 end
    return a
end

function MP.Radius(size)
    if type(size) ~= "number" or size ~= size or size <= 0 or size == math.huge then size = MP.SIZE end
    return size / 2 + MP.PAST_EDGE
end

function MP.Offset(angle, radius, square)
    local a = math.rad(MP.Normalize(angle) or MP.DEFAULT)
    local r = MP.Radius(nil)
    if type(radius) == "number" and radius == radius then r = radius end
    local cx, cy = math.cos(a), math.sin(a)
    if square == true then
        local m = math.max(math.abs(cx), math.abs(cy))
        if m > 0 then cx, cy = cx / m, cy / m end
    end
    return cx * r, cy * r
end

function MP.Angle(dx, dy)
    if type(dx) ~= "number" or type(dy) ~= "number" or dx ~= dx or dy ~= dy then return nil end
    if dx == 0 and dy == 0 then return nil end
    return MP.Normalize(math.deg(math.atan2(dy, dx)))
end
