-- Hearthstone advice (G46, lead DISPATCH section 391 item 2): the words that
-- say when hearthing saves the walk and when to set a new home inn.
-- N.HearthAdvice over hand-written tables. Made-up places, test only.
-- Not tested in game.
local _, ns = ...

local N = ns.Nav

-- Map 1411 is 3000 by 3000 yards. Walking is 7 yards a second.
local SIZE = { w = 3000, h = 3000 }
local TARGET = { map = 1411, x = 0.6, y = 0.5 }
-- The player is 1500 yards (about 214 s) from TARGET; the inn 150 (about 21 s).
local HERE = { map = 1411, x = 0.6, y = 1.0 }
local function bind(more)
    local b = { name = "Goldshire", map = 1411, x = 0.55, y = 0.5 }
    for key, v in pairs(more or {}) do b[key] = v end
    return b
end
local function ask(more)
    local o = { bind = bind(), cooldown = 0, here = HERE, target = TARGET, size = SIZE }
    for key, v in pairs(more or {}) do o[key] = v end
    return o
end

local T = {}

T["hearth advice: the threshold and the words agreed"] = function(t)
    local H = N.HearthAdvice
    t.eq(H.SAVES, 120)
    t.eq(H.CAST, 10)
    t.eq(H.NO_HOME, "Talk to an innkeeper to set your home: then your hearthstone can save you long walks.")
end

T["hearth advice: it saves enough: hearth to the bind place, in minutes"] = function(t)
    -- 214 s walked against 10 s cast and 21 s from the inn: 183 s, 3 minutes.
    local line, why = N.HearthAdvice.Hearth(ask())
    t.eq(why, "hearth")
    t.eq(line, "Hearth to Goldshire: it saves about 3 minutes of walking.")
end

T["hearth advice: it does not save enough: nothing said"] = function(t)
    -- 600 yards away: 86 s walked, 31 s by the stone: 55 s is below 2 minutes.
    local line, why = N.HearthAdvice.Hearth(ask({ here = { map = 1411, x = 0.6, y = 0.7 } }))
    t.eq(line, nil)
    t.eq(why, "near")
    -- far, but the inn is as far from the step as the player is
    line, why = N.HearthAdvice.Hearth(ask({ bind = bind({ x = 0.6, y = 0.0 }) }))
    t.eq(line, nil)
    t.eq(why, "no saving")
end

T["hearth advice: the player's own trip time is used when known"] = function(t)
    -- legs says the walk from the player takes 2100 yards' worth: 300 s.
    local legs = function(a, b, d)
        if a.y > 2000 or b.y > 2000 then return 2100, "exact" end
        return d, nil
    end
    local line = N.HearthAdvice.Hearth(ask({ legs = legs }))
    t.eq(line, "Hearth to Goldshire: it saves about 4 minutes of walking.")
end

T["hearth advice: on cooldown: ready in minutes, only when that changes the advice"] = function(t)
    local line, why = N.HearthAdvice.Hearth(ask({ cooldown = 100 }))
    t.eq(why, "on cooldown")
    t.eq(line, "Your hearthstone is ready in 2 minutes: then hearth to Goldshire to save the walk.")
    -- ready only after the walk is over: no line
    line, why = N.HearthAdvice.Hearth(ask({ cooldown = 1500 }))
    t.eq(line, nil)
    t.eq(why, "on cooldown")
    -- no stone carried (not known): no line, never taken as ready
    line, why = N.HearthAdvice.Hearth(ask({ cooldown = false }))
    t.eq(line, nil)
    t.eq(why, "no stone")
end

T["hearth advice: home not known: talk to an innkeeper"] = function(t)
    local line, why = N.HearthAdvice.Hearth(ask({ bind = {} }))
    t.eq(why, "no home")
    t.eq(line, N.HearthAdvice.NO_HOME)
    -- the name known but not where the inn is: nothing is claimed
    line, why = N.HearthAdvice.Hearth(ask({ bind = { name = "Goldshire" } }))
    t.eq(line, nil)
    t.eq(why, "bind place unknown")
    -- the step is near: no advice about homes at all
    line = N.HearthAdvice.Hearth(ask({ bind = {}, here = { map = 1411, x = 0.6, y = 0.55 } }))
    t.eq(line, nil)
end

local STOPS = { { map = 1411, x = 0.6, y = 0.5 }, { map = 1411, x = 0.62, y = 0.52 }, { map = 1411, x = 0.1, y = 0.1 } }
local INNS = { { name = "Farley", map = 1411, x = 0.6, y = 0.52 } }
local function sizes() return SIZE end

T["hearth advice: set a new home where most of the quests are"] = function(t)
    local H = N.HearthAdvice
    local line, why = H.Home({ bind = bind({ name = "Lakeshire", x = 0.05, y = 0.05 }), inns = INNS,
                               stops = STOPS, size = sizes })
    t.eq(why, "set home")
    t.eq(line, "Set your home at Farley's inn: most of your quests are near it.")
    -- with no home at all, the same advice
    line = H.Home({ bind = {}, inns = INNS, stops = STOPS, size = sizes })
    t.eq(line, "Set your home at Farley's inn: most of your quests are near it.")
end

T["hearth advice: no new home when it is already there, or the quests are spread"] = function(t)
    local H = N.HearthAdvice
    local line, why = H.Home({ bind = bind({ x = 0.601, y = 0.521 }), inns = INNS, stops = STOPS, size = sizes })
    t.eq(line, nil)
    t.eq(why, "home already")
    line, why = H.Home({ bind = bind({ x = 0.05, y = 0.05 }), inns = INNS, size = sizes,
                        stops = { STOPS[1], STOPS[3], { map = 1411, x = 0.9, y = 0.9 } } })
    t.eq(line, nil)
    t.eq(why, "spread")
    line, why = H.Home({ bind = { name = "Lakeshire" }, inns = INNS, stops = STOPS, size = sizes })
    t.eq(line, nil)
    t.eq(why, "bind place unknown")
end

T["hearth advice: the inns seen are the innkeepers among the services"] = function(t)
    local inns = N.HearthAdvice.Inns({
        ["b"] = { name = "Farley", map = 1411, x = 0.6, y = 0.5, kinds = { innkeeper = true } },
        ["a"] = { name = "Smith", map = 1411, x = 0.6, y = 0.5, kinds = { vendor = true } },
        ["c"] = { name = "Bad", map = 1411, x = "no", y = 0.5, kinds = { innkeeper = true } },
    })
    t.eq(inns, { { name = "Farley", map = 1411, x = 0.6, y = 0.5 } })
end

return T
