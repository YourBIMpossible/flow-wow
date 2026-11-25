local _, ns = ...
-- Z-Flow: learned flight times (parity row A1-32, lead section 477). Each
-- flight is timed from take-off to landing and kept per path, as seconds,
-- in account "learned.flights.times" ({ ["from>to"] = seconds }), the table
-- Nav/Flights.lua and Nav/TaxiMark.lua already read (until now filled only
-- by the import). `<slash> flights` lists them. A path never flown stays
-- unknown: nothing is guessed into the table.
--   take-off  client.onTaxi() goes false -> true: from = the saved flight
--             point (Flights.Nodes) nearest where the player stands, start =
--             client.now().
--   landing   client.onTaxi() goes true -> false: to = the saved point
--             nearest where the player stands.
--   kept      only with both ends known, from ~= to, a take-off seen (not a
--             flight already under way at login, "unknown" first read) and
--             MIN < seconds < MAX; else nothing is written.
-- Compared with Flow Modules/Nav/Nav.lua: flightTimes[from..">"..to] =
-- whole seconds, per account; recorded on PLAYER_CONTROL_GAINED off the
-- taxi, not for a partial trip, elapsed > 5, dropped past TAXI_MAX 1200 s.
-- Flow names its ends from the taxi map pick; here they are the nearest
-- saved points, so a flight with no saved point near an end is not kept.
-- LOOK ONLY: nothing is clicked, flown or targeted. Not tested in game.
--
-- Pure:
--   T.Nearest(nodes, at) -> name or nil   (same continent, within NEAR yards)
--   T.Lines(times)       -> the word's lines, by path name; {} with none
--                           (no time is shown for a path never flown)
-- Module "flightTimes" provides Known() (a copy of the saved times, or nil).
ns.Nav = ns.Nav or {}
local N = ns.Nav
local T = {}
N.FlightTimes = T

T.NAME = "flightTimes"
T.EVERY = 1         -- seconds between reads of onTaxi
T.MIN = 5           -- seconds: shorter is not a flight (Flow: elapsed > 5)
T.MAX = 1200        -- seconds: longer is dropped (Flow: TAXI_MAX)
T.NEAR = 80         -- yards from a saved point that count as at it
T.SHOWN = 8         -- times listed at most

T.HEADER = "Flight times you have flown:"
T.LINE = "  %s to %s: %d s (your last flight)"
T.MORE = "  and %d more"

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function T.Nearest(nodes, at)
    if type(nodes) ~= "table" or type(at) ~= "table" or at.cont == nil then return nil end
    if not finite(at.wx) or not finite(at.wy) then return nil end
    local best, bestD
    for name, p in pairs(nodes) do
        if type(p) == "table" and p.cont == at.cont and finite(p.wx) and finite(p.wy) then
            local d = math.sqrt((p.wx - at.wx) ^ 2 + (p.wy - at.wy) ^ 2)
            if d <= T.NEAR and (not bestD or d < bestD or (d == bestD and name < best)) then
                best, bestD = name, d
            end
        end
    end
    return best
end

function T.Lines(times)
    local rows = {}
    for key, s in pairs(type(times) == "table" and times or {}) do
        local from, to
        if type(key) == "string" then from, to = key:match("^(.+)>(.+)$") end
        if from and finite(s) and s > 0 then rows[#rows + 1] = { from = from, to = to, s = s } end
    end
    if #rows == 0 then return {} end
    table.sort(rows, function(a, b)
        if a.from ~= b.from then return a.from < b.from end
        return a.to < b.to
    end)
    local lines = { T.HEADER }
    for i = 1, math.min(#rows, T.SHOWN) do
        local r = rows[i]
        lines[#lines + 1] = T.LINE:format(r.from, r.to, math.floor(r.s + 0.5))
    end
    if #rows > T.SHOWN then lines[#lines + 1] = T.MORE:format(#rows - T.SHOWN) end
    return lines
end

function T.Declare(k)
    local api = {}
    local ctx
    -- nil: not read yet (a flight under way at the first read is partial);
    -- false / true: the last plain read.
    local wasOn
    local trip

    local function ask(name)
        local c = ctx and ctx.client
        if type(c) ~= "table" or type(c[name]) ~= "function" then return nil end
        local ok, v = pcall(c[name])
        if ok then return v end
        return nil
    end

    local function at()
        local F = N.Flights
        local ok, flights = pcall(ctx.use, F and F.NAME or "flights")
        if not ok or type(flights) ~= "table" or type(flights.Nodes) ~= "function" then return nil end
        local fine, nodes = pcall(flights.Nodes)
        if not fine then return nil end
        return T.Nearest(nodes, ask("worldPosition"))
    end

    local function path()
        local F = N.Flights
        return F and F.TIMES or "learned.flights.times"
    end

    local function keep(from, to, seconds)
        -- A copy written back through store:set, never the stored table
        -- changed in place.
        local ok, times = pcall(ctx.store.get, ctx.store, "account", path())
        local copy = {}
        if ok and type(times) == "table" then
            for k2, v in pairs(times) do copy[k2] = v end
        end
        copy[from .. ">" .. to] = math.floor(seconds + 0.5)
        -- A write that fails is said, never lost without a word (Zen's
        -- review, lead section 609; as Nav/TripRoute.lua keeps its route).
        local okSet, done, why = pcall(ctx.store.set, ctx.store, "account", path(), copy)
        if not okSet then
            k.problems:add(T.NAME, "keep", tostring(done))
        elseif done == false then
            k.problems:add(T.NAME, "keep", tostring(why))
        end
    end

    local function tick()
        local on = ask("onTaxi")
        if on == nil then return end
        if on and wasOn == false then
            local now = ask("now")
            trip = finite(now) and { from = at(), start = now } or nil
        elseif not on and wasOn and trip then
            local now, to = ask("now"), at()
            local seconds = finite(now) and now - trip.start or nil
            if trip.from and to and to ~= trip.from and seconds and seconds > T.MIN and seconds < T.MAX then
                keep(trip.from, to, seconds)
            end
            trip = nil
        end
        wasOn = on
    end

    function api.Known()
        if not ctx then return nil end
        local ok, times = pcall(ctx.store.get, ctx.store, "account", path())
        if not ok or type(times) ~= "table" then return nil end
        local out = {}
        for key, s in pairs(times) do out[key] = s end
        return out
    end

    k:Module({
        name = T.NAME,
        needs = { "client", "store" },
        provides = { Known = function() return api.Known() end },
        ticks = { { every = T.EVERY, when = "always", run = function() tick() end } },
        start = function(c) ctx = c end,
        stop = function() ctx = nil; wasOn = nil; trip = nil end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.flightTimes = T.Declare(ns)
