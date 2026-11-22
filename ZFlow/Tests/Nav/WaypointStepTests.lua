-- The quest step made from the player's own map waypoint, over the fake
-- client. No game client is involved.
local _, ns = ...

local N = ns.Nav

local function start()
    local c = ns.make.fakeClient()
    c.setZone(1, 1411)
    c.setFacing(0)
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    return c
end

return {
    ["the label is Waypoint"] = function(t)
        t.eq(N.WAYPOINT_LABEL, "Waypoint")
    end,

    ["absent API: a client with no waypoint read gives no step"] = function(t)
        local c = start()
        c.waypoint = nil
        t.eq(N.WaypointStep(c), nil)
        t.eq(N.WaypointStep(ns.make.client({})), nil, "the real client over an empty environment")
        t.eq(N.WaypointStep(nil), nil)
        t.eq(N.WaypointStep("client"), nil)
    end,

    ["no waypoint: no step"] = function(t)
        local c = start()
        t.eq(N.WaypointStep(c), nil)
        c.setWaypoint(1411, 0.3, 0.6)
        c.setWaypoint(nil)
        t.eq(N.WaypointStep(c), nil, "cleared again")
    end,

    ["waypoint set: the step the guide source takes"] = function(t)
        local c = start()
        c.setWaypoint(1411, 0.3, 0.5)
        t.eq(N.WaypointStep(c), {
            label = "Waypoint",
            place = { cont = 1, map = 1411, x = 0.3, y = 0.5 },
        })
    end,

    ["waypoint set: ViewState reads the step as a place 200 yards west"] = function(t)
        local c = start()
        c.setWaypoint(1411, 0.3, 0.5)
        local state, more = N.ViewState(c, { quest = N.WaypointStep(c) })
        t.ok(type(state.quest.distance) == "number" and math.abs(state.quest.distance - 200) < 1e-6,
            "distance (got " .. tostring(state.quest.distance) .. ")")
        t.eq(more.quest.label, "Waypoint")
    end,

    ["waypoint on another map: the place has no continent, and no distance or turn (W1, W2)"] = function(t)
        local c = start()
        c.setMapSize(1412, 2000, 1000)
        c.setWaypoint(1412, 0.5, 0.5)
        local step = N.WaypointStep(c)
        t.eq(step, { label = "Waypoint", place = { map = 1412, x = 0.5, y = 0.5 } },
            "the player's continent is not given to a map the player is not on")
        local state, more = N.ViewState(c, { quest = step })
        t.eq(state.quest.distance, nil, "no distance from a guessed offset")
        t.eq(more.quest.turn, nil, "no turn from a guessed offset")
        t.eq(more.quest.why, "zone")
    end,

    ["waypoint set, zone unknown: the place has no continent"] = function(t)
        local c = ns.make.fakeClient()
        c.setWaypoint(1411, 0.3, 0.5)
        t.eq(N.WaypointStep(c), { label = "Waypoint", place = { map = 1411, x = 0.3, y = 0.5 } })
        c.zone = function() error("the client refused") end
        t.eq(N.WaypointStep(c), { label = "Waypoint", place = { map = 1411, x = 0.3, y = 0.5 } })
        c.zone = function() return "nowhere" end
        t.eq(N.WaypointStep(c), { label = "Waypoint", place = { map = 1411, x = 0.3, y = 0.5 } })
    end,

    ["a malformed answer: no step"] = function(t)
        local c = start()
        local bad = {
            "a string", 7, true, {},
            { map = 1411 },
            { x = 0.5, y = 0.5 },
            { map = 1411, x = "left", y = 0.5 },
            { map = 1411, x = 0.5 },
            { map = 1411, x = 0 / 0, y = 0.5 },
            { map = 1411, x = 0.5, y = math.huge },
        }
        for i = 1, #bad do
            c.waypoint = function() return bad[i] end
            t.eq(N.WaypointStep(c), nil, "malformed answer " .. i)
        end
    end,

    ["a failing read: no step"] = function(t)
        local c = start()
        c.waypoint = function() error("the client refused") end
        t.eq(N.WaypointStep(c), nil)
    end,

    ["a fresh table each time; the client's answer is not handed out"] = function(t)
        local c = start()
        local answer = { map = 1411, x = 0.3, y = 0.5 }
        c.waypoint = function() return answer end
        local a, b = N.WaypointStep(c), N.WaypointStep(c)
        t.ok(a ~= b and a.place ~= b.place, "two calls, two tables")
        a.place.x = 9
        t.eq(answer.x, 0.3)
        t.eq(N.WaypointStep(c).place.x, 0.3)
    end,
}
