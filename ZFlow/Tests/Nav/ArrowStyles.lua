-- The arrow styles (inventory rows 4 to 11): the list and its order, the
-- one-time move of an old saved "3d", and what the 3D and flat arrows draw,
-- as lines and dots. Pure maths; no client.
local _, ns = ...

local N = ns.Nav

local function near(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-6 end

local function motion(aim)
    local m = N.ArrowMotion()
    aim = aim or {}
    aim.snap = true
    if aim.colour == nil then aim.colour = { 0.2, 0.4, 0.8 } end
    N.ArrowAim(m, aim)
    return m
end

-- The entries of list that fit every field of want.
local function pick(list, n, want)
    local out = {}
    for i = 1, n do
        local e, ok = list[i], true
        for key, v in pairs(want) do
            if type(v) == "number" then
                if not near(e[key], v) then ok = false end
            elseif e[key] ~= v then
                ok = false
            end
        end
        if ok then out[#out + 1] = e end
    end
    return out
end
local function lines(s, want) return pick(s.lines, s.nl, want) end
local function dots(s, want) return pick(s.dots, s.nd, want) end

local SIN, COS = math.sin(math.rad(52)), math.cos(math.rad(52))

return {
    -- Row 10
    ["styles: Modern, 3D (pillars), Flat lines, in that order"] = function(t)
        t.eq(N.ARROW_STYLES, { { "modern", "Modern" }, { "3d", "3D (pillars)" }, { "flat", "Flat lines" } })
    end,

    ["styles: anything but 3d and flat is modern"] = function(t)
        t.eq({ N.ArrowStyle("3d"), N.ArrowStyle("flat"), N.ArrowStyle("modern") }, { "3d", "flat", "modern" })
        t.eq({ N.ArrowStyle(nil), N.ArrowStyle("3D"), N.ArrowStyle(3), N.ArrowStyle({}) },
            { "modern", "modern", "modern", "modern" })
        t.eq({ N.ArrowStyleLabel("3d"), N.ArrowStyleLabel("flat"), N.ArrowStyleLabel("x") },
            { "3D (pillars)", "Flat lines", "Modern" })
    end,

    -- Row 11
    ["migration: a saved 3d from before the modern arrow becomes modern, once"] = function(t)
        t.eq({ N.ArrowStyleMigrate("3d", nil) }, { "modern", true }, "moved, and to be marked")
        t.eq({ N.ArrowStyleMigrate("3d", true) }, { "3d", false }, "chosen after the mark: kept")
        t.eq({ N.ArrowStyleMigrate("flat", nil) }, { "flat", true }, "flat is kept; the mark is still set")
        t.eq({ N.ArrowStyleMigrate(nil, false) }, { "modern", true })
        t.eq({ N.ArrowStyleMigrate("flat", true) }, { "flat", false })
    end,

    ["modern: no shapes"] = function(t)
        t.eq(N.ArrowShapes("modern", motion(), 0.01, 1), nil)
        t.eq(N.ArrowShapes(nil, motion(), 0.01, 1), nil)
        t.ok(type(N.ArrowShapes("flat", motion(), 0.01, 1)) == "table", "flat has shapes")
    end,

    -- Row 8
    ["flat: a glowing outline chevron, a white spine, 16 ring dots and a lead dot"] = function(t)
        local s = N.ArrowShapes("flat", motion({ turn = 0 }), 0.01, 3)
        t.eq(s.nl, 9, "4 glow lines, 4 core lines, the spine")
        t.eq(#lines(s, { thick = 7, r = 0.2, g = 0.4, b = 0.8, a = 0.25 }), 4, "glow")
        t.eq(#lines(s, { thick = 2.5, r = 0.2, g = 0.4, b = 0.8, a = 1 }), 4, "core")
        t.eq(#lines(s, { thick = 2.5, x1 = 0, y1 = 22, x2 = -15, y2 = -14 }), 1, "tip to the left barb")
        t.eq(#lines(s, { thick = 2.5, x1 = 15, y1 = -14, x2 = 0, y2 = 22 }), 1, "right barb back to the tip")
        t.eq(#lines(s, { thick = 1, r = 1, g = 1, b = 1, a = 0.85, x1 = 0, y1 = 22, x2 = 0, y2 = -5 }), 1, "spine")
        t.eq(s.nd, 17)
        t.eq(#dots(s, { w = 2, h = 2, r = 1, g = 1, b = 1, a = 0.22 }), 16, "ring")
        t.eq(#dots(s, { w = 2, x = 0, y = 27 }), 1, "the first ring dot is straight ahead")
        t.eq(#dots(s, { w = 5, h = 5, round = true, r = 0.2, g = 0.4, b = 0.8, a = 1, x = 0, y = 27 }), 1, "lead dot")
    end,

    -- Q-0: the turn is N.ArrowTurn, anticlockwise from up. Every style is
    -- drawn from the turn N.ArrowTurn gives, never from a hand-made one.
    ["every style: a target due east is drawn pointing right, due west left"] = function(t)
        local east, west = N.ArrowTurn(math.pi / 2, 0), N.ArrowTurn(3 * math.pi / 2, 0)
        t.ok(near(east, -math.pi / 2) and near(west, math.pi / 2), "anticlockwise from up")
        -- Flat: the spine runs from the tip to the notch.
        local s = N.ArrowShapes("flat", motion({ turn = east }), 0.01, 3)
        local spine = lines(s, { thick = 1 })
        t.eq(#spine, 1)
        t.ok(spine[1].x1 > 21 and near(spine[1].y1, 0), "flat: the tip is on the right")
        t.ok(spine[1].x2 < 0, "flat: the notch is behind it")
        t.eq(#dots(s, { w = 5, x = 27, y = 0 }), 1, "flat: the lead dot is on the right")
        s = N.ArrowShapes("flat", motion({ turn = west }), 0.01, 3)
        t.ok(lines(s, { thick = 1 })[1].x1 < -21, "flat: west is on the left")
        t.eq(#dots(s, { w = 5, x = -27, y = 0 }), 1)
        -- 3D: the ridge runs from the tip to the notch.
        s = N.ArrowShapes("3d", motion({ turn = east }), 0.01, 0)
        local ridge = lines(s, { thick = 1.2 })
        t.eq(#ridge, 1)
        t.ok(ridge[1].x1 > 20, "3d: the tip is on the right")
        t.ok(ridge[1].x2 < 0, "3d: the notch is behind it")
        s = N.ArrowShapes("3d", motion({ turn = west }), 0.01, 0)
        t.ok(lines(s, { thick = 1.2 })[1].x1 < -20, "3d: west is on the left")
        -- Modern: the cell of the sheet is the one it always was.
        t.eq((N.ArrowCell(east)), 96, "modern: unchanged")
        t.eq((N.ArrowCell(west)), 32, "modern: unchanged")
        t.eq(N.ArrowShapes("modern", motion({ turn = east }), 0.01, 0), nil)
    end,

    ["every style: north is up and south is down, as before"] = function(t)
        local north, south = N.ArrowTurn(0, 0), N.ArrowTurn(math.pi, 0)
        local s = N.ArrowShapes("flat", motion({ turn = north }), 0.01, 3)
        t.eq(#lines(s, { thick = 1, x1 = 0, y1 = 22, x2 = 0, y2 = -5 }), 1)
        s = N.ArrowShapes("flat", motion({ turn = south }), 0.01, 3)
        t.eq(#lines(s, { thick = 1, x1 = 0, y1 = -22, x2 = 0, y2 = 5 }), 1)
        s = N.ArrowShapes("3d", motion({ turn = south }), 0.01, 0)
        local ridge = lines(s, { thick = 1.2 })[1]
        t.ok(near(ridge.x1, 0) and ridge.y1 < ridge.y2, "3d: the tip is nearer the player than the notch")
    end,

    ["flat: a target due east points right, snaps, and does not bob"] = function(t)
        local m = motion({ turn = 0 })
        N.ArrowAim(m, { turn = N.ArrowTurn(math.pi / 2, 0), colour = { 1, 0, 0 } })
        local s = N.ArrowShapes("flat", m, 0.001, 3)
        t.eq(#lines(s, { thick = 1, x1 = 22, y1 = 0, x2 = -5, y2 = 0 }), 1, "the spine points right at once")
        t.eq(#dots(s, { w = 5, x = 27, y = 0, r = 1, g = 0, b = 0 }), 1, "the lead dot is on the right, in the new colour")
        t.eq(#lines(s, { thick = 2.5, r = 1, g = 0, b = 0 }), 4, "no colour blend")
        local again = N.ArrowShapes("flat", m, 0.001, 3.7)
        t.eq(#lines(again, { thick = 1, x1 = 22, y1 = 0 }), 1, "the same place at another time")
    end,

    -- Row 9
    ["flat, arrived: the chevron is gone, the ring grows and pulses, a dot in the middle"] = function(t)
        local now = 2
        local pulse = 0.6 + 0.4 * math.sin(now * 4)
        local s = N.ArrowShapes("flat", motion({ arrived = true, wave = true }), 0.01, now)
        t.eq(s.nl, 0)
        t.eq(s.nd, 17)
        t.eq(#dots(s, { w = 4, h = 4, r = 0.2, g = 0.4, b = 0.8, a = pulse }), 16)
        t.eq(#dots(s, { w = 10, h = 10, round = true, x = 0, y = 0, r = 0.2, g = 0.4, b = 0.8, a = 0.5 + 0.5 * pulse }), 1)
    end,

    ["flat, arrived at a step with an icon: the icon in the middle"] = function(t)
        local s = N.ArrowShapes("flat", motion({ arrived = true, icon = "Interface\\Icons\\x" }), 0.01, 2)
        t.eq(#dots(s, { w = 18, h = 18, x = 0, y = 0, tex = "Interface\\Icons\\x", r = 1, g = 1, b = 1, a = 1 }), 1)
        t.eq(#dots(s, { w = 10 }), 0)
    end,

    -- Row 4
    ["3d: a ground point is tilted 52 degrees with depth 150"] = function(t)
        local x, y, k = N.Project3D(0, 0, 0)
        t.ok(near(x, 0) and near(y, 0) and near(k, 1))
        x, y, k = N.Project3D(0, 26, 0)
        local want = 150 / (150 + 26 * SIN)
        t.ok(near(k, want), "the far end is smaller")
        t.ok(near(x, 0) and near(y, 26 * COS * want))
        x, y = N.Project3D(10, 0, 0)
        t.ok(near(x, 10) and near(y, 0))
    end,

    ["3d: the top of the slab is the colour itself, the sides darker"] = function(t)
        t.ok(near(N.ArrowSliceShade(0), 0.55))
        t.ok(near(N.ArrowSliceShade(2), 0.7))
        t.ok(near(N.ArrowSliceShade(3), 0.775))
        t.eq(N.ArrowSliceShade(4), 1)
    end,

    ["3d: shadow, five slices, a ridge and a ring of 16 short pillars"] = function(t)
        local s = N.ArrowShapes("3d", motion({ turn = 0 }), 0.01, 0)
        t.eq(s.nl, 8 + 16 + 28 + 1 + 16, "2 shadow outlines, 4 side slices, 7 fills of the top, the ridge, 16 stems")
        t.eq(#lines(s, { thick = 7, r = 0, g = 0, b = 0, a = 0.22 }), 8, "shadow")
        t.eq(#lines(s, { thick = 2.6, r = 0.2, g = 0.4, b = 0.8, a = 1 }), 28, "the top, in the colour exactly")
        t.eq(#lines(s, { thick = 2.5, r = 0.2 * 0.55, g = 0.4 * 0.55, b = 0.8 * 0.55 }), 4, "the lowest slice")
        t.eq(#lines(s, { thick = 2.5 }), 16)
        local _, tipY = N.Project3D(0, 26, 0)
        local _, notchY = N.Project3D(0, -6, 0)
        local top = 4 + 4 * 1.4
        t.eq(#lines(s, { thick = 1.2, r = 1, g = 1, b = 1, a = 0.3, x1 = 0, y1 = tipY + top, x2 = 0, y2 = notchY + top }), 1, "ridge")
        t.eq(#lines(s, { thick = 7, x1 = 3, y1 = tipY - 5 }), 1, "the shadow is offset 3 right and 5 down")
        t.eq(#lines(s, { thick = 2, r = 1, g = 1, b = 1, a = 0.22 }), 16, "stems")
        local x, y, k = N.Project3D(0, 27, 0)
        t.eq(#lines(s, { thick = 2, x1 = x, y1 = y, x2 = x, y2 = y + 3.5 * k, layer = "BACKGROUND" }), 1, "the far pillar, behind")
        x, y, k = N.Project3D(0, -27, 0)
        t.eq(#lines(s, { thick = 2, x1 = x, y1 = y, y2 = y + 3.5 * k, layer = "ARTWORK", sub = 7 }), 1, "the near pillar, in front")
        t.eq(s.nd, 16)
        t.eq(#dots(s, { w = 3, h = 2, r = 1, g = 1, b = 1, a = 0.35 }), 16, "caps")
    end,

    ["3d: it bobs in quarter pixels"] = function(t)
        local now = 0.3
        local bob = math.floor(1.5 * math.sin(now * 2.4) * 4 + 0.5) / 4
        t.ok(bob ~= 0, "a time with some bob")
        local s = N.ArrowShapes("3d", motion({ turn = 0 }), 0.01, now)
        local _, tipY = N.Project3D(0, 26, 0)
        t.eq(#lines(s, { thick = 1.2, y1 = tipY + 4 + bob + 4 * 1.4 }), 1)
        t.eq(#lines(s, { thick = 7, y1 = tipY - 5 }), 1, "the shadow stays on the ground")
    end,

    ["3d: it snaps to a new turn, and skips one under 0.003"] = function(t)
        local m = motion({ turn = 1 })
        local x, y = N.Project3D(0, 26, 1)
        local top = 4 + 4 * 1.4
        local s = N.ArrowShapes("3d", m, 0.01, 0)
        t.eq(#lines(s, { thick = 1.2, x1 = x, y1 = y + top }), 1)
        N.ArrowAim(m, { turn = 1.002, colour = { 1, 0, 0 } })
        s = N.ArrowShapes("3d", m, 0.01, 0)
        t.eq(#lines(s, { thick = 1.2, x1 = x, y1 = y + top }), 1, "a change under 0.003 is skipped")
        t.eq(#lines(s, { thick = 2.6, r = 1, g = 0, b = 0 }), 28, "the colour is not blended")
        N.ArrowAim(m, { turn = 2 })
        s = N.ArrowShapes("3d", m, 0.01, 0)
        x, y = N.Project3D(0, 26, 2)
        t.eq(#lines(s, { thick = 1.2, x1 = x, y1 = y + top }), 1, "a larger one is taken at once")
    end,

    -- Row 5
    ["3d, arrived: no chevron; taller pulsing pillars in the colour, and a ball"] = function(t)
        local now = 10
        local m = motion({ turn = 0 })
        N.ArrowShapes("3d", m, 0.01, now - 2)
        N.ArrowAim(m, { arrived = true })
        N.ArrowShapes("3d", m, 0.01, now - 1)
        local s = N.ArrowShapes("3d", m, 0.01, now)
        local pulse = 0.5 + 0.5 * math.sin(now * 4)
        t.eq(s.nl, 16, "stems only")
        local x, y, k = N.Project3D(0, 27, 0)
        local depth = 0.55 + 0.45 * math.min(1, math.max(0, (k - 0.85) * 3))
        t.eq(#lines(s, { x1 = x, y1 = y, y2 = y + 5 * k, r = 0.2 * depth, g = 0.4 * depth, b = 0.8 * depth,
                         a = 0.55 + 0.4 * pulse }), 1, "height 5, darker at the back")
        t.eq(#dots(s, { w = 4, h = 3, r = 0.65, g = 0.85, b = 1, a = 0.7 + 0.3 * pulse }), 16, "caps brighter by 0.45")
        local lift = 7 + 1.5 * math.sin(now * 2.4)
        t.eq(s.nd, 20)
        t.eq(#dots(s, { w = 13, h = 4, x = 0, y = -1, r = 0, g = 0, b = 0, a = 0.45 }), 1, "ball shadow")
        t.eq(#dots(s, { w = 12, h = 12, x = 0, y = lift, r = 0.2 * 0.35, g = 0.4 * 0.35, b = 0.8 * 0.35, a = 1 }), 1, "base")
        t.eq(#dots(s, { w = 9, h = 9, x = -0.8, y = lift + 0.8, r = 0.28, g = 0.46, b = 0.82 }), 1, "body")
        t.eq(#dots(s, { w = 3, h = 3, x = -2.4, y = lift + 2.6, r = 1, g = 1, b = 1, a = 0.85 }), 1, "highlight")
    end,

    ["3d, arriving: the pillars pop up over half a second, and settle back when leaving"] = function(t)
        local m = motion({ turn = 0 })
        N.ArrowShapes("3d", m, 0.01, 100)
        N.ArrowAim(m, { arrived = true })
        N.ArrowShapes("3d", m, 0.01, 100)
        local s = N.ArrowShapes("3d", m, 0.01, 100.125)
        local x, y, k = N.Project3D(0, 27, 0)
        local u = 0.25
        local h = 5 + 11 * math.sin(math.pi * u) * (1 - u)
        t.eq(#lines(s, { x1 = x, y1 = y, y2 = y + h * k }), 1, "a quarter of the way through the pop")
        s = N.ArrowShapes("3d", m, 0.01, 100.5)
        t.eq(#lines(s, { x1 = x, y1 = y, y2 = y + 5 * k }), 1, "settled at 5")
        N.ArrowAim(m, { arrived = false })
        N.ArrowShapes("3d", m, 0.01, 101)
        s = N.ArrowShapes("3d", m, 0.01, 102)
        t.eq(#lines(s, { thick = 2, x1 = x, y1 = y, y2 = y + 3.5 * k }), 1, "back to 3.5")
    end,

    -- Row 6
    ["3d, on the exact spot: a wave of two crests runs round the ring"] = function(t)
        local now = 50
        local m = motion({ arrived = true, wave = true })
        N.ArrowShapes("3d", m, 0.01, now - 1)
        local s = N.ArrowShapes("3d", m, 0.01, now)
        for _, i in ipairs({ 1, 5, 12 }) do
            local at = (i - 1) / 16 * 2 * math.pi
            local x, y, k = N.Project3D(27 * math.sin(at), 27 * math.cos(at), 0)
            local wave = 5 * (0.5 + 0.5 * math.sin(now * 5 - (i - 1) / 16 * 2 * 2 * math.pi))
            t.eq(#lines(s, { x1 = x, y1 = y, y2 = y + (5 + wave) * k }), 1, "pillar " .. i)
        end
        local still = motion({ arrived = true })
        N.ArrowShapes("3d", still, 0.01, now - 1)
        s = N.ArrowShapes("3d", still, 0.01, now)
        local x, y, k = N.Project3D(0, 27, 0)
        t.eq(#lines(s, { x1 = x, y1 = y, y2 = y + 5 * k }), 1, "no wave away from the spot")
    end,

    -- Row 7
    ["3d, arrived at a step with an icon: the icon hops over its shadow in place of the ball"] = function(t)
        local now = 20
        local m = motion({ arrived = true, icon = 134400 })
        N.ArrowShapes("3d", m, 0.01, now - 1)
        local s = N.ArrowShapes("3d", m, 0.01, now)
        local hop = math.abs(math.sin(now * 3.2)) * 5
        t.eq(#dots(s, { w = 18, h = 18, x = 0, y = 9 + hop, tex = 134400, r = 1, g = 1, b = 1, a = 1 }), 1, "icon")
        t.eq(#dots(s, { w = 22, h = 22, x = 0, y = 9 + hop, r = 0.2 * 0.35 }), 1, "the dark disc, grown to 22")
        t.eq(#dots(s, { w = 15 - hop, h = math.max(2, 4 - hop * 0.3), x = 0, y = -1, a = 0.45 }), 1, "shadow")
        t.eq(#dots(s, { w = 9 }), 0, "no ball")
        t.eq(#dots(s, { w = 3, h = 3 }), 0)
        t.eq(s.nd, 16 + 3)
    end,

    ["shapes: the motion is left where the modern arrow can take over"] = function(t)
        local m = motion({ turn = 0 })
        N.ArrowAim(m, { turn = 2, colour = { 1, 0, 0 }, arrived = true })
        N.ArrowShapes("flat", m, 0.01, 1)
        t.eq({ m.at, m.fade }, { 2, 1 })
        t.eq(m.shown, { 1, 0, 0 })
    end,

    ["shapes: a time that is no number draws as time 0, with no error"] = function(t)
        local s = N.ArrowShapes("3d", motion({ turn = 0 }), nil, nil)
        t.eq(s.nl, 69)
        s = N.ArrowShapes("flat", motion({ arrived = true }), 0 / 0, 0 / 0)
        t.eq(#dots(s, { w = 4, a = 0.6 }), 16)
    end,
}
