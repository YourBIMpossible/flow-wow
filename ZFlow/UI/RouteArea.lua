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
--   RA.Update(client, cur, state[, shade]) -> { shown = n, r, g, b }
--     one look; state is kept between looks (the marks are made once, as
--     needed). Slice 4: the marks take the current step's colour (the
--     report's r, g, b); shade is { palette, byDistance }. Slice 6: a
--     one-point current step gets one dot instead (the report's dot).
--   RA.Declare(k) -> api   api.last()
-- Not tested in game.

local RA = {}
ns.RouteArea = RA

RA.NAME = "routeArea"
RA.SETTING = "nav.routeArea"
RA.EVERY = 0.1     -- seconds between looks, as the waypoint pin's
RA.SIZE = 8        -- how wide one mark is. A first guess.
RA.DOT_SIZE = 12   -- how wide the one-point step's dot is (slice 6),
                   -- as the waypoint pin. A first guess.

local N = ns.Nav

-- The arrow's here distance (N.AT_POINT): ArrowView loads before
-- this file and the value is a constant, so it is read once here.
local at = 24
if N and N.AT_POINT then at = N.AT_POINT end

function RA.Points(cur)
    local s
    if type(cur) == "table" and type(cur.stops) == "table" then s = cur.stops[1] end
    local area = nil
    if type(s) == "table" then area = s.area end
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

-- Slice 4: the marks' colour — the current step's colour from the one
-- contract (RC.Of), at the nearest point's yards; "here" when that is
-- under N.AT_POINT (the arrow's own rule), else the distance ramp.
-- nil when the contract is not loaded (the marks then keep the
-- client's fallback colour).
local function colourOf(cur, yards, shade)
    local RC = ns.RouteColor
    if type(RC) ~= "table" or type(RC.Of) ~= "function" then return nil end
    local s
    if type(cur) == "table" and type(cur.stops) == "table" then s = cur.stops[1] end
    if type(s) ~= "table" then return nil end
    local state = "zone"
    if type(yards) == "number" and yards < at then state = "here" end
    local palette, byDistance
    if type(shade) == "table" then palette, byDistance = shade.palette, shade.byDistance end
    local r, g, b = RC.Of({ kind = s.kind, family = s.family, state = state }, yards, palette, byDistance)
    return { r, g, b }
end

-- A mark sits on the character icon when its middle is within half
-- the mark of the minimap's middle. A first guess.
local function onIcon(pin, size)
    local half = size / 2
    return pin.x * pin.x + pin.y * pin.y <= half * half
end

-- Slice 6: the current step's one point, when it has no area of two
-- or more: its place (or its area's only point).
local function onePoint(cur)
    local s
    if type(cur) == "table" and type(cur.stops) == "table" then s = cur.stops[1] end
    if type(s) ~= "table" then return nil end
    if type(s.area) == "table" and #s.area >= 2 then return nil end
    if type(s.place) == "table" then return s.place end
    if type(s.area) == "table" then return s.area[1] end
    return nil
end

-- The one-point step's dot, made once; nil when the client gives none.
local function dotHandle(client, state, colour)
    if state.dot then return state.dot end
    if state.noDot then return nil end
    local spec = { size = RA.DOT_SIZE }
    if colour then spec.r, spec.g, spec.b = colour[1], colour[2], colour[3] end
    local h = ask(client, "minimapPin", spec)
    if type(h) ~= "table" or type(h.place) ~= "function" or type(h.hide) ~= "function" then
        state.noDot = true
        return nil
    end
    state.dot = h
    return h
end

local function hideDot(state)
    if state.dot and state.dotPlaced then
        state.dot.hide()
        state.dotPlaced = false
    end
end

-- Mark i, made the first time it is needed; nil when the client gives none.
local function handle(client, state, i, colour)
    local h = state.handles[i]
    if h then return h end
    if state.noFrame then return nil end
    local spec = { size = RA.SIZE }
    if colour then spec.r, spec.g, spec.b = colour[1], colour[2], colour[3] end
    h = ask(client, "minimapPin", spec)
    if type(h) ~= "table" or type(h.place) ~= "function" or type(h.hide) ~= "function" then
        state.noFrame = true
        return nil
    end
    state.handles[i] = h
    return h
end

function RA.Update(client, cur, state, shade)
    if type(state) ~= "table" then state = {} end
    state.handles = state.handles or {}
    state.placed = state.placed or {}
    local points = RA.Points(cur)
    local single = nil
    if not points then single = onePoint(cur) end
    local seen
    if points or single then seen = ask(client, "minimap") end
    if type(seen) ~= "table" then
        hideFrom(state, 0)
        hideDot(state)
        return { shown = 0 }
    end
    local anchor = single
    if points and points[1] then anchor = points[1] end
    local inset = RA.SIZE / 2
    if single then inset = RA.DOT_SIZE / 2 end
    local mini = { size = seen.size, radius = seen.radius, rotates = seen.rotates,
                   square = seen.square, inset = inset }
    local here = { position = ask(client, "position"), size = ask(client, "mapSize", anchor.map),
                   facing = ask(client, "facing") }
    if single then
        -- Slice 6: one dot for a one-point step; the area marks stand
        -- down (they are the signal only when the step has an area).
        hideFrom(state, 0)
        local pin = N.MinimapPin(single, here, mini)
        if not pin then
            hideDot(state)
            return { shown = 0 }
        end
        local colour = colourOf(cur, pin.distance, shade)
        local h = dotHandle(client, state, colour)
        if not h then return { shown = 0 } end
        if colour then
            local prev = state.dotColour
            if prev and (prev[1] ~= colour[1] or prev[2] ~= colour[2] or prev[3] ~= colour[3])
                and type(h.colour) == "function" then
                h.colour(colour[1], colour[2], colour[3])
            end
            state.dotColour = colour
        end
        h.place(pin.x, pin.y, pin.edge)
        if type(h.hollow) == "function" then h.hollow(onIcon(pin, RA.DOT_SIZE)) end
        state.dotPlaced = true
        local out = { shown = 1, dot = true }
        if colour then out.r, out.g, out.b = colour[1], colour[2], colour[3] end
        return out
    end
    hideDot(state)
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
    -- Slice 4: the step's colour at the nearest mark's yards; the marks
    -- already made are retinted when it changes (the new ones are made
    -- in it), and a mark on the character icon is told to draw hollow.
    local yards
    for _, pin in ipairs(inside) do
        if type(pin.distance) == "number" and (yards == nil or pin.distance < yards) then
            yards = pin.distance
        end
    end
    local colour = colourOf(cur, yards, shade)
    if colour then
        local prev = state.colour
        if not prev or prev[1] ~= colour[1] or prev[2] ~= colour[2] or prev[3] ~= colour[3] then
            for _, h in ipairs(state.handles) do
                if type(h.colour) == "function" then h.colour(colour[1], colour[2], colour[3]) end
            end
            state.colour = colour
        end
    end
    local n = 0
    for _, pin in ipairs(inside) do
        local h = handle(client, state, n + 1, colour)
        if not h then break end
        n = n + 1
        h.place(pin.x, pin.y, pin.edge)
        if type(h.hollow) == "function" then h.hollow(onIcon(pin, RA.SIZE)) end
        state.placed[n] = true
    end
    hideFrom(state, n)
    local out = { shown = n }
    if colour then out.r, out.g, out.b = colour[1], colour[2], colour[3] end
    return out
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
                -- Slice 4: the arrow's palette and one-colour setting,
                -- for the marks' colour.
                local shade = {}
                local okPal, pal = pcall(ctx.settings.get, ctx.settings, "arrow.palette")
                if okPal and type(pal) == "string" then shade.palette = pal end
                local okBy, by = pcall(ctx.settings.get, ctx.settings, "arrow.byDistance")
                if okBy and by == false then shade.byDistance = false end
                last = RA.Update(client, cur, state, shade)
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
