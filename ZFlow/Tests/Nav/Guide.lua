local _, ns = ...
-- Guide tests: from where the player stands, which way they face and up to
-- two steps, the state the arrow view takes. Unknown stays unknown: no turn
-- and no distance is ever made up.
local N = ns.Nav

local PI = math.pi
local function near(t, got, want, msg)
    t.ok(type(got) == "number" and math.abs(got - want) < 1e-9, msg .. " (got " .. tostring(got) .. ")")
end

-- Zone 1411 is 1000 yards wide and 500 tall; zone 1412 lies 1000 yards east.
local function link()
    return { [1411] = { x = 0, y = 0, w = 1000, h = 500 }, [1412] = { x = 1000, y = 0, w = 400, h = 400 } }
end

-- The player in the middle of zone 1411, as the fake client reports it.
local function standing(facing)
    local c = ns.make.fakeClient()
    c.setZone(1, 1411)
    c.setPosition(1411, 0.5, 0.5)
    c.setFacing(facing)
    return { position = c.position(), zone = c.zone(), facing = c.facing(), link = link() }
end

local function step(zone, x, y, label, radius)
    return { place = { cont = 1, zone = zone, x = x, y = y }, label = label, radius = radius }
end

local T = {}

T["place: a map position becomes yards through the zone's size"] = function(t)
    local p = N.GuidePlace({ map = 1411, x = 0.5, y = 0.5 }, { cont = 1, zone = 1411 }, link())
    t.eq(p, { cont = 1, zone = 1411, x = 500, y = 250 })
end

T["place: no position, no size for the map, or a bad number: unknown"] = function(t)
    local p, why = N.GuidePlace(nil, { cont = 1, zone = 1411 }, link())
    t.eq(p, nil)
    t.eq(why, "place")
    p, why = N.GuidePlace({ map = 99, x = 0.5, y = 0.5 }, { cont = 1, zone = 99 }, link())
    t.eq(p, nil)
    t.eq(why, "size")
    p, why = N.GuidePlace({ map = 1411, x = 0.5, y = 0.5 }, nil, nil)
    t.eq(p, nil)
    t.eq(why, "size")
    p, why = N.GuidePlace({ map = 1411, x = 0 / 0, y = 0.5 }, nil, link())
    t.eq(p, nil)
    t.eq(why, "place")
    p, why = N.GuidePlace({ map = 1411, x = 0.5, y = 0.5 }, nil, { [1411] = { x = 0, y = 0, w = 0, h = 500 } })
    t.eq(p, nil)
    t.eq(why, "size")
end

T["a quest step due north, facing north: distance and no turn"] = function(t)
    local i = standing(0)
    i.quest = step(1411, 500, 150, "Kill ten boars")
    local s = N.Guide(i)
    t.eq(s.player, { cont = 1, zone = 1411 })
    t.eq(s.facingKnown, true)
    t.eq(s.quest.hasStep, true)
    t.eq(s.quest.label, "Kill ten boars")
    t.eq(s.quest.target, { cont = 1, zone = 1411 })
    near(t, s.quest.distance, 100, "distance")
    near(t, s.quest.turn, 0, "turn")
    t.eq(s.quest.why, nil)
end

T["the turn follows the facing (Flow's rule)"] = function(t)
    local i = standing(PI / 2)   -- facing west
    i.quest = step(1411, 500, 150)
    near(t, N.Guide(i).quest.turn, -PI / 2, "north while facing west: a quarter turn right")
    i = standing(0)
    i.quest = step(1411, 600, 250)   -- due east
    near(t, N.Guide(i).quest.turn, N.ArrowTurn(PI / 2, 0), "east while facing north")
end

T["both steps: each gets its own distance and turn"] = function(t)
    local i = standing(0)
    i.quest = step(1411, 500, 150, "Quest")
    i.prof = step(1411, 800, 250, "Copper Vein")
    local s = N.Guide(i)
    near(t, s.quest.distance, 100, "quest distance")
    near(t, s.prof.distance, 300, "prof distance")
    near(t, s.prof.turn, N.ArrowTurn(PI / 2, 0), "prof turn")
    t.eq(s.prof.hasStep, true)
    t.eq(s.prof.label, "Copper Vein")
    t.eq(s.prof.bearingKnown, true)
    t.eq(s.prof.mode, "arrow")
end

T["a missing step: no arrow for it"] = function(t)
    local i = standing(0)
    i.prof = step(1411, 800, 250)
    local s = N.Guide(i)
    t.eq(s.quest, { hasStep = false })
    t.eq(s.prof.hasStep, true)
    i = standing(0)
    i.quest = step(1411, 500, 150)
    s = N.Guide(i)
    t.eq(s.prof, { hasStep = false, bearingKnown = false, mode = "off" })
    s = N.Guide(standing(0))
    t.eq(s.quest.hasStep, false)
    t.eq(s.prof.hasStep, false)
end

T["unknown place: no turn and no distance"] = function(t)
    local i = standing(0)
    i.position = nil
    i.quest = step(1411, 500, 150, "Quest")
    i.prof = step(1411, 800, 250)
    local s = N.Guide(i)
    t.eq(s.quest.hasStep, true)
    t.eq(s.quest.label, "Quest")
    t.eq(s.quest.distance, nil)
    t.eq(s.quest.turn, nil)
    t.eq(s.quest.here, nil)
    t.eq(s.quest.why, "place")
    t.eq(s.prof.distance, nil)
    t.eq(s.prof.turn, nil)
    t.eq(s.prof.bearingKnown, false)
    t.eq(s.prof.mode, "off")
    t.eq(s.player, { cont = 1, zone = 1411 }, "the zone alone is still passed on")
end

