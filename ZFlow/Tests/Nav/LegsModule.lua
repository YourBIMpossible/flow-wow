-- Tests for the module in ZFlow/Nav/Legs.lua (S34, lead section 169): the
-- look every second, the saved legs, the planner's answer and the word.
-- Fake client; the step being headed for comes from a stand-in "arrow"
-- module's Heading(), as UI/Arrow.lua provides it. Made-up places and
-- times. Not tested in game. It only times: nothing moves for the player.
local _, ns = ...

local N = ns.Nav
local L = N.Legs
local tests = {}

local MAP = 1411
local A = { cont = 1, map = MAP, x = 0.1, y = 0.5 }      -- (100, 500) in yards
local B = { cont = 1, map = MAP, x = 0.4, y = 0.5 }      -- (400, 500): 300 yd on

-- opts: saved (account data), taxi ("unknown" or a bool), mounted
-- ("unknown" or a bool), combat, heading (false: no arrow module).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.saved or {})
    c.setZone(1, MAP)
    c.setPosition(MAP, A.x, A.y)
    c.setMapSize(MAP, 1000, 1000)
    c.setClock(1000000)
    c.setCombat(opts.combat == true)
    if opts.taxi ~= "unknown" then c.setOnTaxi(opts.taxi == true) end
    if opts.mounted ~= "unknown" then c.setMounted(opts.mounted == true) end
    c.setDead(false)
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    local heading = { place = A }
    if opts.heading ~= false then
        k:Module({ name = "arrow", provides = { Heading = function()
            local p = heading.place
            return p and { cont = p.cont, map = p.map, x = p.x, y = p.y } or nil
        end } })
    end
    local api = L.Declare(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api, heading
end

local function legsOf(c)
    local s = c.saved(ns.id.accountDB)
    local learned = type(s) == "table" and s.learned or nil
    return type(learned) == "table" and learned.legs or nil
end

-- Arrive at A, then head for B and run there at 7 yards a second, one
-- look a second, `beyond` looks past the arrival.
local function runAtoB(c, heading, beyond)
    c.advance(1, 1)                           -- at A: the trip starts here
    heading.place = B
    for i = 1, 39 + (beyond or 3) do
        c.setPosition(MAP, (100 + 7 * i) / 1000, 0.5)
        c.advance(1, 1)
    end
end

local function only(c)
    local all = legsOf(c)
    local store = type(all) == "table" and all[MAP] or nil
    local row = type(store) == "table" and store[L.Cell(100, 500)] or nil
    return type(row) == "table" and row[L.Cell(400, 500)] or nil, store
end

tests["legs module: started, the names, and what it provides"] = function(t)
    local k = start()
    t.eq({ L.NAME, L.SETTING, L.PATH, L.EVERY, L.WORD }, { "legs", "nav.learnLegs", "learned.legs", 1, "legs" })
    t.eq((k:ModuleState(L.NAME)), "started")
    local provided = k.use(L.NAME)
    t.ok(type(provided.Planner) == "function" and type(provided.Count) == "function")
    t.eq(provided.Count(), 0)
    t.eq(k.problems:count(), 0)
end

tests["legs module: the setting is a row, on by default"] = function(t)
    local Model = ns.Settings.Model
    local model = Model.New(Model.ROWS)
    t.ok(model:row(L.SETTING) ~= nil, "nav.learnLegs is a row of the model")
    t.eq(model:default(L.SETTING), true)
    local k = start()
    t.ok(k.settings:row(L.SETTING) ~= nil, "and a row the panel shows")
    t.eq(k.settings:get(L.SETTING), true)
end

tests["legs module: a run from step to step is timed and kept under its map"] = function(t)
    local k, c, api, heading = start()
    t.eq(legsOf(c), nil, "nothing saved before a trip")
    runAtoB(c, heading)
    local e, store = only(c)
    t.ok(type(e) == "table", "the leg from A to B is kept")
    if type(e) ~= "table" then return end
    t.eq({ e.d, e.n, e.m }, { 300, 1, "foot" })
    t.ok(e.s >= 38 and e.s <= 41, "the seconds running: " .. tostring(e.s))
    t.eq(e.f, e.s, "a foot time too")
    t.ok(type(e.at) == "number", "kept with the wall clock")
    t.eq(L.Count(store), 1)
    t.eq(api.count(MAP), 1)
    t.eq(k.use(L.NAME).Count(), 1)
    t.eq(k.problems:count(), 0)
end

tests["legs module: the flight read not known keeps nothing"] = function(t)
    local _, c, _, heading = start({ taxi = "unknown" })
    runAtoB(c, heading)
    t.eq(legsOf(c), nil)
end

tests["legs module: the mounted read not known is kept as ridden, never on foot"] = function(t)
    local _, c, _, heading = start({ mounted = "unknown" })
    runAtoB(c, heading)
    local e = only(c)
    t.ok(type(e) == "table")
    if type(e) ~= "table" then return end
    t.eq(e.m, "mount")
    t.eq(e.f, nil, "no foot time")
end

tests["legs module: with no step to head for, nothing is arrived at"] = function(t)
    local _, c, _, heading = start({ heading = false })
    runAtoB(c, heading)
    t.eq(legsOf(c), nil)
end

tests["legs module: a fight the whole way counts no travelling"] = function(t)
    local _, c, _, heading = start({ combat = true })
    runAtoB(c, heading)
    t.eq(legsOf(c), nil)
end

tests["legs module: dying on the way drops the trip"] = function(t)
    local _, c, _, heading = start()
    c.advance(1, 1)
    heading.place = B
    for i = 1, 42 do
        c.setPosition(MAP, (100 + 7 * i) / 1000, 0.5)
        c.setDead(i == 20)
        c.advance(1, 1)
    end
    t.eq(legsOf(c), nil)
end

tests["legs module: the setting off times nothing and plans nothing"] = function(t)
    local _, c, api, heading = start({ saved = { settings = { nav = { learnLegs = false } } } })
    runAtoB(c, heading)
    t.eq(legsOf(c), nil)
    t.eq(api.planner(MAP), nil)
    t.ok(api.lines()[1]:find("learning is off", 1, true) ~= nil, api.lines()[1])
end

tests["legs module: the planner answers by the trip made, for RoutePlan"] = function(t)
    local k, c, api, heading = start()
    t.eq(api.planner(MAP), nil, "nothing known yet")
    runAtoB(c, heading)
    local legs = k.use(L.NAME).Planner(MAP)
    t.ok(type(legs) == "function")
    if type(legs) ~= "function" then return end
    local e = only(c)
    -- (Both ends in the same 40-yard squares as A and B.)
    local yards, how = legs({ x = 105, y = 505 }, { x = 405, y = 500 }, 300)
    t.eq(how, "exact")
    t.ok(math.abs(yards - e.s * L.RUN) < 1e-6, tostring(yards))
    t.eq(api.planner(9999), nil, "another map: nothing")
    local route = N.RoutePlan({ { map = MAP, x = 0.405, y = 0.5 } }, MAP, { w = 1000, h = 1000 },
        { map = MAP, x = 0.105, y = 0.5 }, legs)
    t.eq(route.stops[1].how, "exact")
    t.eq(route.straight, false)
end

tests["legs module: the word lists the trips, and forget clears them"] = function(t)
    local _, c, _, heading = start()
    runAtoB(c, heading)
    c.slashes[ns.id.slash](L.WORD)
    local said = table.concat(c.printed, "\n")
    t.ok(said:find(ns.id.title .. ": trips timed from step to step: 1", 1, true) ~= nil, said)
    t.ok(said:find("map " .. MAP .. ": 1 trip(s) (0 by flight, 0 riding)", 1, true) ~= nil, said)
    t.ok(said:find("1. 300 yd in", 1, true) ~= nil, said)
    c.slashes[ns.id.slash](L.WORD .. " forget")
    t.eq(legsOf(c), nil, "the saved legs are gone")
    t.ok(c.printed[#c.printed]:find("forgot", 1, true) ~= nil, c.printed[#c.printed])
end

tests["legs module: legs in another shape in the saved data do no harm"] = function(t)
    local saved = { learned = { legs = { [MAP] = { bad = "x", ["2:12"] = { ["10:12"] = "y" } }, other = 5 } } }
    local k, c, api, heading = start({ saved = saved })
    runAtoB(c, heading)
    t.ok(type(only(c)) == "table", "the new leg is kept beside them")
    t.ok(type(api.lines()) == "table")
    t.eq(k.problems:count(), 0)
end

return tests
