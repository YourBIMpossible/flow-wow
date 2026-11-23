-- Tests for Nav/Try.lua (lead section 185): `<slash> try far|crossing|flight`
-- puts a made-up target, and for a crossing or a flight a made-up learned
-- place, in memory only, and runs the real Travel and arrow on it. Chat says
-- it is a preview every time. Nothing is saved; `try off` or a reload ends
-- it. Made-up maps; fake client. Not tested in game. Look only.
local _, ns = ...

local N = ns.Nav
local Try = N.Try
local A = ns.Arrow
local tests = {}

local function near(t, got, want, msg)
    t.ok(type(got) == "number" and math.abs(got - want) < 1e-9,
        (msg or "") .. " (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
end

-- Pure ---------------------------------------------------------------------

tests["try make: far is a made-up place across the player's own map"] = function(t)
    local p = Try.Make("far", { cont = 1, map = 1411, x = 0.3, y = 0.7 })
    t.eq(p.kind, "far")
    t.eq(p.step, { label = Try.LABEL.far, place = { cont = 1, map = 1411, x = 0.9, y = 0.1 }, preview = true })
    t.eq(p.crossings, nil)
    t.eq(p.flight, nil)
    t.eq(Try.Make("far", { cont = 1, map = 1411, x = 0.6, y = 0.5 }).step.place, { cont = 1, map = 1411, x = 0.1, y = 0.1 })
end

tests["try make: a crossing aims at the other continent, with one made-up crossing beside the player"] = function(t)
    local p = Try.Make("crossing", { cont = 1, map = 1411, x = 0.5, y = 0.4 })
    t.eq(p.step.label, Try.LABEL.crossing)
    t.eq(p.step.place, { cont = 0, map = Try.CONT_MAP[0], x = 0.5, y = 0.5 })
    t.eq(Try.CONT_MAP, { [0] = 1415, [1] = 1414 })
    t.eq(#p.crossings, 1)
    local cr = p.crossings[1]
    t.eq({ cr.key, cr.how, cr.faction, cr.seen }, { "preview", "boat", nil, nil }, "anyone may take it, offered at once")
    t.eq({ cr.a.cont, cr.a.map, cr.a.y, cr.a.name }, { 1, 1411, 0.4, Try.BOARD_NAME })
    near(t, cr.a.x, 0.5 + Try.BOARD, "the boarding place a little east of the player")
    t.eq(cr.b, { cont = 0, map = 1415, x = 0.4, y = 0.4, name = Try.LAND_NAME })
    t.eq(Try.Make("crossing", { cont = 0, map = 1429, x = 0.5, y = 0.5 }).step.place.cont, 1)
    t.eq(N.CrossingUsable(cr, "Horde"), true)
    t.eq(N.CrossingUsable(cr, "Alliance"), true)
end

tests["try make: a flight is a far place and a made-up flight master beside the player"] = function(t)
    local p = Try.Make("flight", { cont = 1, map = 1411, x = 0.98, y = 0.2 })
    t.eq(p.step.label, Try.LABEL.flight)
    t.eq(p.step.place, { cont = 1, map = 1411, x = 0.1, y = 0.9 })
    t.eq({ p.flight.name, p.flight.cont, p.flight.map, p.flight.y }, { Try.FLIGHT_NAME, 1, 1411, 0.2 })
    near(t, p.flight.x, 0.98 - Try.BOARD, "kept inside the map")
    t.eq(p.flight.roles, { flight = true })
    t.eq(p.crossings, nil)
end

tests["try make: what cannot be previewed says why"] = function(t)
    t.eq({ Try.Make("boat", { cont = 1, map = 1411, x = 0.5, y = 0.5 }) }, { nil, "unknown" })
    t.eq({ Try.Make("far", nil) }, { nil, "position unknown" })
    t.eq({ Try.Make("far", { cont = 1, map = 1411, x = 0 / 0, y = 0.5 }) }, { nil, "position unknown" })
    t.eq({ Try.Make("crossing", { map = 1411, x = 0.5, y = 0.5 }) }, { nil, "continent unknown" })
    t.eq({ Try.Make("crossing", { cont = 5, map = 1411, x = 0.5, y = 0.5 }) }, { nil, "not on a continent" })
    t.eq(Try.Make("far", { map = 1411, x = 0.5, y = 0.5 }).step.place.cont, nil, "far needs no continent")
end

-- The word, over the fake client -----------------------------------------

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, {})
    c.setScreen(1024, 768)
    c.setZone(opts.cont or 1, 1411)
    c.setFacing(0)
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    c.setClass("WARRIOR")
    c.setFaction("Horde")
    if opts.pin then c.setWaypoint(opts.pin.map, opts.pin.x, opts.pin.y) end
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    if opts.flights then
        k:Module({ name = "flights", needs = {}, provides = { Way = function() return nil end }, start = function() end })
    end
    N.Crossings.Declare(k)
    N.Travel.Declare(k, d)
    local api = Try.Declare(k, d)
    local a = A.Declare(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api, a
end

local function said(c, text)
    local n = 0
    for i = 1, #c.printed do
        if c.printed[i]:find(text, 1, true) then n = n + 1 end
    end
    return n
end

local function run(c, words)
    for i = #c.printed, 1, -1 do c.printed[i] = nil end
    c.slashes[ns.id.slash]("try " .. words)
end

local function head(text) return ns.id.title .. ": " .. text end

tests["try word: every line it says is marked a preview"] = function(t)
    local _, c = start()
    for _, words in ipairs({ "far", "crossing", "flight", "off", "", "boat" }) do
        run(c, words)
        t.ok(#c.printed > 0, "something said for '" .. words .. "'")
        for _, line in ipairs(c.printed) do
            t.ok(line:find(head("Preview"), 1, true) == 1, "marked: " .. line)
        end
    end
end

tests["try word: crossing runs the real Travel on the made-up crossing"] = function(t)
    local k, c, api = start()
    run(c, "crossing")
    t.eq(c.printed[1], head(Try.LABEL.crossing .. ". " .. Try.NOTE:format(ns.id.slash)))
    t.eq(c.printed[2], head("Preview: Travel says: " .. N.CrossingLabel("boat", Try.LAND_NAME) .. "."))
    local step = api.Step()
    t.eq(step.place, { cont = 0, map = 1415, x = 0.5, y = 0.5 })
    local via, how = k.use("travel").Via(step)
    t.eq(how, "crossing", "the crossing module answered from the preview's crossing")
    t.eq(via.place.map, 1411)
    near(t, via.place.x, 0.5 + Try.BOARD, "at the made-up boarding place")
end

tests["try word: far runs the real Travel; with no shortcut it says the arrow points straight"] = function(t)
    local _, c, api = start()
    run(c, "far")
    t.eq(c.printed[1], head(Try.LABEL.far .. ". " .. Try.NOTE:format(ns.id.slash)))
    t.eq(c.printed[2], head(Try.STRAIGHT))
    t.eq(#c.printed, 2)
    t.eq(api.Step().place, { cont = 1, map = 1411, x = 0.1, y = 0.1 })
end

tests["try word: flight says when this build has no flight way"] = function(t)
    local _, c = start()
    run(c, "flight")
    t.eq(said(c, Try.NO_FLIGHTS), 1)
    local _, c2, api2 = start({ flights = true })
    run(c2, "flight")
    t.eq(said(c2, Try.NO_FLIGHTS), 0, "a flight way is there: no such line")
    t.eq(api2.Flight().name, Try.FLIGHT_NAME, "the made-up flight master, for that way to read")
end

tests["try word: off ends it, and a new kind replaces the last"] = function(t)
    local _, c, api = start()
    run(c, "crossing")
    run(c, "far")
    t.eq(api.Crossings(), nil, "far has no made-up crossing")
    t.eq(api.Step().label, Try.LABEL.far)
    run(c, "off")
    t.eq(c.printed[1], head(Try.OFF))
    t.eq(api.Step(), nil)
    t.eq(api.Crossings(), nil)
    t.eq(api.Flight(), nil)
    run(c, "")
    t.eq(c.printed[1], head(Try.USAGE:format(ns.id.slash)))
    run(c, "boat")
    t.eq(c.printed[1], head(Try.USAGE:format(ns.id.slash)))
end

tests["try word: a place that is not known previews nothing and says why"] = function(t)
    local _, c, api = start()
    c.setPosition(nil)
    run(c, "far")
    t.eq(c.printed[1], head(Try.WHY["position unknown"]))
    t.eq(api.Step(), nil)
    c.setPosition(1411, 0.5, 0.5)
    c.setZone(7, 1411)
    run(c, "crossing")
    t.eq(c.printed[1], head(Try.WHY["not on a continent"]))
end

tests["try word: nothing is saved, and the crossing list saved stays as it was"] = function(t)
    local k, c = start()
    local before = k.store:get("account", N.CROSSING_PLACES)
    run(c, "crossing")
    k.use("travel").Via(k.use("try").Step())
    c.advance(5, 10)
    t.eq(k.store:get("account", N.CROSSING_PLACES), before)
    local learned = c.saved(ns.id.accountDB).learned
    t.ok(learned == nil or next(learned) == nil, "nothing was put in the learned table")
end

tests["try word: the step handed out is a copy each time"] = function(t)
    local _, c, api = start()
    run(c, "crossing")
    local s = api.Step()
    s.place.x = 0.01
    t.eq(api.Step().place.x, 0.5)
    local list = api.Crossings()
    list[1].a.x = 0.01
    near(t, api.Crossings()[1].a.x, 0.5 + Try.BOARD)
end

tests["try word: stop clears the preview"] = function(t)
    local k, c, api = start()
    run(c, "far")
    k:SwitchOff(Try.NAME, "test")
    t.eq(api.Step(), nil)
end

-- The arrow --------------------------------------------------------------

tests["try arrow: the preview wins over the map pin, and off gives the pin back"] = function(t)
    local _, c, _, a = start({ pin = { map = 1411, x = 0.5, y = 0.3 } })
    t.eq(a.heading(), { cont = 1, map = 1411, x = 0.5, y = 0.3 })
    run(c, "far")
    c.advance(A.RELAYOUT * 2, 2)
    t.eq(a.heading(), { cont = 1, map = 1411, x = 0.1, y = 0.1 })
    run(c, "off")
    c.advance(A.RELAYOUT * 2, 2)
    t.eq(a.heading(), { cont = 1, map = 1411, x = 0.5, y = 0.3 })
end

tests["try arrow: a crossing preview points at the made-up boarding place"] = function(t)
    local _, c, _, a = start()
    run(c, "crossing")
    c.advance(A.RELAYOUT * 2, 2)
    local h = a.heading()
    t.ok(type(h) == "table", "the arrow points somewhere")
    if type(h) ~= "table" then return end
    t.eq({ h.cont, h.map, h.y }, { 1, 1411, 0.5 })
    near(t, h.x, 0.5 + Try.BOARD)
    for i = #c.printed, 1, -1 do c.printed[i] = nil end
    c.slashes[ns.id.slash]("arrow why")
    t.ok(said(c, Try.FROM) >= 1, "arrow why names the preview")
end

return tests
