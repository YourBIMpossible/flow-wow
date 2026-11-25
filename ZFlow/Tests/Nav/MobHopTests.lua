local _, ns = ...

-- Tests for A2-25 (lead section 667): hop from mob group to mob group in a
-- kill objective's area (Nav/MobHop.lua). Pure: made-up spots on a made-up
-- map 1000 by 1000 yards, so a share of 0.01 is 10 yards.

local tests = {}

local N = ns.Nav
local MAP = 9001
local SIZE = { w = 1000, h = 1000 }
local M = function() return N.MobHop end

local function near(a, b) return math.abs(a - b) < 1e-6 end

tests["clusters: spots within a group's reach are one group, a far spot its own"] = function(t)
    local spots = {
        { map = MAP, x = 0.10, y = 0.10 },
        { map = MAP, x = 0.12, y = 0.10 },
        { map = MAP, x = 0.50, y = 0.50 },
    }
    local g = M().Clusters(spots, SIZE)
    t.eq(#g, 2)
    t.eq(g[1].n, 2)
    t.ok(near(g[1].x, 0.11), "middle of the first group")
    t.ok(near(g[1].y, 0.10))
    t.eq(g[2].n, 1)
    t.eq(g[1].map, MAP)
end

tests["clusters: nothing, or no map size, gives no groups"] = function(t)
    t.eq(#M().Clusters(nil, SIZE), 0)
    t.eq(#M().Clusters({ { map = MAP, x = 0.1, y = 0.1 } }, nil), 0)
end

tests["order: a greedy chain from the player, not a sort by distance from the player"] = function(t)
    local a = { map = MAP, x = 0.10, y = 0, n = 1, spots = { { x = 0.10, y = 0 } } }
    local b = { map = MAP, x = 0.30, y = 0, n = 1, spots = { { x = 0.30, y = 0 } } }
    local c = { map = MAP, x = 0, y = 0.25, n = 1, spots = { { x = 0, y = 0.25 } } }
    local out = M().Order({ c, b, a }, { x = 0, y = 0 }, SIZE)
    t.eq(#out, 3)
    t.eq(out[1], a)
    t.eq(out[2], b)
    t.eq(out[3], c)
    t.ok(near(out[1].leg, 100), "100 yards to the first")
    t.ok(near(out[2].leg, 200), "200 yards on to the second")
    t.ok(math.abs(out[3].leg - 390.5125) < 0.001, "then on to the third")
end

tests["order: no place or no size gives nil"] = function(t)
    t.eq(M().Order({}, nil, SIZE), nil)
    t.eq(M().Order({}, { x = 0, y = 0 }, nil), nil)
end

tests["move on: the objective done"] = function(t)
    local go, why = M().MoveOn({ done = true, yardsIn = 0, now = 5, since = 0 })
    t.eq(go, true)
    t.eq(why, "done")
end

tests["move on: walked out of the group"] = function(t)
    local go, why = M().MoveOn({ yardsIn = M().INSIDE + 1, now = 5, since = 0 })
    t.eq(go, true)
    t.eq(why, "left")
end

tests["move on: stood in the group a while with no fight and no loot"] = function(t)
    local go, why = M().MoveOn({ yardsIn = 10, now = 100, since = 100 - M().STAY })
    t.eq(go, true)
    t.eq(why, "idle")
end

tests["move on: a recent fight or loot keeps you in the group"] = function(t)
    local go = M().MoveOn({ yardsIn = 10, now = 100, since = 0, busy = 95 })
    t.eq(go, false)
    t.eq(M().MoveOn({ yardsIn = 10, now = 100, since = 90 }), false)
    t.eq(M().MoveOn(nil), false)
end

tests["plan: Questie spawns on the player's map, grouped and ordered; other maps left out"] = function(t)
    local spawns = { [12] = { { 50, 50 }, { 10, 10 }, { 12, 10 } }, [99] = { { 5, 5 } } }
    local zones = { GetUiMapIdByAreaId = function(_, area) return ({ [12] = MAP, [99] = 77 })[area] end }
    local out = M().Plan(spawns, zones, { map = MAP, x = 0, y = 0 }, SIZE)
    t.eq(#out, 2)
    t.ok(near(out[1].x, 0.11), "the near group first")
    t.eq(out[1].n, 2)
    t.ok(near(out[2].x, 0.50))
end

return tests
