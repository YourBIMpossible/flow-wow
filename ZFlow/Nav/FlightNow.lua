local _, ns = ...
-- Z-Flow: the arrow's words while on a flight (parity row A1-18, lead
-- section 481): where the flight lands, and in how long, from the time this
-- path took last (Nav/FlightTimes.lua). A path never flown whole stays
-- "landing time not known yet": nothing is guessed from the distance.
--   take-off  client.onTaxi() goes false -> true: from = the saved flight
--             point nearest where the player stands (FlightTimes.Nearest),
--             to = the flight the route planned from there (flights
--             Last(), when its from is this point), else not known.
--   on board  Now(nextText) -> { title, sub }; on the ground or before a
--             take-off was seen (a flight under way at login): nil.
-- UI/Arrow.lua shows the two lines on the quest arrow (the lead-owned hook).
-- Compared with Flow Modules/Nav/Nav.lua N.FlightWords, N.FlightNow and
-- N.TaxiLeft: the same words; Flow also guesses an unknown time from the
-- distance (N.FlightSeconds) and finds where a ride with no flight map
-- lands (Rides.lua). Neither is done here.
-- LOOK ONLY: nothing is clicked, flown or targeted. Not tested in game.
--
-- Pure:
--   FN.Left(times, from, to, start, now) -> seconds to landing, or nil
--   FN.Words(to, left, nextText) -> title, sub
-- Module "flightNow" provides Now(nextText) -> { title, sub } or nil.
ns.Nav = ns.Nav or {}
local N = ns.Nav
local FN = {}
N.FlightNow = FN

FN.NAME = "flightNow"
FN.EVERY = 1

FN.TO = "Flying to %s"
FN.ON = "On a flight"
FN.LANDING = "landing in %s"
FN.UNKNOWN = "landing time not known yet"
FN.THEN = "%s, then: %s"

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- Flow N.FormatSeconds: "~50s", "~1m 10s", "~1h 05m".
function FN.Format(sec)
    sec = math.max(1, math.floor(sec + 0.5))
    if sec < 60 then return ("~%ds"):format(sec) end
    if sec < 3600 then return ("~%dm %02ds"):format(math.floor(sec / 60), sec % 60) end
    return ("~%dh %02dm"):format(math.floor(sec / 3600), math.floor(sec % 3600 / 60))
end

function FN.Left(times, from, to, start, now)
    if type(times) ~= "table" or from == nil or to == nil then return nil end
    local total = times[tostring(from) .. ">" .. tostring(to)]
    if not finite(total) or total <= 0 or not finite(start) or not finite(now) then return nil end
    return math.max(1, total - (now - start))
end

function FN.Words(to, left, nextText)
    local title = (type(to) == "string" and to ~= "") and FN.TO:format(to) or FN.ON
    local sub = finite(left) and FN.LANDING:format(FN.Format(left)) or FN.UNKNOWN
    if type(nextText) == "string" and nextText ~= "" then sub = FN.THEN:format(sub, nextText) end
    return title, sub
end

function FN.Declare(k)
    local api = {}
    local ctx
    local wasOn
    local trip

    local function ask(name)
        local c = ctx and ctx.client
        if type(c) ~= "table" or type(c[name]) ~= "function" then return nil end
        local ok, v = pcall(c[name])
        if ok then return v end
        return nil
    end

    local function flights()
        local F = N.Flights
        local ok, mod = pcall(ctx.use, F and F.NAME or "flights")
        if ok and type(mod) == "table" then return mod end
        return nil
    end

    local function here()
        local mod, T = flights(), N.FlightTimes
        if not mod or type(mod.Nodes) ~= "function" or not T then return nil end
        local ok, nodes = pcall(mod.Nodes)
        if not ok then return nil end
        return T.Nearest(nodes, ask("worldPosition"))
    end

    local function planned(from)
        local mod = flights()
        if not mod or type(mod.Last) ~= "function" or from == nil then return nil end
        local ok, last = pcall(mod.Last)
        if ok and type(last) == "table" and last.from == from and last.to ~= from then return last.to end
        return nil
    end

    local function tick()
        local on = ask("onTaxi")
        if on == nil then return end
        if on and wasOn == false then
            local from = here()
            trip = { from = from, to = planned(from), start = ask("now") }
        elseif not on then
            trip = nil
        end
        wasOn = on
    end

    function api.Now(nextText)
        if not ctx or not trip or ask("onTaxi") ~= true then return nil end
        local times
        local F = N.Flights
        local ok, v = pcall(ctx.store.get, ctx.store, "account", F and F.TIMES or "learned.flights.times")
        if ok then times = v end
        local left = FN.Left(times, trip.from, trip.to, trip.start, ask("now"))
        local title, sub = FN.Words(trip.to, left, nextText)
        return { title = title, sub = sub }
    end

    k:Module({
        name = FN.NAME,
        needs = { "client", "store" },
        provides = { Now = function(nextText) return api.Now(nextText) end },
        ticks = { { every = FN.EVERY, when = "always", run = function() tick() end } },
        start = function(c) ctx = c end,
        stop = function() ctx = nil; wasOn = nil; trip = nil end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.flightNow = FN.Declare(ns)
