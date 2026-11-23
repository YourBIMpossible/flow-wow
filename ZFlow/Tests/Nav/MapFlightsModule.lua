local _, ns = ...

-- Tests for the mapFlights module in ZFlow/Nav/MapFlights.lua (lead section
-- 187 section 7): while the world map shows, MF.Pins of the saved flight
-- points (k.use("flights").Nodes(), or a travel preview's points) drawn on
-- it (client.mapPins), with the next step's flight as a line. Reads
-- nav.mapFlights (off by default). The arrow and the flights modules are
-- stand-ins here. Made-up places; fake client. Not tested in game.

local MF = ns.MapFlights
local tests = {}

local BOARD = { cont = 1, map = 1411, x = 0.52, y = 0.5 }

local function nodes()
    return {
        ["Home Post"] = { cont = 1, wx = 520, wy = 250 },
        ["Far Post"] = { cont = 1, wx = 5480, wy = 500 },
    }
end

local function flightLast()
    return { from = "Home Post", to = "Far Post", board = { map = 1411, x = 0.52, y = 0.5 },
        there = { cont = 1, wx = 5500, wy = 500 } }
end

-- Map 1414 (continent 1) spans world x 0..10000, y 0..1000; map 1411 is
-- x 0..1000, y 0..500; map 1430 is on continent 0.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setMapCorners(1414, { cont = 1, ox = 0, oy = 0, ex = 10000, ey = 0, sx = 0, sy = 1000 })
    c.setMapCorners(1411, { cont = 1, ox = 0, oy = 0, ex = 1000, ey = 0, sx = 0, sy = 500 })
    c.setMapCorners(1430, { cont = 0, ox = 0, oy = 0, ex = 1000, ey = 0, sx = 0, sy = 1000 })
    local k = ns.Kernel({}, c)
    local state = { heading = opts.heading, last = opts.last, nodes = opts.nodes == nil and nodes() or opts.nodes }
    k:Module({ name = "arrow", provides = { Heading = function() return state.heading end } })
    k:Module({ name = "flights", provides = {
        Last = function() return state.last end,
        Nodes = function() return state.nodes or nil end,
    } })
    MF.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    if opts.on then k.settings:set(MF.SETTING, true) end
    return k, c, state
end

local function names(h)
    local out = {}
    for i, p in ipairs(h.pins) do out[i] = p.name .. ":" .. p.kind .. ":" .. tostring(p.role) end
    return table.concat(out, ", ")
end

tests["mapFlights module: started, its row declared, off by default, and off draws nothing"] = function(t)
    local k, c = start()
    t.eq(MF.NAME, "mapFlights")
    t.eq((k:ModuleState(MF.NAME)), "started")
    t.ok(k.settings:row(MF.SETTING) ~= nil, "a row")
    t.eq(k.settings:get(MF.SETTING), false)
    c.setWorldMap(1414)
    c.advance(2, 8)
    t.eq(#c.mapPinSets, 0, "nothing made while off")
end

tests["mapFlights module: on, the world map shows a pin for each known point on it"] = function(t)
    local k, c = start({ on = true })
    c.setWorldMap(1414)
    c.advance(2, 8)
    local h = c.mapPinSets[1]
    t.ok(h ~= nil, "pins made")
    t.eq(names(h), "Far Post:have:nil, Home Post:have:nil")
    t.ok(math.abs(h.pins[2].x - 0.052) < 1e-9 and math.abs(h.pins[2].y - 0.25) < 1e-9, "Home Post at its share")
    t.eq(#h.lines, 0, "no flight step: no line")
    t.eq(k.problems:count(), 0)
end

tests["mapFlights module: the next step's flight gives its two roles and a line"] = function(t)
    local _, c = start({ on = true, heading = BOARD, last = flightLast() })
    c.setWorldMap(1414)
    c.advance(2, 8)
    local h = c.mapPinSets[1]
    t.eq(names(h), "Far Post:have:to, Home Post:have:from")
    t.eq(#h.lines, 1)
    t.eq({ h.lines[1].from, h.lines[1].to }, { "Home Post", "Far Post" })
end

tests["mapFlights module: a flight the arrow is not on gives no roles"] = function(t)
    local _, c = start({ on = true, heading = { cont = 1, map = 1411, x = 0.9, y = 0.9 }, last = flightLast() })
    c.setWorldMap(1414)
    c.advance(2, 8)
    t.eq(names(c.mapPinSets[1]), "Far Post:have:nil, Home Post:have:nil")
end

tests["mapFlights module: only points on the shown map; another continent's map shows none"] = function(t)
    local _, c = start({ on = true, heading = BOARD, last = flightLast() })
    c.setWorldMap(1411)
    c.advance(2, 8)
    local h = c.mapPinSets[1]
    t.eq(names(h), "Home Post:have:from")
    t.eq(#h.lines, 0, "Far Post is off this map: no line")
    c.setWorldMap(1430)
    c.advance(2, 8)
    t.eq(#h.pins, 0)
end

tests["mapFlights module: the map closing, or the setting off, clears the pins"] = function(t)
    local k, c = start({ on = true })
    c.setWorldMap(1414)
    c.advance(2, 8)
    local h = c.mapPinSets[1]
    t.eq(h.shown, true)
    c.setWorldMap(nil)
    c.advance(2, 8)
    t.eq(h.shown, false, "closed")
    c.setWorldMap(1414)
    c.advance(2, 8)
    t.eq(h.shown, true)
    k.settings:set(MF.SETTING, false)
    c.advance(2, 8)
    t.eq(h.shown, false, "off")
    t.eq(#c.mapPinSets, 1, "one set of pins, kept")
end

tests["mapFlights module: a travel preview's points are drawn in place of the saved ones"] = function(t)
    local last = flightLast()
    last.from, last.to = "Made Master", "Made Landing"
    last.points = {
        ["Made Master"] = { cont = 1, wx = 530, wy = 250 },
        ["Made Landing"] = { cont = 1, wx = 5000, wy = 400 },
    }
    local _, c = start({ on = true, heading = BOARD, last = last })
    c.setWorldMap(1414)
    c.advance(2, 8)
    local h = c.mapPinSets[1]
    t.eq(names(h), "Made Landing:have:to, Made Master:have:from")
    t.eq(#h.lines, 1)
end

tests["mapFlights module: no saved points draws no pins"] = function(t)
    local _, c = start({ on = true, nodes = false })
    c.setWorldMap(1414)
    c.advance(2, 8)
    local h = c.mapPinSets[1]
    t.eq(h and #h.pins or 0, 0)
end

return tests
