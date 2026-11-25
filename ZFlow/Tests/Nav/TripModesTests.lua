local _, ns = ...

-- Tests for the route modes, the hub tour first and how many steps show
-- (FLOW-PARITY A1-25, A1-29, A1-30; ZFlow/Nav/TripRoute.lua and
-- Nav/RoutePickups.lua). Pure parts. Made-up quests and places.

local tests = {}

local function T() return ns.Nav.TripRoute end
local function P() return ns.Nav.RoutePickups end

tests["route modes: quests only, the optimal route, or everything"] = function(t)
    t.eq(T().ModeFlags("quests"), { pickups = false, town = false, low = false, hub = false })
    t.eq(T().ModeFlags("optimal"), { pickups = true, town = true, low = false, hub = true })
    t.eq(T().ModeFlags("complete"), { pickups = true, town = true, low = true, hub = true })
    t.eq(T().ModeFlags(nil), T().ModeFlags("optimal"), "no choice: the optimal route")
    t.eq(T().ModeFlags("fly"), T().ModeFlags("optimal"))
end

tests["route modes: everything takes pick-ups far below your level too"] = function(t)
    local q = { Id = 9, name = "Old Errand", level = 3, requiredLevel = 1 }
    local ctx = { level = 20, log = {}, me = {} }
    t.eq((P().Candidate(q, ctx)), false, "far below: not on the optimal route")
    ctx.low = true
    t.eq((P().Candidate(q, ctx)), true, "on the route for everything")
end

local HERE = { map = 1, x = 0.5, y = 0.5 }
local SIZE = { w = 1000, h = 1000 }

local function stop(label, x, y, more)
    local s = { label = label, place = { map = 1, x = x, y = y } }
    for key, v in pairs(more or {}) do s[key] = v end
    return s
end

