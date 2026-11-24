local _, ns = ...

-- N43 (P-TRIP route display): the current step's area on the minimap. A
-- quest stop keeps the points of its spot on the map (Nav/TripRoute.lua
-- T.Stops, area); UI/RouteArea.lua shows them with the existing minimap
-- pin (client.minimapPin), one pin per point on the minimap, or the
-- nearest at the rim when none is on it. A step of one point has no area:
-- nothing. Over the fake client; made-up places. Not tested in game.

local tests = {}

local function RA() return ns.RouteArea end
local function T() return ns.Nav.TripRoute end

local HERE = { map = 1, x = 0.5, y = 0.5, size = { w = 1000, h = 1000 } }

local function area(...)
    local out = {}
    for i, p in ipairs({ ... }) do out[i] = { map = 1, x = p[1], y = p[2] } end
    return out
end

local function cur(points)
    return { kind = "quests", stops = { { label = "Boars", place = points[1], area = points } } }
end

local function client()
    local c = ns.make.fakeClient()
    c.setPosition(1, 0.5, 0.5)
    c.setMapSize(1, 1000, 1000)
    c.setFacing(0)
    c.setMinimap({ size = 140, radius = 100, rotates = false })
    return c
end

local function shown(c)
    local n = 0
    for _, h in ipairs(c.minimapPins) do if h.shown then n = n + 1 end end
    return n
end

local function oneRow()
    return { { id = 1, title = "Boars", complete = false, failed = false,
               objectives = { { text = "Boars: 0/4", done = false } } } }
end

tests["route area: a quest stop keeps its spot's points on this map, the nearest first"] = function(t)
    local places = { [1] = { objectives = { [1] = { points = {
        { map = 1, x = 0.9, y = 0.9 }, { map = 1, x = 0.6, y = 0.5 }, { map = 2, x = 0.5, y = 0.5 } } } } } }
    local stops = T().Stops(oneRow(), places, HERE)
    t.eq(#stops, 1)
    t.eq(stops[1].area, { { map = 1, x = 0.6, y = 0.5 }, { map = 1, x = 0.9, y = 0.9 } })
end

tests["route area: no more than T.AREA_MAX points are kept"] = function(t)
    local many = {}
    for i = 1, T().AREA_MAX + 5 do many[i] = { map = 1, x = i / 100, y = 0.5 } end
    local stops = T().Stops(oneRow(), { [1] = { objectives = { [1] = { points = many } } } }, HERE)
    t.eq(#stops[1].area, T().AREA_MAX)
end

tests["route area: the points of the current step, only when it is an area"] = function(t)
    local pts = area({ 0.52, 0.5 }, { 0.5, 0.52 })
    t.eq(RA().Points(cur(pts)), pts)
    t.eq(RA().Points(cur(area({ 0.52, 0.5 }))), nil, "one point is no area")
    t.eq(RA().Points(nil), nil)
    t.eq(RA().Points({ stops = { { label = "Inn", place = { map = 1, x = 0.5, y = 0.5 } } } }), nil)
end

tests["route area: each point on the minimap gets a pin; the rest stay hidden"] = function(t)
    local c = client()
    local state = {}
    -- 20 and 30 yards away: on the minimap; 400 yards: off it.
    local r = RA().Update(c, cur(area({ 0.52, 0.5 }, { 0.5, 0.53 }, { 0.9, 0.5 })), state)
    t.eq(r.shown, 2)
    t.eq(shown(c), 2)
    for _, h in ipairs(c.minimapPins) do
        if h.shown then t.eq(h.edge, false) end
    end
    r = RA().Update(c, nil, state)
    t.eq(r.shown, 0)
    t.eq(shown(c), 0, "no route: all hidden")
end

tests["route area: none on the minimap shows the nearest at the rim"] = function(t)
    local c = client()
    local r = RA().Update(c, cur(area({ 0.9, 0.5 }, { 0.5, 0.8 })), {})
    t.eq(r.shown, 1)
    t.eq(shown(c), 1)
    local h
    for _, x in ipairs(c.minimapPins) do if x.shown then h = x end end
    t.eq(h and h.edge, true)
    t.ok(h ~= nil and h.y < 0, "the nearer one, south")
end

tests["route area: the row is a bool in the route group, on by default"] = function(t)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    local addon = ns.offline.addon(c)
    local row = addon.settings:row(RA().SETTING)
    t.ok(type(row) == "table", "the row is there")
    t.eq(row and row.type, "bool")
    t.eq(row and row.default, true)
    t.eq(row and row.group, "travel.route")
end

return tests
