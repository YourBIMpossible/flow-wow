local _, ns = ...
-- R-09 (section 835): the other route steps in the area, for the arrow's
-- hover once the player has arrived. Data only: it draws, saves and prints
-- nothing; UI/Arrow.lua shows the lines.
--
-- Ported from Flow (b657e6e5 Modules/Nav/Nav.lua:4385-4405): on arrival the
-- hover lists every route goal other than the current one for which
-- N:InArea holds (:4438-4445): an area goal with a point on the player's
-- map within AREA = 45 yards. Each quest objective is its own goal there,
-- so the current quest's other objectives show too; the same holds here,
-- since TripRoute makes one stop per objective.
--
-- An area step is what Nav/TripRoute.lua itself treats as a quest objective
-- stop (TripRoute.lua:237): it has an objective, is not a hand-in (turnIn)
-- and has no kind (pick-ups, sell, repair, hearth and the like all carry a
-- kind). There is no separate area flag on a stop.
--
--   AH.Lines(steps, current, here, size) -> { header, lines } or nil (pure)
--     steps    the route's stops: { label, detail, quest, objective, turnIn,
--              kind, place = { map, x, y }, area = { { map, x, y }, ... } }
--     current  the current stop (left out, by identity or quest+objective)
--     here     { map, x, y }, shares 0..1 of the map
--     size     { w, h }, the map's size in yards
--   AH.Declare(k) -> api   api.Lines() reads the route and the player
-- Not tested in game.

local N = ns.Nav
local AH = {}
N.AlsoHere = AH

AH.NAME = "alsoHere"
AH.AREA = 45        -- Flow's AREA (Modules/Nav/Nav.lua:4438)
AH.MAX = 6          -- more would crowd the hover
AH.HEADER = "Here as well"
AH.MORE = "and %d more"

local function finite(v)
    return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function isArea(s)
    return type(s) == "table" and s.objective ~= nil and s.turnIn ~= true and s.kind == nil
end

local function isCurrent(s, current)
    if s == current then return true end
    if type(current) ~= "table" or current.objective == nil then return false end
    return s.quest == current.quest and s.objective == current.objective
end

local function within(p, here, size)
    if type(p) ~= "table" or p.map ~= here.map then return false end
    if type(p.x) ~= "number" or type(p.y) ~= "number" then return false end
    if p.x ~= p.x or p.y ~= p.y then return false end
    local dx, dy = (p.x - here.x) * size.w, (p.y - here.y) * size.h
    return dx * dx + dy * dy <= AH.AREA * AH.AREA
end

-- Flow checks every point of the goal (:4441); a stop has its place and
-- may have an area of more points.
local function near(s, here, size)
    if within(s.place, here, size) then return true end
    if type(s.area) == "table" then
        for _, p in ipairs(s.area) do
            if within(p, here, size) then return true end
        end
    end
    return false
end

local function lineOf(s)
    local text = tostring(s.label or "?")
    if s.detail ~= nil and s.detail ~= "" then text = text .. " - " .. tostring(s.detail) end
    return text
end

function AH.Lines(steps, current, here, size)
    if type(steps) ~= "table" or type(here) ~= "table" or type(size) ~= "table" then return nil end
    if here.map == nil or not finite(here.x) or not finite(here.y) then return nil end
    if not finite(size.w) or not finite(size.h) or size.w <= 0 or size.h <= 0 then return nil end
    local lines, extra = {}, 0
    for _, s in ipairs(steps) do
        if isArea(s) and not isCurrent(s, current) and near(s, here, size) then
            if #lines < AH.MAX then
                lines[#lines + 1] = lineOf(s)
            else
                extra = extra + 1
            end
        end
    end
    if #lines == 0 then return nil end
    if extra > 0 then lines[#lines + 1] = AH.MORE:format(extra) end
    return { header = AH.HEADER, lines = lines }
end

local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if not ok then return nil end
    return v
end

function AH.Declare(k)
    local api = {}
    local ctx

    local function client()
        if ctx and ctx.client then return ctx.client end
        return k.client
    end

    -- The player's spot and the map's size, read as Trip.lua's hereNow and
    -- sizeOf do (client.position, client.mapSize).
    local function hereNow()
        local c = client()
        local pos = ask(c, "position")
        if type(pos) ~= "table" or pos.map == nil then return nil, nil end
        local size = ask(c, "mapSize", pos.map)
        if type(size) ~= "table" then return nil, nil end
        return { map = pos.map, x = pos.x, y = pos.y }, { w = size.w, h = size.h }
    end

    local function lines()
        local r = k.use and k.use("tripRoute")
        if type(r) ~= "table" or type(r.Current) ~= "function" then return nil end
        local ok, cur = pcall(r.Current)
        if not ok or type(cur) ~= "table" or type(cur.stops) ~= "table" then return nil end
        local here, size = hereNow()
        if here == nil then return nil end
        return AH.Lines(cur.stops, cur.stops[1], here, size)
    end

    function api.Lines()
        local ok, v = pcall(lines)
        if not ok then return nil end
        return v
    end

    k:Module({
        name = AH.NAME,
        needs = { "client", "tripRoute" },
        provides = { Lines = api.Lines },
        start = function(c) ctx = c end,
        stop = function() ctx = nil end,
    })
    return api
end

-- The addon's own: declared when this file loads. Look only.
ns.alsoHere = AH.Declare(ns)
