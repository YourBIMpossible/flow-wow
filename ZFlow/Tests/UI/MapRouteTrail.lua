local _, ns = ...

-- The treasure-map trail (pathing UI slice 3, lead sections 519 and 525;
-- Muse's MUSE-TO-CLAUDE-PATHING-UI.md 4.3 and 6.4): the route on the world
-- map is a dotted trail, thin and low in opacity, with an X at the
-- destination. The leg to the next stop takes that step's distance colour
-- (Nav/RouteColor.lua); the legs after it stay faint, in the route's
-- gradient. Pure parts, then the fake client's lines. Made-up places and
-- maps. Not tested in game. Red on 899a6f27: there is no MRL.Trail,
-- MRL.Gradient or MRL.Destination, and the module draws whole lines.

local tests = {}

local function MRL() return ns.MapRouteLines end
local function RL() return ns.RouteList end

local W, H = 1000, 500

local function view()
    return { kind = "quests", stops = {
        { quest = 11, objective = 1, label = "Boar Trouble", detail = "Boars slain: 2/8",
          place = { map = 1, x = 0.5, y = 0.6 } },
        { quest = 12, turnIn = true, label = "A Letter Home", detail = "Turn in",
          place = { map = 1, x = 0.8, y = 0.6 } },
        { quest = 13, turnIn = true, label = "Lost Tools", detail = "Turn in",
          place = { map = 1, x = 0.8, y = 0.2 } },
    }, left = {} }
end

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    local current = opts.view
    k:Module({ name = "tripRoute", provides = { View = function() return current end } })
    RL().Declare(k)
    local api = MRL().Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return { c = c, k = k, api = api, set = function(v) current = v end }
end

local function of(marks, kind)
    local out = {}
    for _, m in ipairs(marks) do
        if m.kind == kind then out[#out + 1] = m end
    end
    return out
end

-- How long a mark is, in canvas units.
local function long(m)
    local dx, dy = (m.bx - m.ax) * W, (m.by - m.ay) * H
    return math.sqrt(dx * dx + dy * dy)
end

local function near(a, b, tol) return math.abs(a - b) <= (tol or 1e-6) end

-- A mark's colour is r, g, b to within a rounding step.
local function coloured(m, r, g, b)
    return m ~= nil and near(m.r, r) and near(m.g, g) and near(m.b, b)
end

tests["trail: a leg is dots a gap apart, each a dot long, never one line"] = function(t)
    local M = MRL()
    -- 400 canvas units from (0.1, 0.5) to (0.5, 0.5).
    local marks = M.Trail({ { ax = 0.1, ay = 0.5, bx = 0.5, by = 0.5, kind = "first" } }, W, H,
        { first = { 1, 0.5, 0 } })
    local dots = of(marks, "first")
    t.eq(#dots, 400 / M.GAP, "one dot each gap along the leg")
    for i, m in ipairs(dots) do
        t.ok(near(long(m), M.DOT), "dot " .. i .. " is a dot long: " .. long(m))
        t.eq(m.thick, M.DOT, "and a dot thick")
        t.ok(m.ax >= 0.1 - 1e-9 and m.bx <= 0.5 + 1e-9, "on the leg")
        t.ok(near(m.ay, 0.5) and near(m.by, 0.5), "along it")
    end
    t.ok(near((dots[2].ax - dots[1].ax) * W, M.GAP), "a gap apart")
    local inked = #dots * M.DOT
    t.ok(inked < 400 * 0.35, "most of the leg is map, not ink: " .. inked)
end

tests["trail: the next leg takes the colour it is given; later legs are faint and in the route's gradient"] = function(t)
    local M = MRL()
    local lines = {
        { ax = 0.1, ay = 0.5, bx = 0.3, by = 0.5, kind = "first" },
        { ax = 0.3, ay = 0.5, bx = 0.6, by = 0.5, kind = "rest" },
        { ax = 0.6, ay = 0.5, bx = 0.9, by = 0.5, kind = "rest" },
    }
    local marks = M.Trail(lines, W, H, { first = { 0.2, 0.9, 0.3 } })
    for _, m in ipairs(of(marks, "first")) do
        t.eq({ m.r, m.g, m.b }, { 0.2, 0.9, 0.3 }, "the next leg: the step's colour")
        t.eq(m.a, M.NEXT_ALPHA)
    end
    local rest = of(marks, "rest")
    t.ok(#rest > 10, "later legs are dotted too")
    for _, m in ipairs(rest) do t.eq(m.a, M.LATER_ALPHA, "later legs stay faint") end
    t.ok(M.LATER_ALPHA < M.NEXT_ALPHA and M.NEXT_ALPHA <= 0.6, "thin ink: low opacity, the next leg the stronger")
    local a, z = rest[1], rest[#rest]
    local p, o = M.GRADIENT[1], M.GRADIENT[#M.GRADIENT]
    t.ok(near(a.r, p[2], 0.05) and near(a.b, p[4], 0.05), "the later legs start at the gradient's first colour")
    t.ok(near(z.r, o[2], 0.05) and near(z.b, o[4], 0.05), "and end at its last")
    t.ok(a.r ~= z.r, "never one flat colour along them")
end

tests["trail: the gradient runs purple, blue, orange"] = function(t)
    local M = MRL()
    t.eq({ M.Gradient(0) }, { 0x7C / 255, 0x5C / 255, 0xFF / 255 }, "purple")
    t.eq({ M.Gradient(0.52) }, { 0x2F / 255, 0x7B / 255, 0xFF / 255 }, "blue")
    t.eq({ M.Gradient(1) }, { 0xFF / 255, 0x7A / 255, 0x1A / 255 }, "orange")
    t.eq({ M.Gradient(-3) }, { M.Gradient(0) }, "before the start: the start")
    t.eq({ M.Gradient(7) }, { M.Gradient(1) }, "past the end: the end")
    t.eq({ M.Gradient(0 / 0) }, { M.Gradient(0) }, "not a number: the start")
    local r = M.Gradient(0.26)
    t.ok(r < 0x7C / 255 and r > 0x2F / 255, "between two stops it is between their colours")
end

tests["trail: an X marks the destination, and no dot is drawn over it"] = function(t)
    local M = MRL()
    local marks = M.Trail({ { ax = 0.1, ay = 0.5, bx = 0.5, by = 0.5, kind = "first" } }, W, H,
        { first = { 1, 1, 1 }, dest = { 0.5, 0.5 } })
    local x = of(marks, "x")
    t.eq(#x, 2, "two strokes")
    for _, m in ipairs(x) do
        t.ok(near((m.ax + m.bx) / 2, 0.5) and near((m.ay + m.by) / 2, 0.5), "crossing on the spot")
        t.eq(m.thick, M.X_THICK)
        t.eq({ m.r, m.g, m.b, m.a }, { M.X_COLOR[1], M.X_COLOR[2], M.X_COLOR[3], M.X_ALPHA })
        t.ok(long(m) > M.X_SIZE and long(m) < M.X_SIZE * 1.5, "an X of its size, corner to corner")
    end
    t.ok((x[1].by - x[1].ay) * (x[2].by - x[2].ay) < 0, "the two strokes cross")
    for _, m in ipairs(of(marks, "first")) do
        t.ok((0.5 - m.bx) * W >= M.X_SIZE / 2 - 1e-6, "no dot under the X")
    end
    t.eq(#of(M.Trail({}, W, H, { dest = { 0.5, 0.5 } }), "x"), 2, "the X with no leg on this map")
    t.eq(#of(M.Trail({ { ax = 0.1, ay = 0.5, bx = 0.5, by = 0.5, kind = "first" } }, W, H, {}), "x"), 0,
        "no destination on this map: no X")
end

tests["trail: your waypoint's line is dotted in its own colour, with no X"] = function(t)
    local M = MRL()
    local marks = M.Trail({ { ax = 0.2, ay = 0.2, bx = 0.6, by = 0.2, kind = "waypoint" } }, W, H,
        { waypoint = { 0.1, 1, 0 } })
    local dots = of(marks, "waypoint")
    t.eq(#dots, 400 / M.GAP)
    t.eq({ dots[1].r, dots[1].g, dots[1].b, dots[1].a }, { 0.1, 1, 0, M.NEXT_ALPHA })
    t.eq(#of(marks, "x"), 0)
end

tests["trail: a very long route is thinned out, never past the most marks; bad sizes draw nothing"] = function(t)
    local M = MRL()
    local lines = {}
    for i = 1, 40 do lines[i] = { ax = 0, ay = i / 50, bx = 1, by = i / 50, kind = "rest" } end
    local marks = M.Trail(lines, 4000, 4000, {})
    t.ok(#marks > 0 and #marks <= M.MAX_MARKS, "at most the most marks: " .. #marks)
    t.eq(M.Trail(lines, 0, 500, {}), {})
    t.eq(M.Trail(lines, 0 / 0, 500, {}), {})
    t.eq(M.Trail(nil, W, H, {}), {})
    t.eq(M.Trail({ { ax = 0.5, ay = 0.5, bx = 0.5, by = 0.5, kind = "first" } }, W, H, {}), {}, "no length: no dot")
end

tests["destination: the last stop of the route, when it is on the shown map"] = function(t)
    local M = MRL()
    local rows = RL().Rows(view(), nil)
    t.eq({ M.Destination(rows, 1, function() return nil end) }, { 0.8, 0.2 })
    t.eq({ M.Destination(rows, 2, function() return nil end) }, {}, "on another map with no corners: none")
    t.eq({ M.Destination({}, 1, function() return nil end) }, {})
    t.eq({ M.Destination(nil, 1, nil) }, {})
end

tests["module: the map gets a dotted trail, the next leg in the step's distance colour, an X at the end"] = function(t)
    local M = MRL()
    local h = start({ view = view() })
    h.c.setWorldMap(1)
    h.c.setMapSize(1, 1000, 1000)
    h.c.setPosition(1, 0.1, 0.6)
    h.c.advance(1, 8)
    local set = h.c.routeLineSets[1]
    t.ok(set ~= nil, "a line handle is made")
    local first, rest, x = of(set.lines, "first"), of(set.lines, "rest"), of(set.lines, "x")
    t.ok(#first > 5 and #rest > 5, "dots on the next leg and on the later ones")
    t.eq(#x, 2, "an X at the last stop")
    t.ok(near((x[1].ax + x[1].bx) / 2, 0.8) and near((x[1].ay + x[1].by) / 2, 0.2), "on the last stop")
    -- You are 400 yards from the first stop: the colour of a plain step at 400 yards.
    local r, g, b = ns.RouteColor.Of({}, 400, nil)
    t.ok(coloured(first[1], r, g, b), "the next leg is the step's distance colour")
    t.eq(first[1].a, M.NEXT_ALPHA)
    t.eq(rest[1].a, M.LATER_ALPHA)
    local draws = set.draws
    h.c.advance(1, 8)
    t.eq(set.draws, draws, "an unchanged trail is not drawn again")
    -- Walking closer changes the next leg's colour with the arrow's.
    h.c.setPosition(1, 0.46, 0.6)
    h.c.advance(1, 8)
    local nr, ng, nb = ns.RouteColor.Of({}, 40, nil)
    local now = of(set.lines, "first")
    t.ok(coloured(now[1], nr, ng, nb), "near: the near colour")
end

-- Section 236: a read that raises, then recovers; data arriving late.
tests["module: a size read that raises falls back and the trail is still drawn; a route set later is drawn then"] = function(t)
    local h = start({})
    h.c.setWorldMap(1)
    h.c.setPosition(1, 0.1, 0.6)
    h.c.advance(1, 8)
    local set = h.c.routeLineSets[1]
    t.ok(set == nil or set.shown == false, "no route: nothing drawn")
    h.set(view())
    h.c.advance(1, 8)
    set = h.c.routeLineSets[1]
    t.ok(set ~= nil and #of(set.lines, "first") > 5, "the route set later is drawn")
    local real = set.size
    set.size = function() error("no size (test)") end
    h.c.setPosition(1, 0.2, 0.6)
    h.c.advance(1, 8)
    t.ok(#of(set.lines, "first") > 3, "still drawn while the size read raises")
    set.size = real
    h.c.setPosition(1, 0.1, 0.6)
    h.c.advance(1, 8)
    t.ok(#of(set.lines, "first") > 5, "and after it answers again")
end

-- Slice 2's key (nav.mapLines) is not on this branch: until it lands the
-- trail follows the route list's setting, as the lines did.
tests["module: the route list's setting off clears the trail"] = function(t)
    local h = start({ view = view() })
    h.c.setWorldMap(1)
    h.c.setPosition(1, 0.1, 0.6)
    h.c.advance(1, 8)
    local set = h.c.routeLineSets[1]
    t.eq(set.shown, true)
    h.k.settings:set(RL().SETTING, false)
    h.c.advance(1, 8)
    t.eq(set.shown, false)
end

return tests
