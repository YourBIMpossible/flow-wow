-- The route's lines on the world map (lead section 447 item 6, F7; pathing
-- UI slice 3): the path from you to the next stop and on through the stops
-- after it, and a line from you to your own map waypoint. Ported from the
-- predecessor's Modules/Nav/MapOverlay.lua (drawRoute, drawWaypoint,
-- M.LegParts, M.ClipToMap, M.CrossesEdge), read only.
--
--   The trail is a dotted line, like a pirate treasure map, not a solid
--   one: each route leg is split into dashes (MRL.Dash), and an X marks
--   the next stop (MRL.X, gold). The leg from you to the next stop is
--   stronger (FIRST_ALPHA) than the rest (REST_ALPHA). Z-Flow plans one
--   order, nearest stop next (Nav/RoutePlan.lua).
--   The next stop on another map of the same continent: the leg still
--   starts at you and stops at the shown map's edge; looking at the stop's
--   own map, it comes in from the edge. A stop on another continent, or on
--   a map the client gives no corners for, breaks the line there. The X is
--   drawn only when the next stop is on the shown map.
--   Later legs are drawn only between stops that are both on the shown map
--   (the predecessor's rule: no line to a stop you are not walking to next).
--   Your waypoint (client.waypoint, the one the arrow points at in green):
--   a solid green line from you to it, clipped at the map's edge the same
--   way. The waypoint line is solid on purpose: it is a different thing
--   from the route trail, a direct line to a spot you set yourself.
-- Nothing is drawn when no line falls on the shown map. The setting
-- nav.mapTrail (declared below, lead §543) turns the trail off on its
-- own; nav.routePanel (UI/RouteList.lua) turns it off with the list
-- and the marks. Both must be on.
--
--   The colour is the shared contract (Nav/RouteColor.lua, slice 1):
--   the next leg wears the next step's colour from the contract — its
--   family, when the arrow's step has one, else its distance colour;
--   later legs the same colour fainter, the waypoint green, the X gold.
--   The palette is the arrow's ("arrow.palette" setting; the standard
--   one when it is not kept), and the player's one-colour setting
--   ("arrow.byDistance", N43) is passed through, so the trail keeps it
--   when it is on: one colour, the near one, instead of the distance
--   ramp. Under one-colour the arrow keeps its flat colour for a waypoint
--   or profession step, so the leg does too: the family is skipped and
--   the flat row wins (lead section 617). Colour is never read from the
--   arrow's own frame: the trail asks the same function the arrow does,
--   so the two cannot disagree.
--   The yards to the next stop are worked out here from your position, the
--   stop's place and the map's size (MRL.Yards); when they are not known
--   the leg is drawn as far. A next stop on another map is drawn grey
--   ("away"). The trail cannot see whether you are in the step's area, so
--   it never draws the "here" blue itself: at the destination it shows
--   the near green while the arrow shows blue. That gap is noted in the
--   READY; closing it needs the step's area to reach the trail.
--
-- LOOK ONLY: nothing is moved, targeted, cast, clicked or sent. The world
-- map is only drawn on, never opened, turned or zoomed from code.
--
--   MRL.Place(pt, map, cornersOf) -> x, y or nil   (pure) pt { map, x, y }
--       as shares of the shown map, inside it or beside it
--   MRL.Clip(ix, iy, ox, oy) -> x, y   (pure) where a line from a spot on
--       the map toward one beside it leaves the map
--   MRL.Parts(a, b) -> { ax, ay, bx, by } or nil   (pure) the part of a
--       line on the map
--   MRL.Dash(ax, ay, bx, by) -> segments   (pure) a line split into dashes
--       of MRL.DASH with MRL.GAP between them, in shares of the shown map
--   MRL.X(x, y) -> segments   (pure) the two strokes of an X centred on
--       the point, MRL.X_HALF a side in shares
--   MRL.Yards(you, place, size) -> yards or nil   (pure) straight-line
--       yards from you to a stop on the same map, from the map's size
--   MRL.Lines(rows, map, you, wp, cornersOf) -> lines   (pure)
--       lines = { { ax, ay, bx, by, kind = "first" | "rest" | "waypoint" | "x" } }
--   MRL.Paint(kind, step, yards, palette, byDistance) -> r, g, b, a
--       step: the next step ({ state = "away" } when it is on another map),
--       or { family = "waypoint" } for the waypoint line; byDistance is
--       the player's one-colour setting (false: one colour, the near one)
--   MRL.Declare(k) -> api   api.Refresh() -> lines or nil, api.Shown()
-- Not tested in game.
local _, ns = ...

local MRL = {}
ns.MapRouteLines = MRL

MRL.NAME = "mapRouteLines"
MRL.EVERY = 0.25
MRL.FIRST_ALPHA, MRL.REST_ALPHA = 0.8, 0.45
-- The trail's own setting key (declared in MRL.Declare, lead §543).
-- The Flow import already writes "nav.mapLines", so that name is taken.
MRL.TRAIL_SETTING = "nav.mapTrail"
-- Dashes and the X, in shares of the shown map (0.02 is about 14 px on a
-- 700 px wide map canvas). Tunable: the trail must read as dotted, not
-- solid, and the X must mark the spot without covering the map.
MRL.DASH, MRL.GAP, MRL.X_HALF = 0.02, 0.012, 0.012

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

