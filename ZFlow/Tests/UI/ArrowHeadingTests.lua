-- The arrow's Heading() (lead section 169 B, S34): the place of the step
-- the quest arrow points the player to, for Nav/Legs.lua. Over the fake
-- client; no game client. It only reads what the arrow already chose.
local _, ns = ...

local A = ns.Arrow

-- opts: pin = { map, x, y } (the map pin), login = false (no login).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setScreen(1024, 768)
    c.setZone(1, 1411)
    c.setFacing(0)
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    if opts.pin then c.setWaypoint(opts.pin.map, opts.pin.x, opts.pin.y) end
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
    ["arrow heading: before the start, nil"] = function(t)
        local _, _, a = start({ login = false, pin = { map = 1411, x = 0.5, y = 0.3 } })
        t.eq(a.heading(), nil)
    end,

    ["arrow heading: nothing to point at, nil"] = function(t)
        local k, _, a = start()
        t.eq(a.heading(), nil)
        t.eq(k.use(A.NAME).Heading(), nil)
    end,

    ["arrow heading: the map pin's place, provided by name"] = function(t)
        local k, _, a = start({ pin = { map = 1411, x = 0.5, y = 0.3 } })
        t.eq(a.heading(), { cont = 1, map = 1411, x = 0.5, y = 0.3 })
        local arrow = k.use(A.NAME)
        t.ok(type(arrow) == "table" and type(arrow.Heading) == "function", "Heading is provided")
        if type(arrow) ~= "table" or type(arrow.Heading) ~= "function" then return end
        t.eq(arrow.Heading(), { cont = 1, map = 1411, x = 0.5, y = 0.3 })
    end,

    ["arrow heading: a copy each time, and it follows the arrow"] = function(t)
        local _, c, a = start({ pin = { map = 1411, x = 0.5, y = 0.3 } })
        local got = a.heading()
        got.x = 0.9
        t.eq(a.heading().x, 0.5, "a copy")
        c.setWaypoint(1411, 0.2, 0.5)
        c.advance(A.RELAYOUT * 2, 2)
        t.eq(a.heading(), { cont = 1, map = 1411, x = 0.2, y = 0.5 })
        c.setWaypoint(nil)
        c.advance(A.RELAYOUT * 2, 2)
        t.eq(a.heading(), nil, "the pin taken away")
    end,

    ["arrow heading: a step with no place gives nil"] = function(t)
        local _, _, a = start()
        a.setGuide(function() return { quest = { label = "Talk to someone", still = true } } end)
        t.eq(a.heading(), nil)
        a.setGuide(function() return { quest = { label = "Kill boars", place = { cont = 1, map = 1411, x = 0.4, y = 0.6 } } } end)
        t.eq(a.heading(), { cont = 1, map = 1411, x = 0.4, y = 0.6 })
    end,
}
