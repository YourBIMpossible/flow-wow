local _, ns = ...

-- Map toggles (FLOW-PARITY B-13, B-14; lead section 843.2, plan accepted
-- 846.4): the two switches the world map button's menu shows, as Flow's
-- own map buttons do (MapFlights.lua :615-688 for the flight masters,
-- MapOverlay.lua :1261-1292 for the route).
--
-- State only. Each switch is a setting the map drawing already reads:
--   flight masters  nav.mapFlights  (Nav/MapFlights.lua, off as made)
--   route           nav.mapTrail    (UI/MapRouteLines.lua, on as made)
-- so no new setting and no new default. Both draw on their own ticks, so a
-- change shows at the next one. The menu listing is a lead patch for
-- UI/ArrowMenu.lua (held).
--
--   MT.Items(flightsOn, routeOn) -> { { key, text, checked } } the two rows
--   MT.Declare(k) -> api, module "mapToggles" providing:
--     FlightsShown(), SetFlights(on), RouteShown(), SetRoute(on),
--     MenuItems(), Toggle(key) -> the new state, or nil for another key

local MT = {}
ns.MapToggles = MT

MT.NAME = "mapToggles"
MT.FLIGHTS = "map.flights"
MT.ROUTE = "map.route"
MT.FLIGHTS_TEXT = "Flight masters on the map"
MT.ROUTE_TEXT = "Your route on the map"

-- The setting each switch is, read when used (the files load in any order).
local function flightsKey()
    local MF = ns.MapFlights
    if type(MF) == "table" then return MF.SETTING end
    return nil
end

local function routeKey()
    local MRL = ns.MapRouteLines
    if type(MRL) == "table" then return MRL.TRAIL_SETTING end
    return nil
end

function MT.Items(flightsOn, routeOn)
    return {
        { key = MT.FLIGHTS, text = MT.FLIGHTS_TEXT, checked = flightsOn == true },
        { key = MT.ROUTE, text = MT.ROUTE_TEXT, checked = routeOn == true },
    }
end

function MT.Declare(k)
    local api = {}
    local ctx

    local function get(key, default)
        local s = ctx and ctx.settings
        if key == nil or type(s) ~= "table" or type(s.get) ~= "function" then return default end
        local ok, v = pcall(s.get, s, key)
        if not ok or type(v) ~= "boolean" then return default end
        return v
    end

    local function set(key, on)
        local s = ctx and ctx.settings
        if key == nil or type(s) ~= "table" or type(s.set) ~= "function" then return false end
        local ok = pcall(s.set, s, key, on == true)
        return ok
    end

    function api.FlightsShown() return get(flightsKey(), false) end
    function api.RouteShown() return get(routeKey(), true) end
    function api.SetFlights(on) return set(flightsKey(), on) end
    function api.SetRoute(on) return set(routeKey(), on) end

    function api.MenuItems()
        return MT.Items(api.FlightsShown(), api.RouteShown())
    end

    function api.Toggle(key)
        if key == MT.FLIGHTS then
            api.SetFlights(not api.FlightsShown())
            return api.FlightsShown()
        end
        if key == MT.ROUTE then
            api.SetRoute(not api.RouteShown())
            return api.RouteShown()
        end
        return nil
    end

    k:Module({
        name = MT.NAME,
        needs = { "settings" },
        provides = {
            FlightsShown = api.FlightsShown, SetFlights = api.SetFlights,
            RouteShown = api.RouteShown, SetRoute = api.SetRoute,
            MenuItems = api.MenuItems, Toggle = api.Toggle,
        },
        start = function(c) ctx = c end,
        stop = function() ctx = nil end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.mapToggles = MT.Declare(ns)
