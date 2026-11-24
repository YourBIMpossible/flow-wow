local _, ns = ...

-- RouteArea (N43, P-TRIP route display): the current route step's area on
-- the minimap. When the stop the arrow walks to (Nav/TripRoute.lua Current,
-- stops[1]) is a quest spot of several points (its area, T.AREA_MAX at
-- most), each point that is on the minimap gets one small mark, made by the
-- existing minimap pin (client.minimapPin, as UI/MinimapPin.lua uses it);
-- with none on the minimap, the nearest stands at the rim. Where each mark
-- goes is N.MinimapPin's (Nav/MinimapPin.lua). The area is drawn as its
-- points: a filled area would need a new client part.
--
-- LOOK ONLY: nothing is clicked, targeted, moved, saved or printed.
--
--   RA.Points(cur) -> the area's points, or nil when the current step has
--     fewer than two (pure)
--   RA.Update(client, cur, state) -> { shown = n }   one look; state is
--     kept between looks (the marks are made once, as needed)
--   RA.Declare(k) -> api   api.last()
-- Not tested in game.

local RA = {}
ns.RouteArea = RA

RA.NAME = "routeArea"
RA.SETTING = "nav.routeArea"
RA.EVERY = 0.1     -- seconds between looks, as the waypoint pin's
RA.SIZE = 8        -- how wide one mark is. A first guess.

local N = ns.Nav

function RA.Points(cur)
    local s = type(cur) == "table" and type(cur.stops) == "table" and cur.stops[1] or nil
    local area = type(s) == "table" and s.area or nil
    if type(area) ~= "table" or #area < 2 then return nil end
    return area
end

local function ask(client, read, ...)
    if type(client) ~= "table" or type(client[read]) ~= "function" then return nil end
    return client[read](...)
end

local function hideFrom(state, n)
    for i = n + 1, #state.handles do
        if state.placed[i] then
            state.handles[i].hide()
            state.placed[i] = false
        end
    end
end

-- Mark i, made the first time it is needed; nil when the client gives none.
local function handle(client, state, i)
    local h = state.handles[i]
    if h then return h end
    if state.noFrame then return nil end
    h = ask(client, "minimapPin", { size = RA.SIZE })
    if type(h) ~= "table" or type(h.place) ~= "function" or type(h.hide) ~= "function" then
        state.noFrame = true
        return nil
    end
    state.handles[i] = h
    return h
end

function RA.Update(client, cur, state)
    if type(state) ~= "table" then state = {} end
    state.handles = state.handles or {}
    state.placed = state.placed or {}
    local points = RA.Points(cur)
    local seen = points and ask(client, "minimap") or nil
    if type(seen) ~= "table" then
        hideFrom(state, 0)
        return { shown = 0 }
    end
    local mini = { size = seen.size, radius = seen.radius, rotates = seen.rotates,
                   square = seen.square, inset = RA.SIZE / 2 }
    local here = { position = ask(client, "position"), size = ask(client, "mapSize", points[1].map),
                   facing = ask(client, "facing") }
    local inside, nearest = {}, nil
    for _, pt in ipairs(points) do
        local pin = N.MinimapPin(pt, here, mini)
        if pin then
            if not pin.edge then
                inside[#inside + 1] = pin
            elseif nearest == nil or pin.distance < nearest.distance then
                nearest = pin
            end
        end
    end
    if #inside == 0 and nearest then inside[1] = nearest end
    local n = 0
    for _, pin in ipairs(inside) do
        local h = handle(client, state, n + 1)
        if not h then break end
        n = n + 1
        h.place(pin.x, pin.y, pin.edge)
        state.placed[n] = true
    end
    hideFrom(state, n)
    return { shown = n }
end

function RA.Declare(k)
    local api = {}
    local last
    local state = {}
    function api.last() return last end
    k:Setting({ key = RA.SETTING, scope = "account", type = "bool", default = true,
        label = "Show the step's area on the minimap", group = "travel.route",
        help = "Marks each point of the current route step's area on the minimap.",
        synonyms = { "route", "minimap", "area", "step", "spots" } })
    k:Module({
        name = RA.NAME,
        needs = { "client", "settings", "sched" },
        start = function(ctx)
            local client = ctx.client
            if type(client.minimap) ~= "function" or type(client.minimapPin) ~= "function" then return end
            ctx.sched:every(RA.NAME, RA.EVERY, function()
                local cur
                local okOn, on = pcall(ctx.settings.get, ctx.settings, RA.SETTING)
                local r = k.use and k.use("tripRoute")
                if not (okOn and on == false) and r and type(r.Current) == "function" then
                    local ok, v = pcall(r.Current)
                    if ok then cur = v end
                end
                last = RA.Update(client, cur, state)
            end)
        end,
        stop = function()
            last = RA.Update(nil, nil, state)
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.routeArea = RA.Declare(ns)
