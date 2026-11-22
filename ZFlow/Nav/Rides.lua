local _, ns = ...
-- Z-Flow rides (S33): "Talk to Bunthen Plainswind" when the player is in a
-- ride's zone and the step the guide is on is outside it. Ported from
-- legacy Flow 0.35.377 (Modules/Nav/Rides.lua): after Teleport: Moonglade
-- the owner asked "how do I get back now? where do I go from Moonglade?";
-- the way out is a person, the druids' flight master. Pure. It only says
-- so: nothing talks to anyone for the player. Not tested in game.
--
-- N.RIDES  { { name, from, to, toName, class, faction, how }, ... } as
--          legacy Flow has them (maps are the game's uiMapIDs: Moonglade
--          1450, Thunder Bluff 1456, Teldrassil 1438). Legacy's landing
--          coordinates are not ported: Z-Flow plans on one map and cannot
--          measure a flight, so they are not needed.
--
-- N.RideStep(rides, target, here, class, faction, npcs) -> step, reason
--   target   { map, x, y }: the step the guide is on
--   here     { position = { map, x, y } }
--   class    the player's class token, or nil
--   faction  "Horde" or "Alliance", or nil
--   npcs     the saved npc places, account "learned.places.npcs"
--            [name] = { map, x, y, ... }; where the ride's npc stands is
--            taken only from there, never authored
--   step = { label = "Talk to <name>", text = true, ride = name,
--            detail = how, point = { map, x, y } when the npc's saved place
--            is on the player's map }
--   No step, and the reason, for the first of these that holds:
--     "no target", "class unknown", "faction unknown", "position unknown",
--     "same map" (the step is on the player's map), "no ride" (none leaves
--     the player's map for this class and faction)
ns.Nav = ns.Nav or {}
local N = ns.Nav

N.RIDES = {
    { name = "Bunthen Plainswind", from = 1450, to = 1456, toName = "Thunder Bluff",
      class = "DRUID", faction = "Horde", how = "he flies druids to Thunder Bluff, free" },
    { name = "Silva Fil'naveth", from = 1450, to = 1438, toName = "Rut'theran Village, below Darnassus",
      class = "DRUID", faction = "Alliance", how = "she flies druids to Rut'theran Village, free" },
}
N.RIDE_PLAIN = "Talk to the flight master here"

local function share(v) return type(v) == "number" and v >= 0 and v <= 1 end

local function labelMax()
    return (N.Waypoint and N.Waypoint.LABEL_MAX) or (ns.Waypoint and ns.Waypoint.LABEL_MAX) or 40
end

function N.RideStep(rides, target, here, class, faction, npcs)
    if type(target) ~= "table" or type(target.map) ~= "number" then return nil, "no target" end
    if type(class) ~= "string" or class == "" then return nil, "class unknown" end
    if faction ~= "Horde" and faction ~= "Alliance" then return nil, "faction unknown" end
    local pos = type(here) == "table" and here.position or nil
    if type(pos) ~= "table" or type(pos.map) ~= "number" then return nil, "position unknown" end
    if pos.map == target.map then return nil, "same map" end
    local ride
    for _, r in ipairs(type(rides) == "table" and rides or {}) do
        if type(r) == "table" and r.from == pos.map and (r.class == nil or r.class == class)
            and (r.faction == nil or r.faction == faction) then
            ride = r
            break
        end
    end
    if not ride then return nil, "no ride" end
    local label = "Talk to " .. ride.name
    if #label > labelMax() then label = N.RIDE_PLAIN end
    local step = { label = label, text = true, ride = ride.name, detail = ride.how }
    local spot = type(npcs) == "table" and npcs[ride.name] or nil
    if type(spot) == "table" and spot.map == pos.map and share(spot.x) and share(spot.y) then
        step.point = { map = spot.map, x = spot.x, y = spot.y }
    end
    return step
end
