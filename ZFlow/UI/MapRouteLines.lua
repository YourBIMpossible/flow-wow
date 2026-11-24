-- The route's lines on the world map (lead section 447 item 6, F7): the
-- path from you to the next stop and on through the stops after it, and a
-- line from you to your own map waypoint. Ported from the predecessor's
-- Modules/Nav/MapOverlay.lua (drawRoute, drawWaypoint, M.LegParts,
-- M.ClipToMap, M.CrossesEdge), read only.
--
--   Pathing UI slice 3 (lead sections 519 and 525; Muse's
--   MUSE-TO-CLAUDE-PATHING-UI.md 4.3 and 6.4): the route is a treasure-map
--   trail. Every leg is dots, MRL.DOT wide and MRL.GAP apart, low in
--   opacity, so the map shows through; no leg is a solid line.
--   The leg from you to the next stop takes that step's distance colour,
--   the one the arrow has (Nav/RouteColor.lua RC.Of), at MRL.NEXT_ALPHA.
--   The legs after it stay faint (MRL.LATER_ALPHA) and run through the
--   route's gradient, purple to blue to orange, along their length.
--   An X (two strokes, MRL.X_COLOR) marks the destination: the last stop
--   of the route, when it is on the shown map. No dot is drawn under it.
--   The next stop on another map of the same continent: the leg still
--   starts at you and stops at the shown map's edge; looking at the stop's
--   own map, it comes in from the edge. A stop on another continent, or on
--   a map the client gives no corners for, breaks the line there.
--   Later legs are drawn only between stops that are both on the shown map
--   (the predecessor's rule: no line to a stop you are not walking to next).
--   Your waypoint (client.waypoint, the one the arrow points at in green):
--   a dotted green trail from you to it (RC.Of's waypoint colour), clipped
--   at the map's edge the same way, with no X.
-- Nothing is drawn when no line falls on the shown map. The setting
-- RL.SETTING (UI/RouteList.lua) turns it off with the list and the marks;
-- so does MRL.SETTING_LINES ("nav.mapLines", the map lines alone) once that
-- key exists (slice 2): a key that is not there is read as on.
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
--   MRL.Gradient(f) -> r, g, b   (pure) the route's gradient at share f
--   MRL.Destination(rows, map, cornersOf) -> x, y or nil   (pure) the last
--       stop of the route on the shown map
--   MRL.Trail(lines, w, h, opts) -> marks   (pure) the dots and the X for
--       a canvas w by h. opts: first = { r, g, b } the next leg's colour,
--       waypoint = { r, g, b }, dest = { x, y }. marks = { { ax, ay, bx, by,
--       r, g, b, a, thick, kind = "first" | "rest" | "waypoint" | "x" } }
--   MRL.NextStep(rows, you, sizeOf) -> step, yards   (pure) what RC.Of is
--       asked for the next leg
--   MRL.Declare(k) -> api   api.Refresh() -> lines or nil, api.Shown()
-- Not tested in game.
local _, ns = ...

local MRL = {}
ns.MapRouteLines = MRL

MRL.NAME = "mapRouteLines"
MRL.EVERY = 0.25
MRL.SETTING_LINES = "nav.mapLines"
-- Muse's values (PATHING-PLAYING-VIEW.html: a 2.5 stroke, dash "1 9", 0.55
-- opacity; the X in gold at 0.9; the gradient's three stops). LATER_ALPHA
-- keeps the old first-to-rest ratio (0.8 to 0.45) under the new 0.55.
MRL.DOT, MRL.GAP = 2.5, 10
MRL.NEXT_ALPHA, MRL.LATER_ALPHA = 0.55, 0.3
MRL.X_SIZE, MRL.X_THICK, MRL.X_ALPHA = 14, 3, 0.9
MRL.X_COLOR = { 0xE8 / 255, 0xC5 / 255, 0x47 / 255 }
-- { share along the later legs, r, g, b }
MRL.GRADIENT = {
    { 0, 0x7C / 255, 0x5C / 255, 0xFF / 255 },
    { 0.52, 0x2F / 255, 0x7B / 255, 0xFF / 255 },
    { 1, 0xFF / 255, 0x7A / 255, 0x1A / 255 },
}
-- The world map canvas when the client does not say its size (a first
-- guess: the classic map's canvas), and the most marks ever drawn.
MRL.CANVAS = { 1002, 668 }
MRL.MAX_MARKS = 400

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

function MRL.Gradient(f)
    local G = MRL.GRADIENT
    if not finite(f) or f <= G[1][1] then return G[1][2], G[1][3], G[1][4] end
    for i = 2, #G do
        local a, b = G[i - 1], G[i]
        if f == b[1] then return b[2], b[3], b[4] end
        if f < b[1] then
            local t = (f - a[1]) / (b[1] - a[1])
            return a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, a[4] + (b[4] - a[4]) * t
        end
    end
    local z = G[#G]
    return z[2], z[3], z[4]
end

function MRL.Destination(rows, map, cornersOf)
    local last
    for _, r in ipairs(type(rows) == "table" and rows or {}) do
        if type(r) == "table" and r.n then last = r end
    end
    if not last then return nil end
    local x, y = MRL.Place(last.place, map, cornersOf)
    if not x or not inside(x, y) then return nil end
    return x, y
end

-- What RC.Of is asked for the leg to the next stop: the step (in another
-- zone when it is on another map) and how far it is in yards, or nil when
-- the map's size is not known. sizeOf(map) -> { w, h } in yards.
function MRL.NextStep(rows, you, sizeOf)
    local nextRow
    for _, r in ipairs(type(rows) == "table" and rows or {}) do
        if not nextRow and type(r) == "table" and r.n then nextRow = r end
    end
    local step = {}
    if not nextRow or type(nextRow.place) ~= "table" or type(you) ~= "table" then return step, nil end
    local p = nextRow.place
    if p.map ~= you.map then
        step.state = "away"
        return step, nil
    end
    local size
    if type(sizeOf) == "function" then size = sizeOf(p.map) end
    if type(size) ~= "table" or not finite(size.w) or not finite(size.h) or size.w <= 0 or size.h <= 0 then
        return step, nil
    end
    if not finite(p.x) or not finite(p.y) or not finite(you.x) or not finite(you.y) then return step, nil end
    local dx, dy = (p.x - you.x) * size.w, (p.y - you.y) * size.h
    return step, math.sqrt(dx * dx + dy * dy)
end

function MRL.Trail(lines, w, h, opts)
    local out = {}
    if not finite(w) or not finite(h) or w <= 0 or h <= 0 then return out end
    opts = type(opts) == "table" and opts or {}
    local legs, total, later = {}, 0, 0
    for _, l in ipairs(type(lines) == "table" and lines or {}) do
        if type(l) == "table" and finite(l.ax) and finite(l.ay) and finite(l.bx) and finite(l.by) then
            local dx, dy = (l.bx - l.ax) * w, (l.by - l.ay) * h
            local len = math.sqrt(dx * dx + dy * dy)
            if len > 0 then
                legs[#legs + 1] = { l = l, len = len, ux = dx / len, uy = dy / len, before = later }
                total = total + len
                if l.kind == "rest" then later = later + len end
            end
        end
    end
    -- A very long route gets a wider gap, never more marks.
    local gap = MRL.GAP
    local room = MRL.MAX_MARKS - 2
    if total / gap > room then gap = total / room end
    local dest
    if type(opts.dest) == "table" and finite(opts.dest[1]) and finite(opts.dest[2]) then dest = opts.dest end
    local clear = MRL.X_SIZE / 2 + MRL.DOT / 2
    local first = type(opts.first) == "table" and opts.first or { 1, 1, 1 }
    local wp = type(opts.waypoint) == "table" and opts.waypoint or { 1, 1, 1 }
    for _, leg in ipairs(legs) do
        local l = leg.l
        local at = gap / 2
        while at < leg.len and #out < room do
            local cx, cy = l.ax * w + leg.ux * at, l.ay * h + leg.uy * at
            local under = false
            if dest then
                local ex, ey = cx - dest[1] * w, cy - dest[2] * h
                under = math.sqrt(ex * ex + ey * ey) < clear
            end
            if not under then
                local r, g, b, a
                if l.kind == "rest" then
                    r, g, b = MRL.Gradient((leg.before + at) / later)
                    a = MRL.LATER_ALPHA
                elseif l.kind == "waypoint" then
                    r, g, b, a = wp[1], wp[2], wp[3], MRL.NEXT_ALPHA
                else
                    r, g, b, a = first[1], first[2], first[3], MRL.NEXT_ALPHA
                end
                local half = MRL.DOT / 2
                out[#out + 1] = {
                    ax = (cx - leg.ux * half) / w, ay = (cy - leg.uy * half) / h,
                    bx = (cx + leg.ux * half) / w, by = (cy + leg.uy * half) / h,
                    r = r, g = g, b = b, a = a, thick = MRL.DOT, kind = l.kind,
                }
            end
            at = at + gap
        end
    end
    if dest then
        local half = MRL.X_SIZE / 2
        local x, y = dest[1] * w, dest[2] * h
        local c = MRL.X_COLOR
        out[#out + 1] = { ax = (x - half) / w, ay = (y - half) / h, bx = (x + half) / w, by = (y + half) / h,
                          r = c[1], g = c[2], b = c[3], a = MRL.X_ALPHA, thick = MRL.X_THICK, kind = "x" }
        out[#out + 1] = { ax = (x - half) / w, ay = (y + half) / h, bx = (x + half) / w, by = (y - half) / h,
                          r = c[1], g = c[2], b = c[3], a = MRL.X_ALPHA, thick = MRL.X_THICK, kind = "x" }
    end
    return out
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
        local ok, v = pcall(s.get, s, RL.SETTING)
        if ok and v == false then return false end
        -- Slice 2's key, the map lines alone. Not there yet: read as on.
        local okL, lines = pcall(s.get, s, MRL.SETTING_LINES)
        if okL and lines == false then return false end
        return true
    end

    -- The arrow's saved palette word, for RC.Of; nil is the standard one.
    local function palette()
        local s = ctx and ctx.settings
        local key = ns.Arrow and ns.Arrow.PALETTE
        if type(s) ~= "table" or type(s.get) ~= "function" or type(key) ~= "string" then return nil end
        local ok, v = pcall(s.get, s, key)
        if ok then return v end
        return nil
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
        local you = ask(c, "position")
        local lines = MRL.Lines(rows, map, you, ask(c, "waypoint"), cornersOf)
        local dx, dy = MRL.Destination(rows, map, cornersOf)
        if #lines == 0 and not dx then clear() return lines end
        -- The canvas's size: the client's when it says, else the guess.
        local w, ht = MRL.CANVAS[1], MRL.CANVAS[2]
        if type(handle.size) == "function" then
            local okS, sw, sh = pcall(handle.size)
            if okS and finite(sw) and finite(sh) and sw > 0 and sh > 0 then w, ht = sw, sh end
        end
        -- The next leg's colour is the step's, as the arrow has it.
        local RC = ns.RouteColor
        local first, green = { 1, 1, 1 }, { 1, 1, 1 }
        if type(RC) == "table" and type(RC.Of) == "function" then
            local word = palette()
            local step, yards = MRL.NextStep(rows, you, function(m) return ask(c, "mapSize", m) end)
            local okF, r, g, b = pcall(RC.Of, step, yards, word)
            if okF and finite(r) and finite(g) and finite(b) then first = { r, g, b } end
            local okW, wr, wg, wb = pcall(RC.Of, { family = "waypoint" }, nil, word)
            if okW and finite(wr) and finite(wg) and finite(wb) then green = { wr, wg, wb } end
        end
        local opts = { first = first, waypoint = green }
        if dx then opts.dest = { dx, dy } end
        local marks = MRL.Trail(lines, w, ht, opts)
        if #marks == 0 then clear() return lines end
        local sig = { tostring(map), tostring(w), tostring(ht),
            string.format("%.3f|%.3f|%.3f", first[1], first[2], first[3]), tostring(dx), tostring(dy) }
        for _, l in ipairs(lines) do
            sig[#sig + 1] = table.concat({ l.kind, l.ax, l.ay, l.bx, l.by }, "|")
        end
        sig = table.concat(sig, "\n")
        if drawn and sig == lastSig then return lines end
        local ok = pcall(handle.draw, marks)
        drawn = ok
        if ok then lastSig = sig else lastSig = nil end
        return lines
    end

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
