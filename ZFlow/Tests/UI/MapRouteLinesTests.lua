local _, ns = ...

-- Tests for UI/MapRouteLines.lua (lead section 447 item 6, F7): the route
-- and waypoint lines on the world map. Pure parts, then the fake client's
-- lines. Made-up places and maps. Not tested in game.

local tests = {}

local function MRL() return ns.MapRouteLines end
local function RL() return ns.RouteList end

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

local function kinds(lines)
    local out = {}
    for _, l in ipairs(lines) do out[#out + 1] = l.kind end
    return table.concat(out, ",")
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

tests["lines: you to the first stop, then between later stops, then the waypoint"] = function(t)
    local rows = RL().Rows(view(), nil)
    local lines = MRL().Lines(rows, 1, { map = 1, x = 0.1, y = 0.1 }, { map = 1, x = 0.3, y = 0.9 })
    t.eq(kinds(lines), "first,rest,rest,waypoint")
    t.eq(lines[1].ax, 0.1)
    t.eq(lines[1].bx, 0.5)
    t.eq(lines[2].ax, 0.5)
    t.eq(lines[2].bx, 0.8)
    t.eq(lines[4].bx, 0.3)
    t.eq(lines[4].by, 0.9)
end

tests["lines: nothing with no map, no rows and no position"] = function(t)
    t.eq(#MRL().Lines(nil, nil, nil, nil), 0)
    t.eq(#MRL().Lines({}, 1, nil, { map = 1, x = 0.5, y = 0.5 }), 0, "no position: no waypoint line")
    t.eq(#MRL().Lines(nil, 1, { map = 1, x = 0.5, y = 0.5 }, nil), 0)
end

tests["clip: a line toward a spot beside the map stops at its edge"] = function(t)
    local x, y = MRL().Clip(0.5, 0.5, 1.5, 0.5)
    t.eq(x, 1)
    t.eq(y, 0.5)
    local p = MRL().Parts({ 1.5, 0.5 }, { 0.5, 0.5 })
    t.eq(p[1], 1)
    t.eq(p[3], 0.5)
    t.eq(MRL().Parts({ 1.5, 0.5 }, { 2, 2 }), nil, "both beside the map: nothing")
end

tests["place: a stop on another map of the same continent lands beside the shown map"] = function(t)
    local corners = {
        [1] = { cont = 9, ox = 0, oy = 0, ex = 100, ey = 0, sx = 0, sy = 100 },
        [2] = { cont = 9, ox = 100, oy = 0, ex = 200, ey = 0, sx = 100, sy = 100 },
        [3] = { cont = 8, ox = 0, oy = 0, ex = 100, ey = 0, sx = 0, sy = 100 },
    }
    local function cornersOf(m) return corners[m] end
    local same = { MRL().Place({ map = 1, x = 0.4, y = 0.4 }, 1, cornersOf) }
    t.eq(same[1], 0.4)
    local other = { MRL().Place({ map = 2, x = 0.5, y = 0.5 }, 1, cornersOf) }
    t.eq(other[1], 1.5, "half a map past the east edge")
    t.eq(other[2], 0.5)
    t.eq(MRL().Place({ map = 3, x = 0.5, y = 0.5 }, 1, cornersOf), nil, "another continent: no place")
    t.eq(MRL().Place({ map = 2, x = 0.5, y = 0.5 }, 1, nil), nil, "no corners: no place")
end

tests["paint: route blue, stronger first leg, green waypoint"] = function(t)
    local r, g, b, a = MRL().Paint("first")
    t.eq(b, 0xDD / 255)
    t.eq(a, MRL().FIRST_ALPHA)
    local _, _, _, ra = MRL().Paint("rest")
    t.eq(ra, MRL().REST_ALPHA)
    local _, wg = MRL().Paint("waypoint")
    t.eq(wg, 1)
    t.eq(r, 0)
    t.eq(g, 0x70 / 255)
end

tests["module: the shown map gets the lines with their colours"] = function(t)
    local h = start({ view = view() })
    h.c.setWorldMap(1)
    h.c.setPosition(1, 0.1, 0.1)
    h.c.setWaypoint(1, 0.3, 0.9)
    h.c.advance(1, 8)
    local set = h.c.routeLineSets[1]
    t.ok(set ~= nil, "a line handle is made")
    t.eq(kinds(set.lines), "first,rest,rest,waypoint")
    t.eq(set.lines[1].a, MRL().FIRST_ALPHA)
    t.eq(set.lines[2].a, MRL().REST_ALPHA)
    t.eq(set.lines[4].g, 1)
    local draws = set.draws
    h.c.advance(1, 8)
    t.eq(set.draws, draws, "unchanged lines are not drawn again")
end

tests["module: the map closed or the setting off clears the lines"] = function(t)
    local h = start({ view = view() })
    h.c.setWorldMap(1)
    h.c.setPosition(1, 0.1, 0.1)
    h.c.advance(1, 8)
    local set = h.c.routeLineSets[1]
    t.eq(set.shown, true)
    h.c.setWorldMap(nil)
    h.c.advance(1, 8)
    t.eq(set.shown, false)
    h.c.setWorldMap(1)
    h.c.advance(1, 8)
    t.eq(set.shown, true)
    h.k.settings:set(RL().SETTING, false)
    h.c.advance(1, 8)
    t.eq(set.shown, false)
end

return tests
