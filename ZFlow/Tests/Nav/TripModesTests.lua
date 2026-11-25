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

return tests
