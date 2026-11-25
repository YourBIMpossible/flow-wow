-- The arrow's Family() (R7, lead section 570; CLAUDE-TO-MUSE-R7-WIRING.md):
-- the family of the step the quest arrow points at now, for the map
-- lines (Nav/ViewState.lua:89-92 rule: qs.family, else qs.kind, else nil).
-- Over the fake client; no game client. It only reads what the arrow
-- already chose.

local _, ns = ...

local A = ns.Arrow

-- opts: login = false (no login).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setScreen(1024, 768)
    c.setZone(1, 1411)
    c.setFacing(0)
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    local a = A.Declare(k, d)
    k:Boot()
    if opts.login ~= false then
        c.fire("ADDON_LOADED", ns.id.addon)
        c.fire("PLAYER_LOGIN")
        c.fire("PLAYER_ENTERING_WORLD")
    end
    return k, c, a
end

return {
    ["arrow family: before the start, nil"] = function(t)
        local _, _, a = start({ login = false })
        t.eq(a.family(), nil)
    end,

    ["arrow family: nothing to point at, nil"] = function(t)
        local k, _, a = start()
        t.eq(a.family(), nil)
        t.eq(k.use(A.NAME).Family(), nil)
    end,

    ["arrow family: the step's family, provided by name"] = function(t)
        local k, _, a = start()
        a.setGuide(function() return { quest = { label = "Go to the pin", family = "waypoint", place = { cont = 1, map = 1411, x = 0.5, y = 0.3 } } } end)
        t.eq(a.family(), "waypoint")
        local arrow = k.use(A.NAME)
        t.ok(type(arrow) == "table" and type(arrow.Family) == "function", "Family is provided")
        if type(arrow) ~= "table" or type(arrow.Family) ~= "function" then return end
        t.eq(arrow.Family(), "waypoint")
    end,

    ["arrow family: the step's kind counts the same"] = function(t)
        local _, _, a = start()
        a.setGuide(function() return { quest = { label = "Go to the pin", kind = "waypoint", place = { cont = 1, map = 1411, x = 0.5, y = 0.3 } } } end)
        t.eq(a.family(), "waypoint")
    end,

    ["arrow family: family wins over kind"] = function(t)
        local _, _, a = start()
        a.setGuide(function() return { quest = { label = "A step", family = "profession", kind = "waypoint", place = { cont = 1, map = 1411, x = 0.5, y = 0.3 } } } end)
        t.eq(a.family(), "profession")
    end,

    ["arrow family: a step with neither gives nil, and it clears"] = function(t)
        local _, _, a = start()
        a.setGuide(function() return { quest = { label = "Go to the pin", family = "waypoint", place = { cont = 1, map = 1411, x = 0.5, y = 0.3 } } } end)
        t.eq(a.family(), "waypoint")
        a.setGuide(function() return { quest = { label = "Kill boars", place = { cont = 1, map = 1411, x = 0.4, y = 0.6 } } } end)
        t.eq(a.family(), nil, "a step with neither family nor kind")
        a.setGuide(function() return {} end)
        t.eq(a.family(), nil, "no step at all")
    end,
}
