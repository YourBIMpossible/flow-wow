local _, ns = ...

-------------------------------------------------------------------------------
-- Near first: the route finishes what's around you before it sends you far.
--
-- The planner minimises sum(distance x weight). On its own a step 2,000 yd
-- away and one 50 yd away cost the same per yard, so a tight cluster of kills
-- next to you can be split up by one far step, or by an item drop whose mobs
-- are spread over the zone. Each time the route is planned, this scales a
-- step's weight by how far it is from where you stand now:
--   * up to 300 yd away: unchanged
--   * beyond that: +1x per 700 yd more, at most 3x
--   * item-drop steps (kind "collect") not within 150 yd: another
--     1.5x. They are still planned (their quest can't be turned in without
--     them), just after the kills near you.
--   * milestones (class training, your mount) are left alone.
--   * not on the "Shortest" route (or the completionist one): that's
--     already distance only, and should stay the shortest.
-- The planner re-plans as you move, so "near" always means near you. The
-- steps get their own weights back after each plan (their weight is set once
-- per collect, by the step itself and the route objective in XpValue.lua).
--   /flow nearfirst on|off     (on by default)
-------------------------------------------------------------------------------

local P = ns.planner
local F = {}
ns.nearFirst = F

local NEAR, SPAN, MAX_MUL = 300, 700, 3
local DROP_MUL, DROP_NEAR = 1.5, 150

function F.On() return not (ns.db and ns.db.nearFirst == false) end
-- "Shortest" (the default, and the completionist route, which plans by
-- distance) asks for the shortest path: near-first leaves that alone, and
-- says so (F.Note, /flow nearfirst).
function F.Applies(objective)
    if not F.On() then return false end
    if objective == nil then
        local X = ns.xpValue
        objective = X and X.Objective and (X:Objective()) or "distance"
    end
    return objective ~= "distance"
end

-- How many times heavier a step `d` yards away (nil: not on your continent,
-- or no spot) counts.
function F.Multiplier(goal, d)
    if goal.milestone then return 1 end
    local m = 1
    if d and d > NEAR then m = math.min(MAX_MUL, 1 + (d - NEAR) / SPAN) end
    if goal.kind == "collect" and not (d and d <= DROP_NEAR) then m = m * DROP_MUL end
    return m
end

-- Yards from you to the step's nearest spot on your continent.
function F.Nearest(p, goal)
    local best
    for _, pt in ipairs(goal.points or {}) do
        if pt.wx and pt.cont == p.cont then
            local dx, dy = pt.wx - p.wx, pt.wy - p.wy
            local d = math.sqrt(dx * dx + dy * dy)
            if not best or d < best then best = d end
        end
    end
    return best
end

local plan = P.Plan
function P.Plan(self, p, goals, opts)
    if not (p and p.wx and p.wy and goals and F.Applies()) then return plan(self, p, goals, opts) end
    local saved = {}
    for _, g in ipairs(goals) do
        local m = F.Multiplier(g, F.Nearest(p, g))
        if m ~= 1 then
            saved[g] = g.weight or false
            g.weight = (g.weight or 1) * m
        end
    end
    local ok, result = pcall(plan, self, p, goals, opts)
    for g, w in pairs(saved) do g.weight = w or nil end
    if not ok then error(result, 0) end
    return result
end

-- Why near-first isn't changing your route right now, or nil when it is
-- (on, on a weighted objective). Shortest already plans by travel alone.
function F.Note(objective, on)
    if on == nil then on = F.On() end
    if not on then return nil end
    if objective == nil then
        local X = ns.xpValue
        objective = X and X.Objective and (X:Objective()) or "distance"
    end
    if objective == "distance" then
        return "it only reweighs Most XP and other weighted routes; Shortest (your route now) already goes by travel alone"
    end
    return nil
end

ns.commands.nearfirst = function(arg)
    arg = (arg or ""):lower()
    local set = arg == "on" or arg == "off"
    if set then ns.db.nearFirst = (arg == "on") end
    local note = F.Note()
    ns:Print("route finishes steps near you first: " .. (F.On() and "on" or "off") .. (note and (" - " .. note) or "") .. " (/flow nearfirst on|off)")
    if set and ns.nav and ns.nav.Collect then ns.nav:Collect() end
end
