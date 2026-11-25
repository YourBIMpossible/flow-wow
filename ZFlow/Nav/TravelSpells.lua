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
-- Owner, lead section 619: the facts in a row are researched game facts,
-- each with its source beside it; whether the player knows the spell is
-- asked of the game by the spell's number; and the row's map number is
-- taken for the spell's zone only when the client itself names that map
-- so (client.mapName). Where the spell is learned is not said: no source
-- read so far states it (legacy Flow's "your class trainer" is not one).
--
-- N.TRAVEL_SPELLS  { { name, id, class, level, map, mapName }, ... }
--                  map is the game's uiMapID, mapName what the client must
--                  name it for the row to count
-- N.TRAVEL_NEEDS   the line for a spell not known: its name and level
-- N.TRAVEL_TAUGHT, N.TRAVEL_TAUGHT_COST  that line with the trainer, and
--                  the cost, of a trainer list the player opened (lead
--                  section 621). Who teaches the spell is said from that
--                  record and nothing else: with none, no trainer is named.
-- N.TRAVEL_PLAIN, N.TRAVEL_LEARN_PLAIN  labels when a spell name would be
--                  over N.Waypoint.LABEL_MAX bytes (never cut)
--
-- Lead sections 623 and 625:
--   1. The map's name is checked in the player's language: the client's
--      name for the row's map (client.mapName) against the client's own
--      name for the row's area (client.areaName, C_Map.GetAreaInfo). With
--      no area name read, the row's English mapName is what it is checked
--      against. With the map's name not read: no step.
--   2. The trainer row is matched by the spell's name as the client says
--      it (client.spell(id).name); the row's English name only when the
--      client gives none.
--   3. At the row's level or above (client.level()) the line for a spell
--      not known is N.TRAVEL_NOT_YET, below it or with no level read
--      N.TRAVEL_NEEDS.
-- N.TravelSpellTaught(lists, name) -> { npc, cost } or nil: the trainer
--   whose saved list (char "learned.trainerLists", Spells/TrainerList.lua)
--   has a row of that name, the first by key; cost in copper, left out
--   when the window gave none. The lists hold names, not spell numbers.
-- N.TravelSpellStep(spells, target, here, class, knows, mapName[, taught[, more]]) -> step, reason
--   more    { level = the player's, mapNames = { names the map may have },
--             spellName = the client's name for the spell }, each optional
--   target  { map, x, y }: the step the guide is on
--   here    { position = { map, x, y } } (position may be absent)
--   class   the player's class token ("DRUID"), or nil
--   knows   function(name, id) -> true, false, or nil when the client did not say
--   mapName function(map) -> the client's name for that map, or nil
--   taught  function(name) -> { npc, cost } from the player's trainer lists
--   step = { label, text = true, spell } when known, or
--          { label, text = true, spell, learn = true, hint } when not: hint
--          is N.TRAVEL_NEEDS ("Teleport: Moonglade needs level 10"), left
--          out for a row with no level
--   No step, and the reason, for the first of these that holds:
--     "no target"      target has no map
--     "class unknown"  class is not a string
--     "no spell"       no spell of this class reaches the target's map
--     "map not confirmed"  the client does not name the row's map as
--                      the row does (another name, no name, no reader)
--     "same map"       the player is already on that map
--     "known unknown"  knows() gave neither true nor false: never taken as known
--   A player whose position is not known still gets the step: the spell
--   works from anywhere else.
--
-- N.TravelSpellStepFrom(target, client[, store]) -> the same, read from
--   client.class(), client.position(), client.mapName(map) and
--   client.spell(id).known with the row's id (a row with no id:
--   client.spellId(name)). No id or no answer: "known unknown".
ns.Nav = ns.Nav or {}
local N = ns.Nav

N.TRAVEL_SPELLS = {
    {
        name = "Teleport: Moonglade",
        -- Spell 18960, "Requires Druid":
        -- nether.wowhead.com/forever/tooltip/spell/18960
        id = 18960, class = "DRUID",
        -- "Requires level 10":
        -- nether.wowhead.com/forever/tooltip/spell/18960
        level = 10,
        -- "Teleports the caster to the Moonglade." (the same tooltip). That
        -- Moonglade is uiMapID 1450 has no source but legacy Flow, so the
        -- client is asked: the row counts only while it names 1450 so.
        map = 1450, mapName = "Moonglade",
        -- The zone's area number, asked of the client for the zone's name
        -- in the player's language. Source for 493: Questie's public
        -- Localization/lookups/lookupZones.lua, [493]="Moonglade"; the
        -- client's two names agreeing is what confirms it in game.
        area = 493,
    },
}
N.TRAVEL_NEEDS = "%s needs level %d"
N.TRAVEL_NOT_YET = "%s: not learned yet"
N.TRAVEL_TAUGHT = "%s. %s teaches it."
N.TRAVEL_TAUGHT_COST = "%s. %s teaches it for %s."
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

function N.TravelSpellTaught(lists, name)
    if type(lists) ~= "table" or type(name) ~= "string" then return nil end
    local keys = {}
    for key in pairs(lists) do keys[#keys + 1] = tostring(key) end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local l = lists[key]
        if type(l) == "table" and type(l.npc) == "string" and l.npc ~= "" and type(l.rows) == "table" then
            for _, r in ipairs(l.rows) do
                if type(r) == "table" and r.name == name then
                    local cost
                    if type(r.cost) == "number" and r.cost >= 0 and r.cost % 1 == 0 then cost = r.cost end
                    return { npc = l.npc, cost = cost }
                end
            end
        end
    end
    return nil
end

function N.TravelSpellStep(spells, target, here, class, knows, mapName, taught, more)
    if type(more) ~= "table" then more = {} end
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
    -- Section 619: the map number is the spell's zone only when the client
    -- names it so.
    local named
    if type(mapName) == "function" then
        local ok, v = pcall(mapName, spell.map)
        if ok then named = v end
    end
    local names = more.mapNames
    if type(names) ~= "table" then names = { spell.mapName } end
    local confirmed = false
    for _, n in ipairs(names) do
        if type(n) == "string" and n ~= "" and n == named then confirmed = true end
    end
    if not confirmed then return nil, "map not confirmed" end
    local pos = type(here) == "table" and here.position or nil
    if type(pos) == "table" and pos.map == spell.map then return nil, "same map" end
    local known = nil
    if type(knows) == "function" then known = knows(spell.name, spell.id) end
    if known == true then
        return { label = fit("Cast " .. spell.name, N.TRAVEL_PLAIN), text = true, spell = spell.name }
    end
    if known == false then
        local hint
        if type(spell.level) == "number" then
            if type(more.level) == "number" and more.level >= spell.level then
                hint = N.TRAVEL_NOT_YET:format(spell.name)
            else
                hint = N.TRAVEL_NEEDS:format(spell.name, spell.level)
            end
        end
        -- Section 621: the trainer and cost of the player's own record.
        if hint and type(taught) == "function" then
            local asName = type(more.spellName) == "string" and more.spellName ~= "" and more.spellName or spell.name
            local ok, by = pcall(taught, asName)
            if ok and type(by) == "table" and type(by.npc) == "string" and by.npc ~= "" then
                local coin
                if type(by.cost) == "number" and ns.Prices and type(ns.Prices.Coin) == "function" then
                    coin = ns.Prices.Coin(by.cost)
                end
                if type(coin) == "string" and coin ~= "" then
                    hint = N.TRAVEL_TAUGHT_COST:format(hint, by.npc, coin)
                else
                    hint = N.TRAVEL_TAUGHT:format(hint, by.npc)
                end
            end
        end
        return { label = fit("Learn " .. spell.name, N.TRAVEL_LEARN_PLAIN), text = true, spell = spell.name,
                 learn = true, hint = hint }
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
    local function knows(name, id)
        if type(id) ~= "number" then id = ask(client, "spellId", name) end
        if type(id) ~= "number" then return nil end
        local row = ask(client, "spell", id)
        if type(row) ~= "table" then return nil end
        if row.known == true or row.known == false then return row.known end
        return nil
    end
    local function mapName(map) return ask(client, "mapName", map) end
    local function taught(name)
        if type(store) ~= "table" or type(store.get) ~= "function" then return nil end
        local ok, lists = pcall(store.get, store, "char", N.TRAVEL_LISTS)
        if not ok then return nil end
        return N.TravelSpellTaught(lists, name)
    end
    -- Sections 623 and 625: the player's level, the area's name in their
    -- language (none read: the row's English name), and the client's name
    -- for the spell. The one row is asked about; a table with more rows
    -- would ask per row.
    local more = { level = ask(client, "level") }
    local row = N.TRAVEL_SPELLS[1]
    if type(row) == "table" then
        local area = type(row.area) == "number" and ask(client, "areaName", row.area) or nil
        if type(area) == "string" and area ~= "" then more.mapNames = { area } end
        if type(row.id) == "number" then
            local read = ask(client, "spell", row.id)
            if type(read) == "table" and type(read.name) == "string" and read.name ~= "" then
                more.spellName = read.name
            end
        end
    end
    return N.TravelSpellStep(N.TRAVEL_SPELLS, target, here, class, knows, mapName, taught, more)
end
