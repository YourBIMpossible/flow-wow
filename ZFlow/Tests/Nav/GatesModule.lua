local _, ns = ...

-- Tests for the gates module in ZFlow/Nav/Gates.lua (S35, LEDGER 150/153):
-- the watcher that learns a gate when the player walks from one map into
-- another, now that the client gives a world position and a taxi read, and
-- the step kind "gate" it provides. Fake client; not tested in game.
-- It only watches and writes Z-Flow's own saved data: nothing moves the player.

local N = ns.Nav
local G = N.Gates
local tests = {}

-- Durotar (1411, open) into Orgrimmar (1454, walled): a gate that may be learned.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.saved or {})
    c.setZone(1, 1411)
    c.setPosition(1411, 0.50, 0.10)
    c.setMapSize(1411, 1000, 1000)
    if opts.world ~= false then c.setWorldPosition(1, 1000, 1000) end
    if opts.taxi ~= "unknown" then c.setOnTaxi(opts.taxi == true) end
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    local api = G.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api
end

local function gates(c)
    local s = c.saved(ns.id.accountDB)
    local learned = type(s) == "table" and s.learned or nil
    local places = type(learned) == "table" and learned.places or nil
    return type(places) == "table" and places.gates or nil
end

-- One watcher tick at a new moment.
local function tick(c, api)
    c.advance(G.EVERY, 1)
    return api.sample()
end

local function walkIn(c, api, wx, wy)
    tick(c, api)                                   -- a first sample outside
    c.setPosition(1454, 0.45, 0.60)
    c.setWorldPosition(1, wx or 1030, wy or 1000)  -- 30 yards on: a walk
    return tick(c, api)
end

tests["gates module: started, and it provides the step and the count"] = function(t)
    local k, _, api = start()
    t.eq((k:ModuleState(G.NAME)), "started")
    local provided = k.use(G.NAME)
    t.ok(type(provided.Step) == "function" and type(provided.Count) == "function")
    t.eq(api.count(), 0)
    t.eq(G.KIND, "gate")
end

tests["gates module: walking from one map into another learns the gate"] = function(t)
    local _, c, api = start()
    local report = walkIn(c, api)
    t.eq(report.added, true)
    local list = gates(c)
    t.eq(#list, 1)
    t.eq(list[1], { a = 1411, b = 1454, ax = 0.50, ay = 0.10, bx = 0.45, by = 0.60, cont = 1, wx = 1030, wy = 1000 })
    t.eq(api.count(), 1)
    c.setPosition(1411, 0.50, 0.10)
    c.setWorldPosition(1, 1000, 1000)
    t.eq(tick(c, api).reason, "not learnable", "out of a walled place on foot is not a gate to learn")
    c.setPosition(1454, 0.45, 0.60)
    c.setWorldPosition(1, 1030, 1000)
    t.eq(tick(c, api).reason, "known", "the same crossing again is not written twice")
    t.eq(#gates(c), 1)
end

tests["gates module: a jump too far to be a walk is a teleport, not a gate"] = function(t)
    local _, c, api = start()
    local report = walkIn(c, api, 9000, 9000)
    t.eq(report.added, false)
    t.eq(report.reason, "teleport")
    t.eq(gates(c), nil, "nothing written, and no empty table made")
end

tests["gates module: on a taxi, or with the taxi read unknown, nothing is learned"] = function(t)
    local _, c, api = start({ taxi = true })
    t.eq(walkIn(c, api), nil, "carried: the watcher resets and reports nothing")
    t.eq(gates(c), nil)
    local _, c2, api2 = start({ taxi = "unknown" })
    t.eq(walkIn(c2, api2), nil, "taxi not known: the same")
    t.eq(gates(c2), nil)
end

tests["gates module: without a world position nothing is learned"] = function(t)
    local _, c, api = start({ world = false })
    tick(c, api)
    c.setPosition(1454, 0.45, 0.60)
    t.eq(tick(c, api), nil)
    t.eq(gates(c), nil)
end

tests["gates module: the step leads to the gate on your map, as kind 'gate'"] = function(t)
    local saved = { learned = { places = { gates = {
        { a = 1411, b = 1454, ax = 0.50, ay = 0.10, bx = 0.45, by = 0.60, cont = 1, wx = 1030, wy = 1000 } } } } }
    local _, _, api = start({ saved = saved })
    local step, reason = api.step({ map = 1454 })
    t.eq(reason, nil)
    t.eq(step, { kind = "gate", label = "Way to Orgrimmar", place = { cont = 1, map = 1411, x = 0.50, y = 0.10 }, radius = G.NEAR })
    t.eq(api.count(), 1)
end

tests["gates module: a walled place with no gate known gives a text step, never a made-up place"] = function(t)
    local _, _, api = start()
    local step, reason = api.step({ map = 1454 })
    t.eq(reason, "no gate known")
    t.eq(step, { kind = "gate", label = N.GATE_UNKNOWN, text = true, detail = "Orgrimmar: behind walls, gates only" })
    local none, why = api.step({ map = 1411 })
    t.eq({ none, why }, { nil, "same map" })
    t.eq((api.step(nil)), nil)
end

tests["gates module: the watcher runs by itself on its tick"] = function(t)
    local _, c = start()
    c.advance(G.EVERY * 2, 4)
    c.setPosition(1454, 0.45, 0.60)
    c.setWorldPosition(1, 1030, 1000)
    c.advance(G.EVERY * 2, 4)
    t.eq(#(gates(c) or {}), 1, "learned with no call from the test")
end

tests["gates module: imported entries of another shape are left alone"] = function(t)
    local saved = { learned = { places = { gates = { { cont = 1, wx = 5, wy = 5 } } } } }
    local _, c, api = start({ saved = saved })
    walkIn(c, api)
    local list = gates(c)
    t.eq(#list, 2, "appended")
    t.eq(list[1], { cont = 1, wx = 5, wy = 5 }, "the imported one is untouched")
    -- walkIn leaves the player inside Orgrimmar, where there is no way to
    -- ask for ("same map"). Back outside, the step is asked from Durotar.
    t.eq({ api.step({ map = 1454 }) }, { nil, "same map" }, "inside the walls: no step")
    c.setPosition(1411, 0.50, 0.10)
    local step = api.step({ map = 1454 })
    t.ok(type(step) == "table" and type(step.place) == "table", "a step with a place")
    t.eq(step.place.map, 1411, "and the step uses the one that names its maps")
end

tests["gates: look only - nothing moves, flies or clicks for you"] = function(t)
    for name in pairs(G) do
        local n = tostring(name):lower()
        t.ok(not (n:find("take") or n:find("move") or n:find("click") or n:find("use")), "no acting function: " .. n)
    end
end

return tests
