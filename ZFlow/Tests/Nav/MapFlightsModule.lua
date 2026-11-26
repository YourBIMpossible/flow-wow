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
    c.setSaved(ns.id.charDB, {})
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

-- B-10 + B-11 (lead sections 780, 783): as Flow's flight-master pins
-- (Modules/Nav/MapFlights.lua): a left click picks one and draws a line to
-- every other on the shown map (MF.Pick -> MF.Click, MF.DrawLinks :470-500,
-- green where you can fly, red where you can't yet), and the next click
-- clears (:241-251, MF.Click); hovering one gives its name and words
-- (MF.TipLines), with one picked the flight from it to here (MF.FlightText,
-- :339-343), and what a click does (:344). Fails before: a pin carries no
-- words and a click does nothing.
local function third()
    local n = nodes()
    n["Cold Post"] = { cont = 1, wx = 3000, wy = 750 }
    return n
end

local function pinNamed(h, name)
    for _, p in ipairs(h.pins) do if p.name == name then return p end end
    return nil
end

tests["mapFlights module: each pin carries its words for the tooltip"] = function(t)
    local _, c = start({ on = true })
    c.setWorldMap(1414)
    c.advance(2, 8)
    local p = pinNamed(c.mapPinSets[1], "Home Post")
    t.eq(p and p.title, "Home Post")
    local tip = p and p.tip or {}
    t.eq(tip[1], "You have this flight path: you can fly here.")
    t.eq(tip[#tip - 1], MF.TIP_PICK, "what a click does")
    t.eq(tip[#tip], MF.TIP_POINT, "what a right click does (B-12)")
end

tests["mapFlights module: a click picks a master and lines go to the others; the next click clears"] = function(t)
    local _, c = start({ on = true, heading = BOARD, last = flightLast(), nodes = third() })
    c.setWorldMap(1414)
    c.advance(2, 8)
    local h = c.mapPinSets[1]
    t.eq(type(h.click), "function", "the fake can click")
    if type(h.click) ~= "function" then return end
    t.eq(#h.lines, 1, "the next step's flight")
    h.click("Home Post")
    t.eq(#h.lines, 2, "a line to each other master; the step's flight is not drawn while picking")
    local to = {}
    for _, l in ipairs(h.lines) do
        t.eq(l.from, "Home Post")
        t.eq(l.can, true, "you have both")
        to[#to + 1] = l.to
    end
    table.sort(to)
    t.eq(to, { "Cold Post", "Far Post" })
    local far = pinNamed(h, "Far Post")
    t.eq(far and far.picked, nil)
    t.eq(pinNamed(h, "Home Post").picked, true)
    local tip = far and far.tip or {}
    t.eq(tip[#tip - 2], "Home Post to Far Post: flight time not known yet", "the flight from the one picked")
    t.eq(tip[#tip - 1], MF.TIP_CLEAR)
    c.advance(2, 8)
    t.eq(#h.lines, 2, "it stays picked")
    h.click("Far Post")
    t.eq(#h.lines, 1, "the next click clears: the step's flight again")
    h.click("Home Post", "RightButton")
    t.eq(#h.lines, 1, "a right click picks nothing")
    h.click("Nowhere")
    t.eq(#h.lines, 1, "a name with no pin picks nothing")
end

tests["mapFlights module: a pick that leaves the map is dropped"] = function(t)
    local _, c = start({ on = true, nodes = third() })
    c.setWorldMap(1414)
    c.advance(2, 8)
    local h = c.mapPinSets[1]
    if type(h.click) ~= "function" then return t.ok(false, "no click") end
    h.click("Far Post")
    t.eq(#h.lines, 2)
    c.setWorldMap(1411)
    c.advance(2, 8)
    t.eq(#h.lines, 0, "Far Post is not on this map: nothing picked")
    c.setWorldMap(1414)
    c.advance(2, 8)
    t.eq(#h.lines, 0, "and it stays dropped")
end

-- B-12 (lead section 783): a right click on a flight master sets your own
-- waypoint on it through the existing waypoint path (Nav/Waypoint.lua
-- W.SetAt, as Alt + click on the map); a right click on the same one again
-- takes it off. As Flow's MF.RightClick / MF.PointAt / MF.WaypointOn
-- (Modules/Nav/MapFlights.lua:194-238). Fails before: a right click does
-- nothing.
tests["mapFlights module: a right click sets your waypoint on a master; again takes it off"] = function(t)
    local k, c = start({ on = true })
    c.setWorldMap(1414)
    c.advance(2, 8)
    local h = c.mapPinSets[1]
    if type(h.click) ~= "function" then return t.ok(false, "no click") end
    local W = ns.Nav.Waypoint
    local slot = W.Slot(k.store)
    t.eq(W.Get(slot), nil, "no waypoint first")
    h.click("Home Post", "RightButton")
    local wp = W.Get(slot)
    t.ok(wp ~= nil, "a waypoint is set")
    t.eq(wp and wp.map, 1414, "on the shown map")
    t.ok(wp and math.abs(wp.x - 0.052) < 1e-9 and math.abs(wp.y - 0.25) < 1e-9, "where the pin is")
    t.eq(wp and wp.label, MF.PointLabel({ name = "Home Post" }))
    c.advance(2, 8)
    local p = pinNamed(h, "Home Post")
    t.eq(p and p.tip[#p.tip], MF.TIP_UNPOINT, "its tip says a right click takes it off")
    t.eq(c.mapPinSets[1].lines[1], nil, "nothing picked by a right click")
    h.click("Home Post", "RightButton")
    t.eq(W.Get(slot), nil, "the same again: taken off")
    h.click("Far Post", "RightButton")
    t.eq(W.Get(slot) and W.Get(slot).label, MF.PointLabel({ name = "Far Post" }))
    h.click("Home Post", "RightButton")
    t.eq(W.Get(slot) and W.Get(slot).label, MF.PointLabel({ name = "Home Post" }), "another master: moved there")
    h.click("Nowhere", "RightButton")
    t.eq(W.Get(slot) and W.Get(slot).label, MF.PointLabel({ name = "Home Post" }), "no pin: nothing changes")
end

tests["mapFlights module: a pick draws its line styled, solid green and thin"] = function(t)
    local _, c = start({ on = true })
    c.setWorldMap(1414)
    c.advance(2, 8)
    local h = c.mapPinSets[1]
    h.click("Home Post")
    t.eq(#h.lines, 1)
    local l = h.lines[1]
    t.eq(l.to, "Far Post")
    t.eq({ l.r, l.g, l.b }, { 0x66 / 255, 1, 0x66 / 255 }, "can: the solid green")
    t.eq(l.width, MF.LINE_THIN)
    t.eq(l.a, 0.8)
    t.eq(l.dashOn, nil)
    t.eq(l.label, nil, "no mouse: no label")
end

tests["mapFlights module: the mouse on the line makes it bold with its label"] = function(t)
    local _, c = start({ on = true })
    c.setWorldMap(1414)
    c.advance(2, 8)
    local h = c.mapPinSets[1]
    h.click("Home Post")
    c.setMapMouse(0.3, 0.375, 1000, 500)
    c.advance(2, 8)
    local l = h.lines[1]
    t.eq(l.width, MF.LINE_BOLD, "bold under the mouse")
    t.eq(l.a, 1)
    t.eq(l.label, "Far Post · flight time not known yet")
    c.setMapMouse(0.9, 0.05, 1000, 500)
    c.advance(2, 8)
    t.eq(h.lines[1].width, MF.LINE_THIN, "thin again off the line")
    t.eq(h.lines[1].label, nil)
end

return tests
