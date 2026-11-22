-- Tests for S44, the quest place on another map (lead section 173). The
-- owner's session 6, Block B: a quest on another map showed "on another
-- map", a needle that never turned, no travel step and "nothing to walk
-- past". Now:
--   1. QuestRead keeps one point from another map (`away`) when the spot
--      has none on the player's map; `elsewhere` stays as it was.
--   2. QuestSource's words-only step takes that point as its place (no
--      `still`), so the arrow asks Travel.Via and the needle can turn.
--   3. The needle turns across maps: client.mapCorners(map) gives each
--      map's corners in the world, and GuideRead places the step's map in
--      the player's map frame with them.
-- Fake client and hand-written stand-ins; every place is made up. Not
-- tested in game. Look only: nothing moves, casts or walks for the player.
local _, ns = ...

local N, A = ns.Nav, ns.Arrow
local Q = N.QuestSource
local tests = {}

local function near(a, b, by) return type(a) == "number" and math.abs(a - b) <= (by or 1e-6) end

-- ------------------------------------------------------------ 1. QuestRead

-- A stand-in for Questie: wolves only on area 40 (map 1412), twice.
local function questie()
    local db = {}
    function db.GetQuest(id)
        if id == 303 then return { ObjectiveData = { { Type = "monster", Id = 9002 } } } end
        return nil
    end
    function db.GetNPC(id)
        if id == 9002 then return { name = "Far Wolf", spawns = { [40] = { { 50, 50 }, { 20, 20 } } } } end
        return nil
    end
    local zones = {}
    function zones.GetUiMapIdByAreaId(area) return ({ [12] = 1411, [40] = 1412 })[area] end
    return function(name) return ({ QuestieDB = db, ZoneDB = zones })[name] end
end

local function wolves() return { id = 303, title = "Wolves", objectives = { { text = "Wolves slain: 0/4" } } } end

