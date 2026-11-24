-- Tests for Nav/RouteKinds.lua (A1-26, lead section 547): which kinds of
-- stop the route takes. Pure; made-up stops. Not tested in game.
-- Fails before: there is no Nav/RouteKinds.lua.
local _, ns = ...

local tests = {}

local PICK = { quest = 1, kind = "pickup", label = "Pick up A" }
local TURN = { quest = 2, turnIn = true, label = "Hand in B" }
local OTHER = { label = "Somewhere" }

tests["route kinds: nothing saved takes the defaults"] = function(t)
    local RK = ns.Nav.RouteKinds
    t.eq(RK.Includes(nil, "quests"), true)
    t.eq(RK.Includes({}, "newQuests"), true)
    t.eq(RK.Includes({ quests = "yes" }, "quests"), true)
    t.eq(RK.Summary(nil), "everything")
end

tests["route kinds: a stop's kind"] = function(t)
    local RK = ns.Nav.RouteKinds
    t.eq(RK.KindOf(PICK), "newQuests")
    t.eq(RK.KindOf(TURN), "quests")
    t.eq(RK.KindOf(OTHER), nil)
    t.eq(RK.KindOf("x"), nil)
end

tests["route kinds: new quests off drops pick-ups, keeps the rest"] = function(t)
    local RK = ns.Nav.RouteKinds
    local kinds = RK.Set(nil, "newQuests", false)
    local got = RK.Filter({ PICK, TURN, OTHER }, kinds)
    t.eq(#got, 2)
    t.eq(got[1], TURN)
    t.eq(got[2], OTHER)
    t.eq(RK.Summary(kinds), "all but new quests")
end

tests["route kinds: none keeps only stops no kind claims"] = function(t)
    local RK = ns.Nav.RouteKinds
    local kinds = RK.Set({ quests = true }, "none", true)
    local got = RK.Filter({ PICK, TURN, OTHER }, kinds)
    t.eq(#got, 1)
    t.eq(got[1], OTHER)
    t.eq(RK.Summary(kinds), "nothing")
    t.eq(RK.Summary(RK.Set(kinds, "all", true)), "everything")
end

tests["route kinds: Set turns down bad words and leaves the input alone"] = function(t)
    local RK = ns.Nav.RouteKinds
    local before = { quests = false }
    local got, why = RK.Set(before, "fishing", true)
    t.eq(got, nil)
    t.eq(why, "no kind called fishing")
    t.eq(RK.Set(before, "quests", "maybe"), nil)
    local after = RK.Set(before, "quests", true)
    t.eq(after.quests, true)
    t.eq(before.quests, false)
end

return tests
