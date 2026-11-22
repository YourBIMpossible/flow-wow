-- Tests for ZFlow/Nav/MinimapPin.lua (G43, L-F): where on the minimap a
-- place is. Pure: no client. Made-up places and sizes, test only.
-- Not tested in game.
local _, ns = ...

local N = ns.Nav
local tests = {}

local MAP = 1411

local function near(a, b)
    return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-6
end

local function at(x, y, map)
    return { map = map or MAP, x = x, y = y }
end

-- The player in the middle of a map 1000 yards each way.
local function here(facing, x, y)
    local h = { position = at(x or 0.5, y or 0.5), size = { w = 1000, h = 1000 } }
    h.facing = facing
    return h
end

-- A minimap 140 wide that shows 100 yards to each side: 0.7 to the yard.
local function mini(rotates, square, inset)
    local m = { size = 140, radius = 100, rotates = rotates }
    m.square = square
    m.inset = inset
    return m
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for key, value in pairs(v) do out[key] = copy(value) end
    return out
end

tests["minimap pin: a place to the east is to the right"] = function(t)
    local pin, why = N.MinimapPin(at(0.55, 0.5), here(0), mini(false))
    t.eq(why, nil)
    t.ok(near(pin.x, 35), "50 yards at 0.7 to the yard")
    t.ok(near(pin.y, 0))
    t.eq(pin.edge, false)
    t.ok(near(pin.distance, 50))
end

tests["minimap pin: a place to the north is up, to the south is down"] = function(t)
    local pin = N.MinimapPin(at(0.5, 0.45), here(0), mini(false))
    t.ok(near(pin.x, 0))
    t.ok(near(pin.y, 35), "less y on the map is north, and north is up")
    pin = N.MinimapPin(at(0.5, 0.55), here(0), mini(false))
    t.ok(near(pin.y, -35))
    pin = N.MinimapPin(at(0.45, 0.5), here(0), mini(false))
    t.ok(near(pin.x, -35), "west is left")
end

tests["minimap pin: the place the player stands on is the middle"] = function(t)
    local pin = N.MinimapPin(at(0.5, 0.5), here(0), mini(false))
    t.eq(pin.x, 0)
    t.eq(pin.y, 0)
    t.eq(pin.edge, false)
    t.eq(pin.distance, 0, "a real 0: it was worked out")
end

tests["minimap pin: yards, not shares: a wide map moves the pin further"] = function(t)
    local h = { position = at(0.5, 0.5), size = { w = 2000, h = 500 } }
    local pin = N.MinimapPin(at(0.51, 0.5), h, mini(false))
    t.ok(near(pin.x, 14), "0.01 of 2000 yards is 20 yards")
    pin = N.MinimapPin(at(0.5, 0.51), h, mini(false))
    t.ok(near(pin.y, -3.5), "0.01 of 500 yards is 5 yards")
end

tests["minimap pin: zoomed in, the same place is further from the middle"] = function(t)
    local m = mini(false)
    m.radius = 50
    local pin = N.MinimapPin(at(0.52, 0.5), here(0), m)
    t.ok(near(pin.x, 28), "20 yards at 1.4 to the yard")
end

tests["minimap pin: a place off the minimap sits at the edge, in its direction"] = function(t)
    local pin = N.MinimapPin(at(0.8, 0.5), here(0), mini(false))
    t.eq(pin.edge, true)
    t.ok(near(pin.x, 70), "half the minimap")
    t.ok(near(pin.y, 0))
    t.ok(near(pin.distance, 300), "the distance is the real one")
    pin = N.MinimapPin(at(0.8, 0.1), here(0), mini(false))
    t.eq(pin.edge, true)
    t.ok(near(math.sqrt(pin.x * pin.x + pin.y * pin.y), 70), "on the circle")
    t.ok(near(pin.y / pin.x, 400 / 300), "the direction is kept")
    t.ok(pin.x > 0 and pin.y > 0)
end

tests["minimap pin: the inset keeps a pin at the edge inside the minimap"] = function(t)
    local pin = N.MinimapPin(at(0.8, 0.5), here(0), mini(false, nil, 6))
    t.eq(pin.edge, true)
    t.ok(near(pin.x, 64))
    -- A place inside is not moved by the inset.
    pin = N.MinimapPin(at(0.55, 0.5), here(0), mini(false, nil, 6))
    t.eq(pin.edge, false)
    t.ok(near(pin.x, 35))
    -- Between the inset and the edge it is held at the inset.
    pin = N.MinimapPin(at(0.595, 0.5), here(0), mini(false, nil, 6))
    t.eq(pin.edge, true)
    t.ok(near(pin.x, 64))
