local _, ns = ...
-- The arrow's step hops from mob group to mob group (FLOW-PARITY A2-25, the
-- arrow hook's logic; lead section 674), after legacy Flow's
-- Modules/Nav/AreaHop.lua (H.Tick, :185-230): while the step is a kill
-- objective, once the player first reaches one of its mob groups, the
-- arrow points at the group being worked; when that group is worked (the
-- player walked out of it, or stood in it Nav/MobHop.lua MH.STAY seconds
-- with no fight and nothing looted) it points at the next group not yet
-- worked, in Nav/MobHop.lua's chain order. Until the first group is
-- reached, and once every group is worked, the arrow goes the usual way.
--
-- The groups are Nav/MobHop.lua's (module "mobHop", Plan(npcId)), from the
-- player's Questie spawns. The mob is Questie's: the quest's ObjectiveData[i]
-- of Type "monster" (objective i of the log is ObjectiveData[i], as
-- Nav/QuestRead.lua reads it). LOOK ONLY: nothing is targeted or cast.
--
-- Not ported from Flow: the resting of a worked group (it counts again after
-- a few minutes) and the range limit; open on the A2-25 row (lead section
-- 674). The arrow's line "Next group: N yd" is a MUSE NEED: the step
-- carries hop = { n, of, yards } for it.
--
-- Pure:
--   HS.NpcOf(quest, i) -> the mob id of a kill objective, or nil
--   HS.Next(state, count, f) -> the group to point at (1..count), or nil
--     state: kept between calls ({} to start); f = { inside = the group the
--     player stands in or nil, now, busy (last fight or loot), done }
--   HS.Point(step, groups, n, yards) -> a copy of step pointed at group n
-- Module "mobHopStep": Refine(step) -> the step pointed at its group, or
--   the step itself. The arrow's hook (UI/Arrow.lua, the lead's) calls it.
-- Not tested in game.
ns.Nav = ns.Nav or {}
local N = ns.Nav
local HS = {}
N.MobHopStep = HS

HS.NAME = "mobHopStep"
HS.BUSY_EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "LOOT_OPENED" }

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function HS.NpcOf(quest, i)
    if type(quest) ~= "table" or type(quest.ObjectiveData) ~= "table" or type(i) ~= "number" then return nil end
    local o = quest.ObjectiveData[i]
    if type(o) ~= "table" or o.Type ~= "monster" or type(o.Id) ~= "number" then return nil end
    return o.Id
end

local function nextFree(state, count)
    for i = 1, count do
        if not state.worked[i] then return i end
    end
    return nil
end

function HS.Next(state, count, f)
    if type(state) ~= "table" or type(f) ~= "table" or not finite(count) or count < 1 then return nil end
    if f.done == true then return nil end
    if not state.started then
        if f.inside == nil then return nil end
        state.started, state.worked = true, {}
        state.at, state.entered, state.since = f.inside, true, f.now
        return state.at
    end
    if state.at == nil then return nil end
    if f.inside ~= nil and f.inside == state.at then
        if not state.entered then state.entered, state.since = true, f.now end
        local MH = N.MobHop
        if MH and MH.MoveOn({ now = f.now, since = state.since, busy = f.busy }) then
            state.worked[state.at] = true
            state.at, state.entered, state.since = nextFree(state, count), false, nil
        end
        return state.at
    end
    if f.inside ~= nil then
        if state.entered then state.worked[state.at] = true end
        state.at, state.entered, state.since = f.inside, true, f.now
        return state.at
    end
    if state.entered then
        state.worked[state.at] = true
        state.at, state.entered, state.since = nextFree(state, count), false, nil
    end
    return state.at
end

function HS.Point(step, groups, n, yards)
    if type(step) ~= "table" or type(groups) ~= "table" or type(groups[n]) ~= "table" then return step end
    local g = groups[n]
    local out = {}
    for key, v in pairs(step) do out[key] = v end
    out.place = { map = g.map, x = g.x, y = g.y }
    out.hop = { n = n, of = #groups, yards = yards }
    return out
end

local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if ok then return v end
    return nil
end

function HS.Declare(k)
    local api = {}
    local ctx, key, groups, state, busy
    local cancels = {}

    local function client() return ctx and ctx.client or k.client end

    -- The groups of this step's mob, planned once per step.
    local function groupsOf(step)
        local want = tostring(step.quest) .. ":" .. tostring(step.objective)
        if want == key then return groups end
        key, groups, state = want, nil, {}
        local c = client()
        local db = ask(c, "questieModule", "QuestieDB")
        if type(db) ~= "table" or type(db.GetQuest) ~= "function" then return nil end
        local okQ, quest = pcall(db.GetQuest, step.quest)
        local npc
        if okQ then npc = HS.NpcOf(quest, step.objective) end
        if not npc then return nil end
        local hop = k.use and k.use("mobHop")
        if type(hop) ~= "table" or type(hop.Plan) ~= "function" then return nil end
        local okP, planned = pcall(hop.Plan, npc)
        if okP and type(planned) == "table" and #planned > 0 then groups = planned end
        return groups
    end

    function api.Refine(step)
        if type(step) ~= "table" or step.quest == nil or type(step.objective) ~= "number" or step.turnIn then
            return step
        end
        local list = groupsOf(step)
        if not list then return step end
        local c = client()
        local here = ask(c, "position")
        if type(here) ~= "table" then return step end
        local size = ask(c, "mapSize", here.map)
        if type(size) ~= "table" or not finite(size.w) or not finite(size.h) then
            return step
        end
        local inside, yardsTo = nil, {}
        local MH = N.MobHop
        for i, g in ipairs(list) do
            local dx, dy = (g.x - here.x) * size.w, (g.y - here.y) * size.h
            yardsTo[i] = math.sqrt(dx * dx + dy * dy)
            if inside == nil and g.map == here.map and MH and yardsTo[i] <= MH.INSIDE then inside = i end
        end
        local n = HS.Next(state, #list, { inside = inside, now = ask(c, "now"), busy = busy, done = step.done })
        if not n then return step end
        return HS.Point(step, list, n, yardsTo[n])
    end

    k:Module({
        name = HS.NAME,
        needs = { "client" },
        provides = { Refine = function(step) return api.Refine(step) end },
        start = function(c)
            ctx = c
            if type(c.client.listen) == "function" then
                for _, event in ipairs(HS.BUSY_EVENTS) do
                    local okL, cancel = pcall(c.client.listen, event, function() busy = ask(client(), "now") end)
                    if okL and type(cancel) == "function" then cancels[#cancels + 1] = cancel end
                end
            end
        end,
        stop = function()
            for _, cancel in ipairs(cancels) do pcall(cancel) end
            cancels, ctx, key, groups, state, busy = {}, nil, nil, nil, nil, nil
        end,
    })
    return api
end

ns.mobHopStep = HS.Declare(ns)
