local _, ns = ...
-- The minimap button's place on the minimap's rim (UI/MinimapPlace.lua):
-- pure angle and offset math, no client. Made-up sizes only.
local tests = {}

local function MP() return ns.MinimapPlace or {} end

local function near(t, got, want, what)
    t.ok(type(got) == "number" and math.abs(got - want) < 0.001,
        tostring(what) .. ": " .. tostring(got) .. " is near " .. tostring(want))
end

tests["minimap place: on a round minimap the angle goes round the rim"] = function(t)
    local x, y = MP().Offset(0, 80, false)
    near(t, x, 80, "0 x"); near(t, y, 0, "0 y")
    x, y = MP().Offset(90, 80, false)
    near(t, x, 0, "90 x"); near(t, y, 80, "90 y")
    x, y = MP().Offset(180, 80)
    near(t, x, -80, "180 x"); near(t, y, 0, "180 y")
    x, y = MP().Offset(45, 80)
    near(t, x, 80 * math.sqrt(0.5), "45 x"); near(t, y, 80 * math.sqrt(0.5), "45 y")
end

tests["minimap place: on a square minimap a corner angle goes to the corner"] = function(t)
    local x, y = MP().Offset(45, 80, true)
    near(t, x, 80, "45 x"); near(t, y, 80, "45 y")
    x, y = MP().Offset(225, 80, true)
    near(t, x, -80, "225 x"); near(t, y, -80, "225 y")
    x, y = MP().Offset(90, 80, true)
    near(t, x, 0, "90 x"); near(t, y, 80, "90 y")
end

tests["minimap place: a cursor offset gives its angle"] = function(t)
    near(t, MP().Angle(10, 0), 0, "right")
    near(t, MP().Angle(0, 10), 90, "up")
    near(t, MP().Angle(-10, 0), 180, "left")
    near(t, MP().Angle(0, -10), 270, "down")
    t.eq(MP().Angle(0, 0), nil, "the middle has no angle")
    t.eq(MP().Angle("a", 1), nil)
end

tests["minimap place: an angle is kept between 0 and 360; anything else is nil"] = function(t)
    t.eq(MP().Normalize(-90), 270)
    t.eq(MP().Normalize(450), 90)
    t.eq(MP().Normalize(360), 0)
    t.eq(MP().Normalize("90"), nil)
    t.eq(MP().Normalize(0 / 0), nil)
    t.eq(MP().Normalize(nil), nil)
end

tests["minimap place: the rim radius follows the minimap size, a default without one"] = function(t)
    t.eq(MP().Radius(140), 80)
    t.eq(MP().Radius(200), 110)
    t.eq(MP().Radius(nil), 80)
    t.eq(MP().Radius(-3), 80)
    t.ok(type(MP().DEFAULT) == "number", "a default angle")
end

return tests
