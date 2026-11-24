local _, ns = ...
-- Z-Flow: resting gather spots (parity row A1-21, lead section 481). Of the
-- nodes you gathered yourself (Nav/Nodes.lua, read, not changed):
--   looted  a loot window opened within NR.LOOT_YARDS of a kept node: that
--           node rests for NR.REST seconds (it is growing back).
--   empty   standing within NR.EMPTY_YARDS of the nearest node that is not
--           resting for NR.EMPTY_SECONDS without looting: nothing is there,
--           it rests the same.
-- Next() is the nearest kept node that is not resting. Rests are for this
-- session only, as Flow's: nothing is saved.
-- Not here yet: a caller. The arrow and `nodes go` still take Nodes'
-- nearest; using Next() there is a later hook.
-- Compared with Flow Modules/Nav/Nav.lua SPOT_REST, cleared, N:NearestSpot,
-- N.ClearSpotNear (LOOT_OPENED, 12 yd) and N.SpotEmpty / watchSpot (15 yd,
-- 4 s): the same numbers. Flow works on Questie's spawn spots of the
-- current step and stops watching in combat; here it is your own kept
-- nodes, and combat is not looked at.
-- LOOK ONLY: nothing is looted, cast or moved. Not tested in game.
--
-- Pure:
--   NR.Key(node) -> "x:y:id-or-name"
--   NR.Resting(rests, key, now) -> true while it rests
--   NR.Empty(d, since, now) -> true once the spot turned out empty
--   NR.Next(list, rests, now) -> the first { node, d } not resting, or nil
-- Module "nodeRest" provides Next(), Resting(node).
ns.Nav = ns.Nav or {}
local N = ns.Nav
local NR = {}
N.NodeRest = NR

NR.NAME = "nodeRest"
NR.REST = 240          -- Flow SPOT_REST
NR.LOOT_YARDS = 12     -- Flow N.ClearSpotNear
NR.EMPTY_YARDS = 15    -- Flow N.EMPTY_YARDS
NR.EMPTY_SECONDS = 4   -- Flow N.EMPTY_SECONDS
NR.EVERY = 1
NR.LOOK = 5            -- nodes asked of Nav/Nodes.lua per look
NR.EVENT = "LOOT_OPENED"

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function NR.Key(node)
    if type(node) ~= "table" then return nil end
    return ("%s:%s:%s"):format(tostring(node.x), tostring(node.y), tostring(node.id or node.name))
end

function NR.Resting(rests, key, now)
    local at = type(rests) == "table" and key ~= nil and rests[key] or nil
    return finite(at) and finite(now) and now - at < NR.REST or false
end

function NR.Empty(d, since, now)
    return finite(d) and d < NR.EMPTY_YARDS and finite(since) and finite(now) and now - since >= NR.EMPTY_SECONDS or false
end

function NR.Next(list, rests, now)
    for _, r in ipairs(type(list) == "table" and list or {}) do
        if type(r) == "table" and not NR.Resting(rests, NR.Key(r.node), now) then return r end
    end
    return nil
end

function NR.Declare(k)
    local api = {}
    local ctx
    local rests = {}
    local atKey, atSince

    local function now()
        local c = ctx and ctx.client
        if type(c) ~= "table" or type(c.now) ~= "function" then return nil end
        local ok, v = pcall(c.now)
        if ok then return v end
        return nil
    end

    -- Nodes' nearest, with known distances only.
    local function nearest()
        local ok, mod = pcall(ctx.use, N.Nodes and N.Nodes.NAME or "nodes")
        if not ok or type(mod) ~= "table" or type(mod.Nearest) ~= "function" then return nil end
        local okN, list, known = pcall(mod.Nearest, NR.LOOK)
        if not okN or type(list) ~= "table" or not known then return nil end
        return list
    end

    local function rest(node, t)
        local key = NR.Key(node)
        if key and finite(t) then rests[key] = t end
    end

    local function looted()
        local list, t = nearest(), now()
        local r = list and NR.Next(list, rests, t)
        if r and finite(r.d) and r.d < NR.LOOT_YARDS then rest(r.node, t) end
        atKey, atSince = nil, nil
    end

    local function tick()
        local list, t = nearest(), now()
        local r = list and NR.Next(list, rests, t)
        if not (r and finite(r.d) and r.d < NR.EMPTY_YARDS) then atKey, atSince = nil, nil return end
        local key = NR.Key(r.node)
        if atKey ~= key then atKey, atSince = key, t return end
        if NR.Empty(r.d, atSince, t) then
            rest(r.node, t)
            atKey, atSince = nil, nil
        end
    end

    function api.Next()
        if not ctx then return nil end
        local list = nearest()
        return list and NR.Next(list, rests, now()) or nil
    end

    function api.Resting(node)
        return NR.Resting(rests, NR.Key(node), now())
    end

    k:Module({
        name = NR.NAME,
        needs = { "client", "bus" },
        provides = {
            Next = function() return api.Next() end,
            Resting = function(node) return api.Resting(node) end,
        },
        ticks = { { every = NR.EVERY, when = "always", run = function() pcall(tick) end } },
        start = function(c)
            ctx = c
            c.bus:on(NR.NAME, NR.EVENT, function() pcall(looted) end)
        end,
        stop = function() ctx = nil; rests = {}; atKey, atSince = nil, nil end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.nodeRest = NR.Declare(ns)
