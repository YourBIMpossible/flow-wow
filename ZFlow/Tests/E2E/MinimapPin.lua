local _, ns = ...

-- The minimap pin (G43), on the whole add-on loaded on a fake client. The
-- real entry: the player's own waypoint set with the slash word "way";
-- every MinimapPin.EVERY seconds the module reads the minimap, where the
-- player is and which way they face, and places one pin, or hides it.
-- Player-visible: the pin's place on the minimap, at its edge when the
-- waypoint is off it. Map 1411 is 1000 x 1000 yards; the player stands at
-- (0.5, 0.5). Made-up places. Not tested in game.

local tests = {}
local Pin = ns.MinimapPin

local MAP = 1411
local EPS = 1e-6

-- mini: the minimap as the client says it (nil: not known).
local function boot(mini)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, {})
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 1)
    c.setClass("WARRIOR"); c.setFaction("Horde"); c.setLevel(20)
    c.setMinimap(mini)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function slash(c, text)
    c.slashes[ns.id.slash](text)
    c.advance(1, 10)
end

-- This module's pin: the one made with its name.
local function pin(c)
    local name = tostring(ns.id.addon) .. "MinimapPin"
    for _, h in ipairs(c.minimapPins or {}) do
        if type(h.spec) == "table" and h.spec.name == name then return h end
    end
    return nil
end

local function near(a, b) return type(a) == "number" and math.abs(a - b) < EPS end

local ROUND = { size = 140, radius = 100, rotates = false }

tests["minimap pin: a near waypoint is pinned where it is, north up"] = function(t)
    local c, addon = boot(ROUND)
    t.eq(pin(c), nil, "no pin before a waypoint")
    t.eq(addon.use(Pin.NAME).Last().reason, "no waypoint")
    -- 20 yards east, 30 yards north: scale 70 / 100.
    slash(c, "way 52 47")
    local h = pin(c)
    t.ok(h ~= nil, "a pin is made")
    t.eq(h and h.shown, true, "shown")
    t.ok(near(h and h.x, 14), "x to the right: " .. tostring(h and h.x))
    t.ok(near(h and h.y, 21), "y up: " .. tostring(h and h.y))
    t.eq(h and h.edge, false, "on the minimap")
    local last = addon.use(Pin.NAME).Last()
    t.ok(last and near(last.distance, math.sqrt(20 * 20 + 30 * 30)), "the distance in yards")
end

tests["minimap pin: a far waypoint sits at the edge, in its direction"] = function(t)
    local c = boot(ROUND)
    slash(c, "way 50 20")           -- 300 yards north
    local h = pin(c)
    t.eq(h and h.edge, true, "at the edge")
    t.ok(near(h and h.x, 0), "straight up: x")
    t.ok(near(h and h.y, 70 - Pin.SIZE / 2), "held inside the rim: " .. tostring(h and h.y))
end

tests["minimap pin: a turning minimap turns the pin with the player"] = function(t)
    local c = boot({ size = 140, radius = 100, rotates = true })
    c.setFacing(math.pi / 2)        -- facing west
    slash(c, "way 52 47")
    local h = pin(c)
    t.ok(near(h and h.x, 21), "north is to the right: " .. tostring(h and h.x))
    t.ok(near(h and h.y, -14), "east is behind: " .. tostring(h and h.y))
end

tests["minimap pin: another map or a cleared waypoint hides the pin"] = function(t)
    local c, addon = boot(ROUND)
    slash(c, "way 52 47")
    local h = pin(c)
    t.eq(h and h.shown, true)
    c.setPosition(1420, 0.5, 0.5)
    c.advance(1, 10)
    t.eq(h and h.shown, false, "hidden on another map")
    t.eq(addon.use(Pin.NAME).Last().reason, "other map")
    c.setPosition(MAP, 0.5, 0.5)
    c.advance(1, 10)
    t.eq(h and h.shown, true, "back")
    slash(c, "way clear")
    t.eq(h and h.shown, false, "hidden once cleared")
    t.eq(addon.use(Pin.NAME).Last().reason, "no waypoint")
end

tests["minimap pin: unknown data says nothing wrong"] = function(t)
    -- The zoom's yards not known: no pin, never one in a guessed spot.
    local c, addon = boot({ size = 140, rotates = false })
    slash(c, "way 52 47")
    t.eq(pin(c), nil, "no pin made")
    t.eq(addon.use(Pin.NAME).Last().reason, "minimap unknown")
    -- A turning minimap with no facing read.
    c = boot({ size = 140, radius = 100, rotates = true })
    c.setFacing(nil)
    slash(c, "way 52 47")
    t.eq(pin(c), nil, "no pin made")
    t.eq(addon.use(Pin.NAME).Last().reason, "facing unknown")
    -- Which way is up not said.
    c = boot({ size = 140, radius = 100 })
    slash(c, "way 52 47")
    t.eq(pin(c), nil, "no pin made")
    t.eq(addon.use(Pin.NAME).Last().reason, "rotation unknown")
end

return tests