tests["hub first: turn-ins and pick-ups close by come first, nearest first"] = function(t)
    local stops = {
        stop("Far objective", 0.9, 0.9),
        stop("Turn in near", 0.6, 0.5, { turnIn = true }),
        stop("Pick up nearest", 0.52, 0.5, { kind = "pickup" }),
        stop("Pick up far", 0.95, 0.1, { kind = "pickup" }),
        stop("Close objective", 0.51, 0.5),
    }
    local out = T().HubFirst(stops, HERE, SIZE, 250)
    t.eq(out[1].label, "Pick up nearest")
    t.eq(out[2].label, "Turn in near")
    t.eq(out[3].label, "Far objective", "the rest keep their planned order")
    t.eq(out[4].label, "Pick up far")
    t.eq(out[5].label, "Close objective", "an objective is never hub business")
    t.eq(#out, 5)
end

tests["hub first: pick-ups only as many as the quest log has room for"] = function(t)
    local stops = {
        stop("Pick up A", 0.51, 0.5, { kind = "pickup" }),
        stop("Pick up B", 0.52, 0.5, { kind = "pickup" }),
        stop("Turn in", 0.53, 0.5, { turnIn = true }),
    }
    local out = T().HubFirst(stops, HERE, SIZE, 250, 0)
    -- A full log: the turn-in frees one slot, so one pick-up (the nearest)
    -- joins the tour; the other waits in the planned order.
    t.eq(out[1].label, "Pick up A")
    t.eq(out[2].label, "Turn in")
    t.eq(out[3].label, "Pick up B")
    local none = T().HubFirst(stops, HERE, SIZE, 250, nil)
    t.eq(none[1].label, "Pick up A", "room not known: every close pick-up")
end

tests["hub first: no player place, nothing moves"] = function(t)
    local stops = { stop("A", 0.9, 0.9), stop("B", 0.5, 0.5, { turnIn = true }) }
    local out = T().HubFirst(stops, {}, SIZE, 250)
    t.eq(out[1].label, "A")
end

tests["steps shown: the first n of the route, or all"] = function(t)
    local route = { stops = { stop("A", 0, 0), stop("B", 0, 0), stop("C", 0, 0) } }
    t.eq(#T().Shown(route, 2).stops, 2)
    t.eq(T().Shown(route, 2).more, 1)
    t.eq(#T().Shown(route, nil).stops, 3)
    t.eq(T().Shown(route, nil).more, 0)
    t.eq(T().Shown(nil, 2), nil)
end

-- A1-29 (lead section 646): sort by XP, from the player's own Questie
-- (QuestXP:GetQuestLogRewardXP). A made-up module; no Questie data here.
local function fakeXp(values)
    local mod = {}
    function mod.GetQuestLogRewardXP(self, id)
        if self ~= mod then error("called without self") end
        if values[id] == "raise" then error("no data") end
        return values[id]
    end
    return mod
end

tests["sort by XP: a quest's XP from Questie; 0, nil or an error is not known"] = function(t)
    local xpOf = T().XpOf(fakeXp({ [1] = 450, [2] = 0, [4] = "raise" }))
    t.eq(xpOf(1), 450)
    t.eq(xpOf(2), nil, "0: not known")
    t.eq(xpOf(3), nil, "no entry")
    t.eq(xpOf(4), nil, "a read that raises")
    t.eq(xpOf(nil), nil)
    t.eq(T().XpOf(nil)(1), nil, "no Questie module")
end

tests["sort by XP: most XP first; quests not known keep their order after them"] = function(t)
    local stops = {
        stop("Near, unknown", 0.5, 0.5, { quest = 9 }),
        stop("Small", 0.6, 0.5, { quest = 1 }),
        stop("Town stop", 0.7, 0.5, { kind = "sell" }),
        stop("Big", 0.8, 0.5, { quest = 2 }),
        stop("Big again", 0.9, 0.5, { quest = 2, objective = 2 }),
    }
    local out = T().SortXp(stops, function(id) return ({ [1] = 100, [2] = 900 })[id] end)
    t.eq(out[1].label, "Big")
    t.eq(out[2].label, "Big again", "the same quest's stops stay in their order")
    t.eq(out[3].label, "Small")
    t.eq(out[4].label, "Near, unknown", "not known: after the known ones, in planned order")
    t.eq(out[5].label, "Town stop")
end

tests["sort by XP: the word's choice, distance unless xp"] = function(t)
    t.eq(T().SortOf("xp"), "xp")
    t.eq(T().SortOf("distance"), "distance")
    t.eq(T().SortOf(nil), "distance")
    t.eq(T().SortOf("gold"), "distance")
end

-- A2-15 (lead section 660): near steps first, legacy Flow NearFirst.lua.
-- Only the XP order is reweighed; shortest first is travel alone already.
tests["near first: a stop's weight by how far it is, Flow's tuning"] = function(t)
    t.eq(T().NearMul(100), 1, "close: as it is")
    t.eq(T().NearMul(T().NEAR_YARDS), 1)
    t.eq(T().NearMul(T().NEAR_YARDS + T().NEAR_SPAN), 2, "one span beyond: twice")
    t.eq(T().NearMul(5000), T().NEAR_MAX, "never more than the cap")
    t.eq(T().NearMul(nil), 1, "not known: as it is")
end

tests["near first: by XP, a big quest far off waits behind a fair one close by"] = function(t)
    local stops = {
        stop("Far big", 0.5, 0.5 + 2000 / 10000, { quest = 1 }),
        stop("Near fair", 0.5, 0.5 + 100 / 10000, { quest = 2 }),
    }
    local xp = function(id) return ({ [1] = 900, [2] = 400 })[id] end
    local here, size = { map = 1, x = 0.5, y = 0.5 }, { w = 10000, h = 10000 }
    local near = T().SortXp(stops, xp, here, size)
    t.eq(near[1].label, "Near fair", "900 XP at 2000 yd counts as 300; 400 XP at 100 yd as 400")
    local plain = T().SortXp(stops, xp)
    t.eq(plain[1].label, "Far big", "no place known: XP alone")
end

-- A2-16 (lead section 660): the XP of a quest from the game's own reward
-- read first (GetQuestLogRewardXP, a CLIENT NEED), then the player's
-- Questie; never an estimate (section 611).
tests["quest XP: the game's reward first, then Questie, else not known"] = function(t)
    local game = function(id)
        if id == 4 then error("no read") end
        return ({ [1] = 450, [2] = 0 })[id]
    end
    local questie = function(id) return ({ [1] = 999, [2] = 300, [4] = 120 })[id] end
    local xpOf = T().XpFrom(game, questie)
    t.eq(xpOf(1), 450, "the game's answer wins")
    t.eq(xpOf(2), 300, "the game says 0: Questie's")
    t.eq(xpOf(3), nil, "neither knows")
    t.eq(xpOf(4), 120, "a game read that raises: Questie's")
    t.eq(T().XpFrom(nil, nil)(1), nil)
end

tests["quest XP: a stop's line says its XP when known, nothing when not"] = function(t)
    local route = { label = "straight", stops = {
        { label = "Boars", place = { map = 1, x = 0.5, y = 0.5 }, xp = 450 },
        { label = "Herbs", place = { map = 1, x = 0.5, y = 0.5 } },
    } }
    local lines = T().Lines(route, 1)
    t.ok(lines[2]:find(T().XP_PART:format(450), 1, true) ~= nil, lines[2])
    t.ok(lines[3]:find("XP", 1, true) == nil, lines[3])
end

-- Lead section 713 (Lazy's review of f288bcbd): a Settings row's saved place
-- must start with settings. or layout. (Core/Settings.lua), or the row is
-- refused at load. The route word and the store watch use the same place.
tests["route modes: the three saved places are under settings."] = function(t)
    for _, path in ipairs({ T().MODE_PATH, T().SORT_PATH, T().SHOWN_PATH }) do
        t.eq(tostring(path):sub(1, 9), "settings.", tostring(path))
    end
    t.eq(T().MODE_PATH, "settings." .. T().MODE_KEY, "the row's own default place")
    t.eq(T().SORT_PATH, "settings." .. T().SORT_KEY)
    t.eq(T().SHOWN_PATH, "settings." .. T().SHOWN_KEY)
end

return tests