-- A line split into dashes: dashes of MRL.DASH with MRL.GAP between them,
-- the last one cut short at the line's end. A line shorter than a dash is
-- one dash; a line of no length is none.
function MRL.Dash(ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local len = math.sqrt(dx * dx + dy * dy)
    if len ~= len or len <= 0 then return {} end
    local out = {}
    local step = MRL.DASH + MRL.GAP
    local t = 0
    while t < len do
        local e = math.min(t + MRL.DASH, len)
        out[#out + 1] = { ax + dx * (t / len), ay + dy * (t / len), ax + dx * (e / len), ay + dy * (e / len) }
        t = t + step
    end
    return out
end

-- The two strokes of an X centred on the point.
function MRL.X(x, y)
    local h = MRL.X_HALF
    return { { x - h, y - h, x + h, y + h }, { x - h, y + h, x + h, y - h } }
end

-- Straight-line yards from you to a stop on the same map, from the map's
-- size ({ w, h } in yards, client.mapSize). nil when the two are not on
-- the same map, or the size or a position is not known. The same sums as
-- Nav/Trip.TrackRows, without its "N yd" words: RouteColor takes a number.
function MRL.Yards(you, place, size)
    if type(you) ~= "table" or type(place) ~= "table" or you.map == nil or place.map ~= you.map then return nil end
    if type(size) ~= "table" or not finite(size.w) or not finite(size.h) then return nil end
    if not finite(you.x) or not finite(you.y) or not finite(place.x) or not finite(place.y) then return nil end
    local dx, dy = (place.x - you.x) * size.w, (place.y - you.y) * size.h
    return math.sqrt(dx * dx + dy * dy)
end

local function add(out, part, kind)
    if part then out[#out + 1] = { ax = part[1], ay = part[2], bx = part[3], by = part[4], kind = kind } end
end

local function addDashed(out, part, kind)
    if not part then return end
    for _, d in ipairs(MRL.Dash(part[1], part[2], part[3], part[4])) do
        out[#out + 1] = { ax = d[1], ay = d[2], bx = d[3], by = d[4], kind = kind }
    end
end

function MRL.Lines(rows, map, you, wp, cornersOf)
    local out = {}
    if map == nil then return out end
    local px, py
    if type(you) == "table" then px, py = MRL.Place(you, map, cornersOf) end
    local prev
    local first = true
    local firstX, firstY
    for _, r in ipairs(type(rows) == "table" and rows or {}) do
        if type(r) == "table" and r.n then
            local x, y = MRL.Place(r.place, map, cornersOf)
            if first then
                first = false
                firstX, firstY = x, y
                if px and x then addDashed(out, MRL.Parts({ px, py }, { x, y }), "first") end
            elseif prev and x and inside(prev[1], prev[2]) and inside(x, y) then
                addDashed(out, { prev[1], prev[2], x, y }, "rest")
            end
            if x then prev = { x, y } else prev = nil end
        end
    end
    if px and type(wp) == "table" then
        local wx, wy = MRL.Place(wp, map, cornersOf)
        if wx then add(out, MRL.Parts({ px, py }, { wx, wy }), "waypoint") end
    end
    -- X marks the next stop, when it is on the shown map. A stop on
    -- another map has no X: its place is beside the map, not the spot.
    if firstX and firstY and inside(firstX, firstY) then
        for _, s in ipairs(MRL.X(firstX, firstY)) do
            out[#out + 1] = { ax = s[1], ay = s[2], bx = s[3], by = s[4], kind = "x" }
        end
    end
    return out
end

-- The colour of one line, from the shared contract (Nav/RouteColor.lua).
-- step is the next step ({ state = "away" } when it is on another map,
-- with the family the arrow's step carries, when it has one); the
-- waypoint line passes { family = "waypoint" } instead. yards is the
-- straight-line yards to the next stop, or nil when not known (drawn as
-- far). palette is the arrow's ("standard" when not kept). byDistance is
-- the player's one-colour setting (N43): false gives one colour, the near
-- one, for the route legs; the waypoint and the X are colours of their
-- own and do not read it. When the contract is not loaded, the old route
-- blue, so the trail still draws.
--   One-colour (lead section 617): the arrow keeps its flat colour for a
--   waypoint or profession step (Nav/ArrowView.lua, the flatRow branch),
--   so the first leg must too. When byDistance is false the family is
--   skipped here and the distance colour — the flat row — wins, so the
--   leg is the arrow's colour, whatever the arrow shows.
function MRL.Paint(kind, step, yards, palette, byDistance)
    local RC = ns.RouteColor
    if type(RC) ~= "table" or type(RC.Of) ~= "function" then
        if kind == "waypoint" then return 0x1E / 255, 0xFF / 255, 0, MRL.FIRST_ALPHA end
        if kind == "x" then return 0xE6 / 255, 0x9F / 255, 0, MRL.FIRST_ALPHA end
        if kind == "first" then return 0, 0x70 / 255, 0xDD / 255, MRL.FIRST_ALPHA end
        return 0, 0x70 / 255, 0xDD / 255, MRL.REST_ALPHA
    end
    if kind == "x" then
        local x = RC.DESTINATION_X
        return x[1], x[2], x[3], MRL.FIRST_ALPHA
    end
    if kind == "waypoint" then
        local r, g, b = RC.Of({ family = "waypoint" }, nil, palette)
        return r, g, b, MRL.FIRST_ALPHA
    end
    -- One-colour: skip the family, so the distance colour (the flat row)
    -- wins and the leg matches the arrow's flat colour (lead section 617).
    local colourStep = step
    if byDistance == false and type(step) == "table" and type(RC.FAMILIES) == "table"
        and (RC.FAMILIES[step.family] or RC.FAMILIES[step.kind]) then
        colourStep = { state = step.state }
    end
    local r, g, b = RC.Of(colourStep, yards, palette, byDistance)
    if kind == "first" then return r, g, b, MRL.FIRST_ALPHA end
    return r, g, b, MRL.REST_ALPHA
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

    local function on()
        local RL = ns.RouteList
        local s = ctx and ctx.settings
        if not RL or type(s) ~= "table" or type(s.get) ~= "function" then return true end
        -- The trail's own key (declared below, lead §543) and the route
        -- panel's. Both keys must be on for the trail to show.
        local okT, mt = pcall(s.get, s, MRL.TRAIL_SETTING)
        if okT and mt == false then return false end
        local ok, v = pcall(s.get, s, RL.SETTING)
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
        local pos = ask(c, "position")
        local lines = MRL.Lines(rows, map, pos, ask(c, "waypoint"), cornersOf)
        if #lines == 0 then clear() return lines end
        -- The next step, for the colour: "away" when it is on another map
        -- than you; otherwise the yards, from your position and the map's
        -- size. The palette is the arrow's. The next stop is the first
        -- row with a number; held stops (no number) are not the next one.
        local step, yards = nil, nil
        local firstPlace = nil
        if rows then
            for _, r in ipairs(rows) do
                if type(r) == "table" and r.n then firstPlace = r.place break end
            end
        end
        if pos and firstPlace and pos.map ~= nil and firstPlace.map ~= nil and firstPlace.map ~= pos.map then
            step = { state = "away" }
        elseif pos and firstPlace and pos.map ~= nil and firstPlace.map == pos.map then
            yards = MRL.Yards(pos, firstPlace, ask(c, "mapSize", pos.map))
        end
        -- R7: the family of the step the arrow chose, from the arrow
        -- module (the name string "arrow", Arrow.NAME). nil means the
        -- quest's own family. It rides on the step, so Paint asks the
        -- contract the same way the arrow does. Not taken from the View.
        local family = nil
        local arrow = k.use and k.use("arrow")
        if type(arrow) == "table" and type(arrow.Family) == "function" then
            local okF, f = pcall(arrow.Family)
            if okF and type(f) == "string" then family = f end
        end
        if family ~= nil then
            if step == nil then step = {} end
            step.family = family
        end
        local palette = nil
        local s = ctx.settings
        if type(s) == "table" and type(s.get) == "function" then
            local okP, p = pcall(s.get, s, "arrow.palette")
            if okP and type(p) == "string" then palette = p end
        end
        -- The player's one-colour setting (N43): false means one colour,
        -- the near one, for the route legs. The row is the arrow's; when
        -- it is not declared the setting is on, so nil reads as on.
        local byDistance = nil
        if type(s) == "table" and type(s.get) == "function" then
            local okB, b = pcall(s.get, s, "arrow.byDistance")
            if okB and b == false then byDistance = false end
        end
        local sig = { tostring(map) }
        for _, l in ipairs(lines) do
            local r, g, b, a = MRL.Paint(l.kind, step, yards, palette, byDistance)
            l.r, l.g, l.b, l.a = r, g, b, a
            sig[#sig + 1] = table.concat({ l.kind, l.ax, l.ay, l.bx, l.by, r, g, b, a }, "|")
        end
        sig = table.concat(sig, "\n")
        if drawn and sig == lastSig then return lines end
        local ok = pcall(handle.draw, lines)
        drawn = ok
        if ok then lastSig = sig else lastSig = nil end
        return lines
    end

    -- The trail's own key, declared here (lead §543: the row moves to
    -- slice 3 from slice 2). Both keys must be on for the trail to show;
    -- when the row is not declared, get returns nil, which reads as on.
    k:Setting({ key = MRL.TRAIL_SETTING, scope = "account", type = "bool", default = true,
        label = "Show route lines on the map", group = "travel.route",
        help = "Draws the dotted trail of your route on the world map, with an X at the next stop. Turning it off hides the trail only — the route list beside the quest log stays.",
        synonyms = { "route", "lines", "trail", "map", "X" } })

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
