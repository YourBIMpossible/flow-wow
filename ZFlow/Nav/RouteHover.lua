local _, ns = ...

-- Parity row B-20, the logic half (lead section 738): pointing at a step in
-- a list (the route list, the tracker) shows that step alone on the map,
-- as Flow's Modules/Nav/MapOverlay.lua: hoverSolo (:46-49, "the map shows
-- that step alone"; pointing at a pin on the map itself does not), SoloAt
-- and SoloStops (:767-781: itself, alone, since 0.35.289) and M.Hover
-- (:1971-1975).
--
-- A step is told by its place ({ map, x, y }, as the route list's rows
-- carry it: UI/RouteList.lua:141), since the rows have no key.
--   H.Same(a, b) -> bool            the same map and spot
--   H.SoloAt(plan, place) -> i|nil  the step of plan at that place
--   H.SoloStops(n, at) -> { at } | {}
--   H.Declare(k) -> api
--     api.Hover(place | nil)  a list row pointed at, or left; H.EVENT is
--       emitted with a copy of the place (nil when left), on a change only
--     api.Pointed() -> a copy of the place, or nil
-- Who calls Hover and who draws: the route list's rows (their pointer in
-- and out, UI/RouteList.lua) and the tracker's are the drawing kit's (a
-- MUSE NEED); the map drawing it alone listens for H.EVENT (UI/
-- MapRouteLines.lua is held: a LEAD NEED). Nothing here draws or reads the
-- client. Not tested in game.
local H = {}
ns.Nav.RouteHover = H

H.NAME = "routeHover"
H.EVENT = "ROUTE_HOVER"
H.NEAR = 1e-6

local function placed(p)
    return type(p) == "table" and p.map ~= nil and type(p.x) == "number" and type(p.y) == "number"
        and p.x == p.x and p.y == p.y
end

function H.Same(a, b)
    if not placed(a) or not placed(b) then return false end
    return a.map == b.map and math.abs(a.x - b.x) <= H.NEAR and math.abs(a.y - b.y) <= H.NEAR
end

function H.SoloAt(plan, place)
    if type(plan) ~= "table" or not placed(place) then return nil end
    for i, s in ipairs(plan) do
        if type(s) == "table" and H.Same(s.place, place) then return i end
    end
    return nil
end

function H.SoloStops(n, at)
    if type(at) == "number" and type(n) == "number" and at >= 1 and at <= n then return { at } end
    return {}
end

local function copy(p)
    if not placed(p) then return nil end
    return { cont = p.cont, map = p.map, x = p.x, y = p.y }
end

function H.Declare(k)
    local api = {}
    local ctx, pointed

    function api.Hover(place)
        local now = copy(place)
        if now == nil and pointed == nil then return end
        if now ~= nil and H.Same(now, pointed) then return end
        pointed = now
        if ctx then ctx.bus:emit(H.EVENT, copy(pointed)) end
    end

    function api.Pointed() return copy(pointed) end

    k:Module({
        name = H.NAME,
        needs = { "bus" },
        provides = { Hover = api.Hover, Pointed = api.Pointed },
        start = function(c) ctx = c end,
        stop = function() ctx, pointed = nil, nil end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.routeHover = H.Declare(ns)
