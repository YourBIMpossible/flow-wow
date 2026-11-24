local _, ns = ...
-- Z-Flow flights (lead DISPATCH section 182 item 2): the flight points this
-- character knows, and the flight way Nav/Travel.lua asks for
-- (k.use("flights").Way(place), RESEARCH-S45.md section 3).
--
-- Sources: MyBuddy's RESEARCH-FLIGHTS.md (section 4 "Reading the flight
-- map" and "Learning", section 6 "New client functions" 1 and FlightNodes'
-- Take); legacy Flow 0.35.377 Modules/Nav/Nav.lua:2708-2852 (saved
-- flights, FLIGHT_RATE, FLIGHT_OVERHEAD, AIR_SAVES, ReadTaxiNodes,
-- LearnTaxiNodes, FlightSeconds, AirRoute).
--
-- LOOK ONLY. It reads the open flight map and writes Z-Flow's own saved
-- data. It never takes a flight, selects a node, clicks or casts.
--
-- Saved: char "learned.flights.nodes" = { [name] = { cont, wx, wy } } in
-- world yards, the shape Flow's import already writes there
-- (Import/FromFlow.lua:214). Made only when the first point is written;
-- written by key (a name may hold a dot). Nothing is ever removed.
-- Read: account "learned.flights.times" ({ ["from>to"] = seconds }) and
-- "learned.flights.rate" (yards a second), both from the import.
--
-- Pure:
--   cont, wx, wy = Flights.ToWorld(corners, x, y)    a map share to the world
--   x, y = Flights.ToShare(corners, wx, wy)          and back
--     corners: client.mapCorners(map) = { cont, ox, oy, ex, ey, sx, sy };
--     nil for anything not known or a map of no size.
--   into, written = Flights.Take(read, corners, old)
--     read: client.taxiNodes(); corners: those of read.map. A copy of old
--     with each "current" or "reachable" node put in (legacy skipped only
--     Unreachable; the research keeps a state not known out: never
--     guessed). A node with no world place is skipped.
--   pick, reason = Flights.Pick(nodes, me, there, home, seconds, speed, rate)
--     The way rule (legacy N.AirRoute, Nav.lua:2836-2849), with the board
--     point held to the player's own map so the arrow can point at it:
--       - me and there are { cont, wx, wy }; another continent: nil (a
--         crossing's, not a flight's);
--       - board: the known point nearest the player among those on the
--         player's map (its share on `home` within 0..1);
--       - to: the known point nearest the target on that continent;
--       - nil when either is missing or both are the same point;
--       - flight seconds: seconds(from, to) (your own time) or the straight
--         line at rate (your saved rate, else RATE) yards a second plus
--         OVERHEAD;
--       - nil unless walking to the board point, flying and walking on
--         takes less than SAVES of walking straight there (at speed).
--     -> { from, to, x, y, sec, walk, run, learned }  (x, y: the board
--     point on `home`; run: yards from `to` to the target; learned: true
--     when the flight seconds are your own time, false when guessed)
--   line = Flights.Explain(nodes, me, there, reason)
--     Lead section 286: what the arrow says under a far goal when Pick
--     found no flight for `reason` (a Pick reason). nil on another
--     continent or a place not known; WALK when the flight is no quicker
--     or both ends are one point; NONE with no point known on the
--     continent; else ROUTE from the known point nearest the player to
--     the one nearest the target.
--
-- Module "flights" (Flights.Declare(k) -> api):
--   On TAXIMAP_OPENED: client.taxiNodes() and client.mapCorners(read.map),
--   then Take into the saved points. Always on, like ServiceSeen (it only
--   keeps what the game showed; RESEARCH-FLIGHTS.md question 5). No setting.
--   api.way(place)  place = { map, x, y } -> the step
--     { kind = "flight", label = "Fly to <to>", place = { cont, map, x, y },
--       radius = Flights.NEAR, hint = ROUTE } at the board point, or nil,
--       reason, line: line (Explain) only when the target is far (another
--       map, or more than FAR yards).
--     While a travel preview is on (k.use("try").Flight() answers a table,
--     lead section 187), the saved points are not read: the points are the
--     preview's made-up master (its map share put in the world with its
--     map's corners) under its name, and the target place itself under
--     Try.LAND_NAME. In memory only; nothing is saved.
--   api.nodes()     the saved points (a copy), or nil
--   api.last()      the flight the last way found (a copy), or nil; for
--                   Nav/TaxiMark.lua and Nav/MapFlights.lua (section 187 s7)
--   ns.use("flights") -> { Way = api.way, Nodes = api.nodes, Last = api.last }
ns.Nav = ns.Nav or {}
local N = ns.Nav

