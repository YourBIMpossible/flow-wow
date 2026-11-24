local _, ns = ...
-- ViewState tests: the arrow view's state built from a client's reads, with
-- exactly the fields the arrow view names. What the client does not say
-- stays nil or false.
local N = ns.Nav

local function near(t, got, want, msg)
    t.ok(type(got) == "number" and math.abs(got - want) < 1e-9, msg .. " (got " .. tostring(got) .. ")")
end

-- The player in the middle of map 1411 (1000 by 500 yards), facing north.
local function client()
    local c = ns.make.fakeClient()
    c.setZone(1, 1411)
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    c.setFacing(0)
    return c
end

-- A step as shares of a map, as client.position() gives them.
local function share(map, x, y, radius)
    return { place = { cont = 1, map = map, x = x, y = y }, radius = radius }
end

local function keys(tbl)
    local out = {}
    for k in pairs(tbl) do out[k] = true end
    return out
end

local T = {}

T["fractions become yards as x*w and y*h"] = function(t)
    -- Player at 500, 250. Quest at 0.5*1000, 0.3*500 = 500, 150: 100 yards.
    -- Prof at 0.8*1000, 0.5*500 = 800, 250: 300 yards.
    local s = N.ViewState(client(), { quest = share(1411, 0.5, 0.3), prof = share(1411, 0.8, 0.5) })
    near(t, s.quest.distance, 100, "quest distance")
    near(t, s.prof.distance, 300, "prof distance")
    t.eq(s.player, { cont = 1, zone = 1411 })
    t.eq(s.facingKnown, true)
    t.eq(s.prof.bearingKnown, true)
    t.eq(s.quest.hasStep, true)
    t.eq(s.quest.target, { cont = 1, zone = 1411 })
end

T["here comes from the distance and the step's radius"] = function(t)
    local s = N.ViewState(client(), { quest = share(1411, 0.5, 0.3, 150), prof = share(1411, 0.8, 0.5, 150) })
    t.eq(s.quest.here, true)
    t.eq(s.prof.here, false)
    s = N.ViewState(client(), { quest = share(1411, 0.5, 0.3) })
    t.eq(s.quest.here, false, "no radius: not here")
end

T["only the fields the arrow view names"] = function(t)
    local s = N.ViewState(client(), {
        quest = { place = { cont = 1, map = 1411, x = 0.5, y = 0.3 }, radius = 150, label = "Quest",
                  overlay = true, travel = true, textHeight = 28 },
        prof = { place = { cont = 1, map = 1411, x = 0.8, y = 0.5 }, label = "Vein",
                 on = true, own = { 1, 0.5, 0 }, textHeight = 14 },
        view = { layout = { mode = "separate" }, screenW = 1024, screenH = 768, size = 54,
                 defaultPoint = { "CENTER", "CENTER", 0, 0 }, gate = "open", palette = N.ARROW_PALETTE.standard,
                 other = "dropped" },
    })
    t.eq(keys(s), { layout = true, screenW = true, screenH = true, size = true, defaultPoint = true,
                    gate = true, palette = true, player = true, facingKnown = true, quest = true, prof = true,
                    spread = true })
    -- The quest step lies due north, the profession step due east.
    near(t, s.spread, math.pi / 2, "spread: the angle between the two bearings")
    t.eq(N.ViewState(client(), { quest = share(1411, 0.5, 0.3) }).spread, nil, "one step only: no spread")
    t.eq(keys(s.quest), { hasStep = true, overlay = true, target = true, here = true, distance = true,
                          travel = true, textHeight = true })
    t.eq(keys(s.prof), { on = true, hasStep = true, target = true, here = true, distance = true,
                         bearingKnown = true, own = true, textHeight = true })
    t.eq(s.quest.overlay, true)
    t.eq(s.quest.textHeight, 28)
    t.eq(s.prof.own, { 1, 0.5, 0 })
    t.eq(s.screenW, 1024)
end

T["the turn and the reason are given beside the state, not in it"] = function(t)
    local c = client()
    local s, more = N.ViewState(c, { quest = share(1411, 0.5, 0.3), prof = share(1412, 0.5, 0.5) })
    t.eq(s.quest.turn, nil)
    near(t, more.quest.turn, 0, "quest turn")
    t.eq(more.prof.why, "size")
    t.eq(more.prof.turn, nil)
    c.setFacing(math.pi / 2)
    s, more = N.ViewState(c, { quest = share(1411, 0.5, 0.3) })
    t.ok(s.quest.distance ~= nil, "distance")
    t.ok(type(more.quest.turn) == "number" and math.abs(more.quest.turn) > 1, "the turn follows the facing")
end

T["no map size: no distance, no bearing, not here"] = function(t)
    local c = client()
    c.setMapSize(1411, nil)
    local s, more = N.ViewState(c, { quest = share(1411, 0.5, 0.3, 150), prof = share(1411, 0.8, 0.5, 150) })
    t.eq(s.quest.distance, nil)
    t.eq(s.quest.here, false)
    t.eq(s.prof.distance, nil)
    t.eq(s.prof.bearingKnown, false)
    t.eq(s.prof.here, false)
    t.eq(s.facingKnown, true)
    t.eq(more.quest.why, "size")
end

