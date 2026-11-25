local _, ns = ...
-- The route tracker's "here" mode, data half (A2-20, lead section 674): the
-- steps of the planned route that are around the player. The window and
-- all drawing are UI's; this file draws nothing, saves nothing, prints
-- nothing and moves no one.
--
-- The steps come from the existing step source, Nav/TripRoute.lua
-- api.Current() (the stops still to walk, in route order). Ported from
-- legacy Flow (origin/buff-fishing-prof-path Modules/Nav/Nav.lua:1405-1435:
-- :1409 N.HERE_YARDS = 150, :1427 N.HereStops): a step is here when it is the next step, or one of
-- its points is within RH.YARDS of the player, or of the next step. Order:
-- the route's own.
--
-- Z-Flow's places are shares 0..1 of a map, so a distance is known only on
-- the same map and when the map's size in yards is known (client.mapSize,
-- as Nav/TripRoute.lua measures). Unknown stays unknown: a step that cannot
-- be measured is not taken as near; the next step is here all the same.
--
--   RH.Stops(stops, here[, yards]) -> list (pure)
--     stops  the route's stops, in order: { label, quest, place = { map, x,
--            y }, area = { { map, x, y }, ... } }
--     here   { map, x, y, size = { w, h } } or nil; x, y may be absent
--     list   copies of the stops that are here, in route order, each with
--            index = its place on the route
--   RH.Declare(k) -> api   api.Here() -> { stops = list, total = n } or nil
--     with no route planned
-- Not tested in game.

local N = ns.Nav
local RH = {}
N.RouteHere = RH

RH.NAME = "routeHere"
RH.YARDS = 150   -- Flow's N.HERE_YARDS (origin/buff-fishing-prof-path Modules/Nav/Nav.lua:1409)

local function finite(v)
    return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function sizeOf(here)
    local s = type(here) == "table" and here.size or nil
    if type(s) ~= "table" or not finite(s.w) or not finite(s.h) or s.w <= 0 or s.h <= 0 then return nil end
    return s
end

-- Is point p within yards of point at? Both on map, which has size.
local function within(p, at, map, size, yards)
    if type(p) ~= "table" or type(at) ~= "table" then return false end
    if p.map ~= map or at.map ~= map then return false end
    if not (finite(p.x) and finite(p.y) and finite(at.x) and finite(at.y)) then return false end
    local dx, dy = (p.x - at.x) * size.w, (p.y - at.y) * size.h
    return dx * dx + dy * dy <= yards * yards
end

-- Any of the stop's points (its place, then its area) near at?
local function near(s, at, map, size, yards)
    if within(s.place, at, map, size, yards) then return true end
    if type(s.area) == "table" then
        for _, p in ipairs(s.area) do
            if within(p, at, map, size, yards) then return true end
        end
    end
    return false
end

local function copy(s, i)
    local out = {}
    for key, v in pairs(s) do out[key] = v end
    if type(s.place) == "table" then out.place = { map = s.place.map, x = s.place.x, y = s.place.y } end
    if type(s.area) == "table" then
        local area = {}
        for j, p in ipairs(s.area) do
            if type(p) == "table" then area[j] = { map = p.map, x = p.x, y = p.y } end
        end
        out.area = area
    end
    out.index = i
    return out
end

function RH.Stops(stops, here, yards)
    local out = {}
    if type(stops) ~= "table" then return out end
    if not finite(yards) then yards = RH.YARDS end
    local size = sizeOf(here)
    local map
    if type(here) == "table" then map = here.map end
    local first
    if type(stops[1]) == "table" then first = stops[1].place end
    for i, s in ipairs(stops) do
        if type(s) == "table" then
            local isHere = i == 1
            if not isHere and size ~= nil and map ~= nil then
                isHere = near(s, here, map, size, yards) or near(s, first, map, size, yards)
            end
            if isHere then out[#out + 1] = copy(s, i) end
        end
    end
    return out
end

local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if not ok then return nil end
    return v
end

function RH.Declare(k)
    local api = {}
    local ctx

    local function client() return ctx and ctx.client or k.client end

    local function hereNow()
        local c = client()
        local pos = ask(c, "position")
        local here = {}
        if type(pos) == "table" then here.map, here.x, here.y = pos.map, pos.x, pos.y end
        if here.map ~= nil then
            local size = ask(c, "mapSize", here.map)
            if type(size) == "table" then here.size = { w = size.w, h = size.h } end
        end
        return here
    end

    function api.Here()
        local r = k.use and k.use("tripRoute")
        if not (r and type(r.Current) == "function") then return nil end
        local ok, cur = pcall(r.Current)
        if not ok or type(cur) ~= "table" or type(cur.stops) ~= "table" then return nil end
        return { stops = RH.Stops(cur.stops, hereNow()), total = #cur.stops }
    end

    k:Module({
        name = RH.NAME,
        needs = { "client" },
        provides = { Here = api.Here },
        start = function(c) ctx = c end,
        stop = function() ctx = nil end,
    })
    return api
end

-- The addon's own: declared when this file loads. Look only.
ns.routeHere = RH.Declare(ns)