N.Flights = N.Flights or {}
local Flights = N.Flights

Flights.NAME = "flights"
Flights.KIND = "flight"
Flights.PATH = "learned.flights.nodes"           -- char
Flights.TIMES = "learned.flights.times"          -- account
Flights.RATE_PATH = "learned.flights.rate"       -- account
Flights.LABEL = "Fly to %s"
Flights.NEAR = 10       -- yards from the flight master that count as there (as Gates.NEAR)
Flights.RUN = 7         -- yards a second on foot (TaxiMark.SPEED, Legs.RUN)
Flights.RATE = 24       -- yards of straight line a second of flight (Flow: N.FLIGHT_RATE)
Flights.OVERHEAD = 10   -- seconds to take off and land (Flow: N.FLIGHT_OVERHEAD)
Flights.SAVES = 0.8     -- a flight must beat this share of the walk (Flow: N.AIR_SAVES)
Flights.FAR = 1000      -- yards: a goal this far on your own map is far (section 286)
Flights.ROUTE = "Fly: %s to %s, then run %d yd"
Flights.NONE = "No flight points known yet for this character: open any flight map once"
Flights.WALK = "Walking: no known flight is quicker"

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function dist(ax, ay, bx, by)
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

local function plainCorners(m)
    if type(m) ~= "table" or m.cont == nil then return false end
    for _, key in ipairs({ "ox", "oy", "ex", "ey", "sx", "sy" }) do
        if not finite(m[key]) then return false end
    end
    return true
end

function Flights.ToWorld(m, x, y)
    if not plainCorners(m) or not finite(x) or not finite(y) then return nil end
    local wx = m.ox + x * (m.ex - m.ox) + y * (m.sx - m.ox)
    local wy = m.oy + x * (m.ey - m.oy) + y * (m.sy - m.oy)
    if not finite(wx) or not finite(wy) then return nil end
    return m.cont, wx, wy
end

function Flights.ToShare(m, wx, wy)
    if not plainCorners(m) or not finite(wx) or not finite(wy) then return nil end
    local ax, ay = m.ex - m.ox, m.ey - m.oy
    local bx, by = m.sx - m.ox, m.sy - m.oy
    local det = ax * by - bx * ay
    if det == 0 or not finite(det) then return nil end
    local dx, dy = wx - m.ox, wy - m.oy
    local x, y = (dx * by - bx * dy) / det, (ax * dy - dx * ay) / det
    if not finite(x) or not finite(y) then return nil end
    return x, y
end

local KNOWN = { current = true, reachable = true }

function Flights.Take(read, corners, old)
    local into = {}
    for name, p in pairs(type(old) == "table" and old or {}) do into[name] = p end
    local written = 0
    if type(read) ~= "table" or type(read.nodes) ~= "table" then return into, 0 end
    for _, n in ipairs(read.nodes) do
        if type(n) == "table" and type(n.name) == "string" and n.name ~= "" and KNOWN[n.state] then
            local cont, wx, wy = Flights.ToWorld(corners, n.x, n.y)
            if cont ~= nil then
                into[n.name] = { cont = cont, wx = wx, wy = wy }
                written = written + 1
            end
        end
    end
    return into, written
end

local function point(p)
    return type(p) == "table" and p.cont ~= nil and finite(p.wx) and finite(p.wy)
end

