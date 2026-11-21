-- Navigation arrow: points at your next goal (a quest mob, an item source, a
-- turn-in NPC...), with a short sentence and the distance. Left-click for
-- details, right-click to switch to the next goal, Ctrl-drag to move.
--
-- Paths: WoW gives addons no map of walkable ground, so Flow learns it.
-- As you travel, your route is recorded as a network of trail points per
-- continent. When both you and your goal are near known trails, the arrow
-- follows the shortest known trail (A* search) instead of a straight line,
-- so it leads you around hills, rivers and walls the way you've actually
-- walked before. In new places it points straight until it has learned more.
--
-- Goals come from registered providers:
--   ns:Register("navGoal", key, { collect = function() return { goal, ... } end })
--   goal = { key, title, text, details = { lines }, weight = 1,
--            points = { { map = uiMapID, x = 0-1, y = 0-1 }, ... } }

local _, ns = ...
local A = ns.api
local N = {}
ns.nav = N

local SPACING = 15     -- yards between recorded trail points
local SNAP = 8         -- reuse an existing trail point this close
local MAX_EDGE = 45    -- longer jumps are teleports/hearths, not walking
local MAX_NODES = 6000 -- per continent
local CELL = 50        -- spatial grid size (yards)
local ARRIVED = 12     -- yards

local floor, sqrt, atan2 = math.floor, math.sqrt, math.atan2

