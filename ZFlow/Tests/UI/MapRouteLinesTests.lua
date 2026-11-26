local _, ns = ...

-- Tests for UI/MapRouteLines.lua (lead section 447 item 6, F7; pathing UI
-- slice 3): the dotted trail and the X on the world map, in the shared
-- colour contract. Pure parts, then the fake client's lines. Made-up
-- places and maps. Not tested in game.

local tests = {}

local function MRL() return ns.MapRouteLines end
local function RL() return ns.RouteList end
local function TL() return ns.Nav.TrackerList end

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

-- The kinds in order, consecutive duplicates collapsed: one dashed leg is
-- many lines of the same kind.
local function kinds(lines)
    local out = {}
    for _, l in ipairs(lines) do
        if out[#out] ~= l.kind then out[#out + 1] = l.kind end
    end
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
    local rows = TL().Rows(view(), nil, TL().ALL)
    local lines = MRL().Lines(rows, 1, { map = 1, x = 0.1, y = 0.1 }, { map = 1, x = 0.3, y = 0.9 })
    -- the kinds, runs collapsed: the two later legs are one run of "rest"
    t.eq(kinds(lines), "first,rest,waypoint,x")
    -- the first leg is dashes, not one line: it starts at you and the
    -- last dash ends at the first stop
    t.eq(lines[1].kind, "first")
    t.eq(lines[1].ax, 0.1)
    t.eq(lines[1].ay, 0.1)
    local lastFirst
    for _, l in ipairs(lines) do if l.kind == "first" then lastFirst = l end end
    t.eq(lastFirst.bx, 0.5)
    t.eq(lastFirst.by, 0.6)
    -- two later legs, told apart by where their dashes start and end
    local restStart, restMid, restEnd = false, false, false
    for _, l in ipairs(lines) do
        if l.kind == "rest" then
            if l.ax == 0.5 and l.ay == 0.6 then restStart = true end
            if l.ax == 0.8 and l.ay == 0.6 then restMid = true end
            if l.bx == 0.8 and l.by == 0.2 then restEnd = true end
        end
    end
    t.ok(restStart, "a later leg starts at the first stop")
    t.ok(restMid, "a later leg starts at the second stop")
    t.ok(restEnd, "a later leg ends at the third stop")
    -- the waypoint line is one solid line, you to the waypoint
    local wp
    for _, l in ipairs(lines) do if l.kind == "waypoint" then wp = l end end
    t.eq(wp.ax, 0.1)
    t.eq(wp.ay, 0.1)
    t.eq(wp.bx, 0.3)
    t.eq(wp.by, 0.9)
    -- the X marks the first stop: two strokes, one centre
    local xs = {}
    for _, l in ipairs(lines) do if l.kind == "x" then xs[#xs + 1] = l end end
    t.eq(#xs, 2)
    local mx1, my1 = (xs[1].ax + xs[1].bx) / 2, (xs[1].ay + xs[1].by) / 2
    local mx2, my2 = (xs[2].ax + xs[2].bx) / 2, (xs[2].ay + xs[2].by) / 2
    t.eq(mx1, mx2)
    t.eq(my1, my2)
    t.ok(mx1 > 0.48 and mx1 < 0.52, "the X is centred on the first stop")
    t.ok(my1 > 0.58 and my1 < 0.62, "the X is centred on the first stop")
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

tests["dash: a line splits into dashes, a short line is one, a point is none"] = function(t)
    local d = MRL().Dash(0, 0, 0.1, 0)
    t.eq(#d, 4, "0.1 of shares at 0.02 a dash and 0.012 a gap")
    t.eq(d[1][1], 0)
    t.eq(d[1][2], 0)
    t.eq(d[4][3], 0.1)
    t.eq(d[4][4], 0)
    local short = MRL().Dash(0, 0, 0.01, 0)
    t.eq(#short, 1)
    t.eq(short[1][1], 0)
    t.eq(short[1][3], 0.01)
    t.eq(#MRL().Dash(0, 0, 0, 0), 0)
end

tests["x: two strokes, one centre, crossing"] = function(t)
    local s = MRL().X(0.5, 0.5)
    t.eq(#s, 2)
    t.ok(s[1][1] < s[1][3] and s[1][2] < s[1][4], "one stroke runs down and right")
    t.ok(s[2][1] < s[2][3] and s[2][2] > s[2][4], "the other runs up and right")
    local mx1, my1 = (s[1][1] + s[1][3]) / 2, (s[1][2] + s[1][4]) / 2
    local mx2, my2 = (s[2][1] + s[2][3]) / 2, (s[2][2] + s[2][4]) / 2
    t.eq(mx1, mx2)
    t.eq(my1, my2)
    t.ok(mx1 > 0.48 and mx1 < 0.52, "centred on the point")
    t.ok(my1 > 0.48 and my1 < 0.52, "centred on the point")
end

tests["yards: straight-line yards on the same map, none otherwise"] = function(t)
    t.eq(MRL().Yards({ map = 1, x = 0.1, y = 0.1 }, { map = 1, x = 0.7, y = 0.1 }, { w = 1000, h = 1000 }), 600)
    t.eq(MRL().Yards({ map = 1, x = 0.1, y = 0.1 }, { map = 2, x = 0.7, y = 0.1 }, { w = 1000, h = 1000 }), nil, "another map")
    t.eq(MRL().Yards({ map = 1, x = 0.1, y = 0.1 }, { map = 1, x = 0.7, y = 0.1 }, nil), nil, "no size")
    t.eq(MRL().Yards(nil, { map = 1, x = 0.7, y = 0.1 }, { w = 1000, h = 1000 }), nil, "no position")
end

tests["lines: no X when the next stop is on another map"] = function(t)
    local corners = {
        [1] = { cont = 9, ox = 0, oy = 0, ex = 100, ey = 0, sx = 0, sy = 100 },
        [2] = { cont = 9, ox = 100, oy = 0, ex = 200, ey = 0, sx = 100, sy = 100 },
    }
    local function cornersOf(m) return corners[m] end
    local v = { kind = "quests", stops = {
        { quest = 11, label = "Over There", detail = "Go", place = { map = 2, x = 0.5, y = 0.5 } },
    }, left = {} }
    local rows = TL().Rows(v, nil, TL().ALL)
    local lines = MRL().Lines(rows, 1, { map = 1, x = 0.1, y = 0.1 }, nil, cornersOf)
    t.eq(kinds(lines), "first", "the leg is clipped at the edge, and no X")
    for _, l in ipairs(lines) do t.ok(l.kind ~= "x", "no X for a stop off the map") end
end

tests["paint: the contract's colours, stronger first leg, gold X"] = function(t)
    local RC = ns.RouteColor
    -- far and near come from the contract, not a colour of this file
    local fr, fg, fb = RC.Of(nil, 600, "standard")
    local r, g, b, a = MRL().Paint("first", nil, 600, "standard")
    t.eq(r, fr)
    t.eq(g, fg)
    t.eq(b, fb)
    t.eq(a, MRL().FIRST_ALPHA)
    local nr, ng, nb = RC.Of(nil, 40, "standard")
    local r2, g2, b2 = MRL().Paint("first", nil, 40, "standard")
    t.eq(r2, nr)
    t.eq(g2, ng)
    t.eq(b2, nb)
    -- later legs: the same colour, fainter
    local rr, rg, rb, ra = MRL().Paint("rest", nil, 600, "standard")
    t.eq(rr, fr)
    t.eq(rg, fg)
    t.eq(rb, fb)
    t.eq(ra, MRL().REST_ALPHA)
    -- away: grey, from the contract
    local ar, ag, ab = MRL().Paint("first", { state = "away" }, nil, "standard")
    t.eq(ar, 0x9E / 255)
    t.eq(ag, 0xA0 / 255)
    t.eq(ab, 0xA8 / 255)
    -- waypoint: green, at the first-leg strength
    local wr, wg, wb, wa = MRL().Paint("waypoint", nil, nil, "standard")
    t.eq(wr, 0x1E / 255)
    t.eq(wg, 1)
    t.eq(wb, 0)
    t.eq(wa, MRL().FIRST_ALPHA)
    -- X: gold, at the first-leg strength
    local xr, xg, xb, xa = MRL().Paint("x", nil, nil, "standard")
    t.eq(xr, 0xE6 / 255)
    t.eq(xg, 0x9F / 255)
    t.eq(xb, 0)
    t.eq(xa, MRL().FIRST_ALPHA)
end

tests["paint: one colour when the player's setting says so (N43)"] = function(t)
    local RC = ns.RouteColor
    -- far is the near colour, not the far one, when the setting is off
    local nr, ng, nb = RC.Of(nil, 600, "standard", false)
    local r, g, b, a = MRL().Paint("first", nil, 600, "standard", false)
    t.eq(r, nr)
    t.eq(g, ng)
    t.eq(b, nb)
    t.eq(a, MRL().FIRST_ALPHA)
    t.eq(nr, 0x33 / 255)
    t.eq(ng, 0xF2 / 255)
    t.eq(nb, 0x4D / 255)
    -- the waypoint stays its green, one colour or not
    local wr, wg, wb = MRL().Paint("waypoint", nil, nil, "standard", false)
    t.eq(wr, 0x1E / 255)
    t.eq(wg, 1)
    t.eq(wb, 0)
end

tests["module: the shown map gets the lines with their colours"] = function(t)
    local h = start({ view = view() })
    h.c.setWorldMap(1)
    h.c.setPosition(1, 0.1, 0.1)
    h.c.setWaypoint(1, 0.3, 0.9)
    h.c.advance(1, 8)
    local set = h.c.routeLineSets[1]
    t.ok(set ~= nil, "a line handle is made")
    t.eq(kinds(set.lines), "first,rest,waypoint,x")
    -- no map size is set, so the yards are not known: the next leg is far
    t.eq(set.lines[1].r, 0xFF / 255)
    t.eq(set.lines[1].g, 0x8C / 255)
    t.eq(set.lines[1].b, 0x1A / 255)
    t.eq(set.lines[1].a, MRL().FIRST_ALPHA)
    -- B-17 (lead section 894): the later legs wear the order mode's colour,
    -- fainter; nothing set, so the default mode in the standard palette
    local rest
    for _, l in ipairs(set.lines) do if l.kind == "rest" then rest = l break end end
    t.ok(rest ~= nil, "a later leg is drawn")
    t.eq(rest.a, MRL().REST_ALPHA)
    local ROC = ns.RouteOrderColor
    local mr, mg, mb = ROC.Color(ROC.DEFAULT, "standard")
    t.eq(rest.r, mr, "later legs: the order mode colour")
    t.eq(rest.g, mg)
    t.eq(rest.b, mb)
    -- the waypoint line is green; the X is gold
    local wp, x
    for _, l in ipairs(set.lines) do if l.kind == "waypoint" then wp = l end if l.kind == "x" then x = l end end
    t.ok(wp ~= nil, "a waypoint line is drawn")
    t.eq(wp.g, 1)
    t.ok(x ~= nil, "an X is drawn")
    t.eq(x.r, 0xE6 / 255)
    t.eq(x.g, 0x9F / 255)
    t.eq(x.b, 0)
    local draws = set.draws
    h.c.advance(1, 8)
    t.eq(set.draws, draws, "unchanged lines are not drawn again")
end

tests["module: a known map size colours the next leg by its yards"] = function(t)
    local v = { kind = "quests", stops = {
        { quest = 11, label = "Far Off", detail = "Go", place = { map = 1, x = 0.7, y = 0.1 } },
    }, left = {} }
    local h = start({ view = v })
    h.c.setWorldMap(1)
    h.c.setMapSize(1, 1000, 1000)
    h.c.setPosition(1, 0.1, 0.1)
    h.c.advance(1, 8)
    local set = h.c.routeLineSets[1]
    t.ok(set ~= nil, "a line handle is made")
    t.eq(kinds(set.lines), "first,x")
    -- 600 yards out: far, exactly the contract's far orange
    t.eq(set.lines[1].r, 0xFF / 255)
    t.eq(set.lines[1].g, 0x8C / 255)
    t.eq(set.lines[1].b, 0x1A / 255)
end

tests["module: one colour when the player's setting says so (N43)"] = function(t)
    local h = start({ view = view() })
    h.c.setWorldMap(1)
    h.c.setPosition(1, 0.1, 0.1)
    h.c.advance(1, 8)
    local set = h.c.routeLineSets[1]
    t.ok(set ~= nil, "a line handle is made")
    -- the setting is on by default: the next leg is far (no map size)
    t.eq(set.lines[1].r, 0xFF / 255)
    h.k:Setting({ key = "arrow.byDistance", scope = "account", type = "bool", default = true,
        label = "Arrow colour by distance", group = "travel.arrow" })
    h.k.settings:set("arrow.byDistance", false)
    h.c.advance(1, 8)
    -- one colour: the near green, whatever the distance
    t.eq(set.lines[1].r, 0x33 / 255)
    t.eq(set.lines[1].g, 0xF2 / 255)
    t.eq(set.lines[1].b, 0x4D / 255)
    h.k.settings:set("arrow.byDistance", true)
    h.c.advance(1, 8)
    t.eq(set.lines[1].r, 0xFF / 255, "back to the distance colours")
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
    h.k.settings:set(RL().SETTING, true)
    h.c.advance(1, 8)
    t.eq(set.shown, true)
    -- the trail's own key, declared by the module (lead §543)
    h.k.settings:set("nav.mapTrail", false)
    h.c.advance(1, 8)
    t.eq(set.shown, false)
    h.k.settings:set("nav.mapTrail", true)
    h.c.advance(1, 8)
    t.eq(set.shown, true)
end

tests["paint: without the contract, the route blue follows the palette (F-23)"] = function(t)
    local saved = ns.RouteColor
    ns.RouteColor = nil
    local ok, err = pcall(function()
        local r, g, b, a = MRL().Paint("first", nil, 600, "standard")
        t.eq({ r, g, b }, { 0, 0x70 / 255, 0xDD / 255 }, "standard: today's blue")
        t.eq(a, MRL().FIRST_ALPHA)
        local cr, cg, cb, ca = MRL().Paint("rest", nil, 600, "colourBlind")
        t.eq({ cr, cg, cb }, { 0, 0x72 / 255, 0xB2 / 255 }, "colour-blind: Flow's blue")
        t.eq(ca, MRL().REST_ALPHA)
    end)
    ns.RouteColor = saved
    t.ok(ok, tostring(err))
end

tests["paint: the route legs take the order mode's colour (B-17)"] = function(t)
    local saved = ns.RouteOrderColor
    ns.RouteOrderColor = { Color = function(mode, palette)
        if mode == "xp" and palette == "standard" then return 0.1, 0.2, 0.3 end
        return 0.9, 0.9, 0.9
    end }
    local r, g, b, a = MRL().Paint("first", nil, 600, "standard", nil, "xp")
    local rr, rg, rb, ra = MRL().Paint("rest", nil, 600, "standard", nil, "xp")
    local wr = MRL().Paint("waypoint", nil, nil, "standard", nil, "xp")
    local xr = MRL().Paint("x", nil, nil, "standard", nil, "xp")
    local nr = MRL().Paint("rest", nil, 600, "standard")
    local fr, fg, fb, fa = MRL().Paint("first", nil, 600, "standard")
    ns.RouteOrderColor = saved
    t.eq({ r, g, b, a }, { fr, fg, fb, fa }, "first leg: the arrow colour, as Flow's live leg")
    t.eq(rr, 0.1, "later legs: the mode colour")
    t.eq(rg, 0.2)
    t.eq(rb, 0.3)
    t.eq(ra, MRL().REST_ALPHA, "later legs stay fainter")
    t.ok(wr ~= 0.1, "the waypoint keeps its own colour")
    t.ok(xr ~= 0.1, "the X keeps its own colour")
    t.ok(nr ~= 0.1, "no order mode: the contract colour")
end

return tests
