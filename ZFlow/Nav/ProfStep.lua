local _, ns = ...
-- Z-Flow profession step: "your profession is at its cap, go to its trainer",
-- made only from what this player's own characters have seen and saved. No
-- trainer, place or skill data is authored here. Pure: plain tables in, a
-- step or a reason out; nothing handed in is changed, nothing is remembered.
--
-- N.ProfStep(readings, npcs, tierSeen, here) -> step, or nil and a reason
--   readings  char "learned.facts.profSkill":
--             { [profession] = { skill, max, visitedAtCap } }
--   npcs      account "learned.places.npcs":
--             { [name] = { map, x, y, trains = { [profession] = true },
--                          factions = { [faction] = true }, seen } }
--   tierSeen  char "learned.facts.tierSeen":
--             { [profession] = { cap, category } }
--   here      { position = { map, x, y }, zone = { cont }, faction,
--               mapSize = function(map) -> { w, h } in yards, or nil }
--             every field may be absent: what is not known is not guessed.
--
--   step = { label = "<profession> trainer", place = { cont, map, x, y },
--            radius = N.PROF_NEAR }
--   the shape N.Guide takes as input.prof. x and y are shares 0..1 of map.
--   label is left out, never cut, when it is over N.Waypoint.LABEL_MAX bytes.
--   cont is the continent of the zone the player is in, and only for a
--   trainer on the map the player is on (see Nav/WaypointStep.lua).
--
--   A trainer on another map, when the map the player is on is known (owner
--   decision D10), is text only:
--     step = { label = "<profession> trainer" .. N.PROF_OTHER_MAP,
--              still = true, elsewhere = { map, x, y } }
--   No place, so no needle and no distance. elsewhere is where the trainer
--   was seen. The label is left out, never cut, when it is over the limit.
--   With the player's map not known, the step is the one above, no cont.
--
-- A profession gets a step when all of these hold; the reason names the
-- first that does not:
--   "no reading"   skill and max are both finite numbers, max above 0
--   "not capped"   skill has reached max
--   "visited"      visitedAtCap is not this max (the player was already
--                  taken to a trainer at this cap)
--   "unavailable"  tierSeen does not say "unavailable" at this very cap
--   "no trainer"   a saved npc trains it and has a map and x, y in 0..1
--   "faction"      such an npc was seen by a character of here.faction; an
--                  npc with no factions, or a faction not known, is no target
-- With several professions and no step, the reason is the one that got
-- furthest down that list.
--
-- Which trainer: one on the map the player is on comes first. Among those,
-- the nearest in yards when here.mapSize gives that map a size and the
-- player's x, y are known; otherwise, and for a tie, the most recently seen,
-- then the lowest name. With none on that map: the most recently seen, then
-- the lowest name.
-- Which profession: one whose trainer is on the map the player is on, then
-- the lowest name.
--
-- N.ProfStepFrom(client, store) -> the same, read from the client and the
-- three saved tables. It writes nothing; a read that fails is "not known".
ns.Nav = ns.Nav or {}
local N = ns.Nav

-- Yards from the trainer inside which the player is "here". A first guess.
N.PROF_NEAR = 10

local RANK = { ["no reading"] = 0, ["not capped"] = 1, visited = 2, unavailable = 3, ["no trainer"] = 4, faction = 5 }

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function share(v)
    return finite(v) and v >= 0 and v <= 1
end

-- Is candidate a to be taken before b: the most recently seen, then the
-- lowest name. An entry with a date comes before one with none.
local function before(a, b)
    if a.seen ~= b.seen then
        if a.seen and b.seen then return a.seen > b.seen end
        return a.seen ~= nil
    end
    return a.name < b.name
end

local function first(list)
    local best
    for _, c in ipairs(list) do
        if not best or before(c, best) then best = c end
    end
    return best
end

-- The size of a map in yards, or nil when it is not known.
local function sizeOf(here, map)
    if type(here.mapSize) ~= "function" then return nil end
    local ok, size = pcall(here.mapSize, map)
    if not ok or type(size) ~= "table" then return nil end
    if not (finite(size.w) and finite(size.h) and size.w > 0 and size.h > 0) then return nil end
    return size
end

