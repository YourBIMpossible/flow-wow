local _, ns = ...
-- Z-Flow flight masters not learned yet (parity row B-08, the data half;
-- lead section 611): the flight masters of the player's own Questie on the
-- player's continent, of the player's faction, whose flight point this
-- character does not know. DATA ONLY: no pin, no window, no word, no
-- setting. LOOK ONLY: nothing is targeted, talked to, taken or saved.
--
-- Ported from Flow 0.35.377 (commit a529eea):
--   Modules/Nav/MapFlights.lua:57-91 (MF.Pins): a flight master within
--     MF.SAME = 250 yards (:37) of a flight point you have, on the same
--     continent, is that point's master and not one to learn; a name with
--     any such place is left out whole; of the rest a name once;
--   Modules/Nav/FlightPaths.lua:40-54 (FP.Learned): known too when you
--     opened their flight map (talked), or when they had no flight path
--     for you and you have not gained a level since (FP.Waits);
--   Modules/Nav/Services.lua:158-197 (S:All): only on the player's
--     continent, only friendly to the player's faction, one place for a
--     name in a 20 yard square, nearest first, the nearest MF.MAX = 80
--     (MapFlights.lua:33) looked at;
--   Modules/Nav/MapFlights.lua:152-155 and FlightPaths.lua:92-98
--     (FP.NotRides): not the NPCs who carry you themselves.
--
-- Where the facts are from (lead section 611: only the game, the player's
-- own Questie, or what this client recorded; unknown stays unknown):
--   the flight masters   Questie, through the one pass of Nav/ProfStep.lua
--                        (N.ProfPlace), owned by Nav/ProfFeed.lua: asked
--                        as use("profFeed").List("flight", client). This
--                        file reads nothing of Questie.
--   the known points     char "learned.flights.nodes" = { [name] =
--                        { cont, wx, wy } }: what Nav/Flights.lua saved
--                        from each flight map this character opened.
--   talked, none         char "learned.flights.talked" and
--                        "learned.flights.none" (Nav/FlightPaths.lua).
--   the world            client.mapCorners(map), client.worldPosition(),
--                        client.position(), client.faction(), client.level().
-- A flight map shows the points of the continent it is opened on, so the
-- known points of a continent are known only once a point is saved there
-- (the first flight master talked to is one). With none saved on the
-- player's continent the answer is nil and FU.NO_KNOWN, never "every
-- flight master is unknown".
--
-- Pure (plain tables in, nothing read, nothing remembered):
--   FU.KnowsOn(nodes, cont) -> is a known point saved on that continent?
--   FU.Learned(fm, facts) -> true when fm = { name, cont, wx, wy } is known
--     facts = { nodes, talked, none, level }
--   FU.Placed(list, corners, isRide) -> masters, left
--     list: { { name, map, x, y } } (the feed's List); corners(map) -> the
--     client's mapCorners of it or nil; isRide(name) optional. masters:
--     { { name, map, x, y, cont, wx, wy } }; left: how many were left out
--     because their map has no place in the world (never guessed).
--   FU.Of(masters, facts, me) -> list, or nil and a reason
--     me = { cont, wx, wy }. list = { { name, map, x, y, cont, wx, wy,
--     yards } }, nearest first (a tie: the lower name, map, x, y): x, y
--     shares 0..1 of map; cont, wx, wy the world place in yards; yards the
--     straight line from the player. An empty list: none is left to learn
--     among the ones Questie gives here.
--
-- Module "flightUnknown" (FU.Declare(k) -> api):
--   ns.use("flightUnknown").List() -> list, nil, left
--                                  or nil, reason
--     reason is one of FU.NOT_STARTED, FU.NO_FACTION, FU.NO_CONTINENT,
--     FU.NO_KNOWN, FU.READING (Questie's list is still being gone through:
--     ask again later), FU.NO_QUESTIE. Asked in that order, so Questie's
--     pass is not started for an answer that cannot be given.
-- Not tested in game.
ns.Nav = ns.Nav or {}
local N = ns.Nav

N.FlightUnknown = N.FlightUnknown or {}
local FU = N.FlightUnknown

FU.NAME = "flightUnknown"
FU.KIND = "flight"
FU.FEED = "profFeed"
FU.SAME = 250      -- yards: a known point this close to a flight master is theirs (Flow: MF.SAME)
FU.MAX = 80        -- flight masters looked at, the nearest (Flow: MF.MAX)
FU.GRID = 20       -- yards: one place for a name in a square of this side (Flow: S:All)
FU.NODES = "learned.flights.nodes"      -- char (Nav/Flights.lua)
FU.TALKED = "learned.flights.talked"    -- char (Nav/FlightPaths.lua)
FU.NONE = "learned.flights.none"        -- char (Nav/FlightPaths.lua)
FU.FACTIONS = { Alliance = true, Horde = true }
FU.NOT_STARTED = "not started"
FU.NO_FACTION = "your faction is not known"
FU.NO_CONTINENT = "where you are in the world is not known"
FU.NO_KNOWN = "the flight points this character knows on this continent are not known yet: open a flight map here once"
FU.READING = "the flight masters are still being read from Questie"
FU.NO_QUESTIE = "no flight masters: Questie is not there"

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function point(p)
    return type(p) == "table" and p.cont ~= nil and finite(p.wx) and finite(p.wy)
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok then return nil end
    return v
end

function FU.KnowsOn(nodes, cont)
    if type(nodes) ~= "table" or cont == nil then return false end
    for _, k in pairs(nodes) do
        if point(k) and k.cont == cont then return true end
    end
    return false
end

-- Is a "no flight path here" note still holding (Nav/FlightPaths.lua)?
local function held(note, level)
    local FP = ns.FlightPaths
    if note == nil or type(FP) ~= "table" then return false end
    return call(FP.Waits, note, level) == true
end

function FU.Learned(fm, facts)
    if type(fm) ~= "table" or type(facts) ~= "table" then return false end
    if type(facts.talked) == "table" and facts.talked[fm.name] then return true end
    if type(facts.none) == "table" and held(facts.none[fm.name], facts.level) then return true end
    if not point(fm) or type(facts.nodes) ~= "table" then return false end
    for _, k in pairs(facts.nodes) do
        if point(k) and k.cont == fm.cont then
            local dx, dy = k.wx - fm.wx, k.wy - fm.wy
            if dx * dx + dy * dy <= FU.SAME * FU.SAME then return true end
        end
    end
    return false
end

function FU.Placed(list, corners, isRide)
    local out, left = {}, 0
    local Flights = N.Flights
    for _, fm in ipairs(type(list) == "table" and list or {}) do
        if type(fm) == "table" and type(fm.name) == "string" and fm.name ~= "" and call(isRide, fm.name) ~= true then
            local cont, wx, wy
            if type(Flights) == "table" and type(Flights.ToWorld) == "function" then
                cont, wx, wy = Flights.ToWorld(call(corners, fm.map), fm.x, fm.y)
            end
            if cont ~= nil then
                out[#out + 1] = { name = fm.name, map = fm.map, x = fm.x, y = fm.y, cont = cont, wx = wx, wy = wy }
            else
                left = left + 1
            end
        end
    end
    return out, left
end

-- Is a to come before b? Nearer first; then the lower name, map, x, y.
local function nearer(a, b)
    if a.yards ~= b.yards then return a.yards < b.yards end
    if a.name ~= b.name then return a.name < b.name end
    local am, bm = tostring(a.map), tostring(b.map)
    if am ~= bm then return am < bm end
    if a.x ~= b.x then return a.x < b.x end
    return a.y < b.y
end

function FU.Of(masters, facts, me)
    if not point(me) then return nil, FU.NO_CONTINENT end
    if type(facts) ~= "table" or not FU.KnowsOn(facts.nodes, me.cont) then return nil, FU.NO_KNOWN end
    if type(masters) ~= "table" then return nil, FU.NO_QUESTIE end
    local near = {}
    for _, fm in ipairs(masters) do
        if type(fm) == "table" and type(fm.name) == "string" and fm.name ~= "" and point(fm) and fm.cont == me.cont
            and finite(fm.x) and finite(fm.y) then
            local dx, dy = fm.wx - me.wx, fm.wy - me.wy
            near[#near + 1] = { name = fm.name, map = fm.map, x = fm.x, y = fm.y, cont = fm.cont,
                                wx = fm.wx, wy = fm.wy, yards = math.sqrt(dx * dx + dy * dy) }
        end
    end
    table.sort(near, nearer)
    -- One place for a name in a square of FU.GRID yards, the nearest FU.MAX.
    local kept, square = {}, {}
    for _, fm in ipairs(near) do
        local key = fm.name .. ":" .. math.floor(fm.wx / FU.GRID) .. ":" .. math.floor(fm.wy / FU.GRID)
        if not square[key] and #kept < FU.MAX then
            square[key] = true
            kept[#kept + 1] = fm
        end
    end
    -- A name with any place by a known point is known whole.
    local has = {}
    for _, fm in ipairs(kept) do
        if not has[fm.name] and FU.Learned(fm, facts) then has[fm.name] = true end
    end
    local out, named = {}, {}
    for _, fm in ipairs(kept) do
        if not has[fm.name] and not named[fm.name] then
            named[fm.name] = true
            out[#out + 1] = fm
        end
    end
    return out
end

function FU.Declare(k)
    local api = {}
    local ctx

    local function ask(name, ...)
        local client = ctx and ctx.client
        if type(client) ~= "table" then return nil end
        return call(client[name], ...)
    end

    local function saved(path)
        local store = ctx.store
        if type(store) ~= "table" or type(store.get) ~= "function" then return nil end
        local ok, v = pcall(store.get, store, "char", path)
        if ok and type(v) == "table" then return v end
        return nil
    end

    -- Where the player is in the world: the client's own read, else the
    -- player's place on its map put in the world by that map's corners.
    local function world()
        local w = ask("worldPosition")
        if point(w) then return { cont = w.cont, wx = w.wx, wy = w.wy } end
        local pos = ask("position")
        local Flights = N.Flights
        if type(pos) ~= "table" or pos.map == nil or type(Flights) ~= "table"
            or type(Flights.ToWorld) ~= "function" then
            return nil
        end
        local cont, wx, wy = Flights.ToWorld(ask("mapCorners", pos.map), pos.x, pos.y)
        if cont == nil then return nil end
        return { cont = cont, wx = wx, wy = wy }
    end

    function api.list()
        if not ctx then return nil, FU.NOT_STARTED end
        if FU.FACTIONS[ask("faction")] ~= true then return nil, FU.NO_FACTION end
        local me = world()
        if not me then return nil, FU.NO_CONTINENT end
        local facts = { nodes = saved(FU.NODES), talked = saved(FU.TALKED), none = saved(FU.NONE),
                        level = ask("level") }
        if not FU.KnowsOn(facts.nodes, me.cont) then return nil, FU.NO_KNOWN end
        -- Questie's flight masters, from the feed's one pass. Asked only now.
        local feed = call(ctx.use, FU.FEED)
        if type(feed) ~= "table" or type(feed.List) ~= "function" then return nil, FU.NO_QUESTIE end
        local ok, list, waiting = pcall(feed.List, FU.KIND, ctx.client)
        if not ok or type(list) ~= "table" then
            if ok and waiting == true then return nil, FU.READING end
            return nil, FU.NO_QUESTIE
        end
        -- Each map's corners are read once an ask.
        local corners = {}
        local masters, left = FU.Placed(list, function(map)
            local c = corners[map]
            if c == nil then
                c = ask("mapCorners", map) or false
                corners[map] = c
            end
            return c
        end, N.IsRide)
        local out, why = FU.Of(masters, facts, me)
        if not out then return nil, why end
        return out, nil, left
    end

    k:Module({
        name = FU.NAME,
        needs = { "client", "store" },
        provides = { List = function() return api.list() end },
        start = function(c) ctx = c end,
        stop = function() ctx = nil end,
    })
    return api
end

-- The addon's own: declared when this file loads. It answers only when asked.
ns.flightUnknown = FU.Declare(ns)
