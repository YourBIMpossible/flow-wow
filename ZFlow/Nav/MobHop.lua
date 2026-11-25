local _, ns = ...
-- Z-Flow: hop from mob group to mob group inside a kill objective's area
-- (lead section 667, parity row A2-25). A kill target has many spawn
-- points; they are gathered into groups, the groups are ordered as a
-- greedy chain nearest first from where you stand, and a rule says when to
-- move on to the next group.
--
-- Compared with Flow Modules/Nav/AreaHop.lua: the group rule (a spot joins
-- the first group whose middle is within GROUP yards, the middle is the
-- running mean, :51-79), the sizes (:33-39) and the move-on rule (you
-- walked out of the group, or stood in it STAY seconds with no fight and
-- nothing looted, :196-200) are Flow's. Here the order is a whole greedy
-- chain from the player (Flow asks for the one nearest group at each tick,
-- :108-119, or the route planner's order, :123-139), and the objective
-- done also moves you on. Not tested in game.
--
-- Spawns are Questie's QueryNPCSingle(npc, "spawns") ({ [area] = { { x, y } } },
-- x and y 0..100), read through Nav/ProfStep.lua's N.ProfSpotsOf.
--
--   MH.Clusters(spots, size[, groupYards]) -> { { map, x, y, n, spots } }
--   MH.Order(groups, here, size) -> groups in visit order, each with .leg
--       (yards from the place before), or nil without a place or size
--   MH.MoveOn(f) -> true, "done" | "left" | "idle", or false
--       f = { done, yardsIn, now, since (entered), busy (last fight or loot) }
--       yardsIn is yards from the player to the NEAREST spot in the group,
--       not to its middle, as Flow H.YardsTo measures (AreaHop.lua:81-88);
--       the arrow caller must measure it the same way.
--   MH.Plan(spawns, zones, here, size) -> ordered groups on here.map
--   Module "mobHop": Plan(npcId) -> ordered groups, or nil and a reason
ns.Nav = ns.Nav or {}
local N = ns.Nav

local MH = {}
N.MobHop = MH

MH.NAME = "mobHop"
MH.GROUP = 60        -- yards: Flow AreaHop.lua:33
MH.INSIDE = 45       -- yards: Flow AreaHop.lua:34
MH.STAY = 20         -- seconds: Flow AreaHop.lua:37
MH.MAX_SPOTS = 600   -- Flow AreaHop.lua:39

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function sizeOk(size)
    return type(size) == "table" and finite(size.w) and finite(size.h) and size.w > 0 and size.h > 0
end

local function yards(ax, ay, bx, by, size)
    local dx, dy = (ax - bx) * size.w, (ay - by) * size.h
    return math.sqrt(dx * dx + dy * dy)
end

function MH.Clusters(spots, size, groupYards)
    local out = {}
    if type(spots) ~= "table" or not sizeOk(size) then return out end
    local reach = MH.GROUP
    if finite(groupYards) then reach = groupYards end
    for i = 1, math.min(#spots, MH.MAX_SPOTS) do
        local p = spots[i]
        if type(p) == "table" and finite(p.x) and finite(p.y) then
            local home
            for _, g in ipairs(out) do
                if yards(p.x, p.y, g.x, g.y, size) <= reach then home = g break end
            end
            if home == nil then
                home = { map = p.map, x = p.x, y = p.y, n = 0, spots = {} }
                out[#out + 1] = home
            end
            local n = home.n
            home.x = (home.x * n + p.x) / (n + 1)
            home.y = (home.y * n + p.y) / (n + 1)
            home.n = n + 1
            home.spots[n + 1] = { x = p.x, y = p.y }
        end
    end
    return out
end

function MH.Order(groups, here, size)
    if type(here) ~= "table" or not finite(here.x) or not finite(here.y) or not sizeOk(size) then return nil end
    local left = {}
    for _, g in ipairs(groups or {}) do left[#left + 1] = g end
    local out = {}
    local x, y = here.x, here.y
    while #left > 0 do
        local bestI, bestD
        for i, g in ipairs(left) do
            local d = yards(x, y, g.x, g.y, size)
            if bestD == nil or d < bestD then bestI, bestD = i, d end
        end
        local g = table.remove(left, bestI)
        g.leg = bestD
        out[#out + 1] = g
        x, y = g.x, g.y
    end
    return out
end

function MH.MoveOn(f)
    if type(f) ~= "table" then return false end
    if f.done == true then return true, "done" end
    if finite(f.yardsIn) and f.yardsIn > MH.INSIDE then return true, "left" end
    if not finite(f.now) or not finite(f.since) then return false end
    local from = f.since
    if finite(f.busy) and f.busy > from then from = f.busy end
    if f.now - from >= MH.STAY then return true, "idle" end
    return false
end

function MH.Plan(spawns, zones, here, size)
    if type(here) ~= "table" or here.map == nil or type(N.ProfSpotsOf) ~= "function" then return nil end
    local spots = N.ProfSpotsOf(zones, spawns, MH.MAX_SPOTS, here.map)
    return MH.Order(MH.Clusters(spots, size), here, size)
end

local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if not ok then return nil end
    return v
end

function MH.Declare(k)
    local api = {}
    local ctx

    function api.Plan(npcId)
        local c = ctx and ctx.client or k.client
        local db = ask(c, "questieModule", "QuestieDB")
        if type(db) ~= "table" or type(db.QueryNPCSingle) ~= "function" then return nil, "no questie" end
        local okS, spawns = pcall(db.QueryNPCSingle, npcId, "spawns")
        if not okS or type(spawns) ~= "table" then return nil, "no spawns" end
        local here = ask(c, "position")
        if type(here) ~= "table" then return nil, "no position" end
        local size = ask(c, "mapSize", here.map)
        if not sizeOk(size) then return nil, "no map size" end
        local out = MH.Plan(spawns, ask(c, "questieModule", "ZoneDB"), here, size)
        if out == nil then return nil, "no plan" end
        return out
    end

    k:Module({
        name = MH.NAME,
        needs = { "client" },
        provides = { Plan = function(npcId) return api.Plan(npcId) end },
        start = function(c) ctx = c end,
        stop = function() ctx = nil end,
    })

    return api
end

ns.mobHop = MH.Declare(ns)
