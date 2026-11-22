-- Tests for ZFlow/UI/MinimapPin.lua (G43, L-F): the pin on the minimap at
-- the waypoint the player set. The two client reads it needs (minimap,
-- minimapPin) are asked for, not yet on the client: here they are put on a
-- made-up client, or on the fake one. Made-up places, test only.
-- Not tested in game.
local _, ns = ...

local P = ns.MinimapPin
local N = ns.Nav
local tests = {}

local MAP = 1411

local function near(a, b)
    return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-6
end

-- A made-up client. o: position, sizes (by map), facing, mini, noFrame.
-- What it was asked is counted in o.asked; the one pin frame is o.frame.
local function client(o)
    o.asked = { minimapPin = 0 }
    local c = {}
    function c.position() return o.position end
    function c.mapSize(map) return o.sizes and o.sizes[map] end
    function c.facing() return o.facing end
    function c.minimap() return o.mini end
    function c.minimapPin(spec)
        o.asked.minimapPin = o.asked.minimapPin + 1
        o.spec = spec
        if o.noFrame then return nil end
        local f = { shown = false, places = 0, hides = 0 }
        o.frame = f
        return {
            place = function(x, y, edge)
                f.x, f.y, f.edge, f.shown = x, y, edge, true
                f.places = f.places + 1
            end,
            hide = function()
                f.shown = false
                f.hides = f.hides + 1
            end,
        }
    end
    return c
end

-- A made-up store with only the waypoint slot in it.
local function store(o)
    return {
        get = function(_, scope, path)
            if scope == N.Waypoint.SCOPE and path == N.Waypoint.PATH then return o.slot end
            return nil
        end,
    }
end

-- The player in the middle of a 1000 yard map, a waypoint 50 yards east,
-- a minimap 140 wide showing 100 yards to each side, north up.
local function world()
    return {
        position = { map = MAP, x = 0.5, y = 0.5 },
        sizes = { [MAP] = { w = 1000, h = 1000 } },
        facing = 0,
        mini = { size = 140, radius = 100, rotates = false },
        slot = { waypoint = { map = MAP, x = 0.55, y = 0.5 } },
    }
end

tests["minimap pin: the name and the first guesses"] = function(t)
    t.eq(P.NAME, "minimapPin")
    t.ok(type(P.EVERY) == "number" and P.EVERY > 0)
    t.ok(type(P.SIZE) == "number" and P.SIZE > 0)
end

tests["minimap pin: a waypoint on the minimap is pinned where it is"] = function(t)
    local o = world()
    local state = {}
    local r = P.Update(client(o), store(o), state)
    t.eq(r.shown, true)
    t.ok(near(r.x, 35))
    t.ok(near(r.y, 0))
    t.eq(r.edge, false)
    t.ok(near(r.distance, 50))
    t.eq(o.frame.shown, true)
    t.ok(near(o.frame.x, 35))
    t.ok(near(o.frame.y, 0))
    t.eq(o.frame.edge, false)
end

tests["minimap pin: the frame is asked for once, by a name that is not spelled here"] = function(t)
    local o = world()
    local state = {}
    local c, s = client(o), store(o)
    P.Update(c, s, state)
    P.Update(c, s, state)
    P.Update(c, s, state)
    t.eq(o.asked.minimapPin, 1)
    t.eq(o.frame.places, 3, "placed at each look")
    t.eq(o.spec.size, P.SIZE)
    t.eq(o.spec.name, tostring(ns.id.addon) .. "MinimapPin")
end

tests["minimap pin: the pin follows the player"] = function(t)
    local o = world()
    local state = {}
    local c, s = client(o), store(o)
    P.Update(c, s, state)
    o.position = { map = MAP, x = 0.52, y = 0.5 }
    local r = P.Update(c, s, state)
    t.ok(near(r.x, 21), "30 yards now")
    t.ok(near(o.frame.x, 21))
end

tests["minimap pin: a waypoint off the minimap is held at the edge, inside it"] = function(t)
    local o = world()
    o.slot.waypoint.x = 0.9
    local r = P.Update(client(o), store(o), {})
    t.eq(r.shown, true)
    t.eq(r.edge, true)
    t.ok(near(r.x, 70 - P.SIZE / 2), "half the pin inside the edge")
    t.eq(o.frame.edge, true)
    t.ok(near(r.distance, 400))
