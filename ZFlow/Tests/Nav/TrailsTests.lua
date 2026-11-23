-- Tests for Nav/Trails.lua (G38): the path the player walked into a cave,
-- learned from the player's own movement only, and the arrow following it
-- to a target reached through it. Made-up map 1411, 1000 x 500 yards;
-- fake client. Not tested in game. Look only.
local _, ns = ...

local N = ns.Nav
local A = ns.Arrow
local tests = {}

local MAP = 1411

local function near(t, got, want, msg)
    t.ok(type(got) == "number" and math.abs(got - want) < 1e-3,
        (msg or "") .. " (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
end

local function has(t)
    local T = N.Trails
    local ok = type(T) == "table" and type(T.Declare) == "function"
    t.ok(ok, "Nav/Trails.lua is loaded")
    return ok
end

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, {})
    c.setScreen(1024, 768)
    c.setZone(1, MAP)
    c.setFacing(0)
    c.setPosition(MAP, 0.5, 0.5)
    c.setMapSize(MAP, 1000, 500)
    c.setClass("WARRIOR")
    c.setFaction("Horde")
    c.setIndoors(false)
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    local api = N.Trails.Declare(k, d)
    local a = A.Declare(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    if opts.off then k.settings:set(N.Trails.SETTING, false) end
    return k, c, api, a
end

local function at(c, x, y)
    c.setPosition(MAP, x / 1000, y / 500)
    c.advance(1.1, 2)
end

-- Outside east 48 yards, then into the cave 60 yards north, then out.
local function walkIn(c)
    at(c, 500, 250)
    at(c, 512, 250)
    at(c, 524, 250)
    at(c, 536, 250)
    at(c, 548, 250)
    c.setIndoors(true)
    at(c, 548, 250)
    for y = 238, 190, -12 do at(c, 548, y) end
    c.setIndoors(false)
    at(c, 548, 190)
end

local function trailsOf(c)
    local all = c.saved(ns.id.accountDB).learned
    return type(all) == "table" and type(all.trails) == "table" and all.trails[MAP] or nil
end

tests["trails: the names, the setting row and the saved path"] = function(t)
    if not has(t) then return end
    local T = N.Trails
    t.eq({ T.NAME, T.SETTING, T.PATH, T.WORD }, { "trails", "nav.learnTrails", "learned.trails", "trails" })
    local Model = ns.Settings.Model
    t.ok(Model.New(Model.ROWS):row(T.SETTING) ~= nil, "nav.learnTrails is a row of the model")
    local k = start()
    t.eq(k.settings:get(T.SETTING), true, "on by default")
    t.eq((k:ModuleState(T.NAME)), "started")
end

tests["trails: a walk into a cave is learned, thinned and kept under its map"] = function(t)
    if not has(t) then return end
    local k, c = start()
    walkIn(c)
    local trails = trailsOf(c)
    t.ok(type(trails) == "table" and #trails == 1, "one trail on the map")
    if type(trails) ~= "table" or #trails ~= 1 then return end
    local pts = trails[1].pts
    t.ok(#pts >= 8 and #pts <= N.Trails.POINTS, "thinned points, capped: " .. tostring(#pts))
    near(t, pts[#pts].x, 0.548)
    near(t, pts[#pts].y, 0.38)
    t.eq(k.problems:count(), 0)
end

tests["trails: the arrow follows the trail to a target in the cave"] = function(t)
    if not has(t) then return end
    local _, c, _, a = start()
    walkIn(c)
    at(c, 500, 250)
    c.slashes[ns.id.slash]("way 54.8 38")
    c.advance(A.RELAYOUT * 2, 2)
    local h = a.heading()
    t.ok(type(h) == "table", "the arrow points somewhere")
    if type(h) ~= "table" then return end
    t.eq(h.map, MAP)
    near(t, h.x, 0.512, "the next trail point, not the cave")
    near(t, h.y, 0.5)
end

tests["trails: with no trail the arrow points straight at the target"] = function(t)
    if not has(t) then return end
    local _, c, _, a = start()
    c.slashes[ns.id.slash]("way 54.8 38")
    c.advance(A.RELAYOUT * 2, 2)
    local h = a.heading()
    t.ok(type(h) == "table")
    if type(h) ~= "table" then return end
    near(t, h.x, 0.548)
    near(t, h.y, 0.38)
end

tests["trails: off, nothing is learned"] = function(t)
    if not has(t) then return end
    local _, c = start({ off = true })
    walkIn(c)
    t.eq(trailsOf(c), nil)
end

tests["trails: the word lists and forgets"] = function(t)
    if not has(t) then return end
    local _, c = start()
    walkIn(c)
    c.slashes[ns.id.slash]("trails")
    local found = false
    for _, line in ipairs(c.printed) do
        if line:find("1 trail", 1, true) then found = true end
    end
    t.ok(found, "the count is said")
    c.slashes[ns.id.slash]("trails forget")
    t.eq(trailsOf(c), nil, "forgotten")
end

tests["trails pure: next point walks from the player's end toward the target"] = function(t)
    if not has(t) then return end
    local pts = { { x = 0, y = 0 }, { x = 10, y = 0 }, { x = 20, y = 0 }, { x = 20, y = 10 }, { x = 20, y = 20 } }
    t.eq(N.Trails.Next(pts, { x = 0, y = 0 }, { x = 20, y = 20 }), 2)
    t.eq(N.Trails.Next(pts, { x = 20, y = 20 }, { x = 0, y = 0 }), 4, "the other way")
    t.eq(N.Trails.Next(pts, { x = 200, y = 200 }, { x = 20, y = 20 }), nil, "far from the trail")
    t.eq(N.Trails.Next(pts, { x = 20, y = 18 }, { x = 20, y = 20 }), nil, "already there")
end

tests["trails: the client read is there and its fake answers"] = function(t)
    local c = ns.make.fakeClient()
    t.ok(type(c.indoors) == "function" and type(c.setIndoors) == "function", "fake read and setter")
    if type(c.setIndoors) ~= "function" then return end
    c.setIndoors(true)
    t.eq(c.indoors(), true)
    c.setIndoors(nil)
    t.eq(c.indoors(), nil)
    local real = ns.make.client({})
    t.ok(type(real.indoors) == "function", "the real client has the read")
    if type(real.indoors) == "function" then t.eq(real.indoors(), nil, "no game: not known") end
end

return tests
