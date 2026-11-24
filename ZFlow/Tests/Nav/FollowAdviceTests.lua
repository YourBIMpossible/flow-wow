-- Tests for Nav/FollowAdvice.lua (G47, lead section 397 item 15): in a
-- group, one advisor line when your leader is far away, with how far and
-- which way. TEXT ONLY: nothing follows, targets, assists or casts. Pure
-- parts and the client read; made-up names. Not tested in game.
local _, ns = ...

local tests = {}
local MAP = 1411

local function FA() return ns.Nav and ns.Nav.FollowAdvice end

local function has(t)
    local F = FA()
    local ok = type(F) == "table" and type(F.Text) == "function"
    t.ok(ok, "Nav/FollowAdvice.lua is loaded")
    return ok
end

local SIZE = { w = 1000, h = 1000 }

tests["follow advice: the leader far away gives one line with yards and a direction"] = function(t)
    if not has(t) then return end
    local me = { map = MAP, x = 0.5, y = 0.5 }
    local at = { map = MAP, x = 0.5, y = 0.3 }   -- 200 yd north
    t.eq(FA().Text("Ander", me, at, SIZE), "Your leader Ander is 200 yd away to the N: catch up.")
end

tests["follow advice: near, unknown, another map or no size: no line"] = function(t)
    if not has(t) then return end
    local F = FA()
    local me = { map = MAP, x = 0.5, y = 0.5 }
    t.eq(F.Text("Ander", me, { map = MAP, x = 0.52, y = 0.5 }, SIZE), nil, "20 yd: near")
    t.eq(F.Text("Ander", me, nil, SIZE), nil, "where the leader is is not known")
    t.eq(F.Text("Ander", nil, { map = MAP, x = 0.1, y = 0.1 }, SIZE), nil, "where you are is not known")
    t.eq(F.Text("Ander", me, { map = MAP + 1, x = 0.1, y = 0.1 }, SIZE), nil, "another map")
    t.eq(F.Text("Ander", me, { map = MAP, x = 0.1, y = 0.1 }, nil), nil, "map size not known")
    t.eq(F.Text(nil, me, { map = MAP, x = 0.1, y = 0.1 }, SIZE), nil, "no name")
end

tests["follow advice: the fake leader read and the real read with no game"] = function(t)
    local c = ns.make.fakeClient()
    t.ok(type(c.groupLeader) == "function" and type(c.setGroupLeader) == "function", "fake read and setter")
    if type(c.setGroupLeader) ~= "function" then return end
    t.eq(c.groupLeader(), nil, "not set: not known")
    c.setGroupLeader("party2")
    t.eq(c.groupLeader(), "party2")
    c.setGroupLeader(false)
    t.eq(c.groupLeader(), false)
    local real = ns.make.client({})
    t.ok(type(real.groupLeader) == "function", "the real client has the read")
    if type(real.groupLeader) == "function" then t.eq(real.groupLeader(), nil, "no game: no answer") end
end

return tests