tests["away: QuestRead keeps the first point seen on another map, and only then"] = function(t)
    local c = ns.make.fakeClient()
    c.questieModule = questie()
    local rows = { wolves() }
    local spot = N.QuestiePlaces(c, rows, 1411)[303].objectives[1]
    t.eq(spot, { points = {}, elsewhere = true, away = { map = 1412, x = 0.5, y = 0.5 } })
    local there = N.QuestiePlaces(c, rows, 1412)[303].objectives[1]
    t.eq(there.away, nil, "points on the map asked for: no away point")
    t.eq(#there.points, 2)
end

-- ---------------------------------------------------------- 2. QuestSource

local HERE = { map = 1411, x = 0.5, y = 0.5, cont = 1, size = { w = 1000, h = 500 } }

tests["away: the words-only step takes the point as its place, no still"] = function(t)
    local places = { [303] = { objectives = { { points = {}, elsewhere = true, away = { map = 1412, x = 0.5, y = 0.5 } } } } }
    local step, from = Q.Pick({ wolves() }, places, HERE)
    t.eq(from, "log")
    t.eq(step, { quest = 303, objective = 1, turnIn = false, label = "Wolves", detail = "Wolves slain: 0/4",
                 place = { map = 1412, x = 0.5, y = 0.5 } })
end

tests["away: a turn-in on another map gets its place too"] = function(t)
    local row = { id = 202, title = "Crates", complete = true, objectives = {} }
    local places = { [202] = { turnIn = { points = {}, elsewhere = true, name = "Marshal Dughan",
                                          away = { map = 1412, x = 0.1, y = 0.2 } } } }
    local step = Q.Pick({ row }, places, HERE)
    t.eq(step.place, { map = 1412, x = 0.1, y = 0.2 })
    t.eq(step.detail, "Turn in: Marshal Dughan")
    t.eq(step.still, nil)
    t.eq(step.lines, nil)
end

tests["away: a point on the player's map still wins over one away"] = function(t)
    local boars = { id = 101, title = "Boars", objectives = { { text = "Boars slain: 2/8" } } }
    local places = {
        [303] = { objectives = { { points = {}, elsewhere = true, away = { map = 1412, x = 0.5, y = 0.5 } } } },
        [101] = { objectives = { { points = { { map = 1411, x = 0.6, y = 0.5 } } } } },
    }
    local step = Q.Pick({ wolves(), boars }, places, HERE)
    t.eq(step.quest, 101)
    t.eq(step.place.map, 1411)
end

tests["away: no away point, the words as before"] = function(t)
    local places = { [303] = { objectives = { { points = {}, elsewhere = true } } } }
    local step = Q.Pick({ wolves() }, places, HERE)
    t.eq(step.lines, { "Wolves", "Wolves slain: 0/4", Q.ELSEWHERE })
    t.eq(step.still, true)
    local bad = { [303] = { objectives = { { points = {}, elsewhere = true, away = { map = 1412, x = "x", y = 0.5 } } } } }
    t.eq(Q.Pick({ wolves() }, bad, HERE).still, true, "an away point that is no place is not used")
end

-- --------------------------------------------------- 3. client.mapCorners

-- A world where each map's (x, y) share lies at origin + x * east + y * south.
local MAPS = {
    [1411] = { cont = 1, o = { 1000, 2000 }, e = { 0, -1000 }, s = { -500, 0 } },
    [1412] = { cont = 1, o = { 1000, 1000 }, e = { 0, -800 }, s = { -800, 0 } },
    [1450] = { cont = 2, o = { 0, 0 }, e = { 0, -500 }, s = { -500, 0 } },
}

local function worldEnv()
    local env = { made = 0 }
    env.CreateVector2D = function(x, y)
        env.made = env.made + 1
        return { x = x, y = y, GetXY = function(self) return self.x, self.y end }
    end
    env.C_Map = { GetWorldPosFromMapPos = function(map, v)
        local m = MAPS[map]
        if not m then return nil end
        local x, y = v:GetXY()
        local wx, wy = m.o[1] + x * m.e[1] + y * m.s[1], m.o[2] + x * m.e[2] + y * m.s[2]
        return m.cont, { GetXY = function() return wx, wy end }
    end }
    return env
end

tests["c.mapCorners: a map's corners in the world"] = function(t)
    local env = worldEnv()
    local c = ns.make.client(env)
    t.eq(c.mapCorners(1411), { cont = 1, ox = 1000, oy = 2000, ex = 1000, ey = 1000, sx = 500, sy = 2000 })
    t.eq(env.made, 3, "three points asked: 0,0, 1,0 and 0,1")
    t.eq(c.mapCorners(9999), nil, "a map the client cannot place")
    t.eq(c.mapCorners(nil), nil)
    t.eq(ns.make.client({}).mapCorners(1411), nil, "no map calls")
    local raised = worldEnv()
    raised.C_Map.GetWorldPosFromMapPos = function() error("no") end
    t.eq(ns.make.client(raised).mapCorners(1411), nil, "raised")
    local secret = worldEnv()
    secret.issecretvalue = function(v) return v == 1000 end
    t.eq(ns.make.client(secret).mapCorners(1411), nil, "a secret coordinate")
end

tests["fake client: mapCorners is unknown until set, a copy each time"] = function(t)
    local c = ns.make.fakeClient()
    t.eq(c.mapCorners(1411), nil)
    c.setMapCorners(1411, { cont = 1, ox = 1, oy = 2, ex = 3, ey = 4, sx = 5, sy = 6 })
    local got = c.mapCorners(1411)
    t.eq(got, { cont = 1, ox = 1, oy = 2, ex = 3, ey = 4, sx = 5, sy = 6 })
    got.ox = 99
    t.eq(c.mapCorners(1411).ox, 1)
    c.setMapCorners(1411, nil)
    t.eq(c.mapCorners(1411), nil)
end

-- ------------------------------------------------------ 3. GuideRead link

local function corners(m)
    local d = MAPS[m]
    return { cont = d.cont, ox = d.o[1], oy = d.o[2], ex = d.o[1] + d.e[1], ey = d.o[2] + d.e[2],
             sx = d.o[1] + d.s[1], sy = d.o[2] + d.s[2] }
end

-- The player in the middle of 1411 (1000 by 500 yards), facing north.
local function client(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setZone(1, 1411)
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    c.setMapSize(1412, 800, 800)
    c.setMapSize(1450, 500, 500)
    c.setFacing(0)
    if opts.corners ~= false then
        for m in pairs(MAPS) do c.setMapCorners(m, corners(m)) end
    end
    return c
end

tests["away: the step's map is placed beside the player's through the world"] = function(t)
    local c = client()
    -- 1412 starts at 1411's east edge: 1000 yd east, 0 south. Its middle is
    -- (400, 400) in it, so (1400, 400) from 1411's corner; the player is at
    -- (500, 250): 900 east, 150 south.
    local link = N.GuideLink(c, nil, { 1412 })
    t.eq(link[1411], { x = 0, y = 0, w = 1000, h = 500 })
    t.ok(near(link[1412].x, 1000) and near(link[1412].y, 0), tostring(link[1412].x) .. ", " .. tostring(link[1412].y))
    t.eq({ link[1412].w, link[1412].h }, { 800, 800 })
    local s = N.GuideRead(c, { quest = { place = { map = 1412, x = 0.5, y = 0.5 }, label = "Wolves" } })
    t.ok(near(s.quest.distance, math.sqrt(900 * 900 + 150 * 150)), tostring(s.quest.distance))
    t.eq(s.quest.compass, "E")
    t.eq(s.quest.why, nil)
end

tests["away: maps not placed by the world stay unrelated"] = function(t)
    local s = N.GuideRead(client({ corners = false }), { quest = { place = { map = 1412, x = 0.5, y = 0.5 } } })
    t.eq(s.quest.why, "zone", "no corners: as before")
    s = N.GuideRead(client(), { quest = { place = { map = 1450, x = 0.5, y = 0.5 } } })
    t.eq(s.quest.why, "zone", "another continent: never placed beside")
    local given = N.GuideLink(client(), { [1412] = { x = 5, y = 6 } }, { 1412 })
    t.eq({ given[1412].x, given[1412].y }, { 5, 6 }, "a caller's offsets are kept")
    t.eq(given[1411], { w = 1000, h = 500 }, "and the player's map stays unplaced in the caller's frame")
end

-- ------------------------------------------- the owner's scenario: arrow

-- A druid on 1411 who knows Teleport: Moonglade. opts.quest: where the
-- quest's wolves are ({ area, x, y }, Questie's 0..100).
local function arrow(opts)
    opts = opts or {}
    local c = client()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setScreen(1024, 768)
    c.setClass("DRUID")
    c.setFaction("Horde")
    c.setSpellId("Teleport: Moonglade", 18960)
    c.setSpell(18960, { known = true })
    c.questLog = function() return { wolves() } end
    local spawn = opts.quest or { 40, 50, 50 }
    local db = {}
    function db.GetQuest(id)
        if id == 303 then return { ObjectiveData = { { Type = "monster", Id = 9002 } } } end
        return nil
    end
    function db.GetNPC(id)
        if id == 9002 then return { name = "Far Wolf", spawns = { [spawn[1]] = { { spawn[2], spawn[3] } } } } end
        return nil
    end
    local zones = {}
    function zones.GetUiMapIdByAreaId(area) return ({ [12] = 1411, [40] = 1412, [493] = 1450 })[area] end
    c.questieModule = function(name) return ({ QuestieDB = db, ZoneDB = zones })[name] end
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    A.Start(k, d)
    N.Travel.Declare(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c
end

tests["owner session 6 B: a quest on the next map turns the needle and says how far"] = function(t)
    local k, c = arrow()
    local q = c.arrows[1]
    t.eq(q.shown, true)
    t.eq(q.lines[1], "Wolves")
    t.eq(q.lines[2], "Wolves slain: 0/4")
    t.eq(q.lines[3], "912 yd E", "no 'on another map' and no 'direction unknown'")
    t.eq(#q.lines, 3)
    t.eq(k.problems:count(), 0)
end

tests["owner session 6 B: a quest in Moonglade is a cast away, and walk works"] = function(t)
    local _, c = arrow({ quest = { 493, 50, 50 } })
    t.eq(c.arrows[1].lines, { "Cast Teleport: Moonglade", "Then: Wolves" }, "Travel.Via was reached")
    c.slashes[ns.id.slash](N.Travel.WORD)
    t.ok(c.printed[#c.printed]:find("you walk to this step", 1, true) ~= nil, c.printed[#c.printed])
    c.advance(A.RELAYOUT * 2, 2)
    t.eq(c.arrows[1].lines[1], "Wolves", "walking: the quest step itself")
    c.slashes[ns.id.slash](N.Travel.WORD)
    c.advance(A.RELAYOUT * 2, 2)
    t.eq(c.arrows[1].lines[1], "Cast Teleport: Moonglade", "said again: the shortcut is back")
end

return tests
