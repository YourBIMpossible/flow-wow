-- The profession route (lead section 341, zflow-prof-guide): a craft that
-- gives a point gets a place when its profession needs a station this
-- account has seen, and the next profession step is the nearest stop that
-- has a place: a trainer, a node or a station. Pure: plain tables in, a
-- step out. No game client is involved. Made-up names and places only.
--
-- Red before the code: N.ProfRoute and N.PROF_STATION_DETAIL do not exist
-- and a craft step is text only, so every test here fails.
local _, ns = ...

local N = ns.Nav

local T = {}

local function fmt(pattern, ...)
    if type(pattern) ~= "string" then return nil end
    return pattern:format(...)
end

-- Standing in the middle of map 1411 (1000 by 500 yards), Horde.
local function here()
    return {
        position = { map = 1411, x = 0.5, y = 0.5 },
        zone = { cont = 1, zone = 1411 },
        faction = "Horde",
        mapSize = function(map)
            if map == 1411 then return { w = 1000, h = 500 } end
            return nil
        end,
    }
end

local BOOK = {
    ["Test Buckle"] = { profession = "Blacksmithing" },
    ["Stew"] = { profession = "Cooking" },
    ["Test Cloth"] = { profession = "Tailoring" },
}
local COLOURS = {
    ["Test Buckle"] = { optimal = { lo = 40, hi = 60 } },
    ["Stew"] = { optimal = { lo = 40, hi = 60 } },
    ["Test Cloth"] = { optimal = { lo = 40, hi = 60 } },
}

local function at(kind, x, y, map)
    return { kind = kind, map = map or 1411, x = x, y = y }
end

-- over: fields of the input put over a Blacksmithing character at 50 of 75.
local function input(over)
    local i = {
        professions = { Blacksmithing = true },
        readings = { Blacksmithing = { skill = 50, max = 75 } },
        here = here(),
        nodeState = "absent",
        book = BOOK,
        colours = COLOURS,
    }
    for k, v in pairs(over or {}) do i[k] = v end
    return i
end

local BUCKLE = "Make Test Buckle: a sure Blacksmithing point"

T["the lines and tables of the route exist"] = function(t)
    t.eq(type(N.ProfRoute), "function", "N.ProfRoute")
    t.eq(type(N.PROF_STATION_DETAIL), "string", "N.PROF_STATION_DETAIL")
    t.eq(type(N.PROF_STATION), "table", "N.PROF_STATION")
    t.eq(N.PROF_STATION and N.PROF_STATION.Blacksmithing, "anvil", "Blacksmithing works at an anvil (first guess)")
    t.eq(N.PROF_STATION and N.PROF_STATION.Cooking, "fire", "Cooking works at a fire (first guess)")
    t.eq(N.PROF_STATION and N.PROF_STATION.Tailoring, nil, "Tailoring needs no station")
end

T["a craft at a station: the nearest anvil seen on this map is the place"] = function(t)
    t.eq(fmt(N.PROF_CRAFT_SURE, "Test Buckle", "Blacksmithing"), BUCKLE, "the craft line")
    local step = N.ProfNext(input({ stations = { at("anvil", 0.9, 0.5), at("anvil", 0.6, 0.5) } }))
    t.eq(step, {
        place = { cont = 1, map = 1411, x = 0.6, y = 0.5 }, radius = N.PROF_NEAR,
        label = "Blacksmithing anvil", detail = BUCKLE,
    }, "the craft line is over the label limit: it is the line under the label")
end

T["a craft at a station: a craft line that fits is the label, and the station is said under it"] = function(t)
    local step = N.ProfNext(input({
        professions = { Cooking = true }, readings = { Cooking = { skill = 50, max = 75 } },
        stations = { at("fire", 0.5, 0.7) },
    }))
    t.eq(step, {
        place = { cont = 1, map = 1411, x = 0.5, y = 0.7 }, radius = N.PROF_NEAR,
        label = "Make Stew: a sure Cooking point", detail = fmt(N.PROF_STATION_DETAIL, "fire"),
    })
end

