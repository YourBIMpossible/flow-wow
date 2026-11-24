local _, ns = ...
-- Z-Flow guide: from where the player stands, which way they face and up to
-- two steps (one quest step, one profession step), the state table the arrow
-- view takes. Pure Lua 5.1: no client calls and nothing remembered.
-- Needs Nav/ArrowLayout.lua, Nav/Bearing.lua and Nav/ArrowView.lua.
--
-- Unknown stays unknown. With no usable place for the player or the step, or
-- zones that cannot be related, a step gets no distance and no turn. With no
-- facing it gets no turn. Nothing is guessed. A step that is not given gets
-- no arrow.
--
-- No quest or route data lives here: the steps are handed in.
ns.Nav = ns.Nav or {}
local N = ns.Nav

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- The size of a map in yards, from its entry in the link, or nil.
local function sizeOf(link, map)
    local e = type(link) == "table" and map ~= nil and link[map] or nil
    if type(e) == "table" and finite(e.w) and finite(e.h) and e.w > 0 and e.h > 0 then return e end
    return nil
end

-- A place in yards from a position on a map.
--   position: { map, x, y }, x and y as shares 0..1 of the map
--     (client.position()).
--   zone: { cont, zone } (client.zone()); only its cont is used.
--   link: the zone link N.Bearing takes, { [zone] = { x, y } }. An entry may
--     also carry w and h, the zone's width and height in yards. A map with
--     no w and h cannot be turned into yards.
-- -> { cont, zone = the position's map, x, y } in yards, as N.Bearing takes
-- -> nil, "place" (no usable position) or nil, "size" (no size for the map)
function N.GuidePlace(position, zone, link)
    if type(position) ~= "table" or position.map == nil or not finite(position.x) or not finite(position.y) then
        return nil, "place"
    end
    local size = sizeOf(link, position.map)
    if not size then return nil, "size" end
    return {
        cont = type(zone) == "table" and zone.cont or nil,
        zone = position.map,
        x = position.x * size.w,
        y = position.y * size.h,
    }
end

-- A step's place in yards. A place with `map` is a map position (shares of
-- the map); any other is taken as yards already.
local function stepPlace(place, link)
    if type(place) ~= "table" then return nil, "place" end
    if place.map ~= nil then return N.GuidePlace(place, place, link) end
    if not finite(place.x) or not finite(place.y) then return nil, "place" end
    return place
end

-- { cont, zone } of a step's place, for the arrow's colour; nil when the
-- place names neither.
local function targetOf(place)
    if type(place) ~= "table" then return nil end
    local zone = place.zone
    if zone == nil then zone = place.map end
    if place.cont == nil and zone == nil then return nil end
    return { cont = place.cont, zone = zone }
end

-- One step's part of the state: distance, turn and why not.
local function leg(step, from, fromWhy, facing, link)
    if type(step) ~= "table" then return { hasStep = false } end
    local out = { hasStep = true, target = targetOf(step.place) }
    if type(step.label) == "string" then out.label = step.label end
    local to, toWhy = stepPlace(step.place, link)
    if not from or not to then
        out.why = (not from and fromWhy) or toWhy or "place"
        return out
    end
    local b = N.Bearing(from, to, link)
    if not b.known then
        out.why = b.reason
        return out
    end
    out.distance = b.distance
    out.bearing = b.bearing
    out.turn = N.ArrowTurn(b.bearing, facing)
    if finite(step.radius) then out.here = b.distance <= step.radius end
    return out
end

-- input = {
--   position,   -- client.position(): { map, x, y } or nil
--   zone,       -- client.zone(): { cont, zone } or nil
--   facing,     -- client.facing(): radians or nil
--   link,       -- as N.Bearing takes it; w and h per zone for map positions
--   quest,      -- the quest step or nil
--   prof,       -- the profession step or nil
--   separate,   -- the two arrows are separated (the saved layout's mode)
--   view,       -- anything else the arrow view takes (layout, screenW,
--               -- screenH, size, defaultPoint, gate, palette): copied as is
-- }
--   a step: { place, label, radius }
--     place: { cont, zone, x, y } in yards (as N.Bearing), or
--            { cont, map, x, y } as shares of a map (as client.position()).
--     radius: yards; inside it the player is "here". Optional.
-- -> the state N.ArrowView takes:
--   player = { cont, zone } or nil, facingKnown,
--   quest = { hasStep, label, target, distance, turn, here, why, compass },
--   prof  = { hasStep, label, target, distance, turn, here, why, compass,
--             bearingKnown, mode },
--   compass: N.Compass of the bearing to the step ("N", "NE", ...); nil
--     with no distance, and at the very spot. It needs no facing.
--   plus the fields of `view`.
--   turn: radians anticlockwise from straight up (N.ArrowTurn); nil = unknown.
--   why: "place", "size", "zone" or "continent" when there is no distance.
--   prof.mode: N.ProfArrowMode's answer ("arrow", "ring" or "off").
function N.Guide(input)
    input = type(input) == "table" and input or {}
    local state = {}
    if type(input.view) == "table" then
        for k, v in pairs(input.view) do state[k] = v end
    end

    local zone = type(input.zone) == "table" and input.zone or nil
    local position = type(input.position) == "table" and input.position or nil
    if zone or (position and position.map ~= nil) then
        local z = zone and zone.zone
        if z == nil and position then z = position.map end
        state.player = { cont = zone and zone.cont or nil, zone = z }
    end
    local facing = finite(input.facing) and input.facing or nil
    state.facingKnown = facing ~= nil

    local from, fromWhy = N.GuidePlace(position, zone, input.link)
    local q = leg(input.quest, from, fromWhy, facing, input.link)
    local p = leg(input.prof, from, fromWhy, facing, input.link)
    -- The compass word (G40) is said from the bearing before it is dropped.
    q.compass, p.compass = N.Compass(q.bearing), N.Compass(p.bearing)
    q.bearing = nil
    p.bearingKnown = p.bearing ~= nil
    p.bearing = nil

    local profHere = (p.here or N.AtPoint(p.distance)) and true or false
    local canPoint = p.bearingKnown and state.facingKnown
    if p.hasStep then
        p.mode = N.ProfArrowMode(false, profHere, canPoint)
    else
        p.mode = "off"
    end

    state.quest, state.prof = q, p
    return state
end
