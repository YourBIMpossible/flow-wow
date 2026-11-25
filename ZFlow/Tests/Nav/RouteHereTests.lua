local _, ns = ...
-- A2-20 (lead section 674): the tracker's "here" mode, data half
-- (Nav/RouteHere.lua). Ported from legacy Flow's rule (origin/buff-fishing-prof-path
-- Modules/Nav/Nav.lua:1405-1435, N.HereStops, N.HERE_YARDS = 150): the next step, and every step
-- within the yards of the player or of the next step, in route order.
-- Made-up stops and places; not tested in game.

local tests = {}

local function RH() return ns.Nav.RouteHere end

-- A 1000 x 1000 yard map: a share of 0.1 is 100 yards.
local HERE = { map = 1, x = 0.5, y = 0.5, size = { w = 1000, h = 1000 } }

local function stop(label, map, x, y, area)
    return { label = label, place = { map = map, x = x, y = y }, area = area }
end

local function labels(list)
    local out = {}
    for i, s in ipairs(list) do out[i] = s.label end
    return table.concat(out, ",")
end

tests["route here: the next step is always here"] = function(t)
    local list = RH().Stops({ stop("far", 1, 0.9, 0.9) }, HERE)
    t.eq(labels(list), "far")
end

tests["route here: steps near the player or the next step, in route order"] = function(t)
    local stops = {
        stop("next", 1, 0.9, 0.9),        -- far from the player, always here
        stop("away", 1, 0.1, 0.1),        -- 565 yards from both
        stop("byMe", 1, 0.55, 0.5),       -- 50 yards from the player
        stop("byNext", 1, 0.95, 0.9),     -- 50 yards from the next step
    }
    t.eq(labels(RH().Stops(stops, HERE)), "next,byMe,byNext")
end

tests["route here: the yards edge is inside, one past it is not"] = function(t)
    local stops = { stop("next", 1, 0.5, 0.5), stop("edge", 1, 0.5, 0.35), stop("past", 1, 0.5, 0.849) }
    local list = RH().Stops(stops, { map = 1, x = 0.5, y = 0.2, size = { w = 1000, h = 1000 } })
    -- edge: 150 yards from the player; past: 349 from the next step and 649 from the player
    t.eq(labels(list), "next,edge")
    t.eq(RH().YARDS, 150, "Flow's N.HERE_YARDS")
end

tests["route here: a step on another map is not here"] = function(t)
    local stops = { stop("next", 1, 0.5, 0.5), stop("other", 2, 0.5, 0.5) }
    t.eq(labels(RH().Stops(stops, HERE)), "next")
end

tests["route here: an area point near the player counts"] = function(t)
    local area = { { map = 1, x = 0.1, y = 0.1 }, { map = 1, x = 0.52, y = 0.5 } }
    local stops = { stop("next", 1, 0.9, 0.9), stop("roam", 1, 0.1, 0.1, area) }
    t.eq(labels(RH().Stops(stops, HERE)), "next,roam")
end

tests["route here: with no map size nothing is measured, only the next step"] = function(t)
    local stops = { stop("next", 1, 0.5, 0.5), stop("byMe", 1, 0.5, 0.5) }
    t.eq(labels(RH().Stops(stops, { map = 1, x = 0.5, y = 0.5 })), "next")
end

tests["route here: no player position still measures from the next step"] = function(t)
    local stops = { stop("next", 1, 0.5, 0.5), stop("byNext", 1, 0.52, 0.5), stop("away", 1, 0.1, 0.1) }
    t.eq(labels(RH().Stops(stops, { map = 1, size = { w = 1000, h = 1000 } })), "next,byNext")
end

tests["route here: nothing planned is an empty list"] = function(t)
    t.eq(#RH().Stops(nil, HERE), 0)
    t.eq(#RH().Stops({}, HERE), 0)
    t.eq(#RH().Stops({ stop("next", 1, 0.5, 0.5) }, nil), 1)
end

tests["route here: the list is copies, the stops are not changed"] = function(t)
    local s = stop("next", 1, 0.5, 0.5)
    local list = RH().Stops({ s }, HERE)
    list[1].label = "changed"
    t.eq(s.label, "next")
    t.eq(list[1].index, 1, "each carries its place on the route")
end

return tests
