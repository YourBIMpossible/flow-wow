local _, ns = ...
-- Z-Flow: the arrow's words while on a flight (parity row A1-18, lead
-- section 481).
-- KNOWN: the player is on a flight (client.onTaxi()), and the saved flight
--   point nearest where the take-off was seen (FlightTimes.Nearest).
-- ADVICE, not a fact: where the flight lands. The player picks the
--   destination on the flight map and there is no read of that pick. All
--   there is: the flight the route advised last (flights Last()), used
--   when its from is the take-off point. The player may have picked
--   another, so it is said as the route's flight, never as "Flying to
--   <place>", and the time that path took last (Nav/FlightTimes.lua) is
--   said whole with "if that is yours": no countdown, which would read as
--   certain. A path never flown whole says no time; with no advised flight
--   from here the words are "landing time not known yet". Nothing is
--   guessed from the distance or from the way the player moves.
-- CLIENT REQUEST (for the lead; Core/Client.lua is not edited here): a
--   read of the destination the player picked on the flight map, giving
--   the node name, or nil when not known. Flow hooked TakeTaxiNode with a
--   post-hook: a read of the player's own click, nothing is clicked for
--   them. Until that read exists no words here may say "Flying to": there
--   is no such constant and FN.Words takes no known destination.
--   take-off  client.onTaxi() goes false -> true: from = the nearest saved
--             flight point, advised = the route's flight from there, or nil.
--   on board  Now(nextText) -> { title, sub }; on the ground or before a
--             take-off was seen (a flight under way at login): nil.
-- UI/Arrow.lua shows the two lines on the quest arrow (the lead-owned hook).
-- Compared with Flow Modules/Nav/Nav.lua N.FlightWords, N.FlightNow and
-- N.TaxiLeft: Flow knows the picked destination (its TakeTaxiNode hook) and
-- says "Flying to <place>, landing in <time>"; it also guesses an unknown
-- time from the distance (N.FlightSeconds) and finds where a ride with no
-- flight map lands (Rides.lua). None of that is done here.
-- LOOK ONLY: nothing is clicked, flown or targeted. Not tested in game.
--
-- Pure:
--   FN.Total(times, from, to) -> seconds that path took last, or nil
--   FN.Words(advised, total, nextText) -> title, sub
-- Module "flightNow" provides Now(nextText) -> { title, sub } or nil.
ns.Nav = ns.Nav or {}
local N = ns.Nav
local FN = {}
N.FlightNow = FN

FN.NAME = "flightNow"
FN.EVERY = 1

FN.ON = "On a flight"
FN.ADVISED = "The route's flight from here goes to %s"
FN.IF_YOURS = "%s, %s if that is yours"
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

function FN.Total(times, from, to)
    if type(times) ~= "table" or from == nil or to == nil then return nil end
    local total = times[tostring(from) .. ">" .. tostring(to)]
    if not finite(total) or total <= 0 then return nil end
    return total
end

-- advised: where the route's flight from the take-off point goes, or nil;
-- total: the seconds that path took last, or nil. The title never names a
-- place, and a time is only said beside the advised flight it belongs to.
function FN.Words(advised, total, nextText)
    local sub = FN.UNKNOWN
    if type(advised) == "string" and advised ~= "" then
        sub = FN.ADVISED:format(advised)
        if finite(total) then sub = FN.IF_YOURS:format(sub, FN.Format(total)) end
    end
    if type(nextText) == "string" and nextText ~= "" then sub = FN.THEN:format(sub, nextText) end
    return FN.ON, sub
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

    -- The route's advice only: not where the player is flying.
    local function advised(from)
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
            trip = { from = from, advised = advised(from) }
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
        local title, sub = FN.Words(trip.advised, FN.Total(times, trip.from, trip.advised), nextText)
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
