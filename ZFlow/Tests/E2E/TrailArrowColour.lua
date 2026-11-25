local _, ns = ...

-- R7 (lead section 570): the trail's first leg takes the arrow's own step
-- family, read from the arrow module (CLAUDE-TO-MUSE-R7-WIRING.md), so
-- the arrow's colour and the first leg's colour are the same. Today the
-- family is "waypoint" or nil (the profession step is the separate echo).
-- Lead section 617: under one-colour the arrow keeps its flat colour, so
-- the first leg must too; the one-colour tests below state that rule.
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

-- Lead section 617: under one-colour the arrow keeps its flat colour for
-- a waypoint step, so the first leg does too. The old expectation (the
-- leg stays green) asserted the bug.
tests["trail arrow colour: one colour recolours a waypoint leg to the flat colour (N43)"] = function(t)
    local h = start({ view = farView(), family = "waypoint" })
    h.k:Setting({ key = "arrow.byDistance", scope = "account", type = "bool", default = true,
        label = "Arrow colour by distance", group = "travel.arrow" })
    h.k.settings:set("arrow.byDistance", false)
    local leg = firstLeg(h)
    t.ok(leg ~= nil, "a first leg is drawn")
    if leg == nil then return end
    -- 600 yards out, standard palette, one colour: the flat colour, the
    -- palette's near green, not the waypoint green.
    t.eq(leg.r, 0x33 / 255)
    t.eq(leg.g, 0xF2 / 255)
    t.eq(leg.b, 0x4D / 255)
end

-- Lead section 617: the rule from both sides. The family comes from the
-- REAL arrow module (not a stub — Lazy's gap), and the arrow's colour is
-- read from N.ArrowView, the function the arrow draws from, with the same
-- step, distance and palette row. For a waypoint and a profession step,
-- under the standard and the colour-blind palettes, with and without
-- one-colour, the arrow's colour equals the first leg's r, g, b.
local function startReal(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setScreen(1024, 768)
    c.setZone(1, 1)
    c.setFacing(0)
    c.setPosition(1, 0.1, 0.1)
    c.setMapSize(1, 1000, 1000)
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    local current = opts.view
    k:Module({ name = "tripRoute", provides = { View = function() return current end } })
    local a = ns.Arrow.Declare(k, d)
    RL().Declare(k)
    local api = MRL().Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    -- The guide: the quest step with the family, at the same spot as the
    -- view's first stop (map 1, 0.7, 0.1), so the arrow and the trail
    -- agree on the destination. The family is read from the real arrow
    -- module, the way the game reads it.
    a.setGuide(function()
        return { quest = { label = "Go", family = opts.family, place = { cont = 1, map = 1, x = 0.7, y = 0.1 } } }
    end)
    return { c = c, k = k, api = api, a = a, set = function(v) current = v end }
end

-- The quest arrow's colour for a step of this family at this distance,
-- under this palette and one-colour choice, as N.ArrowView works it out.
local function arrowColour(family, paletteKey, byDistance, yards)
    local N = ns.Nav
    local v = N.ArrowView({
        gate = "open", screenW = 1024, screenH = 768, facingKnown = true,
        player = { cont = 1, zone = 1 },
        quest = { hasStep = true, target = { cont = 1, zone = 1 }, distance = yards, family = family },
        prof = { hasStep = false },
        palette = N.ArrowPaletteOf(paletteKey, byDistance),
    })
    return v.quest.colour[1], v.quest.colour[2], v.quest.colour[3]
end

tests["trail arrow colour: the arrow's colour equals the first leg's, for waypoint and profession, in every palette, with and without one-colour"] = function(t)
    for _, family in ipairs({ "waypoint", "profession" }) do
        for _, paletteKey in ipairs({ "standard", "colourBlind" }) do
            for _, byDistance in ipairs({ true, false }) do
                local h = startReal({ view = farView(), family = family })
                -- The palette and the one-colour rows are the arrow
                -- module's own (declared by Arrow.Declare); set them.
                h.k.settings:set("arrow.palette", paletteKey)
                h.k.settings:set("arrow.byDistance", byDistance)
                local leg = firstLeg(h)
                local tag = family .. "/" .. paletteKey .. "/byDistance=" .. tostring(byDistance)
                t.ok(leg ~= nil, tag .. ": a first leg is drawn")
                if leg ~= nil then
                    local ar, ag, ab = arrowColour(family, paletteKey, byDistance, 600)
                    t.eq(leg.r, ar, tag .. ": r")
                    t.eq(leg.g, ag, tag .. ": g")
                    t.eq(leg.b, ab, tag .. ": b")
                end
            end
        end
    end
end

return tests
