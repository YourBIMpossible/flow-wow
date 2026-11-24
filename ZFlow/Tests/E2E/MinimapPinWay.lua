local _, ns = ...
-- The minimap pin (G43; UI/MinimapPin.lua) on the whole add-on loaded on a
-- fake client, through its real entry: the player sets a waypoint with the
-- slash word "way", and the pin's look runs on the add-on's timer as the
-- frames go by. The player sees the pin on the fake minimap. Unknown data:
-- a minimap that does not say how far it reaches. Look only: the pin
-- never changes the waypoint and says nothing. Offline: the fake client's
-- minimap, not the game's. Not tested in game.
local tests = {}

local MAP = 1411

-- opts.minimap: what client.minimap() answers.
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, {})
    c.setVersion("0.1.0")
    c.setScreen(1024, 768)
    c.setZone(1, MAP)
    c.setFacing(0)
    c.setPosition(MAP, 0.5, 0.5)
    c.setMapSize(MAP, 1000, 500)
    c.setMinimap(opts.minimap)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function slash(c, rest) c.slashes[ns.id.slash](rest) end

local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.01 end

local function waypoint(addon)
    local W = ns.Nav.Waypoint
    local slot = addon.store:get(W.SCOPE, W.PATH)
    local wp = type(slot) == "table" and slot.waypoint or nil
    if type(wp) ~= "table" then return nil end
    return { map = wp.map, x = wp.x, y = wp.y, label = wp.label }
end

tests["minimap pin: a waypoint set with the slash word shows a pin where it lies, at the rim when far, and none once cleared"] = function(t)
    local c, addon = boot({ minimap = { size = 140, radius = 150, rotates = false } })
    t.eq(#c.minimapPins, 0, "no pin before a waypoint is set")

    slash(c, "way 60 50")
    local set = waypoint(addon)
    local printed = #c.printed
    c.advance(0.5, 5)
    local pin = c.minimapPins[1]
    t.ok(pin ~= nil and pin.shown == true, "a pin is on the minimap")
    if not pin then return end
    t.eq(#c.minimapPins, 1, "one pin")
    -- 100 yards east of you; 70 units of minimap reach 150 yards.
    t.ok(near(pin.x, 100 * 70 / 150) and near(pin.y, 0), "east of the middle: " .. tostring(pin.x) .. ", " .. tostring(pin.y))
    t.eq(pin.edge, false, "inside the minimap")
    t.eq(#c.printed, printed, "the pin says nothing")
    t.eq(waypoint(addon), set, "and leaves the waypoint as it was")

    slash(c, "way 90 50")
    c.advance(0.5, 5)
    t.eq(#c.minimapPins, 1, "the same pin is moved, not another made")
    t.eq(pin.edge, true, "a far waypoint is at the rim")
    t.ok(near(pin.x, 70 - ns.MinimapPin.SIZE / 2) and near(pin.y, 0), "on the rim toward it: " .. tostring(pin.x))

    slash(c, "way clear")
    c.advance(0.5, 5)
    t.eq(pin.shown, false, "no waypoint: no pin")
    t.eq(waypoint(addon), nil, "only the word cleared it")
end

tests["minimap pin: unknown data: a minimap that does not say how far it reaches shows no pin"] = function(t)
    local c, addon = boot({ minimap = { size = 140, rotates = false } })
    slash(c, "way 60 50")
    c.advance(0.5, 5)
    t.eq(#c.minimapPins, 0, "no pin is made")
    local use = addon.use(ns.MinimapPin.NAME)
    local last = use and use.Last and use.Last() or nil
    t.eq(last and { last.shown, last.reason }, { false, "minimap unknown" }, "and why")
    t.ok(waypoint(addon) ~= nil, "the waypoint itself stays set")

    local c2, addon2 = boot()
    slash(c2, "way 60 50")
    c2.advance(0.5, 5)
    t.eq(#c2.minimapPins, 0, "no minimap at all: no pin")
    t.ok(waypoint(addon2) ~= nil, "and the waypoint is kept")
end

return tests
