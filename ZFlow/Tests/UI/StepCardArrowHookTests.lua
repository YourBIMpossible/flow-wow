-- A1-13 lead hook: M.ArrowDrawer(route, card), what a left click on the
-- quest arrow opens. Made-up stops; fakes for the route and the card. Not
-- seen in game.
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

local function fakeRoute(stops)
    return { Current = function() return stops end }
end

tests["ArrowDrawer: the quest arrow opens the card on the first stop still to walk"] = function(t)
    local card = fakeCard()
    local first, second = { label = "Hand in" }, { label = "Pick up" }
    local drawer = M.ArrowDrawer(fakeRoute({ first, second }), card)
    t.eq(drawer("quest"), true)
    t.eq(#card.calls, 1)
    t.eq(card.calls[1].step, first)
    t.eq(card.calls[1].facts, nil, "no distance or place made up")
    t.eq(card.calls[1].anchor, nil)
end

tests["ArrowDrawer: another arrow's left click opens nothing"] = function(t)
    local card = fakeCard()
    local drawer = M.ArrowDrawer(fakeRoute({ { label = "Go" } }), card)
    t.eq(drawer("prof"), false)
    t.eq(#card.calls, 0)
end

tests["ArrowDrawer: no route, or no stop to walk, opens nothing"] = function(t)
    local card = fakeCard()
    t.eq(M.ArrowDrawer(fakeRoute(nil), card)("quest"), false)
    t.eq(M.ArrowDrawer(fakeRoute({}), card)("quest"), false)
    t.eq(M.ArrowDrawer(nil, card)("quest"), false)
    t.eq(#card.calls, 0)
end

tests["ArrowDrawer: no card opens nothing and does not raise"] = function(t)
    t.eq(M.ArrowDrawer(fakeRoute({ { label = "Go" } }), nil)("quest"), false)
    t.eq(M.ArrowDrawer(fakeRoute({ { label = "Go" } }), {})("quest"), false)
end

return tests
