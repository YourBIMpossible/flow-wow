-- Activities: whose step each route step is, and which lane it sits in.
--
-- The route has two lanes today: the quest route (the main arrow) and, when
-- the faint profession arrow is on, the profession steps' own route. An
-- `activity` says which steps are its own (`owns`) and whether it has a lane
-- of its own right now (`exists`); a step goes to the first activity, lowest
-- `order`, that has a lane and owns it. "quest" owns everything no one else
-- claims, so no step is ever left without a lane.
--
--   ns:Register("activity", key, { order, label, owns = fn(goal, ctx),
--       exists = fn(ctx), options = fn(travel) })
--
-- Two fields on a step (set in N:Collect, never by a step's source):
--   goal.owner     whose step it is by definition, lane or no lane
--   goal.activity  the lane it sits in: its owner's when that lane has steps
--                  on the route, else the lane it fell through to
--
-- Everything here is pure: it decides from the step, the definitions and
-- `ctx` alone, so the self-tests run it on made-up steps.

local _, ns = ...

local A = {}
ns.activities = A

-- Every activity, lowest `order` first (the same order for the same
-- registrations: ties go by key). Each entry: { key, def }.
function A.Defs()
    local defs = {}
    for key, def in ns:Each("activity") do defs[#defs + 1] = { key = key, def = def } end
    table.sort(defs, function(a, b)
        local oa, ob = a.def.order or 0, b.def.order or 0
        if oa ~= ob then return oa < ob end
        return tostring(a.key) < tostring(b.key)
    end)
    return defs
end

-- Has this activity a lane of its own now? `ctx.exists[key]`, when the caller
-- has already decided it, wins over the definition's own `exists(ctx)`; no
-- `exists` at all means it always has one.
local function laneOf(entry, ctx)
    local decided = ctx and ctx.exists and ctx.exists[entry.key]
    if decided ~= nil then return decided and true or false end
    local fn = entry.def.exists
    if fn == nil then return true end
    return fn(ctx) ~= false
end

function A.Exists(key, defs, ctx)
    for _, entry in ipairs(defs) do
        if entry.key == key then return laneOf(entry, ctx) end
    end
    return false
end

-- The catch-all: the activity asked last. nil with nothing registered.
function A.CatchAll(defs)
    local last = defs[#defs]
    return last and last.key or nil
end

-- Whose step this is by definition: the first activity that owns it, whether
-- or not that activity has a lane now. nil when no one claims it.
function A.Owner(goal, defs, ctx)
    for _, entry in ipairs(defs) do
        local owns = entry.def.owns
        if owns and owns(goal, ctx) then return entry.key end
    end
    return nil
end

-- The lane this step goes to: the first activity that has a lane and owns
-- it. A step of an activity without a lane falls through to the next owner.
function A.Of(goal, defs, ctx)
    for _, entry in ipairs(defs) do
        local owns = entry.def.owns
        if owns and laneOf(entry, ctx) and owns(goal, ctx) then return entry.key end
    end
    return nil
end

-- The steps by lane, { [key] = { goals } }, in one pass, each lane in the
-- list's own order. Whether a lane exists is asked once, not per step. A
-- step no one claims is in no lane (with "quest" registered there is none).
function A.Split(list, defs, ctx)
    local live = {}
    for _, entry in ipairs(defs) do
        if entry.def.owns and laneOf(entry, ctx) then live[#live + 1] = entry end
    end
    local lanes = {}
    for _, goal in ipairs(list) do
        for _, entry in ipairs(live) do
            if entry.def.owns(goal, ctx) then
                local lane = lanes[entry.key]
                if not lane then lane = {} lanes[entry.key] = lane end
                lane[#lane + 1] = goal
                break
            end
        end
    end
    return lanes
end

-- goal.owner on every step of `list`. Returns the list.
function A.StampOwners(list, defs, ctx)
    for _, goal in ipairs(list) do goal.owner = A.Owner(goal, defs, ctx) end
    return list
end

-- goal.activity, once the lanes are final (after "no quest step left" has
-- been decided): a routed step gets the lane it is in; a step that is off the
-- route (`others`: lists of blocked, hidden and "along the way" steps) gets
-- its owner's lane when that lane has steps on the route, else the catch-all,
-- so a step never names a lane that isn't there.
function A.StampLanes(lanes, others, defs, ctx)
    for key, goals in pairs(lanes) do
        for _, goal in ipairs(goals) do
            if goal.owner == nil then goal.owner = A.Owner(goal, defs, ctx) end
            goal.activity = key
        end
    end
    local catchAll = A.CatchAll(defs)
    for _, list in ipairs(others or {}) do
        for _, goal in ipairs(list) do
            if goal.owner == nil then goal.owner = A.Owner(goal, defs, ctx) end
            local lane = goal.owner and lanes[goal.owner]
            goal.activity = (lane and #lane > 0) and goal.owner or catchAll
        end
    end
end

-------------------------------------------------------------------------------
-- The two activities, as the route splits them today.
-------------------------------------------------------------------------------

-- Quests: every step no other activity claims. Asked last.
ns:Register("activity", "quest", {
    order = 100,
    label = "Quests",
    owns = function() return true end,
    options = function() return ns.nav:Options() end,
})

-- Professions: training and skill-up steps (N.IsProfessionStop). Their own
-- lane only while the faint profession arrow is on and no custom route is in
-- force (a custom route that is waiting, `idle`, isn't): the same test the
-- split has always made. `exists` reads the custom route's state, which the
-- custom route's own filter changes during a collect, so N:Collect asks it at
-- the split, not before.
ns:Register("activity", "professions", {
    order = 50,
    label = "Professions",
    owns = function(goal) return ns.nav.IsProfessionStop(goal) end,
    exists = function()
        local N, F = ns.nav, ns.focus
        return (N:ProfPointerOn() and not (F and F.Active() and not F.idle)) and true or false
    end,
    options = function(travel) return travel end,
})
