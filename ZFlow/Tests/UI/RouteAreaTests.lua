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

-- Slice 4: the marks take the current step's colour (RC.Of at the
-- nearest point's yards), and follow it as the player walks. Fails
-- before: the pin spec carries no colour and nothing retints.
local function RC() return ns.RouteColor end

tests["route area: the marks are made in the current step's colour"] = function(t)
    local c = client()
    local state = {}
    local r = RA().Update(c, cur(area({ 0.53, 0.5 }, { 0.5, 0.54 })), state, {})
    t.eq(r.shown, 2)
    local er, eg, eb = RC().Of({ state = "zone" }, 30, nil, nil)
    t.eq({ r.r, r.g, r.b }, { er, eg, eb }, "the report carries the colour (nearest point, 30 yd)")
    for _, h in ipairs(c.minimapPins) do
        t.eq({ h.spec.r, h.spec.g, h.spec.b }, { er, eg, eb }, "the mark's colour")
    end
end

tests["route area: walking recolours the marks"] = function(t)
    local c = client()
    local state = {}
    RA().Update(c, cur(area({ 0.53, 0.5 }, { 0.5, 0.54 })), state, {})
    local h = c.minimapPins[1]
    t.eq(h.tints or 0, 0, "no retint yet: the colour came with the frame")
    c.setPosition(1, 0.52, 0.5)
    local r = RA().Update(c, cur(area({ 0.53, 0.5 }, { 0.5, 0.54 })), state, {})
    local er, eg, eb = RC().Of({ state = "here" }, 10, nil, nil)
    t.eq({ r.r, r.g, r.b }, { er, eg, eb }, "the nearest point under 24 yd: here")
    t.eq(h.tint, { r = er, g = eg, b = eb }, "the marks were retinted")
end

tests["route area: a mark on the character icon is told to draw hollow"] = function(t)
    local c = client()
    local state = {}
    local r = RA().Update(c, cur(area({ 0.5, 0.5 }, { 0.5, 0.53 })), state, {})
    t.eq(r.shown, 2)
    local onIcon, offIcon
    for _, h in ipairs(c.minimapPins) do
        if h.x == 0 and h.y == 0 then onIcon = h else offIcon = h end
    end
    t.eq(onIcon and onIcon.hollowSet, true, "the mark on the icon: hollow")
    t.eq(offIcon and offIcon.hollowSet, false, "the other: solid")
end

return tests
