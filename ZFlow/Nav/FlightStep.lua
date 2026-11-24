local _, ns = ...
-- Z-Flow "learn the flight path" on the quest arrow and the route (S30):
-- Nav/FlightPaths.lua works out which flight masters the player has passed
-- and not yet talked to, and gives a step for the nearest; nothing walked
-- the player to it. This puts that step on the quest arrow while the
-- master is a short detour away, and says it under the route word's list.
-- LOOK ONLY: a needle and lines. Nobody is targeted or talked to, no
-- flight is taken. No place data is authored here: the masters are the
-- ones the player's own play has recorded.
--
-- Pure:
--   S.Pick(goals, within) -> the nearest goal on your map whose distance
--     is known and at most `within` yards, or nil
--   S.Of(goal, zone)      -> the arrow's step for it
--   S.Line(goal)          -> the route word's line for it
-- Module "flightStep" provides Step (within S.DETOUR) and Line (within
-- ns.FlightPaths.HERE). Setting: nav.flightPaths (Nav/FlightPaths.lua
-- gives no goals with it off).
-- Not tested in game.
ns.Nav = ns.Nav or {}
local N = ns.Nav
local S = {}
N.FlightStep = S

S.NAME = "flightStep"
S.DETOUR = 150           -- yards: this close, the arrow points at the master first
S.FROM = "a flight path to learn"
S.LABEL = "Learn the flight path: %s"
S.LABEL_SHORT = "Learn the flight path"
S.DETAIL = "Talk to %s once. It is free."
S.LINE = "Close by: learn the flight path from %s, about %d yards away. It is free."

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function S.Pick(goals, within)
    if type(goals) ~= "table" or not finite(within) then return nil end
    local best
    for _, g in ipairs(goals) do
        if type(g) == "table" and type(g.name) == "string" and g.name ~= "" and type(g.place) == "table"
            and finite(g.yards) and g.yards >= 0 and g.yards <= within
            and (best == nil or g.yards < best.yards) then
            best = g
        end
    end
    return best
end

function S.Of(goal, zone)
    if type(goal) ~= "table" or type(goal.place) ~= "table" or type(goal.name) ~= "string" then return nil end
    local max = N.Waypoint and N.Waypoint.LABEL_MAX or 40
    local label = S.LABEL:format(goal.name)
    local step = {
        kind = "flight",
        place = { cont = type(zone) == "table" and zone.cont or nil,
                  map = goal.place.map, x = goal.place.x, y = goal.place.y },
        radius = ns.FlightPaths and ns.FlightPaths.NEAR or 10,
        label = #label <= max and label or S.LABEL_SHORT,
        detail = S.DETAIL:format(goal.name),
    }
    return step
end

function S.Line(goal)
    if type(goal) ~= "table" or type(goal.name) ~= "string" or not finite(goal.yards) then return nil end
    -- To the nearest ten: the place is a recorded one, not exact.
    return S.LINE:format(goal.name, math.floor(goal.yards / 10 + 0.5) * 10)
end

function S.Declare(k)
    local api = {}
    local ctx

    local function goals()
        local FP = ns.FlightPaths
        if not ctx or not FP then return nil end
        local ok, flights = pcall(ctx.use, FP.NAME)
        if not ok or type(flights) ~= "table" or type(flights.Goals) ~= "function" then return nil end
        local fine, got = pcall(flights.Goals)
        return fine and got or nil
    end

    local function zone()
        local c = ctx and ctx.client
        if type(c) ~= "table" or type(c.zone) ~= "function" then return nil end
        local ok, z = pcall(c.zone)
        return ok and z or nil
    end

    function api.Step()
        local goal = S.Pick(goals(), S.DETOUR)
        if not goal then return nil end
        return S.Of(goal, zone())
    end

    function api.Line()
        local FP = ns.FlightPaths
        return S.Line(S.Pick(goals(), FP and FP.HERE or 800))
    end

    k:Module({
        name = S.NAME,
        needs = { "client" },
        provides = { Step = api.Step, Line = api.Line },
        start = function(c) ctx = c end,
        stop = function() ctx = nil end,
    })
    return api
end

-- The addon's own: declared when this file loads. It gives nothing until a
-- flight master the player has not talked to is close.
ns.flightStep = S.Declare(ns)
