-- Tests for the trail hint lines (G38, lead dispatch section 391 item 3 /
-- section 395): the quest arrow says in plain words when it is following a
-- path the player walked into a cave, and when the player must first walk
-- to the cave's entrance. Made-up map 1411, 1000 x 500 yards; fake client.
-- Not tested in game. Look only.
local _, ns = ...

local N = ns.Nav
local A = ns.Arrow
local tests = {}

local MAP = 1411

local function start()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, {})
    c.setScreen(1024, 768)
    c.setZone(1, MAP)
    c.setFacing(0)
    c.setPosition(MAP, 0.5, 0.5)
    c.setMapSize(MAP, 1000, 500)
    c.setClass("WARRIOR")
    c.setFaction("Horde")
    c.setIndoors(false)
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    N.Trails.Declare(k, d)
    local a = A.Declare(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, a
end

local function at(c, x, y)
    c.setPosition(MAP, x / 1000, y / 500)
    c.advance(1.1, 2)
end

-- As Tests/Nav/TrailsTests.lua: east 48 yards outside, 60 yards north inside.
local function walkIn(c)
    for x = 500, 548, 12 do at(c, x, 250) end
    c.setIndoors(true)
    at(c, 548, 250)
    for y = 238, 190, -12 do at(c, 548, y) end
    c.setIndoors(false)
    at(c, 548, 190)
end

local function lines(c)
    local a = c.arrows and c.arrows[1]
    return type(a) == "table" and type(a.lines) == "table" and a.lines or {}
end

local function says(c, text)
    for _, l in ipairs(lines(c)) do
        if l == text then return true end
    end
    return false
end

local function way(c)
    c.slashes[ns.id.slash]("way 54.8 38")
    c.advance(A.RELAYOUT * 2, 2)
end

tests["trail hint: the two lines are plain words"] = function(t)
    local T = N.Trails
    t.eq(T.ON_TRAIL, "The way is through the cave: follow the arrow along the path you walked.")
    t.eq(T.TO_ENTRANCE, "The way in is a cave: walk to the entrance first.")
end

tests["trail hint: on the trail the arrow says to follow it"] = function(t)
    local k, c = start()
    walkIn(c)
    at(c, 500, 250)
    way(c)
    t.ok(says(c, N.Trails.ON_TRAIL), "the follow line: " .. table.concat(lines(c), " | "))
    t.ok(not says(c, N.Trails.TO_ENTRANCE), "not the entrance line")
    t.eq(k.problems:count(), 0)
end

tests["trail hint: far from the trail the arrow says to walk to the entrance"] = function(t)
    local _, c, a = start()
    walkIn(c)
    at(c, 100, 250)
    way(c)
    t.ok(says(c, N.Trails.TO_ENTRANCE), "the entrance line: " .. table.concat(lines(c), " | "))
    t.ok(not says(c, N.Trails.ON_TRAIL), "not the follow line")
    local h = a.heading()
    t.ok(type(h) == "table", "the arrow points somewhere")
    if type(h) == "table" then
        t.ok(math.abs(h.x - 0.548) < 1e-3 and math.abs(h.y - 0.38) < 1e-3, "still at the target")
    end
end

tests["trail hint: with no trail there is no cave line"] = function(t)
    local _, c = start()
    way(c)
    t.ok(not says(c, N.Trails.ON_TRAIL) and not says(c, N.Trails.TO_ENTRANCE), "no cave line")
end

tests["trail hint: learning off, no cave line"] = function(t)
    local k, c = start()
    walkIn(c)
    k.settings:set(N.Trails.SETTING, false)
    at(c, 500, 250)
    way(c)
    t.ok(not says(c, N.Trails.ON_TRAIL) and not says(c, N.Trails.TO_ENTRANCE), "no cave line")
end

tests["trail hint pure: Hint picks the line from where the player is"] = function(t)
    local T = N.Trails
    local pts = { { x = 0, y = 0 }, { x = 10, y = 0 }, { x = 20, y = 0 }, { x = 20, y = 10 }, { x = 20, y = 20 } }
    t.eq(T.Hint(pts, { x = 0, y = 0 }, { x = 20, y = 20 }), T.ON_TRAIL, "on the trail")
    t.eq(T.Hint(pts, { x = 0, y = 40 }, { x = 20, y = 20 }), T.TO_ENTRANCE, "near, not on it")
    t.eq(T.Hint(pts, { x = 400, y = 0 }, { x = 20, y = 20 }), T.TO_ENTRANCE, "far away")
    t.eq(T.Hint(pts, { x = 0, y = 0 }, { x = 400, y = 400 }), nil, "target not on the trail")
    t.eq(T.Hint(pts, { x = 20, y = 18 }, { x = 20, y = 20 }), nil, "already there")
end

return tests
