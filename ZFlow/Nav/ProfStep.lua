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
--
-- Module (lead section 279 item 2, N25): N.ProfStepDeclare(k) -> api;
--   ns.use(N.PROF_STEP) -> { Step = api.step }, the step above or nil.
-- Setting "nav.profArrow" (account, bool, default true): false gives no
-- profession step, so the arrow shows no profession needle and says no
-- trainer. Flow's nav.profArrow lands here on import (Import/FromFlow.lua).
-- The row is declared here, by the module that reads it. Look only.
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

-- Lead section 288 (N25 widened): the next profession step for any
-- character with a profession, by priority:
--   1. the trainer of a capped profession on another map, as text
--      (N.ProfStep above, owner decision D10);
--   2. the first stop of the profession route (lead section 341): the
--      nearest of the stops that have a place on the map the player is on,
--      which are
--        the trainer of a capped profession (N.ProfStep above);
--        the nearest known node of a gathering profession not capped, from
--        GatherMate2 (Nav/AddonSources.lua);
--        the nearest station this account has seen (an anvil, a forge or a
--        fire: Rotation/KeyActions.lua saves them) for the craft that
--        gives a point, when its profession works at one (N.PROF_STATION);
--      at the same distance, or with where the player is not known, in
--      that order;
--   3. the craft that gives a point, from the recipe book of this character
--      and the recipe colours its profession windows showed, as one line;
--   4. else one line per profession, by name, that says why there is
--      nothing to point at, and how the player supplies it (Lead section
--      339: before, only the first profession by name got a line).
-- No profession: nil, "no profession".
--
-- N.ProfRoute(input) -> { { kind, step, d }, ... }: every stop with a
-- place, nearest first. kind: "trainer", "node" or "station". d: the
-- distance squared (yards with a map size, else shares of the map; 0 with
-- where the player is not known). Pure; the input of N.ProfNext.
--
-- N.ProfNext(input) -> step, or nil and a reason. Pure; input fields:
--   professions  client.professions(): { [name] = true } or nil
--   readings, npcs, tierSeen, here   as N.ProfStep
--   nodes        { { x, y, map, kind, node } } on here.position.map, or nil
--   nodeState    "absent" | "off" | "failed" | "no map" | "ready"
--   book         char "learned.facts.recipeBook": { [recipe] = { profession } }
--   colours      char "learned.recipeColors":
--                { [recipe] = { [difficulty] = { lo, hi } } }
--   stations     account "learned.keyStations": { { kind, map, x, y } },
--                kind "anvil", "forge" or "fire"
-- A node step: { place = { cont, map, x, y }, radius = N.PROF_NEAR,
--   label = the node name (or "<profession> node" over the limit),
--   detail = N.PROF_NODE_DETAIL }. A craft at a station:
--   { place, radius = N.PROF_NEAR, label = the craft line, detail =
--   N.PROF_STATION_DETAIL with the kind seen there }; a craft line over the
--   limit is the detail, under the label "<profession> <kind>". No recipe
--   saves the station it needs, so the station is the profession's. No
--   vendor's wares are saved, so no step points at a reagent vendor.
--   A craft with no station, or a why step:
--   { still = true, lines = { text, ... }, label = the text when there is
--   one line within the limit }.
--
-- The names client.professions gives are kept only when they are on
-- N.PROF_NAMES (the real client also gives weapon and other skill lines).
-- Needs game test: the English names. A client in another language is known
-- only through the readings its profession windows saved.

-- Gathering professions and the GatherMate2 kind of their nodes; false: a
-- gathering profession with no node kind.
N.PROF_GATHER = { Mining = "Mining", Herbalism = "Herb Gathering", Fishing = "Fishing", Skinning = false }
N.PROF_NAMES = {}
for _, name in ipairs({ "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Leatherworking",
    "Tailoring", "Jewelcrafting", "Inscription", "Cooking", "First Aid",
    "Mining", "Herbalism", "Skinning", "Fishing" }) do
    N.PROF_NAMES[name] = true
end