local function dist(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return sqrt(dx * dx + dy * dy)
end

-------------------------------------------------------------------------------
-- Positions
-------------------------------------------------------------------------------

function N:PlayerPos()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local map = C_Map.GetBestMapForUnit("player")
    if not map then return nil end
    local pos = C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    x, y = A.Safe(x), A.Safe(y)
    if not x or not y then return nil end
    local cont, world = C_Map.GetWorldPosFromMapPos(map, pos)
    if not world then return nil end
    local wx, wy = world:GetXY()
    return { map = map, x = x, y = y, cont = cont, wx = wx, wy = wy }
end

-- World position (yards) of a point on a map, as the game works it out.
local function gameToWorld(map, x, y)
    local cont, world = C_Map.GetWorldPosFromMapPos(map, CreateVector2D(x, y))
    if not world then return nil end
    local wx, wy = world:GetXY()
    return cont, wx, wy
end
N._gameToWorld = gameToWorld   -- (tests)

-- A zone map is a flat rectangle of the world: from its corner and its two
-- edges, any point on it is plain arithmetic (no game call, no garbage).
-- Gathering the route turns thousands of spawn spots into world positions,
-- so this matters. Each map is checked against the game on two more points
-- first; a map that doesn't fit keeps asking the game (as before).
local flatMaps = {}
local CHECKS = { { 1, 1 }, { 0.37, 0.71 } }
local function flatMap(map)
    local f = flatMaps[map]
    if f ~= nil then return f end
    f = false
    local c0, ox, oy = gameToWorld(map, 0, 0)
    local c1, ax, ay = gameToWorld(map, 1, 0)
    local c2, bx, by = gameToWorld(map, 0, 1)
    if ox and ax and bx and c0 == c1 and c0 == c2 then
        local t = { cont = c0, ox = ox, oy = oy, ux = ax - ox, uy = ay - oy, vx = bx - ox, vy = by - oy }
        local fits = true
        for _, q in ipairs(CHECKS) do
            local c, wx, wy = gameToWorld(map, q[1], q[2])
            local px, py = ox + q[1] * t.ux + q[2] * t.vx, oy + q[1] * t.uy + q[2] * t.vy
            if not (wx and c == c0 and math.abs(wx - px) < 0.05 and math.abs(wy - py) < 0.05) then fits = false end
        end
        if fits then f = t end
    end
    flatMaps[map] = f
    return f
end

function N:ToWorld(map, x, y)
    -- A spot with no map (an NPC place saved without one): nil, not an error
    -- from the game (it stopped the anvil/forge step finding trainers, 0.35.130).
    map, x, y = tonumber(map), tonumber(x), tonumber(y)
    if not (map and x and y) then return nil end
    local f = flatMap(map)
    if f then return f.cont, f.ox + x * f.ux + y * f.vx, f.oy + x * f.uy + y * f.vy end
    return gameToWorld(map, x, y)
end

-- East/south unit vectors of a map in world space, so world offsets can be
-- turned into a compass bearing without caring how world axes are oriented.
local axes = {}
local function mapAxes(map)
    if not map then return nil end   -- (a spot with no map: no axes, and no nil table key)
    local a = axes[map]
    if a ~= nil then return a or nil end
    local _, ox, oy = N:ToWorld(map, 0, 0)
    local _, ex, ey = N:ToWorld(map, 1, 0)
    local _, sx, sy = N:ToWorld(map, 0, 1)
    if not (ox and ex and sx) then axes[map] = false return nil end
    local el, sl = dist(ex, ey, ox, oy), dist(sx, sy, ox, oy)
    if el == 0 or sl == 0 then axes[map] = false return nil end
    a = { ex = (ex - ox) / el, ey = (ey - oy) / el, sx = (sx - ox) / sl, sy = (sy - oy) / sl }
    axes[map] = a
    return a
end

-- The arrow turns with your character: up = the way you face. (Map-style
-- north-up and "like my minimap" were tried in 0.35.51-0.35.54 and removed:
-- neither turned the way you look.) Add-ons can read your character's
-- facing but not the camera's, so the arrow can't follow the camera as you
-- swing it around your character; it matches your screen whenever the
-- camera is behind you.
function N.ArrowFacing()
    return A.Safe(GetPlayerFacing and GetPlayerFacing())
end
ns:OnLoad(function(saved)
    saved.nav = saved.nav or {}
    saved.nav.arrowTurn, saved.nav.northUp = nil, nil   -- (the removed modes)
end)

-- Bearing (radians clockwise from north) from the player to a world point.

local function bearing(p, wx, wy)
    local a = mapAxes(p.map)
    if not a then return nil end
    local dx, dy = wx - p.wx, wy - p.wy
    local east = dx * a.ex + dy * a.ey
    local south = dx * a.sx + dy * a.sy
    return atan2(east, -south)
end

-- East / south offset in yards from the player to a world point (minimap pin).
function N:Offset(p, wx, wy)
    local a = mapAxes(p.map)
    if not a then return nil end
    local dx, dy = wx - p.wx, wy - p.wy
    return dx * a.ex + dy * a.ey, dx * a.sx + dy * a.sy
end

local COMPASS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
local function compass(b)
    local i = floor(((b % (2 * math.pi)) / (2 * math.pi)) * 8 + 0.5) % 8
    return COMPASS[i + 1]
end

-------------------------------------------------------------------------------
-- Learned trails
-------------------------------------------------------------------------------

local grids = {}  -- runtime spatial index per continent (not saved)

local function graph(cont)
    local all = ns.db.nav.graphs
    local g = all[cont]
    if not g then
        g = { x = {}, y = {}, adj = {} }
        all[cont] = g
    end
    if not grids[cont] then
        -- Nearly full: straight runs are thinned first (N.Thin), so there's room to learn more.
        if #g.x > MAX_NODES * N.THIN_AT then
            local ok, removed = pcall(N.ThinInPlace, g)
            if ok and removed and removed > 0 then
                ns:Log("nav", string.format("trails: thinned %d point(s) on straight runs (continent %s, %d left)", removed, tostring(cont), #g.x))
            end
        end
        local grid = {}
        for i = 1, #g.x do
            local k = floor(g.x[i] / CELL) .. ":" .. floor(g.y[i] / CELL)
            grid[k] = grid[k] or {}
            table.insert(grid[k], i)
        end
        grids[cont] = grid
    end
    return g, grids[cont]
end

local function nearestNode(cont, x, y, radius)
    local g, grid = graph(cont)
    local cx, cy, r = floor(x / CELL), floor(y / CELL), math.ceil(radius / CELL)
    local best, bestD
    for i = cx - r, cx + r do
        for j = cy - r, cy + r do
            for _, n in ipairs(grid[i .. ":" .. j] or {}) do
                local d = dist(x, y, g.x[n], g.y[n])
                if d <= radius and (not bestD or d < bestD) then best, bestD = n, d end
            end
        end
    end
    return best, bestD
end

local function addNode(cont, x, y)
    local g, grid = graph(cont)
    if #g.x >= MAX_NODES then return nil end
    local n = #g.x + 1
    g.x[n], g.y[n] = floor(x * 10) / 10, floor(y * 10) / 10
    local k = floor(x / CELL) .. ":" .. floor(y / CELL)
    grid[k] = grid[k] or {}
    table.insert(grid[k], n)
    return n
end

local function link(g, a, b)
    g.adj[a] = g.adj[a] or {}
    g.adj[b] = g.adj[b] or {}
    for _, v in ipairs(g.adj[a]) do if v == b then return end end
    table.insert(g.adj[a], b)
    table.insert(g.adj[b], a)
end

-------------------------------------------------------------------------------
-- How long each stretch takes, and thinning (0.35.286)
-------------------------------------------------------------------------------
-- "You're capturing where I go and the time, so you could connect the points
-- and collapse them, right?" Flow kept the points and their joins, no time,
-- and never tidied. Now:
--   * each join remembers the quickest you've covered it (seconds). The trail
--     search goes by that, so of two known ways it takes the one you got
--     through faster (a road over a swim, the lift over the long way round),
--     not just the shorter line. A stretch you stood or fought on is not
--     timed (too slow to be travel), nor one too fast to be on foot or a mount.
--   * when a continent's network is nearly full, points in the middle of a
--     straight run are taken out and their neighbours joined, so the same
--     ground takes fewer points and there's room to learn new places.
N.RUN = 7                 -- yards a second on foot: an untimed stretch counts as this
N.SLOWEST, N.FASTEST = 2, 40   -- yards a second: outside this a time isn't travel
N.COST_MIN, N.COST_MAX = 0.5, 4   -- a timed stretch counts as this share of its length, at least and at most
N.THIN_AT = 0.8           -- thin when a continent is this full
N.THIN_GAP, N.THIN_OFF = 45, 2.5   -- a join after thinning is at most this long; a point this near the line is "on" it

-- Pure: the seconds worth keeping for a stretch of d yards walked in `sec`,
-- or nil when that wasn't travel.
function N.EdgeSeconds(d, sec)
    if type(d) ~= "number" or type(sec) ~= "number" or sec <= 0 or d <= 0 then return nil end
    local speed = d / sec
    if speed < N.SLOWEST or speed > N.FASTEST then return nil end
    return floor(sec * 10 + 0.5) / 10
end
-- Pure: what a stretch costs the search, in yards at running speed: its
-- length when untimed; else the time it took, kept within sensible bounds.
function N.EdgeCost(d, sec)
    if not sec then return d end
    return math.max(d * N.COST_MIN, math.min(d * N.COST_MAX, sec * N.RUN))
end
local function edgeTime(g, a, b)
    if a > b then a, b = b, a end
    return g.t and g.t[a] and g.t[a][b] or nil
end
local function setEdgeTime(g, a, b, sec)
    if a > b then a, b = b, a end
    g.t = g.t or {}
    g.t[a] = g.t[a] or {}
    local old = g.t[a][b]
    if not old or sec < old then g.t[a][b] = sec end
end
N._edgeTime, N._setEdgeTime = edgeTime, setEdgeTime   -- (tests)

-- Pure: a thinned copy of a network ({ x, y, adj, indoor, t }) and how many
-- points went. A point goes when it has exactly two neighbours that aren't
-- joined already, lies on the line between them (within `off` yards), isn't
-- indoors, and the new join is at most `gap` long. Times add up.
function N.Thin(g, gap, off)
    gap, off = gap or N.THIN_GAP, off or N.THIN_OFF
    local count = #g.x
    local adj, times = {}, {}
    for a = 1, count do
        adj[a] = {}
        for _, b in ipairs(g.adj[a] or {}) do adj[a][b] = true end
    end
    for a, row in pairs(g.t or {}) do
        for b, sec in pairs(row) do times[a .. ":" .. b] = sec end
    end
    local function key(a, b) if a > b then a, b = b, a end return a .. ":" .. b end
    local gone, removed = {}, 0
    for b = 1, count do
        if not (g.indoor and g.indoor[b]) then
            local nb = {}
            for k in pairs(adj[b]) do nb[#nb + 1] = k end
            if #nb == 2 then
                local a, c = nb[1], nb[2]
                local ax, ay, cx, cy = g.x[a], g.y[a], g.x[c], g.y[c]
                local len = dist(ax, ay, cx, cy)
                if not adj[a][c] and len <= gap and len > 0 then
                    -- How far b lies from the line a-c.
                    local away = math.abs((cx - ax) * (ay - g.y[b]) - (ax - g.x[b]) * (cy - ay)) / len
                    if away <= off then
                        adj[a][b], adj[c][b], adj[b] = nil, nil, {}
                        adj[a][c], adj[c][a] = true, true
                        local t1, t2 = times[key(a, b)], times[key(b, c)]
                        if t1 and t2 then times[key(a, c)] = t1 + t2 end
                        times[key(a, b)], times[key(b, c)] = nil, nil
                        gone[b] = true
                        removed = removed + 1
                    end
                end
            end
        end
    end
    local out = { x = {}, y = {}, adj = {} }
    local map = {}
    for i = 1, count do
        if not gone[i] then
            local m = #out.x + 1
            out.x[m], out.y[m], map[i] = g.x[i], g.y[i], m
            if g.indoor and g.indoor[i] then out.indoor = out.indoor or {}; out.indoor[m] = true end
        end
    end
    for a = 1, count do
        if not gone[a] then
            local list = {}
            for b in pairs(adj[a]) do list[#list + 1] = map[b] end
            table.sort(list)
            if #list > 0 then out.adj[map[a]] = list end
        end
    end
    for k, sec in pairs(times) do
        local a, b = k:match("^(%d+):(%d+)$")
        a, b = map[tonumber(a)], map[tonumber(b)]
        if a and b then
            if a > b then a, b = b, a end
            out.t = out.t or {}
            out.t[a] = out.t[a] or {}
            out.t[a][b] = sec
        end
    end
    return out, removed
end
-- Thins a saved network where it lies (everything else kept on it stays).
function N.ThinInPlace(g)
    local thin, removed = N.Thin(g)
    if removed > 0 then g.x, g.y, g.adj, g.indoor, g.t = thin.x, thin.y, thin.adj, thin.indoor, thin.t end
    return removed
end

local lastNode, lastCont, lastIndoor
local lastNodeAt   -- when you were at lastNode (for the stretch's time)
local function record(p)
    if (UnitOnTaxi and UnitOnTaxi("player")) or (IsFlying and IsFlying()) then lastNode = nil return end
    local speed = A.Safe(GetUnitSpeed("player")) or 0
    if speed == 0 then return end
    if lastCont ~= p.cont then lastNode, lastCont = nil, p.cont end
    local g = graph(p.cont)
    if lastNode then
        local d = dist(p.wx, p.wy, g.x[lastNode], g.y[lastNode])
        if d < SPACING then return end
        if d > MAX_EDGE then lastNode, lastNodeAt = nil, nil end
    end
    local n = nearestNode(p.cont, p.wx, p.wy, SNAP) or addNode(p.cont, p.wx, p.wy)
    -- Caves and buildings: trail points walked indoors are marked, and the
    -- spot where you went from outdoors to indoors is kept as an entrance.
    local indoor = IsIndoors and IsIndoors() or false
    if n and indoor then g.indoor = g.indoor or {}; g.indoor[n] = true end
    if indoor and lastIndoor == false then N:AddEntrance(p) end
    lastIndoor = indoor
    if n and lastNode and n ~= lastNode then
        link(g, lastNode, n)
        local sec = lastNodeAt and N.EdgeSeconds(dist(g.x[lastNode], g.y[lastNode], g.x[n], g.y[n]), GetTime() - lastNodeAt)
        if sec then setEdgeTime(g, lastNode, n, sec) end
    end
    if n and n ~= lastNode then lastNodeAt = GetTime() end
    lastNode = n or lastNode
end

-------------------------------------------------------------------------------
-- Shortest known trail (A*)
-------------------------------------------------------------------------------

local function heapPush(h, node, f)
    local i = #h + 1
    h[i] = { node, f }
    while i > 1 do
        local parent = floor(i / 2)
        if h[parent][2] <= h[i][2] then break end
        h[parent], h[i] = h[i], h[parent]
        i = parent
    end
end

local function heapPop(h)
    local top = h[1]
    local last = table.remove(h)
    if #h > 0 then
        h[1] = last
        local i = 1
        while true do
            local l, r, s = i * 2, i * 2 + 1, i
            if h[l] and h[l][2] < h[s][2] then s = l end
            if h[r] and h[r][2] < h[s][2] then s = r end
            if s == i then break end
            h[i], h[s] = h[s], h[i]
            i = s
        end
    end
    return top[1]
end

local function astar(cont, s, t)
    local g = graph(cont)
    local tx, ty = g.x[t], g.y[t]
    local open, gScore, came, closed = {}, { [s] = 0 }, {}, {}
    -- (Costs are in yards at running speed: a stretch's length, or the time it
    -- took you. The guess to the end is the straight line at the best a timed
    -- stretch can count, so the search stays exact.)
    heapPush(open, s, dist(g.x[s], g.y[s], tx, ty) * N.COST_MIN)
    local steps = 0
    while #open > 0 do
        steps = steps + 1
        if steps > 20000 then return nil end
        local cur = heapPop(open)
        if cur == t then
            local path, n, length = { t }, t, 0
            while came[n] do
                length = length + dist(g.x[n], g.y[n], g.x[came[n]], g.y[came[n]])
                n = came[n]
                table.insert(path, 1, n)
            end
            return path, length
        end
        if not closed[cur] then
            closed[cur] = true
            for _, nb in ipairs(g.adj[cur] or {}) do
                local ng = gScore[cur] + N.EdgeCost(dist(g.x[cur], g.y[cur], g.x[nb], g.y[nb]), edgeTime(g, cur, nb))
                if not gScore[nb] or ng < gScore[nb] then
                    gScore[nb] = ng
                    came[nb] = cur
                    heapPush(open, nb, ng + dist(g.x[nb], g.y[nb], tx, ty) * N.COST_MIN)
                end
            end
        end
    end
    return nil
end

-------------------------------------------------------------------------------
-- Goals
-------------------------------------------------------------------------------

local goals = {}       -- collected goals
local current          -- chosen goal
local pinnedKey        -- goal chosen with right-click
local route            -- { goalKey, cont, nodes = {...}, idx, length } or nil

local function resolvePoints(goal)
    for _, pt in ipairs(goal.points or {}) do
        if pt.wx == nil and pt.map then
            local cont, wx, wy = N:ToWorld(pt.map, pt.x, pt.y)
            pt.cont, pt.wx, pt.wy = cont, wx, wy
            if not wx then pt.wx = false end
        end
    end
end

-- Nearest point of a goal to the player (same continent only).
local function nearestPoint(goal, p)
    local best, bestD
    for _, pt in ipairs(goal.points or {}) do
        if pt.wx and pt.cont == p.cont then
            local d = dist(p.wx, p.wy, pt.wx, pt.wy)
            if not bestD or d < bestD then best, bestD = pt, d end
        end
    end
    return best, bestD
end

-- The one spot for a step, the same everywhere (the arrow, "Point the arrow
-- here", the step card, tooltips): its route spot when it's on the route
-- (the arrow's own for your next step), else its spawn nearest you, else its
-- first. (Off the route it used to be the first spawn Flow happened to keep,
-- anywhere in the zone.)
function N:Spot(goal, p)
    if not goal then return nil end
    for _, s in ipairs(N.plan or {}) do
        if s.goal == goal or s.goal.key == goal.key then return s.point end
    end
    p = p or self:PlayerPos()
    if p then
        local best = nearestPoint(goal, p)
        if best then return best end
    end
    return goal.points and goal.points[1]
end

function N:Coin(c)
    return ns.Money(c or 0)
end

local timedProviders = {}   -- each step source timed on its own in /flow perf
-- One step source's goals, added to `list`.
local function gatherFrom(key, provider, list)
    local t = timedProviders[key]
    if not t or t.fn ~= provider.collect then
        t = { fn = provider.collect, timed = ns.perf.Wrap("gather: " .. key, provider.collect) }
        timedProviders[key] = t
    end
    local ok, found = pcall(t.timed)
    if ok then
        for _, goal in ipairs(found or {}) do
            goal.provider = key
            resolvePoints(goal)
            list[#list + 1] = goal
        end
    elseif ns.db.rotation.debug then
        ns:Print("nav goal " .. key .. ": " .. tostring(found))
    end
end
N._gatherFrom = gatherFrom  -- (tests)

-- Every source in one go, then planned: what commands use. The routine
-- refresh (collectSoon below) gathers one source per frame instead and
-- hands the list in as `gathered`, so no one frame does all of it.
function N:Collect(gathered)
    local list = gathered
    -- Asked for directly while a spread-out refresh is still gathering: that
    -- refresh would replace this list with older steps when it finishes, so
    -- it goes once more after (N.MarkAgain, below).
    if not gathered and N.MarkAgain then N.MarkAgain() end
    if not list then
        list = {}
        for key, provider in ns:Each("navGoal") do gatherFrom(key, provider, list) end
    end
    -- Only the kinds of step you ticked (the route menu's "Route includes":
    -- current quests, new quests, training, professions...). Steps no kind
    -- claims stay: a dungeon run you prepared, party steps. First of all, so
    -- a step never waits on (or is listed as blocked by) a kind you left out.
    -- (On a custom route, 0.35.377: the quest kinds are all gathered, since the
    -- lines you picked choose among them; the rest go by the custom route's own ticks.)
    local FK = ns.focus
    local customOn = FK and FK.KindsOn and FK.KindsOn()
    list = N.FilterKinds(list, function(kind)
        if customOn and FK.Replaces(kind) then return true end
        return N:Includes(kind)
    end, UnitLevel("player"))
    -- "Only the dungeon run" (Dungeons.lua): just the prepared run's steps. Here
    -- with the ticks, before the blocked steps are set apart, so a blocked
    -- step of another kind isn't listed either.
    if ns.dungeons and ns.dungeons.FilterOnly then list = ns.dungeons:FilterOnly(list) end
    -- A custom route: only the quest lines you picked (Focus.lua).
    if ns.focus and ns.focus.Filter then
        local okF, cut = pcall(ns.focus.Filter, list)
        if okF and type(cut) == "table" then list = cut
        elseif not okF then ns:Log("nav", "custom route: " .. tostring(cut)) end
    end
    -- What steps need first (Needs.lua): after the step that provides it, or
    -- blocked with the reason when nothing on the route does.
    if N.ResolveNeeds then
        local okN, errN = pcall(N.ResolveNeeds, list)
        if not okN then ns:Log("nav", "needs: " .. tostring(errN)) end
    end
    -- Blocked steps stay off the route but are listed (with a lock and the
    -- reason) on the map list and the tracker:
    --   goal.blockedBy = "needs Mining"     set by the goal's provider
    --   goal.cost = copper                  blocked while you have less money
    -- Money-blocked steps are remembered in ns.db.nav.deferred. When your
    -- money reaches the cost (PLAYER_MONEY below) they come back and are
    -- planned like any other step: by distance and weight, so a trainer you're
    -- standing near (say, after a hearth) goes to the top by itself.
    local money = GetMoney and GetMoney() or 0
    local deferred = ns.db.nav.deferred or {}
    ns.db.nav.deferred = deferred
    local present, kept, blockedGoals = {}, {}, {}
    for _, g in ipairs(list) do
        present[g.key] = g
        if g.cost and g.cost > money then
            if not deferred[g.key] then
                ns:Print(string.format("skipping %s for now: it costs %s and you have %s. It comes back on the route once you can pay.",
                    g.title or g.text or g.key, N:Coin(g.cost), N:Coin(money)))
            end
            deferred[g.key] = { text = g.title or g.text, cost = g.cost, since = deferred[g.key] and deferred[g.key].since or time() }
            g.blockedBy = string.format("needs %s (you have %s)", N:Coin(g.cost), N:Coin(money))
            g.blockedShort = "needs " .. N:Coin(g.cost)
            g.blockIcon = "Interface\\MoneyFrame\\UI-GoldIcon"
        elseif deferred[g.key] then
            ns:Print((g.title or g.text or g.key) .. ": you have the money now, back on the route.")
            deferred[g.key] = nil
            g.details = g.details or {}
            table.insert(g.details, 1, "Skipped earlier for lack of money; you can afford it now.")
        end
        if g.blockedBy then blockedGoals[#blockedGoals + 1] = g else kept[#kept + 1] = g end
    end
    -- Gone altogether (trained elsewhere, no longer needed): forget it.
    for key in pairs(deferred) do if not present[key] then deferred[key] = nil end end
    N.blockedGoals = blockedGoals
    N.deferredGoals = blockedGoals  -- older name
    list = kept
    -- "Just <name>'s" quests (PartyHelp.lua): only theirs, and yours where
    -- they need the same thing.
    if ns.partyHelp then list = ns.partyHelp:FilterGoals(list) end
    -- Inside a dungeon: only its quests (Dungeons.lua).
    if ns.dungeons then list = ns.dungeons:FilterInside(list) end
    -- Steps you hid (right-click on the map) stay out of the route; they're
    -- kept in N.hiddenGoals so the map panel can list and unhide them.
    local hidden = ns.db.nav.hidden or {}
    local shown, hiddenGoals = {}, {}
    for _, g in ipairs(list) do
        if hidden[g.key] then hiddenGoals[#hiddenGoals + 1] = g else shown[#shown + 1] = g end
    end
    N.hiddenGoals = hiddenGoals
    -- Your quests by zone, and the zones you haven't picked (0.35.293; picked
    -- one by one since 0.35.316, N.ZoneOn).
    do
        local function filter(sel)
            return pcall(N.ZoneFilter, shown, function(zone) return sel ~= nil and not sel[zone] end,
                function(g) return N.GoalZone(g) end, N.ZoneNameOf)
        end
        local sel = ns.db.nav.zonesOn
        local okZ, summary, keptZ, left = filter(sel)
        -- This character's first zones: the one it's in, and those where the
        -- quests in its log are (N.FirstZones). After that, only what you pick.
        if okZ and sel == nil then
            local p = N:PlayerPos()
            local here = p and N.ZoneOf(p.map)
            if here then
                sel = N.FirstZones(summary, here, ns.db.nav.zonesOff)
                ns.db.nav.zonesOn = sel
                ns:Log("route", "your questing zones, to start: " .. N.ZoneNames(sel))
                okZ, summary, keptZ, left = filter(sel)
            end
        end
        if okZ then
            N.zoneSummary = summary
            -- "Finish the selected zones first" (0.35.311): the zones you
            -- didn't tick stay on the route, after the ones you did (N:Options).
            if N.ZonesFirstOn() then
                for _, z in ipairs(summary) do z.later, z.off = z.off, false end
                N.zoneLeftOut = 0
            else
                shown, N.zoneLeftOut = keptZ, left
            end
        end
    end
    -- A step that waits for one you hid (a quest's hand-in, its objective
    -- hidden) can't be done yet either: off the route, with the reason
    -- (0.35.240: "Turn in: Centaur Bracers" at 10/15, its collect step hidden).
    local waiting
    shown, waiting = N.HoldForHidden(shown, hiddenGoals)
    for _, g in ipairs(waiting) do blockedGoals[#blockedGoals + 1] = g end
    -- And one that waits for a step on another continent (0.35.290: "Trial of
    -- the Sea Lion" sent to the shrine with half the pendant: the other half
    -- is across the sea, so its step wasn't on the route, and nothing held
    -- back the steps that need it). Both are listed, with where and how.
    do
        local me = N:PlayerPos()
        if me and me.cont then
            local okA, keptA, heldA = pcall(N.HoldForAway, shown, function(g) return N.AwayCont(g, me.cont) end, N.AwayWords)
            if okA then
                shown = keptA
                for _, g in ipairs(heldA) do blockedGoals[#blockedGoals + 1] = g end
            end
        end
    end
    -- And one that waits for any step left off the route for another reason:
    -- held (a quest 3+ levels above you, an elite), blocked, in a zone you
    -- didn't pick, filtered out. "Flow is telling me to turn in quests I have
    -- that are incomplete": "Turn in: Deepmoss Spider Eggs" at 0/15, its
    -- collect step held until level 20, so the hand-in had nothing left to
    -- wait for and looked ready.
    do
        local okD, keptD, heldD = pcall(N.HoldForDropped, shown, present)
        if okD then
            shown = keptD
            for _, g in ipairs(heldD) do blockedGoals[#blockedGoals + 1] = g end
        else
            ns:Log("nav", "hold for dropped: " .. tostring(keptD))
        end
    end
    -- "Along the way" goals (loot meat for an optional profession): never a
    -- step of their own, so the route never sends you off to grind them.
    -- They're listed in the arrow panel and step cards, and their mobs are
    -- worth looting when you meet them anyway.
    local routed, along = {}, {}
    for _, g in ipairs(shown) do
        if g.along then along[#along + 1] = g else routed[#routed + 1] = g end
    end
    N.alongGoals = along
    shown = routed
    -- XP-first sorting (XpValue.lua): weights by XP and quest level; also adds XP to tooltips.
    -- and the route objective (what the route optimises; XpValue.lua) weighs
    -- the steps and may pick which ones count.
    if ns.xpValue then
        local okA, picked = pcall(ns.xpValue.Apply, ns.xpValue, shown)
        if okA and picked then shown = picked end
    end
    -- A craft whose materials come from a step that's off the route (blocked,
    -- hidden, filtered out) can't be made yet: it waits, never "Here: Make".
    local held
    shown, held = N.HoldCrafts(shown, present)
    for _, g in ipairs(held) do blockedGoals[#blockedGoals + 1] = g end
    -- Profession steps (training, skill-ups) get their own faint arrow when
    -- it's on, so the quest arrow never sends you off to them.
    -- (On a custom route a profession step you picked is the route: the main arrow has it.)
    local quest, prof = N.SplitProfessions(shown, N:ProfPointerOn() and not (ns.focus and ns.focus.Active() and not ns.focus.idle))
    N.profGoals = prof
    N.profDirty = true
    goals = quest
    N.planDirty = true
end

-- A profession step: a skill-up step (SkillPlan.lua) or a profession errand
-- (train or skill up a profession). Class training is not one: it stays on
-- the quest arrow.
function N.IsProfessionStop(g)
    if not g or g.milestone then return false end
    if g.provider == "skillplan" then return true end
    return g.provider == "errands" and g.key ~= "train:class"
end

-- The faint profession arrow: off unless you tick it (arrow menu, Options,
-- /flow nav profarrow on, or under Professions in the route menu), and only with Professions on the route. (On by
-- default it moved profession steps off the main route, where the Flow key
-- does their steps: at a forge step the key no longer made the bars.)
function N:ProfPointerOn()
    local cfg = ns.db.nav
    return cfg.profArrow == true and self:Includes("professions")
end

-- Craft steps whose deps (bank, smelting, an earlier craft) are steps that
-- exist (all: key -> goal) but aren't in `shown` can't be made yet. They come
-- out of the route, blocked with the reason; repeats so a craft that needs a
-- held craft waits too. A dep that isn't in `all` is done and doesn't hold.
-- Returns kept, held.
function N.HoldCrafts(shown, all)
    local kept, held = shown, {}
    while true do
        local inRoute, next, changed = {}, {}, false
        for _, g in ipairs(kept) do inRoute[g.key] = true end
        for _, g in ipairs(kept) do
            local wait
            if g.kind == "craft" then
                for _, dep in ipairs(g.deps or {}) do
                    if not inRoute[dep] and all[dep] then wait = all[dep] break end
                end
            end
            if wait then
                -- A copy: providers may hand back the same goal next time.
                local c = {}
                for k, v in pairs(g) do c[k] = v end
                local name = wait.text or wait.title or wait.key
                c.blockedBy = "first: " .. name .. (wait.blockedBy and (" (" .. wait.blockedBy .. ")") or "")
                held[#held + 1] = c
                changed = true
            else
                next[#next + 1] = g
            end
        end
        kept = next
        if not changed then return kept, held end
    end
end

-- Pure: steps in `shown` that wait (goal.deps) for a step in `off`
-- ({ [key] = goal }) leave the route too, blocked (a copy: the step itself
-- isn't marked); and so on down the chain. why(wait) -> blockedBy,
-- blockedShort. binds(g, dep) -> false for a dep that only orders (optional:
-- every dep binds). Returns kept, held.
local function holdChain(shown, off, why, binds)
    local kept, held = shown, {}
    if not next(off) then return kept, held end
    while true do
        local nextKept, changed = {}, false
        for _, g in ipairs(kept) do
            local wait
            for _, dep in ipairs(g.deps or {}) do
                if off[dep] and (not binds or binds(g, dep)) then wait = off[dep] break end
            end
            if wait then
                local c = {}
                for k, v in pairs(g) do c[k] = v end
                c.blockedBy, c.blockedShort = why(wait)
                held[#held + 1] = c
                off[g.key] = c
                changed = true
            else
                nextKept[#nextKept + 1] = g
            end
        end
        kept = nextKept
        if not changed then return kept, held end
    end
end

local function stepName(g) return g.text or g.title or g.key end

-- A dep that only orders (goal.softDeps: a soft need) never holds a step.
local function bindsHard(g, dep) return not (g.softDeps and g.softDeps[dep]) end

-- Pure: steps that come after a step you hid (goal.deps) leave the route
-- too, blocked with the reason; and so on down the chain. A soft dep only
-- orders, so it never holds. Returns kept, held.
function N.HoldForHidden(shown, hiddenGoals)
    local off = {}
    for _, g in ipairs(hiddenGoals or {}) do off[g.key] = g end
    return holdChain(shown, off, function(wait)
        return "first: " .. stepName(wait) .. " (you hid that step: unhide it in the Flow Router)", "its step is hidden"
    end, bindsHard)
end

-- Pure: steps that wait for one Flow knows (known: { [key] = goal }: N:Collect's
-- `present`, every step of the kinds you ticked, blocked and hidden ones too)
-- that isn't on the route (`shown`) leave it too: a hand-in whose objective is
-- held, blocked or in a zone you left out can't be done yet, so it isn't
-- "Turn in". A step that is done is in neither, so what waits for it stays.
-- A dep that only orders (goal.softDeps, a soft need: class training after
-- the quest that teaches Bear Form) never holds: training doesn't wait for a
-- quest you can't do yet. Returns kept, held.
function N.HoldForDropped(shown, known)
    local on, off = {}, {}
    for _, g in ipairs(shown) do on[g.key] = true end
    for key, g in pairs(known or {}) do
        if not on[key] then off[key] = g end
    end
    return holdChain(shown, off, function(wait)
        local reason = wait.blockedBy and (" (" .. wait.blockedBy .. ")") or " (not on your route)"
        return "first: " .. stepName(wait) .. reason, "waits for another step"
    end, bindsHard)
end

-- Quests by zone (0.35.293). "Quests are starting to pull me into the
-- Stonetalon Mountains and I don't know if I want to go there. I'd like to
-- be able to tell which zone I should be heading towards." Flow had "finish
-- the area you're in first" (an order, not a choice) and nothing that said
-- what waits where. Now it counts your quest steps by zone, with their
-- levels, and a zone can be left out of the route: its quests stay in your
-- log and come back when you tick it again.
--   Only quest steps count (accepting, objectives, handing in): a trainer or
--   a vendor is wherever it is.
N.ZONE_PROVIDERS = { questie = true, pickups = true, native = true }
-- Pure: summary ({ { zone, name, steps, accept, log, min, max, off,
-- classSpells } }, most steps first), the goals kept, and how many were
-- left out.
--   off: { [zone] = true }, or function(zone) -> true for a zone left out;
--   zoneOf(goal) -> zone or nil; nameOf(zone) -> name
--   log: steps of quests in your log (not ones to pick up); classSpells:
--   { [spell] = true } for class-quest steps there
function N.ZoneFilter(goals, off, zoneOf, nameOf)
    local isOff = type(off) == "function" and off or function(zone) return (off or {})[zone] == true end
    local byZone, order, kept, left = {}, {}, {}, 0
    for _, g in ipairs(goals or {}) do
        local zone = N.ZONE_PROVIDERS[g.provider or ""] and zoneOf(g) or nil
        local z
        if zone then
            z = byZone[zone]
            if not z then
                z = { zone = zone, name = nameOf(zone), steps = 0, accept = 0, log = 0, off = isOff(zone) and true or false }
                byZone[zone] = z
                order[#order + 1] = z
            end
            z.steps = z.steps + 1
            if g.kind == "accept" then z.accept = z.accept + 1 end
            if g.provider ~= "pickups" then z.log = z.log + 1 end
            if g.classQuest then
                z.classSpells = z.classSpells or {}
                z.classSpells[g.classQuest] = true
            end
            local lv = tonumber(g.level)
            if lv and lv > 0 then
                z.min = math.min(z.min or lv, lv)
                z.max = math.max(z.max or lv, lv)
            end
        end
        if z and z.off then left = left + 1 else kept[#kept + 1] = g end
    end
    table.sort(order, function(a, b)
        if a.steps ~= b.steps then return a.steps > b.steps end
        return tostring(a.name) < tostring(b.name)
    end)
    return order, kept, left
end
-- Pure: one zone's line: "The Barrens: 55 steps (12 to accept), levels 12-20".
function N.ZoneLine(z)
    local levels = z.min and (z.min == z.max and string.format(", level %d", z.min) or string.format(", levels %d-%d", z.min, z.max)) or ""
    return string.format("%s: %d step%s%s%s%s", tostring(z.name), z.steps, z.steps == 1 and "" or "s",
        z.accept > 0 and string.format(" (%d to accept)", z.accept) or "", levels,
        z.off and " - LEFT OUT" or (z.later and " - after your zones" or ""))
end
-- Pure: the zone a typed name means among the summary (a part of its name), or nil.
function N.ZoneByName(summary, text)
    text = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil end
    for _, z in ipairs(summary or {}) do
        if tostring(z.name):lower():find(text, 1, true) then return z end
    end
    return nil
end
function N.GoalZone(g)
    local pt = g.points and g.points[1]
    return pt and pt.map and N.ZoneOf and N.ZoneOf(pt.map) or nil
end
-- Your questing zones (0.35.316): the zones you pick, per character. "I
-- don't really want [Flow] intelligently picking what zone was next ...
-- show the user what the options were and what was suggested for the next
-- level, and then let them pick." Until 0.35.315 every zone was in unless
-- you unticked it, so quests to pick up anywhere around your level pulled
-- you into zones you hadn't chosen (Stonetalon). Now the route's quests are
-- in the zones you've ticked: the Flow Router's Zones list shows each zone
-- with what it holds (WhereNext.lua) and marks a few "suggested", and a note
-- says when you're in one you haven't picked (ZoneNotice.lua). A trainer,
-- vendor or flight master is wherever it is: only quest steps count.
-- (0.35.293's list of zones left out, zonesOff, was shared by every
-- character; it's read once, for a character's first zones.)
ns:PerCharacter("nav.zonesOn")
-- Is this zone one of yours? (Not picked yet: every zone, as before.)
function N.ZoneOn(zone)
    local sel = ns.db.nav.zonesOn
    return sel == nil or sel[zone] == true
end
-- Pure: a character's first zones: the one it's in and those where quests
-- in its log have steps, less those left out before (legacyOff).
function N.FirstZones(summary, here, legacyOff)
    legacyOff = legacyOff or {}
    local out = {}
    for _, z in ipairs(summary or {}) do
        if (z.log or 0) > 0 and not legacyOff[z.zone] then out[z.zone] = true end
    end
    if here and not legacyOff[here] then out[here] = true end
    return out
end
-- The zones of a set by name, for a line ("Mulgore, Thunder Bluff").
function N.ZoneNames(set)
    local names = {}
    for zone in pairs(set or {}) do names[#names + 1] = tostring(N.ZoneNameOf(zone)) end
    table.sort(names)
    return #names > 0 and table.concat(names, ", ") or "none"
end
local function zonesChanged(why)
    N.planDirty = true
    if N.RequestCollect then N.RequestCollect(why) end
    if ns.zoneNotice and ns.zoneNotice.Check then pcall(ns.zoneNotice.Check) end
end
function N.SetZoneOn(zone, on)
    if not zone then return end
    if not ns.db.nav.zonesOn then ns.db.nav.zonesOn = N.SelectedZones() or {} end
    ns.db.nav.zonesOn[zone] = on and true or nil
    zonesChanged(on and "a zone picked" or "a zone left out")
end
function N.SetZoneOff(zone, off) N.SetZoneOn(zone, not off) end   -- (its older name)

-- "Finish the selected zones first" (0.35.311: "the option to finish the
-- area you're in first should be finish the selected zones first, and then
-- in zones the user can select the zones that they want"). The ticks in
-- the Flow menu's Zones are the selection either way:
--   off (default): an unticked zone is left out of the route (0.35.293);
--   on: an unticked zone stays on it, after the ticked ones are done.
function N.ZonesFirstOn() return ns.db.nav.zonesFirst == true end
function N.SetZonesFirst(on)
    ns.db.nav.zonesFirst = on and true or false
    N.planDirty = true
    if N.RequestCollect then N.RequestCollect("finish the selected zones first " .. (on and "on" or "off")) end
end
-- The zones ticked: { [zone] = true }. Not picked yet: every zone with
-- quest steps (the summary), as the route has them.
function N.SelectedZones(summary)
    local sel, out = ns.db.nav.zonesOn, {}
    if sel then
        for zone in pairs(sel) do out[zone] = true end
        return out
    end
    for _, z in ipairs(summary or N.zoneSummary or {}) do out[z.zone] = true end
    return out
end
-- Pure: the Flow Tracker's line for it. nameOf(zone) -> name.
function N.PickedNote(picked, nameOf)
    local names = {}
    for z in pairs(picked or {}) do names[#names + 1] = nameOf(z) end
    table.sort(names)
    if #names == 0 then return nil end
    if #names <= 2 then return "Finishing " .. table.concat(names, " and ") .. " first" end
    return string.format("Finishing your %d zones first", #names)
end
-- Pure: the zones a quick choice picks. how: "all" (every zone listed),
-- "none", or "here" (only `here`, the zone you're in). -> { [zone] = true }
function N.ZonesOnFor(how, choices, here)
    local on = {}
    if how == "none" then return on end
    if how == "here" then
        if here then on[here] = true end
        return on
    end
    for _, c in ipairs(choices or {}) do on[c.zone] = true end
    return on
end

-- The Zones list (0.35.316): your zones with quest steps, and the zones
-- with quests for your level (WhereNext.lua), a row each. Pure:
--   summary: N.ZoneFilter's; where: { [zone] = tally } (W.ByZone);
--   selected: { [zone] = true } (nil: not picked yet, every zone is in);
--   here: the zone you're in.
-- -> { { zone, name, route = summary row, where = tally, on, here } }:
--   yours first (most steps first), then the suggested, then the rest
--   (most XP first).
function N.ZoneChoices(summary, where, selected, here)
    local byZone, out = {}, {}
    local function row(zone, name)
        local c = byZone[zone]
        if not c then
            c = { zone = zone, name = name, on = selected == nil or selected[zone] == true, here = zone == here }
            byZone[zone] = c
            out[#out + 1] = c
        end
        return c
    end
    for _, z in ipairs(summary or {}) do row(z.zone, z.name).route = z end
    for zone, w in pairs(where or {}) do
        local c = row(zone, w.name)
        c.where = w
        c.name = c.name or w.name
    end
    local function rank(c) return (c.on and 1) or ((c.where and c.where.suggested) and 2) or 3 end
    table.sort(out, function(a, b)
        local ra, rb = rank(a), rank(b)
        if ra ~= rb then return ra < rb end
        local sa, sb = a.route and a.route.steps or 0, b.route and b.route.steps or 0
        if sa ~= sb then return sa > sb end
        local xa, xb = a.where and a.where.xp or 0, b.where and b.where.xp or 0
        if xa ~= xb then return xa > xb end
        return tostring(a.name) < tostring(b.name)
    end)
    return out
end
-- The list as it is now.
function N.ZoneChoicesNow()
    local p = N.PlayerPos and N:PlayerPos()
    local here = p and N.ZoneOf(p.map)
    local W = ns.whereNext
    local where = W and W.ByZone and W.ByZone() or {}
    return N.ZoneChoices(N.zoneSummary, where, ns.db.nav.zonesOn, here), here
end

-- Pure: a zone's row: "Ashenvale: levels 18-24, 22 to pick up - suggested".
function N.ZoneChoiceText(c)
    local w, r = c.where, c.route
    local lo = math.min(w and w.min or 999, r and r.min or 999)
    local hi = math.max(w and w.max or 0, r and r.max or 0)
    local parts = {}
    if lo <= hi then parts[#parts + 1] = lo == hi and ("level " .. lo) or string.format("levels %d-%d", lo, hi) end
    if r and r.steps > 0 then parts[#parts + 1] = string.format("%d step%s", r.steps, r.steps == 1 and "" or "s") end
    if w and w.quests > 0 then parts[#parts + 1] = string.format("%d to pick up", w.quests) end
    local text = tostring(c.name) .. (#parts > 0 and (": " .. table.concat(parts, ", ")) or "")
    if c.here then text = text .. " (you're here)" end
    if w and w.suggested then text = text .. " |cffffd100- suggested|r" end
    return text
end

-- Pure: a zone's tooltip: its name, then short lines (what's on your route
-- there, what you could pick up, how it levels: WhereNext.lua).
function N.ZoneChoiceTip(c)
    local lines = { tostring(c.name) }
    local w, r = c.where, c.route
    if w and w.suggested then lines[#lines + 1] = "|cffffd100Suggested: " .. tostring(w.why) .. "|r" end
    if r and r.steps > 0 then
        local levels = r.min and (r.min == r.max and string.format(", level %d", r.min) or string.format(", levels %d-%d", r.min, r.max)) or ""
        lines[#lines + 1] = string.format("Your route here: %d step%s%s%s", r.steps, r.steps == 1 and "" or "s",
            r.accept > 0 and string.format(" (%d to accept)", r.accept) or "", levels)
    end
    if r and r.classSpells then
        local spells = {}
        for s in pairs(r.classSpells) do spells[#spells + 1] = s end
        table.sort(spells)
        lines[#lines + 1] = "Class quest here: " .. table.concat(spells, ", ")
    end
    local W = ns.whereNext
    if w and W and W.TipLines then
        for _, l in ipairs(W.TipLines(w)) do lines[#lines + 1] = l end
    elseif not w then
        lines[#lines + 1] = "No quests to pick up here for your level"
    end
    return lines
end

function N.SelectZones(how)
    local choices, here = N.ZoneChoicesNow()
    ns.db.nav.zonesOn = N.ZonesOnFor(how, choices, here)
    zonesChanged("zones: select " .. tostring(how))
end
function N.ZoneLines()
    local choices = N.ZoneChoicesNow()
    if #choices == 0 then return { "zones: none with quests for you yet" } end
    local out = { string.format("your questing zones, [x] picked (%d quest steps left out of the route now%s):", N.zoneLeftOut or 0,
        N.ZonesFirstOn() and "; finishing the picked zones first" or "") }
    for _, c in ipairs(choices) do out[#out + 1] = "  " .. (c.on and "[x] " or "[ ] ") .. N.ZoneChoiceText(c) end
    out[#out + 1] = "  /flow zones on <zone> picks a zone; /flow zones off <zone> leaves it out; /flow zones all | none | here; /flow zones first (on or off)"
    return out
end
ns.commands.zones = function(arg)
    arg = arg or ""
    local cmd, rest = arg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "all" then
        N.SelectZones("all")
        ns:Print("every zone listed is picked")
        return
    end
    if cmd == "none" or cmd == "here" then
        N.SelectZones(cmd)
        ns:Print(cmd == "none" and "no zone is picked: tick the ones you want (Flow Router, Route, Zones, or /flow zones on <zone>)"
            or "only the zone you're in is picked")
        return
    end
    if cmd == "first" then
        N.SetZonesFirst(not N.ZonesFirstOn())
        ns:Print("finish the selected zones first: " .. (N.ZonesFirstOn() and "on (unticked zones come after them)" or "off (unticked zones are left out)"))
        return
    end
    if cmd == "off" or cmd == "on" then
        local z = N.ZoneByName(N.ZoneChoicesNow(), rest)
        if not z then ns:Print("no zone with quests for you called \"" .. tostring(rest) .. "\" (/flow zones lists them)") return end
        N.SetZoneOn(z.zone, cmd == "on")
        ns:Print(cmd == "off" and (z.name .. " is left out of your route: its quests stay in your log. /flow zones on " .. z.name .. " puts it back.")
            or (z.name .. " is one of your zones: its quests are on your route"))
        return
    end
    for i, l in ipairs(N.ZoneLines()) do if i == 1 then ns:Print(l) else print(l) end end
end
-- The Flow menu's entries: a tick a zone (your zones, then the suggested,
-- then the rest, each with its levels and a tooltip of what it holds), then
-- (under a line) the quick choices. ("Finish the selected zones first" is
-- under Order.)
function N.ZoneMenuItems()
    local items = {}
    local first = N.ZonesFirstOn()
    local choices, here = N.ZoneChoicesNow()
    for _, c in ipairs(choices) do
        items[#items + 1] = { text = N.ZoneChoiceText(c), stay = true, checked = N.ZoneOn(c.zone),
            tipLines = N.ZoneChoiceTip(c),
            tip = first and "Ticked: the route finishes this zone's quests first. Unticked: they stay on your route, after the ticked zones."
                or "Ticked: you quest here, and its quests are on your route. Unticked: left out (quests in your log stay there).",
            func = function() N.SetZoneOn(c.zone, not N.ZoneOn(c.zone)) end,
            refresh = function(it) it.checked = N.ZoneOn(c.zone) end }
    end
    local W = ns.whereNext
    if W and W.scanning then
        items[#items + 1] = { text = "|cff888888Looking up the zones for your level...|r", disabled = true }
    end
    if #items == 0 then return items end
    items[#items + 1] = { rule = true }
    if here and not N.ZoneOn(here) then
        items[#items + 1] = { text = "Quest in the zone you're in (" .. N.ZoneNameOf(here) .. ")", stay = true,
            func = function() N.SetZoneOn(here, true) end,
            tip = "Adds the zone you're in to your zones: its quests come onto your route." }
    end
    -- ("Select all zones", not "Select all": Route includes has a Select all
    -- of its own, and no entry may be in the Flow menu twice.)
    items[#items + 1] = { text = "Select all zones", stay = true, func = function() N.SelectZones("all") end }
    items[#items + 1] = { text = "Select no zones", stay = true, func = function() N.SelectZones("none") end,
        tip = "Untick every zone, then tick the ones you want." }
    items[#items + 1] = { text = here and ("Current zone only (" .. N.ZoneNameOf(here) .. ")") or "Current zone only", stay = true,
        func = function() N.SelectZones("here") end }
    return items
end

-- Steps that wait for one on another continent. Pure:
--   awayOf(g) -> the continent a step is on when that isn't yours (nil: here)
--   words(wait, waiting) -> blockedBy, blockedShort for the step across the
--     sea itself (waiting = false) or for one that waits for it (true)
--   -> kept, held: the away steps something waits for and everything that
--      waits (in turn) for them are held; an away step nothing waits for
--      stays as it was.
function N.HoldForAway(shown, awayOf, words)
    local away = {}
    for _, g in ipairs(shown or {}) do
        if awayOf(g) ~= nil then away[g.key] = g end
    end
    local held = {}
    if not next(away) then return shown, held end
    local off, needed = {}, {}
    for k, g in pairs(away) do off[k] = g end
    local kept = shown
    while true do
        local nextKept, changed = {}, false
        for _, g in ipairs(kept) do
            local wait
            if not away[g.key] then
                for _, dep in ipairs(g.deps or {}) do
                    -- (A soft dep only orders: it never holds.)
                    if off[dep] and not (g.softDeps and g.softDeps[dep]) then wait = off[dep] break end
                end
            end
            if wait then
                -- (The step across the sea it comes down to.)
                local root = wait.awayRoot or wait
                needed[root.key] = root
                local c = {}
                for k, v in pairs(g) do c[k] = v end
                c.blockedBy, c.blockedShort = words(root, true)
                c.awayRoot = root
                held[#held + 1] = c
                off[g.key] = c
                changed = true
            else
                nextKept[#nextKept + 1] = g
            end
        end
        kept = nextKept
        if not changed then break end
    end
    -- The away steps that are waited for: listed too, saying where they are.
    local out = {}
    for _, g in ipairs(kept) do
        if needed[g.key] then
            local c = {}
            for k, v in pairs(g) do c[k] = v end
            c.blockedBy, c.blockedShort = words(g, false)
            table.insert(held, 1, c)
        else
            out[#out + 1] = g
        end
    end
    return out, held
end
-- The continent a step is on when none of its places is on yours (nil: it
-- has a place here, or none Flow knows).
function N.AwayCont(g, mine)
    local other
    for _, pt in ipairs(g.points or {}) do
        if pt.wx == nil and pt.map then
            local cont, wx, wy = N:ToWorld(pt.map, pt.x, pt.y)
            pt.cont, pt.wx, pt.wy = cont, wx, wy
            if not wx then pt.wx = false end
        end
        if pt.wx and pt.cont == mine then return nil end
        if pt.wx and pt.cont ~= nil then other = pt.cont end
    end
    return other
end
-- Pure: the words, from a step's text, its zone, its continent and how to
-- cross. The row's few words name the zone when it's known (0.35.309: three
-- rows said "overseas" and "waits for a step overseas", and only the tooltip
-- said Silverpine Forest).
function N.AwayText(text, zone, continent, hint, waiting)
    local where = (zone and (zone .. ", ") or "") .. (continent or "another continent")
    if waiting then
        return string.format("first: %s. That's in %s.%s", text, where, hint and (" " .. hint) or ""),
            zone and ("after " .. zone) or "waits for a step overseas"
    end
    return string.format("It's in %s, not on this continent.%s", where, hint and (" " .. hint) or ""),
        zone and ("in " .. zone) or "overseas"
end
function N.AwayWords(wait, waiting)
    local pt = wait.points and wait.points[1]
    local zoneMap = pt and pt.map and N.ZoneOf and N.ZoneOf(pt.map)
    local info = zoneMap and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(zoneMap)
    local D = ns.dungeons
    local cont = pt and pt.cont
    local continent = D and D.CONTINENTS and cont ~= nil and D.CONTINENTS[cont] or nil
    local hint = D and D.TravelHint and cont ~= nil and D.TravelHint(cont, UnitFactionGroup and UnitFactionGroup("player")) or nil
    return N.AwayText(wait.text or wait.title or wait.key, info and info.name or nil, continent, hint, waiting)
end

-- Splits the steps into quest steps and profession steps. Off, or with
-- nothing but profession steps left, everything stays on the main arrow.
function N.SplitProfessions(list, on)
    if not on then return list, {} end
    local quest, prof = {}, {}
    for _, g in ipairs(list) do
        if N.IsProfessionStop(g) then prof[#prof + 1] = g else quest[#quest + 1] = g end
    end
    if #quest == 0 then return list, {} end
    return quest, prof
end

-- Turn the faint profession arrow on or off, and redo the route.
function N:SetProfArrow(on)
    ns.db.nav.profArrow = on and true or false
    self:Collect()
end

function N:Hide(key)
    if not key then return end
    ns.db.nav.hidden = ns.db.nav.hidden or {}
    ns.db.nav.hidden[key] = true
    self:Collect()
end

function N:Unhide(key)
    if ns.db.nav.hidden then ns.db.nav.hidden[key] = nil end
    self:Collect()
end

-------------------------------------------------------------------------------
-- What the route is made of: one tick per kind of step (0.35.157), in place
-- of the three routes (Quests only / Optimal / Completionist) and their
-- Professions switch. Each kind is a registration (Goals.lua has Flow's):
--   ns:Register("routeKind", key, { order, label, short, tip, default, custom,
--       match = function(goal, yourLevel) return true or false end })
-- custom (0.35.377) is what the kind does on a custom route: "lines" for the
-- quest kinds (your picked lines stand in for them), false for a kind that
-- starts unticked there (professions), nothing for one that starts ticked.
-- A step takes the first kind that matches it (lowest order first). A step
-- no kind claims is always on the route: a dungeon run you prepared and
-- party steps are there because you asked for them.
-- Your choice: ns.db.nav.kinds[key] (nothing saved: the kind's default).
-------------------------------------------------------------------------------
N.LOW_QUEST_BELOW = 4   -- a quest this many levels under you is "low-level" (grey soon)

local kindList
function N.Kinds()
    if not kindList then
        kindList = {}
        for key, def in ns:Each("routeKind") do kindList[#kindList + 1] = { key = key, def = def } end
        table.sort(kindList, function(a, b) return (a.def.order or 50) < (b.def.order or 50) end)
    end
    return kindList
end
function N.KindOf(goal, level)
    for _, k in ipairs(N.Kinds()) do
        local ok, yes = pcall(k.def.match, goal, level)
        if ok and yes then return k.key end
    end
end
-- On a custom route the kinds that aren't quests (trainers, errands, the bank,
-- flight paths, crossings, professions) have ticks of their own (Focus.lua,
-- 0.35.377), so leaving it gives you your usual ticks back untouched.
local function customTick(kind)
    local F = ns.focus
    return F and F.KindsOn and F.KindsOn() and not F.Replaces(kind)
end
function N:Includes(kind)
    if customTick(kind) then return ns.focus.KindOn(kind) end
    local saved = ns.db.nav.kinds and ns.db.nav.kinds[kind]
    if saved ~= nil then return saved end
    local def = ns:Get("routeKind", kind)
    return not def or def.default ~= false
end
function N:SetKind(kind, on)
    if customTick(kind) then
        ns.focus.SetKind(kind, on)
        return self:Collect()
    end
    ns.db.nav.kinds = ns.db.nav.kinds or {}
    ns.db.nav.kinds[kind] = on and true or false
    if kind == "professions" then ns.db.nav.professions = on and true or false end   -- (its older saved name)
    self:Collect()
end
function N:SetAllKinds(on)
    if ns.focus and ns.focus.KindsOn and ns.focus.KindsOn() then
        -- (Select all / Clear all on a custom route: its own ticks; your lines stay.)
        for _, k in ipairs(N.Kinds()) do
            if not ns.focus.Replaces(k.key) then ns.focus.SetKind(k.key, on) end
        end
        return self:Collect()
    end
    local kinds = {}
    for _, k in ipairs(N.Kinds()) do kinds[k.key] = on and true or false end
    ns.db.nav.kinds = kinds
    ns.db.nav.professions = on and true or false   -- (its older saved name)
    self:Collect()
end
-- The steps whose kind is ticked (includes(kind) -> bool); each step is
-- tagged with its kind (goal.routeKind) for the map and menus.
function N.FilterKinds(list, includes, level)
    local out = {}
    for _, g in ipairs(list) do
        local kind = N.KindOf(g, level)
        g.routeKind = kind
        if not kind or includes(kind) then out[#out + 1] = g end
    end
    return out
end
-- "everything", "current quests, new quests", "all but professions", "3 of 6 kinds".
function N.KindsSummary(includes)
    local on, off = {}, {}
    for _, k in ipairs(N.Kinds()) do
        local t = includes(k.key) and on or off
        t[#t + 1] = k.def.short or k.def.label
    end
    if #on == 0 then return "nothing" end
    if #off == 0 then return "everything" end
    if #on <= 2 then return table.concat(on, ", ") end
    if #off <= 2 then return "all but " .. table.concat(off, ", ") end
    return string.format("%d of %d kinds", #on, #on + #off)
end

-- The three older routes, still understood (/flow nav quests|optimal|complete
-- and code that asks which one you're on): told from the ticks.
function N:Mode()
    if self:Includes("lowQuests") then return "complete" end
    for _, k in ipairs(N.Kinds()) do
        if k.key ~= "quests" and k.key ~= "lowQuests" and self:Includes(k.key) then return "optimal" end
    end
    return "quests"
end
-- The ticks an older route stood for: "quests" (your log only), "complete"
-- (everything, low-level quests too), else "optimal" (everything at your
-- level). Professions stay as you had them.
function N.ModeKinds(mode, professions)
    local kinds = {
        quests = true,
        newQuests = mode ~= "quests",
        lowQuests = mode == "complete",
        training = mode ~= "quests",
        professions = mode ~= "quests" and professions ~= false,
        town = mode ~= "quests",
        battlegrounds = mode == "complete",   -- (0.35.357: only "everything" has them)
        crossings = mode ~= "quests",
    }
    -- (Kinds added since: the bank, flight paths. On, except on "quests only".)
    for _, k in ipairs(N.Kinds()) do
        if kinds[k.key] == nil then kinds[k.key] = mode ~= "quests" end
    end
    return kinds
end
function N:SetMode(mode)
    mode = (mode == "quests" or mode == "complete") and mode or "optimal"
    ns.db.nav.kinds = N.ModeKinds(mode, ns.db.nav.professions)
    ns.db.nav.mode = mode   -- (its older saved name, kept in step)
    self:Collect()
end

function N:Goals() return goals end

-------------------------------------------------------------------------------
-- HUD arrow: a chevron drawn from thin lines with a soft glow, a centre
-- spine, and a faint ring of dots with one bright dot in the direction of
-- travel. Lines can point anywhere, so the arrow is redrawn rotated instead
-- of rotating a picture. Same calls as a texture: SetRotation (radians,
-- counter-clockwise), SetVertexColor, Show, Hide.
-------------------------------------------------------------------------------

local CHEVRON = { { 0, 22 }, { -15, -14 }, { 0, -5 }, { 15, -14 } }
local RING_R, RING_DOTS = 27, 16

function N:MakeHudArrow(parent)
    local a = CreateFrame("Frame", nil, parent)
    a:SetSize(64, 64)
    a:SetPoint("CENTER")
    a.glow, a.core = {}, {}
    for i = 1, #CHEVRON do
        a.glow[i] = a:CreateLine(nil, "BACKGROUND")
        a.glow[i]:SetThickness(7)
        a.core[i] = a:CreateLine(nil, "ARTWORK")
        a.core[i]:SetThickness(2.5)
    end
    a.spine = a:CreateLine(nil, "OVERLAY")
    a.spine:SetThickness(1)
    a.ring = {}
    for i = 1, RING_DOTS do
        local d = a:CreateTexture(nil, "BACKGROUND")
        d:SetSize(2, 2)
        d:SetColorTexture(1, 1, 1, 0.22)
        local t = (i - 1) / RING_DOTS * 2 * math.pi
        d:SetPoint("CENTER", a, "CENTER", RING_R * math.sin(t), RING_R * math.cos(t))
        a.ring[i] = d
    end
    a.lead = a:CreateTexture(nil, "OVERLAY")
    a.lead:SetSize(5, 5)
    a.lead:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")

    a.angle, a.r, a.g, a.b = 0, 1, 0.62, 0
    local function draw()
        local c, s = math.cos(a.angle), math.sin(a.angle)
        local pts = {}
        for i, p in ipairs(CHEVRON) do
            pts[i] = { p[1] * c - p[2] * s, p[1] * s + p[2] * c }
        end
        for i = 1, #pts do
            local p1, p2 = pts[i], pts[i % #pts + 1]
            for _, l in ipairs({ a.glow[i], a.core[i] }) do
                l:SetStartPoint("CENTER", a, p1[1], p1[2])
                l:SetEndPoint("CENTER", a, p2[1], p2[2])
            end
            a.glow[i]:SetColorTexture(a.r, a.g, a.b, 0.25)
            a.core[i]:SetColorTexture(a.r, a.g, a.b, 1)
        end
        a.spine:SetStartPoint("CENTER", a, pts[1][1], pts[1][2])
        a.spine:SetEndPoint("CENTER", a, pts[3][1], pts[3][2])
        a.spine:SetColorTexture(1, 1, 1, 0.85)
        -- Bright dot on the ring where the arrow points.
        a.lead:ClearAllPoints()
        a.lead:SetPoint("CENTER", a, "CENTER", -RING_R * s, RING_R * c)
        a.lead:SetVertexColor(a.r, a.g, a.b, 1)
    end
    function a:SetRotation(r) self.angle = r or 0; draw() end
    function a:SetVertexColor(r, g, b) self.r, self.g, self.b = r, g, b; draw() end
    -- The step's own icon in the middle instead of the dot (cooking, a bag...).
    function a:SetCenterIcon(tex)
        if tex == self.iconTex then return end
        self.iconTex = tex
        if tex then
            self.center:SetTexture(tex); self.center:SetTexCoord(0.08, 0.92, 0.08, 0.92); self.center:SetSize(18, 18)
        else
            self.center:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask"); self.center:SetTexCoord(0, 1, 0, 1)
            self.center:SetSize(10, 10)
        end
    end
    -- Arrived: chevron gone, the ring lights up in the route colour and pulses,
    -- with a dot in the middle ("you're here").
    a.center = a:CreateTexture(nil, "OVERLAY")
    a.center:SetSize(10, 10)
    a.center:SetPoint("CENTER")
    a.center:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    a.center:Hide()
    function a:SetArrived(on)
        on = on and true or false
        if self.arrived == on then return end
        self.arrived = on
        for i = 1, #CHEVRON do self.glow[i]:SetShown(not on); self.core[i]:SetShown(not on) end
        self.spine:SetShown(not on); self.lead:SetShown(not on)
        self.center:SetShown(on)
        for _, d in ipairs(self.ring) do d:SetSize(on and 4 or 2, on and 4 or 2) end
        if on then
            self:SetScript("OnUpdate", function(me)
                local pulse = 0.6 + 0.4 * math.sin(GetTime() * 4)
                for _, d in ipairs(me.ring) do d:SetColorTexture(me.r, me.g, me.b, pulse) end
                if me.iconTex then me.center:SetVertexColor(1, 1, 1, 1) else me.center:SetVertexColor(me.r, me.g, me.b, 0.5 + 0.5 * pulse) end
            end)
        else
            self:SetScript("OnUpdate", nil)
            for _, d in ipairs(self.ring) do d:SetColorTexture(1, 1, 1, 0.22) end
        end
    end
    draw()
    return a
end

-------------------------------------------------------------------------------
-- 3D arrow (/flow nav arrow 3d; the modern arrow below is the default).
-- A thick chevron lying on the ground in front of you, seen from above and
-- behind like the game camera: it tilts away towards the horizon, its far
-- end is smaller (perspective), it has a lit top, darker sides and a soft
-- shadow, and it floats with a slight bob. Built from lines only:
--   * the slab is a stack of slices, darker at the bottom (the sides),
--   * each slice is filled with nested outlines,
--   * the top slice is shaded per edge by a fixed light (top-left).
-- Looks only: it turns left and right like the flat arrow. Forever gives no
-- heights, so it can't point up or down.
-------------------------------------------------------------------------------

local TILT = math.rad(52)                    -- how far the ground leans away from you
local COS_T, SIN_T = math.cos(TILT), math.sin(TILT)
local DEPTH = 150                            -- perspective strength (bigger = flatter)
local SLICES, FILL = 5, 7                    -- slab thickness (slices), fill density of the top
local THICK = 1.4                            -- pixels between slices
local LIGHT = { -0.6, 0.8 }                  -- light from the top-left of the screen
local CHEVRON3D = { { 0, 26 }, { -18, -16 }, { 0, -6 }, { 18, -16 } }

-- A ground point (x right, z forward) turned by `angle`, on screen. Pure
-- maths, so it can be tested: returns screen x, y and the perspective scale.
function N.Project3D(x, z, angle)
    local c, s = math.cos(angle), math.sin(angle)
    local gx, gz = x * c - z * s, x * s + z * c
    local k = DEPTH / (DEPTH + gz * SIN_T)
    return gx * k, gz * COS_T * k, k
end

-- Brightness of each slice of the 3D arrow's slab (0 = bottom): the top is
-- the route colour itself (1), the sides below a little darker.
function N.ArrowSliceShade(slice)
    if slice >= SLICES - 1 then return 1 end
    return 0.55 + 0.3 * slice / (SLICES - 1)
end

function N:MakeArrow3D(parent)
    local a = CreateFrame("Frame", nil, parent)
    a:SetSize(64, 64)
    a:SetPoint("CENTER")
    a.lines, a.n = {}, 0
    local function line(layer, thick)
        a.n = a.n + 1
        local l = a.lines[a.n]
        if not l then
            l = a:CreateLine(nil, layer)
            a.lines[a.n] = l
        end
        l:SetThickness(thick)
        l:Show()
        return l
    end
    -- The ring on the ground: a circle of pillars standing on it (short while
    -- pointing the way, tall and glowing when you've arrived). Each pillar is
    -- a stem with a lit cap; the ones at the back sit behind the arrow, the
    -- ones in front of it in front. a.ringAngle turns the ring (the login
    -- intro spins it).
    local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
    a.ring = {}
    for i = 1, RING_DOTS do
        local p = {}
        p.stem = a:CreateLine(nil, "BACKGROUND")
        p.stem:SetThickness(2)
        p.cap = a:CreateTexture(nil, "BACKGROUND", nil, 1)
        p.cap:SetTexture(CIRCLE)
        p.cap:SetSize(3, 2)
        a.ring[i] = p
    end
    a.ringAngle = 0
    -- Pillar height: small (3.5) while pointing, only a little taller (5)
    -- once you've arrived, with a quick bounce up as the change happens
    -- (POP for half a second); tall (12) while the login intro spins them.
    a.hStart, a.hFrom = 0, 3.5
    local POP, POP_SECS = 11, 0.5
    function a:PillarHeight()
        if self.spinning then return 12 end
        local base = self.arrived and 5 or 3.5
        local u = (GetTime() - (self.hStart or 0)) / POP_SECS
        if u >= 1 then return base end
        if self.arrived then return base + POP * math.sin(math.pi * u) * (1 - u) end
        return base + ((self.hFrom or base) - base) * (1 - u)   -- shrink back
    end
    function a:Popping() return GetTime() - (self.hStart or 0) < POP_SECS end
    -- Right on the spot: a sine wave runs round the ring, each pillar rising
    -- and falling a little after the one before it (two crests at a time).
    local WAVE_AMP, WAVE_SPEED, WAVE_CRESTS = 5, 5, 2
    function a:SetWave(on)
        on = (on and self.arrived) and true or false
        if on == (self.wave or false) then return end
        self.wave = on
        self.needDraw = true   -- (draw is defined further down: the frame update redraws)
    end
    function a:Wave(i)
        if not (self.wave and self.arrived) or self.spinning then return 0 end
        local phase = (i - 1) / RING_DOTS * WAVE_CRESTS * 2 * math.pi
        return WAVE_AMP * (0.5 + 0.5 * math.sin(GetTime() * WAVE_SPEED - phase))
    end
    -- The sphere in the middle when you've arrived: a dark base, a lit body
    -- and a white highlight up and to the left (the light), floating above
    -- its own shadow on the ground.
    local function ball(layer, sub, w, h)
        local t = a:CreateTexture(nil, layer, nil, sub)
        t:SetTexture(CIRCLE); t:SetSize(w, h or w); t:Hide()
        return t
    end
    a.ballShadow = ball("BACKGROUND", 2, 13, 4)
    a.ballBase = ball("OVERLAY", 1, 12)
    a.ballBody = ball("OVERLAY", 2, 9)
    a.ballHi = ball("OVERLAY", 3, 3)
    a.center = a.ballBody   -- older name
    function a:PlaceBall(lift)
        self.ballShadow:SetPoint("CENTER", self, "CENTER", 0, -1)
        self.ballBase:SetPoint("CENTER", self, "CENTER", 0, lift)
        self.ballBody:SetPoint("CENTER", self, "CENTER", -0.8, lift + 0.8)
        self.ballHi:SetPoint("CENTER", self, "CENTER", -2.4, lift + 2.6)
    end
    -- The step's own icon in place of the ball (the cooking icon at "Make 4 x
    -- Roasted Boar Meat", a bag for something to use from your bags):
    -- round, on a dark disc, bouncing over its shadow.
    a.icon = a:CreateTexture(nil, "OVERLAY", nil, 4)
    a.icon:SetSize(18, 18)
    a.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    a.icon:Hide()
    if a.CreateMaskTexture then
        local okM, mask = pcall(a.CreateMaskTexture, a)
        if okM and mask then
            mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints(a.icon)
            pcall(a.icon.AddMaskTexture, a.icon, mask)
        end
    end
    function a:SetCenterIcon(tex)
        if tex == self.iconTex then return end
        self.iconTex = tex
        if tex then self.icon:SetTexture(tex) end
        self:ShowBall(self.arrived)
    end
    function a:ShowBall(on)
        on = on and not self.noBall
        local icon = on and self.iconTex ~= nil
        self.icon:SetShown(icon)
        self.ballShadow:SetShown(on)
        self.ballBase:SetShown(on)                     -- the dark disc (behind the icon too)
        self.ballBody:SetShown(on and not icon); self.ballHi:SetShown(on and not icon)
        self.ballBase:SetSize(icon and 22 or 12, icon and 22 or 12)
    end

    a.angle, a.r, a.g, a.b, a.bob = 0, 1, 0.62, 0, 0
    local function outline(pts, dx, dy, layer, thick, r, g, b, alpha, shade)
        for i = 1, #pts do
            local p1, p2 = pts[i], pts[i % #pts + 1]
            local l = line(layer, thick)
            l:SetStartPoint("CENTER", a, p1[1] + dx, p1[2] + dy)
            l:SetEndPoint("CENTER", a, p2[1] + dx, p2[2] + dy)
            local m = 1
            if shade then
                -- Edge facing the light: brighter; facing away: darker.
                local ex, ey = p2[1] - p1[1], p2[2] - p1[2]
                local len = math.sqrt(ex * ex + ey * ey)
                if len > 0 then m = 0.8 + 0.35 * ((ey * LIGHT[1] - ex * LIGHT[2]) / len) end
            end
            l:SetColorTexture(math.min(1, r * m), math.min(1, g * m), math.min(1, b * m), alpha)
        end
    end
    local function draw()
        a.n = 0
        local pts, cx, cy = {}, 0, 0
        for i, p in ipairs(CHEVRON3D) do
            local x, y = N.Project3D(p[1], p[2], a.angle)
            pts[i] = { x, y }
            cx, cy = cx + x / #CHEVRON3D, cy + y / #CHEVRON3D
        end
        local function shrink(f)
            local out = {}
            for i, p in ipairs(pts) do out[i] = { cx + (p[1] - cx) * f, cy + (p[2] - cy) * f } end
            return out
        end
        if not a.arrived then
            -- Shadow on the ground: soft, offset down and right.
            outline(pts, 3, -5, "BACKGROUND", 7, 0, 0, 0, 0.22)
            outline(shrink(0.5), 3, -5, "BACKGROUND", 7, 0, 0, 0, 0.22)
            -- The slab: slices from the bottom (the sides, a little darker) up.
            -- The top is the route colour exactly, flat, the same purple as
            -- the (o) over the NPC you're heading to (it used to be shaded per
            -- edge and read as a muddier purple).
            local lift = 4 + a.bob
            for sl = 0, SLICES - 1 do
                local top = (sl == SLICES - 1)
                local m = N.ArrowSliceShade(sl)
                local dy = lift + sl * THICK
                for f = 1, (top and FILL or 1) do   -- lower slices: outline only (the sides)
                    local scale = 1 - (f - 1) / FILL
                    outline(scale == 1 and pts or shrink(scale), 0, dy, top and "ARTWORK" or "BORDER",
                        top and 2.6 or 2.5, a.r * m, a.g * m, a.b * m, 1, false)
                end
            end
            -- Ridge along the middle of the top: a faint highlight.
            local ridge = line("OVERLAY", 1.2)
            local dy = lift + (SLICES - 1) * THICK
            ridge:SetStartPoint("CENTER", a, pts[1][1], pts[1][2] + dy)
            ridge:SetEndPoint("CENTER", a, pts[3][1], pts[3][2] + dy)
            ridge:SetColorTexture(1, 1, 1, 0.3)
        end
        for i = a.n + 1, #a.lines do a.lines[i]:Hide() end
        -- The ring lies on the ground (an ellipse); its pillars stand up from it.
        local tall = a.arrived or a.spinning
        local hgt = a:PillarHeight()
        for i, p in ipairs(a.ring) do
            local t = (i - 1) / RING_DOTS * 2 * math.pi + a.ringAngle
            local x, y, k = N.Project3D(RING_R * math.sin(t), RING_R * math.cos(t), 0)
            local h = (hgt + a:Wave(i)) * k
            local front = math.cos(t) < 0      -- near you: in front of the arrow
            p.stem:SetDrawLayer(front and "ARTWORK" or "BACKGROUND", front and 7 or 0)
            p.cap:SetDrawLayer(front and "ARTWORK" or "BACKGROUND", 7)
            p.stem:SetStartPoint("CENTER", a, x, y)
            p.stem:SetEndPoint("CENTER", a, x, y + h)
            p.cap:ClearAllPoints()
            p.cap:SetPoint("CENTER", a, "CENTER", x, y + h)
            p.cap:SetSize(tall and 4 or 3, tall and 3 or 2)
            p.k = k
        end
        a:Light(a.arrived and a.pulse or 1)
    end
    -- Colours of the pillars: faint white while pointing; in the route colour
    -- (pulsing) when arrived or spinning, darker at the back, caps brightest.
    function a:Light(pulse)
        local tall = self.arrived or self.spinning
        pulse = pulse or 1
        for i, p in ipairs(self.ring) do
            if tall then
                local depth = 0.55 + 0.45 * math.min(1, math.max(0, ((p.k or 1) - 0.85) * 3))   -- back: darker
                p.stem:SetColorTexture(self.r * depth, self.g * depth, self.b * depth, 0.55 + 0.4 * pulse)
                p.cap:SetVertexColor(math.min(1, self.r + 0.45), math.min(1, self.g + 0.45), math.min(1, self.b + 0.45), 0.7 + 0.3 * pulse)
            else
                p.stem:SetColorTexture(1, 1, 1, 0.22)
                p.cap:SetVertexColor(1, 1, 1, 0.35)
            end
        end
        local r, g, b = self.r, self.g, self.b
        self.ballBase:SetVertexColor(r * 0.35, g * 0.35, b * 0.35, 1)
        self.ballBody:SetVertexColor(math.min(1, r * 0.9 + 0.1), math.min(1, g * 0.9 + 0.1), math.min(1, b * 0.9 + 0.1), 1)
        self.ballHi:SetVertexColor(1, 1, 1, 0.85)
        self.ballShadow:SetVertexColor(0, 0, 0, 0.45)
    end
    -- Turn the ring (the intro spins it fast; otherwise it stays put).
    function a:SetRingSpin(angle)
        self.ringAngle = angle or 0
        draw()
    end
    function a:SetRotation(r)
        r = r or 0
        if math.abs(r - self.angle) < 0.003 then return end
        self.angle = r; draw()
    end
    function a:SetVertexColor(r, g, b)
        if self.r == r and self.g == g and self.b == b then return end
        self.r, self.g, self.b = r, g, b; draw()
    end
    -- Gentle floating; once you've arrived the pillars pulse and the sphere floats.
    a:SetScript("OnUpdate", function(me)
        if me.arrived then
            local now = GetTime()
            if me:Popping() or me.wave or me.needDraw then me.needDraw = nil; draw() end   -- pop and wave move every frame
            me.pulse = 0.5 + 0.5 * math.sin(now * 4)
            me:Light(me.pulse)
            if me.iconTex then
                -- The icon bounces (a hop, not a float): "do this here, now".
                local hop = math.abs(math.sin(now * 3.2)) * 5
                me:PlaceBall(9 + hop)
                me.icon:ClearAllPoints(); me.icon:SetPoint("CENTER", me, "CENTER", 0, 9 + hop)
                me.ballShadow:SetSize(15 - hop, math.max(2, 4 - hop * 0.3))
            else
                me:PlaceBall(7 + 1.5 * math.sin(now * 2.4))
                me.ballShadow:SetSize(13, 4)
            end
            return
        end
        local bob = math.floor(1.5 * math.sin(GetTime() * 2.4) * 4 + 0.5) / 4   -- quarter pixels
        if bob ~= me.bob or me:Popping() then me.bob = bob; draw() end
    end)
    function a:SetArrived(on)
        on = on and true or false
        if self.arrived == on then return end
        self.hFrom = self:PillarHeight()   -- pop from where they are now
        self.hStart = GetTime()
        self.arrived = on
        self:ShowBall(on)
        if on then self:PlaceBall(7) end
        draw()
    end
    draw()
    return a
end

-------------------------------------------------------------------------------
-- Modern arrow (the default look): a glossy, bevelled chevron with a dark
-- outline and a soft shadow, drawn from pictures that tools/make-arrow-art.py
-- renders (128 turns, one picture each, in Modules/Nav/Art). Its colour
-- tells you how close you are (N.ArrowColor): grey while the step is in
-- another zone, red far away through yellow to green close by, blue in the
-- step's area. It floats over its shadow and a pool of its own light. When
-- you've arrived it gives way to a glowing ring on the ground with ripples
-- running out of it and a beam of light rising from the middle.
-------------------------------------------------------------------------------

local ART = "Interface\\AddOns\\Flow\\Modules\\Nav\\Art\\"
local TURNS, ART_COLS, ART_ROWS = 128, 16, 8
local COLOR_NEAR, COLOR_FAR = 40, 600   -- yards: fully green inside NEAR, fully red beyond FAR

-- The picture for a turn of `angle` (radians, anticlockwise, 0 = pointing
-- up): its number (0-127) and its texture coordinates left, right, top, bottom.
function N.ArrowCell(angle)
    local two = 2 * math.pi
    local i = math.floor(((angle or 0) % two) / two * TURNS + 0.5) % TURNS
    local col, row = i % ART_COLS, math.floor(i / ART_COLS)
    return i, col / ART_COLS, (col + 1) / ART_COLS, row / ART_ROWS, (row + 1) / ART_ROWS
end

-- How the arrow should be coloured for this step: "here" (you're in its
-- area), "away" (it's in another zone or on another continent) or "zone"
-- (same zone: by distance). p = N:PlayerPos(), pt = the step's point.
function N.ArrowState(p, pt, here)
    if here then return "here" end
    if p and pt then
        if p.cont and pt.cont and p.cont ~= pt.cont then return "away" end
        local mine, theirs = N.ZoneOf(p.map), N.ZoneOf(pt.map)
        if mine and theirs and mine ~= theirs then return "away" end
    end
    return "zone"
end

local function mix(a, b, t)
    return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t
end

-- The arrow's colour (r, g, b) for a state from N.ArrowState and the
-- distance in yards, from the theme (the colour-blind palette has its own).
function N.ArrowColor(state, d)
    local th = ns.theme
    if state == "away" then return th.arrowAway[1], th.arrowAway[2], th.arrowAway[3] end
    if state == "here" then return th.arrowHere[1], th.arrowHere[2], th.arrowHere[3] end
    local near = 1 - math.min(1, math.max(0, ((d or COLOR_FAR) - COLOR_NEAR) / (COLOR_FAR - COLOR_NEAR)))
    if near < 0.5 then return mix(th.arrowFar, th.arrowMid, near * 2) end
    return mix(th.arrowMid, th.arrowNear, near * 2 - 1)
end

-- The ring on the ground when you've arrived: an ellipse as wide as the
-- arrow, flattened by the same camera tilt as the pictures.
local HALO_W, HALO_H, HALO_Y = 58, 42, -4

-- The beam of light through the ring is one picture drawn twice: upright
-- above the ring's middle, mirrored below it. The picture (32 x 128) has a
-- see-through row round its edge, so where the two met there was a thin dark
-- line: "a slight crack between the centre up and down graphic" (0.35.179).
-- Both now stop at the middle of the picture's brightest row (one and a half
-- rows in from its bottom edge): bright meets bright, nothing between.
--   down: the mirrored one. -> left, right, top, bottom
N.BEAM_ROWS, N.BEAM_TRIM = 128, 1.5
function N.BeamCoords(down)
    local edge = 1 - N.BEAM_TRIM / N.BEAM_ROWS
    if down then return 0, 1, edge, 0 end
    return 0, 1, 0, edge
end

function N:MakeArrowModern(parent)
    local a = CreateFrame("Frame", nil, parent)
    a:SetSize(64, 64)
    a:SetPoint("CENTER")
    local function tex(file, layer, sub, blend)
        local t = a:CreateTexture(nil, layer, nil, sub)
        t:SetTexture(ART .. file)
        if blend then t:SetBlendMode(blend) end
        return t
    end
    -- Pointing the way: shadow and light pool stay on the ground, the
    -- arrow (body + its highlights) floats above them.
    a.shadow = tex("ArrowShadow", "BACKGROUND", 1)
    a.shadow:SetAllPoints()
    a.pool = tex("ArrowGlow", "BACKGROUND", 2, "ADD")
    a.pool:SetSize(60, 36)
    a.pool:SetPoint("CENTER", a, "CENTER", 0, -3)
    a.body = tex("ArrowBody", "ARTWORK", 1)
    a.body:SetSize(64, 64)
    a.body:SetPoint("CENTER")
    a.shine = tex("ArrowShine", "ARTWORK", 2, "ADD")
    a.shine:SetAllPoints(a.body)
    -- Arrived: the ring, a ripple running out of it and the beam.
    a.halo = tex("ArrowRing", "BACKGROUND", 3, "ADD")
    a.halo:SetSize(HALO_W, HALO_H)
    a.halo:SetPoint("CENTER", a, "CENTER", 0, HALO_Y)
    a.ripple = tex("ArrowRing", "BACKGROUND", 4, "ADD")
    a.ripple:SetPoint("CENTER", a, "CENTER", 0, HALO_Y)
    a.beam = tex("ArrowBeam", "ARTWORK", 3, "ADD")
    a.beam:SetTexCoord(N.BeamCoords(false))
    a.beam:SetPoint("BOTTOM", a, "CENTER", 0, HALO_Y)
    -- The same beam mirrored below the ring: it fades downward just as it
    -- fades upward, so the light runs through the ring both ways.
    a.beamDown = tex("ArrowBeam", "ARTWORK", 3, "ADD")
    a.beamDown:SetTexCoord(N.BeamCoords(true))
    a.beamDown:SetPoint("TOP", a, "CENTER", 0, HALO_Y)
    -- The step's own icon (craft here, use from your bags) bouncing in the
    -- ring: round, on a dark disc.
    local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
    a.disc = a:CreateTexture(nil, "OVERLAY", nil, 1)
    a.disc:SetTexture(CIRCLE)
    a.disc:SetSize(24, 24)
    a.icon = a:CreateTexture(nil, "OVERLAY", nil, 2)
    a.icon:SetSize(18, 18)
    a.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if a.CreateMaskTexture then
        local okM, mask = pcall(a.CreateMaskTexture, a)
        if okM and mask then
            mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints(a.icon)
            pcall(a.icon.AddMaskTexture, a.icon, mask)
        end
    end
    for _, t in ipairs({ a.halo, a.ripple, a.beam, a.beamDown, a.disc, a.icon }) do t:Hide() end

    -- a.r/g/b and a.angle are where the arrow is heading; a.cr/cg/cb and
    -- a.at are what's on screen, easing towards them (snapping while the
    -- login intro spins it).
    a.angle, a.at, a.cell = 0, 0, -1
    a.r, a.g, a.b = 1, 0.62, 0
    a.cr, a.cg, a.cb = a.r, a.g, a.b
    a.fade = 0   -- 0 = pointing, 1 = arrived (the arrow faded out, the ring in)

    local function paintCell()
        local i, l, r, t, b = N.ArrowCell(a.at)
        if i == a.cell then return end
        a.cell = i
        a.body:SetTexCoord(l, r, t, b)
        a.shine:SetTexCoord(l, r, t, b)
        a.shadow:SetTexCoord(l, r, t, b)
    end
    local function paintColor()
        local r, g, b = a.cr, a.cg, a.cb
        a.body:SetVertexColor(r, g, b)
        a.pool:SetVertexColor(r, g, b)
        a.halo:SetVertexColor(r, g, b)
        a.ripple:SetVertexColor(r, g, b)
        a.beam:SetVertexColor(r, g, b)
        a.beamDown:SetVertexColor(r, g, b)
        a.disc:SetVertexColor(r * 0.3, g * 0.3, b * 0.3, 1)
    end
    local function paintFade()
        local on = 1 - a.fade
        a.body:SetAlpha(on); a.shine:SetAlpha(on * 0.9)
        a.shadow:SetAlpha(on * 0.75); a.pool:SetAlpha(0.35 * on)
        local arrived = a.fade > 0.01
        a.halo:SetShown(arrived); a.ripple:SetShown(arrived); a.beam:SetShown(arrived); a.beamDown:SetShown(arrived)
        local icon = a.arrived and not a.noBall and a.iconTex ~= nil
        a.icon:SetShown(icon); a.disc:SetShown(icon)
    end

    function a:SetRotation(r)
        self.angle = r or 0
        if self.spinning then self.at = self.angle; paintCell() end
    end
    function a:SetVertexColor(r, g, b)
        self.r, self.g, self.b = r, g, b
        if self.spinning then self.cr, self.cg, self.cb = r, g, b; paintColor() end
    end
    function a:SetArrived(on)
        on = on and true or false
        if self.arrived == on then return end
        self.arrived = on
        self.arrivedAt = GetTime()
        paintFade()
    end
    function a:SetCenterIcon(tex)
        if tex == self.iconTex then return end
        self.iconTex = tex
        if tex then self.icon:SetTexture(tex) end
        paintFade()
    end
    -- Right on the spot: the ripples run faster and brighter.
    function a:SetWave(on) self.wave = (on and self.arrived) and true or false end

    a:SetScript("OnUpdate", function(me, elapsed)
        local dt = math.min(elapsed or 0, 0.1)
        local now = GetTime()
        -- Turn the shortest way round, quickly but without snapping.
        local diff = (me.angle - me.at + math.pi) % (2 * math.pi) - math.pi
        if math.abs(diff) > 0.001 then
            me.at = me.at + diff * (1 - math.exp(-dt * 14))
            paintCell()
        end
        -- Colour changes blend over about a second.
        local k = 1 - math.exp(-dt * 3)
        if math.abs(me.r - me.cr) + math.abs(me.g - me.cg) + math.abs(me.b - me.cb) > 0.004 then
            me.cr = me.cr + (me.r - me.cr) * k
            me.cg = me.cg + (me.g - me.cg) * k
            me.cb = me.cb + (me.b - me.cb) * k
            paintColor()
        end
        -- Fade between pointing and arrived (a quarter second).
        local want = me.arrived and 1 or 0
        if me.fade ~= want then
            local step = dt * 4
            me.fade = (want > me.fade) and math.min(want, me.fade + step) or math.max(want, me.fade - step)
            paintFade()
        end
        if me.fade < 1 then
            -- Float: the arrow bobs, its shadow stays on the ground.
            me.body:SetPoint("CENTER", me, "CENTER", 0, 1.5 * math.sin(now * 2.4))
        end
        if me.fade > 0 then
            local f = me.fade
            local pulse = 0.5 + 0.5 * math.sin(now * 4)
            me.halo:SetAlpha(f * (0.6 + 0.4 * pulse))
            local u = (now * (me.wave and 1.4 or 0.7)) % 1
            me.ripple:SetSize(HALO_W * (0.55 + 0.75 * u), HALO_H * (0.55 + 0.75 * u))
            me.ripple:SetAlpha(f * (1 - u) * (me.wave and 0.9 or 0.6))
            me.beam:SetSize(18 + 4 * pulse, 50 + 8 * pulse)
            me.beam:SetAlpha(f * (0.45 + 0.25 * pulse))
            me.beamDown:SetSize(18 + 4 * pulse, 50 + 8 * pulse)
            me.beamDown:SetAlpha(f * (0.45 + 0.25 * pulse))
            if me.icon:IsShown() then
                local hop = math.abs(math.sin(now * 3.2)) * 5   -- a hop: "do this here, now"
                me.icon:SetPoint("CENTER", me, "CENTER", 0, 8 + hop)
                me.disc:SetPoint("CENTER", me, "CENTER", 0, 8 + hop)
            end
        end
    end)
    paintCell(); paintColor(); paintFade()
    return a
end

-- The arrow styles, in the order the menus list them.
N.ARROW_STYLES = {
    { "modern", "Modern" },
    { "3d", "3D (pillars)" },
    { "flat", "Flat lines" },
}

-- The style in use: "modern" (default), "3d" or "flat".
function N:ArrowStyle()
    local s = ns.db.nav.arrowStyle
    return (s == "3d" or s == "flat") and s or "modern"
end

-- The arrow in the style you chose.
function N:MakeArrow(parent)
    local style = self:ArrowStyle()
    if style == "flat" then return self:MakeHudArrow(parent) end
    if style == "3d" then return self:MakeArrow3D(parent) end
    return self:MakeArrowModern(parent)
end

-- Arrow colour: "distance" (default: grey in another zone, orange to green as
-- you close in, blue in the area) or "route" (the route's own colour, your
-- waypoint green).
function N:ArrowColorMode()
    return ns.db.nav.arrowColor == "route" and "route" or "distance"
end
function N:SetArrowColorMode(mode)
    ns.db.nav.arrowColor = (mode == "route") and "route" or nil
end

-- Switch styles on the fly (arrow menu, settings, /flow nav arrow).
function N:SetArrowStyle(style)
    ns.db.nav.arrowStyle = (style == "3d" or style == "flat") and style or "modern"
    local frame = N.arrowFrame
    if frame and frame.arrow then
        local old = frame.arrow
        old:Hide(); old:SetScript("OnUpdate", nil)
        frame.arrow = self:MakeArrow(frame)
        frame.arrow:SetVertexColor(old.r or 1, old.g or 0.62, old.b or 0)
        frame.arrow:SetRotation(old.angle or 0)
        if old.arrived then frame.arrow:SetArrived(true) end
    end
    if frame and frame.prof and frame.prof.arrow then
        local old = frame.prof.arrow
        old:Hide(); old:SetScript("OnUpdate", nil)
        frame.prof.arrow = self:MakeProfArrow(frame.prof)
        frame.prof.arrow:SetRotation(old.angle or 0)
        frame.prof.arrow.at = old.at or old.angle or 0
        frame.prof.arrow:Paint()
    end
end

-- The faint profession arrow: the main arrow's own art, stretched narrow and
-- long (66% of its width, 133% of its length), in dark smoked glass under
-- the main arrow. It turns as one piece and eases round like the main arrow.
-- Same turning: 0 = straight up, counter-clockwise.
-- Measured on the art you see, not its 64 px picture cell: the main arrow's
-- drawn arrow is MAIN_WID across and MAIN_LEN long (its side-on length; the
-- pointing-up picture is tilted away, so it looks shorter), shown at
-- ON_NEEDLE_SCALE while this arrow is out. The pointing-up cell this one is
-- cut from holds an arrow ART0_W x ART0_H inside its 64 px.
N.MAIN_WID, N.MAIN_LEN = 40, 54
N.ART0_W, N.ART0_H = 40, 38
N.ON_NEEDLE_SCALE, N.ON_NEEDLE_ALPHA = 0.8, 0.7
N.PROF_WID_K, N.PROF_LEN_K = 0.5, 1.5   -- vs the main arrow you see: thinner, longer
N.PROF_WID = N.MAIN_WID * N.ON_NEEDLE_SCALE * N.PROF_WID_K
N.PROF_LEN = N.MAIN_LEN * N.ON_NEEDLE_SCALE * N.PROF_LEN_K
N.PROF_ARROW_W = 64 * N.PROF_WID / N.ART0_W
N.PROF_ARROW_H = 64 * N.PROF_LEN / N.ART0_H
N.PROF_RING_ALPHA = 0.35   -- the faint ring at the profession step
function N:MakeProfArrow(holder)
    local a = CreateFrame("Frame", nil, holder)
    a:SetAllPoints(holder)
    local W, H = N.PROF_ARROW_W, N.PROF_ARROW_H
    local function tex(file, layer, sub, blend, alpha)
        local t = a:CreateTexture(nil, layer, nil, sub)
        t:SetTexture(ART .. file)
        if blend then t:SetBlendMode(blend) end
        t:SetAlpha(alpha)
        t:SetPoint("CENTER")
        return t
    end
    -- Dark body, a soft shadow under it and the main arrow's highlights on
    -- top: dark glass, not a flat grey cut-out.
    a.shadow = tex("ArrowShadow", "BACKGROUND", 1, nil, 0.45)
    a.body = tex("ArrowBody", "ARTWORK", 1, nil, 0.9)
    a.shine = tex("ArrowShine", "ARTWORK", 2, "ADD", 0.55)
    a.parts = { a.shadow, a.body, a.shine }
    -- Turning the picture itself keeps it narrow at every angle. A client
    -- that can't turn pictures gets the main arrow's pre-turned frames at
    -- full size instead.
    a.turns = a.body.SetRotation ~= nil
    local _, l, r, t, b = N.ArrowCell(0)
    for _, part in ipairs(a.parts) do
        if a.turns then part:SetSize(W, H); part:SetTexCoord(l, r, t, b) else part:SetSize(H, H) end
    end
    -- a.angle is where it's heading, a.at what's on screen.
    a.angle, a.at, a.cell = 0, 0, -1
    function a:Paint()
        if self.turns then
            for _, part in ipairs(self.parts) do part:SetRotation(self.at) end
            return
        end
        local i, l2, r2, t2, b2 = N.ArrowCell(self.at)
        if i == self.cell then return end
        self.cell = i
        for _, part in ipairs(self.parts) do part:SetTexCoord(l2, r2, t2, b2) end
    end
    function a:SetRotation(rad) self.angle = rad or 0 end
    function a:SetVertexColor(r2, g2, b2) self.body:SetVertexColor(r2, g2, b2) end
    local c = ns.theme.profPointer
    a:SetVertexColor(c[1], c[2], c[3])
    a:SetScript("OnUpdate", function(me, elapsed)
        local dt = math.min(elapsed or 0, 0.1)
        -- Turn the shortest way round, quickly but without snapping.
        local diff = (me.angle - me.at + math.pi) % (2 * math.pi) - math.pi
        if math.abs(diff) > 0.001 then
            me.at = me.at + diff * (1 - math.exp(-dt * 14))
            me:Paint()
        end
    end)
    a:Paint()
    return a
end

-- How far the profession arrow reaches past the arrow frame's edge (it is
-- longer than the frame), plus a little air: the texts above and below move
-- out by this much so the arrow never runs over or under them.
function N.NeedleClearance(f)
    local h = (f and f.GetHeight and f:GetHeight()) or 56
    return math.max(0, math.ceil(N.PROF_LEN / 2 - h / 2)) + 2
end

-- While the needle shows, the main arrow sits on top of it smaller and
-- see-through (the short hand), so the needle shows through and past it
-- (ON_NEEDLE_SCALE / ALPHA, set with the profession arrow's size above).
function N.SetOverNeedle(f, on)
    local a = f and f.arrow
    on = on and true or false
    if not a or a.overNeedle == on then return end
    a.overNeedle = on
    a:SetScale(on and N.ON_NEEDLE_SCALE or 1)
    a:SetAlpha(on and N.ON_NEEDLE_ALPHA or 1)
    -- (The arrow's lines move clear of the long profession arrow: N.LayoutLines.)
    f.stackSig = nil
end

-- The arrow's lines of text (0.35.323). "I'd like to see the text at the top
-- of the arrow with the largest at the very top, then the medium, then the
-- shortest under that, and then the arrow. If it's on the bottom half of the
-- screen it could flip, so the largest text is at the very bottom and it
-- works up almost like a triangle to the arrow on top."
--
-- Every line that goes with the arrow (the step's name, how far, the
-- profession arrow's line, the party and dungeon lines) is stacked on one
-- side of it, the shortest next to the arrow and the longest furthest away:
--   * arrow in the top half of the screen: the lines above it;
--   * arrow in the bottom half: the lines below it;
--   * no room above (the arrow sits right at the top edge): below, so
--     nothing runs off the screen. Drag the arrow down a little for "above".
-- A long second line ("2166 yd (to the flight master: fly ...). Hearthstone
-- is about 3 min quicker") is wrapped to N.SUB_WIDTH (0.35.302).
N.SUB_LONG, N.SUB_WIDTH = 60, 340
N.LINE_GAP = 2
-- Pure: is this a long line (to wrap)? Colour codes don't count.
function N.LongLine(text)
    if type(text) ~= "string" then return false end
    local plain = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    plain = plain:gsub("|r", "")
    return #plain > N.SUB_LONG
end
-- Pure: the lines in the order they leave the arrow: shortest first.
--   lines: { { key, w, h } } -> a new list
function N.StackOrder(lines)
    local out = {}
    for i, l in ipairs(lines or {}) do out[i] = l end
    table.sort(out, function(a, b)
        if a.w ~= b.w then return a.w < b.w end
        return tostring(a.key) < tostring(b.key)
    end)
    return out
end
-- Pure: which side of the arrow? centerY, top: the arrow's middle and top
-- edge, from the bottom of the screen; need: the stack's height.
function N.StackSide(centerY, screenH, top, need)
    if centerY < screenH / 2 then return "below" end
    if top + need > screenH then return "below" end
    return "above"
end
-- Pure: how far from the arrow's edge each line starts. -> { [key] = offset }, total
function N.StackOffsets(ordered, first, gap)
    local out, at = {}, first or 0
    for _, l in ipairs(ordered) do
        out[l.key] = at
        at = at + (l.h or 0) + (gap or 0)
    end
    return out, at
end

local function arrowLines(f)
    local out = {}
    local function add(key, region, fs, cap)
        fs = fs or region
        local text = fs:GetText()
        if not (region:IsShown() and text and text ~= "") then return end
        local w = fs:GetStringWidth() or 0
        if cap then w = math.min(w, cap) end
        out[#out + 1] = { key = key, region = region, fs = fs, w = w, h = math.max(fs:GetStringHeight() or 0, 10) }
    end
    add("title", f.text)
    local long = N.LongLine(f.sub:GetText())
    if long ~= f.subLong then
        f.subLong = long
        f.sub:SetWidth(long and N.SUB_WIDTH or 0)
    end
    add("sub", f.sub, nil, long and N.SUB_WIDTH or nil)
    if f.prof and f.prof:IsShown() then add("prof", f.prof.text, nil, 260) end
    -- The lines other parts of Flow hang on the arrow: buttons with a .text.
    for _, pair in ipairs({ { "party", ns.party }, { "partyHelp", ns.partyHelp }, { "dungeon", ns.dungeons } }) do
        local t = pair[2] and pair[2].toggle
        if t and t.text then add(pair[1], t, t.text) end
    end
    return out
end

-- Places the arrow's lines. Cheap when nothing changed (called a few times a second).
function N.LayoutLines(f)
    if not (f and f.text and f.sub and f:IsVisible()) then return false end
    local lines = N.StackOrder(arrowLines(f))
    local h = f:GetHeight() or 56
    local clear = ((f.arrow and f.arrow.overNeedle) or (f.prof and f.prof:IsShown())) and N.NeedleClearance(f) or nil
    local travel = (f.travel and f.travel:IsShown()) and (((N.TRAVEL_ICON or 0) - h) / 2 + 4) or 0
    local _, need = N.StackOffsets(lines, 0, N.LINE_GAP)
    local _, cy = f:GetCenter()
    local scale = (f:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
    local screenH = (UIParent:GetHeight() or 768) / scale
    local side = N.StackSide(cy or 0, screenH, f:GetTop() or 0, need + (clear or 4))
    local first = math.max(clear or (side == "above" and 4 or 2), travel)
    local parts = { side, tostring(math.floor(first + 0.5)) }
    for _, l in ipairs(lines) do parts[#parts + 1] = string.format("%s:%d:%d", l.key, math.floor(l.w + 0.5), math.floor(l.h + 0.5)) end
    local sig = table.concat(parts, "|")
    f.stackSide, f.stackFirst, f.stackOrder = side, first, lines
    if sig == f.stackSig then return false end
    f.stackSig = sig
    local offsets, total = N.StackOffsets(lines, first, N.LINE_GAP)
    for _, l in ipairs(lines) do
        local r = l.region
        if r ~= l.fs then r:SetSize(math.max(60, l.w), math.max(16, l.h)) end   -- (a button: as wide as its words)
        r:ClearAllPoints()
        if side == "above" then r:SetPoint("BOTTOM", f, "TOP", 0, offsets[l.key])
        else r:SetPoint("TOP", f, "BOTTOM", 0, -offsets[l.key]) end
    end
    -- The part of the stack that clicks like the arrow: over the lines, on their side.
    if f.textHit then
        f.textHit:ClearAllPoints()
        f.textHit:SetSize(240, math.max(20, total))
        if side == "above" then f.textHit:SetPoint("BOTTOM", f, "TOP", 0, 0)
        else f.textHit:SetPoint("TOP", f, "BOTTOM", 0, 0) end
    end
    return true
end

-- Travel time: yards to "~1m 20s" at the speed you are moving, or the speed
-- you last moved at (a run, 7 yd a second, before you have moved at all).
N.RUN_SPEED = 7
-- (A flight path's speed isn't yours: it is never remembered as your speed.)
function N.TravelSpeed()
    local onTaxi = UnitOnTaxi and UnitOnTaxi("player")
    local s = A.Safe(GetUnitSpeed("player")) or 0
    if not onTaxi and type(s) == "number" and s > 0.5 then N.lastSpeed = s end
    return N.lastSpeed or N.RUN_SPEED
end
function N.FormatTravel(yd, speed)
    speed = speed or N.TravelSpeed()
    if type(yd) ~= "number" or yd <= 0 or type(speed) ~= "number" or speed <= 0 then return "" end
    return N.FormatSeconds(yd / speed)
end
-- Seconds to "~45s" / "~1m 20s" / "~1h 02m" ("" for no time).
function N.FormatSeconds(sec)
    if type(sec) ~= "number" or sec <= 0 then return "" end
    sec = math.max(1, math.floor(sec + 0.5))
    if sec < 60 then return string.format("~%ds", sec) end
    if sec < 3600 then return string.format("~%dm %02ds", math.floor(sec / 60), sec % 60) end
    return string.format("~%dh %02dm", math.floor(sec / 3600), math.floor(sec % 3600 / 60))
end
-- The same with a space in front, or nothing when there is no time to show.
function N.TravelSuffix(yd, speed)
    local t = N.FormatTravel(yd, speed)
    return t ~= "" and (" " .. t) or ""
end

-- Shared look for route steps (trip plan, world map pins, map list):
--   label "3 [9]" = 3rd step, quest level 9; "!2 [8]" = 2nd quest pickup
--   colour: route colour (green) = where the arrow points now, blue = quest pickup,
--           sky blue = your waypoint, bluish green = the rest of the route
-- A blocked step for lists: lock (or coin) icon, greyed text, and the reason.
local LOCK = "Interface\\Buttons\\LockButton-Locked-Up"
-- A few words for a locked step's row: its own short form (blockedShort),
-- else its reason cut to size. The whole reason is in the step's tooltip and
-- on its card. (The Flow Router's rows are 300 wide: "Flow doesn't know
-- where: Questie has no spot for Fish Chunks. Your quest log says how." ran
-- out of the Router and over the quest log beside it.)
N.BLOCKED_MAX = 26
N.NO_SPOT = "no known spot"   -- (a quest step neither the quest data nor the game's marker places)
-- Reasons that start the same way, in two or three words.
local SHORT_REASONS = {
    { "^Flow doesn't know who sells", "no known seller" },
    { "^Flow doesn't know where .- comes from", "no known source" },
    { "^Flow doesn't know where", N.NO_SPOT },
    { "^Flow needs Questie", "needs Questie" },
}
function N.ShortBlocked(goal, max)
    max = max or N.BLOCKED_MAX
    local s = goal.blockedShort
    if not s then
        s = goal.blockedBy or "blocked"
        for _, r in ipairs(SHORT_REASONS) do
            if s:find(r[1]) then return r[2] end
        end
        -- "(you have 6c)", "(sold by Seller A or Seller B)": asides, kept for the tooltip.
        s = (s:gsub("%s*%b()", ""))
        s = s:match("^(.-)%.%s") or s   -- its first sentence
    end
    -- (Never cut through a colour or texture code: the row's own width does that.)
    if #s > max and not s:find("|", 1, true) then
        local cut = s:sub(1, max - 3)
        cut = cut:match("^(.*%S)%s+%S*$") or cut   -- (at a word, not through one)
        s = cut .. "..."
    end
    return s
end
function N:FormatBlocked(goal)
    return string.format("|T%s:12:12|t |cff9a9a9a%s|r", goal.blockIcon or LOCK, goal.text or goal.title or "?"),
           "|cffff7070" .. N.ShortBlocked(goal) .. "|r"
end

-- The NPC names of the next `n` steps after the current one (currentKey), for
-- the smaller (o) over their nameplates (QuestMarks.lua). Nameplates only
-- show near you, so these are the ones around you.
function N.NextStopNames(plan, currentKey, n)
    local out, seen, taken = {}, {}, 0
    for _, s in ipairs(plan or {}) do
        if taken >= (n or 5) then break end
        if s.goal and s.goal.key ~= currentKey then
            taken = taken + 1
            for _, name in ipairs(s.goal.npcs or {}) do
                if not seen[name] then seen[name] = true; out[#out + 1] = name end
            end
        end
    end
    return out
end

-- Everything to do around you (the Flow Tracker): the next step, and every
-- step on the route within N.HERE_YARDS of you or of that step, in route
-- order. `p` (where you are) may be nil. Returns plan indices.
N.HERE_YARDS = 150
local function within(a, b, yards)
    return a and b and a.cont == b.cont and a.wx and b.wx and dist(a.wx, a.wy, b.wx, b.wy) <= yards or false
end
-- Is any of step s's spots near `at`? Its route spot first, then every spawn
-- of its objective (goal.points), as the arrow's "in the area" does: a kill
-- objective whose wolves roam right here counts even when its one route spot
-- is across the zone (0.35.140: the map and Flow Tracker went by that one
-- spot only, the arrow by every spawn, so they disagreed).
-- (Each objective's spawns get a box around them, worked out once: a step
-- nowhere near you is ruled out at once instead of spawn by spawn. Checking
-- up to 80 spawns of every step, twice a second, doubled the Flow Tracker's
-- cost in 0.35.140.)
-- (Keyed by the spawn list itself and its length, so a list that is
-- replaced or grows gets a new box.)
local boxes = setmetatable({}, { __mode = "k" })
local function boxOf(points)
    local b = boxes[points]
    if b and b.n == #points then return b end
    b = { n = #points }
    for _, pt in ipairs(points) do
        if pt.wx and pt.wy then
            if not b.any then b.any, b.cont, b.x1, b.x2, b.y1, b.y2 = true, pt.cont, pt.wx, pt.wx, pt.wy, pt.wy
            elseif pt.cont ~= b.cont then b.mixed = true
            else
                if pt.wx < b.x1 then b.x1 = pt.wx elseif pt.wx > b.x2 then b.x2 = pt.wx end
                if pt.wy < b.y1 then b.y1 = pt.wy elseif pt.wy > b.y2 then b.y2 = pt.wy end
            end
        end
    end
    boxes[points] = b
    return b
end
N.SpawnBox = boxOf   -- (Actions.lua's "at the step" check; tests)
local function stopNear(s, at, yards)
    if not at then return false end
    if within(s.point, at, yards) then return true end
    local pts = s.goal and s.goal.points
    local b = pts and boxOf(pts)
    if not (b and b.any) or not at.wx then return false end
    if not b.mixed and (b.cont ~= at.cont or at.wx < b.x1 - yards or at.wx > b.x2 + yards
        or at.wy < b.y1 - yards or at.wy > b.y2 + yards) then
        return false
    end
    for _, pt in ipairs(pts) do
        if within(pt, at, yards) then return true end
    end
    return false
end
N._stopNear = stopNear   -- (tests)
-- Is step i of the plan "here": the next step, or near you, or near the
-- next step? (One step at a time, for a caller that only cares about a few.)
function N.IsHere(plan, i, p, yards)
    local s = plan and plan[i]
    if not s then return false end
    yards = yards or N.HERE_YARDS
    local first = plan[1] and plan[1].point
    return i == 1 or stopNear(s, p, yards) or stopNear(s, first, yards)
end
function N.HereStops(plan, p, yards)
    local out = {}
    for i in ipairs(plan or {}) do
        if N.IsHere(plan, i, p, yards) then out[#out + 1] = i end
    end
    return out
end

-- The mobs and NPCs of the steps at your waypoint (the next step and those
-- right by it): Flow's (o) goes over every mob there, not just the first
-- step's (QuestMarks.lua). Names, each once.
function N.HereNames(plan, yards)
    local out, seen = {}, {}
    for _, i in ipairs(N.HereStops(plan, nil, yards)) do
        for _, name in ipairs(plan[i].goal.npcs or {}) do
            if not seen[name] then seen[name] = true; out[#out + 1] = name end
        end
    end
    return out
end

function N:PlanLabels(plan)
    local out, pickups = {}, 0
    for i, s in ipairs(plan or {}) do
        local isPickup = s.goal.key:find("^pickup:") ~= nil
        if isPickup then pickups = pickups + 1 end
        -- (The quest's level: shown and coloured as the game's map filter has it, QuestLevels.lua.)
        out[i] = (isPickup and ("!" .. pickups) or tostring(i))
            .. (s.goal.level and (ns.questLevels and ns.questLevels.For(s.goal.level) or string.format(" [%d]", s.goal.level)) or "")
    end
    return out
end

-- Steps on the map: how many upcoming steps the world map and the Flow
-- Tracker show. Returns the number, or nil for all of them. Saved: nothing
-- = 1, just the next step (the default); 0 = all.
-- The whole trip is still planned (the next step depends on everything after
-- it), and the Flow Router still lists all of it so you can pick any step.
N.STOP_CHOICES = { 1, 3, 5, 10 }
function N:StopsShown()
    local saved = ns.db.nav.stopsShown
    if saved == nil then return 1 end
    local n = tonumber(saved)
    if n and n >= 1 then return math.floor(n) end
    return nil
end
-- "All steps in this area", the last choice of Steps on the map (per
-- character): the map and the Flow Tracker show the steps around you and
-- around your next step (N.HereStops: within N.HERE_YARDS) instead of your
-- next N. Somewhere with nothing else nearby that is just your next step.
-- Off unless you choose it (0.35.225: "make 'next step only' the default";
-- until then it was on unless you had picked a number). Called "All
-- objectives in this area" before: a step is Flow's word, an objective is a
-- line of a quest (docs/ARCHITECTURE.md, "Words").
N.AREA_LABEL = "All steps in this area"
function N:AreaMode()
    return ns.db.nav.stopsArea == true
end
local function stopsChanged()
    if ns.mapOverlay and WorldMapFrame and WorldMapFrame:IsShown() then pcall(ns.mapOverlay.Redraw, ns.mapOverlay) end
    if ns.routeTracker then pcall(ns.routeTracker.Refresh, ns.routeTracker) end
end
function N:SetArea(on)
    ns.db.nav.stopsArea = on and true or false
    stopsChanged()
end
-- Is step i one of the area's? (Worked out at most twice a second.)
-- (Named StopInArea: it was InArea too, the same name as "are you in a
-- quest's area" further down, which replaced it, so with "All objectives in
-- this area" on every map and Flow Tracker check failed with "attempt to
-- index local 'goal' (a number)". Lint now refuses a name defined twice.)
local areaCache = { at = -10 }
function N:StopInArea(i)
    local now = GetTime()
    if now - areaCache.at > 0.5 or areaCache.plan ~= N.plan then
        areaCache = { at = now, plan = N.plan, set = {} }
        for _, k in ipairs(N.HereStops(N.plan, self:PlayerPos())) do areaCache.set[k] = true end
    end
    return areaCache.set[i] == true
end
-- Is step i drawn? Past your limit (or outside the area) only the step you
-- point at is.
-- (Named StopVisible: it was ShowStop too, the same name as the step card
-- below, and the card's later definition replaced it, so every map and
-- Tracker call failed with "attempt to index local 'goal' (a number)".)
function N:StopVisible(i, pointed)
    if pointed then return true end
    if self:AreaMode() then return self:StopInArea(i) end
    local limit = self:StopsShown()
    return limit == nil or i <= limit
end
-- Your next n steps (nil: all of them); this turns the area choice off.
function N:SetStopsShown(n)
    n = tonumber(n)
    ns.db.nav.stopsShown = (n and n >= 1) and math.floor(n) or 0   -- (0 = all; nothing saved = 1)
    ns.db.nav.stopsArea = false
    stopsChanged()
end
function N:StopsShownLabel(n)
    if n == nil and self:AreaMode() then return N.AREA_LABEL end
    if n == nil then n = self:StopsShown() end
    if not n or n < 1 then return "All steps" end
    if n == 1 then return "Next step only" end
    return string.format("Next %d steps", n)
end

-- The kind of a step (accept, turnin, kill, collect, ...): set by the goal's
-- provider, or worked out from its key for older goals.
function N:StopKind(goal)
    if goal.kind then return goal.kind end
    local k = goal.key
    if k == "user:wp" then return "waypoint" end
    if k:find("^party:") then return "party" end
    if k:find("^pickup:") then return "accept" end
    if k:find(":done$") then return "turnin" end
    if k == "train:class" then return "classtrainer" end
    if k:find("^train:") then return "proftrainer" end
    if k:find("^skill:") then return "skill" end
    if k:find("^hearth:") then return "hearth" end
    if k == "merchant" then return "merchant" end
    return "kill"
end

-- Colour for a step: by its kind (see Theme.lua kinds).
function N:StopColor(i, goal)
    local kinds = ns.theme.kinds
    local k = kinds[self:StopKind(goal)]
    return k and k.color or ns.theme.current
end

-- "icon number text" for lists: the number is in the route colour for the step the arrow
-- points at now, grey for the rest; the text takes the kind's colour.
function N:FormatStop(i, goal, label)
    local kindName = self:StopKind(goal)
    local kind = ns.theme.kinds[kindName]
    local path = kind and kind.icon
    -- Profession steps show that profession's own icon (pickaxe, anvil...).
    local prof = goal.key:match("^train:(.+)$") or goal.key:match("^skill:(.+)$")
    if prof and ns.disposition and ns.disposition.PROF_ICON[prof] then path = ns.disposition.PROF_ICON[prof] end
    local icon = path and string.format("|T%s:13:13|t ", path) or ""
    -- Objectives of a quest you're on: the game's in-progress "?" (grey) first,
    -- so every quest step shows a quest icon (accept "!" and turn-in "?" already do).
    if goal.key:find("^%d+:%d+$") then
        icon = "|TInterface\\GossipFrame\\ActiveQuestIcon:13:13:0:0:16:16:0:16:0:16:150:150:150|t" .. icon
    end
    local numColor = (i == 1) and ns.theme.route.hex or "999999"
    local textColor = kind and kind.color.hex or "ffffff"
    -- A step in another zone, waiting until this zone is done: says where.
    local where = goal.awayZone and string.format(" |cff888888(%s, %s)|r", goal.awayZone, N.awayWords or "after this zone") or ""
    -- A step that goes after another (Needs.lua): "after Bear Form".
    if goal.after then where = where .. string.format(" |cff888888(after %s)|r", goal.after) end
    -- A class quest's step names the spell it leads to (0.35.310: "I don't see
    -- Cure Poison at all": on WoW: Forever it's "The Principal Source", not the
    -- trainer, and the row only said the quest's name).
    if goal.classQuest then where = where .. string.format(" |cff888888(for %s)|r", goal.classQuest) end
    return string.format("%s|cff%s%s|r |cff%s%s|r%s", icon, numColor, label or tostring(i),
        textColor, goal.text or goal.title or "?", where)
end

-------------------------------------------------------------------------------
-- Finish a zone before leaving it. Quest steps in your zone come before
-- steps in another zone, except:
--   * quests too low (reduced XP) or too high (3+ levels above) for you: they
--     don't hold you here
--   * a step just over the border (within BRIEF yards of you) and your class
--     trainer (a milestone): short trips that don't wait
--   * a step here that needs one over there first (its objectives are in the
--     next zone) can't hold you here either
-- The waiting steps say "(Westfall, after this zone)", and the Flow Router and
-- Tracker say "Finishing Elwynn Forest first". Setting: /flow settings.
-------------------------------------------------------------------------------

local BRIEF = 150
local zoneCache = {}
-- The zone a map belongs to (a town, cave or sub-zone map -> its zone).
function N.ZoneOf(map)
    if not map then return nil end
    local z = zoneCache[map]
    if z ~= nil then return z or nil end
    local zoneType = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3
    local m = map
    for _ = 1, 6 do
        local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(m)
        if not info then break end
        if (info.mapType or zoneType) <= zoneType then zoneCache[map] = m return m end
        if not info.parentMapID or info.parentMapID == 0 then break end
        m = info.parentMapID
    end
    zoneCache[map] = false
    return nil
end

local function zoneName(map)
    local info = map and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
    return info and info.name or "another zone"
end
N.ZoneNameOf = zoneName

-------------------------------------------------------------------------------
-- Travel by air: the flight masters this character can fly to (read when
-- you open a flight map), how long each flight took (for the whole account),
-- and the time to a step by air when that beats going on foot.
-- Assumes the flight masters you know on a continent connect, which is how
-- the game's flight network works for the paths you have learned.
-------------------------------------------------------------------------------

ns:OnLoad(function(saved)
    saved.flights = saved.flights or {}
    saved.flightTimes = saved.flightTimes or {}
end)
ns:PerCharacter("flights")

-- Flight paths fly around hills and through other flight masters: yards (in
-- a straight line) per second of flight, learned from your own flights.
N.FLIGHT_RATE = 24
N.FLIGHT_OVERHEAD = 10   -- seconds: taking off and landing
-- Only worth saying when it saves this much (fraction of the walk).
N.AIR_SAVES = 0.8

-- The flight masters on the open flight map: name, map position, and the
-- one you are standing at. Either client API.
function N.ReadTaxiNodes()
    local map = GetTaxiMapID and GetTaxiMapID()
    local nodes, here = {}, nil
    if C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and map then
        local st = Enum and Enum.FlightPathState
        for _, n in ipairs(C_TaxiMap.GetAllTaxiNodes(map) or {}) do
            local reach = not (st and n.state == st.Unreachable)
            if reach and n.name and n.position then
                -- (A vector on most clients; a plain { x, y } table on Forever.)
                local pos, x, y = n.position
                if type(pos.GetXY) == "function" then x, y = pos:GetXY() else x, y = pos.x, pos.y end
                nodes[#nodes + 1] = { name = n.name, x = x, y = y }
                if st and n.state == st.Current then here = n.name end
            end
        end
    elseif NumTaxiNodes and TaxiNodeGetType then
        for i = 1, NumTaxiNodes() do
            local kind = TaxiNodeGetType(i)
            if kind == "CURRENT" or kind == "REACHABLE" then
                local x, y = TaxiNodePosition(i)
                nodes[#nodes + 1] = { name = TaxiNodeName(i), x = x, y = y }
                if kind == "CURRENT" then here = TaxiNodeName(i) end
            end
        end
    end
    return nodes, here, map
end

-- Remembers the flight masters this character can fly to, in world yards.
function N.LearnTaxiNodes(nodes, map)
    local known = ns.db.flights
    for _, n in ipairs(nodes) do
        local cont, wx, wy = N:ToWorld(map, n.x, n.y)
        if cont and wx then known[n.name] = { cont = cont, wx = wx, wy = wy } end
    end
    N.flightGen = (N.flightGen or 0) + 1
end

-- Seconds a flight takes: what it took last time, else a guess from the
-- straight distance at the rate your flights have gone.
function N.FlightSeconds(from, to)
    local t = ns.db.flightTimes and ns.db.flightTimes[from .. ">" .. to]
    if t then return t end
    local a, b = ns.db.flights[from], ns.db.flights[to]
    if not (a and b and a.cont == b.cont) then return nil end
    return dist(a.wx, a.wy, b.wx, b.wy) / (ns.db.flightRate or N.FLIGHT_RATE) + N.FLIGHT_OVERHEAD
end

-- The known flight master nearest a spot on a continent, and how far.
local function nearestFlightMaster(cont, wx, wy)
    local best, bd
    for name, n in pairs(ns.db.flights or {}) do
        if n.cont == cont then
            local d = dist(wx, wy, n.wx, n.wy)
            if not bd or d < bd then best, bd = name, d end
        end
    end
    return best, bd
end
N.NearestFlightMaster = nearestFlightMaster

-- Each spot's nearest flight master, kept until you learn a new one (the
-- route asks this for the same spots thousands of times a plan).
local fmCache = setmetatable({}, { __mode = "k" })
local function flightMasterOf(pt)
    local c = fmCache[pt]
    local gen = N.flightGen or 0
    if c and c.gen == gen and c.wx == pt.wx and c.wy == pt.wy and c.flights == ns.db.flights then
        return c.name, c.d
    end
    local name, d = nearestFlightMaster(pt.cont, pt.wx, pt.wy)
    fmCache[pt] = { gen = gen, wx = pt.wx, wy = pt.wy, flights = ns.db.flights, name = name, d = d }
    return name, d
end

-- Running yards from spot a to spot b by flight: the walk to the flight
-- master nearest a, the flight (the yards you'd run in its seconds) and the
-- walk on from the one nearest b. nil without a flight between them. The
-- route picks steps by this when it beats the straight line (Planner: air).
-- memo (optional): { [from] = { [to] = seconds or false } }, flight times
-- already worked out in this plan.
function N.TravelYards(a, b, speed, memo)
    if not (a and b and a.wx and b.wx and a.cont == b.cont and ns.db.flights) then return nil end
    local from, d1 = flightMasterOf(a)
    local to, d2 = flightMasterOf(b)
    if not (from and to) or from == to then return nil end
    local fly
    if memo then
        local row = memo[from]
        if not row then row = {}; memo[from] = row end
        fly = row[to]
        if fly == nil then fly = N.FlightSeconds(from, to) or false; row[to] = fly end
    else
        fly = N.FlightSeconds(from, to)
    end
    if not fly then return nil end
    return d1 + d2 + fly * (speed or N.TravelSpeed())
end

-- The planner's "by flight" answer for one plan (Planner: air), or nil when
-- you know fewer than two flight masters (then nothing can be flown, and
-- the planner needn't ask). The planner asks it for thousands of pairs of
-- spots a plan, so your speed is read once and each pair of flight masters
-- is worked out once (review of pull request 20: it read your speed and
-- built a text key on every call).
function N.PlanAir()
    local n = 0
    for _ in pairs(ns.db.flights or {}) do
        n = n + 1
        if n >= 2 then break end
    end
    if n < 2 then return nil end
    local speed, memo = N.TravelSpeed(), {}
    return function(a, b) return N.TravelYards(a, b, speed, memo) end
end

-- By air to a point from where you are: { sec, from, to } when walking to a
-- flight master, flying and walking on beats walking `walkYd` at `speed`.
function N.AirRoute(p, pt, walkYd, speed)
    if not (p and pt and pt.wx and p.cont == pt.cont and walkYd) then return nil end
    speed = speed or N.TravelSpeed()
    local from, d1 = nearestFlightMaster(p.cont, p.wx, p.wy)
    local to, d2 = nearestFlightMaster(pt.cont, pt.wx, pt.wy)
    if not (from and to) or from == to then return nil end
    local fly = N.FlightSeconds(from, to)
    if not fly then return nil end
    local sec = (d1 + d2) / speed + fly
    if sec >= (walkYd / speed) * N.AIR_SAVES then return nil end
    return { sec = sec, from = from, to = to }
end

-- The flight you are on: where from and to, and when it took off.
N.taxiTrip = nil
local taxiHere   -- the flight master whose map is open
ns:On("TAXIMAP_OPENED", function()
    local ok, nodes, here, map = pcall(N.ReadTaxiNodes)
    if not ok then return end
    taxiHere = here
    if map then N.LearnTaxiNodes(nodes, map) end
end)
if hooksecurefunc and TakeTaxiNode then
    hooksecurefunc("TakeTaxiNode", function(i)
        local to = TaxiNodeName and TaxiNodeName(i)
        if to and taxiHere and to ~= taxiHere then
            N.taxiTrip = { from = taxiHere, to = to, start = GetTime() }
            if ns.db and ns.db.nav then ns.db.nav.taxiTrip = N.taxiTrip end
        end
    end)
end

-- A flight that didn't start at a flight map (a druid's ride out of
-- Moonglade starts with a word to Bunthen Plainswind): all Flow sees is that
-- you're on one. Where it lands comes from the ride you were standing by
-- (Rides.lua); how long it takes is learned the first time it's flown whole.
-- The trip is kept through a /reload (GetTime carries on), so reloading in
-- the air doesn't lose it. Called on every arrow update.
--   onTaxi: are you on a flight now; now: GetTime();
--   rideHere() -> the ride of the zone you're in, or nil; saved: ns.db.nav
N.TAXI_MAX = 1200   -- no flight is longer: an older saved trip is stale
local groundSeen = false
function N.NoteTaxi(onTaxi, now, rideHere, saved)
    if not onTaxi then
        groundSeen = true
        if saved and saved.taxiTrip and not N.taxiTrip then saved.taxiTrip = nil end
        return nil
    end
    if N.taxiTrip then return N.taxiTrip end
    local kept = saved and saved.taxiTrip
    if type(kept) == "table" and type(kept.start) == "number" and kept.start <= now and now - kept.start < N.TAXI_MAX then
        N.taxiTrip = kept
        return kept
    end
    local r = rideHere and rideHere() or nil
    -- (partial: first seen in the air, after a login: its time isn't the flight's)
    N.taxiTrip = { from = r and r.name or "?", to = r and r.toName or nil, start = now, partial = not groundSeen or nil }
    if saved then saved.taxiTrip = N.taxiTrip end
    return N.taxiTrip
end
function N._TaxiReset(seen) N.taxiTrip, groundSeen = nil, seen and true or false end   -- (tests)

-- On a flight you can't steer, so the arrow's two lines are the flight's.
--   to: where it lands (nil: Flow doesn't know); left: seconds to landing
--   (nil: not learned yet); nextText: your next step
function N.FlightWords(to, left, nextText)
    local title = to and ("Flying to " .. to) or "On a flight"
    local sub = left and ("landing in " .. N.FormatSeconds(left)) or "landing time not known yet"
    if nextText and nextText ~= "" then sub = sub .. ", then: " .. nextText end
    return title, sub
end

-- Landed: remember how long it took, and learn how fast flights go.
function N.Landed(trip, elapsed)
    if not (trip and trip.to and not trip.partial and elapsed and elapsed > 5) then return end
    ns.db.flightTimes[trip.from .. ">" .. trip.to] = math.floor(elapsed + 0.5)
    local a, b = ns.db.flights[trip.from], ns.db.flights[trip.to]
    if a and b and a.cont == b.cont and elapsed > N.FLIGHT_OVERHEAD then
        local rate = dist(a.wx, a.wy, b.wx, b.wy) / (elapsed - N.FLIGHT_OVERHEAD)
        if rate > 5 and rate < 100 then
            ns.db.flightRate = ns.db.flightRate and (ns.db.flightRate * 0.7 + rate * 0.3) or rate
        end
    end
end
ns:On("PLAYER_CONTROL_GAINED", function()
    local trip = N.taxiTrip
    if trip and not (UnitOnTaxi and UnitOnTaxi("player")) then
        N.taxiTrip = nil
        if ns.db and ns.db.nav then ns.db.nav.taxiTrip = nil end
        N.Landed(trip, GetTime() - trip.start)
    end
end)

-- The arrow's words while you're on a flight (title, sub), or nil on the ground.
function N.FlightNow(nextText)
    local trip = N.taxiTrip
    if not (trip and UnitOnTaxi and UnitOnTaxi("player")) then return nil end
    local left = N.TaxiLeft()
    return N.FlightWords(trip.to, left, nextText)
end

-- On a flight: seconds until you land, and where.
function N.TaxiLeft()
    local trip = N.taxiTrip
    if not (trip and UnitOnTaxi and UnitOnTaxi("player")) then return nil end
    if not trip.to then return nil end
    local total = N.FlightSeconds(trip.from, trip.to)
    if not total then return nil, trip.to end
    return math.max(1, total - (GetTime() - trip.start)), trip.to
end

-- The walk to a step crosses into another zone: yards to that zone's edge
-- along the arrow's line, and the zone's map (nil: it stays in this zone).
-- at(yd) -> the zone at that distance along the line.
function N.FirstChange(len, at, step)
    step = step or 50
    local z0 = at(0)
    local lo, hi
    local d = step
    while d < len + step do
        local dd = math.min(d, len)
        local z = at(dd)
        if z and z ~= z0 then lo, hi = dd - step, dd break end
        lo = dd
        d = d + step
    end
    if not hi then return nil end
    lo = math.max(0, lo)
    for _ = 1, 6 do
        local mid = (lo + hi) / 2
        local z = at(mid)
        if z and z ~= z0 then hi = mid else lo = mid end
    end
    return hi, at(hi)
end

-- The continent's map above a zone's map.
local function continentMap(map)
    local want = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or 2
    local m = map
    for _ = 1, 6 do
        local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(m)
        if not info then return nil end
        if info.mapType == want then return m end
        if not info.parentMapID or info.parentMapID == 0 then return nil end
        m = info.parentMapID
    end
end

-- The zone under a world spot on a continent.
local function zoneAtWorld(cont, contMap, wx, wy)
    if not (C_Map.GetMapPosFromWorldPos and C_Map.GetMapInfoAtPosition) then return nil end
    local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, cont, CreateVector2D(wx, wy), contMap)
    if not (ok and pos) then return nil end
    local x, y = pos:GetXY()
    if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    local info = C_Map.GetMapInfoAtPosition(contMap, x, y)
    return info and N.ZoneOf(info.mapID)
end

-- Yards to the next zone on the way to a step in another zone, and its
-- name. Worked out again only after you've moved a bit, one answer kept per
-- step (a single shared one missed every time with two steps in other
-- zones: ~100 zone lookups a call, several calls a second).
local borderCache = setmetatable({}, { __mode = "k" })
function N.NextZone(p, pt)
    if not (p and pt and pt.wx and p.cont == pt.cont) then return nil end
    local zone, goal = N.ZoneOf(p.map), N.ZoneOf(pt.map)
    if not (zone and goal) or zone == goal then return nil end
    local c = borderCache[pt] or {}
    if c.wx and dist(c.wx, c.wy, p.wx, p.wy) < 20 then return c.yd, c.name end
    local contMap = continentMap(p.map)
    local yd, z
    if contMap then
        local len = dist(p.wx, p.wy, pt.wx, pt.wy)
        local ux, uy = (pt.wx - p.wx) / len, (pt.wy - p.wy) / len
        yd, z = N.FirstChange(math.min(len, 5000), function(d)
            return zoneAtWorld(p.cont, contMap, p.wx + ux * d, p.wy + uy * d)
        end)
    end
    c = { wx = p.wx, wy = p.wy, yd = yd, name = z and zoneName(z) }
    borderCache[pt] = c
    return yd, c.name
end

-- The time part of a step's distance line (with a space in front, or ""):
--   on a flight: "~1m 10s (landing at Sentinel Hill in ~50s)"
--   quicker by air: "~2m 10s by air"
--   on foot: "~3m 40s", and, for a step in another zone, "(Westfall in ~40s)".
-- (Each step's text is kept a second: the arrow, its drawer and the
-- profession arrow ask ten times a second each.)
local travelCache = setmetatable({}, { __mode = "k" })
function N.TravelText(p, pt, yd)
    local now = GetTime()
    local c = pt and travelCache[pt]
    if c and now - c.at < 1 then return c.text end
    local text = N.TravelTextNow(p, pt, yd)
    if pt then travelCache[pt] = { at = now, text = text } end
    return text
end
function N.TravelTextNow(p, pt, yd)
    local speed = N.TravelSpeed()
    local left, landing = N.TaxiLeft()
    if landing then
        local node = ns.db.flights[landing]
        local walk = (node and pt and pt.wx and node.cont == pt.cont) and dist(node.wx, node.wy, pt.wx, pt.wy) / speed or 0
        if not left then return string.format(" (flying to %s)", landing) end
        return string.format(" %s (landing at %s in %s)", N.FormatSeconds(left + walk), landing, N.FormatSeconds(left))
    end
    local air = N.AirRoute(p, pt, yd, speed)
    if air then return " " .. N.FormatSeconds(air.sec) .. " by air" end
    local out = N.TravelSuffix(yd, speed)
    local okZ, zyd, zname = pcall(N.NextZone, p, pt)
    if okZ and zyd and zname and zyd < (yd or 0) then
        out = out .. string.format(" (%s in %s)", zname, N.FormatTravel(zyd, speed))
    end
    return out
end

local function isQuestStop(key)
    return key:find("^%d+:") ~= nil or key:find("^pickup:") ~= nil or key:find("^help:") ~= nil
end

-- Which steps hold you in `zone` (here) and which wait (away); nil, nil when
-- there's nothing to hold you or nowhere else to go. zone: one zone, or a set
-- of them ({ [zone] = true }: the zones you ticked, "Finish the selected
-- zones first").
function N.AreaSplit(list, zone, p, zoneOf)
    local here, away, byKey = {}, {}, {}
    local function inSet(z)
        if type(zone) == "table" then return z ~= nil and zone[z] == true end
        return z == zone
    end
    for _, g in ipairs(list) do
        byKey[g.key] = g
        local inZone, nearest = false, nil
        for _, pt in ipairs(g.points or {}) do
            if pt.map and inSet(zoneOf(pt.map)) then inZone = true end
            if p and pt.wx and pt.cont == p.cont then
                local d = dist(p.wx, p.wy, pt.wx, pt.wy)
                if not nearest or d < nearest then nearest = d end
            end
        end
        if inZone then
            local tooHigh = (g.levelsAbove or 0) >= 3
            local tooLow = g.share ~= nil and g.share < 1
            if isQuestStop(g.key) and not (tooHigh or tooLow or g.optional) then here[g.key] = true end
        elseif g.points and #g.points > 0 then
            if not ((nearest and nearest < BRIEF) or g.milestone) then away[g.key] = true end
        end
    end
    local changed = true
    while changed do
        changed = false
        for key in pairs(here) do
            for _, dep in ipairs(byKey[key].deps or {}) do
                if away[dep] then here[key] = nil; away[key] = true; changed = true; break end
            end
        end
    end
    if not (next(here) and next(away)) then return nil, nil end
    return here, away
end

-------------------------------------------------------------------------------
-- Choosing the route. N.selection = { first = goal key, tour = { [key] = true } }
--   first : the next step you picked (its ^ in the Flow Router, "Go here
--           first"). That makes it a Custom route (orange): this step first,
--           with the (o), the rest planned after it. It stays Custom until you
--           pick Most XP or Shortest again (or click the (o) of your pick).
--   tour  : steps that must all come before anything else (picking one of the
--           "!" quest pickups puts all pickups first: !3 -> the other pickups
--           -> then the normal plan)
-- Your own waypoint (Waypoint.lua) is NOT part of the route: see
-- N.WaypointChoice (the arrow follows it in green while it's set).
-------------------------------------------------------------------------------

N.planVersion = 0

-- This hub's business before heading out, like a walkthrough: turn in every
-- finished quest near you, train if you're standing at your trainer (below),
-- then pick up the quests here (nearest first,
-- capped at the free quest log slots; each turn-in frees one). Turn-ins used
-- to be left out, so a hand-in right next to you waited behind every pickup.
local HUB_RADIUS = 250  -- yards
local function ready(g, present)
    for _, dep in ipairs(g.deps or {}) do if present[dep] then return false end end
    return true
end

-- Training is hub business too, but only when you're right at the trainer
-- (in town, N.TRAIN_NEAR yards): Yang stood next to the trainer with
-- training as step 7. Wider (0.35.98's 300 yards) pulled you off the mobs
-- you were killing for a quest. Not when you can't pay for any of it (cost),
-- nor when your trainer, seen at this level, has nothing left to learn (a
-- spell Flow lists that the trainer doesn't have would keep you there).
N.TRAIN_NEAR = 60
-- Anything to learn at your class trainer now? Not seen at this level: yes,
-- as far as Flow knows. Seen: its own list must still show something
-- "available". (0.35.115 skipped training as soon as you'd opened the
-- trainer at your level, bought or not: Yang still had Blessing of Might.)
function N.TrainerHasSomething(tr, level)
    if not (tr and tr.seenAt == level) then return true end
    for _, s in ipairs(tr.services or {}) do
        if s.category == "available" then return true end
    end
    return false
end
-- What a goal is for the hub's business at distance d: "turnin", "pickup",
-- "train" or nil (not this hub's business). nothingToLearn: your class
-- trainer has nothing left for you (N.TrainerHasSomething).
function N.HubBusiness(g, d, present, nothingToLearn, radius)
    if not d then return nil end
    -- (Not while a step it goes after is still on the route: training after
    -- the Bear Form quest, Needs.lua. The town's errands go first and would
    -- otherwise pull it ahead of what it waits for.)
    if g.key:find("^train:") then
        if g.cost or (g.key == "train:class" and nothingToLearn) or not ready(g, present) then return nil end
        return d <= N.TRAIN_NEAR and "train" or nil
    end
    if d > (radius or HUB_RADIUS) then return nil end
    if g.key:find(":done$") and ready(g, present) then return "turnin" end
    if (g.provider == "pickups" or (g.provider == "dungeon" and g.key:find("^pickup:"))) and ready(g, present) then   -- (a prepared dungeon run's too)
        return "pickup"
    end
    return nil
end

function N:PickupKeys(radius)
    local p = self:PlayerPos()
    if not p then return nil end
    local present = {}
    for _, g in ipairs(goals) do present[g.key] = true end
    local trained = not N.TrainerHasSomething(ns.db.trainer, UnitLevel("player"))
    local near, turnins, nTurnins = {}, {}, 0
    for _, g in ipairs(goals) do
        -- (Distances only for what can be hub business: some goals have many spawn points.)
        if g.provider == "pickups" or g.provider == "dungeon" or g.key:find(":done$") or g.key:find("^train:") then
            local _, d = nearestPoint(g, p)
            local kind = N.HubBusiness(g, d, present, trained, radius)
            -- Turn-ins and training take no quest log slot; each turn-in frees one.
            if kind == "turnin" or kind == "train" then turnins[#turnins + 1] = { key = g.key, d = d } end
            if kind == "turnin" then nTurnins = nTurnins + 1 end
            if kind == "pickup" then near[#near + 1] = { key = g.key, d = d } end
        end
    end
    table.sort(near, function(a, b) return a.d < b.d end)
    local free = (ns.quests.FreeSlots and ns.quests:FreeSlots() or 20) + nTurnins
    local t, any = {}, false
    for _, e in ipairs(turnins) do t[e.key] = true; any = true end
    for i = 1, math.min(#near, free) do t[near[i].key] = true; any = true end
    return any and t or nil
end

function N:Select(key)
    -- On a shared party route, choosing edits the shared route instead:
    -- a shared step moves to the front; anything else is added at the front.
    if key and ns.party and ns.party:Following() then
        local id = key:match("^party:(.+)$")
        if id then
            ns.party:MoveFirst(id)
        else
            for _, g in ipairs(goals) do
                if g.key == key then ns.party:AddGoal(g) break end
            end
        end
        return
    end
    local tour
    if key and key:find("^pickup:") then tour = self:PickupKeys() end
    self.selection = key and { first = key, tour = tour } or nil
    ns.db.nav.selectedKey = key  -- kept across /reload
    -- Picking a step: Custom route (orange). Clearing it: back to optimised
    -- (your last objective).
    if key then
        ns.db.nav.sorter = "custom"
    elseif ns.db.nav.sorter == "custom" or ns.db.nav.sorter == "selected" then
        ns.db.nav.sorter = ns.xpValue and ns.xpValue:Base() or "distance"
    end
    ns.theme:UpdateRoute()
    self.planDirty = true
    pinnedKey = nil
end

function N:ClearSelection() self:Select(nil) end

-- Open what a step is about, without changing the route (tracker clicks,
-- arrow menu): a quest in your log opens in the quest log; anything else
-- opens the world map on that step, highlighted.
local function questLogIndex(id)
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then return C_QuestLog.GetLogIndexForQuestID(id) end
    if GetQuestLogIndexByID then
        local i = GetQuestLogIndexByID(id)
        if i and i > 0 then return i end
    end
end

-- One readable tooltip for any step (map pins, map list, tracker, minimap):
--   title (gold) with the step type icon and level
--   WHAT TO DO: the objective or task, large and white
--   quest objectives with progress (done ones green), the quest text (short)
--   details from the step's provider, XP, blocked reason
--   footer hint (grey)
local function questText(id)
    local q = ns.quests.QuestieGet and ns.quests:QuestieGet("GetQuest", id)
    local d = q and (q.Description or q.objectivesText)
    if type(d) == "table" then d = table.concat(d, " ") end
    if type(d) == "string" and d ~= "" then return d end
end

-- Clickable things look clickable: the hand (interact) cursor while hovering
-- anything a click does something for (route rows, map points...).
function N:ClickCursor(on)
    if on then
        if SetCursor then pcall(SetCursor, "INTERACT_CURSOR") end
    elseif ResetCursor then
        ResetCursor()
    end
end

-- Pure: should a tooltip line be wrapped? A bullet ("- ...") and a short
-- line are written as they are, so they stay on one line; a sentence wraps.
N.WRAP_FROM = 60
function N.WrapLine(text)
    if type(text) ~= "string" then return true end
    if text:find("^%- ") then return false end
    return #text > N.WRAP_FROM
end
-- Pure: a footer of several hints ("Click: open it. Right-click: menu.") as
-- one short line each.
function N.FooterLines(footer)
    local out = {}
    for part in tostring(footer or ""):gmatch("[^%.]+%.?") do
        part = part:gsub("^%s+", ""):gsub("%s+$", "")
        if part ~= "" and part ~= "." then out[#out + 1] = (part:gsub("%.$", "")) end
    end
    return out
end
function N:FillTooltip(tt, goal, footer)
    local kind = ns.theme.kinds[self:StopKind(goal)]
    local icon = kind and string.format("|T%s:16:16|t ", kind.icon) or ""
    local title = goal.title or goal.text or "?"
    tt:AddLine(icon .. title .. (goal.level and (ns.questLevels and ns.questLevels.For(goal.level, "  ") or string.format("  |cff999999[%d]|r", goal.level)) or ""), 1, 0.82, 0.25, true)
    -- (What the level's colour says: too high, full XP, dropping, none.)
    if goal.level and ns.questLevels then
        local says, hex = ns.questLevels.Says(goal.level)
        if says then tt:AddLine(string.format("|cff%sLevel %d|r: %s", hex, goal.level, says), 0.8, 0.8, 0.8, true) end
    end
    -- What to do: the line your eyes should land on.
    local task = goal.text or title
    if goal.title and task:sub(1, #goal.title + 2) == goal.title .. ": " then task = task:sub(#goal.title + 3) end
    tt:AddLine(" ")
    tt:AddLine(task, 1, 1, 1, true)
    if goal.blockedBy then tt:AddLine("Blocked: " .. goal.blockedBy, 1, 0.45, 0.45, true) end
    -- Inside a cave or building (learned from your trails): say so, the arrow
    -- goes through the entrance.
    local pt = N:Spot(goal)
    if pt and pt.wx and pt.cont and N:Inside(pt.cont, pt.wx, pt.wy) then
        tt:AddLine("Inside (cave or building): the arrow takes you through the entrance.", 0.6, 0.8, 1, true)
    end
    local id = tonumber(goal.key:match("^(%d+):")) or tonumber(goal.key:match("^pickup:(%d+)$"))
    if id then
        local objs = C_QuestLog and C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(id)
        if objs and #objs > 0 then
            tt:AddLine(" ")
            for _, o in ipairs(objs) do
                if o.text then
                    if o.finished then tt:AddLine("  " .. o.text, 0.4, 0.9, 0.4, true)
                    else tt:AddLine("  " .. o.text, 0.85, 0.85, 0.85, true) end
                end
            end
        end
        local text = questText(id)
        if text then
            if #text > 260 then text = text:sub(1, 257) .. "..." end
            tt:AddLine(" ")
            tt:AddLine(text, 0.7, 0.7, 0.7, true)
        end
    end
    local first = true
    for _, d in ipairs(goal.details or {}) do
        if not d:find("^Quest: ") and not d:find("^Objective: ") then
            if first then tt:AddLine(" "); first = false end
            if d:find("^XP: ") then tt:AddLine(d, 0.64, 0.21, 0.93, true)
            else tt:AddLine(d, 0.8, 0.8, 0.8, N.WrapLine(d)) end
        end
    end
    if footer then
        tt:AddLine(" ")
        for _, hint in ipairs(N.FooterLines(footer)) do tt:AddLine(hint, 0.55, 0.55, 0.55, N.WrapLine(hint)) end
    end
end

-- Clicking a step (Flow Router row or pin, tracker row, map area) opens
-- Flow's own card for it next to what you clicked (N:ShowStop, below). The
-- game's quest log, which folds the Flow Router away, is a link on the card.
function N:OpenStop(goal, anchor)
    if not goal then return end
    if N.ShowStop then return N:ShowStop(goal, anchor) end
    return N:OpenInGame(goal)
end

-- A step in the game's own windows, WITHOUT calling the game's map or
-- quest-log functions from Flow's code (QuestMapFrame_OpenToQuestDetails,
-- ToggleWorldMap, SetMapID...): those run the map from add-on code and taint
-- it, and in a later fight the map's own buttons get blocked (0.35.47). So:
-- the quest is selected in your log (you open it with L or M, so the game
-- runs its own window), and Flow's map layer highlights the step for the
-- next 20 seconds.
-- The map a step is on: where the route goes for it, else its first spot.
function N.GoalMap(goal)
    if not goal then return nil end
    for _, s in ipairs(N.plan or {}) do
        if s.goal == goal or (s.goal and s.goal.key == goal.key) then
            if s.point and s.point.map then return s.point.map end
        end
    end
    local pt = goal.points and goal.points[1]
    return pt and pt.map or nil
end

function N:OpenInGame(goal)
    if not goal then return end
    local id = tonumber(goal.key:match("^(%d+):"))
    if id and questLogIndex(id) and C_QuestLog and C_QuestLog.SetSelectedQuest then
        pcall(C_QuestLog.SetSelectedQuest, id)
    end
    if ns.mapOverlay and ns.mapOverlay.Focus then ns.mapOverlay:Focus(goal.key, 20) end
end

-- The constraints for planning, dropping any that refer to finished goals.
function N:Options(sel)
    sel = sel or self.selection or {}
    local present = {}
    for _, g in ipairs(goals) do present[g.key] = true end
    local first = sel.first and present[sel.first] and sel.first or nil
    local tour
    if sel.tour then
        tour = {}
        for k in pairs(sel.tour) do if present[k] then tour[k] = true end end
        if not next(tour) then tour = nil end
    end
    -- (Not in the first seconds after login: quest data may not be in yet, and
    -- a step chosen before the reload would be dropped too early.)
    -- Your pick is done: the route carries on from here, still a Custom route
    -- (orange) until you choose Most XP or Shortest again.
    if not first and not tour and self.selection and GetTime() - (N.loadedAt or 0) > 20 then
        self.selection = nil
        ns.db.nav.selectedKey = nil
    end
    -- Default (nothing chosen): pick up the quests in this hub before heading
    -- out, like a walkthrough does, as long as your quest log has room.
    if not tour and not sel.first and self:Mode() ~= "quests" then
        tour = self:PickupKeys()
    end
    -- A dungeon run you prepared (the key): its pickups, then its entrance,
    -- come first, unless you picked a step yourself.
    if not sel.first and not sel.tour and ns.dungeons and ns.dungeons:Prepared() then
        for _, g in ipairs(goals) do
            if g.provider == "dungeon" and not g.optional then   -- (not the "only if you pass by" ones)
                tour = tour or {}
                tour[g.key] = true
            end
        end
    end
    -- (Party members' quests, PartyHelp.lua, need no order of their own:
    -- "Combined" is one optimal route over everyone's steps, and "Just
    -- <name>'s" leaves only theirs on the route.)
    -- Shared party route: its steps come first, in the shared order (their
    -- deps chain), before your own goals.
    if ns.party and ns.party:Following() then
        local partyFirst
        for _, s in ipairs(ns.party:Stops()) do
            local k = "party:" .. s.id
            if present[k] then
                tour = tour or {}
                tour[k] = true
                partyFirst = partyFirst or k
            end
        end
        if partyFirst then first = partyFirst end
    end
    -- Finish the zones you ticked first, else this zone before leaving it
    -- (see N.AreaSplit).
    local here, away
    local p = self:PlayerPos()
    local zone = p and N.ZoneOf(p.map)
    local picked = N.ZonesFirstOn() and N.SelectedZones() or nil
    if picked and next(picked) then
        here, away = N.AreaSplit(goals, picked, p, N.ZoneOf)
        N.awayWords = "after your zones"
    elseif zone and ns.db.nav.zoneFirst ~= false then
        here, away = N.AreaSplit(goals, zone, p, N.ZoneOf)
        N.awayWords = "after this zone"
    end
    for _, g in ipairs(goals) do
        local awayZone
        if away and away[g.key] then
            local pt = g.points and g.points[1]
            awayZone = zoneName(N.ZoneOf(pt and pt.map))
        end
        g.awayZone = awayZone
    end
    if here and away then
        N.zoneNote = picked and N.PickedNote(picked, zoneName) or ("Finishing " .. zoneName(zone) .. " first")
    else
        N.zoneNote = nil
    end
    -- Set your home before a spell casts you far from it: a step that's a
    -- travel spell away waits for the "Set hearthstone" step here (Hearth.lua).
    if p and ns.hearth and ns.hearth.BeforeTrips and ns.travelSpells then
        pcall(ns.hearth.BeforeTrips, goals, function(pt) return ns.travelSpells.Spell(p, pt) ~= nil end)
    end
    return { first = first, tour = tour, here = here, away = away, air = N.PlanAir(), walk = ns.gates and ns.gates.PlanWalk() or nil,
             port = ns.travelSpells and ns.travelSpells.PlanPort() or nil,
             ride = ns.rides and ns.rides.PlanRide() or nil,
             -- (Trips you've made, and how long they took: Legs.lua.)
             legs = ns.legs and ns.legs.PlanLegs() or nil }
end

-- A plan as if you had picked this step (for previews on the map / advice list).
-- Previews are cached until the main route is re-planned (goals changed or
-- every few seconds), so hovering checkpoints doesn't re-plan every frame.
local previewCache, previewVersion = {}, -1
function N:PlanFor(key)
    if previewVersion ~= self.planVersion then
        wipe(previewCache)
        previewVersion = self.planVersion
    end
    local cacheKey = key or "-"
    local hit = previewCache[cacheKey]
    if hit ~= nil then return hit or nil end
    local p = self:PlayerPos()
    if not (p and ns.planner) then return nil end
    local tour = key and key:find("^pickup:") and self:PickupKeys() or nil
    local ok, result = pcall(ns.planner.Plan, ns.planner, p, goals, self:Options({ first = key, tour = tour }))
    previewCache[cacheKey] = (ok and result) or false
    return ok and result or nil
end

-- The plan: the whole trip in order (see Planner.lua). Re-planned when goals
-- change, and every few seconds as you move.
local plan, planAt = nil, 0

-- Every step by (weighted) distance from you. Only needed for a step you
-- pinned, or when there's no plan: not on every arrow tick (it was ~90
-- steps x up to 80 spots, 10 times a second).
local function rank(p)
    local ranked = {}
    for _, goal in ipairs(goals) do
        local pt, d = nearestPoint(goal, p)
        if pt then ranked[#ranked + 1] = { goal = goal, point = pt, d = d, score = d * (goal.weight or 1) } end
    end
    table.sort(ranked, function(a, b) return a.score < b.score end)
    return ranked
end

-- Is any step on your continent at all? (Else there's nothing to plan.)
-- Known again when the steps are gathered, you change continent, or after 5 s.
local reach = { at = -10 }
local function anyReachable(p)
    if reach.goals == goals and reach.cont == p.cont and GetTime() - reach.at < 5 then return reach.yes end
    local yes = false
    for _, goal in ipairs(goals) do
        if goal.anywhere then yes = true break end
        for _, pt in ipairs(goal.points or {}) do
            if pt.wx and pt.cont == p.cont then yes = true break end
        end
        if yes then break end
    end
    reach.goals, reach.cont, reach.yes, reach.at = goals, p.cont, yes, GetTime()
    return yes
end

-- The arrow's words when nothing here is left but a dungeon run's steps are
-- on another continent (worked out at most every 2 s: it reads every step).
local away = { at = -10 }
local function awayHint(p)
    if not (ns.dungeons and ns.dungeons.AwayHint) then return nil end
    if away.goals == goals and away.cont == p.cont and GetTime() - away.at < 2 then return away.text, away.sub end
    local ok, text, sub = pcall(ns.dungeons.AwayHint, ns.dungeons, goals, p.cont, UnitFactionGroup("player"))
    if not ok then text, sub = nil, nil end
    away.goals, away.cont, away.at, away.text, away.sub = goals, p.cont, GetTime(), text, sub
    return text, sub
end

local function choose(p)
    -- "Do it where you stand" steps (e.g. crafting with no station) follow you.
    for _, goal in ipairs(goals) do
        if goal.anywhere then goal.points = { { cont = p.cont, wx = p.wx, wy = p.wy, map = p.map, x = p.x, y = p.y } } end
    end
    if not anyReachable(p) then N.plan = nil return nil end
    if pinnedKey then
        for _, r in ipairs(rank(p)) do if r.goal.key == pinnedKey then return r end end
        pinnedKey = nil
    end

    -- Re-plan when something changed, or every 8 s only if you've moved 30+
    -- yards (standing still, the order can't change). Each plan is ~20-30 ms,
    -- enough to feel as a stutter, so it shouldn't run for nothing (/flow perf).
    local now = GetTime()
    local moved = not N.planPos or N.planPos.cont ~= p.cont
        or dist(p.wx, p.wy, N.planPos.wx, N.planPos.wy) > 30
    if ns.planner and (N.planDirty or not plan or (now - planAt > 8 and moved) or now - planAt > 60) then
        -- On the party route, everyone follows the same route: one member
        -- plans it and the rest take that order and those spots (PartyHelp.lua).
        local shared = ns.partyHelp and ns.partyHelp.SharedPlan and ns.partyHelp:SharedPlan(p, goals)
        local ok, result
        if shared then ok, result = true, shared
        else ok, result = pcall(ns.planner.Plan, ns.planner, p, goals, N:Options()) end
        plan = ok and result or nil
        if not ok then N.lastError = "planner: " .. tostring(result) end
        if ok and not shared and ns.partyHelp and ns.partyHelp.Publish then pcall(ns.partyHelp.Publish, ns.partyHelp, plan) end
        planAt, N.planDirty = now, false
        N.planPos = { cont = p.cont, wx = p.wx, wy = p.wy }
        N.planVersion = N.planVersion + 1
    end
    N.plan = plan
    if plan and plan[1] then
        local s = plan[1]
        return { goal = s.goal, point = s.point, d = dist(p.wx, p.wy, s.point.wx, s.point.wy) }
    end
    -- No plan (no planner, or it failed): the nearest step.
    local ranked = rank(p)
    if #ranked == 0 then return nil end
    -- Sticky: don't flip between goals unless the new one is clearly closer.
    if current then
        for _, r in ipairs(ranked) do
            if r.goal.key == current.goal.key then
                if ranked[1].score < r.score * 0.7 then return ranked[1] end
                return r
            end
        end
    end
    return ranked[1]
end

-- The profession steps' own route (N.profGoals), planned like the quest
-- route: again when something changed, or every 8 s once you've moved.
-- Returns { goal, point, d } for the faint arrow, or nil.
local profPlan, profPlanAt = nil, 0
local function chooseProf(p)
    local list = N.profGoals
    if not (ns.planner and list and #list > 0) then N.profPlan, profPlan = nil, nil return nil end
    for _, goal in ipairs(list) do
        if goal.anywhere then goal.points = { { cont = p.cont, wx = p.wx, wy = p.wy, map = p.map, x = p.x, y = p.y } } end
    end
    local now = GetTime()
    local moved = not N.profPos or N.profPos.cont ~= p.cont
        or dist(p.wx, p.wy, N.profPos.wx, N.profPos.wy) > 30
    if N.profDirty or not profPlan or (now - profPlanAt > 8 and moved) or now - profPlanAt > 60 then
        local ok, result = pcall(ns.planner.Plan, ns.planner, p, list, {})
        profPlan = ok and result or nil
        if not ok then N.lastError = "profession route: " .. tostring(result) end
        profPlanAt, N.profDirty = now, false
        N.profPos = { cont = p.cont, wx = p.wx, wy = p.wy }
    end
    N.profPlan = profPlan
    local s = profPlan and profPlan[1]
    if not s then return nil end
    return { goal = s.goal, point = s.point, d = dist(p.wx, p.wy, s.point.wx, s.point.wy) }
end

-- Where the minimap dot goes. It marks the step, never you:
--  * in a quest's area the dot goes away and the area itself shows (Flow's
--    cloud on the minimap, or the game's own quest zone when that's off);
--  * a "do it where you stand" step has no dot (its spot is wherever you are);
--  * once you're at a step the dot stays on the spot you reached, even if a
--    nearer spot of the same step turns up as you walk around.
-- choice: from choose(); here: arrived. Returns the point, or nil (no dot).
N.dotHeld = {}
function N.DotPoint(choice, here)
    local held = N.dotHeld   -- key, point: the spot you arrived at
    if not choice then held.key, held.point = nil, nil return nil end
    local g = choice.goal
    if g.anywhere or (here and g.area) then return nil end
    if not here then held.key, held.point = nil, nil return choice.point end
    if held.key ~= g.key or not held.point then held.key, held.point = g.key, choice.point end
    return held.point
end

-- Your own waypoint (Waypoint.lua: Ctrl/Alt-click the map, /way, "Point the
-- arrow here"). It isn't a route step: while it's set the arrow points at it,
-- in the waypoint green, the map draws a green line to it, and the route
-- carries on unchanged underneath. It clears itself when you get there.
-- Returns { goal, point, d, waypoint = true } like choose(), or nil (none set,
-- or it's on another continent).
local wpGoal = { key = "user:wp", title = "Your waypoint", points = {}, kind = "waypoint" }
local wpCache = {}
function N.WaypointChoice(p)
    local w = ns.waypoint and ns.waypoint:Get()
    if not (w and w.map and w.x and p) then return nil end
    if wpCache.map ~= w.map or wpCache.x ~= w.x or wpCache.y ~= w.y then
        local cont, wx, wy = N:ToWorld(w.map, w.x, w.y)
        wpCache = { map = w.map, x = w.x, y = w.y, pt = wx and { map = w.map, x = w.x, y = w.y, cont = cont, wx = wx, wy = wy } }
    end
    local pt = wpCache.pt
    if not pt or pt.cont ~= p.cont then return nil end
    wpGoal.text = "Your waypoint" .. (w.note and (": " .. w.note) or "")
    wpGoal.details = { string.format("You set this at %.1f, %.1f.", w.x * 100, w.y * 100),
                       "Not part of the route: it clears when you get there (or the X in the Flow Router), then the arrow is back on the route." }
    wpGoal.points[1] = pt
    return { goal = wpGoal, point = pt, d = dist(p.wx, p.wy, pt.wx, pt.wy), waypoint = true }
end

-- Decide where the arrow points: a trail point along a known path, or the
-- goal itself. Returns wx, wy, how ("path"/"direct"), routeLength.
local lastRouteAt = 0
-- Entrances you've walked through (outdoors -> indoors), per continent.
function N:AddEntrance(p)
    local list = ns.db.nav.entrances or {}
    ns.db.nav.entrances = list
    for _, e in ipairs(list) do
        if e.cont == p.cont and dist(e.wx, e.wy, p.wx, p.wy) < 30 then return end
    end
    list[#list + 1] = { cont = p.cont, wx = floor(p.wx), wy = floor(p.wy), map = p.map }
end

-- Is a point inside (a cave or building)? Known once you've walked there:
-- an indoor trail point within 35 yd.
function N:Inside(cont, wx, wy)
    local g = graph(cont)
    if not g.indoor then return false end
    local n = nearestNode(cont, wx, wy, 35)
    return n ~= nil and g.indoor[n] == true
end

-- Nearest known entrance to a point (within 250 yd).
local function entranceNear(cont, wx, wy)
    local best, bestD
    for _, e in ipairs(ns.db.nav.entrances or {}) do
        if e.cont == cont then
            local d = dist(e.wx, e.wy, wx, wy)
            if d < 250 and (not bestD or d < bestD) then best, bestD = e, d end
        end
    end
    return best
end

-- Trails you've walked are used only where they help:
--   * always for a step inside a cave or building while you're outside
--     (straight at it leads on top of the cave): the trail in, or the entrance
--   * outdoors only with "Arrow follows paths you've walked" on, and only a
--     trail at most 1.5x the straight line (it used to take one up to 4x
--     longer, so the arrow wandered off along an old detour)
-- Otherwise the arrow points straight at the step.
local PATH_DETOUR = 1.5
local LOOKAHEAD = 35   -- yards: point at the furthest trail point this close, not the next one
function N.TrailWorthIt(trail, direct, inside)
    return trail < direct * (inside and 20 or PATH_DETOUR)
end
-- Along a trail: the furthest point (from idx on) within `ahead` yards of
-- you, so the arrow leads forward instead of back at a point you passed.
-- pts: { {x, y} }, returns an index.
function N.Carrot(pts, idx, px, py, ahead)
    local best = idx
    for i = idx, #pts do
        if dist(px, py, pts[i][1], pts[i][2]) <= ahead then best = i
        elseif i > idx + 1 then break end
    end
    return best
end

-- A trail is followed only while it heads roughly where the step is. A trail
-- up to half again as long as the straight line may set off well to one
-- side, or backwards to its nearest point, before it bends round: "the arrow
-- will point the wrong way for some time and then all of a sudden flip to
-- being right" (0.35.195; trails had become the default that day). In open
-- country the straight line is right; Flow can't see cliffs, so a trail that
-- leads off at a wide angle is more often an old wander than a way round.
-- Steps inside a cave keep their trail whatever its heading.
--   p: you; c: the trail point the arrow would lead to; t: the step
N.TRAIL_HEADING = 60   -- degrees between "along the trail" and "at the step", at most
N.TRAIL_NEAR = 8       -- a trail point this close says nothing about a heading
function N.TrailHeadingOk(px, py, cx, cy, tx, ty, maxDeg)
    local ax, ay, bx, by = cx - px, cy - py, tx - px, ty - py
    local la, lb = math.sqrt(ax * ax + ay * ay), math.sqrt(bx * bx + by * by)
    if la < N.TRAIL_NEAR or lb < 1 then return true end
    local cos = (ax * bx + ay * by) / (la * lb)
    return cos >= math.cos(math.rad(maxDeg or N.TRAIL_HEADING))
end
-- A trail turned down for its heading isn't worked out again for a while.
local trailOff = { key = nil, till = 0 }

-- "Arrow follows paths you've walked": on unless you turn it off (0.35.172;
-- it was off unless ticked). A trail is only taken when it's at most half
-- again as long as the straight line, so it bends round a cliff you've
-- walked round before without wandering off along an old detour.
function N.TrailsOn() return ns.db.nav.arrowPaths ~= false end

-- Where to walk now to reach one place (pt: { wx, wy }): along a trail
-- you've walked, by a cave's entrance, or straight. key: what the trail is
-- for (a step, or the gate on the way to it), so it's planned again when
-- that changes.
local function steerTo(p, pt, direct, key, inside)
    if not inside and not N.TrailsOn() then route = nil return pt.wx, pt.wy, "direct", direct end
    if direct < 80 and not inside then route = nil return pt.wx, pt.wy, "direct", direct end

    local now = GetTime()
    local stale = not route or route.goalKey ~= key or route.cont ~= p.cont
    if route and not stale then
        local g = graph(p.cont)
        local w = route.nodes[route.idx]
        -- Off the path? Re-plan (at most every 3s).
        if w and dist(p.wx, p.wy, g.x[w], g.y[w]) > 60 and now - lastRouteAt > 3 then stale = true end
    end
    if stale and now - lastRouteAt > 1 then
        lastRouteAt = now
        route = nil
        local s = not (trailOff.key == key and now < trailOff.till) and nearestNode(p.cont, p.wx, p.wy, 40) or nil
        local t, td = nearestNode(p.cont, pt.wx, pt.wy, 80)
        if s and t and s ~= t then
            local nodes, length = astar(p.cont, s, t)
            if nodes and N.TrailWorthIt(length + (td or 0), direct, inside) then
                route = { goalKey = key, cont = p.cont, nodes = nodes, idx = 1,
                          length = length + (td or 0) }
            end
        end
    end
    if not route then
        local e = inside and entranceNear(p.cont, pt.wx, pt.wy)
        if e and dist(p.wx, p.wy, e.wx, e.wy) > ARRIVED then return e.wx, e.wy, "entrance", direct end
        return pt.wx, pt.wy, "direct", direct
    end

    local g = graph(p.cont)
    -- Advance along the path; also jump ahead if a later point is already closer.
    local bestIdx, bestD = route.idx, nil
    for i = route.idx, math.min(#route.nodes, route.idx + 6) do
        local n = route.nodes[i]
        local d = dist(p.wx, p.wy, g.x[n], g.y[n])
        if not bestD or d < bestD then bestIdx, bestD = i, d end
    end
    route.idx = bestIdx
    local n = route.nodes[route.idx]
    while n and dist(p.wx, p.wy, g.x[n], g.y[n]) < ARRIVED and route.idx < #route.nodes do
        route.idx = route.idx + 1
        n = route.nodes[route.idx]
    end
    if route.idx >= #route.nodes and dist(p.wx, p.wy, g.x[n], g.y[n]) < ARRIVED then
        return pt.wx, pt.wy, "direct", direct   -- end of known trail: head straight in
    end
    -- Lead forward: the furthest trail point within LOOKAHEAD yards.
    local pts = {}
    for i = route.idx, math.min(#route.nodes, route.idx + 12) do
        local m = route.nodes[i]
        pts[#pts + 1] = { g.x[m], g.y[m] }
    end
    local ahead = route.idx + N.Carrot(pts, 1, p.wx, p.wy, LOOKAHEAD) - 1
    n = route.nodes[ahead] or n
    -- Leading well away from where the step is: not this trail. Straight at
    -- the step, and the trail isn't tried again for a while.
    if not inside and not N.TrailHeadingOk(p.wx, p.wy, g.x[n], g.y[n], pt.wx, pt.wy) then
        if trailOff.key ~= key then
            ns:Log("nav", string.format("a trail to %s (%d yd, %d straight) leads off at a wide angle: pointing straight at it",
                tostring(key), route.length or 0, direct or 0))
        end
        trailOff.key, trailOff.till = key, now + 15
        route = nil
        return pt.wx, pt.wy, "direct", direct
    end
    return g.x[n], g.y[n], "path", route.length
end

-- Where the arrow points for this step. Returns wx, wy, how, yards:
--   "direct"    straight at the step
--   "path"      along a trail you've walked
--   "entrance"  to the way into the cave or building the step is in
--   "gate"      to the way into another region (Gates.lua: the lift up
--               Thunder Bluff, the pass into the next zone), then on
local function steer(p, choice)
    local pt = choice.point
    local direct = choice.d
    -- A step a cast away (Teleport: Moonglade): the panel and the arrow say so.
    local TS = ns.travelSpells
    if TS then
        local spell = TS.Spell(p, pt)
        N.port, N.portHint = spell and spell.name or nil, TS.Hint(p, pt)
    end
    -- Out of a zone someone carries you from (a druid in Moonglade): the
    -- arrow leads to them, and says who to talk to (Rides.lua).
    local RD = ns.rides
    local way, named
    if RD then way, named = RD.Way(p, pt) end
    N.ride, N.rideHint = way, RD and RD.HintOf(way or named) or nil
    if way then
        N.via = nil
        local wx, wy, how, len = steerTo(p, way.point, way.toNpc, choice.goal.key .. ":ride", false)
        if how == "path" then return wx, wy, "path", len end
        return wx, wy, "ride", way.toNpc
    end
    -- The step is in another region: by a gate you've used, never straight
    -- through the cliff. The gate is where to walk to until you're through.
    local via = ns.gates and ns.gates.Via(p, pt) or nil
    -- A walled place with no way known on foot: a flight path is a way too.
    -- When flying from a flight master you know gets you nearer, the arrow
    -- leads to that flight master.
    if via and via.unknown then
        local air = N.AirRoute(p, pt, direct)
        local node = air and ns.db.flights and ns.db.flights[air.from]
        if node and node.cont == p.cont then
            via = ns.gates.WithAir(via, air, node, dist(p.wx, p.wy, node.wx, node.wy))
        end
    end
    N.via = via
    local gate = via and via.points[1]
    if gate then
        local toGate = dist(p.wx, p.wy, gate.wx, gate.wy)
        if toGate > ARRIVED then
            local wx, wy, how = steerTo(p, gate, toGate, choice.goal.key .. ":gate", false)
            return wx, wy, how == "path" and "path" or "gate", via.yards
        end
    end
    -- A step inside a cave while you're outside: never straight at it (that
    -- leads on top of the cave). Follow a trail in, or head for the entrance.
    local inside = not (IsIndoors and IsIndoors()) and N:Inside(p.cont, pt.wx, pt.wy)
    return steerTo(p, pt, direct, choice.goal.key, inside)
end

-- The places a leg of the route passes between its two ends ({ cont, wx,
-- wy } each), or nil when it's a straight line. For the world map's dotted
-- path, which follows the way you'd really walk (0.35.172).
--   live: the leg from you to your next step: the arrow's own way now (the
--         trail it follows, the gate it heads for). Other legs: their gates.
N.LEG_POINTS = 60   -- at most this many trail points a leg (a long trail is thinned)
function N.LegVia(a, b, live)
    local out
    if live and route and N.how == "path" then
        local g = graph(route.cont)
        local n = #route.nodes - route.idx + 1
        local step = math.max(1, math.ceil(n / N.LEG_POINTS))
        out = {}
        for i = route.idx, #route.nodes, step do
            local node = route.nodes[i]
            out[#out + 1] = { cont = route.cont, wx = g.x[node], wy = g.y[node] }
        end
    end
    -- To someone who carries you (a flight out of Moonglade): the walk ends
    -- at them; the rest is by air.
    if live and N.ride and N.ride.point then
        local pt, lastPt = N.ride.point, out and out[#out]
        out = out or {}
        if not lastPt or dist(lastPt.wx, lastPt.wy, pt.wx, pt.wy) > ARRIVED then
            out[#out + 1] = { cont = pt.cont, wx = pt.wx, wy = pt.wy }
        end
        return out
    end
    local via = ns.gates and ns.gates.Via(a, b)
    if via and via.points[1] then
        out = out or {}
        for _, gate in ipairs(via.points) do
            local lastPt = out[#out]
            -- (A trail that already ends at the gate: not twice.)
            if not lastPt or dist(lastPt.wx, lastPt.wy, gate.wx, gate.wy) > ARRIVED then
                out[#out + 1] = { cont = gate.cont, wx = gate.wx, wy = gate.wy }
            end
        end
    end
    -- Into a cave or building you've been in (and the leg isn't already a
    -- trail): through its entrance.
    if not out and b and b.wx and b.cont and N:Inside(b.cont, b.wx, b.wy)
        and not (a and a.wx and N:Inside(a.cont, a.wx, a.wy)) then
        local e = entranceNear(b.cont, b.wx, b.wy)
        if e then out = { { cont = e.cont, wx = e.wx, wy = e.wy } } end
    end
    return out
end

-- ". Hearthstone (Thunder Bluff) is about 4 min quicker": beside the arrow's
-- distance when the stone is ready and clearly the quicker way to this step
-- (Hearth.lua H:Saves). Asked every few seconds, not every update.
local hearthCue = { key = nil, at = 0, text = "" }
function N.HearthCue(key, pt, yards, now)
    if hearthCue.key == key and now - hearthCue.at < 3 then return hearthCue.text end
    local text = ""
    local H = ns.hearth
    if H and H.Saves and pt and pt.map and pt.x then
        local saving, bind = H:Saves(pt.map, pt.x, pt.y, yards)
        local cue = H.Cue(saving, bind)
        if cue then text = ". " .. cue end
    end
    hearthCue.key, hearthCue.at, hearthCue.text = key, now, text
    return text
end

-- " (by the way into Thunder Bluff, 340 yd)": beside the distance while the
-- arrow leads to a gate.
function N.GateText(via, yards)
    local gate = via and via.points and via.points[1]
    if not gate then return "" end
    if via.air then
        return string.format(" (to the flight master: fly %s to %s, %d yd)", via.air.from, via.air.to, yards or via.yards or 0)
    end
    local G = ns.gates
    local into = (G and via.to and G.Name(via.to)) or nil
    return string.format(" (by the way %s, %d yd)", into and ("into " .. into) or "through", yards or via.yards or 0)
end

-- One line for the arrow's panel: how it's taking you there.
function N.HowText(how, via, ride)
    if ride then
        return string.format("It's far from here: the arrow takes you to %s (%s).", ride.name, ride.how or "a ride out")
    end
    if how == "path" then return "Following a trail you've walked before." end
    if how == "entrance" then return "It's inside: the arrow takes you to the entrance first." end
    if how == "gate" then
        if via and via.air then
            return string.format("Flow knows no way there on foot yet, but a flight path is a way too: the arrow takes you to the flight master. Fly %s to %s.",
                via.air.from, via.air.to)
        end
        return "It's in another part of the map you can't walk straight into: the arrow takes you to the way in you've used before (a lift, a gate, a pass)."
    end
    if via and via.unknown then
        local G = ns.gates
        return string.format("Straight line: Flow doesn't know the way %s yet. It learns it the first time you go in on foot (or by lift).",
            (G and via.to and G.Walled(via.to) and ("into " .. G.Name(via.to))) or (G and via.from and ("out of " .. G.Name(via.from))) or "there")
    end
    return "Straight line: no known trail yet."
end

-- Changes whenever the arrow's way changes (a trail point passed, a gate
-- reached): the world map draws its path again then.
function N.PathStamp()
    local via = N.via
    return (N.how or "") .. (N.ride and (":ride:" .. N.ride.name) or "")
        .. (route and (":" .. tostring(route.goalKey) .. ":" .. route.idx .. ":" .. #route.nodes) or "")
        .. ((via and via.points[1]) and (":g" .. #via.points .. ":" .. via.points[1].wx) or "")
end

-------------------------------------------------------------------------------
-- Arrow UI
-------------------------------------------------------------------------------

local frame, panel

-- The arrow's panel (left-click the arrow). Built so your eyes land on the
-- task first:
--   [hero]  a band in the route colour: step icon, TYPE in small caps,
--           the task in large white text, distance and direction on the right
--   then    quest name, objectives, details (small), the trip plan (smaller)
local function buildPanel(name)
    local f = CreateFrame("Frame", name or "FlowNavPanel", UIParent)
    f:SetSize(340, 140)
    f:SetFrameStrata("DIALOG")
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0.04, 0.04, 0.07, 0.92)

    local h = CreateFrame("Frame", nil, f)
    h:SetPoint("TOPLEFT", 0, 0)
    h:SetPoint("TOPRIGHT", 0, 0)
    h:SetHeight(64)
    h.bg = h:CreateTexture(nil, "BACKGROUND")
    h.bg:SetAllPoints()
    h.bar = h:CreateTexture(nil, "BORDER")
    h.bar:SetPoint("TOPLEFT"); h.bar:SetPoint("BOTTOMLEFT"); h.bar:SetWidth(5)
    h.icon = h:CreateTexture(nil, "ARTWORK")
    h.icon:SetSize(36, 36)
    h.icon:SetPoint("LEFT", 14, 0)
    h.label = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h.label:SetPoint("TOPLEFT", h.icon, "TOPRIGHT", 10, 2)
    h.dist = h:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    h.dist:SetPoint("TOPRIGHT", -10, -8)
    h.dist:SetJustifyH("RIGHT")
    h.task = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    h.task:SetPoint("TOPLEFT", h.label, "BOTTOMLEFT", 0, -3)
    h.task:SetPoint("RIGHT", -10, 0)
    h.task:SetJustifyH("LEFT")
    h.task:SetWordWrap(true)
    f.hero = h

    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.text:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 12, -8)
    f.text:SetPoint("RIGHT", -12, 0)
    f.text:SetJustifyH("LEFT")
    f.text:SetJustifyV("TOP")
    f:EnableMouse(true)
    f:SetScript("OnMouseUp", function(self) self:Hide() end)
    f:Hide()
    return f
end

-- Drag a panel (arrow panel, step card) by its title band. Once moved it
-- opens where you left it (saved as ns.db.nav[key]); right-click the title
-- to put it back where it opens by default (`home`, said in chat).
function N.Draggable(f, key, home)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    local h = f.hero
    h:EnableMouse(true)
    h:RegisterForDrag("LeftButton")
    h:SetScript("OnDragStart", function() f:StartMoving() end)
    h:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local a, _, b, x, y = f:GetPoint()
        ns.db.nav[key] = { a, b, x, y }
    end)
    h:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and ns.db.nav[key] then
            ns.db.nav[key] = nil
            ns:Print("back " .. home .. " next time it opens")
        end
    end)
    h:SetScript("OnEnter", function(self)
        if self.hinted then return end
        self.hinted = true   -- once per session: how to move it
        ns.Tip(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Drag the title to move this.", 1, 1, 1)
        GameTooltip:AddLine("Right-click the title to put it back " .. home .. ".", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    h:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- The coloured band at the top of the arrow panel and the step card.
local function fillHero(p, g, distText)
    local h = p.hero
    local c = ns.theme.route
    h.bg:SetColorTexture(c[1] * 0.35, c[2] * 0.35, c[3] * 0.35, 0.95)
    h.bar:SetColorTexture(c[1], c[2], c[3], 1)
    local kind = ns.theme.kinds[N:StopKind(g)]
    h.icon:SetTexture(kind and kind.icon or "Interface\\Icons\\INV_Misc_Map_01")
    h.label:SetText(((kind and kind.label) or "Next step"):upper())
    h.label:SetTextColor(c[1] + (1 - c[1]) * 0.5, c[2] + (1 - c[2]) * 0.5, c[3] + (1 - c[3]) * 0.5)
    local task = g.text or g.title or "Next step"
    if g.title and task:sub(1, #g.title + 2) == g.title .. ": " then task = task:sub(#g.title + 3) end
    h.task:SetText(task)
    h.dist:SetText(distText or "")
    h:SetHeight(math.max(64, h.task:GetStringHeight() + h.label:GetStringHeight() + 26))
    return task
end

-- The arrow's panel is a drawer beside the arrow (below it, a lip joins it
-- to the arrow's text). Click the arrow to open it, click again or its X to
-- close it; it opens and closes at once (no slide), follows your current
-- step, and stays open after a /reload until you close it. It opens on
-- whichever side of the arrow has room (N.DrawerSide): below, above near the
-- bottom of the screen, to the right or left at a screen edge. Ctrl-drag it
-- to give it a place of its own (the arrow's right-click menu puts it back).
-- (The step card, shared by the Flow Tracker and Router, is a separate window.)

-- Which side of the arrow the drawer opens on. Arrow at ax, ay (left,
-- bottom) of size aw x ah on a screen sw x sh; the drawer is dw x dh.
-- (Below the arrow, its text takes 38 more.)
function N.DrawerSide(ax, ay, aw, ah, sw, sh, dw, dh)
    local cx = ax + aw / 2
    if cx < dw / 2 + 8 then return "right" end          -- at the left edge
    if cx > sw - dw / 2 - 8 then return "left" end      -- at the right edge
    local roomBelow, roomAbove = ay - 38, sh - (ay + ah)
    if roomBelow >= dh + 8 then return "below" end
    if roomAbove >= dh + 8 then return "above" end
    return roomBelow >= roomAbove and "below" or "above"   -- (kept on screen either way)
end

local DRAWER_POINTS = {
    below = { "TOP", "BOTTOM", 0, -38 }, above = { "BOTTOM", "TOP", 0, 8 },
    right = { "TOPLEFT", "TOPRIGHT", 8, 0 }, left = { "TOPRIGHT", "TOPLEFT", -8, 0 },
}

-- Put the drawer where it opens: your spot (Ctrl-dragged), else beside the arrow.
local function placeDrawer(drawer, arrow)
    drawer:ClearAllPoints()
    local saved = ns.db.nav.drawerPoint
    if saved then
        drawer:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
        drawer.lip:Hide()
        return "yours"
    end
    local k = (arrow:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
    local side = N.DrawerSide((arrow:GetLeft() or 0) * k, (arrow:GetBottom() or 0) * k, arrow:GetWidth() * k, arrow:GetHeight() * k,
        UIParent:GetWidth(), UIParent:GetHeight(), drawer:GetWidth(), drawer:GetHeight())
    local p = DRAWER_POINTS[side]
    drawer:SetPoint(p[1], arrow, p[2], p[3], p[4])
    drawer.lip:SetShown(side == "below")
    return side
end
N._placeDrawer = placeDrawer   -- (tests)

local function makeDrawer(f)
    local BG = { 0.04, 0.04, 0.07, 0.92 }
    -- An X closes it, top right as on Flow's other views; a click on the
    -- arrow opens and closes it too. (0.35.139: no more pin, hover-open, pull
    -- tab or slide: it opens and closes at once, and stays open, following
    -- your steps and across a /reload, until you close it.)
    f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.close:SetPoint("TOPRIGHT", 2, 2)
    f.close:SetScript("OnClick", function() f:Fold(true) end)
    if f.hero and f.hero.dist then   -- (the X takes the top-right corner)
        f.hero.dist:ClearAllPoints()
        f.hero.dist:SetPoint("BOTTOMRIGHT", -10, 8)
    end
    f.lip = f:CreateTexture(nil, "BACKGROUND")
    f.lip:SetSize(90, 5)
    f.lip:SetPoint("BOTTOM", f, "TOP", 0, 0)
    f.lip:SetColorTexture(BG[1], BG[2], BG[3], BG[4])
    -- byYou: you closed it (the X or the arrow): it stays closed after a /reload.
    function f:Fold(byYou)
        if byYou then ns.db.nav.drawerOpen = nil end
        self:Hide()
    end
    -- Ctrl-drag: your own place for it (saved).
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if ns.MoveKeyDown() then self:StartMoving(); self.dragging = true end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self.dragging = nil
        local a, _, r, x, y = self:GetPoint()
        ns.db.nav.drawerPoint = { a, r, x, y }
        self.lip:Hide()
        ns:Print("the drawer stays here now (right-click the arrow: \"Drawer next to the arrow\" puts it back).")
    end)
end

N._makeDrawer = makeDrawer  -- (tests)

local function showPanel()
    if not (panel and panel:IsShown()) then GameTooltip:Hide() end   -- opening: the drawer replaces the tooltip
    if not current then return end
    if not panel then
        panel = buildPanel()
        makeDrawer(panel)
        ns.db.nav.panelPoint = nil   -- (it used to be draggable)
    end
    local g = current.goal
    local h = panel.hero
    local p = N:PlayerPos()
    local task = fillHero(panel, g, string.format("%d yd%s", current.d or 0, N.TravelText(p, current.point, current.d)))

    local lines = {}
    if g.title and g.title ~= task then lines[#lines + 1] = "|cffffd200" .. g.title .. "|r" end
    local air = N.AirRoute(p, current.point, current.d)
    if air then lines[#lines + 1] = string.format("Quicker by air: fly from %s to %s.", air.from, air.to) end
    if g.blockedBy then lines[#lines + 1] = "|cffff7070Blocked: " .. g.blockedBy .. "|r" end
    for _, l in ipairs(g.details or {}) do
        if not l:find("^Quest: ") and not l:find("^Objective: ") then lines[#lines + 1] = "|cffcccccc" .. l .. "|r" end
    end
    if N.portHint then lines[#lines + 1] = "|cff66ccff" .. N.portHint .. "|r" end
    if N.rideHint then lines[#lines + 1] = "|cff66ccff" .. N.rideHint .. "|r" end
    -- Your hearthstone, when Flow's estimate says it's clearly the quicker
    -- way (against the ride, where there is one).
    local hs = ns.hearth and ns.hearth.Advice and current.point and current.point.map
        and ns.hearth:Advice(current.point.map, current.point.x, current.point.y, (N.ride and N.ride.yards) or current.d)
    if hs then lines[#lines + 1] = "|cff66ccff" .. hs .. "|r" end
    lines[#lines + 1] = "|cff888888" .. N.HowText(N.how, N.via, N.ride) .. "|r"
    -- The whole trip, in the order Flow plans to do it.
    if N.plan and #N.plan > 1 then
        lines[#lines + 1] = " "
        lines[#lines + 1] = string.format("|cffffd200Then|r |cff888888(%d steps, about %d yd)|r",
            #N.plan - 1, N.plan[#N.plan].cum or 0)
        local labels = N:PlanLabels(N.plan)
        for i, s in ipairs(N.plan) do
            if i > 1 then
                if i > 10 then lines[#lines + 1] = "  ..."; break end
                lines[#lines + 1] = "  " .. N:FormatStop(i, s.goal, labels[i])
                    .. string.format(" |cff888888(+%d yd)|r", s.leg or 0)
            end
        end
        if N.plan.dropped and #N.plan.dropped > 0 then
            lines[#lines + 1] = "|cff888888Skipped as too far out of the way: " .. table.concat(N.plan.dropped, ", ") .. "|r"
        end
    end
    -- Things to pick up as you go, never a detour of their own.
    if N.alongGoals and #N.alongGoals > 0 then
        lines[#lines + 1] = " "
        lines[#lines + 1] = "|cffffd200Along the way|r |cff888888(loot these when you meet them; no detour)|r"
        for _, a in ipairs(N.alongGoals) do lines[#lines + 1] = "  |cffcccccc" .. (a.text or a.title or "?") .. "|r" end
    end
    lines[#lines + 1] = " "
    lines[#lines + 1] = "|cff888888Right-click the arrow for options. Click the arrow or the ^ tab to fold this away.|r"
    panel.text:SetText(table.concat(lines, "\n"))
    panel:SetHeight(h:GetHeight() + panel.text:GetStringHeight() + 24)
    -- Placed when it opens (it's refreshed all the time while open): on the
    -- side of the arrow with room, or where you Ctrl-dragged it.
    if not panel:IsShown() then panel.side = placeDrawer(panel, frame) end
    panel:Show()
end

-------------------------------------------------------------------------------
-- Step card: Flow's small view of one step, opened by clicking it anywhere.
-- Same look as the arrow panel; it stays where it is (the Flow Router stays
-- open), and has links for the rarer things you might want instead.
-------------------------------------------------------------------------------

local card

-- A tooltip stand-in that collects FillTooltip's lines as coloured text.
local function textTooltip()
    local tt = { lines = {} }
    function tt:AddLine(text, r, g, b)
        text = text or ""
        if r then text = string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, text) end
        self.lines[#self.lines + 1] = text
    end
    return tt
end
N._textTooltip = textTooltip  -- (tests)

-- arm(link): called when the mouse comes over the link, for a link that
-- opens one of the game's own windows (MapOpen.lua puts a secure button over
-- it, so the game opens its window itself).
local function uiLink(parent, label, fn, arm)
    local b = CreateFrame("Button", nil, parent)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("LEFT")
    b.text:SetText(label)
    b.text:SetTextColor(0.35, 0.7, 1)
    b.line = b:CreateTexture(nil, "ARTWORK")        -- underline: it's a link
    b.line:SetPoint("TOPLEFT", b.text, "BOTTOMLEFT", 0, -1)
    b.line:SetPoint("TOPRIGHT", b.text, "BOTTOMRIGHT", 0, -1)
    b.line:SetHeight(1)
    b.line:SetColorTexture(0.35, 0.7, 1, 0.6)
    b:SetSize(b.text:GetStringWidth() + 2, 14)
    b:SetScript("OnEnter", function(self)
        self.text:SetTextColor(1, 1, 1); N:ClickCursor(true)
        if arm then pcall(arm, self) end
    end)
    b:SetScript("OnLeave", function(self) self.text:SetTextColor(0.35, 0.7, 1); N:ClickCursor(false) end)
    b:SetScript("OnClick", function() fn(); N:ClickCursor(false) end)
    return b
end
N._uiLink = uiLink   -- (tests)


local function buildCard()
    local f = buildPanel("FlowStopCard")
    f:SetFrameStrata("FULLSCREEN_DIALOG")          -- above the world map
    f:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "FlowStopCard")         -- Esc closes it
    f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.close:SetPoint("TOPRIGHT", 2, 2)
    f.close:SetScale(0.8)
    f.close:SetScript("OnClick", function() f:Hide() end)   -- (our own: the game's handler can't close an add-on window in a fight)
    N.Draggable(f, "cardPoint", "beside what you click")
    f.hero.dist:ClearAllPoints()
    f.hero.dist:SetPoint("BOTTOMRIGHT", -10, 8)
    -- "Select in quest log" and "Show on map" open the game's window when it's
    -- closed (0.35.171): MapOpen.lua lets the game do the opening (its own
    -- button, clicked through a secure one), so Flow's code still never runs
    -- the map. Where that can't be (a fight, a client without those buttons)
    -- the link does what it did: selects, highlights, and says which key.
    f.links = {
        quest = uiLink(f, "Select in quest log", function()
            N:OpenInGame(f.goal)
            if not WorldMapFrame:IsShown() then ns:Print("selected in your quest log: press L (or M) to read it.") end
        end, function(self)
            local id = f.goal and tonumber(f.goal.key:match("^(%d+):"))
            return ns.mapOpen and ns.mapOpen.Arm(self, "log", function() N:OpenInGame(f.goal) end, nil, id)
        end),
        map = uiLink(f, "Show on map", function()
            local g = f.goal
            if ns.mapOverlay then ns.mapOverlay:Focus(g.key, 20) end
            if not WorldMapFrame:IsShown() then ns:Print("press M: Flow highlights it on your map.") end
        end, function(self)
            return ns.mapOpen and ns.mapOpen.Arm(self, "map", nil, function()
                if ns.mapOverlay and f.goal then ns.mapOverlay:Focus(f.goal.key, 20) end
            end, nil, N.GoalMap(f.goal))
        end),
        first = uiLink(f, "Go here next", function()
            -- (Across the sea: its zeppelin or boat is the next step, Crossings.lua.)
            if ns.crossings and ns.crossings.CanLead(f.goal) then ns.crossings.Lead(f.goal) else N:Select(f.goal.key) end
            f:Hide()
        end),
    }
    f:HookScript("OnHide", function() if ns.mapOpen then ns.mapOpen.Disarm() end end)
    return f
end

function N:ShowStop(goal, anchor)
    GameTooltip:Hide()   -- the card says it all: the hover tooltip would just cover it
    card = card or buildCard()
    if card:IsShown() and card.goal and card.goal.key == goal.key then card:Hide() return end  -- click again: close
    card.goal = goal
    local p = N:PlayerPos()
    local pt = N:Spot(goal, p)
    local d = (p and pt and pt.wx and pt.cont == p.cont) and dist(p.wx, p.wy, pt.wx, pt.wy)
    local task = fillHero(card, goal, d and string.format("%d yd%s", d, N.TravelText(p, pt, d)) or "")

    -- Body: what the tooltip says, minus the title and task the band shows.
    local tt = textTooltip()
    N:FillTooltip(tt, goal)
    local body = {}
    if goal.title and goal.title ~= task then body[1] = "|cffffd200" .. goal.title .. "|r" end
    for i = 4, #tt.lines do body[#body + 1] = tt.lines[i] end
    card.text:SetText(table.concat(body, "\n"))

    -- Links under the text.
    local id = tonumber(goal.key:match("^(%d+):"))
    local inLog = id and questLogIndex(id)
    local x = 12
    for _, name in ipairs({ "quest", "map", "first" }) do
        local l = card.links[name]
        if name == "quest" and not inLog then l:Hide()
        else
            l:ClearAllPoints()
            l:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", x, 10)
            l:Show()
            x = x + l:GetWidth() + 14
        end
    end
    card:SetHeight(card.hero:GetHeight() + card.text:GetStringHeight() + 48)
    card:ClearAllPoints()
    local saved = ns.db.nav.cardPoint
    if saved then
        card:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])   -- where you dragged it
    -- Where WoW shows its tooltips (Edit Mode / interface options), else:
    elseif not ns.PlaceAtTipSpot(card, anchor or UIParent) then
        if anchor and anchor.GetRight then
            -- Beside what you clicked, on whichever side has room.
            local right = anchor:GetRight() and anchor:GetRight() * anchor:GetEffectiveScale() / UIParent:GetEffectiveScale()
            if right and right + 350 > GetScreenWidth() then card:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -8, 0)
            else card:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 0) end
        else
            card:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
        end
    end
    card:Show()
end

local function buildArrow()
    local f = CreateFrame("Button", "FlowNavArrow", UIParent)
    f:SetSize(56, 56)
    f:SetFrameStrata("HIGH")
    local p = ns.db.nav.point
    if p then f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else f:SetPoint("TOP", UIParent, "TOP", 0, -120) end
    -- The faint profession needle sits under the main arrow (a lower frame
    -- level, a little see-through), its step name and distance in small grey
    -- text above, opposite the main arrow's text.
    f.prof = CreateFrame("Frame", nil, f)
    f.prof:SetAllPoints(f)
    f.prof:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1))
    f.prof:SetAlpha(0.85)
    f.prof.arrow = N:MakeProfArrow(f.prof)
    -- At the profession step: a faint see-through ring where the arrow was,
    -- with none of the main arrow's beam or bouncing icon (those mean "your
    -- main step").
    f.prof.ring = f.prof:CreateTexture(nil, "BACKGROUND", nil, 2)
    f.prof.ring:SetTexture(ART .. "ArrowRing")
    f.prof.ring:SetBlendMode("ADD")
    f.prof.ring:SetSize(HALO_W, HALO_H)
    f.prof.ring:SetPoint("CENTER", f.prof, "CENTER", 0, HALO_Y)
    f.prof.ring:SetAlpha(N.PROF_RING_ALPHA)
    f.prof.ring:Hide()
    f.prof.text = f.prof:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.prof.text:SetPoint("BOTTOM", f, "TOP", 0, N.NeedleClearance(f))
    f.prof.text:SetWidth(260)
    f.prof.text:SetWordWrap(false)
    do local c = ns.theme.muted; f.prof.text:SetTextColor(c[1], c[2], c[3]) end
    f.prof:Hide()
    f.arrow = N:MakeArrow(f)
    N.arrowFrame = f
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.text:SetPoint("TOP", f, "BOTTOM", 0, -2)
    f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.sub:SetPoint("TOP", f.text, "BOTTOM", 0, -2)
    -- The lines are stacked by length on one side of the arrow (N.LayoutLines),
    -- looked at a few times a second: any of them may change, and so may
    -- where the arrow is.
    f.linesDriver = CreateFrame("Frame", nil, f)
    do
        local acc = 1
        f.linesDriver:SetScript("OnUpdate", function(_, dt)
            acc = acc + dt
            if acc < 0.2 then return end
            acc = 0
            pcall(N.LayoutLines, f)
        end)
    end
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if ns.MoveKeyDown() then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local a, _, r, x, y = self:GetPoint()
        ns.db.nav.point = { a, r, x, y }
    end)
    f:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            -- Menu: this step, then route and order choices, unhide all.
            local items = {}
            if current and current.follow then
                -- Following a party member (Follow.lua).
                items[#items + 1] = { title = true, text = current.goal.text or "Following" }
                items[#items + 1] = { text = "Stop following (back to the route)", func = function() ns.follow:Stop() end }
                items[#items + 1] = { sep = true }
            elseif current and current.waypoint then
                -- Following your own waypoint (not a route step).
                items[#items + 1] = { title = true, text = current.goal.text or "Your waypoint" }
                items[#items + 1] = { text = "Clear it (back to the route)", func = function()
                    if ns.waypoint then ns.waypoint:Clear() end
                    ns:Print("waypoint cleared: back to your route")
                end }
                items[#items + 1] = { sep = true }
            elseif current then
                local g = current.goal
                items[#items + 1] = { title = true, text = g.text or g.title or "This step" }
                items[#items + 1] = { text = "Open it", func = function() N:OpenStop(g) end }
                items[#items + 1] = { text = "Hide this step", func = function() N:Hide(g.key) end }
                items[#items + 1] = { sep = true }
            end
            -- (The arrow's look is the Flow menu's "Arrow" section: N:ArrowMenuItems.)
            for _, it in ipairs(ns.menu:RouteItems()) do items[#items + 1] = it end
            ns.menu:Open(items)
        elseif panel and panel:IsShown() then
            panel:Fold(true)
        else
            -- A click opens it; it stays open (across a /reload too) until
            -- you close it: the X, or another click on the arrow.
            showPanel()
            ns.db.nav.drawerOpen = true
        end
    end)
    -- The text under the arrow (step name, distance) clicks like the arrow:
    -- left = this panel, right = the menu.
    f.textHit = CreateFrame("Button", nil, f)
    f.textHit:SetPoint("TOP", f, "BOTTOM", 0, 0)
    f.textHit:SetSize(240, 34)
    f.textHit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f.textHit:SetScript("OnClick", function(_, button) f:GetScript("OnClick")(f, button) end)
    -- Hover the arrow (or ring, or its text): the step's details, e.g. quest progress.
    local function tip(owner)
        if not current or (panel and panel:IsShown()) then return end   -- the drawer already shows it
        ns.Tip(owner, "ANCHOR_BOTTOM")
        N:FillTooltip(GameTooltip, current.goal, not N.arrived and "Click: details and the trip. Right-click: options." or nil)
        -- In an area: every other quest step you're in the area for, with progress.
        if N.arrived then
            local p = N:PlayerPos()
            local first = true
            for _, g in ipairs(goals) do
                if g ~= current.goal and N:InArea(g, p) then
                    if first then
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine("Also here", 1, 0.82, 0.25)
                        first = false
                    end
                    GameTooltip:AddLine(N:FormatStop(0, g, ""), 1, 1, 1, true)
                end
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("You're there. Click: details. Right-click: options.", 0.55, 0.55, 0.55, true)
        end
        GameTooltip:Show()
    end
    -- Hovering shows a tooltip (not the drawer: a click opens that).
    local function leave() GameTooltip:Hide() end
    f:SetScript("OnEnter", function() tip(f) end)
    f:SetScript("OnLeave", leave)
    f.textHit:SetScript("OnEnter", function() tip(f) end)
    f.textHit:SetScript("OnLeave", leave)
    -- The faint arrow's text: left-click opens that step, right-click the
    -- arrow's menu, hover its details.
    f.prof.hit = CreateFrame("Button", nil, f.prof)
    f.prof.hit:SetPoint("BOTTOM", f, "TOP", 0, N.NeedleClearance(f) - 2)
    f.prof.hit:SetSize(240, 16)
    f.prof.hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f.prof.hit:SetScript("OnClick", function(_, button)
        if button == "RightButton" then f:GetScript("OnClick")(f, button)
        elseif N.profChoice then N:OpenStop(N.profChoice.goal) end
    end)
    f.prof.hit:SetScript("OnEnter", function(self)
        if not N.profChoice then return end
        ns.Tip(self, "ANCHOR_TOP")
        N:FillTooltip(GameTooltip, N.profChoice.goal, "Profession step (the faint arrow). Click: open it. Right-click: options.")
        GameTooltip:Show()
    end)
    f.prof.hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:Hide()
    return f
end

-- In a quest's area: within AREA yards of any of its spawn points (objective
-- steps only; a vendor or trainer is one spot).
local AREA = 45
function N:InArea(goal, p)
    if not (goal and goal.area and p) then return false end
    for _, pt in ipairs(goal.points or {}) do
        if pt.wx and pt.cont == p.cont and dist(p.wx, p.wy, pt.wx, pt.wy) < AREA then return true end
    end
    return false
end

-- The nearest spot in a step's area where its thing spawns (a Bundle of
-- Wood, a Prowler), skipping spots you looted in the last few minutes (the
-- arrow moves on to the next one). Returns the point and yards, or nil.
local SPOT_ON = 7                 -- yards: "you're on it" (ring)
local SPOT_REST = 240             -- seconds a looted spot is skipped (respawn)
local cleared = {}                -- "wx:wy" -> time looted
local function spotKey(pt) return math.floor(pt.wx) .. ":" .. math.floor(pt.wy) end
function N:NearestSpot(goal, p)
    if not (goal and goal.points and p) then return nil end
    local now, best, bestD = GetTime(), nil, nil
    for _, pt in ipairs(goal.points) do
        if pt.wx and pt.cont == p.cont then
            local c = cleared[spotKey(pt)]
            if not (c and now - c < SPOT_REST) then
                local d = dist(p.wx, p.wy, pt.wx, pt.wy)
                if not bestD or d < bestD then best, bestD = pt, d end
            end
        end
    end
    return best, bestD
end
-- Looting (a mob, a Bundle of Wood): the spot you're standing at is done for now.
function N.ClearSpotNear(p, goal)
    if not (p and goal) then return end
    local pt, d = N:NearestSpot(goal, p)
    if pt and d < 12 then cleared[spotKey(pt)] = GetTime() end
end
ns:On("LOOT_OPENED", function()
    local p = N:PlayerPos()
    if p and current and current.goal then N.ClearSpotNear(p, current.goal) end
end)

-- A herb or ore spot with nothing on it (0.35.259). "The minimap showed me
-- one, I went to it and there's nothing there: it should check the item's
-- actually there." Flow can't: an add-on isn't told which nodes are up (the
-- game's Find Herbs dots are its own), only where they can grow. So it does
-- the next best thing: once you've stood at a spot for a few seconds
-- without picking anything, that spot rests like a picked one and the arrow
-- goes on to the next.
N.EMPTY_YARDS, N.EMPTY_SECONDS = 15, 4
-- Pure: is this a step at herb or ore spots?
function N.GatherSpots(goal)
    if not goal then return false end
    return (goal.prof == "Herbalism" or goal.prof == "Mining") and (goal.kind == nil or goal.kind == "skill" or goal.kind == "gather")
end
-- Pure: has the spot you're at turned out empty? d: yards to it; since:
-- when you got within reach (nil: not yet); now.
function N.SpotEmpty(d, since, now)
    return d ~= nil and d < N.EMPTY_YARDS and since ~= nil and (now - since) >= N.EMPTY_SECONDS
end
local atSpot, atSince
local function watchSpot()
    local goal = current and current.goal
    if not N.GatherSpots(goal) or InCombatLockdown() then atSpot = nil return end
    local p = N:PlayerPos()
    local pt, d = N:NearestSpot(goal, p)
    if not (pt and d and d < N.EMPTY_YARDS) then atSpot = nil return end
    local key, now = spotKey(pt), GetTime()
    if atSpot ~= key then atSpot, atSince = key, now return end
    if N.SpotEmpty(d, atSince, now) then
        cleared[key] = now
        atSpot = nil
        N.emptySpots = (N.emptySpots or 0) + 1
        ns:Log("nav", string.format("nothing at this %s spot: on to the next (%d so far this session)", tostring(goal.prof), N.emptySpots))
    end
end
if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(1, function() pcall(watchSpot) end)
end

-- A nameplate on screen for one of the step's mobs / NPCs (goal.npcs): the
-- one nearest the middle of the screen. Returns { x, y (screen pixels), name }.
function N:VisibleTarget(goal)
    -- Forever doesn't let addons measure nameplates ("restricted regions"):
    -- after the first refusal, stop asking for this session.
    if N.platesRestricted then return nil end
    if not (goal and goal.npcs and C_NamePlate and C_NamePlate.GetNamePlates) then return nil end
    local want = {}
    for _, n in ipairs(goal.npcs) do want[n:lower()] = true end
    local cx, cy = GetScreenWidth() * UIParent:GetEffectiveScale() / 2, GetScreenHeight() * UIParent:GetEffectiveScale() / 2
    local best, bestD
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        local name = unit and A.Safe(UnitName(unit))
        if name and want[name:lower()] and not UnitIsDead(unit) then
            local okC, x, y = pcall(plate.GetCenter, plate)
            if not okC then N.platesRestricted = true return nil end
            if x then
                local s = plate:GetEffectiveScale()
                x, y = x * s, y * s
                local d = (x - cx) ^ 2 + (y - cy) ^ 2
                if not bestD or d < bestD then best, bestD = { x = x, y = y, name = name }, d end
            end
        end
    end
    return best
end

-- While you're dead: a red arrow to your corpse (as a ghost), or "Release
-- your spirit" before that. Returns true when it took over the arrow.
local CORPSE_RED = { 1, 0.2, 0.2 }
function N:ShowCorpse(p)
    frame.text:SetText("|cffff4040Your corpse|r")
    local pos = UnitIsGhost("player") and C_DeathInfo and C_DeathInfo.GetCorpseMapPosition
        and C_DeathInfo.GetCorpseMapPosition(p.map)
    if not pos then
        frame.sub:SetText(UnitIsGhost("player") and "On another map: follow the graveyard path" or "Release your spirit, then follow the red arrow")
        frame.arrow:Hide()
        frame:Show()
        return true
    end
    local x, y = pos:GetXY()
    local cont, wx, wy = N:ToWorld(p.map, x, y)
    if not wx then return false end
    local d = dist(p.wx, p.wy, wx, wy)
    local b = bearing(p, wx, wy)
    local facing = N.ArrowFacing()
    frame.arrow:SetVertexColor(CORPSE_RED[1], CORPSE_RED[2], CORPSE_RED[3])
    frame.arrow:SetArrived(d < ARRIVED * 2)
    if b and facing then frame.arrow:SetRotation(-(b + facing)); frame.arrow:Show() end
    frame.sub:SetText(d < ARRIVED * 2 and "Here: resurrect" or string.format("%d yd", d))
    if ns.minimapPin then
        pcall(ns.minimapPin.Update, ns.minimapPin, p, { cont = cont, wx = wx, wy = wy }, { text = "Your corpse" }, CORPSE_RED)
    end
    frame:Show()
    return true
end

-- The faint profession arrow: points straight at its step (no trails),
-- dark grey behind the main arrow, with its text above. Hidden at the
-- step (the text says "Here:"), and when it's off or nothing is due.
-- What the profession arrow shows: "ring" at its step, "off" while you are
-- on the main step's point (one thing to look at there) or it can't point,
-- else "arrow". Anywhere else in a main quest's area it still points.
function N.ProfArrowMode(mainHere, profHere, canPoint)
    if profHere then return "ring" end
    if mainHere or not canPoint then return "off" end
    return "arrow"
end

-- Standing on a step's point (not just inside its area).
function N.AtStopPoint(d)
    return d ~= nil and d < ARRIVED * 2
end

local function updateProf(p)
    local holder = frame.prof
    if not holder then return end
    local choice = N:ProfPointerOn() and chooseProf(p) or nil
    N.profChoice = choice
    if ns.minimapPin and ns.minimapPin.UpdateProf then
        local pt = choice and not choice.goal.anywhere and choice.point or nil
        pcall(ns.minimapPin.UpdateProf, ns.minimapPin, p, pt, choice and choice.goal)
    end
    if not choice then holder:Hide(); N.SetOverNeedle(frame, false) return end
    local g, pt = choice.goal, choice.point
    local name = g.text or g.title or "Profession step"
    local here = choice.d < ARRIVED * 2 or N:InArea(g, p)
    local b = bearing(p, pt.wx, pt.wy)
    local facing = N.ArrowFacing()
    local mode = N.ProfArrowMode(N.arrivedSpot, here, b and facing)
    holder.mode = mode
    if holder.ring then holder.ring:SetShown(mode == "ring") end
    if mode == "arrow" then
        holder.arrow:SetRotation(-(b + facing))
        holder.arrow:Show()
        N.SetOverNeedle(frame, true)
    else
        holder.arrow:Hide()
        N.SetOverNeedle(frame, false)
    end
    if ns.db.nav.profArrowText ~= false then
        holder.text:SetText(here and ("Here: " .. name) or string.format("%s, %d yd%s", name, choice.d, N.TravelText(p, pt, choice.d)))
        holder.text:Show(); holder.hit:Show()
    else
        holder.text:Hide(); holder.hit:Hide()
    end
    holder:Show()
end

local function update()
    local cfg = ns.db.nav
    -- Route colour follows the order mode (purple / blue / gold): recolour on change.
    if cfg.sorter ~= N.lastSorter then
        N.lastSorter = cfg.sorter
        ns.theme:UpdateRoute()
        if ns.mapOverlay and WorldMapFrame:IsShown() then pcall(ns.mapOverlay.Redraw, ns.mapOverlay) end
    end
    if not cfg.enabled then frame:Hide(); if ns.minimapPin then ns.minimapPin:Hide() end return end
    -- New to Flow: no arrow until you start walking (Reveal.lua).
    if ns.reveal and not ns.reveal:Shown("arrow") then frame:Hide(); if ns.minimapPin then ns.minimapPin:Hide() end return end
    if N.intro then return end   -- the login intro is playing on the arrow (Splash.lua)
    local p = N:PlayerPos()
    if not p then frame:Hide() return end
    if cfg.learn then
        record(p)
        -- (Gates.lua: where you cross from one map into another on foot.)
        if ns.gates then ns.gates.Track(p, (UnitOnTaxi and UnitOnTaxi("player")) or (IsFlying and IsFlying()) or false) end
    end
    -- On a flight, however it started (a flight map, or a word to someone who
    -- carries you): N.taxiTrip, for the arrow's words below.
    N.NoteTaxi((UnitOnTaxi and UnitOnTaxi("player")) and true or false, GetTime(),
        function() return ns.rides and ns.rides.Here(p) or nil end, ns.db.nav)

    -- Dead: the arrow turns red and points back to your corpse.
    if UnitIsDeadOrGhost("player") and N:ShowCorpse(p) then
        if frame.prof then frame.prof:Hide() end
        return
    end

    local choice = choose(p)          -- (keeps the route planned, waypoint or not)
    -- A party member you follow (Follow.lua), else your own waypoint, else the route.
    choice = (ns.follow and ns.follow.Choice(p)) or N.WaypointChoice(p) or choice
    current = choice
    N.current = choice  -- for Flow Actions (Modules/Rotation/Actions.lua)
    -- (With a step, the minimap dot is drawn below, once the arrow's colour is known.)
    if ns.minimapPin and not choice then pcall(ns.minimapPin.Update, ns.minimapPin, p, nil, nil) end
    local tk = choice and choice.goal.key
    local planKey = N.plan and #N.plan > 0 and (N.plan[1].goal.key .. ":" .. #N.plan) or ""
    if tk ~= N.lastTargetKey or planKey ~= N.lastPlanKey then
        N.lastTargetKey, N.lastPlanKey = tk, planKey
        -- Mark the NPC of the new step above its nameplate, every mob of the
        -- steps right by it (your waypoint's area), and (smaller) the NPCs of
        -- the next steps.
        if ns.questMarks and ns.questMarks.SetRouteTarget then
            local onRoute = N.plan and N.plan[1] and N.plan[1].goal.key == tk
            pcall(ns.questMarks.SetRouteTarget, choice and choice.goal.npcs, N.NextStopNames(N.plan, tk, 5),
                onRoute and N.HereNames(N.plan) or nil)
        end
    end
    if not choice then
        -- Nothing on this continent, but the dungeon run's steps are on the
        -- other one: say where, and how to get there (Dungeons.lua).
        local hint, sub = awayHint(p)
        if hint then
            frame.text:SetText(hint)
            frame.sub:SetText(sub or "")
            frame.arrow:Hide()
            frame:Show()
        elseif #goals == 0 and not ns.quests:Source() then
            frame.text:SetText("No directions yet")
            frame.sub:SetText("Install Questie + QuestieDB for quest locations")
            frame.arrow:Hide()
            frame:Show()
        else
            frame:Hide()
        end
        if frame.prof then frame.prof:Hide() end
        return
    end

    local wx, wy, how, length = steer(p, choice)
    -- In a kill or collect step's area: from group to group (AreaHop.lua).
    -- "go": the arrow points at the next group; "in": the ring, in a group.
    local hop
    if N.Hop then
        local okH, h = pcall(N.Hop, p, choice)
        hop = okH and type(h) == "table" and h or nil
    end
    if hop and hop.state == "go" then wx, wy, how, length = hop.wx, hop.wy, "hop", hop.d end
    N.how = how
    local b = bearing(p, wx, wy)
    local facing = N.ArrowFacing()
    if b and facing then
        frame.arrow:SetRotation(-(b + facing))
        frame.arrow:Show()
    else
        frame.arrow:Hide()
    end

    local g = choice.goal
    -- Your own waypoint clears itself when you get there.
    if g.key == "user:wp" and choice.d < 10 and ns.waypoint then
        ns.waypoint:Clear()
        ns:Print("arrived at your waypoint")
    end
    -- Reaching a shared step clears it for the whole party.
    local partyId = g.key:match("^party:(.+)$")
    if partyId and choice.d < 15 and ns.party then
        ns.party:Done(partyId)
        ns:Print("reached a shared step: " .. (g.title or "?"))
    end
    frame.text:SetText(g.text or g.title or "Next goal")
    -- A step with its own icon (craft here: the profession; use from your
    -- bags: a bag) shows it bouncing in the ring when you're there.
    if frame.arrow.SetCenterIcon then frame.arrow:SetCenterIcon(g.icon) end
    -- Arrived: at the step, or anywhere in a quest's area (near any spawn of
    -- its mobs / objects, not just the one point the route picked). Then the
    -- arrow is a pulsing ring - unless one of the quest's mobs or NPCs has a
    -- nameplate on screen: then the arrow points straight at it.
    local here = choice.d < ARRIVED * 2 or N:InArea(g, p)
    if hop then here = hop.state == "in" end   -- (a worked group isn't "here" any more: the arrow points on)
    N.arrived = here
    -- On the step's own point, not just somewhere in its area. A big area
    -- quest can have a profession step inside it (a node, a forge); that
    -- arrow should still point while you roam the area.
    N.arrivedSpot = N.AtStopPoint(choice.d)
    -- In the area it's the ring. (Pointing at the nearest Questie spawn spot
    -- was tried in 0.35.45: the spots are where things CAN spawn, not where
    -- they are, so the arrow jumped around and sent you back and forth.) The
    -- nearest spot is still used for one thing: standing on one makes the
    -- pillars wave.
    local _, spotD
    if here and g.area then _, spotD = N:NearestSpot(g, p) end
    if here then
        local tgt = N:VisibleTarget(g)
        if tgt then
            local ax, ay = frame:GetCenter()
            local s = frame:GetEffectiveScale()
            frame.arrow:SetArrived(false)
            frame.arrow:SetRotation(atan2(-(tgt.x / s - ax), tgt.y / s - ay))
            frame.arrow:Show()
            frame.sub:SetText("There: " .. tgt.name)
        else
            frame.arrow:SetArrived(true)
            frame.arrow:Show()
            frame.sub:SetText((hop and hop.text) or (choice.d < ARRIVED * 2 and "You're here" or "You're in the area"))
        end
    elseif how == "hop" then
        frame.sub:SetText(hop.text)
        frame.arrow:SetArrived(false)
    elseif N.ride then
        -- Who to talk to and how far they are (not the step's own distance:
        -- that's a flight away).
        frame.sub:SetText(ns.rides.Text(N.ride, how == "path" and length or N.ride.toNpc))
        frame.arrow:SetArrived(false)
    else
        frame.sub:SetText(string.format("%d yd%s%s%s", choice.d,
            N.TravelText(p, choice.point, (how == "path" or how == "gate") and length or choice.d),
            (not facing and b) and (" " .. compass(b)) or "",
            how == "path" and string.format(" (trail, %d yd walk)", length)
                or (how == "entrance" and " (it's inside: entrance first)")
                or (how == "gate" and N.GateText(N.via, length)) or "")
            .. (N.port and (": cast " .. N.port) or "")
            .. N.HearthCue(g.key, choice.point, choice.d, GetTime()))
        frame.arrow:SetArrived(false)
    end
    -- On a flight you can't steer: the arrow's two lines are the flight's
    -- (where to, landing in how long, and what comes after).
    local flyTitle, flySub = N.FlightNow(g.text or g.title)
    if flyTitle then
        frame.text:SetText(flyTitle)
        frame.sub:SetText(flySub)
    end
    -- A step that's a cast or a hearthstone away: that icon in the arrow's
    -- place, the arrow small beside it (TravelIcon.lua).
    if N.ShowTravel then pcall(N.ShowTravel, frame, g.key, choice.point, choice.d) end
    -- Right on the spot (on a spawn spot, or at the step itself): the pillars
    -- run a wave.
    if frame.arrow.SetWave then
        frame.arrow:SetWave(here and frame.arrow.arrived and ((spotD and spotD <= SPOT_ON) or choice.d < ARRIVED * 2))
    end
    local col
    if N:ArrowColorMode() == "distance" then
        -- Grey: in another zone; red far away to green close by; blue in the area.
        col = { N.ArrowColor(N.ArrowState(p, choice.point, here), choice.d) }
    else
        col = choice.waypoint and ns.theme.waypoint or ns.theme.route   -- your waypoint: green
    end
    frame.arrow:SetVertexColor(col[1], col[2], col[3])
    -- The world map's trail and target dot wear the same colour (MapOverlay).
    -- A new table only when the colour changes, so the map can tell.
    local ac = N.arrowColor
    if not (ac and ac[1] == col[1] and ac[2] == col[2] and ac[3] == col[3]) then N.arrowColor = col end
    N.arrowWaypoint = choice.waypoint and true or false
    -- The minimap dot: the arrow's colour, on the step (not on you).
    if ns.minimapPin then pcall(ns.minimapPin.Update, ns.minimapPin, p, N.DotPoint(choice, here), g, col, here) end
    updateProf(p)
    frame:Show()
    if panel and panel:IsShown() then showPanel()
    elseif ns.db.nav.drawerOpen and not N.drawerRestored then
        -- Open before the /reload: open again, once, now there's a step.
        N.drawerRestored = true
        showPanel()
    end
end

-------------------------------------------------------------------------------
-- Wiring
-------------------------------------------------------------------------------

-- busy: something changed (quest, level, item...) and the route is being
-- redone; the Flow Tracker spins its icon meanwhile. The quiet refresh every
-- 10 s doesn't count, or it would spin all the time.
-- The refresh gathers one step source per frame (~15 frames, a quarter
-- second), then plans in the frame after: all in one frame, a busy refresh
-- could take 30+ ms, a hitch you can see. A change that comes in while it
-- gathers gets one more refresh straight after.
local pendingCollect, gathering, again, busy = false, false, false, false
-- Why the refresh being gathered was asked for (an event, "every 30 s"...):
-- /flow perf lists each cause, how often and what its refreshes cost, so a
-- route that refreshes too often says what keeps asking.
local gatherWhy
local clock = debugprofilestop
function N.Busy() return busy end
function N.MarkAgain() if gathering then again = true end end
local collectSoon
local function finishRefresh()
    pendingCollect, gathering, busy = false, false, false
    if again then again = false; collectSoon(false, "a change while gathering") end
end
local function collectSpread()
    gathering = true
    local why, spent = gatherWhy or "?", 0
    local sources = {}
    for key, provider in ns:Each("navGoal") do sources[#sources + 1] = { key = key, provider = provider } end
    local list, i = {}, 0
    local function step()
        local t0 = clock and clock()
        i = i + 1
        local s = sources[i]
        if s then
            -- gatherFrom pcalls the source; this catches the rest, so a bad
            -- step can't leave the refresh stuck (no route updates ever again).
            local ok, err = pcall(gatherFrom, s.key, s.provider, list)
            if not ok and ns.db.rotation.debug then ns:Print("nav goal " .. s.key .. ": " .. tostring(err)) end
            if t0 then spent = spent + clock() - t0 end
            C_Timer.After(0, step)
            return
        end
        pcall(N.Collect, N, list)
        if t0 then spent = spent + clock() - t0 end
        if ns.perf and ns.perf.AddPart then ns.perf.AddPart("route: gather steps", why, spent) end
        finishRefresh()
    end
    step()
end
-- Lite mode (a raid, a dungeon, a battleground): the route is gathered at
-- most every N.LITE_GATHER seconds, however many quest and bag events come
-- in (each gathering is some 60 ms of work). Pure: gather now, or later?
N.LITE_GATHER = 20
function N.LiteGather(lite, sinceLast, gap)
    if not lite then return "now" end
    return (sinceLast or math.huge) >= (gap or N.LITE_GATHER) and "now" or "later"
end
collectSoon = function(quiet, why)
    if N.LiteGather(ns.Lite and ns.Lite(), GetTime() - (N.liteGatherAt or -1000)) == "later" then
        N.litePending = true
        return
    end
    N.liteGatherAt, N.litePending = GetTime(), nil
    if not quiet then busy = true end
    if pendingCollect then
        -- Waiting the 1 s: this change is picked up anyway. Gathering: the
        -- sources already read may be out of date, so go again after.
        if gathering and not quiet then again = true end
        return
    end
    pendingCollect = true
    gatherWhy = why or (quiet and "every 30 s") or "?"
    C_Timer.After(1, collectSpread)
end
local function scheduleCollect(why) collectSoon(false, why) end
-- Other modules: re-plan soon (throttled). `why` names the cause in /flow perf.
function N.RequestCollect(why) collectSoon(false, type(why) == "string" and why or "another part of Flow") end

-- Money changed: re-plan only when it crosses a skipped step's cost (so it
-- comes back) or drops below a planned step's cost (so it's skipped).
ns:On("PLAYER_MONEY", function()
    local money = GetMoney()
    for _, d in pairs(ns.db.nav.deferred or {}) do
        if d.cost and d.cost <= money then scheduleCollect("money") return end
    end
    for _, g in ipairs(goals or {}) do
        if g.cost and g.cost > money then scheduleCollect("money") return end
    end
end)

-- Per character: the steps you hid, money-blocked steps, your Custom route
-- pick. (Trails, cave entrances and settings stay shared: they're the same
-- for everyone.) Steps hidden before the split stay hidden for everyone.
ns:PerCharacter("nav.hidden", { adopt = function(old) return old end })
ns:PerCharacter("nav.deferred")
ns:PerCharacter("nav.selectedKey")
-- How many steps the map and the Flow Tracker show: each character's own, so
-- a new character always starts with "Next step only" (nothing saved = 1),
-- simple, whatever your other characters chose.
ns:PerCharacter("nav.stopsShown")
ns:PerCharacter("nav.stopsArea")

ns:OnLoad(function(saved)
    saved.nav = saved.nav or {}
    saved.nav.graphs = saved.nav.graphs or {}
    if saved.nav.enabled == nil then saved.nav.enabled = true end
    if saved.nav.learn == nil then saved.nav.learn = true end
    -- Restore your Custom route's pick from before the reload ("selected" is
    -- the older name of "custom").
    N.loadedAt = GetTime()
    if saved.nav.sorter == "selected" then saved.nav.sorter = "custom" end
    -- 0.35.157: the three routes became one tick per kind of step. Once: your
    -- saved route (Quests only / Optimal / Completionist, professions on or
    -- off) becomes the same ticks.
    if saved.nav.kinds == nil then saved.nav.kinds = N.ModeKinds(saved.nav.mode or "optimal", saved.nav.professions) end
    -- The modern arrow came after "3D" was the default (and the old switch
    -- could only say 3D or flat): a saved "3D" moves to the modern one, once.
    if not saved.nav.arrowModern then
        saved.nav.arrowModern = true
        if saved.nav.arrowStyle == "3d" then saved.nav.arrowStyle = nil end
    end
    if saved.nav.selectedKey then N.selection = { first = saved.nav.selectedKey } end
    ns.theme:UpdateRoute()
    frame = buildArrow()
    local acc, collectAcc = 0, 0
    local timedUpdate = ns.perf.Wrap("arrow + minimap (10/s)", update)
    local driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(_, dt)
        acc, collectAcc = acc + dt, collectAcc + dt
        -- Quiet refresh: events (quests, items, level, skills) already
        -- re-plan at once; this only catches what has no event. Every 30 s:
        -- each rebuild is ~20-40 ms (/flow perf).
        local lite = ns.Lite and ns.Lite()
        if collectAcc > 30 and not lite then collectAcc = 0; collectSoon(true) end
        -- (What lite mode held back: once its gap has passed, or lite mode has ended.)
        if N.litePending and N.LiteGather(lite, GetTime() - (N.liteGatherAt or -1000)) == "now" then collectSoon(true, "held back in lite mode") end
        if acc < (lite and 0.5 or 0.1) then return end   -- lite (dungeon, raid, boss): 2 a second
        acc = 0
        local ok, err = pcall(timedUpdate)
        if not ok then
            if err ~= N.lastError then ns:Log("nav", err) end
            N.lastError = err
            if ns.db.rotation.debug then ns:Print("nav: " .. tostring(err)) end
        end
    end)
end)

for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "QUEST_ACCEPTED",
                      "QUEST_TURNED_IN", "ZONE_CHANGED_NEW_AREA", "PLAYER_LEVEL_UP",
                      "SKILL_LINES_CHANGED", "TRAINER_CLOSED", "LEARNED_SPELL_IN_TAB", "LEARNED_SPELL_IN_SKILL_LINE" }) do
    ns:On(ev, function() scheduleCollect(ev) end)
end

-- The game fires QUEST_LOG_UPDATE for many things that change nothing: 25 of
-- 71 route refreshes in six minutes were this event, each about 22 ms with
-- the re-plan it sets off (/flow perf, 0.35.152). So the route refreshes
-- only when your log really differs: a quest added or gone, an objective's
-- count, a quest completed.
function N.LogSignature(entries)
    local parts = {}
    for _, q in ipairs(entries or {}) do
        parts[#parts + 1] = tostring(q.id) .. (q.complete and "!" or "")
        for _, o in ipairs(q.objectives or {}) do
            parts[#parts + 1] = tostring(o.text) .. (o.finished and "+" or "")
        end
    end
    return table.concat(parts, "|")
end
-- true when `sig` differs from the last one seen (nil: couldn't read the log: refresh).
local lastLog
function N.LogChanged(sig)
    if sig ~= nil and sig == lastLog then return false end
    lastLog = sig
    return true
end
ns:On("QUEST_LOG_UPDATE", function()
    local ok, sig = pcall(function() return N.LogSignature(ns.quests.LogEntries()) end)
    if N.LogChanged(ok and sig or nil) then scheduleCollect("QUEST_LOG_UPDATE") end
end)

ns.commands.nav = function(arg)
    arg = (arg or ""):lower()
    local cfg = ns.db.nav
    if arg == "on" or arg == "off" then
        cfg.enabled = (arg == "on")
        ns:Print("navigation arrow " .. arg)
    elseif arg:find("^profarrow") then
        local v = arg:match("^profarrow%s+(%a+)")
        if v == "on" or v == "off" then N:SetProfArrow(v == "on") end
        ns:Print("faint profession arrow: " .. (cfg.profArrow == true and "on" or "off")
            .. (N:ProfPointerOn() and "" or " (shows with Professions ticked in the route menu)"))
    elseif arg:find("^professions") then
        local v = arg:match("^professions%s+(%a+)")
        N:SetKind("professions", v ~= "off")
        ns:Print("professions on the route: " .. (N:Includes("professions") and "on" or "off"))
    elseif arg:find("^include") then
        -- /flow nav include all|none, or <kind> on|off (the route menu's ticks).
        local what, v = arg:match("^include%s+(%S+)%s*(%a*)")
        if what == "all" or what == "none" then
            N:SetAllKinds(what == "all")
        elseif what then
            for _, k in ipairs(N.Kinds()) do
                if k.key:lower() == what then N:SetKind(k.key, v ~= "off") end
            end
        end
        local names = {}
        for _, k in ipairs(N.Kinds()) do names[#names + 1] = k.key .. (N:Includes(k.key) and " on" or " off") end
        ns:Print("route includes: " .. table.concat(names, ", ") .. ". /flow nav include all|none|<kind> on|off")
    elseif arg:find("^sort") then
        -- Any registered route objective (XpValue.lua): /flow nav sort <key>.
        local key = arg:match("^sort%s+(%S+)")
        if key then
            ns.xpValue:SetMode(key)
            ns:Print("route optimises for: " .. (select(2, ns.xpValue:Objective()).label or key))
        else
            ns:Print("route orders (now: " .. (ns.xpValue:Objective()) .. "):")
            for _, o in ipairs(ns.xpValue:List()) do print("  " .. o.key .. " - " .. o.label) end
            print("  /flow nav sort <key>")
        end
    elseif arg:find("^st[eo]ps") then
        -- How many upcoming steps the map and the Flow Tracker show.
        local v = arg:match("^st[eo]ps%s+(%S+)")
        local n = v and tonumber(v)
        if v == "area" then
            N:SetArea(true)
            ns:Print("steps on the map and in the Flow Tracker: " .. N:StopsShownLabel())
        elseif v == "all" or (n and n >= 1) then
            N:SetStopsShown(n)
            ns:Print("steps on the map and in the Flow Tracker: " .. N:StopsShownLabel())
        else
            ns:Print("steps shown: " .. N:StopsShownLabel() .. ". /flow nav steps area|1|3|5|10|all (any number works)")
        end
    elseif arg == "xp" or arg == "xp on" or arg == "xp off" or arg == "distance" then
        ns.xpValue:Set(arg ~= "xp off" and arg ~= "distance")
        ns:Print("route sorting: " .. (ns.xpValue:On() and "most XP first" or "shortest path"))
    elseif arg == "unhide" or arg == "hidden" then
        -- Bring back every step you hid (right-click), or list them.
        local n = 0
        for _ in pairs(cfg.hidden or {}) do n = n + 1 end
        if arg == "hidden" then
            ns:Print(n .. " hidden stop(s):")
            for _, g in ipairs(N.hiddenGoals or {}) do ns:Print("  " .. (g.text or g.title or g.key)) end
            ns:Print("/flow nav unhide brings them all back")
        else
            cfg.hidden = {}
            N:Collect()
            ns:Print(n .. " hidden stop(s) back on the route.")
        end
    elseif arg == "arrow modern" or arg == "arrow 3d" or arg == "arrow flat" then
        N:SetArrowStyle(arg:match("^arrow (%w+)$"))
        ns:Print("arrow: " .. N:ArrowStyle())
    elseif arg == "arrowcolor distance" or arg == "arrowcolor route" or arg == "arrowcolor" then
        if arg ~= "arrowcolor" then N:SetArrowColorMode(arg:match("^arrowcolor (%a+)$")) end
        ns:Print("arrow colour: " .. (N:ArrowColorMode() == "distance"
            and "by distance (grey: another zone, orange to green: closing in, blue: in the area)"
            or "the route's colour (your waypoint green)") .. ". /flow nav arrowcolor distance|route")
    elseif arg == "why" then
        -- What the route is made of, and what Flow wanted but couldn't place.
        ns:Print(string.format("route: includes %s; Questie %s",
            N.KindsSummary(function(k) return N:Includes(k) end),
            ns.quests:Source() and ns.quests:Source().label or "not found"))
        local byProvider = {}
        for _, g in ipairs(goals) do
            local placed = g.points and #g.points > 0
            local b = byProvider[g.provider] or { n = 0, placed = 0 }
            b.n = b.n + 1
            if placed then b.placed = b.placed + 1 end
            byProvider[g.provider] = b
        end
        for prov, b in pairs(byProvider) do
            print(string.format("  %s: %d goal(s), %d with a location", prov, b.n, b.placed))
        end
        -- The quests-to-pick-up scan: what it looked at and why it left some out.
        local st = ns.quests.scanStats
        if not st then
            print("  quests to pick up: scan not finished yet")
        elseif st.failed then
            print("  quests to pick up: scan failed: " .. st.failed)
        else
            print(string.format("  quests to pick up: %d kept (%d not done, %d here, %d too high level, %d not for you, %d wait for an earlier part)",
                st.kept or 0, st.scanned or 0, st.here or 0, st.level or 0, st.notDoable or 0, st.chain or 0))
        end
        local missing = {}
        for name in pairs(ns.places.missing or {}) do missing[#missing + 1] = name end
        if #missing > 0 then
            print("  couldn't find on the map: " .. table.concat(missing, ", "))
            print("  (talk to them once and Flow remembers where they stand)")
            table.sort(missing)
            for i = 1, math.min(3, #missing) do print("    " .. ns.places:Explain(missing[i])) end
        end
        -- Quests in your log Flow can't put on the route, and why (Goals.lua).
        for _, u in ipairs(ns.quests.unplaced or {}) do
            print(string.format("  can't place: %s [%s] - %s", tostring(u.title), tostring(u.id), u.why))
        end
        for _, e in ipairs(ns.quests.classSteps or {}) do
            print("  class quest: " .. ns.quests.ClassQuestLine(e))
        end
        -- How you leave where you are: a ride (Rides.lua), your hearthstone (Hearth.lua).
        if N.ride then print("  way out: " .. ns.rides.Text(N.ride)) elseif N.rideHint then print("  way out: " .. N.rideHint) end
        if ns.hearth and ns.hearth.Line then print("  " .. ns.hearth.Line()) end
        local here = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        print("  your map: " .. tostring(here) .. ", Elwynn zone lookup: " .. tostring(ns.quests:UiMapForArea(12)))
        print("  plan: " .. (N.plan and #N.plan or 0) .. " stop(s)")
        -- The route itself (also saved in the diagnostics for Claude to check).
        local free, max = ns.quests:FreeSlots()
        print(string.format("  quest log: %d free of %d; bound to %s", free, max, tostring(GetBindLocation and GetBindLocation())))
        for _, g in ipairs(N.blockedGoals or {}) do
            print(string.format("  blocked: %s - %s [%s]", tostring(g.text or g.title), tostring(g.blockedBy), g.key))
        end
        local nHidden = 0
        for _ in pairs(cfg.hidden or {}) do nHidden = nHidden + 1 end
        if nHidden > 0 then print(string.format("  hidden by you: %d stop(s) (/flow nav unhide)", nHidden)) end
        local labels = N:PlanLabels(N.plan or {})
        for i, s in ipairs(N.plan or {}) do
            if i > 25 then print("  ...") break end
            print(string.format("  %s %s  +%d yd  [%s]", labels[i], s.goal.text or s.goal.title or "?", s.leg or 0, s.goal.key))
        end
        local p = N:PlayerPos()
        if p then print(string.format("  you: map %d at %.1f, %.1f", p.map, p.x * 100, p.y * 100)) end
        -- Objectives in your log that didn't make this plan (it takes the 14
        -- nearest steps): how far their nearest known spot is, and how many
        -- spots Flow kept of the ones Questie knows.
        if p then
            local onRoute = {}
            for _, s in ipairs(N.plan or {}) do onRoute[s.goal.key] = true end
            for _, g in ipairs(goals) do
                if g.key:find("^%d+:%d+$") and not onRoute[g.key] then
                    local _, d = nearestPoint(g, p)
                    print(string.format("  not on this plan: %s  nearest spot %s, %d spot(s) of %s known  [%s]",
                        tostring(g.text or g.title), d and (math.floor(d) .. " yd") or "none here",
                        g.points and #g.points or 0, tostring(g.known or "?"), g.key))
                end
            end
        end
    elseif arg == "quests" or arg == "optimal" or arg == "complete" then
        N:SetMode(arg)
        ns:Print(arg == "quests" and "following your current quests only"
            or arg == "complete" and "completionist: every quest in the zones you're questing in, any level, shortest order"
            or "following the optimal path (quests, pickups, trainers, skill-ups)")
    elseif arg == "learn" then
        cfg.learn = not cfg.learn
        ns:Print("trail learning " .. (cfg.learn and "on" or "off"))
    elseif arg == "forget" then
        wipe(cfg.graphs); wipe(grids); route = nil; lastNode = nil
        ns:Print("forgot all learned trails")
    else
        local nodes = 0
        for _, g in pairs(cfg.graphs) do nodes = nodes + #g.x end
        ns:Print(string.format("%d goals, %d learned trail points. Last error: %s",
            #goals, nodes, tostring(N.lastError or "none")))
        print("  /flow nav on|off|learn|forget. Ctrl-drag the arrow to move it.")
    end
end

-- Timed for /flow perf.
N.Collect = ns.perf.Wrap("route: gather steps", N.Collect)
ns.perf.PartsLabel("route: gather steps", "refreshed after", 8)   -- (each cause: collectSpread)

-- A Flow window you can switch off (/flow nav off): the menus offer it back (Menu.lua).
-- The Flow menu's "Arrow" section: its style (one of three), its colour,
-- the faint profession arrow's text, and the drawer back beside it.
function N:ArrowMenuItems()
    local items = {}
    for _, st in ipairs(N.ARROW_STYLES) do
        items[#items + 1] = { text = st[2], radio = true, checked = N:ArrowStyle() == st[1],
            func = function() N:SetArrowStyle(st[1]) end }
    end
    items[#items + 1] = { text = "Colour by distance", checked = N:ArrowColorMode() == "distance",
        tip = "Ticked: grey in another zone, orange to green as you close in, blue in the area. Not ticked: the route's colour.",
        func = function() N:SetArrowColorMode(N:ArrowColorMode() == "distance" and "route" or "distance") end }
    local cfg = ns.db.nav
    -- (The faint arrow itself is a tick under "Route includes".)
    if cfg.profArrow == true then
        items[#items + 1] = { text = "Text under the faint profession arrow", checked = cfg.profArrowText ~= false,
            func = function() cfg.profArrowText = (cfg.profArrowText == false) end }
    end
    -- (Only once you've Ctrl-dragged the drawer somewhere of its own.)
    if cfg.drawerPoint then
        items[#items + 1] = { text = "Drawer next to the arrow (again)", func = function()
            cfg.drawerPoint = nil
            if panel and panel:IsShown() then panel.side = placeDrawer(panel, frame) end
        end }
    end
    return items
end

ns:Register("window", "arrow", { name = "Flow Arrow", order = 10,
    hidden = function() return ns.db.nav.enabled == false end,
    show = function() ns.commands.nav("on") end,
    hide = function() ns.commands.nav("off") end })

-- Options > AddOns > Flow, under "Flow".
if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck({
        group = "route",
        label = "Faint profession arrow",
        note = "(with Professions on the route)",
        tip = "Profession steps (training, skill-ups) get their own route and a faint dark grey arrow behind "
            .. "the main one, with their name above it. The main arrow then only takes you to quests. "
            .. "Off (default): profession steps stay on the main arrow's route, where the Flow key does their steps.",
        get = function() return ns.db.nav.profArrow == true end,
        set = function(on) N:SetProfArrow(on) end,
    })
    ns.settings:AddCheck({
        group = "route",
        label = "Finish the selected zones first",
        note = "(tick them in the Flow menu, Zones)",
        tip = "On: the route does the zones ticked in the Flow menu (Zones) first, and the other zones' quests after them. "
            .. "Off (default): a zone you untick there is left out of the route.",
        get = function() return N.ZonesFirstOn() end,
        set = function(on) N.SetZonesFirst(on) end,
    })
    ns.settings:AddCheck({
        group = "route",
        label = "Finish the area you're in first",
        note = "(steps within 300 yd)",
        tip = "Off (default): the arrow follows the shortest whole trip. On: the route clears the steps "
            .. "around you before it sends you the other way, unless going the other way first saves a lot "
            .. "of walking. Quests to pick up nearby count as part of the area.",
        get = function() return ns.db.nav.areaFirst == true end,
        set = function(on) ns.db.nav.areaFirst = on and true or false; N.planDirty = true end,
    })
end