T["a zone with no known size: no turn and no distance"] = function(t)
    local i = standing(0)
    i.link = nil
    i.quest = step(1411, 500, 150)
    local s = N.Guide(i)
    t.eq(s.quest.distance, nil)
    t.eq(s.quest.turn, nil)
    t.eq(s.quest.why, "size")
end

T["a step with no usable place: no turn and no distance"] = function(t)
    local i = standing(0)
    i.quest = { label = "Somewhere" }
    i.prof = { place = { cont = 1, zone = 1411, x = "a", y = 3 } }
    local s = N.Guide(i)
    t.eq(s.quest.hasStep, true)
    t.eq(s.quest.distance, nil)
    t.eq(s.quest.turn, nil)
    t.eq(s.quest.target, nil)
    t.eq(s.quest.why, "place")
    t.eq(s.prof.distance, nil)
    t.eq(s.prof.target, { cont = 1, zone = 1411 })
end

T["unknown facing: no turn, and the profession arrow cannot point"] = function(t)
    local i = standing(nil)
    i.quest = step(1411, 500, 150)
    i.prof = step(1411, 800, 250)
    local s = N.Guide(i)
    t.eq(s.facingKnown, false)
    t.eq(s.quest.turn, nil)
    t.eq(s.prof.turn, nil)
    t.eq(s.prof.mode, "off")
    near(t, s.quest.distance, 100, "the distance does not need the facing")
end

T["zones that cannot be related: no turn and no distance"] = function(t)
    local i = standing(0)
    i.quest = step(77, 10, 10)                                   -- a zone the link does not cover
    i.prof = { place = { cont = 2, zone = 1412, x = 10, y = 10 } }   -- another continent
    local s = N.Guide(i)
    t.eq(s.quest.distance, nil)
    t.eq(s.quest.turn, nil)
    t.eq(s.quest.why, "zone")
    t.eq(s.quest.target, { cont = 1, zone = 77 })
    t.eq(s.prof.distance, nil)
    t.eq(s.prof.turn, nil)
    t.eq(s.prof.why, "continent")
    t.eq(s.prof.bearingKnown, false)
end

T["a linked neighbour zone is related through the link"] = function(t)
    local i = standing(0)
    i.quest = step(1412, 100, 250)   -- 1100 yards east in the shared frame
    local s = N.Guide(i)
    near(t, s.quest.distance, 600, "distance")
    near(t, s.quest.turn, N.ArrowTurn(PI / 2, 0), "turn")
end

T["a step given as a map position is read the same way as the player's"] = function(t)
    local i = standing(0)
    i.quest = { place = { cont = 1, map = 1411, x = 0.5, y = 0.3 } }
    local s = N.Guide(i)
    near(t, s.quest.distance, 100, "distance")
    t.eq(s.quest.target, { cont = 1, zone = 1411 })
    i.quest = { place = { cont = 1, map = 99, x = 0.5, y = 0.3 } }
    s = N.Guide(i)
    t.eq(s.quest.distance, nil)
    t.eq(s.quest.why, "size")
end

T["here: inside the step's own radius, when it gives one"] = function(t)
    local i = standing(0)
    i.quest = step(1411, 500, 150, nil, 120)
    i.prof = step(1411, 800, 250, nil, 50)
    local s = N.Guide(i)
    t.eq(s.quest.here, true)
    t.eq(s.prof.here, false)
    i.quest = step(1411, 500, 150)
    t.eq(N.Guide(i).quest.here, nil, "no radius: not said")
end

T["profession arrow mode comes from N.ProfArrowMode"] = function(t)
    local i = standing(0)
    i.quest = step(1411, 500, 240)          -- 10 yards: standing on the main step's point
    i.prof = step(1411, 800, 250)
    t.eq(N.Guide(i).prof.mode, "arrow", "stacked: it stays at a quest stop, over the quest arrow")
    i.separate = true
    t.eq(N.Guide(i).prof.mode, "arrow", "separated: it keeps pointing")
    i = standing(0)
    i.prof = step(1411, 505, 250)           -- 5 yards: on its own point
    t.eq(N.Guide(i).prof.mode, "ring")
    i = standing(0)
    i.prof = step(1411, 500, 250)           -- the very spot: no bearing
    local s = N.Guide(i)
    t.eq(s.prof.bearingKnown, false)
    t.eq(s.prof.turn, nil)
    t.eq(s.prof.mode, "ring")
end

T["view settings are passed through, and the arrow view takes the state"] = function(t)
    local i = standing(0)
    i.quest = step(1411, 500, 150)
    i.prof = step(1411, 800, 250)
    i.view = { screenW = 1024, screenH = 768, gate = "on", size = 56 }
    local s = N.Guide(i)
    t.eq(s.screenW, 1024)
    t.eq(s.screenH, 768)
    t.eq(s.gate, "on")
    t.eq(s.size, 56)
    local v = N.ArrowView(s)
    t.eq(type(v.quest), "table")
    t.eq(type(v.prof), "table")
    t.eq(v.prof.mode, s.prof.mode, "the view agrees on the profession arrow's mode")
end

T["nothing handed in: an empty state, no error"] = function(t)
    local s = N.Guide(nil)
    t.eq(s.facingKnown, false)
    t.eq(s.player, nil)
    t.eq(s.quest, { hasStep = false })
    t.eq(s.prof, { hasStep = false, bearingKnown = false, mode = "off" })
end

T["the input is not changed"] = function(t)
    local i = standing(0)
    i.quest = step(1411, 500, 150, "Quest", 30)
    N.Guide(i)
    t.eq(i.quest, step(1411, 500, 150, "Quest", 30))
    t.eq(i.position, { map = 1411, x = 0.5, y = 0.5 })
    t.eq(i.link, link())
end

return T
