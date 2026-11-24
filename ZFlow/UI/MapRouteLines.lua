-- The route's lines on the world map (lead section 447 item 6, F7): the
-- path from you to the next stop and on through the stops after it, and a
-- line from you to your own map waypoint. Ported from the predecessor's
-- Modules/Nav/MapOverlay.lua (drawRoute, drawWaypoint, M.LegParts,
-- M.ClipToMap, M.CrossesEdge), read only.
--
--   The leg from you to the next stop is stronger (FIRST_ALPHA) than the
--   rest (REST_ALPHA). Z-Flow plans one order, nearest stop next
--   (Nav/RoutePlan.lua), so the route is drawn in the predecessor's colour
--   for that order (Shortest path blue); the other orders it had (Most XP,
--   custom) do not exist here and get no colour.
--   The next stop on another map of the same continent: the leg still
--   starts at you and stops at the shown map's edge; looking at the stop's
--   own map, it comes in from the edge. A stop on another continent, or on
--   a map the client gives no corners for, breaks the line there.
--   Later legs are drawn only between stops that are both on the shown map
--   (the predecessor's rule: no line to a stop you are not walking to next).
--   Your waypoint (client.waypoint, the one the arrow points at in green):
--   a green line from you to it, clipped at the map's edge the same way.
-- Nothing is drawn when no line falls on the shown map. The lines have
-- their own setting, MRL.SETTING (on at first; lead section 519 slice 2,
-- S3-05): off, no line is drawn, and the route list, the numbers and the
-- zone card stay. The list's setting (RL.SETTING, UI/RouteList.lua) no
-- longer turns the lines off.
--
-- LOOK ONLY: nothing is moved, targeted, cast, clicked or sent.
--
--   MRL.Place(pt, map, cornersOf) -> x, y or nil   (pure) pt { map, x, y }
--       as shares of the shown map, inside it or beside it
--   MRL.Clip(ix, iy, ox, oy) -> x, y   (pure) where a line from a spot on
--       the map toward one beside it leaves the map
--   MRL.Parts(a, b) -> { ax, ay, bx, by } or nil   (pure) the part of a
--       line on the map
--   MRL.Lines(rows, map, you, wp, cornersOf) -> lines   (pure)
--       lines = { { ax, ay, bx, by, kind = "first" | "rest" | "waypoint" } }
--   MRL.Paint(kind) -> r, g, b, a
--   MRL.Declare(k) -> api   api.Refresh() -> lines or nil, api.Shown()
-- Not tested in game.
local _, ns = ...

local MRL = {}
ns.MapRouteLines = MRL

MRL.NAME = "mapRouteLines"
MRL.SETTING = "nav.mapLines"
MRL.LABEL = "Show route lines on the map"
MRL.HELP = "Draws your route on the world map: a line from you to the next stop and on through the stops after it, and a green line to your own waypoint. Off hides only these lines: the route list beside the quest log, the numbered stops and the zone card stay."
MRL.EVERY = 0.25
MRL.FIRST_ALPHA, MRL.REST_ALPHA = 0.8, 0.45
-- The predecessor's standard palette (Modules/Theme.lua): "distance" for
-- the route, "waypoint" for your own waypoint.
MRL.ROUTE = { 0x00 / 255, 0x70 / 255, 0xDD / 255 }
MRL.WAYPOINT = { 0x1E / 255, 0xFF / 255, 0x00 / 255 }

local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

function MRL.Place(pt, map, cornersOf)
    if type(pt) ~= "table" or map == nil or not finite(pt.x) or not finite(pt.y) then return nil end
    if pt.map == map then return pt.x, pt.y end
    local F = ns.Nav and ns.Nav.Flights
    if type(cornersOf) ~= "function" or type(F) ~= "table" or pt.map == nil then return nil end
    local from, to = cornersOf(pt.map), cornersOf(map)
    if type(from) ~= "table" or type(to) ~= "table" or from.cont == nil or from.cont ~= to.cont then return nil end
    local cont, wx, wy = F.ToWorld(from, pt.x, pt.y)
    if cont == nil then return nil end
    local x, y = F.ToShare(to, wx, wy)
    if not finite(x) or not finite(y) then return nil end
    return x, y
end

local function inside(x, y) return x >= 0 and x <= 1 and y >= 0 and y <= 1 end

function MRL.Clip(ix, iy, ox, oy)
    local t = 1
    local dx, dy = ox - ix, oy - iy
    if ox > 1 then t = math.min(t, (1 - ix) / dx) elseif ox < 0 then t = math.min(t, (0 - ix) / dx) end
    if oy > 1 then t = math.min(t, (1 - iy) / dy) elseif oy < 0 then t = math.min(t, (0 - iy) / dy) end
    return ix + dx * t, iy + dy * t
end

function MRL.Parts(a, b)
    local ain, bin = inside(a[1], a[2]), inside(b[1], b[2])
    if ain and bin then return { a[1], a[2], b[1], b[2] } end
    if ain then
        local cx, cy = MRL.Clip(a[1], a[2], b[1], b[2])
        return { a[1], a[2], cx, cy }
    end
    if bin then
        local cx, cy = MRL.Clip(b[1], b[2], a[1], a[2])
        return { cx, cy, b[1], b[2] }
    end
    return nil
end

local function add(out, part, kind)
    if part then out[#out + 1] = { ax = part[1], ay = part[2], bx = part[3], by = part[4], kind = kind } end
end

function MRL.Lines(rows, map, you, wp, cornersOf)
    local out = {}
    if map == nil then return out end
    local px, py
    if type(you) == "table" then px, py = MRL.Place(you, map, cornersOf) end
    local prev
    local first = true
    for _, r in ipairs(type(rows) == "table" and rows or {}) do
        if type(r) == "table" and r.n then
            local x, y = MRL.Place(r.place, map, cornersOf)
            if first then
                first = false
                if px and x then add(out, MRL.Parts({ px, py }, { x, y }), "first") end
            elseif prev and x and inside(prev[1], prev[2]) and inside(x, y) then
                add(out, { prev[1], prev[2], x, y }, "rest")
            end
            if x then prev = { x, y } else prev = nil end
        end
    end
    if px and type(wp) == "table" then
        local wx, wy = MRL.Place(wp, map, cornersOf)
        if wx then add(out, MRL.Parts({ px, py }, { wx, wy }), "waypoint") end
    end
    return out
end

function MRL.Paint(kind)
    if kind == "waypoint" then return MRL.WAYPOINT[1], MRL.WAYPOINT[2], MRL.WAYPOINT[3], MRL.FIRST_ALPHA end
    if kind == "first" then return MRL.ROUTE[1], MRL.ROUTE[2], MRL.ROUTE[3], MRL.FIRST_ALPHA end
    return MRL.ROUTE[1], MRL.ROUTE[2], MRL.ROUTE[3], MRL.REST_ALPHA
end

local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if not ok then return nil end
    return v
end

function MRL.Declare(k)
    local api = {}
    local ctx, handle
    local drawn, lastSig = false, nil

    -- Off only when the lines' own setting says false; a read that fails
    -- is not off.
    local function on()
        local s = ctx and ctx.settings
        if type(s) ~= "table" or type(s.get) ~= "function" then return true end
        local ok, v = pcall(s.get, s, MRL.SETTING)
        return not (ok and v == false)
    end

    local function view()
        local r = k.use and k.use("tripRoute")
        if not (r and type(r.View) == "function") then return nil end
        local ok, v = pcall(r.View)
        if ok and type(v) == "table" then return v end
        return nil
    end

    local function clear()
        if handle and drawn then pcall(handle.clear) end
        drawn, lastSig = false, nil
    end

    function api.Shown() return drawn end

    function api.Refresh()
        if not ctx then return nil end
        if not on() then clear() return nil end
        local c = ctx.client
        if not handle then
            handle = ask(c, "mapRouteLines")
            if type(handle) ~= "table" then handle = nil return nil end
        end
        local okMap, map = pcall(handle.map)
        if not okMap or map == nil then clear() return nil end
        local RL = ns.RouteList
        local v = view()
        local rows = nil
        if v and RL then rows = RL.Rows(v, nil) end
        local function cornersOf(m) return ask(c, "mapCorners", m) end
        local lines = MRL.Lines(rows, map, ask(c, "position"), ask(c, "waypoint"), cornersOf)
        if #lines == 0 then clear() return lines end
        local sig = { tostring(map) }
        for _, l in ipairs(lines) do
            local r, g, b, a = MRL.Paint(l.kind)
            l.r, l.g, l.b, l.a = r, g, b, a
            sig[#sig + 1] = table.concat({ l.kind, l.ax, l.ay, l.bx, l.by }, "|")
        end
        sig = table.concat(sig, "\n")
        if drawn and sig == lastSig then return lines end
        local ok = pcall(handle.draw, lines)
        drawn = ok
        if ok then lastSig = sig else lastSig = nil end
        return lines
    end

    k:Setting({ key = MRL.SETTING, scope = "account", type = "bool", default = true,
        label = MRL.LABEL, group = "travel.route", help = MRL.HELP,
        synonyms = { "route", "lines", "line", "path", "trail", "map", "world map", "waypoint" } })

    k:Module({
        name = MRL.NAME,
        needs = { "client", "settings" },
        ticks = { { every = MRL.EVERY, when = "always", run = function() api.Refresh() end } },
        start = function(c) ctx = c end,
        stop = function() clear() end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.mapRouteLines = MRL.Declare(ns)
