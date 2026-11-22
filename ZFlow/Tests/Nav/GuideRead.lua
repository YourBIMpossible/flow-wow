local _, ns = ...
-- GuideRead tests: the guide fed from a client. The link is built from what
-- the client says about the player's map; what the client does not say
-- stays unknown.
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

local function step(zone, x, y, label)
    return { place = { cont = 1, zone = zone, x = x, y = y }, label = label }
end

local T = {}

T["link: the player's map with the size the client gives"] = function(t)
    t.eq(N.GuideLink(client()), { [1411] = { x = 0, y = 0, w = 1000, h = 500 } })
end

T["link: no position or no size: nothing in it"] = function(t)
    local c = client()
    c.setMapSize(1411, nil)
    t.eq(N.GuideLink(c), {})
    c = client()
    c.setPosition(nil)
    t.eq(N.GuideLink(c), {})
    t.eq(N.GuideLink(nil), {})
    t.eq(N.GuideLink({}), {})
end

T["link: a size that is not a size is left out"] = function(t)
    local c = client()
    c.mapSize = function() return { w = 0, h = 500 } end
    t.eq(N.GuideLink(c), {})
    c.mapSize = function() return "big" end
    t.eq(N.GuideLink(c), {})
    c.mapSize = function() error("the client refused") end
    t.eq(N.GuideLink(c), {})
end

T["link: a link handed in keeps its offsets; sizes come from the client"] = function(t)
    local given = { [1411] = { x = 200, y = 100, w = 1, h = 1 }, [1412] = { x = 1200, y = 100 } }
    local link = N.GuideLink(client(), given)
    t.eq(link, { [1411] = { x = 200, y = 100, w = 1000, h = 500 }, [1412] = { x = 1200, y = 100 } })
    t.eq(given[1411], { x = 200, y = 100, w = 1, h = 1 }, "the given link is not changed")
end

T["link: extra maps are asked about too"] = function(t)
    local c = client()
    c.setMapSize(1412, 400, 300)
    local link = N.GuideLink(c, { [1412] = { x = 1000, y = 0 } }, { 1412, 99 })
    t.eq(link[1412], { x = 1000, y = 0, w = 400, h = 300 })
    t.eq(link[99], nil, "no size from the client: left out")
end

T["read: distance and turn from the client's reads"] = function(t)
    local s = N.GuideRead(client(), { quest = step(1411, 500, 150, "Quest"), prof = step(1411, 800, 250, "Vein") })
    t.eq(s.player, { cont = 1, zone = 1411 })
    t.eq(s.facingKnown, true)
    near(t, s.quest.distance, 100, "quest distance")
    near(t, s.quest.turn, 0, "quest turn")
    t.eq(s.quest.label, "Quest")
    near(t, s.prof.distance, 300, "prof distance")
    t.eq(s.prof.mode, "arrow")
end

T["read: the same answer as the guide given the same reads"] = function(t)
    local c = client()
    local steps = { quest = step(1411, 500, 150), prof = step(1411, 800, 250), separate = true,
                    view = { screenW = 1024, screenH = 768 } }
    local want = N.Guide({
        position = c.position(), zone = c.zone(), facing = c.facing(),
        link = { [1411] = { x = 0, y = 0, w = 1000, h = 500 } },
        quest = steps.quest, prof = steps.prof, separate = true, view = steps.view,
    })
    t.eq(N.GuideRead(c, steps), want)
end

T["read: no map size from the client: no distance, no turn"] = function(t)
    local c = client()
    c.setMapSize(1411, nil)
    local s = N.GuideRead(c, { quest = step(1411, 500, 150) })
    t.eq(s.quest.hasStep, true)
    t.eq(s.quest.distance, nil)
    t.eq(s.quest.turn, nil)
    t.eq(s.quest.why, "size")
end

T["read: no position from the client: no distance, no turn"] = function(t)
    local c = client()
    c.setPosition(nil)
    local s = N.GuideRead(c, { quest = step(1411, 500, 150) })
    t.eq(s.quest.distance, nil)
    t.eq(s.quest.turn, nil)
    t.eq(s.quest.why, "place")
    t.eq(s.player, { cont = 1, zone = 1411 })