-- The trainer to walk to, and whether it is on the map the player is on.
local function choose(list, here)
    local at = type(here.position) == "table" and here.position or nil
    local onMap = {}
    if at and at.map ~= nil then
        for _, c in ipairs(list) do
            if c.map == at.map then onMap[#onMap + 1] = c end
        end
    end
    if #onMap == 0 then return first(list), false end
    local size = finite(at.x) and finite(at.y) and sizeOf(here, at.map) or nil
    if not size then return first(onMap), true end
    local best, bestD
    for _, c in ipairs(onMap) do
        local dx, dy = (c.x - at.x) * size.w, (c.y - at.y) * size.h
        local d = dx * dx + dy * dy
        if not best or d < bestD or (d == bestD and before(c, best)) then best, bestD = c, d end
    end
    return best, true
end

-- One profession: its trainer and whether that is on the player's map, or
-- nil and the reason.
local function forProfession(prof, r, npcs, tierSeen, here)
    if r.skill < r.max then return nil, "not capped" end
    if r.visitedAtCap == r.max then return nil, "visited" end
    local said = type(tierSeen) == "table" and tierSeen[prof] or nil
    if type(said) == "table" and said.category == "unavailable" and said.cap == r.max then
        return nil, "unavailable"
    end
    local placed, usable = false, {}
    if type(npcs) == "table" then
        for name, e in pairs(npcs) do
            if type(name) == "string" and type(e) == "table" and type(e.trains) == "table" and e.trains[prof] == true
                and finite(e.map) and share(e.x) and share(e.y) then
                placed = true
                if type(here.faction) == "string" and type(e.factions) == "table" and e.factions[here.faction] == true then
                    usable[#usable + 1] = { name = name, map = e.map, x = e.x, y = e.y,
                                            seen = finite(e.seen) and e.seen or nil }
                end
            end
        end
    end
    if not placed then return nil, "no trainer" end
    if #usable == 0 then return nil, "faction" end
    return choose(usable, here)
end

-- Said after the label of a trainer on another map: a long dash (three
-- bytes, written as byte escapes to keep this file ASCII) and the words.
N.PROF_OTHER_MAP = " \226\128\148 other map"

function N.ProfStep(readings, npcs, tierSeen, here)
    if type(here) ~= "table" then here = {} end
    local names = {}
    if type(readings) == "table" then
        for prof, r in pairs(readings) do
            if type(prof) == "string" and type(r) == "table" and finite(r.skill) and finite(r.max) and r.max > 0 then
                names[#names + 1] = prof
            end
        end
    end
    table.sort(names)

    local why = "no reading"
    local prof, to, near
    for _, name in ipairs(names) do
        local c, onMap = forProfession(name, readings[name], npcs, tierSeen, here)
        if c then
            if not to or (onMap and not near) then prof, to, near = name, c, onMap end
        elseif RANK[onMap] > RANK[why] then
            why = onMap
        end
    end
    if not to then return nil, why end

    local max = N.Waypoint and N.Waypoint.LABEL_MAX or 40
    if not near and type(here.position) == "table" and here.position.map ~= nil then
        local step = { still = true, elsewhere = { map = to.map, x = to.x, y = to.y } }
        local label = prof .. " trainer" .. N.PROF_OTHER_MAP
        if #label <= max then step.label = label end
        return step
    end
    local cont
    if near and type(here.zone) == "table" then cont = here.zone.cont end
    local step = { place = { cont = cont, map = to.map, x = to.x, y = to.y }, radius = N.PROF_NEAR }
    local label = prof .. " trainer"
    if #label <= max then step.label = label end
    return step
end

-- One read of the client, or nil when it has no such read or the read fails.
local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if not ok then return nil end
    return v
end

-- One saved table, read without making it; nil when it is not there.
local function saved(store, scope, path)
    if type(store) ~= "table" or type(store.get) ~= "function" then return nil end
    local ok, v = pcall(store.get, store, scope, path)
    if not ok then return nil end
    return v
end

function N.ProfStepFrom(client, store)
    return N.ProfStep(
        saved(store, "char", "learned.facts.profSkill"),
        saved(store, "account", "learned.places.npcs"),
        saved(store, "char", "learned.facts.tierSeen"),
        {
            position = ask(client, "position"),
            zone = ask(client, "zone"),
            faction = ask(client, "faction"),
            mapSize = function(map) return ask(client, "mapSize", map) end,
        })
end
