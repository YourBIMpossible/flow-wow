local _, ns = ...
-- Z-Flow minimap pin, the pure part (G43): where on the minimap a place
-- is, as an offset from the middle of the minimap. Pure Lua 5.1: no client
-- calls, no frames, nothing saved, nothing printed. Straight lines on the
-- flat map. Unknown stays unknown: with anything missing there is no pin
-- at all, never a pin in a guessed spot. Not tested in game.
--
-- N.MinimapPin(target, here, mini) -> pin, reason
--   target  { map, x, y }: the place to pin; x, y shares 0..1 of map
--   here    { position = { map, x, y },   where the player is
--             size = { w, h },            that map in yards
--             facing = radians }          0 = north, turning left adds
--                                         (client.facing()); only used on
--                                         a minimap that turns
--   mini    { size,     how wide the minimap is drawn, in its own units
--             radius,   yards from the middle to the edge at the zoom now
--             rotates,  true: it turns with the player; false: north is up
--             square,   true: a square minimap; else taken as round
--             inset }   optional: how far inside the edge a pin at the
--                       edge sits (half the pin, so it stays on the map)
--
--   pin = { x, y,      offset from the middle: x to the right, y up
--           edge,      true: the place is off the minimap and the pin sits
--                      at the edge, in its direction
--           distance } yards to the place, in a straight line
--
--   A minimap not said to be square is taken as round: a pin held inside
--   the circle is inside the square too, so it is on the map either way.
--
--   No pin, and the reason, for the first of these that holds:
--     "no target"         target has no map or no x, y in 0..1
--     "minimap unknown"   no size or radius above 0, or nothing left of it
--                         inside the inset
--     "position unknown"  the map or the x, y of the player is not known
--     "other map"         the player is on another map than the target
--     "size unknown"      the size of the map in yards is not known
--     "rotation unknown"  mini.rotates is neither true nor false: which
--                         way is up is not known
--     "facing unknown"    the minimap turns and the facing is not known
ns.Nav = ns.Nav or {}
local N = ns.Nav

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function share(v)
    return finite(v) and v >= 0 and v <= 1
end

local function above0(v)
    return finite(v) and v > 0
end

function N.MinimapPin(target, here, mini)
    if type(target) ~= "table" or target.map == nil or not (share(target.x) and share(target.y)) then
        return nil, "no target"
    end
    if type(mini) ~= "table" or not (above0(mini.size) and above0(mini.radius)) then
        return nil, "minimap unknown"
    end
    local half = mini.size / 2
    local rim = half
    if above0(mini.inset) then rim = half - mini.inset end
    if rim <= 0 then return nil, "minimap unknown" end

    if type(here) ~= "table" then here = {} end
    local at = here.position
    if type(at) ~= "table" or at.map == nil or not (finite(at.x) and finite(at.y)) then
        return nil, "position unknown"
    end
    if at.map ~= target.map then return nil, "other map" end
    local size = here.size
    if type(size) ~= "table" or not (above0(size.w) and above0(size.h)) then
        return nil, "size unknown"
    end
    if mini.rotates ~= true and mini.rotates ~= false then return nil, "rotation unknown" end
    if mini.rotates and not finite(here.facing) then return nil, "facing unknown" end

    -- Yards east and north of the player.
    local east = (target.x - at.x) * size.w
    local north = (at.y - target.y) * size.h
    local distance = math.sqrt(east * east + north * north)

    local scale = half / mini.radius
    local x, y = east * scale, north * scale
    if mini.rotates then
        -- The way the player faces is up: the map is turned clockwise by
        -- the facing.
        local c, s = math.cos(here.facing), math.sin(here.facing)
        x, y = x * c + y * s, y * c - x * s
    end

    local edge = false
    local reach
    if mini.square == true then
        reach = math.max(math.abs(x), math.abs(y))
    else
        reach = math.sqrt(x * x + y * y)
    end
    if reach > rim then
        x, y, edge = x * rim / reach, y * rim / reach, true
    end
    return { x = x, y = y, edge = edge, distance = distance }
end