end

T["read: no facing from the client: no turn"] = function(t)
    local c = client()
    c.setFacing(nil)
    local s = N.GuideRead(c, { quest = step(1411, 500, 150) })
    t.eq(s.facingKnown, false)
    t.eq(s.quest.turn, nil)
    near(t, s.quest.distance, 100, "distance")
end

T["read: a step in a zone the link does not relate: no distance"] = function(t)
    local s = N.GuideRead(client(), { quest = step(1412, 100, 250) })
    t.eq(s.quest.distance, nil)
    t.eq(s.quest.why, "zone")
end

T["read: a handed-in link relates a neighbour zone"] = function(t)
    local s = N.GuideRead(client(), { quest = step(1412, 100, 250),
                                      link = { [1411] = { x = 0, y = 0 }, [1412] = { x = 1000, y = 0 } } })
    near(t, s.quest.distance, 600, "distance")
end

T["read: a step given as shares of a map uses the client's size for it"] = function(t)
    local s = N.GuideRead(client(), { quest = { place = { cont = 1, map = 1411, x = 0.5, y = 0.3 } } })
    near(t, s.quest.distance, 100, "distance")
    s = N.GuideRead(client(), { quest = { place = { cont = 1, map = 1412, x = 0.5, y = 0.3 } } })
    t.eq(s.quest.distance, nil)
    t.eq(s.quest.why, "size")
end

T["link: a further map gets its size but no offset unless one is given (W1)"] = function(t)
    local c = client()
    c.setMapSize(1412, 2000, 1000)
    local link = N.GuideLink(c, nil, { 1412 })
    t.eq(link[1411], { x = 0, y = 0, w = 1000, h = 500 }, "the player's map sits at 0, 0")
    t.eq(link[1412], { w = 2000, h = 1000 }, "no offset is made up for another map")
end

T["read: a step on another map with a size but no link: no distance, no turn (W1)"] = function(t)
    local c = client()
    c.setMapSize(1412, 2000, 1000)
    local s = N.GuideRead(c, { quest = { place = { map = 1412, x = 0.5, y = 0.5 } } })
    t.eq(s.quest.distance, nil, "no distance from a guessed offset")
    t.eq(s.quest.turn, nil, "no turn from a guessed offset")
    t.eq(s.quest.why, "zone")
end

T["read: no steps: no arrows"] = function(t)
    local s = N.GuideRead(client(), nil)
    t.eq(s.quest, { hasStep = false })
    t.eq(s.prof, { hasStep = false, bearingKnown = false, mode = "off" })
end

T["read: no client, or one whose reads fail: an empty state, no error"] = function(t)
    local s = N.GuideRead(nil, { quest = step(1411, 500, 150) })
    t.eq(s.player, nil)
    t.eq(s.facingKnown, false)
    t.eq(s.quest.distance, nil)
    local boom = function() error("the client refused") end
    s = N.GuideRead({ position = boom, zone = boom, facing = boom, mapSize = boom }, { quest = step(1411, 500, 150) })
    t.eq(s.player, nil)
    t.eq(s.facingKnown, false)
    t.eq(s.quest.distance, nil)
    t.eq(s.quest.why, "place")
end

T["read: only position, zone, facing and mapSize are asked"] = function(t)
    local real, asked = client(), {}
    local c = setmetatable({}, { __index = function(_, k)
        asked[k] = true
        return real[k]
    end })
    N.GuideRead(c, { quest = step(1411, 500, 150) })
    t.eq(asked, { position = true, zone = true, facing = true, mapSize = true })
end

T["read: the steps handed in are not changed"] = function(t)
    local steps = { quest = step(1411, 500, 150, "Quest"), link = { [1411] = { x = 0, y = 0 } } }
    N.GuideRead(client(), steps)
    t.eq(steps, { quest = step(1411, 500, 150, "Quest"), link = { [1411] = { x = 0, y = 0 } } })
end

return T