end

tests["minimap pin: a round minimap holds the corners in, a square one does not"] = function(t)
    -- 90 yards east and 90 south: 63 each way. Outside a circle of 70,
    -- inside a square of 70.
    local pin = N.MinimapPin(at(0.59, 0.59), here(0), mini(false))
    t.eq(pin.edge, true)
    t.ok(near(math.sqrt(pin.x * pin.x + pin.y * pin.y), 70))
    pin = N.MinimapPin(at(0.59, 0.59), here(0), mini(false, true))
    t.eq(pin.edge, false)
    t.ok(near(pin.x, 63))
    t.ok(near(pin.y, -63))
end

tests["minimap pin: off a square minimap the pin is on the side of the square"] = function(t)
    local pin = N.MinimapPin(at(0.8, 0.6), here(0), mini(false, true))
    t.eq(pin.edge, true)
    t.ok(near(pin.x, 70))
    t.ok(near(pin.y, -70 / 3), "the direction is kept")
end

tests["minimap pin: square only when said to be: anything else is round"] = function(t)
    local pin = N.MinimapPin(at(0.59, 0.59), here(0), mini(false, "yes"))
    t.eq(pin.edge, true)
    pin = N.MinimapPin(at(0.59, 0.59), here(0), mini(false, false))
    t.eq(pin.edge, true)
end

tests["minimap pin: north up, the facing does not matter and may be unknown"] = function(t)
    local a = N.MinimapPin(at(0.55, 0.45), here(0), mini(false))
    local b = N.MinimapPin(at(0.55, 0.45), here(2), mini(false))
    local c, why = N.MinimapPin(at(0.55, 0.45), here(nil), mini(false))
    t.eq(why, nil)
    t.ok(near(a.x, b.x) and near(a.y, b.y))
    t.ok(near(a.x, c.x) and near(a.y, c.y))
end

tests["minimap pin: a minimap that turns: what is ahead is up"] = function(t)
    -- Facing north, it is as with north up.
    local pin = N.MinimapPin(at(0.5, 0.45), here(0), mini(true))
    t.ok(near(pin.x, 0) and near(pin.y, 35))
    -- Facing west (a quarter turn to the left): north is to the right.
    pin = N.MinimapPin(at(0.5, 0.45), here(math.pi / 2), mini(true))
    t.ok(near(pin.x, 35), "north is on the right hand")
    t.ok(near(pin.y, 0))
    -- Facing west, a place to the west is ahead: up.
    pin = N.MinimapPin(at(0.45, 0.5), here(math.pi / 2), mini(true))
    t.ok(near(pin.x, 0))
    t.ok(near(pin.y, 35))
    -- Facing south, a place to the north is behind: down.
    pin = N.MinimapPin(at(0.5, 0.45), here(math.pi), mini(true))
    t.ok(near(pin.x, 0))
    t.ok(near(pin.y, -35))
    -- Facing east (a quarter turn to the right), a place to the east is up.
    pin = N.MinimapPin(at(0.55, 0.5), here(-math.pi / 2), mini(true))
    t.ok(near(pin.x, 0))
    t.ok(near(pin.y, 35))
end

tests["minimap pin: turning does not change how far the pin is from the middle"] = function(t)
    local a = N.MinimapPin(at(0.53, 0.46), here(0), mini(true))
    local b = N.MinimapPin(at(0.53, 0.46), here(1.234), mini(true))
    t.ok(near(a.x * a.x + a.y * a.y, b.x * b.x + b.y * b.y))
    t.ok(near(a.distance, b.distance))
end

tests["minimap pin: a minimap that turns and no facing: no pin, never a guess"] = function(t)
    local pin, why = N.MinimapPin(at(0.55, 0.5), here(nil), mini(true))
    t.eq(pin, nil)
    t.eq(why, "facing unknown")
    t.eq(select(2, N.MinimapPin(at(0.55, 0.5), here(0 / 0), mini(true))), "facing unknown")
    t.eq(select(2, N.MinimapPin(at(0.55, 0.5), here("north"), mini(true))), "facing unknown")
end

tests["minimap pin: whether it turns is not known: no pin"] = function(t)
    local pin, why = N.MinimapPin(at(0.55, 0.5), here(0), mini(nil))
    t.eq(pin, nil)
    t.eq(why, "rotation unknown")
    t.eq(select(2, N.MinimapPin(at(0.55, 0.5), here(0), mini(1))), "rotation unknown")
end

