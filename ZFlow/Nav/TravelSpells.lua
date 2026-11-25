local _, ns = ...
-- Z-Flow travel spells (S33): "Cast Teleport: Moonglade" when the step the
-- guide is on is in that spell's zone and the player is not, and the
-- player knows the spell; "Learn Teleport: Moonglade" with where it comes
-- from when they do not. Ported from legacy Flow 0.35.377
-- (Modules/Nav/TravelSpells.lua): the owner's young druid was never sent
-- to Moonglade for the Bear Form quest because the route only knew feet.
-- One way only: the way back is on foot, by hearthstone or by a ride
-- (Nav/Rides.lua). Pure but for N.TravelSpellStepFrom. It only says so:
-- nothing casts for the player. Not tested in game.
--
-- N.TRAVEL_SPELLS  { { name, map, class }, ... } as legacy Flow has them;
--                  map is the game's uiMapID (Moonglade 1450). Owner, lead
--                  section 618 ("Game facts, drop level"; section 611): no
--                  level and no where-from text is typed here. Where a
--                  spell not known is learned is N.TRAVEL_FROM; a level is
--                  said only once the player's own trainer window listed
--                  the spell (the saved trainer lists, N.TravelSpellLevel).
-- N.TRAVEL_FROM, N.TRAVEL_FROM_LEVEL  the learn step's detail, without and
--                  with the level the trainer window showed
-- N.TRAVEL_PLAIN, N.TRAVEL_LEARN_PLAIN  labels when a spell name would be
--                  over N.Waypoint.LABEL_MAX bytes (never cut)
--
-- N.TravelSpellStep(spells, target, here, class, knows[, levelOf]) -> step, reason
--   target  { map, x, y }: the step the guide is on
--   here    { position = { map, x, y } } (position may be absent)
--   class   the player's class token ("DRUID"), or nil
--   knows   function(name) -> true, false, or nil when the client did not say
--   levelOf function(name) -> the level a trainer window listed, or nil
--   step = { label, text = true, spell } when known, or
--          { label, text = true, spell, learn = true, detail } when not,
--          detail N.TRAVEL_FROM, or N.TRAVEL_FROM_LEVEL with levelOf's level
--   No step, and the reason, for the first of these that holds:
--     "no target"      target has no map
--     "class unknown"  class is not a string
--     "no spell"       no spell of this class reaches the target's map
--     "same map"       the player is already on that map
--     "known unknown"  knows() gave neither true nor false: never taken as known
--   A player whose position is not known still gets the step: the spell
--   works from anywhere else.
--
-- N.TravelSpellLevel(lists, name) -> the level a saved trainer list gives
--   the spell (char "learned.trainerLists", Spells/TrainerList.lua rows),
--   a whole number from 1, or nil when no list shows one
-- N.TravelSpellStepFrom(target, client[, store]) -> the same, read from
--   client.class(), client.position(), client.spellId(name) and
--   client.spell(id).known; the level from store's trainer lists (no
--   store: no level). No id or no answer: "known unknown".
ns.Nav = ns.Nav or {}
local N = ns.Nav

N.TRAVEL_SPELLS = {
    { name = "Teleport: Moonglade", map = 1450, class = "DRUID" },
}
N.TRAVEL_FROM = "from your class trainer"
N.TRAVEL_FROM_LEVEL = "from your class trainer at level %d"
N.TRAVEL_LISTS = "learned.trainerLists" -- char: Spells/TrainerModule.lua M.PATH
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

function N.TravelSpellLevel(lists, name)
    if type(lists) ~= "table" or type(name) ~= "string" then return nil end
    local best
    for _, l in pairs(lists) do
        for _, r in ipairs(type(l) == "table" and type(l.rows) == "table" and l.rows or {}) do
            local lv = type(r) == "table" and r.name == name and r.level or nil
            if type(lv) == "number" and lv >= 1 and lv % 1 == 0 and (best == nil or lv < best) then best = lv end
        end
    end
    return best
end

function N.TravelSpellStep(spells, target, here, class, knows, levelOf)
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
        local level
        if type(levelOf) == "function" then
            local ok, lv = pcall(levelOf, spell.name)
            if ok and type(lv) == "number" then level = lv end
        end
        local detail = level and N.TRAVEL_FROM_LEVEL:format(level) or N.TRAVEL_FROM
        return { label = fit("Learn " .. spell.name, N.TRAVEL_LEARN_PLAIN), text = true, spell = spell.name,
                 learn = true, detail = detail }
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

function N.TravelSpellStepFrom(target, client, store)
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
    local function levelOf(name)
        if type(store) ~= "table" or type(store.get) ~= "function" then return nil end
        local ok, lists = pcall(store.get, store, "char", N.TRAVEL_LISTS)
        if not ok then return nil end
        return N.TravelSpellLevel(lists, name)
    end
    return N.TravelSpellStep(N.TRAVEL_SPELLS, target, here, class, knows, levelOf)
end