N.PROF_NODE_DETAIL = "nearest known %s node"
-- The station a profession's crafts are made at. A first guess, by
-- profession: the recipe book saves no station for a recipe. A profession
-- not named here has none, and its craft stays a line of text.
N.PROF_STATION = { Blacksmithing = "anvil", Cooking = "fire" }
-- The saved kinds that serve a station (a forge stands by an anvil: a
-- first guess, as original Flow had it).
N.PROF_STATION_SPOTS = {
    anvil = { anvil = true, forge = true },
    forge = { forge = true },
    fire = { fire = true },
}
N.PROF_STATION_DETAIL = "nearest known %s"
-- Where Rotation/KeyActions.lua saves the stations (its KA.STATIONS_PATH;
-- that file loads after this one).
N.PROF_STATIONS_PATH = "learned.keyStations"
N.PROF_CRAFT_SURE = "Make %s: a sure %s point"
N.PROF_CRAFT_MAYBE = "Make %s: may give a %s point"
N.PROF_WHY_READ = "Open your %s window once to read your skill"
N.PROF_WHY_TRAINER = "%s capped at %d: open a %s trainer once to mark it"
N.PROF_WHY_TRAIN = "%s capped at %d: train the next rank when you can"
N.PROF_WHY_GM_ABSENT = "No known %s node here: GatherMate2 gives nodes"
N.PROF_WHY_GM_OFF = "No known %s node here: turn on Read GatherMate2 nodes"
N.PROF_WHY_NODE = "No known %s node on this map"
N.PROF_WHY_RECIPES = "Open your %s window once to see what gives a point"
N.PROF_WHY_NO_POINT = "No known %s recipe gives a point at %d"
N.PROF_WHY_NOTHING = "Nothing known to point at for %s"

-- Recipe colours that give a point: sure, or may.
local GIVES = { optimal = "sure", medium = "maybe", easy = "maybe" }

local function reading(readings, prof)
    local r = type(readings) == "table" and readings[prof] or nil
    if type(r) == "table" and finite(r.skill) and finite(r.max) and r.max > 0 then return r end
    return nil
end

local function capped(r) return r ~= nil and r.skill >= r.max end

-- lines: one text, or a list of texts (one per profession).
local function textStep(lines)
    if type(lines) == "string" then lines = { lines } end
    local step = { still = true, lines = lines }
    if #lines == 1 and #lines[1] <= (N.Waypoint and N.Waypoint.LABEL_MAX or 40) then step.label = lines[1] end
    return step
end

-- Squared distance from the player to n: yards when the map size is
-- known, else shares; 0 when where the player is is not known.
local function apart(n, pos, size)
    if not (pos and share(pos.x) and share(pos.y)) then return 0 end
    local dx, dy = n.x - pos.x, n.y - pos.y
    if size then dx, dy = dx * size.w, dy * size.h end
    return dx * dx + dy * dy
end