function Flights.Pick(nodes, me, there, home, seconds, speed, rate)
    if not point(me) or not point(there) then return nil, "not known" end
    if me.cont ~= there.cont then return nil, "another continent" end
    if type(nodes) ~= "table" then return nil, "no flight points known" end
    local from, d1, bx, by
    local to, d2
    for name, n in pairs(nodes) do
        if type(name) == "string" and point(n) and n.cont == me.cont then
            local x, y = Flights.ToShare(home, n.wx, n.wy)
            if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                local d = dist(me.wx, me.wy, n.wx, n.wy)
                if not d1 or d < d1 or (d == d1 and name < from) then from, d1, bx, by = name, d, x, y end
            end
            local e = dist(there.wx, there.wy, n.wx, n.wy)
            if not d2 or e < d2 or (e == d2 and name < to) then to, d2 = name, e end
        end
    end
    if not from then return nil, "no flight point known on your map" end
    if not to then return nil, "no flight point known near the target" end
    if from == to then return nil, "the same flight point" end
    local fly, learned = nil, false
    if type(seconds) == "function" then
        local ok, sec = pcall(seconds, from, to)
        if ok and finite(sec) and sec > 0 then fly, learned = sec, true end
    end
    if not fly then
        local a, b = nodes[from], nodes[to]
        rate = finite(rate) and rate > 0 and rate or Flights.RATE
        fly = dist(a.wx, a.wy, b.wx, b.wy) / rate + Flights.OVERHEAD
    end
    speed = finite(speed) and speed > 0 and speed or Flights.RUN
    local walk = dist(me.wx, me.wy, there.wx, there.wy)
    local sec = (d1 + d2) / speed + fly
    if sec >= (walk / speed) * Flights.SAVES then return nil, "walking is about as quick" end
    return { from = from, to = to, x = bx, y = by, sec = sec, walk = walk, run = d2, learned = learned }
end

local NO_GAIN = { ["the same flight point"] = true, ["walking is about as quick"] = true }

function Flights.Explain(nodes, me, there, reason)
    if not point(me) or not point(there) or me.cont ~= there.cont then return nil end
    if NO_GAIN[reason] then return Flights.WALK end
    local from, d1, to, d2
    for name, n in pairs(type(nodes) == "table" and nodes or {}) do
        if type(name) == "string" and point(n) and n.cont == me.cont then
            local d = dist(me.wx, me.wy, n.wx, n.wy)
            if not d1 or d < d1 or (d == d1 and name < from) then from, d1 = name, d end
            local e = dist(there.wx, there.wy, n.wx, n.wy)
            if not d2 or e < d2 or (e == d2 and name < to) then to, d2 = name, e end
        end
    end
    if not from then return Flights.NONE end
    if from == to then return Flights.WALK end
    return Flights.ROUTE:format(from, to, math.floor(d2 + 0.5))
end

-- One read of the client, or nil when it has no such read or it fails.
local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if not ok then return nil end
    return v
end

