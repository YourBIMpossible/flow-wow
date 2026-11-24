local _, ns = ...
-- Z-Flow: the "Quicker by air" route line (parity row A1-19, lead section
-- 488). When the arrow's step is reached by a flight, one line names it.
-- The flight is Nav/TaxiMark.lua's StepFlight (read, not changed); the
-- mapFlights module (Nav/MapFlights.lua) gives the line as AirLine().
-- Not here yet: a caller. The arrow's route lines are a later hook; until
-- then the player sees nothing new.
-- Only when the leg's time was learned (lead section 497: flight.learned,
-- Nav/Flights.lua Last(); the times are A1-32's): a guessed time says
-- nothing, so an unknown stays unknown.
-- Compared with Flow Modules/Nav/Nav.lua (N.AirRoute's route line):
-- "Quicker by air: fly from %s to %s." The same words.
-- Not tested in game.
--
-- Pure:
--   AL.Words(flight) -> the line, or nil without both names or without
--                       flight.learned == true
ns.Nav = ns.Nav or {}
local N = ns.Nav
local AL = {}
N.AirLine = AL

-- Player-visible words, from Flow.
AL.TEXT = "Quicker by air: fly from %s to %s."

local function name(v)
    return type(v) == "string" and v ~= ""
end

function AL.Words(flight)
    if type(flight) ~= "table" or not (name(flight.from) and name(flight.to)) then return nil end
    if flight.from == flight.to or flight.learned ~= true then return nil end
    return AL.TEXT:format(flight.from, flight.to)
end
