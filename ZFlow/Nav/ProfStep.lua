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

-- Lead section 418 item 6: the profession each older step covers, kept
-- beside the step (the step's own shape is unchanged), for N.ProfCovers.
local COVERS = setmetatable({}, { __mode = "k" })
local function covers(step, prof)
    if type(step) == "table" then COVERS[step] = prof end
    return step
end

-- N.ProfCovers(step) -> the one profession an older step (N.ProfStep,
-- N.ProfNext) is about, or nil (a why step names every profession).
function N.ProfCovers(step)
    if type(step) ~= "table" then return nil end
    return COVERS[step]
end

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
        return covers(step, prof)
    end
    local cont
    if near and type(here.zone) == "table" then cont = here.zone.cont end
    local step = { place = { cont = cont, map = to.map, x = to.x, y = to.y }, radius = N.PROF_NEAR }
    local label = prof .. " trainer"
    if #label <= max then step.label = label end
    return covers(step, prof)
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
-- P-PROF slice 4 (Lazy), as Flow's SkillPlan UseBank: the craft's mats are
-- short in the bags but there with what the bank held at the last visit.
N.PROF_BANK_NOTE = "Its mats are in your bank: visit the banker first."
N.PROF_WHY_READ = "Open your %s window once to read your skill"
N.PROF_WHY_TRAINER = "%s capped at %d: open a %s trainer once to mark it"
N.PROF_WHY_TRAIN = "%s capped at %d: train the next rank when you can"
N.PROF_WHY_GM_ABSENT = "No known %s node here: GatherMate2 gives nodes"
N.PROF_WHY_GM_OFF = "No known %s node here: turn on Read GatherMate2 nodes"
N.PROF_WHY_NODE = "No known %s node on this map"
N.PROF_WHY_RECIPES = "Open your %s window once to see what gives a point"
N.PROF_WHY_NO_POINT = "No known %s recipe gives a point at %d"
-- Lead section 421 point 2: a recipe last seen giving a point below the
-- skill, and never seen grey, is still the step, not confirmed: the craft
-- on one line, then when it was last seen giving points (two lines, never
-- cut).
N.PROF_CRAFT_STALE = "Make %s"
N.PROF_STALE_CHECK = "last seen giving points at %d; open your %s window to check"
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

-- Seen grey at or below skill: a colour only goes down, so it gives no
-- point now.
local function seenGrey(spans, skill)
    local s = spans.trivial
    return type(s) == "table" and finite(s.lo) and s.lo <= skill
end

-- The craft of prof that gives a point at skill: its name and "sure" or
-- "maybe"; else (lead section 421 point 2) one last seen giving a point
-- below skill and never seen grey: its name, "stale", and the highest
-- skill it was seen giving a point at; else nil, nil. The third value:
-- whether any recipe of prof has colours seen; the fifth: whether every
-- such recipe was seen grey.
local function craftFor(prof, skill, book, colours)
    if type(book) ~= "table" or type(colours) ~= "table" then return nil, nil, false, nil, false end
    local sure, maybe, stale, last, seen, allGrey = {}, {}, {}, {}, false, true
    for name, rec in pairs(book) do
        local spans = colours[name]
        if type(name) == "string" and type(rec) == "table" and rec.profession == prof and type(spans) == "table" then
            seen = true
            local grey = seenGrey(spans, skill)
            if not grey then allGrey = false end
            for difficulty, span in pairs(spans) do
                local kind = GIVES[difficulty]
                if kind and type(span) == "table" and finite(span.lo) and finite(span.hi) then
                    if span.lo <= skill and skill <= span.hi then
                        if kind == "sure" then sure[#sure + 1] = name else maybe[#maybe + 1] = name end
                    elseif not grey and span.hi < skill and (last[name] == nil or span.hi > last[name]) then
                        if last[name] == nil then stale[#stale + 1] = name end
                        last[name] = span.hi
                    end
                end
            end
        end
    end
    table.sort(sure)
    table.sort(maybe)
    table.sort(stale)
    if sure[1] then return sure[1], "sure", true end
    if maybe[1] then return maybe[1], "maybe", true end
    if stale[1] then return stale[1], "stale", true, last[stale[1]] end
    return nil, nil, seen, nil, seen and allGrey
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
    return covers(step, bestProf)
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
            if craft and gives ~= "stale" then
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
    return covers(step, bestProf)
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

-- Slice 4: true when one craft of rec is short in bags and not with bank
-- added. bags, bank: { [item key] = count } (Items/HaveTip.lua); nil (not
-- read, or the bank never seen) is never short.
function N.ProfBankShort(rec, bags, bank)
    if type(rec) ~= "table" or type(rec.mats) ~= "table" or type(bags) ~= "table" or type(bank) ~= "table" then
        return false
    end
    local short = false
    for item, need in pairs(rec.mats) do
        local key = ns.Items.Key(item)
        if key == nil or not finite(need) then return false end
        local inBags, inBank = bags[key], bank[key]
        if not finite(inBags) then inBags = 0 end
        if not finite(inBank) then inBank = 0 end
        if inBags + inBank < need then return false end
        if inBags < need then short = true end
    end
    return short
end

-- Steps 3 and 4 of N.ProfNext: nothing has a place.
textNext = function(input, names, here)
    -- The craft that gives a point: sure before maybe before one last seen
    -- giving a point lower (lead section 421), then by profession.
    local ORDER = { sure = 1, maybe = 2, stale = 3 }
    local pick, pickKind, pickProf, pickLast
    for _, prof in ipairs(names) do
        local r = reading(input.readings, prof)
        if N.PROF_GATHER[prof] == nil and r and not capped(r) then
            local name, kind, _, last = craftFor(prof, r.skill, input.book, input.colours)
            if name and (not pick or ORDER[kind] < ORDER[pickKind]) then
                pick, pickKind, pickProf, pickLast = name, kind, prof, last
            end
        end
    end
    if pick then
        local lines
        if pickKind == "stale" then
            lines = { N.PROF_CRAFT_STALE:format(pick), N.PROF_STALE_CHECK:format(pickLast, pickProf) }
        else
            local words = pickKind == "sure" and N.PROF_CRAFT_SURE or N.PROF_CRAFT_MAYBE
            lines = { words:format(pick, pickProf) }
        end
        if N.ProfBankShort(input.book[pick], input.bags, input.bank) then
            lines[#lines + 1] = N.PROF_BANK_NOTE
        end
        local step = covers(textStep(lines), pickProf)
        -- Lead section 421 point 1: this names a craft the player can do now.
        step.doable = true
        return step
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
        -- Lead section 421 point 2: only when every known recipe was seen grey.
        local _, _, _, _, allGrey = craftFor(prof, r.skill, input.book, input.colours)
        if allGrey then return N.PROF_WHY_NO_POINT:format(prof, r.skill) end
        return N.PROF_WHY_RECIPES:format(prof)
    end
    local lines = {}
    for _, prof in ipairs(names) do lines[#lines + 1] = whyFor(prof) end
    return textStep(lines)
end

-- N.ProfNextFrom(client, store, nodeSource) -> N.ProfNext read from the
-- client, the saved tables and the GatherMate2 source module (or nil).
-- It writes nothing; a read that fails is "not known".
-- Slice 4: the bag and bank counts by item key, or nil when not read.
local function bagCounts(client)
    local stacks = ask(client, "bagItems")
    if type(stacks) ~= "table" or type(ns.HaveTip) ~= "table" then return nil end
    return ns.HaveTip.Counts(stacks, ns.Items.Key)
end

local function bankCounts(store)
    local b = saved(store, "char", "learned.bankCounts")
    if type(b) ~= "table" or type(b.counts) ~= "table" then return nil end
    return b.counts
end

-- Lead section 414: the readings at the skill the game has now
-- (Items/ProfPlan.lua's P.Readings), and the stations with the places a
-- craft succeeded at (Items/CraftSpots.lua). Both load after this file.
local function readingsNow(client, store)
    local got = saved(store, "char", "learned.facts.profSkill")
    local P = ns.ProfPlan
    if type(P) == "table" and type(P.Readings) == "function" then return P.Readings(client, got) end
    return got
end

local function stationsSeen(store)
    local CS = ns.CraftSpots
    if type(CS) == "table" and type(CS.All) == "function" then return CS.All(store) end
    return saved(store, "account", N.PROF_STATIONS_PATH)
end

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
        readings = readingsNow(client, store),
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
        stations = stationsSeen(store),
        bags = bagCounts(client),
        bank = bankCounts(store),
    })
end

-- Profession place (N.ProfPlace): the place a profession step in words can be
-- pointed at. A step of the profession plan (Items/ProfPlan.lua) carries a
-- target only where the plan itself saw one; the rest are words, and the
-- profession arrow has nothing to point at. This part finds the nearest
-- KNOWN place for such a step, as the predecessor did (its
-- Modules/Crafting/SkillPlan.lua, Modules/Nav/Services.lua and Places.lua).
-- LOOK ONLY: nothing is targeted, bought, trained or moved.
--
-- Unknown stays unknown: no place is shipped, authored or guessed. A place
-- is one this account saved, or one the player's own Questie gives at run
-- time (asked through the client, never copied). With neither the answer is
-- nil and the step stays in words.
--
-- Where from, in this order (PP.Of):
--   1. saved, on the map the player is on, the nearest;
--   2. Questie, on that map, the nearest;
--   3. saved, on another map of the player's continent, the nearest by the
--      far read (not known: after every one that is known);
--   4. Questie, the same.
-- A map counts as on the player's continent only when the client names the
-- same continent for both. A tie goes to the lower name, then map, then x, y.
--
-- By step kind (PP.KIND):
--   learn_recipe, train_tier   a trainer of the profession. Saved: account
--       "learned.places.npcs" entries with trains[profession]
--       (Nav/ProfSeen.lua, or imported). Questie: an NPC whose sub-name is
--       "<Profession> Trainer" (PP.TRAINER_TITLE, the predecessor's rule)
--       for a profession of N.PROF_NAMES. Only for a step that names no
--       trainer: one that names its trainer points at that one or at none.
--   take_bank                  a banker; buy_auction: an auctioneer. Saved:
--       char "learned.places.services" (Nav/ServiceSeen.lua) and the
--       account npcs whose roles say bank or auction (imported entries).
--       Questie: an NPC whose npcFlags hold the banker or auctioneer bit:
--       Questie's own list (db.npcFlags.BANKER, .AUCTIONEER) when it has
--       one, else PP.FLAG (256 and 4096, the first game's, as the
--       predecessor's Services.lua).
--   gather_skill               a node of that profession on the map the
--       player is on: the nearest the player gathered there (Nav/Nodes.lua);
--       else the nearest place Questie gives for an object the player has
--       gathered before, on any map (its saved object id): a node this
--       player can gather, never one picked by its name.
--   craft, make_part, go_station   an anvil or a forge (PP.STATION_FAR),
--       only when none is seen on this map (that one is the plan's own):
--       the nearest seen on the continent (Items/CraftSpots.lua); else a
--       Blacksmithing trainer, who works by both (the predecessor's rule,
--       and what the plan's own "look for" line says). A fire is never
--       looked for: the player can light one.
--   visit_weapon_master        a weapon master (asked for by
--       Nav/WeaponMasterStep.lua, no step of the plan). Saved: the account
--       npcs whose roles say weaponMaster (Nav/WeaponMasterSeen.lua).
--       Questie: an NPC whose sub-name is exactly PP.WEAPON_MASTER. Which
--       weapons one teaches is not read: not known until the player visits.
--       step.only = { [name] = true }: only weapon masters of those names;
--       step.skip = { [name] = true }: none of those names (saved ones and
--       Questie's alike). The names are the asker's (Nav/WeaponMasterStep.lua
--       with Nav/WeaponMasterNames.lua, lead section 602).
--   visit_named                the NPC whose name is step.name, from Questie
--       only: on this map, else on this continent. Found only for a name
--       given to PP.Want before the pass (Nav/RidingNames.lua's riding
--       trainers, lead section 602; asked for by Nav/RidingStep.lua).
-- Any other kind: nil. The plan gives a vendor or node step its own place.
-- An npc the player's faction cannot use is left out: a saved one by its
-- factions (none saved, or the faction not known: it stays in), Questie's
-- by friendlyToFaction ("A", "H", "AH").
--
--   PP.Pick(step, prof, known) -> { name, map, x, y }, from or nil   pure
--     The same answer as PP.Of with the name when it has one (an npc's),
--     and for an npc where it is from: PP.SAVED or PP.QUESTIE.
--   PP.Of(step, prof, known) -> { map, x, y } or nil            pure
--     known = { here = { map, x, y, faction, size }, npcs, services,
--               stations = { { kind, map, x, y } },
--               nodes = { { x, y, prof } } on here.map, nearest first,
--               questie = function() -> PP.Scan's answer or nil,
--               spots = function(prof) -> { { map, x, y } } or nil,
--               contOf = function(map) -> continent or nil,
--               far = function(place) -> a number, less is nearer, or nil }
--   PP.Scan(db, zones) -> found, n                               pure
--     One pass over every NPC Questie knows (db.NPCPointers), two reads
--     each (subName, npcFlags). found = { trainer = { [profession] =
--     { { name, map, x, y, side } } }, banker = { ... }, auction = { ... } },
--     and weaponMaster = { ... } once one is met (the sub-name read, no
--     read more), at most PP.SPOTS places an NPC; n = how many places in
--     all. And named = { [name] = { ... } } once an NPC with a name given
--     to PP.Want is met: for that, the name of an NPC that has any npcFlags
--     is read in the same pass (one read more for such an NPC not kept
--     for another reason; none for an NPC with no flags, which is no
--     trainer or vendor; none at all while no name is wanted).
--     And vendor, repair, flight, innkeeper = { ... } once an NPC with
--     that npcFlags bit is met (PP.SERVICE; parity rows A2-10 and A1-41):
--     Questie's own list first (db.npcFlags.VENDOR, .REPAIR,
--     .FLIGHT_MASTER, .INNKEEPER), else PP.FLAG (4, 16384, 8, 128, the
--     first game's, as the predecessor's S.CLASSIC_FLAGS). The same
--     npcFlags read; an NPC in two lists has one place table in both.
--   PP.Service(kind, known) -> { name, map, x, y } or nil          pure
--     Questie's nearest NPC of a service kind (PP.SERVICES: those four,
--     banker and auction) the player's faction can use: on here.map, else
--     on another map of the player's continent. known as for PP.Of
--     (here, questie, contOf, far). For N.Nearest
--     (Nav/ServiceNearest.lua), asked through the feed's Service.
--   PP.Want(name): asks the pass to keep the places of the NPC of that
--     name (PP.NAMES). Called when a names file loads, before any pass.
--   PP.ScanStart(db) -> pass or nil; PP.ScanStep(pass, zones, count) ->
--     done: the same pass a part at a time, count NPCs a call. pass.found
--     and pass.n are the answer once done.
--   PP.Questie() -> reader: the cost control, kept by its one owner
--     (Nav/ProfFeed.lua) for the session.
--     reader.places(client) -> found or nil. It reads nothing itself: it
--       gives the kept answer, or says the answer is wanted.
--     reader.work(client) -> is there more to do? The scan, a part a call
--       (lead section 564: no hitch; the predecessor went through 300
--       NPCs a frame too): the first call of a pass lists the NPCs, each
--       later one goes through PP.STEP of them. Its owner calls it once a
--       frame and never in combat. Nothing is done before places() was
--       asked. One pass, and its answer is kept. A pass with no place
--       (Questie still loading) is done again no sooner than PP.RETRY
--       seconds later and PP.TRIES times in all, then kept as it is. A
--       client with no time (now() 0) has nothing to wait by: its tries
--       come in a row and still end.
--     reader.waiting(client) -> true while an answer asked for is still on
--       its way (a pass runs, or one is due and Questie has its NPCs).
--     reader.ids(client, prof, read) -> read()'s list, kept PP.RETRY
--       seconds, so the saved nodes are not gone through on every update.
--     reader.spots(client, ids, map) -> { { map, x, y } }: the places of
--       those objects on that map; one read an object, kept, with the same
--       bounds while Questie does not answer.
--   PP.From(client, store, use, kind, reads) -> known
--     reads only what kind (a value of PP.KIND) needs. reads = { contOf,
--     far, questie = the reader } are the caller's. It writes nothing; a
--     read that fails is "not known".
-- Not tested in game: Questie's field names (subName, npcFlags, spawns,
-- friendlyToFaction, QueryNPCSingle, QueryObjectSingle, NPCPointers) are the
-- ones Spells/ClassQuestList.lua and the predecessor read.

local PP = {}
N.ProfPlace = PP

PP.KIND = {
    learn_recipe = "trainer", train_tier = "trainer",
    take_bank = "banker", buy_auction = "auction",
    gather_skill = "node",
    craft = "station", make_part = "station", go_station = "station",
    visit_weapon_master = "weaponMaster",
    visit_named = "named",
}
-- The NPC names the pass over Questie keeps places for (PP.Want).
PP.NAMES = {}
-- The npc role of a saved entry, by place kind.
PP.ROLE = { banker = "bank", auction = "auction", weaponMaster = "weaponMaster" }
-- Questie's sub-name of a weapon master, the whole of it.
PP.WEAPON_MASTER = "Weapon Master"
-- Where an npc's place is from (PP.Pick).
PP.SAVED, PP.QUESTIE = "saved", "questie"
PP.STATION_FAR = { anvil = true, forge = true }
PP.STATION_PROF = "Blacksmithing"
PP.NPCS = "learned.places.npcs"
PP.NODES_PATH = "learned.nodes"
PP.NODE_MODULE = "nodes"
-- How many of the nearest gathered nodes are asked for.
PP.NODES = 50
PP.TRAINER_TITLE = "^(.-) Trainer$"
-- The first game's npcFlags bits, as the predecessor's Services.lua
-- (S.CLASSIC_FLAGS), and their names in Questie's own list.
PP.FLAG = { banker = 256, auction = 4096, vendor = 4, repair = 16384, flight = 8, innkeeper = 128 }
PP.FLAG_NAME = { banker = "BANKER", auction = "AUCTIONEER", vendor = "VENDOR", repair = "REPAIR",
                 flight = "FLIGHT_MASTER", innkeeper = "INNKEEPER" }
-- The kinds kept by flag whose list is made once one is met (banker and
-- auction have theirs from the start), and every kind PP.Service answers:
-- the kinds of N.SERVICE_KINDS that are an NPC.
PP.SERVICE = { "vendor", "repair", "flight", "innkeeper" }
PP.SERVICES = { vendor = true, repair = true, flight = true, innkeeper = true, banker = true, auction = true }
PP.TRIES, PP.RETRY = 6, 10
-- NPCs gone through in one call of reader.work (one frame).
PP.STEP = 300
-- Places kept for one NPC, and for one object on one map.
PP.SPOTS, PP.NODE_SPOTS = 8, 400

local function text(v)
    if type(v) == "string" and v ~= "" then return v end
    return nil
end

local function placed(p)
    return type(p) == "table" and p.map ~= nil and share(p.x) and share(p.y)
end

function PP.Want(name)
    if text(name) then PP.NAMES[name] = true end
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok then return nil end
    return v
end

local function mayUse(e, faction)
    if faction == nil or type(e.factions) ~= "table" or next(e.factions) == nil then return true end
    return e.factions[faction] == true
end

-- Questie's friendlyToFaction against the player's faction.
local function friendly(side, faction)
    local letter
    if faction == "Alliance" then letter = "A" elseif faction == "Horde" then letter = "H" end
    if letter and type(side) == "string" and side ~= "" and not side:find(letter, 1, true) then return false end
    return true
end

-- Is candidate a to be taken before b at the same distance?
local function lower(a, b)
    local an, bn = tostring(a.name), tostring(b.name)
    if an ~= bn then return an < bn end
    local am, bm = tostring(a.map), tostring(b.map)
    if am ~= bm then return am < bm end
    if a.x ~= b.x then return a.x < b.x end
    return a.y < b.y
end

-- The nearest of list on the map the player is on, or nil.
local function onMap(list, known)
    local here = known.here
    local w, h = 1, 1
    if type(here.size) == "table" and finite(here.size.w) and finite(here.size.h) then
        w, h = here.size.w, here.size.h
    end
    local best, bestD
    for _, c in ipairs(list) do
        if c.map == here.map then
            local dx, dy = (c.x - here.x) * w, (c.y - here.y) * h
            local d = dx * dx + dy * dy
            if best == nil or d < bestD or (d == bestD and lower(c, best)) then best, bestD = c, d end
        end
    end
    return best
end

-- same(map) -> is map known to be on the player's continent? Each map is
-- asked for once.
local function sameOf(known)
    local mine = call(known.contOf, known.here.map)
    local seen = {}
    return function(map)
        if mine == nil then return false end
        local v = seen[map]
        if v == nil then
            v = call(known.contOf, map) == mine
            seen[map] = v
        end
        return v
    end
end

-- The nearest of list on another map of the player's continent, or nil.
local function onContinent(list, known, same)
    local best, bestD
    for _, c in ipairs(list) do
        if c.map ~= known.here.map and same(c.map) then
            local d = call(known.far, c)
            if not finite(d) then d = math.huge end
            if best == nil or d < bestD or (d == bestD and lower(c, best)) then best, bestD = c, d end
        end
    end
    return best
end

-- The saved places of one kind: { { name, map, x, y } }.
local function seenList(known, kind, prof)
    local out, faction = {}, text(known.here.faction)
    local function add(name, e)
        if placed(e) then out[#out + 1] = { name = name, map = e.map, x = e.x, y = e.y } end
    end
    local npcs = type(known.npcs) == "table" and known.npcs or {}
    if kind == "trainer" then
        for name, e in pairs(npcs) do
            if type(e) == "table" and type(e.trains) == "table" and e.trains[prof] == true and mayUse(e, faction) then
                add(name, e)
            end
        end
        return out
    end
    if type(known.services) == "table" then
        for key, e in pairs(known.services) do
            if type(e) == "table" and type(e.kinds) == "table" and e.kinds[kind] == true then
                add(text(e.name) or tostring(key), e)
            end
        end
    end
    local role = PP.ROLE[kind]
    for name, e in pairs(npcs) do
        if role and type(e) == "table" and type(e.roles) == "table" and e.roles[role] == true and mayUse(e, faction) then
            add(name, e)
        end
    end
    return out
end

-- Questie's places of one kind the player's faction can use.
local function questieList(known, kind, prof)
    local found = call(known.questie)
    local list
    if type(found) == "table" then
        if kind == "named" then
            -- prof: the NPC's name.
            if type(found.named) == "table" and prof ~= nil then list = found.named[prof] end
        elseif kind ~= "trainer" then
            list = found[kind]
        elseif type(found.trainer) == "table" then
            list = found.trainer[prof]
        end
    end
    local out, faction = {}, text(known.here.faction)
    if type(list) ~= "table" then return out end
    for _, c in ipairs(list) do
        if placed(c) and friendly(c.side, faction) then out[#out + 1] = c end
    end
    return out
end

-- list without the names a step leaves out: with step.only, only the
-- names in it; with step.skip, none of the names in it.
local function namesKept(list, step)
    local only, skip
    if type(step) == "table" then
        if type(step.only) == "table" then only = step.only end
        if type(step.skip) == "table" then skip = step.skip end
    end
    if not only and not skip then return list end
    local out = {}
    for _, c in ipairs(list) do
        if (not only or only[c.name] == true) and not (skip and skip[c.name] == true) then out[#out + 1] = c end
    end
    return out
end

-- step: the asking step, for its only and skip names (nil: every name).
local function npcPlace(known, kind, prof, same, step)
    local seen = namesKept(seenList(known, kind, prof), step)
    local to = onMap(seen, known)
    if to then return to, PP.SAVED end
    -- Questie is asked only now: nothing saved is on this map.
    local q = namesKept(questieList(known, kind, prof), step)
    to = onMap(q, known)
    if to then return to, PP.QUESTIE end
    to = onContinent(seen, known, same)
    if to then return to, PP.SAVED end
    to = onContinent(q, known, same)
    if to then return to, PP.QUESTIE end
    return nil
end

local function nodeOf(known, prof)
    if type(prof) ~= "string" then return nil end
    if type(known.nodes) == "table" then
        for _, n in ipairs(known.nodes) do
            if type(n) == "table" and n.prof == prof and share(n.x) and share(n.y) then
                return { map = known.here.map, x = n.x, y = n.y }
            end
        end
    end
    local spots = call(known.spots, prof)
    if type(spots) ~= "table" then return nil end
    local list = {}
    for _, c in ipairs(spots) do
        if placed(c) then list[#list + 1] = c end
    end
    return onMap(list, known)
end

local function stationOf(known, kind, same)
    if not PP.STATION_FAR[kind] then return nil end
    local serves = type(N.PROF_STATION_SPOTS) == "table" and N.PROF_STATION_SPOTS[kind] or nil
    if type(serves) ~= "table" then serves = { [kind] = true } end
    local list = {}
    if type(known.stations) == "table" then
        for _, s in ipairs(known.stations) do
            if type(s) == "table" and serves[s.kind] == true and placed(s) then
                -- One on this map is the plan's own to point at.
                if s.map == known.here.map then return nil end
                list[#list + 1] = { name = tostring(s.kind), map = s.map, x = s.x, y = s.y }
            end
        end
    end
    return onContinent(list, known, same) or npcPlace(known, "trainer", PP.STATION_PROF, same)
end

function PP.Pick(step, prof, known)
    if type(step) ~= "table" or type(known) ~= "table" then return nil end
    local here = known.here
    if type(here) ~= "table" or here.map == nil or not (share(here.x) and share(here.y)) then return nil end
    local kind = PP.KIND[step.kind]
    local to, from
    if kind == "trainer" then
        if step.npc ~= nil or type(prof) ~= "string" then return nil end
        to, from = npcPlace(known, kind, prof, sameOf(known))
    elseif kind == "banker" or kind == "auction" then
        to, from = npcPlace(known, kind, nil, sameOf(known))
    elseif kind == "weaponMaster" then
        to, from = npcPlace(known, kind, nil, sameOf(known), step)
    elseif kind == "named" then
        -- Questie's alone: this map, else this continent.
        if not text(step.name) then return nil end
        local q = questieList(known, kind, step.name)
        to = onMap(q, known) or onContinent(q, known, sameOf(known))
        if to then from = PP.QUESTIE end
    elseif kind == "node" then
        local what = step.gather
        if type(what) ~= "string" then what = prof end
        to = nodeOf(known, what)
    elseif kind == "station" then
        to = stationOf(known, step.station, sameOf(known))
    end
    if not placed(to) then return nil end
    return { name = to.name, map = to.map, x = to.x, y = to.y }, from
end

function PP.Of(step, prof, known)
    local to = PP.Pick(step, prof, known)
    if not to then return nil end
    return { map = to.map, x = to.x, y = to.y }
end

-- Questie's nearest NPC of a service kind (PP.SERVICES) the player's
-- faction can use: on the map the player is on, else on another map of
-- the player's continent (by known.far). Saved places are not looked at
-- here: N.Nearest (Nav/ServiceNearest.lua) sets this beside them.
function PP.Service(kind, known)
    if PP.SERVICES[kind] ~= true or type(known) ~= "table" then return nil end
    local here = known.here
    if type(here) ~= "table" or here.map == nil or not (share(here.x) and share(here.y)) then return nil end
    local q = questieList(known, kind)
    local to = onMap(q, known) or onContinent(q, known, sameOf(known))
    if not placed(to) then return nil end
    return { name = to.name, map = to.map, x = to.x, y = to.y }
end

-- The map of one of Questie's areas, or nil. Both ways of calling it.
local function mapOf(zones, area)
    if type(zones) ~= "table" or type(zones.GetUiMapIdByAreaId) ~= "function" then return nil end
    local m = call(zones.GetUiMapIdByAreaId, area)
    if type(m) == "number" then return m end
    m = call(zones.GetUiMapIdByAreaId, zones, area)
    if type(m) == "number" then return m end
    return nil
end

-- Questie's spawns ({ [area] = { { x, y }, ... } }, x and y 0..100) as
-- places { map, x, y }, at most max of them, areas in number order. only:
-- the one map wanted, or nil for every map. A spot with no map the client
-- can place, or off the map, is left out.
local function spotsOf(zones, spawns, max, only)
    local out = {}
    if type(spawns) ~= "table" then return out end
    local areas = {}
    for area in pairs(spawns) do
        if type(area) == "number" then areas[#areas + 1] = area end
    end
    table.sort(areas)
    for _, area in ipairs(areas) do
        local map = mapOf(zones, area)
        local pts = spawns[area]
        if map ~= nil and (only == nil or only == map) and type(pts) == "table" then
            for i = 1, #pts do
                local p = pts[i]
                if #out < max and type(p) == "table" and finite(p[1]) and finite(p[2])
                    and share(p[1] / 100) and share(p[2] / 100) then
                    out[#out + 1] = { map = map, x = p[1] / 100, y = p[2] / 100 }
                end
            end
        end
    end
    return out
end

-- Is the bit of flag (a power of two) set in mask?
local function flagged(mask, flag)
    return math.floor(mask / flag) % 2 == 1
end

function PP.ScanStart(db)
    if type(db) ~= "table" or type(db.NPCPointers) ~= "table" then return nil end
    local bits = {}
    for kind, name in pairs(PP.FLAG_NAME) do
        local own = type(db.npcFlags) == "table" and db.npcFlags[name] or nil
        if finite(own) and own > 0 then bits[kind] = own else bits[kind] = PP.FLAG[kind] end
    end
    local ids = {}
    for id in pairs(db.NPCPointers) do
        if type(id) == "number" then ids[#ids + 1] = id end
    end
    table.sort(ids)
    local names
    if next(PP.NAMES) ~= nil then names = PP.NAMES end
    return { db = db, ids = ids, at = 0, bits = bits, n = 0, names = names,
             found = { trainer = {}, banker = {}, auction = {} } }
end

function PP.ScanStep(pass, zones, count)
    if type(pass) ~= "table" or type(pass.ids) ~= "table" then return true end
    local db, ids, bits, found = pass.db, pass.ids, pass.bits, pass.found
    local last = #ids
    if finite(count) and count >= 1 and pass.at + count < last then last = pass.at + math.floor(count) end
    for at = pass.at + 1, last do
        local id = ids[at]
        local lists = {}
        local sub = call(db.QueryNPCSingle, id, "subName")
        if type(sub) == "string" then
            local prof = sub:match(PP.TRAINER_TITLE)
            if prof ~= nil and N.PROF_NAMES[prof] then
                found.trainer[prof] = found.trainer[prof] or {}
                lists[#lists + 1] = found.trainer[prof]
            end
            if sub == PP.WEAPON_MASTER then
                found.weaponMaster = found.weaponMaster or {}
                lists[#lists + 1] = found.weaponMaster
            end
        end
        local mask = call(db.QueryNPCSingle, id, "npcFlags")
        local name
        local named = false
        if finite(mask) and mask > 0 then
            if flagged(mask, bits.banker) then lists[#lists + 1] = found.banker end
            if flagged(mask, bits.auction) then lists[#lists + 1] = found.auction end
            -- The other services (PP.Service): the same read, no read more.
            for i = 1, #PP.SERVICE do
                local kind = PP.SERVICE[i]
                if flagged(mask, bits[kind]) then
                    found[kind] = found[kind] or {}
                    lists[#lists + 1] = found[kind]
                end
            end
            -- An NPC asked for by its name (PP.Want): the name is read of
            -- an NPC with any flag only (a trainer or a vendor has one).
            if pass.names then
                name, named = call(db.QueryNPCSingle, id, "name"), true
                if type(name) == "string" and pass.names[name] == true then
                    found.named = found.named or {}
                    found.named[name] = found.named[name] or {}
                    lists[#lists + 1] = found.named[name]
                end
            end
        end
        if #lists > 0 then
            if not named then name = call(db.QueryNPCSingle, id, "name") end
            local spots = {}
            if type(name) == "string" and name ~= "" then
                spots = spotsOf(zones, call(db.QueryNPCSingle, id, "spawns"), PP.SPOTS, nil)
            end
            local side = call(db.QueryNPCSingle, id, "friendlyToFaction")
            -- One table a place, in every list the NPC is in (a repair
            -- vendor is a vendor too): vendors are many.
            for _, spot in ipairs(spots) do
                local place = { name = name, map = spot.map, x = spot.x, y = spot.y, side = side }
                for _, list in ipairs(lists) do
                    list[#list + 1] = place
                    pass.n = pass.n + 1
                end
            end
        end
    end
    pass.at = last
    return last >= #ids
end

function PP.Scan(db, zones)
    local pass = PP.ScanStart(db)
    if not pass then return { trainer = {}, banker = {}, auction = {} }, 0 end
    PP.ScanStep(pass, zones, nil)
    return pass.found, pass.n
end

-- The client's time, or nil when it has none (now() answers 0).
local function nowOf(client)
    local now = ask(client, "now")
    if finite(now) and now > 0 then return now end
    return nil
end

-- May state = { tries, last } ask again at now?
local function due(state, now)
    if state.tries >= PP.TRIES then return false end
    if now and state.last and now >= state.last and now - state.last < PP.RETRY then return false end
    return true
end

function PP.Questie()
    local reader = {}
    local found
    local state = { tries = 0 }
    local objects = {}

    local wanted, pass

    function reader.places()
        if found then return found end
        wanted = true
        return nil
    end

    function reader.work(client)
        if found or not wanted then return false end
        if not pass then
            if not due(state, nowOf(client)) then return false end
            -- Questie not there, or its list of NPCs not built yet: nothing
            -- to go through, and no try is used up.
            pass = PP.ScanStart(ask(client, "questieModule", "QuestieDB"))
            return pass ~= nil
        end
        if not PP.ScanStep(pass, ask(client, "questieModule", "ZoneDB"), PP.STEP) then return true end
        state.tries = state.tries + 1
        state.last = nowOf(client)
        if pass.n > 0 or state.tries >= PP.TRIES then found = pass.found end
        pass = nil
        return false
    end

    -- Is an answer asked for still on its way? True while a pass runs, or
    -- one is due and Questie has its list of NPCs. It reads nothing more.
    function reader.waiting(client)
        if found or not wanted then return false end
        if pass then return true end
        if state.tries >= PP.TRIES then return false end
        local db = ask(client, "questieModule", "QuestieDB")
        return type(db) == "table" and type(db.NPCPointers) == "table"
    end

    -- read() -> the object ids of a profession, asked again no sooner than
    -- PP.RETRY seconds later (a client with no time: every call).
    local idsOf = {}
    function reader.ids(client, prof, read)
        local kept, now = idsOf[prof], nowOf(client)
        if kept and now and kept.at and now >= kept.at and now - kept.at < PP.RETRY then return kept.ids end
        local ids = call(read)
        if type(ids) ~= "table" then ids = {} end
        idsOf[prof] = { ids = ids, at = now }
        return ids
    end

    function reader.spots(client, ids, map)
        local out = {}
        if type(ids) ~= "table" or map == nil then return out end
        for _, id in ipairs(ids) do
            local o = objects[id]
            if not o then
                o = { tries = 0, maps = {} }
                objects[id] = o
            end
            local now = nowOf(client)
            if o.spawns == nil and due(o, now) then
                local db = ask(client, "questieModule", "QuestieDB")
                if type(db) == "table" then
                    o.tries = o.tries + 1
                    o.last = now
                    local spawns = call(db.QueryObjectSingle, id, "spawns")
                    if type(spawns) == "table" then o.spawns = spawns end
                end
            end
            if o.spawns ~= nil then
                local list = o.maps[map]
                if not list then
                    list = spotsOf(ask(client, "questieModule", "ZoneDB"), o.spawns, PP.NODE_SPOTS, map)
                    o.maps[map] = list
                end
                for i = 1, #list do out[#out + 1] = list[i] end
            end
        end
        return out
    end

    return reader
end

-- The object ids of the nodes of prof this account gathered, on any map.
local function nodeIds(store, prof)
    local all = saved(store, "account", PP.NODES_PATH)
    local ids, has = {}, {}
    if type(all) ~= "table" then return ids end
    for _, list in pairs(all) do
        if type(list) == "table" then
            for _, e in ipairs(list) do
                if type(e) == "table" and e.prof == prof and finite(e.id) and not has[e.id] then
                    has[e.id] = true
                    ids[#ids + 1] = e.id
                end
            end
        end
    end
    table.sort(ids)
    return ids
end

function PP.From(client, store, use, kind, reads)
    if type(reads) ~= "table" then reads = {} end
    local known = { contOf = reads.contOf, far = reads.far }
    local at = ask(client, "position")
    if type(at) == "table" and at.map ~= nil and share(at.x) and share(at.y) then
        known.here = { map = at.map, x = at.x, y = at.y, faction = text(ask(client, "faction")) }
        local size = ask(client, "mapSize", at.map)
        if type(size) == "table" and finite(size.w) and finite(size.h) and size.w > 0 and size.h > 0 then
            known.here.size = { w = size.w, h = size.h }
        end
    end
    local q = type(reads.questie) == "table" and reads.questie or nil
    if kind == "trainer" or kind == "banker" or kind == "auction" or kind == "station"
        or kind == "weaponMaster" then
        known.npcs = saved(store, "account", PP.NPCS)
        if q then known.questie = function() return call(q.places, client) end end
    end
    if (kind == "named" or kind == "service") and q then
        known.questie = function() return call(q.places, client) end
    end
    if kind == "banker" or kind == "auction" then
        known.services = saved(store, "char", N.SERVICES or "learned.places.services")
    end
    if kind == "station" then known.stations = call(stationsSeen, store) end
    if kind == "node" then
        local mod = call(use, PP.NODE_MODULE)
        local list
        if type(mod) == "table" then list = call(mod.Nearest, PP.NODES) end
        if type(list) == "table" then
            known.nodes = {}
            for _, r in ipairs(list) do
                if type(r) == "table" and type(r.node) == "table" then known.nodes[#known.nodes + 1] = r.node end
            end
        end
        if q and known.here then
            known.spots = function(prof)
                local ids = call(q.ids, client, prof, function() return nodeIds(store, prof) end)
                return call(q.spots, client, ids, known.here.map)
            end
        end
    end
    return known
end

N.PROF_STEP = "profStep"
N.PROF_SETTING = "nav.profArrow"

-- The feed's step (Nav/ProfFeed.lua: picked, with its pick) or the older
-- step (N.ProfNext: gather nodes, the trainer at the cap, the station),
-- whichever walks the player further:
--   a pick to do here or to walk to on this continent (ranks 1 to 3),
--   else the older step when it has a place,
--   else a pick in words (also one on another continent), but training in
--   words leaves it to the older step, which knows the trainer and the cap,
--   else the older step's words, else the feed's one line of what to do.
-- Never silent while either has something to say.
function N.ProfChoose(picked, pick, older)
    if type(picked) ~= "table" then return older end
    local rank = type(pick) == "table" and pick.rank or nil
    if type(rank) ~= "number" then return picked end
    if rank <= 3 then return picked end
    if type(older) == "table" and type(older.place) == "table" then return older end
    -- Lead section 419: "any trainer", said only because every known recipe
    -- was outgrown and no trainer was seen, leaves it to the older step's
    -- words, which name the craft or say why nothing gives a point.
    -- Lead section 421 point 1: a trainer step with no place (any kind)
    -- never beats an older step that names something the player can do now.
    local step = pick.step
    if type(older) == "table" and type(step) == "table" and step.kind == "learn_recipe"
        and (step.outgrown == true or older.doable == true) then
        return older
    end
    -- Lead section 422 item 1: "no point yet" with no place never beats an
    -- older step that names something the player can do now.
    if type(older) == "table" and type(step) == "table" and step.kind == "no_point" and older.doable == true then
        return older
    end
    local training = type(pick.step) == "table" and pick.step.kind == "train_tier"
    if rank <= 5 and not (training and type(older) == "table") then return picked end
    if type(older) == "table" then return older end
    return picked
end

-- Lead section 418 item 6: the older step N.ProfChoose shows, with the
-- other professions' lines (also, Nav/ProfFeed.lua F.Also) after its own:
-- a text step's lines, else its also (UI/Arrow.lua says it under the label
-- and detail). A copy; place, label and the rest are kept as they are.
function N.ProfWithAlso(step, also)
    if type(step) ~= "table" or type(also) ~= "table" or #also == 0 then return step end
    local out = {}
    for key, v in pairs(step) do out[key] = v end
    if type(step.lines) == "table" then
        out.lines = {}
        for i = 1, #step.lines do out.lines[i] = step.lines[i] end
        for i = 1, #also do out.lines[#out.lines + 1] = also[i] end
    else
        out.also = {}
        for i = 1, #also do out.also[i] = also[i] end
    end
    COVERS[out] = COVERS[step]
    return out
end

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
        local picked, pick, result
        if feed and type(feed.Step) == "function" then
            local okStep, s, p, r = pcall(feed.Step)
            if okStep and type(s) == "table" then picked, pick, result = s, p, r end
        end
        local source
        if type(ctx.use) == "function" then
            local ok, s = pcall(ctx.use, "gatherMateSource")
            if ok then source = s end
        end
        local older = N.ProfNextFrom(ctx.client, ctx.store, source)
        local chosen = N.ProfChoose(picked, pick, older)
        -- Lead section 418 item 6: the older step shown, the other
        -- professions still get their lines, none for the one it covers
        -- (a why step covers them all: no line added).
        local covered = N.ProfCovers(older)
        local F = N.ProfFeed
        if chosen == older and picked ~= nil and covered ~= nil and type(result) == "table"
            and F and type(F.Also) == "function" then
            local okAlso, also = pcall(F.Also, result, covered)
            if okAlso then chosen = N.ProfWithAlso(chosen, also) end
        end
        return chosen
    end

    k:Setting({ key = N.PROF_SETTING, scope = "account", type = "bool", default = true,
        label = "Profession arrow", group = "travel.arrow",
        help = "Shows a second, purple arrow for your profession steps: gathering in an area, smelting or crafting at a station, learning at a trainer, or buying from a vendor.",
        synonyms = { "profession", "trainer", "arrow", "gather", "craft", "buy", "smelt", "skill cap" } })

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