function Flights.Declare(k)
    local api = {}
    local ctx

    local function get(scope, path)
        local ok, v = pcall(ctx.store.get, ctx.store, scope, path)
        if ok and type(v) == "table" then return v end
        return nil
    end

    local function learn()
        local read = ask(ctx.client, "taxiNodes")
        if type(read) ~= "table" or read.map == nil then return end
        local corners = ask(ctx.client, "mapCorners", read.map)
        local old = get("char", Flights.PATH)
        local into, written = Flights.Take(read, corners, old)
        if written == 0 then return end
        if old then
            -- The saved table itself is kept; each point written by key.
            for name, p in pairs(into) do old[name] = p end
        else
            ctx.store:set("char", Flights.PATH, into)
        end
    end

    function api.nodes()
        if not ctx then return nil end
        local saved = get("char", Flights.PATH)
        if not saved then return nil end
        local out = {}
        for name, p in pairs(saved) do
            if type(p) == "table" then out[name] = { cont = p.cont, wx = p.wx, wy = p.wy } end
        end
        return out
    end

    -- The flight of the last way that found one (section 187 section 7, for
    -- the taxiMark and mapFlights readers):
    --   { from, to, board = { map, x, y } (the step's place), there =
    --     { cont, wx, wy } (the target), points = the preview's points or nil,
    --     learned = true when the leg's time is your own (lead section 497) }
    -- nil after a way that found none. In memory only.
    local last

    local function points(known)
        local out = {}
        for name, p in pairs(known) do out[name] = { cont = p.cont, wx = p.wx, wy = p.wy } end
        return out
    end

    function api.last()
        if type(last) ~= "table" then return nil end
        return {
            from = last.from, to = last.to,
            board = { map = last.board.map, x = last.board.x, y = last.board.y },
            there = { cont = last.there.cont, wx = last.there.wx, wy = last.there.wy },
            points = last.points and points(last.points) or nil,
        }
    end

    function api.way(place)
        last = nil
        if not ctx then return nil, "not started" end
        if type(place) ~= "table" or place.map == nil or not finite(place.x) or not finite(place.y) then
            return nil, "no place"
        end
        local client = ctx.client
        local pos = ask(client, "position")
        if type(pos) ~= "table" or pos.map == nil then return nil, "not known where you are" end
        local home = ask(client, "mapCorners", pos.map)
        local cont, px, py = Flights.ToWorld(home, pos.x, pos.y)
        if cont == nil then return nil, "not known where you are" end
        local corners = place.map == pos.map and home or ask(client, "mapCorners", place.map)
        local tcont, tx, ty = Flights.ToWorld(corners, place.x, place.y)
        if tcont == nil then return nil, "the target is not placed in the world" end
        local times = get("account", Flights.TIMES)
        local seconds = function(from, to) return times and times[from .. ">" .. to] or nil end
        local okRate, rate = pcall(ctx.store.get, ctx.store, "account", Flights.RATE_PATH)
        if not okRate then rate = nil end
        local known = get("char", Flights.PATH)
        -- A travel preview (Nav/Try.lua, <slash> try flight): its made-up
        -- master and the target itself, in memory only, in place of the
        -- saved points. Nothing is saved.
        local okTry, try = pcall(function() return k.use and k.use("try") or nil end)
        local preview = false
        if okTry and type(try) == "table" and type(try.Flight) == "function" then
            local okMade, made = pcall(try.Flight)
            if okMade and type(made) == "table" and type(made.name) == "string" then
                local mc = made.map == pos.map and home or ask(client, "mapCorners", made.map)
                local mcont, mx, my = Flights.ToWorld(mc, made.x, made.y)
                if mcont ~= nil then
                    known = {
                        [made.name] = { cont = mcont, wx = mx, wy = my },
                        [(N.Try and N.Try.LAND_NAME) or "the made-up landing"] = { cont = tcont, wx = tx, wy = ty },
                    }
                    preview = true
                end
            end
        end
        local me, there = { cont = cont, wx = px, wy = py }, { cont = tcont, wx = tx, wy = ty }
        local pick, reason = Flights.Pick(known, me, there, home, seconds, Flights.RUN, rate)
        if not pick then
            -- Lead section 286: a far goal says why there is no flight.
            local far = place.map ~= pos.map or dist(px, py, tx, ty) > Flights.FAR
            if not far or preview then return nil, reason end
            return nil, reason, Flights.Explain(known, me, there, reason)
        end
        last = {
            from = pick.from, to = pick.to,
            board = { map = pos.map, x = pick.x, y = pick.y },
            there = { cont = tcont, wx = tx, wy = ty },
            points = preview and points(known) or nil,
            learned = pick.learned == true,
        }
        return {
            kind = Flights.KIND,
            label = Flights.LABEL:format(pick.to),
            place = { cont = cont, map = pos.map, x = pick.x, y = pick.y },
            radius = Flights.NEAR,
            hint = Flights.ROUTE:format(pick.from, pick.to, math.floor(pick.run + 0.5)),
        }
    end

    k:Module({
        name = Flights.NAME,
        needs = { "client", "store", "bus" },
        provides = {
            Way = function(place) return api.way(place) end,
            Nodes = function() return api.nodes() end,
            Last = function() return api.last() end,
        },
        start = function(c)
            ctx = c
            c.bus:on(Flights.NAME, "TAXIMAP_OPENED", function() learn() end)
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.flights = Flights.Declare(ns, ns.diag)