T["a craft at a station: a forge serves an anvil, a fire does not, and another map is not here"] = function(t)
    local step = N.ProfNext(input({ stations = { at("fire", 0.51, 0.5), at("anvil", 0.52, 0.5, 1412), at("forge", 0.7, 0.5) } }))
    t.eq(step and step.place, { cont = 1, map = 1411, x = 0.7, y = 0.5 }, "the forge")
    t.eq(step and step.label, "Blacksmithing forge", "named as what was seen there")
    step = N.ProfNext(input({ stations = { at("fire", 0.51, 0.5), at("anvil", 0.52, 0.5, 1412) } }))
    t.eq(step, { still = true, lines = { BUCKLE } }, "no anvil or forge on this map: the craft as text, as before")
end

T["a craft at a station: no station seen, or a list that is not one, is text as before"] = function(t)
    for what, stations in pairs({ none = false, empty = {}, text = "anvil", holes = { 7, "x", { kind = "anvil" },
        { kind = "anvil", map = 1411, x = 2, y = 0.5 }, { kind = "anvil", map = 1411, x = 0.5 } } }) do
        local step = N.ProfNext(input({ stations = stations or nil }))
        t.eq(step, { still = true, lines = { BUCKLE } }, what)
    end
end

T["a craft at a station: a profession with no station stays text, whatever was seen"] = function(t)
    local step = N.ProfNext(input({
        professions = { Tailoring = true }, readings = { Tailoring = { skill = 50, max = 75 } },
        stations = { at("anvil", 0.6, 0.5), at("fire", 0.6, 0.5) },
    }))
    t.eq(step and step.place, nil, "no place")
    t.eq(step and step.still, true, "text only")
    t.eq(step and step.lines, { "Make Test Cloth: a sure Tailoring point" })
end

T["a craft at a station: nothing that gives a point, or a capped profession, gets no station"] = function(t)
    local stations = { at("anvil", 0.6, 0.5) }
    local step = N.ProfNext(input({ stations = stations, colours = { ["Test Buckle"] = { trivial = { lo = 40, hi = 60 } } } }))
    t.eq(step and step.place, nil, "all grey: no place")
    t.eq(step and step.lines, { fmt(N.PROF_WHY_NO_POINT, "Blacksmithing", 50) }, "all grey: the why line")
    step = N.ProfNext(input({ stations = stations, readings = { Blacksmithing = { skill = 75, max = 75 } } }))
    t.eq(step and step.place, nil, "capped: no place")
    t.eq(step and step.lines, { fmt(N.PROF_WHY_TRAINER, "Blacksmithing", 75, "Blacksmithing") }, "capped: the trainer line")
end

T["a craft at a station: where the player is not known, there is no station to choose"] = function(t)
    local i = input({ stations = { at("anvil", 0.6, 0.5) } })
    i.here.position = nil
    t.eq(N.ProfNext(i), { still = true, lines = { BUCKLE } })
end

T["a craft at a station: a placed craft comes before a craft that is only text"] = function(t)
    local step = N.ProfNext(input({
        professions = { Blacksmithing = true, Alchemy = true },
        readings = { Blacksmithing = { skill = 50, max = 75 }, Alchemy = { skill = 50, max = 75 } },
        book = { ["Test Buckle"] = { profession = "Blacksmithing" }, ["A Potion"] = { profession = "Alchemy" } },
        colours = { ["Test Buckle"] = { medium = { lo = 40, hi = 60 } }, ["A Potion"] = { optimal = { lo = 40, hi = 60 } } },
        stations = { at("anvil", 0.6, 0.5) },
    }))
    t.eq(step and step.place, { cont = 1, map = 1411, x = 0.6, y = 0.5 }, "the needle has the anvil to point at")
    t.eq(step and step.detail, "Make Test Buckle: may give a Blacksmithing point")
end

-- A capped Cooking with its trainer 300 yards east, and Mining below its
-- cap with one vein.
local function two(nodeX, over)
    local i = input({
        professions = { Cooking = true, Mining = true },
        readings = { Cooking = { skill = 75, max = 75 }, Mining = { skill = 30, max = 75 } },
        npcs = { Aska = { map = 1411, x = 0.8, y = 0.5, trains = { Cooking = true }, factions = { Horde = true }, seen = 1 } },
        nodes = { { kind = "Mining", x = nodeX, y = 0.5, node = "Test Vein" } },
        nodeState = "ready",
    })
    for k, v in pairs(over or {}) do i[k] = v end
    return i
end