T["no position: no distance, no bearing"] = function(t)
    local c = client()
    c.setPosition(nil)
    local s, more = N.ViewState(c, { quest = share(1411, 0.5, 0.3), prof = share(1411, 0.8, 0.5) })
    t.eq(s.quest.distance, nil)
    t.eq(s.prof.bearingKnown, false)
    t.eq(s.player, { cont = 1, zone = 1411 })
    t.eq(more.quest.why, "place")
end

T["no facing: facingKnown false, distance and bearing kept"] = function(t)
    local c = client()
    c.setFacing(nil)
    local s, more = N.ViewState(c, { quest = share(1411, 0.5, 0.3), prof = share(1411, 0.8, 0.5) })
    t.eq(s.facingKnown, false)
    near(t, s.quest.distance, 100, "distance")
    t.eq(s.prof.bearingKnown, true)
    t.eq(more.quest.turn, nil)
    t.eq(more.prof.turn, nil)
end

T["no steps: no arrows"] = function(t)
    local s, more = N.ViewState(client(), nil)
    t.eq(s.quest, { hasStep = false, here = false })
    t.eq(s.prof, { hasStep = false, here = false, bearingKnown = false })
    t.eq(more, { quest = {}, prof = {} })
end

T["no client, or one whose reads fail: nothing known, no error"] = function(t)
    local steps = { quest = share(1411, 0.5, 0.3), prof = share(1411, 0.8, 0.5) }
    local s = N.ViewState(nil, steps)
    t.eq(s.player, nil)
    t.eq(s.facingKnown, false)
    t.eq(s.quest.distance, nil)
    t.eq(s.prof.bearingKnown, false)
    local boom = function() error("the client refused") end
    s = N.ViewState({ position = boom, zone = boom, facing = boom, mapSize = boom }, steps)
    t.eq(s.player, nil)
    t.eq(s.facingKnown, false)
    t.eq(s.quest.distance, nil)
    t.eq(s.quest.hasStep, true)
end

T["prof.on false is passed on; anything else is left out"] = function(t)
    local step = share(1411, 0.8, 0.5)
    step.on = false
    t.eq(N.ViewState(client(), { prof = step }).prof.on, false)
    step.on = nil
    t.eq(N.ViewState(client(), { prof = step }).prof.on, nil)
end

T["the arrow view takes the state as it is"] = function(t)
    local s = N.ViewState(client(), {
        quest = share(1411, 0.5, 0.3), prof = share(1411, 0.8, 0.5),
        view = { gate = "open", screenW = 1024, screenH = 768 },
    })
    local v = N.ArrowView(s)
    t.eq(v.quest.shown, true)
    t.eq(v.quest.mode, "arrow")
    t.eq(v.prof.mode, "arrow")
    local c = client()
    c.setFacing(nil)
    s = N.ViewState(c, { quest = share(1411, 0.5, 0.3), prof = share(1411, 0.8, 0.5),
                         view = { gate = "open", screenW = 1024, screenH = 768 } })
    t.eq(N.ArrowView(s).prof.mode, "off", "no facing: the profession arrow cannot point")
end

T["what is handed in is not changed, and the state shares no table with it"] = function(t)
    local own = { 1, 0, 0 }
    local steps = { quest = share(1411, 0.5, 0.3), prof = share(1411, 0.8, 0.5) }
    steps.prof.own = own
    local s = N.ViewState(client(), steps)
    t.eq(steps.quest, share(1411, 0.5, 0.3))
    s.prof.own[1] = 0
    t.eq(own[1], 1)
end

-- Lead section 510 (CHANGES-1). The quest step lies due north; the profession
-- step 200 yards off at `deg` degrees east of north.
local function at(deg)
    local a = deg * math.pi / 180
    return { quest = share(1411, 0.5, 0.3),
             prof = share(1411, 0.5 + 200 * math.sin(a) / 1000, 0.5 - 200 * math.cos(a) / 500),
             view = { gate = "open", screenW = 1024, screenH = 768 } }
end

T["the echo's last place is kept per client: two reads in a row at 29 to 31 degrees do not flip it"] = function(t)
    local c = client()
    local function slid(deg)
        local s = N.ViewState(c, at(deg))
        local first = N.ArrowView(s).prof.slid
        t.eq(N.ArrowView(s).prof.slid, first, deg .. ": the same state gives the same answer twice")
        return first
    end
    t.eq(slid(31), true, "31 first: slid")
    t.eq(slid(29), true, "then 29: still slid, inside the band")
    t.eq(slid(31), true, "then 31: slid")
    t.eq(slid(24), false, "then 24: past the band, tucked under")
    t.eq(slid(31), false, "then 31: still tucked under, inside the band")
    t.eq(slid(29), false, "then 29: tucked under")
    t.eq(slid(36), true, "then 36: past the band, slid")
    -- Another client has its own answer.
    t.eq(N.ArrowView(N.ViewState(client(), at(29))).prof.slid, false, "a fresh client at 29: the plain edge")
    t.eq(N.ArrowView(N.ViewState(client(), at(31))).prof.slid, true, "a fresh client at 31: the plain edge")
end

T["with no spread the echo's last place is dropped"] = function(t)
    local c = client()
    t.eq(N.ArrowView(N.ViewState(c, at(31))).prof.slid, true, "31: slid")
    local s = N.ViewState(c, { quest = share(1411, 0.5, 0.3), view = { gate = "open" } })
    t.eq(s.echoSlid, nil, "one step only: nothing carried")
    t.eq(N.ArrowView(N.ViewState(c, at(29))).prof.slid, false, "29 after that: the plain edge again")
end

return T