tests["minimap pin: no target"] = function(t)
    local pin, why = N.MinimapPin(nil, here(0), mini(false))
    t.eq(pin, nil)
    t.eq(why, "no target")
    t.eq(select(2, N.MinimapPin("there", here(0), mini(false))), "no target")
    t.eq(select(2, N.MinimapPin({ x = 0.5, y = 0.5 }, here(0), mini(false))), "no target")
    t.eq(select(2, N.MinimapPin({ map = MAP, x = 0.5 }, here(0), mini(false))), "no target")
    t.eq(select(2, N.MinimapPin(at(1.5, 0.5), here(0), mini(false))), "no target")
    t.eq(select(2, N.MinimapPin(at(0.5, 0 / 0), here(0), mini(false))), "no target")
end

tests["minimap pin: the minimap is not known: no pin, no made-up zoom"] = function(t)
    local pin, why = N.MinimapPin(at(0.55, 0.5), here(0), nil)
    t.eq(pin, nil)
    t.eq(why, "minimap unknown")
    local m = mini(false)
    m.radius = nil
    t.eq(select(2, N.MinimapPin(at(0.55, 0.5), here(0), m)), "minimap unknown", "no radius, no pin")
    m = mini(false)
    m.radius = 0
    t.eq(select(2, N.MinimapPin(at(0.55, 0.5), here(0), m)), "minimap unknown")
    m = mini(false)
    m.size = nil
    t.eq(select(2, N.MinimapPin(at(0.55, 0.5), here(0), m)), "minimap unknown")
    m = mini(false)
    m.size = -140
    t.eq(select(2, N.MinimapPin(at(0.55, 0.5), here(0), m)), "minimap unknown")
    m = mini(false)
    m.radius = math.huge
    t.eq(select(2, N.MinimapPin(at(0.55, 0.5), here(0), m)), "minimap unknown")
    -- An inset that leaves nothing of the minimap.
    t.eq(select(2, N.MinimapPin(at(0.55, 0.5), here(0), mini(false, nil, 70))), "minimap unknown")
end

tests["minimap pin: where the player is is not known: no pin"] = function(t)
    local pin, why = N.MinimapPin(at(0.55, 0.5), nil, mini(false))
    t.eq(pin, nil)
    t.eq(why, "position unknown")
    t.eq(select(2, N.MinimapPin(at(0.55, 0.5), {}, mini(false))), "position unknown")
    local h = here(0)
    h.position = { map = MAP, x = 0.5 }
    t.eq(select(2, N.MinimapPin(at(0.55, 0.5), h, mini(false))), "position unknown")
    h.position = { x = 0.5, y = 0.5 }
    t.eq(select(2, N.MinimapPin(at(0.55, 0.5), h, mini(false))), "position unknown")
end

tests["minimap pin: the player is on another map: no pin"] = function(t)
    local h = here(0)
    h.position = at(0.5, 0.5, 9)
    local pin, why = N.MinimapPin(at(0.55, 0.5), h, mini(false))
    t.eq(pin, nil)
    t.eq(why, "other map")
end

tests["minimap pin: the size of the map is not known: no pin"] = function(t)
    local h = here(0)
    h.size = nil
    local pin, why = N.MinimapPin(at(0.55, 0.5), h, mini(false))
    t.eq(pin, nil)
    t.eq(why, "size unknown")
    h.size = { w = 1000 }
    t.eq(select(2, N.MinimapPin(at(0.55, 0.5), h, mini(false))), "size unknown")
    h.size = { w = 0, h = 1000 }
    t.eq(select(2, N.MinimapPin(at(0.55, 0.5), h, mini(false))), "size unknown")
end

tests["minimap pin: the first reason that holds is the one given"] = function(t)
    t.eq(select(2, N.MinimapPin(nil, nil, nil)), "no target")
    t.eq(select(2, N.MinimapPin(at(0.55, 0.5), nil, nil)), "minimap unknown")
    t.eq(select(2, N.MinimapPin(at(0.55, 0.5), nil, mini(nil))), "position unknown")
    local h = here(nil)
    h.size = nil
    t.eq(select(2, N.MinimapPin(at(0.55, 0.5), h, mini(nil))), "size unknown")
    t.eq(select(2, N.MinimapPin(at(0.55, 0.5), here(nil), mini(nil))), "rotation unknown")
end

tests["minimap pin: what is handed in is not changed"] = function(t)
    local target, h, m = at(0.8, 0.1), here(1), mini(true, nil, 6)
    local t0, h0, m0 = copy(target), copy(h), copy(m)
    N.MinimapPin(target, h, m)
    t.eq(target, t0)
    t.eq(h, h0)
    t.eq(m, m0)
end

return tests