-- The craft of prof that gives a point at skill: its name and "sure" or
-- "maybe"; else nil, nil and whether any recipe of prof has colours seen.
local function craftFor(prof, skill, book, colours)
    if type(book) ~= "table" or type(colours) ~= "table" then return nil, nil, false end
    local sure, maybe, seen = {}, {}, false
    for name, rec in pairs(book) do
        local spans = colours[name]
        if type(name) == "string" and type(rec) == "table" and rec.profession == prof and type(spans) == "table" then
            seen = true
            for difficulty, span in pairs(spans) do
                local kind = GIVES[difficulty]
                if kind and type(span) == "table" and finite(span.lo) and finite(span.hi)
                    and span.lo <= skill and skill <= span.hi then
                    if kind == "sure" then sure[#sure + 1] = name else maybe[#maybe + 1] = name end
                end
            end
        end
    end
    table.sort(sure)
    table.sort(maybe)
    if sure[1] then return sure[1], "sure", true end
    if maybe[1] then return maybe[1], "maybe", true end
    return nil, nil, seen
end

local function nodeWhy(prof, state)
    if state == "absent" then return N.PROF_WHY_GM_ABSENT:format(prof) end
    if state == "off" then return N.PROF_WHY_GM_OFF:format(prof) end
    return N.PROF_WHY_NODE:format(prof)
end

local function nodeStep(input, names, here)
    if input.nodeState ~= "ready" or type(input.nodes) ~= "table" then return nil end
    local pos = type(here.position) == "table" and here.position or nil
    local size = pos and sizeOf(here, pos.map) or nil
    local best, bestProf, bestD
    for _, prof in ipairs(names) do
        local kind = N.PROF_GATHER[prof]
        if kind and not capped(reading(input.readings, prof)) then
            for _, n in ipairs(input.nodes) do
                if type(n) == "table" and n.kind == kind and share(n.x) and share(n.y) then
                    local d = apart(n, pos, size)
                    if not best or d < bestD then best, bestProf, bestD = n, prof, d end
                end
            end
        end
    end
    if not best then return nil end
    local cont = type(here.zone) == "table" and here.zone.cont or nil
    local map = best.map
    if map == nil and pos then map = pos.map end
    local step = { place = { cont = cont, map = map, x = best.x, y = best.y },
                   radius = N.PROF_NEAR, detail = N.PROF_NODE_DETAIL:format(bestProf) }
    local max = N.Waypoint and N.Waypoint.LABEL_MAX or 40
    local label = type(best.node) == "string" and #best.node <= max and best.node or (bestProf .. " node")
    if #label <= max then step.label = label end
    return step
end

-- The craft that gives a point, at the nearest station this account has
-- seen on the map the player is on; nil when no profession with such a
-- craft works at a station seen here.
local function stationStep(input, names, here)
    local pos = type(here.position) == "table" and here.position or nil
    if type(input.stations) ~= "table" or not pos or pos.map == nil then return nil end
    local size = sizeOf(here, pos.map)
    local best, bestD, bestProf, bestCraft, bestGives
    for _, prof in ipairs(names) do
        local need = N.PROF_STATION[prof]
        local serves = need and N.PROF_STATION_SPOTS[need] or nil
        local r = reading(input.readings, prof)
        if serves and N.PROF_GATHER[prof] == nil and r and not capped(r) then
            local craft, gives = craftFor(prof, r.skill, input.book, input.colours)
            if craft then
                for _, s in ipairs(input.stations) do
                    if type(s) == "table" and serves[s.kind] == true and s.map == pos.map
                        and share(s.x) and share(s.y) then
                        local d = apart(s, pos, size)
                        if not best or d < bestD then
                            best, bestD, bestProf, bestCraft, bestGives = s, d, prof, craft, gives
                        end
                    end
                end
            end
        end
    end
    if not best then return nil end
    local cont = type(here.zone) == "table" and here.zone.cont or nil
    local step = { place = { cont = cont, map = pos.map, x = best.x, y = best.y }, radius = N.PROF_NEAR }
    local words = bestGives == "sure" and N.PROF_CRAFT_SURE or N.PROF_CRAFT_MAYBE
    local line = words:format(bestCraft, bestProf)
    local max = N.Waypoint and N.Waypoint.LABEL_MAX or 40
    if #line <= max then
        step.label, step.detail = line, N.PROF_STATION_DETAIL:format(best.kind)
    else
        step.detail = line
        local label = bestProf .. " " .. best.kind
        if #label <= max then step.label = label end
    end
    return step
end

-- The professions of the input, by name.
local function namesOf(input)
    local names, has = {}, {}
    local function add(name)
        if type(name) == "string" and not has[name] then
            has[name] = true
            names[#names + 1] = name
        end
    end
    if type(input.professions) == "table" then
        for name in pairs(input.professions) do
            if N.PROF_NAMES[name] then add(name) end
        end
    end
    if type(input.readings) == "table" then
        for name in pairs(input.readings) do
            if reading(input.readings, name) then add(name) end
        end
    end
    table.sort(names)
    return names
end

-- The stops with a place, nearest first; trainer is N.ProfStep's answer.
local function route(input, names, here, trainer)
    local pos = type(here.position) == "table" and here.position or nil
    local size = pos and sizeOf(here, pos.map) or nil
    local stops = {}
    local function add(kind, step)
        if type(step) == "table" and type(step.place) == "table" then
            stops[#stops + 1] = { kind = kind, step = step, d = apart(step.place, pos, size), nth = #stops + 1 }
        end
    end
    add("trainer", trainer)
    add("node", nodeStep(input, names, here))
    add("station", stationStep(input, names, here))
    table.sort(stops, function(a, b)
        if a.d ~= b.d then return a.d < b.d end
        return a.nth < b.nth
    end)
    for _, stop in ipairs(stops) do stop.nth = nil end
    return stops
end

function N.ProfRoute(input)
    if type(input) ~= "table" then input = {} end
    local here = type(input.here) == "table" and input.here or {}
    local names = namesOf(input)
    if #names == 0 then return {} end
    local trainer = N.ProfStep(input.readings, input.npcs, input.tierSeen, here)
    return route(input, names, here, trainer)
end

local textNext

function N.ProfNext(input)
    if type(input) ~= "table" then input = {} end
    local here = type(input.here) == "table" and input.here or {}
    local names = namesOf(input)
    if #names == 0 then return nil, "no profession" end

    local trainer = N.ProfStep(input.readings, input.npcs, input.tierSeen, here)
    if trainer and type(trainer.place) ~= "table" then return trainer end

    local stops = route(input, names, here, trainer)
    if stops[1] then return stops[1].step end
    return textNext(input, names, here)
end

-- Steps 3 and 4 of N.ProfNext: nothing has a place.
textNext = function(input, names, here)
    -- The craft that gives a point: sure before maybe, then by profession.
    local pick, pickKind, pickProf
    for _, prof in ipairs(names) do
        local r = reading(input.readings, prof)
        if N.PROF_GATHER[prof] == nil and r and not capped(r) then
            local name, kind = craftFor(prof, r.skill, input.book, input.colours)
            if name and (not pick or (kind == "sure" and pickKind ~= "sure")) then
                pick, pickKind, pickProf = name, kind, prof
            end
        end
    end
    if pick then
        local words = pickKind == "sure" and N.PROF_CRAFT_SURE or N.PROF_CRAFT_MAYBE
        return textStep(words:format(pick, pickProf))
    end

    -- Why, one line for each profession by name.
    local function whyFor(prof)
        local r = reading(input.readings, prof)
        if capped(r) then
            local _, why = N.ProfStep({ [prof] = r }, input.npcs, input.tierSeen, here)
            if why == "visited" or why == "unavailable" then
                return N.PROF_WHY_TRAIN:format(prof, r.max)
            end
            return N.PROF_WHY_TRAINER:format(prof, r.max, prof)
        elseif N.PROF_GATHER[prof] then
            return nodeWhy(prof, input.nodeState)
        elseif N.PROF_GATHER[prof] == false then
            return N.PROF_WHY_NOTHING:format(prof)
        elseif not r then
            return N.PROF_WHY_READ:format(prof)
        end
        local _, _, seen = craftFor(prof, r.skill, input.book, input.colours)
        if seen then return N.PROF_WHY_NO_POINT:format(prof, r.skill) end
        return N.PROF_WHY_RECIPES:format(prof)
    end
    local lines = {}
    for _, prof in ipairs(names) do lines[#lines + 1] = whyFor(prof) end
    return textStep(lines)
end

-- N.ProfNextFrom(client, store, nodeSource) -> N.ProfNext read from the
-- client, the saved tables and the GatherMate2 source module (or nil).
-- It writes nothing; a read that fails is "not known".
function N.ProfNextFrom(client, store, nodeSource)
    local nodes, state
    if type(nodeSource) == "table" then
        if type(nodeSource.State) == "function" then
            local ok, s = pcall(nodeSource.State)
            if ok then state = s end
        end
        if type(nodeSource.Nodes) == "function" then
            local ok, n = pcall(nodeSource.Nodes)
            if ok then nodes = n end
        end
    end
    return N.ProfNext({
        professions = ask(client, "professions"),
        readings = saved(store, "char", "learned.facts.profSkill"),
        npcs = saved(store, "account", "learned.places.npcs"),
        tierSeen = saved(store, "char", "learned.facts.tierSeen"),
        here = {
            position = ask(client, "position"),
            zone = ask(client, "zone"),
            faction = ask(client, "faction"),
            mapSize = function(map) return ask(client, "mapSize", map) end,
        },
        nodes = nodes,
        nodeState = state or "absent",
        book = saved(store, "char", "learned.facts.recipeBook"),
        colours = saved(store, "char", "learned.recipeColors"),
        stations = saved(store, "account", N.PROF_STATIONS_PATH),
    })
end

N.PROF_STEP = "profStep"
N.PROF_SETTING = "nav.profArrow"

function N.ProfStepDeclare(k)
    local api = {}
    local ctx

    -- Off only when the setting says false; a read that fails is not off.
    local function off()
        if not ctx or type(ctx.settings) ~= "table" or type(ctx.settings.get) ~= "function" then return false end
        local ok, v = pcall(ctx.settings.get, ctx.settings, N.PROF_SETTING)
        return ok and v == false
    end

    function api.step()
        if not ctx or off() then return nil end
        -- Lead section 382 (Nav/ProfFeed.lua): the Professions tick off
        -- gives no profession step; with the planner there, its one step
        -- picked across the professions comes first.
        local feed
        if type(ctx.use) == "function" then
            local okFeed, f = pcall(ctx.use, N.ProfFeed and N.ProfFeed.NAME or "profFeed")
            if okFeed and type(f) == "table" then feed = f end
        end
        if feed and type(feed.Off) == "function" then
            local okOff, isOff = pcall(feed.Off)
            if okOff and isOff then return nil end
        end
        if feed and type(feed.Step) == "function" then
            local okStep, picked = pcall(feed.Step)
            if okStep and type(picked) == "table" then return picked end
        end
        local source
        if type(ctx.use) == "function" then
            local ok, s = pcall(ctx.use, "gatherMateSource")
            if ok then source = s end
        end
        return N.ProfNextFrom(ctx.client, ctx.store, source)
    end

    k:Setting({ key = N.PROF_SETTING, scope = "account", type = "bool", default = true,
        label = "Profession trainer arrow", group = "travel.arrow",
        synonyms = { "profession", "trainer", "arrow", "needle", "skill cap" } })

    k:Module({
        name = N.PROF_STEP,
        needs = { "client", "store", "settings" },
        provides = { Step = api.step },
        start = function(c)
            ctx = c
        end,
    })
    return api
end

-- The addon's own: declared when this file loads.
ns.profStep = N.ProfStepDeclare(ns)
