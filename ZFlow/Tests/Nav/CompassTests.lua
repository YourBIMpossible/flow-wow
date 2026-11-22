-- The compass word for a bearing (G40): one of eight points, said beside
-- the distance on an arrow. Pure: no game client.
local _, ns = ...

local N = ns.Nav
local PI = math.pi

local T = {}

T["compass: the eight points, each at its own bearing"] = function(t)
    local want = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
    t.eq(N.COMPASS, want)
    for i = 1, 8 do
        t.eq(N.Compass((i - 1) * PI / 4), want[i], want[i])
    end
end

T["compass: each point takes the eighth of the circle around it"] = function(t)
    t.eq(N.Compass(PI / 8 - 0.01), "N")
    t.eq(N.Compass(PI / 8 + 0.01), "NE")
    t.eq(N.Compass(2 * PI - 0.01), "N", "just west of north is north")
    t.eq(N.Compass(2 * PI - PI / 8 - 0.01), "NW")
    t.eq(N.Compass(PI + 0.2), "S")
    t.eq(N.Compass(3 * PI / 2 - 0.2), "W")
end

T["compass: a bearing outside one turn is taken round"] = function(t)
    t.eq(N.Compass(2 * PI), "N")
    t.eq(N.Compass(2 * PI + PI / 2), "E")
    t.eq(N.Compass(-PI / 2), "W")
end

T["compass: no bearing, no word"] = function(t)
    t.eq(N.Compass(nil), nil)
    t.eq(N.Compass("north"), nil)
    t.eq(N.Compass(0 / 0), nil)
    t.eq(N.Compass(math.huge), nil)
end

T["compass: the guide says it for each step, and needs no facing for it"] = function(t)
    local s = N.Guide({
        position = { map = 1411, x = 0.5, y = 0.5 }, zone = { cont = 1, zone = 1411 },
        link = { [1411] = { w = 1000, h = 500 } },
        quest = { place = { cont = 1, map = 1411, x = 0.5, y = 0.3 } },
        prof = { place = { cont = 1, map = 1411, x = 0.4, y = 0.7 } },
    })
    t.eq(s.facingKnown, false)
    t.eq(s.quest.compass, "N")
    t.eq(s.prof.compass, "SW", "100 yd west and 100 yd south")
    t.eq(s.quest.bearing, nil, "the bearing itself is still not handed on")
end

T["compass: none where there is no distance, and none at the very spot"] = function(t)
    local s = N.Guide({
        position = { map = 1411, x = 0.5, y = 0.5 }, zone = { cont = 1, zone = 1411 }, facing = 0,
        link = { [1411] = { w = 1000, h = 500 } },
        quest = { place = { cont = 1, map = 1411, x = 0.5, y = 0.5 } },
        prof = { place = { cont = 1, map = 1412, x = 0.5, y = 0.5 } },
    })
    t.eq(s.quest.distance, 0)
    t.eq(s.quest.compass, nil, "no direction to the spot the player is on")
    t.eq(s.prof.distance, nil)
    t.eq(s.prof.compass, nil)
end

return T
