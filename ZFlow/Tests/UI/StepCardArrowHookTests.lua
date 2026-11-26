-- A1-13 lead hook: M.ArrowDrawer(route, card), what a left click on the
-- quest arrow opens. Fakes return TripRoute.View's shape
-- ({ kind, label, stops = {...}, left = {...} }). Made-up stops. Not seen
-- in game.
local _, ns = ...
local tests = {}

local M = ns.StepCard

local function fakeCard()
    local card = { calls = {} }
    function card.Toggle(step, facts, anchor)
        card.calls[#card.calls + 1] = { step = step, facts = facts, anchor = anchor }
    end
    return card
end

local function fakeRoute(view)
    return { View = function() return view end, Current = function() return nil end }
end

local function stop(label, extra)
    local s = { label = label, quest = 1, objective = 1, place = { map = 1, x = 0.5, y = 0.5 } }
    for key, v in pairs(extra or {}) do s[key] = v end
    return s
end

tests["ArrowDrawer: the quest arrow opens the card on the route's first stop, index 1"] = function(t)
    local card = fakeCard()
    local first, second = stop("Kill boars"), stop("Hand in", { turnIn = true })
    local drawer = M.ArrowDrawer(fakeRoute({ kind = "quests", stops = { first, second }, left = {} }), card)
    t.eq(drawer("quest"), true)
    t.eq(#card.calls, 1)
    t.eq(card.calls[1].step, first)
    t.eq(card.calls[1].facts.index, 1, "the arrow's step is the next step")
    t.eq(card.calls[1].facts.distance, nil, "no distance made up")
    t.eq(card.calls[1].anchor, nil)
end

tests["ArrowDrawer: a route planned by itself (Current nil, View set) still opens the card"] = function(t)
    local card = fakeCard()
    local first = stop("Pick up")
    local drawer = M.ArrowDrawer(fakeRoute({ kind = "auto", stops = { first }, left = {} }), card)
    t.eq(drawer("quest"), true)
    t.eq(card.calls[1].step, first)
end

tests["ArrowDrawer: a held stop is passed over, as the arrow passes over it"] = function(t)
    local card = fakeCard()
    local held, open = stop("Held", { held = "needs level 10" }), stop("Walk here")
    local drawer = M.ArrowDrawer(fakeRoute({ stops = { held, open }, left = {} }), card)
    t.eq(drawer("quest"), true)
    t.eq(card.calls[1].step, open)
end

tests["ArrowDrawer: another arrow's left click opens nothing"] = function(t)
    local card = fakeCard()
    local drawer = M.ArrowDrawer(fakeRoute({ stops = { stop("Go") }, left = {} }), card)
    t.eq(drawer("prof"), false)
    t.eq(#card.calls, 0)
end

tests["ArrowDrawer: no route, no stops, or only held stops open nothing"] = function(t)
    local card = fakeCard()
    t.eq(M.ArrowDrawer(fakeRoute(nil), card)("quest"), false)
    t.eq(M.ArrowDrawer(fakeRoute({ stops = {}, left = {} }), card)("quest"), false)
    t.eq(M.ArrowDrawer(fakeRoute({ stops = { stop("H", { held = "x" }) }, left = {} }), card)("quest"), false)
    t.eq(M.ArrowDrawer(nil, card)("quest"), false)
    t.eq(#card.calls, 0)
end

tests["ArrowDrawer: no card, or a View that raises, opens nothing and does not raise"] = function(t)
    local view = { stops = { stop("Go") }, left = {} }
    t.eq(M.ArrowDrawer(fakeRoute(view), nil)("quest"), false)
    t.eq(M.ArrowDrawer(fakeRoute(view), {})("quest"), false)
    t.eq(M.ArrowDrawer({ View = function() error("boom") end }, fakeCard())("quest"), false)
end

return tests