T["the route: the nearest stop with a place comes first"] = function(t)
    local step = N.ProfNext(two(0.6))
    t.eq(step and step.label, "Test Vein", "the vein at 100 yards before the trainer at 300")
    step = N.ProfNext(two(0.1))
    t.eq(step and step.label, "Cooking trainer", "the trainer at 300 yards before the vein at 400")
end

T["the route: the same distance, or where the player is not known: trainer, then node, then station"] = function(t)
    local same = two(0.25)
    same.npcs.Aska.x = 0.75
    local step = N.ProfNext(same)
    t.eq(step and step.label, "Cooking trainer", "both at 250 yards: the trainer")
    local i = two(0.6)
    i.here.position = nil
    step = N.ProfNext(i)
    t.eq(step and step.label, "Cooking trainer", "no position: nothing is nearer, the trainer")
end

T["the route: with no size for the map, the nearest by its share of the map"] = function(t)
    local i = two(0.6)
    i.here.mapSize = nil
    t.eq(N.ProfNext(i).label, "Test Vein")
end

T["the route: a trainer on another map is said first, as before (D10)"] = function(t)
    local i = two(0.6)
    i.npcs.Aska.map = 1412
    t.eq(N.ProfNext(i).label, "Cooking trainer" .. N.PROF_OTHER_MAP)
end

T["the route: every stop with a place, nearest first, with what it is"] = function(t)
    if type(N.ProfRoute) ~= "function" then return t.ok(false, "N.ProfRoute") end
    local i = two(0.9, {
        professions = { Cooking = true, Mining = true, Blacksmithing = true },
        readings = { Cooking = { skill = 75, max = 75 }, Mining = { skill = 30, max = 75 },
                     Blacksmithing = { skill = 50, max = 75 } },
        stations = { at("anvil", 0.6, 0.5) },
    })
    local stops = N.ProfRoute(i)
    local kinds, yards = {}, {}
    for n, s in ipairs(stops) do
        kinds[n] = s.kind
        yards[n] = math.floor(math.sqrt(s.d) + 0.5)
        t.eq(type(s.step) == "table" and type(s.step.place), "table", "stop " .. n .. " has a place")
    end
    t.eq(kinds, { "station", "trainer", "node" })
    t.eq(yards, { 100, 300, 400 })
    t.eq(N.ProfNext(i), stops[1] and stops[1].step, "the next step is the first stop")
    t.eq(N.ProfRoute(nil), {}, "nothing handed in: no stops")
    t.eq(N.ProfRoute(input()), {}, "a craft with no station seen: no stop with a place")
end

T["the route: nothing handed in is changed"] = function(t)
    local stations = { at("anvil", 0.9, 0.5), at("anvil", 0.6, 0.5) }
    local i = input({ stations = stations })
    N.ProfNext(i)
    t.eq(stations, { at("anvil", 0.9, 0.5), at("anvil", 0.6, 0.5) }, "the saved list")
    t.eq(i.readings, { Blacksmithing = { skill = 50, max = 75 } }, "the readings")
end

T["from the client and the store: the stations this account has seen are read"] = function(t)
    local asked = {}
    local char = {
        ["learned.facts.profSkill"] = { Blacksmithing = { skill = 50, max = 75 } },
        ["learned.facts.recipeBook"] = BOOK,
        ["learned.recipeColors"] = COLOURS,
    }
    local account = { ["learned.keyStations"] = { at("anvil", 0.6, 0.5) } }
    local store = { writes = 0 }
    function store:get(scope, path)
        asked[scope .. ":" .. path] = true
        local from = scope == "char" and char or account
        return from[path]
    end
    function store:set() self.writes = self.writes + 1; return true end
    function store:table() self.writes = self.writes + 1; return {} end
    local client = {
        professions = function() return { Blacksmithing = true } end,
        position = function() return { map = 1411, x = 0.5, y = 0.5 } end,
        zone = function() return { cont = 1, zone = 1411 } end,
        faction = function() return "Horde" end,
        mapSize = function(map) if map == 1411 then return { w = 1000, h = 500 } end end,
    }
    local step = N.ProfNextFrom(client, store, nil)
    t.eq(asked["account:learned.keyStations"], true, "the account's stations are read")
    t.eq(step and step.place, { cont = 1, map = 1411, x = 0.6, y = 0.5 })
    t.eq(store.writes, 0, "nothing is written")
end

return T
