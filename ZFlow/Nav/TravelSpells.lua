local _, ns = ...
-- Z-Flow travel spells (S33): "Cast Teleport: Moonglade" when the step the
-- guide is on is in that spell's zone and the player is not, and the
-- player knows the spell; "Learn Teleport: Moonglade" with where it comes
-- from when they do not. Ported from legacy Flow 0.35.377
-- (Modules/Nav/TravelSpells.lua): the owner's level 10 druid was never sent
-- to Moonglade for the Bear Form quest because the route only knew feet.
-- One way only: the way back is on foot, by hearthstone or by a ride
-- (Nav/Rides.lua). Pure but for N.TravelSpellStepFrom. It only says so:
-- nothing casts for the player. Not tested in game.
--
-- N.TRAVEL_SPELLS  { { name, map, class, from }, ... } as legacy Flow has
--                  them; map is the game's uiMapID (Moonglade 1450)
-- N.TRAVEL_PLAIN, N.TRAVEL_LEARN_PLAIN  labels when a spell name would be
--                  over N.Waypoint.LABEL_MAX bytes (never cut)
--
-- N.TravelSpellStep(spells, target, here, class, knows) -> step, reason
--   target  { map, x, y }: the step the guide is on
--   here    { position = { map, x, y } } (position may be absent)
--   class   the player's class token ("DRUID"), or nil
--   knows   function(name) -> true, false, or nil when the client did not say
--   step = { label, text = true, spell } when known, or
--          { label, text = true, spell, learn = true, detail = from }
--   No step, and the reason, for the first of these that holds:
--     "no target"      target has no map
--     "class unknown"  class is not a string
--     "no spell"       no spell of this class reaches the target's map
--     "same map"       the player is already on that map
--     "known unknown"  knows() gave neither true nor false: never taken as known
--   A player whose position is not known still gets the step: the spell
--   works from anywhere else.
--
-- N.TravelSpellStepFrom(target, client) -> the same, read from
--   client.class(), client.position(), client.spellId(name) and
--   client.spell(id).known. No id or no answer: "known unknown".
ns.Nav = ns.Nav or {}
local N = ns.Nav

N.TRAVEL_SPELLS = {
    { name = "Teleport: Moonglade", map = 1450, class = "DRUID", from = "your class trainer, from level 10" },
}
-- What a ten-second cast is worth in running yards, for a planner that
-- measures a step a cast away (legacy TS.YARDS).
N.TRAVEL_SPELL_YARDS = 120
N.TRAVEL_PLAIN = "Use your travel spell"
N.TRAVEL_LEARN_PLAIN = "Learn a travel spell"

local function labelMax()
    return (N.Waypoint and N.Waypoint.LABEL_MAX) or (ns.Waypoint and ns.Waypoint.LABEL_MAX) or 40
end

local function fit(label, plain)
    if #label > labelMax() then return plain end
    return label
end

function N.TravelSpellStep(spells, target, here, class, knows)
    if type(target) ~= "table" or type(target.map) ~= "number" then return nil, "no target" end
    if type(class) ~= "string" or class == "" then return nil, "class unknown" end
    local spell
    for _, s in ipairs(type(spells) == "table" and spells or {}) do
        if type(s) == "table" and s.map == target.map and (s.class == nil or s.class == class) then
            spell = s
            break
        end
    end
    if not spell then return nil, "no spell" end
    local pos = type(here) == "table" and here.position or nil
    if type(pos) == "table" and pos.map == spell.map then return nil, "same map" end
    local known = nil
    if type(knows) == "function" then known = knows(spell.name) end
    if known == true then
        return { label = fit("Cast " .. spell.name, N.TRAVEL_PLAIN), text = true, spell = spell.name }
    end
    if known == false then
        return { label = fit("Learn " .. spell.name, N.TRAVEL_LEARN_PLAIN), text = true, spell = spell.name,
                 learn = true, detail = spell.from }
    end
    return nil, "known unknown"
end

local function ask(client, name, ...)
    local f = type(client) == "table" and client[name] or nil
    if type(f) ~= "function" then return nil end
    local ok, v = pcall(f, ...)
    if ok then return v end
    return nil
end

function N.TravelSpellStepFrom(target, client)
    local class = ask(client, "class")
    local here = { position = ask(client, "position") }
    local function knows(name)
        local id = ask(client, "spellId", name)
        if type(id) ~= "number" then return nil end
        local row = ask(client, "spell", id)
        if type(row) ~= "table" then return nil end
        if row.known == true or row.known == false then return row.known end
        return nil
    end
    return N.TravelSpellStep(N.TRAVEL_SPELLS, target, here, class, knows)
end
