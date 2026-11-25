local _, ns = ...

-- R7 (lead section 570): the trail's first leg takes the arrow's own step
-- family, read from the arrow module (CLAUDE-TO-MUSE-R7-WIRING.md), so
-- the arrow's colour and the first leg's colour are the same. Today the
-- family is "waypoint" or nil (the profession step is the separate echo).
-- Over the fake client; no game client. Made-up places and maps.
-- Not tested in game.

local tests = {}

local function MRL() return ns.MapRouteLines end
local function RL() return ns.RouteList end

-- opts: view (the tripRoute View), family (what the fake arrow's Family
-- returns; nil for no family), arrow (false: no arrow module at all).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    local current = opts.view
    k:Module({ name = "tripRoute", provides = { View = function() return current end } })
    if opts.arrow ~= false then
        local family = opts.family
        k:Module({ name = "arrow", provides = { Family = function() return family end } })
    end
    RL().Declare(k)
    local api = MRL().Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return { c = c, k = k, api = api, set = function(v) current = v end }
end

-- One stop, 600 yards out on the same map: far, exactly the contract's
-- far orange when the family is the quest's own.
local function farView()
    return { kind = "quests", stops = {
        { quest = 11, label = "Far Off", detail = "Go", place = { map = 1, x = 0.7, y = 0.1 } },
    }, left = {} }
end

local function firstLeg(h)
    h.c.setWorldMap(1)
    h.c.setMapSize(1, 1000, 1000)
    h.c.setPosition(1, 0.1, 0.1)
    h.c.advance(1, 8)
    local set = h.c.routeLineSets[1]
    if set == nil then return nil end
    for _, l in ipairs(set.lines) do if l.kind == "first" then return l end end
    return nil
end

tests["trail arrow colour: a waypoint step paints the first leg green"] = function(t)
    local h = start({ view = farView(), family = "waypoint" })
    local leg = firstLeg(h)
    t.ok(leg ~= nil, "a first leg is drawn")
    if leg == nil then return end
    t.eq(leg.r, 0x1E / 255)
    t.eq(leg.g, 1)
    t.eq(leg.b, 0)
    t.eq(leg.a, MRL().FIRST_ALPHA)
end

tests["trail arrow colour: the colour-blind waypoint is blue"] = function(t)
    local h = start({ view = farView(), family = "waypoint" })
    h.k:Setting({ key = "arrow.palette", scope = "account", type = "choice",
        choices = { "standard", "colourBlind" }, default = "standard",
        label = "Arrow palette", group = "travel.arrow" })
    h.k.settings:set("arrow.palette", "colourBlind")
    local leg = firstLeg(h)
    t.ok(leg ~= nil, "a first leg is drawn")
    if leg == nil then return end
    t.eq(leg.r, 0x00 / 255)
    t.eq(leg.g, 0x72 / 255)
    t.eq(leg.b, 0xB2 / 255)
end

tests["trail arrow colour: no family paints the first leg the quest colour"] = function(t)
    local h = start({ view = farView(), family = nil })
    local leg = firstLeg(h)
    t.ok(leg ~= nil, "a first leg is drawn")
    if leg == nil then return end
    -- 600 yards out: far, exactly the contract's far orange
    t.eq(leg.r, 0xFF / 255)
    t.eq(leg.g, 0x8C / 255)
    t.eq(leg.b, 0x1A / 255)
end

tests["trail arrow colour: no arrow module paints the first leg the quest colour"] = function(t)
    local h = start({ view = farView(), arrow = false })
    local leg = firstLeg(h)
    t.ok(leg ~= nil, "a first leg is drawn")
    if leg == nil then return end
    t.eq(leg.r, 0xFF / 255)
    t.eq(leg.g, 0x8C / 255)
    t.eq(leg.b, 0x1A / 255)
end

tests["trail arrow colour: one colour does not recolour a waypoint leg (N43)"] = function(t)
    local h = start({ view = farView(), family = "waypoint" })
    h.k:Setting({ key = "arrow.byDistance", scope = "account", type = "bool", default = true,
        label = "Arrow colour by distance", group = "travel.arrow" })
    h.k.settings:set("arrow.byDistance", false)
    local leg = firstLeg(h)
    t.ok(leg ~= nil, "a first leg is drawn")
    if leg == nil then return end
    t.eq(leg.r, 0x1E / 255)
    t.eq(leg.g, 1)
    t.eq(leg.b, 0)
end

return tests