end

tests["minimap pin: a minimap that turns is turned by the facing"] = function(t)
    local o = world()
    o.mini.rotates = true
    o.facing = -math.pi / 2
    local r = P.Update(client(o), store(o), {})
    t.ok(near(r.x, 0), "facing east, a place to the east is ahead")
    t.ok(near(r.y, 35))
end

tests["minimap pin: no waypoint: nothing shown and no frame made"] = function(t)
    local o = world()
    o.slot = {}
    local r = P.Update(client(o), store(o), {})
    t.eq(r, { shown = false, reason = "no waypoint" })
    t.eq(o.asked.minimapPin, 0)
    o.slot = nil
    t.eq(P.Update(client(o), store(o), {}), { shown = false, reason = "no waypoint" })
    t.eq(P.Update(client(o), nil, {}), { shown = false, reason = "no waypoint" })
    -- A damaged waypoint is no waypoint to pin.
    o.slot = { waypoint = { map = MAP, x = 1.5, y = 0.5 } }
    t.eq(P.Update(client(o), store(o), {}).shown, false)
end

tests["minimap pin: the waypoint is only read"] = function(t)
    local o = world()
    o.slot.waypoint.label = "Camp"
    P.Update(client(o), store(o), {})
    t.eq(o.slot, { waypoint = { map = MAP, x = 0.55, y = 0.5, label = "Camp" } })
end

tests["minimap pin: the waypoint cleared: the pin is hidden, once"] = function(t)
    local o = world()
    local state = {}
    local c, s = client(o), store(o)
    P.Update(c, s, state)
    o.slot.waypoint = nil
    local r = P.Update(c, s, state)
    t.eq(r, { shown = false, reason = "no waypoint" })
    t.eq(o.frame.shown, false)
    t.eq(o.frame.hides, 1)
    P.Update(c, s, state)
    t.eq(o.frame.hides, 1, "not hidden again while it is hidden")
    -- Set again: shown again, the same frame.
    o.slot.waypoint = { map = MAP, x = 0.5, y = 0.45 }
    r = P.Update(c, s, state)
    t.eq(r.shown, true)
    t.eq(o.frame.shown, true)
    t.eq(o.asked.minimapPin, 1)
end

tests["minimap pin: what is not known hides the pin and says why"] = function(t)
    local function reasonWith(change)
        local o = world()
        local state = {}
        local c, s = client(o), store(o)
        P.Update(c, s, state)
        change(o)
        local r = P.Update(c, s, state)
        return r, o
    end
    local r, o = reasonWith(function(w) w.position = nil end)
    t.eq(r, { shown = false, reason = "position unknown" })
    t.eq(o.frame.shown, false)
    r = reasonWith(function(w) w.position = { map = 9, x = 0.5, y = 0.5 } end)
    t.eq(r.reason, "other map")
    r = reasonWith(function(w) w.sizes = {} end)
    t.eq(r.reason, "size unknown")
    r = reasonWith(function(w) w.mini = nil end)
    t.eq(r.reason, "minimap unknown")
    r = reasonWith(function(w) w.mini.radius = nil end)
    t.eq(r.reason, "minimap unknown", "no zoom read: no pin, no made-up yards")
    r = reasonWith(function(w) w.mini.rotates = nil end)
    t.eq(r.reason, "rotation unknown")
    r, o = reasonWith(function(w) w.mini.rotates = true; w.facing = nil end)
    t.eq(r.reason, "facing unknown")
    t.eq(o.frame.shown, false)
end

tests["minimap pin: the size asked for is that of the map of the waypoint"] = function(t)
    local o = world()
    o.sizes = { [MAP] = { w = 2000, h = 1000 }, [9] = { w = 10, h = 10 } }
    local r = P.Update(client(o), store(o), {})
    t.ok(near(r.x, 70 - P.SIZE / 2), "100 yards east: at the edge")
    t.ok(near(r.distance, 100))
end

