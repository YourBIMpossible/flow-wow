local _, ns = ...
-- Z-Flow waypoint step: a quest step made from the player's own map
-- waypoint. Client data only: no route data, nothing authored but the label.
-- Pure given a client: no frames, nothing remembered.
--
-- N.WaypointStep(client) -> step or nil
--   step = { label = N.WAYPOINT_LABEL,
--            place = { cont = client.zone().cont, map, x, y } }
--   the shape Arrow.GuideSource takes as given.quest (the corpse step's
--   shape in UI/Arrow.lua). x and y are shares 0..1 of map.
--
-- nil when the client has no waypoint read, the read fails, no waypoint is
-- set, or the answer is not a map with two finite numbers. cont is the
-- continent of the zone the player is in, as the corpse step has it; it is
-- left out when the client does not say. Nothing is guessed.
ns.Nav = ns.Nav or {}
local N = ns.Nav

N.WAYPOINT_LABEL = "Waypoint"

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- One read of the client, or nil when it has no such read or the read fails.
local function ask(client, name)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name])
    if not ok then return nil end
    return v
end

function N.WaypointStep(client)
    local at = ask(client, "waypoint")
    if type(at) ~= "table" or at.map == nil or not finite(at.x) or not finite(at.y) then return nil end
    local zone = ask(client, "zone")
    return {
        label = N.WAYPOINT_LABEL,
        place = { cont = type(zone) == "table" and zone.cont or nil, map = at.map, x = at.x, y = at.y },
    }
end
