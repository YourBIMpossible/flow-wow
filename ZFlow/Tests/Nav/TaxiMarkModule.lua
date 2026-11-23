local _, ns = ...

-- Tests for the taxiMark module in ZFlow/Nav/TaxiMark.lua (lead section 187
-- section 7): on the flight map opening, ring the flight master TM.Pick
-- chooses for the next step (client.taxiMark); hide it on the closing.
-- Reads nav.taxiMark (on by default). The arrow and the flights modules are
-- stand-ins here. Made-up places; fake client. Not tested in game.
-- Look only: nothing takes a flight.

local TM = ns.TaxiMark
local tests = {}

-- The flight map 1414 spans world x 0..10000, y 0..1000 on continent 1.
-- Home Post (0.052, 0.25) is world (520, 250); Far Post (0.548, 0.5) is
-- world (5480, 500); the wolves are at (5500, 500).
local CORNERS = { cont = 1, ox = 0, oy = 0, ex = 10000, ey = 0, sx = 0, sy = 1000 }
local BOARD = { cont = 1, map = 1411, x = 0.52, y = 0.5 }

local function read()
    return { map = 1414, here = "Home Post", nodes = {
        { name = "Home Post", x = 0.052, y = 0.25, state = "current" },
        { name = "Far Post", x = 0.548, y = 0.5, state = "reachable" },
        { name = "Shut Post", x = 0.55, y = 0.5, state = "unreachable" },
    } }
end

local function flightLast()
    return { from = "Home Post", to = "Far Post", board = { map = 1411, x = 0.52, y = 0.5 },
        there = { cont = 1, wx = 5500, wy = 500 } }
end

-- opts.heading, opts.last: what the stand-ins answer (a function or a value).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setMapCorners(1414, CORNERS)
    local k = ns.Kernel({}, c)
    local state = { heading = opts.heading, last = opts.last }
    k:Module({ name = "arrow", provides = { Heading = function() return state.heading end } })
    k:Module({ name = "flights", provides = { Last = function() return state.last end, Nodes = function() return nil end } })
    TM.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, state
end

local function open(c, r)
    c.setTaxiNodes(r == nil and read() or r or nil)
    c.fire("TAXIMAP_OPENED")
end

local function close(c)
    c.setTaxiNodes(nil)
    c.fire("TAXIMAP_CLOSED")
end

tests["taxiMark module: started, its row declared, on by default"] = function(t)
    local k = start()
    t.eq(TM.NAME, "taxiMark")
    t.eq((k:ModuleState(TM.NAME)), "started")
    t.ok(k.settings:row(TM.SETTING) ~= nil, "a row")
    t.eq(k.settings:get(TM.SETTING), true)
end

tests["taxiMark module: the flight map opening rings the master that lands nearest the step"] = function(t)
    local k, c = start({ heading = BOARD, last = flightLast() })
    open(c)
    local h = c.taxiMarks[1]
    t.ok(h ~= nil, "a ring was made")
    t.eq(h.shown, true)
    t.eq(h.node, { name = "Far Post", x = 0.548, y = 0.5 })
    t.eq(h.label, TM.Label(nil))
    t.eq(k.use(TM.NAME).Marked(), "Far Post")
    t.eq(k.problems:count(), 0)
end

tests["taxiMark module: the flight map closing hides the ring"] = function(t)
    local k, c = start({ heading = BOARD, last = flightLast() })
    open(c)
    close(c)
    t.eq(c.taxiMarks[1].shown, false)
    t.eq(k.use(TM.NAME).Marked(), nil)
end

tests["taxiMark module: the setting off rings nothing; switched off while open hides it"] = function(t)
    local k, c = start({ heading = BOARD, last = flightLast() })
    k.settings:set(TM.SETTING, false)
    open(c)
    t.eq(#c.taxiMarks, 0, "nothing made")
    close(c)
    k.settings:set(TM.SETTING, true)
    open(c)
    t.eq(c.taxiMarks[1].shown, true)
    k.settings:set(TM.SETTING, false)
    c.advance(2, 8)
    t.eq(c.taxiMarks[1].shown, false, "hidden at the next look while the map is open")
end

tests["taxiMark module: an arrow step that is not the flight's board point is the step itself"] = function(t)
    -- The arrow heads straight at Far Post's own spot on 1414; no flight
    -- was picked by the flights module.
    local _, c = start({ heading = { cont = 1, map = 1414, x = 0.548, y = 0.5 }, last = flightLast() })
    open(c)
    t.eq(c.taxiMarks[1] and c.taxiMarks[1].node.name, "Far Post")
end

tests["taxiMark module: no step, a step nearer where you stand, or no read: no ring"] = function(t)
    local _, c = start()
    open(c)
    t.eq(#c.taxiMarks, 0, "no step")
    close(c)
    local _, c2 = start({ heading = { cont = 1, map = 1414, x = 0.06, y = 0.25 } })
    open(c2)
    t.eq(#c2.taxiMarks, 0, "the step is by Home Post, where you stand")
    local _, c3 = start({ heading = BOARD, last = flightLast() })
    open(c3, false)
    t.eq(#c3.taxiMarks, 0, "no flight map read")
end

tests["taxiMark module: an unreachable master is never rung"] = function(t)
    local r = read()
    r.nodes[2].state = "unreachable"
    local _, c = start({ heading = BOARD, last = flightLast() })
    open(c, r)
    t.eq(#c.taxiMarks, 0)
end

tests["taxiMark module: while the map is open a step that comes later is rung at the next look"] = function(t)
    local _, c, state = start()
    open(c)
    t.eq(#c.taxiMarks, 0)
    state.heading, state.last = BOARD, flightLast()
    c.advance(2, 8)
    t.eq(c.taxiMarks[1] and c.taxiMarks[1].shown, true)
    close(c)
    state.heading = nil
    c.advance(2, 8)
    t.eq(c.taxiMarks[1].shown, false, "closed: no look")
end

tests["taxiMark module: look only - it asks the client for reads and the ring, nothing else"] = function(t)
    local _, c = start({ heading = BOARD, last = flightLast() })
    local asked = {}
    local real = { taxiNodes = c.taxiNodes, mapCorners = c.mapCorners, taxiMark = c.taxiMark }
    for name, fn in pairs(real) do
        c[name] = function(...) asked[name] = true return fn(...) end
    end
    open(c)
    close(c)
    t.eq(asked, { taxiNodes = true, mapCorners = true, taxiMark = true })
    for name in pairs(c) do
        local lower = type(name) == "string" and name:lower() or ""
        t.ok(not lower:find("taketaxi", 1, true) and not lower:find("selecttaxi", 1, true)
            and not lower:find("cvar", 1, true), "the fake client has a taking function: " .. tostring(name))
    end
end

return tests
