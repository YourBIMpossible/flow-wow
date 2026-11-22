-- Arrow motion: the sheet cell for a turn, the shortest-way turn, the colour
-- blend and the pointer / ring fade. Pure maths; no client.
local _, ns = ...

local N = ns.Nav

local function near(a, b) return math.abs(a - b) < 1e-6 end

return {
    ["cell: 128 turns in a 16 x 8 sheet, wrapping both ways"] = function(t)
        local i, l, r, top, b = N.ArrowCell(0)
        t.eq({ i, l, r, top, b }, { 0, 0, 1 / 16, 0, 1 / 8 })
        i, l, r, top, b = N.ArrowCell(2 * math.pi * 17 / 128)
        t.eq({ i, l, r, top, b }, { 17, 1 / 16, 2 / 16, 1 / 8, 2 / 8 })
        t.eq((N.ArrowCell(-2 * math.pi / 128)), 127, "a small turn the other way is the last cell")
        t.eq((N.ArrowCell(2 * math.pi)), 0)
        t.eq((N.ArrowCell(2 * math.pi * 127.6 / 128)), 0, "rounds to the nearest cell, wrapping")
        t.eq((N.ArrowCell(0 / 0)), 0, "not a number: the first cell")
        t.eq((N.ArrowCell(nil)), 0)
    end,

    ["beam: mirrored below the ring, the last row left out"] = function(t)
        local edge = 1 - 1.5 / 128
        t.eq({ N.BeamCoords(false) }, { 0, 1, 0, edge })
        t.eq({ N.BeamCoords(true) }, { 0, 1, edge, 0 })
    end,

    ["turn: the shortest way round, eased, never past"] = function(t)
        local at = N.TurnToward(0.1, -0.1 + 2 * math.pi, 0.05)
        t.ok(at < 0.1 and at > -0.1, "goes down through zero, not the long way up")
        local a = 0
        for _ = 1, 200 do a = N.TurnToward(a, 3, 0.016) end
        t.eq(a, 3, "settles exactly on the wanted turn")
        t.eq(N.TurnToward(1, 1, 0.016), 1)
        t.eq(N.TurnToward(1, nil, 0.016), 1, "no wanted turn: stays")
        t.eq(N.TurnToward(nil, 1, 0), 0, "no turn yet: north; no time: no move")
        local step = N.TurnToward(0, 1, 0.1)
        t.ok(near(step, 1 - math.exp(-0.1 * N.TURN_RATE)), "the Flow easing rate")
    end,

    ["step: colour blends over about a second, then holds exactly"] = function(t)
        local m = N.ArrowAim(N.ArrowMotion(), { colour = { 0, 1, 0 } })
        local d = N.ArrowStep(m, 0.1, 0)
        t.ok(d.colour[2] > 0.62 and d.colour[2] < 1, "part of the way after a tenth")
        for _ = 1, 100 do d = N.ArrowStep(m, 0.05, 0) end
        t.eq(d.colour, { 0, 1, 0 })
        t.eq(m.colour, { 0, 1, 0 })
    end,

    ["step: a quarter second from pointer to ring and back"] = function(t)
        local m = N.ArrowAim(N.ArrowMotion(), { turn = 1, arrived = true })
        local d = N.ArrowStep(m, 0.1, 0)
        t.ok(near(m.fade, 0.4) and d.arrived, "ring shown as soon as it starts")
        t.ok(near(d.body, 0.6) and near(d.shadow, 0.45) and near(d.pool, 0.21))
        N.ArrowStep(m, 0.1, 0)
        d = N.ArrowStep(m, 0.1, 0)
        t.eq(m.fade, 1)
        t.eq(d.body, 0, "the pointer is gone on arrival")
        t.eq(d.bodyY, 0, "no float once faded out")
        N.ArrowAim(m, { arrived = false })
        for _ = 1, 3 do d = N.ArrowStep(m, 0.1, 0) end
        t.eq(m.fade, 0)
        t.eq(d.arrived, false)
    end,

    ["step: long frames are clipped, bad input is harmless"] = function(t)
        local a = N.ArrowStep(N.ArrowAim(N.ArrowMotion(), { turn = 2 }), 5, 0)
        local b = N.ArrowStep(N.ArrowAim(N.ArrowMotion(), { turn = 2 }), N.MOTION_STEP, 0)
        t.eq(a.turn, b.turn, "a five-second frame turns as far as a tenth")
        local m = N.ArrowMotion()
        local d = N.ArrowStep(N.ArrowAim(m, { turn = 0 / 0, colour = { 1, "x", 0 } }), -1, nil)
        t.eq(d.turn, 0)
        t.eq(d.colour, N.ARROW_START_COLOUR, "a bad colour is not taken")
        N.ArrowAim(m, "nonsense")
        t.eq(m.arrived, false)
    end,

    ["aim: snap jumps there now; wave only once arrived"] = function(t)
        local m = N.ArrowAim(N.ArrowMotion(), { turn = 2, colour = { 1, 0, 0 }, arrived = true, snap = true })
        t.eq(m.at, 2)
        t.eq(m.shown, { 1, 0, 0 })
        t.eq(m.fade, 1)
        N.ArrowAim(m, { wave = true })
        t.eq(m.wave, false, "not arrived: no wave")
        N.ArrowAim(m, { wave = true, arrived = true })
        t.eq(m.wave, true)
        local d = N.ArrowStep(m, 0, 0.25)
        t.ok(near(d.ripple[3], (1 - 0.35) * 0.9), "the wave ripple runs faster and brighter")
    end,
}