tests["minimap pin: a client that gives no frame: nothing shown, asked once"] = function(t)
    local o = world()
    o.noFrame = true
    local state = {}
    local c, s = client(o), store(o)
    t.eq(P.Update(c, s, state), { shown = false, reason = "no pin frame" })
    t.eq(P.Update(c, s, state), { shown = false, reason = "no pin frame" })
    t.eq(o.asked.minimapPin, 1)
end

tests["minimap pin: a client without the reads: nothing shown, no error"] = function(t)
    local o = world()
    local c = client(o)
    c.minimap = nil
    t.eq(P.Update(c, store(o), {}), { shown = false, reason = "minimap unknown" })
    c = client(o)
    c.minimapPin = nil
    t.eq(P.Update(c, store(o), {}), { shown = false, reason = "no pin frame" })
    t.eq(P.Update({}, store(o), {}).shown, false)
    t.eq(P.Update(nil, store(o), {}).shown, false)
end

-- ------------------------------------------------------------- the module
-- Over the fake client. opts.reads: put the two asked-for reads on it.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setZone(1, MAP)
    c.setFacing(0)
    c.setPosition(MAP, 0.5, 0.5)
    c.setMapSize(MAP, 1000, 1000)
    local seen = { made = 0 }
    if opts.reads then
        c.minimap = function() return seen.mini end
        c.minimapPin = function()
            seen.made = seen.made + 1
            local f = { shown = false }
            seen.frame = f
            return {
                place = function(x, y, edge) f.x, f.y, f.edge, f.shown = x, y, edge, true end,
                hide = function() f.shown = false end,
            }
        end
        seen.mini = { size = 140, radius = 100, rotates = false }
    end
    local k = ns.Kernel({}, c)
    local api = P.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api, seen
end

local function setWaypoint(k, x, y)
    N.Waypoint.Slot(k.store).waypoint = { map = MAP, x = x, y = y }
end

tests["minimap pin module: on a client without the reads it does nothing"] = function(t)
    local k, c, api = start()
    setWaypoint(k, 0.55, 0.5)
    c.advance(1, 10)
    t.eq(api.last(), nil, "no look was taken")
    t.eq(api.update(), nil)
    t.eq(k.problems:count(), 0)
end

tests["minimap pin module: before the first look there is no report"] = function(t)
    local _, _, api = start({ reads = true })
    t.eq(api.last(), nil)
end

tests["minimap pin module: a look pins the waypoint the player set"] = function(t)
    local k, _, api, seen = start({ reads = true })
    setWaypoint(k, 0.55, 0.5)
    local r = api.update()
    t.eq(r.shown, true)
    t.ok(near(r.x, 35))
    t.ok(api.last() == r)
    t.eq(seen.frame.shown, true)
    t.ok(near(seen.frame.x, 35))
    t.eq(k.problems:count(), 0)
end

tests["minimap pin module: it looks by itself, and follows the player"] = function(t)
    local k, c, api, seen = start({ reads = true })
    setWaypoint(k, 0.55, 0.5)
    c.advance(P.EVERY * 3, 3)
    t.ok(api.last() ~= nil, "a look was taken")
    t.eq(api.last().shown, true)
    c.setPosition(MAP, 0.52, 0.5)
    c.advance(P.EVERY * 3, 3)
    t.ok(near(seen.frame.x, 21))
    t.eq(seen.made, 1)
    t.eq(k.problems:count(), 0)
end

tests["minimap pin module: no waypoint: no frame is made"] = function(t)
    local k, c, api, seen = start({ reads = true })
    c.advance(P.EVERY * 3, 3)
    t.eq(api.update(), { shown = false, reason = "no waypoint" })
    t.eq(seen.made, 0)
    t.eq(k.problems:count(), 0)
end

tests["minimap pin module: nothing is saved by it"] = function(t)
    local k, c, api = start({ reads = true })
    setWaypoint(k, 0.55, 0.5)
    api.update()
    c.advance(P.EVERY * 3, 3)
    t.eq(k.store:get(N.Waypoint.SCOPE, N.Waypoint.PATH), { waypoint = { map = MAP, x = 0.55, y = 0.5 } })
end

return tests
