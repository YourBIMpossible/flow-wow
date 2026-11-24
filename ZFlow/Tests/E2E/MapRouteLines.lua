local _, ns = ...
-- F7 end to end: the whole add-on on a fake client. With the world map
-- open and a waypoint set, a green line runs from you to the waypoint.
-- Look only: nothing is moved, targeted or clicked. Fake client lines, not
-- the game frame. Not tested in game.
--
-- Red before the code: the add-on draws no lines on the map.
local tests = {}

tests["e2e: the open world map shows a green line to your waypoint"] = function(t)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.setWorldMap(1)
    c.setPosition(1, 0.2, 0.2)
    c.setWaypoint(1, 0.7, 0.4)
    c.advance(5, 20)
    local set = type(c.routeLineSets) == "table" and c.routeLineSets[1] or nil
    t.ok(set ~= nil, "the add-on asks for map lines")
    -- Pathing UI slice 3: the line is a dotted trail; its last dot ends just
    -- short of the waypoint.
    local found = nil
    for _, l in ipairs(set and set.lines or {}) do
        if l.kind == "waypoint" then found = l end
    end
    t.ok(found ~= nil, "a waypoint trail is drawn")
    t.ok(found ~= nil and found.bx <= 0.7 and found.bx > 0.65, "it runs to the waypoint: " .. tostring(found and found.bx))
    t.eq(found and found.g, 1)
end

return tests
