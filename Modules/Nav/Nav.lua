-- Navigation arrow: points at your next goal (a quest mob, an item source, a
-- turn-in NPC...), with a short sentence and the distance. Left-click for
-- details, right-click to switch to the next goal, shift-drag to move.
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
    local f = map and flatMap(map)
    if f then return f.cont, f.ox + x * f.ux + y * f.vx, f.oy + x * f.uy + y * f.vy end
    return gameToWorld(map, x, y)
end

-- East/south unit vectors of a map in world space, so world offsets can be
-- turned into a compass bearing without caring how world axes are oriented.
local axes = {}
local function mapAxes(map)
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

local lastNode, lastCont, lastIndoor
local function record(p)
    if (UnitOnTaxi and UnitOnTaxi("player")) or (IsFlying and IsFlying()) then lastNode = nil return end
    local speed = A.Safe(GetUnitSpeed("player")) or 0
    if speed == 0 then return end
    if lastCont ~= p.cont then lastNode, lastCont = nil, p.cont end
    local g = graph(p.cont)
    if lastNode then
        local d = dist(p.wx, p.wy, g.x[lastNode], g.y[lastNode])
        if d < SPACING then return end
        if d > MAX_EDGE then lastNode = nil end
    end
    local n = nearestNode(p.cont, p.wx, p.wy, SNAP) or addNode(p.cont, p.wx, p.wy)
    -- Caves and buildings: trail points walked indoors are marked, and the
    -- spot where you went from outdoors to indoors is kept as an entrance.
    local indoor = IsIndoors and IsIndoors() or false
    if n and indoor then g.indoor = g.indoor or {}; g.indoor[n] = true end
    if indoor and lastIndoor == false then N:AddEntrance(p) end
    lastIndoor = indoor
    if n and lastNode and n ~= lastNode then link(g, lastNode, n) end
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
    heapPush(open, s, dist(g.x[s], g.y[s], tx, ty))
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
                local ng = gScore[cur] + dist(g.x[cur], g.y[cur], g.x[nb], g.y[nb])
                if not gScore[nb] or ng < gScore[nb] then
                    gScore[nb] = ng
                    came[nb] = cur
                    heapPush(open, nb, ng + dist(g.x[nb], g.y[nb], tx, ty))
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

function N:Coin(c)
    return GetCoinTextureString and GetCoinTextureString(c or 0) or ((c or 0) .. "c")
end

local timedProviders = {}   -- each stop source timed on its own in /flow perf
-- One stop source's goals, added to `list`.
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
    if not list then
        list = {}
        for key, provider in ns:Each("navGoal") do gatherFrom(key, provider, list) end
    end
    -- Blocked stops stay off the route but are listed (with a lock and the
    -- reason) on the map list and the tracker:
    --   goal.blockedBy = "needs Mining"     set by the goal's provider
    --   goal.cost = copper                  blocked while you have less money
    -- Money-blocked stops are remembered in ns.db.nav.deferred. When your
    -- money reaches the cost (PLAYER_MONEY below) they come back and are
    -- planned like any other stop: by distance and weight, so a trainer you're
    -- standing near (say, after a hearth) goes to the top by itself.
    local money = GetMoney and GetMoney() or 0
    local deferred = ns.db.nav.deferred or {}
    ns.db.nav.deferred = deferred
    local present, kept, blockedGoals = {}, {}, {}
    for _, g in ipairs(list) do
        present[g.key] = true
        if g.cost and g.cost > money then
            if not deferred[g.key] then
                ns:Print(string.format("skipping %s for now: it costs %s and you have %s. It comes back on the route once you can pay.",
                    g.title or g.text or g.key, N:Coin(g.cost), N:Coin(money)))
            end
            deferred[g.key] = { text = g.title or g.text, cost = g.cost, since = deferred[g.key] and deferred[g.key].since or time() }
            g.blockedBy = string.format("needs %s (you have %s)", N:Coin(g.cost), N:Coin(money))
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
    -- Route mode: "quests" = only quests already in your log (their objectives
    -- and turn-ins), plus the party route; "optimal" (default)
    -- = everything worth doing: pickups, trainers, fishing/gathering too.
    if N:Mode() == "quests" then
        local questsOnly = {}
        for _, g in ipairs(list) do
            if g.key:find("^%d+:") or g.key:find("^party:") or g.key:find("^help:") then
                questsOnly[#questsOnly + 1] = g
            end
        end
        list = questsOnly
    end
    -- "Just <name>'s" quests (PartyHelp.lua): only theirs, and yours where
    -- they need the same thing.
    if ns.partyHelp then list = ns.partyHelp:FilterGoals(list) end
    -- Stops you hid (right-click on the map) stay out of the route; they're
    -- kept in N.hiddenGoals so the map panel can list and unhide them.
    local hidden = ns.db.nav.hidden or {}
    local shown, hiddenGoals = {}, {}
    for _, g in ipairs(list) do
        if hidden[g.key] then hiddenGoals[#hiddenGoals + 1] = g else shown[#shown + 1] = g end
    end
    N.hiddenGoals = hiddenGoals
    -- "Along the way" goals (loot meat for an optional profession): never a
    -- stop of their own, so the route never sends you off to grind them.
    -- They're listed in the arrow panel and stop cards, and their mobs are
    -- worth looting when you meet them anyway.
    local routed, along = {}, {}
    for _, g in ipairs(shown) do
        if g.along then along[#along + 1] = g else routed[#routed + 1] = g end
    end
    N.alongGoals = along
    shown = routed
    -- XP-first sorting (XpValue.lua): weights by XP and quest level; also adds XP to tooltips.
    -- and the route objective (what the route optimises; XpValue.lua) weighs
    -- the stops and may pick which ones count.
    if ns.xpValue then
        local okA, picked = pcall(ns.xpValue.Apply, ns.xpValue, shown)
        if okA and picked then shown = picked end
    end
    goals = shown
    N.planDirty = true
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

function N:Mode() return (ns.db.nav and ns.db.nav.mode) or "optimal" end

-- Route modes: "quests" (only your log), "optimal" (everything worth the XP),
-- "complete" (completionist: every quest you can still do in the zones
-- you're questing in, whatever its level, in the shortest order).
function N:SetMode(mode)
    ns.db.nav.mode = (mode == "quests" or mode == "complete") and mode or "optimal"
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
    -- The stop's own icon in the middle instead of the dot (cooking, a bag...).
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
-- 3D arrow (the default look; /flow nav arrow flat for the line arrow).
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
    -- The stop's own icon in place of the ball (the cooking icon at "Make 4 x
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

-- The arrow in the style you chose: "3d" (default) or "flat".
function N:MakeArrow(parent)
    if ns.db.nav.arrowStyle == "flat" then return self:MakeHudArrow(parent) end
    return self:MakeArrow3D(parent)
end

-- Switch styles on the fly (arrow menu, /flow nav arrow).
function N:SetArrowStyle(style)
    ns.db.nav.arrowStyle = (style == "flat") and "flat" or "3d"
    local frame = N.arrowFrame
    if frame and frame.arrow then
        local old = frame.arrow
        old:Hide(); old:SetScript("OnUpdate", nil)
        frame.arrow = self:MakeArrow(frame)
        frame.arrow:SetVertexColor(old.r or 1, old.g or 0.62, old.b or 0)
        frame.arrow:SetRotation(old.angle or 0)
        if old.arrived then frame.arrow:SetArrived(true) end
    end
end

-- Shared look for route stops (trip plan, world map pins, map list):
--   label "3 [9]" = 3rd stop, quest level 9; "!2 [8]" = 2nd quest pickup
--   colour: route colour (green) = where the arrow points now, blue = quest pickup,
--           sky blue = your waypoint, bluish green = the rest of the route
-- A blocked stop for lists: lock (or coin) icon, greyed text, and the reason.
local LOCK = "Interface\\Buttons\\LockButton-Locked-Up"
function N:FormatBlocked(goal)
    return string.format("|T%s:12:12|t |cff9a9a9a%s|r", goal.blockIcon or LOCK, goal.text or goal.title or "?"),
           "|cffff7070" .. (goal.blockedBy or "blocked") .. "|r"
end

-- The NPC names of the next `n` stops after the current one (currentKey), for
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

function N:PlanLabels(plan)
    local out, pickups = {}, 0
    for i, s in ipairs(plan or {}) do
        local isPickup = s.goal.key:find("^pickup:") ~= nil
        if isPickup then pickups = pickups + 1 end
        out[i] = (isPickup and ("!" .. pickups) or tostring(i))
            .. (s.goal.level and string.format(" [%d]", s.goal.level) or "")
    end
    return out
end

-- Stops on the map: how many upcoming stops the world map and the Flow
-- Tracker show. Returns the number, or nil for all of them. Saved: nothing
-- = 1, just the next stop (the default); 0 = all.
-- The whole trip is still planned (the next stop depends on everything after
-- it), and the Flow Router still lists all of it so you can pick any stop.
N.STOP_CHOICES = { 1, 3, 5, 10 }
function N:StopsShown()
    local saved = ns.db.nav.stopsShown
    if saved == nil then return 1 end
    local n = tonumber(saved)
    if n and n >= 1 then return math.floor(n) end
    return nil
end
-- Is stop i drawn? Past your limit only the stop you point at is.
-- (Named StopVisible: it was ShowStop too, the same name as the stop card
-- below, and the card's later definition replaced it, so every map and
-- Tracker call failed with "attempt to index local 'goal' (a number)".)
function N:StopVisible(i, pointed)
    local limit = self:StopsShown()
    return (pointed and true) or limit == nil or i <= limit
end
function N:SetStopsShown(n)
    n = tonumber(n)
    ns.db.nav.stopsShown = (n and n >= 1) and math.floor(n) or 0   -- (0 = all; nothing saved = 1)
    if ns.mapOverlay and WorldMapFrame and WorldMapFrame:IsShown() then pcall(ns.mapOverlay.Redraw, ns.mapOverlay) end
    if ns.routeTracker then pcall(ns.routeTracker.Refresh, ns.routeTracker) end
end
function N:StopsShownLabel(n)
    if n == nil then n = self:StopsShown() end
    if not n or n < 1 then return "All stops" end
    if n == 1 then return "Next stop only" end
    return string.format("Next %d stops", n)
end

-- The kind of a stop (accept, turnin, kill, collect, ...): set by the goal's
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

-- Colour for a stop: by its kind (see Theme.lua kinds).
function N:StopColor(i, goal)
    local kinds = ns.theme.kinds
    local k = kinds[self:StopKind(goal)]
    return k and k.color or ns.theme.current
end

-- "icon number text" for lists: the number is in the route colour for the stop the arrow
-- points at now, grey for the rest; the text takes the kind's colour.
function N:FormatStop(i, goal, label)
    local kindName = self:StopKind(goal)
    local kind = ns.theme.kinds[kindName]
    local path = kind and kind.icon
    -- Profession stops show that profession's own icon (pickaxe, anvil...).
    local prof = goal.key:match("^train:(.+)$") or goal.key:match("^skill:(.+)$")
    if prof and ns.disposition and ns.disposition.PROF_ICON[prof] then path = ns.disposition.PROF_ICON[prof] end
    local icon = path and string.format("|T%s:13:13|t ", path) or ""
    -- Objectives of a quest you're on: the game's in-progress "?" (grey) first,
    -- so every quest stop shows a quest icon (accept "!" and turn-in "?" already do).
    if goal.key:find("^%d+:%d+$") then
        icon = "|TInterface\\GossipFrame\\ActiveQuestIcon:13:13:0:0:16:16:0:16:0:16:150:150:150|t" .. icon
    end
    local numColor = (i == 1) and ns.theme.route.hex or "999999"
    local textColor = kind and kind.color.hex or "ffffff"
    -- A stop in another zone, waiting until this zone is done: says where.
    local where = goal.awayZone and string.format(" |cff888888(%s, after this zone)|r", goal.awayZone) or ""
    return string.format("%s|cff%s%s|r |cff%s%s|r%s", icon, numColor, label or tostring(i),
        textColor, goal.text or goal.title or "?", where)
end

-------------------------------------------------------------------------------
-- Finish a zone before leaving it. Quest stops in your zone come before
-- stops in another zone, except:
--   * quests too low (reduced XP) or too high (3+ levels above) for you: they
--     don't hold you here
--   * a stop just over the border (within BRIEF yards of you) and your class
--     trainer (a milestone): short trips that don't wait
--   * a stop here that needs one over there first (its objectives are in the
--     next zone) can't hold you here either
-- The waiting stops say "(Westfall, after this zone)", and the Flow Router and
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

local function isQuestStop(key)
    return key:find("^%d+:") ~= nil or key:find("^pickup:") ~= nil or key:find("^help:") ~= nil
end

-- Which stops hold you in `zone` (here) and which wait (away); nil, nil when
-- there's nothing to hold you or nowhere else to go.
function N.AreaSplit(list, zone, p, zoneOf)
    local here, away, byKey = {}, {}, {}
    for _, g in ipairs(list) do
        byKey[g.key] = g
        local inZone, nearest = false, nil
        for _, pt in ipairs(g.points or {}) do
            if pt.map and zoneOf(pt.map) == zone then inZone = true end
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
--   first : the next stop you picked (its ^ in the Flow Router, "Go here
--           first"). That makes it a Custom route (orange): this stop first,
--           with the (o), the rest planned after it. It stays Custom until you
--           pick Most XP or Shortest again (or click the (o) of your pick).
--   tour  : stops that must all come before anything else (picking one of the
--           "!" quest pickups puts all pickups first: !3 -> the other pickups
--           -> then the normal plan)
-- Your own waypoint (Waypoint.lua) is NOT part of the route: see
-- N.WaypointChoice (the arrow follows it in green while it's set).
-------------------------------------------------------------------------------

N.planVersion = 0

-- This hub's business before heading out, like a walkthrough: turn in every
-- finished quest near you, then pick up the quests here (nearest first,
-- capped at the free quest log slots; each turn-in frees one). Turn-ins used
-- to be left out, so a hand-in right next to you waited behind every pickup.
local HUB_RADIUS = 250  -- yards
local function ready(g, present)
    for _, dep in ipairs(g.deps or {}) do if present[dep] then return false end end
    return true
end
function N:PickupKeys(radius)
    local p = self:PlayerPos()
    if not p then return nil end
    local present = {}
    for _, g in ipairs(goals) do present[g.key] = true end
    local near, turnins = {}, {}
    for _, g in ipairs(goals) do
        local isPickup = g.provider == "pickups"
        local isTurnin = g.key:find(":done$") and ready(g, present)
        if isPickup or isTurnin then
            local _, d = nearestPoint(g, p)
            if d and d <= (radius or HUB_RADIUS) then
                local list = isTurnin and turnins or near
                list[#list + 1] = { key = g.key, d = d }
            end
        end
    end
    table.sort(near, function(a, b) return a.d < b.d end)
    local free = (ns.quests.FreeSlots and ns.quests:FreeSlots() or 20) + #turnins
    local t, any = {}, false
    for _, e in ipairs(turnins) do t[e.key] = true; any = true end
    for i = 1, math.min(#near, free) do t[near[i].key] = true; any = true end
    return any and t or nil
end

function N:Select(key)
    -- On a shared party route, choosing edits the shared route instead:
    -- a shared stop moves to the front; anything else is added at the front.
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
    -- Picking a stop: Custom route (orange). Clearing it: back to optimised
    -- (your last objective).
    if key then
        ns.db.nav.sorter = "custom"
    elseif ns.db.nav.sorter == "custom" or ns.db.nav.sorter == "selected" then
        ns.db.nav.sorter = ns.xpValue and ns.xpValue:Base() or "xp"
    end
    ns.theme:UpdateRoute()
    self.planDirty = true
    pinnedKey = nil
end

function N:ClearSelection() self:Select(nil) end

-- Open what a stop is about, without changing the route (tracker clicks,
-- arrow menu): a quest in your log opens in the quest log; anything else
-- opens the world map on that stop, highlighted.
local function questLogIndex(id)
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then return C_QuestLog.GetLogIndexForQuestID(id) end
    if GetQuestLogIndexByID then
        local i = GetQuestLogIndexByID(id)
        if i and i > 0 then return i end
    end
end

-- One readable tooltip for any stop (map pins, map list, tracker, minimap):
--   title (gold) with the stop type icon and level
--   WHAT TO DO: the objective or task, large and white
--   quest objectives with progress (done ones green), the quest text (short)
--   details from the stop's provider, XP, blocked reason
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

function N:FillTooltip(tt, goal, footer)
    local kind = ns.theme.kinds[self:StopKind(goal)]
    local icon = kind and string.format("|T%s:16:16|t ", kind.icon) or ""
    local title = goal.title or goal.text or "?"
    tt:AddLine(icon .. title .. (goal.level and string.format("  |cff999999[%d]|r", goal.level) or ""), 1, 0.82, 0.25, true)
    -- What to do: the line your eyes should land on.
    local task = goal.text or title
    if goal.title and task:sub(1, #goal.title + 2) == goal.title .. ": " then task = task:sub(#goal.title + 3) end
    tt:AddLine(" ")
    tt:AddLine(task, 1, 1, 1, true)
    if goal.blockedBy then tt:AddLine("Blocked: " .. goal.blockedBy, 1, 0.45, 0.45, true) end
    -- Inside a cave or building (learned from your trails): say so, the arrow
    -- goes through the entrance.
    local pt = goal.points and goal.points[1]
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
            else tt:AddLine(d, 0.8, 0.8, 0.8, true) end
        end
    end
    if footer then tt:AddLine(" "); tt:AddLine(footer, 0.55, 0.55, 0.55, true) end
end

-- Clicking a stop (Flow Router row or pin, tracker row, map area) opens
-- Flow's own card for it next to what you clicked (N:ShowStop, below). The
-- game's quest log, which folds the Flow Router away, is a link on the card.
function N:OpenStop(goal, anchor)
    if not goal then return end
    if N.ShowStop then return N:ShowStop(goal, anchor) end
    return N:OpenInGame(goal)
end

-- A stop in the game's own windows, WITHOUT calling the game's map or
-- quest-log functions from Flow's code (QuestMapFrame_OpenToQuestDetails,
-- ToggleWorldMap, SetMapID...): those run the map from add-on code and taint
-- it, and in a later fight the map's own buttons get blocked (0.35.47). So:
-- the quest is selected in your log (you open it with L or M, so the game
-- runs its own window), and Flow's map layer highlights the stop for the
-- next 20 seconds.
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
    -- a stop chosen before the reload would be dropped too early.)
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
    -- (Party members' quests, PartyHelp.lua, need no order of their own:
    -- "Combined" is one optimal route over everyone's stops, and "Just
    -- <name>'s" leaves only theirs on the route.)
    -- Shared party route: its stops come first, in the shared order (their
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
    -- Finish this zone before leaving it (see N.AreaSplit).
    local here, away
    local p = self:PlayerPos()
    local zone = p and N.ZoneOf(p.map)
    if zone and ns.db.nav.zoneFirst ~= false then here, away = N.AreaSplit(goals, zone, p, N.ZoneOf) end
    for _, g in ipairs(goals) do
        local awayZone
        if away and away[g.key] then
            local pt = g.points and g.points[1]
            awayZone = zoneName(N.ZoneOf(pt and pt.map))
        end
        g.awayZone = awayZone
    end
    N.zoneNote = (here and away) and ("Finishing " .. zoneName(zone) .. " first") or nil
    return { first = first, tour = tour, here = here, away = away }
end

-- A plan as if you had picked this stop (for previews on the map / advice list).
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

-- Every stop by (weighted) distance from you. Only needed for a stop you
-- pinned, or when there's no plan: not on every arrow tick (it was ~90
-- stops x up to 80 spots, 10 times a second).
local function rank(p)
    local ranked = {}
    for _, goal in ipairs(goals) do
        local pt, d = nearestPoint(goal, p)
        if pt then ranked[#ranked + 1] = { goal = goal, point = pt, d = d, score = d * (goal.weight or 1) } end
    end
    table.sort(ranked, function(a, b) return a.score < b.score end)
    return ranked
end

-- Is any stop on your continent at all? (Else there's nothing to plan.)
-- Known again when the stops are gathered, you change continent, or after 5 s.
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

local function choose(p)
    -- "Do it where you stand" stops (e.g. crafting with no station) follow you.
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
    -- No plan (no planner, or it failed): the nearest stop.
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

-- Your own waypoint (Waypoint.lua: Ctrl/Alt-click the map, /way, "Point the
-- arrow here"). It isn't a route stop: while it's set the arrow points at it,
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
--   * always for a stop inside a cave or building while you're outside
--     (straight at it leads on top of the cave): the trail in, or the entrance
--   * outdoors only with "Arrow follows paths you've walked" on, and only a
--     trail at most 1.5x the straight line (it used to take one up to 4x
--     longer, so the arrow wandered off along an old detour)
-- Otherwise the arrow points straight at the stop.
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

local function steer(p, choice)
    local pt = choice.point
    local direct = choice.d
    -- A stop inside a cave while you're outside: never straight at it (that
    -- leads on top of the cave). Follow a trail in, or head for the entrance.
    local inside = not (IsIndoors and IsIndoors()) and N:Inside(p.cont, pt.wx, pt.wy)
    if not inside and ns.db.nav.arrowPaths ~= true then route = nil return pt.wx, pt.wy, "direct", direct end
    if direct < 80 and not inside then route = nil return pt.wx, pt.wy, "direct", direct end

    local now = GetTime()
    local stale = not route or route.goalKey ~= choice.goal.key or route.cont ~= p.cont
    if route and not stale then
        local g = graph(p.cont)
        local w = route.nodes[route.idx]
        -- Off the path? Re-plan (at most every 3s).
        if w and dist(p.wx, p.wy, g.x[w], g.y[w]) > 60 and now - lastRouteAt > 3 then stale = true end
    end
    if stale and now - lastRouteAt > 1 then
        lastRouteAt = now
        route = nil
        local s = nearestNode(p.cont, p.wx, p.wy, 40)
        local t, td = nearestNode(p.cont, pt.wx, pt.wy, 80)
        if s and t and s ~= t then
            local nodes, length = astar(p.cont, s, t)
            if nodes and N.TrailWorthIt(length + (td or 0), direct, inside) then
                route = { goalKey = choice.goal.key, cont = p.cont, nodes = nodes, idx = 1,
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
    return g.x[n], g.y[n], "path", route.length
end

-------------------------------------------------------------------------------
-- Arrow UI
-------------------------------------------------------------------------------

local frame, panel

-- The arrow's panel (left-click the arrow). Built so your eyes land on the
-- task first:
--   [hero]  a band in the route colour: stop icon, TYPE in small caps,
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

-- Drag a panel (arrow panel, stop card) by its title band. Once moved it
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
        f.byHover = false   -- you moved it: keep it open
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

-- The coloured band at the top of the arrow panel and the stop card.
local function fillHero(p, g, distText)
    local h = p.hero
    local c = ns.theme.route
    h.bg:SetColorTexture(c[1] * 0.35, c[2] * 0.35, c[3] * 0.35, 0.95)
    h.bar:SetColorTexture(c[1], c[2], c[3], 1)
    local kind = ns.theme.kinds[N:StopKind(g)]
    h.icon:SetTexture(kind and kind.icon or "Interface\\Icons\\INV_Misc_Map_01")
    h.label:SetText(((kind and kind.label) or "Next stop"):upper())
    h.label:SetTextColor(c[1] + (1 - c[1]) * 0.5, c[2] + (1 - c[2]) * 0.5, c[3] + (1 - c[3]) * 0.5)
    local task = g.text or g.title or "Next stop"
    if g.title and task:sub(1, #g.title + 2) == g.title .. ": " then task = task:sub(#g.title + 3) end
    h.task:SetText(task)
    h.dist:SetText(distText or "")
    h:SetHeight(math.max(64, h.task:GetStringHeight() + h.label:GetStringHeight() + 26))
    return task
end

-- The arrow's panel is a drawer: it slides out of the arrow (below it, a lip
-- joins it to the arrow's text), and a pull tab at the bottom with a ^ folds
-- it back. It opens on whichever side of the arrow has room (N.DrawerSide):
-- below, above near the bottom of the screen, to the right or left at a
-- screen edge. Shift-drag it to give it a place of its own (the arrow's
-- right-click menu puts it back). Click the arrow to pin it open: it follows
-- your current stop, and stays open after a /reload until you fold it.
-- (The stop card, shared by the Flow Tracker and Router, is a separate window.)

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

-- Put the drawer where it opens: your spot (Shift-dragged), else beside the arrow.
local function placeDrawer(drawer, arrow)
    drawer:ClearAllPoints()
    local saved = ns.db.nav.drawerPoint
    if saved then
        drawer:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
        drawer.lip:Hide()
        drawer:SetSlideOrigin("TOP")
        return "yours"
    end
    local k = (arrow:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
    local side = N.DrawerSide((arrow:GetLeft() or 0) * k, (arrow:GetBottom() or 0) * k, arrow:GetWidth() * k, arrow:GetHeight() * k,
        UIParent:GetWidth(), UIParent:GetHeight(), drawer:GetWidth(), drawer:GetHeight())
    local p = DRAWER_POINTS[side]
    drawer:SetPoint(p[1], arrow, p[2], p[3], p[4])
    drawer.lip:SetShown(side == "below")
    drawer:SetSlideOrigin(side == "above" and "BOTTOM" or "TOP")
    return side
end
N._placeDrawer = placeDrawer   -- (tests)

-- Flow's pin button: a small red square where Flow's other views have their
-- close button (top right), with a pushpin drawn on it: upright and gold when
-- pinned, tilted and grey when not. isOn() says which; a click calls
-- set(not isOn()). onLeave: called when the mouse leaves it.
N.PIN_GLYPH = {   -- a pushpin pointing down: cap, body, needle (x1, y1, x2, y2, thickness)
    { -4, 4, 4, 4, 3 }, { 0, 4, 0, -1, 4 }, { 0, -1, 0, -7, 1.5 },
}
function N.PinPoints(on)
    -- Not pinned: tilted, a pin lying loose. Pinned: straight in.
    local a = on and 0 or math.rad(45)
    local c, s = math.cos(a), math.sin(a)
    local out = {}
    for i, l in ipairs(N.PIN_GLYPH) do
        out[i] = { l[1] * c - l[2] * s, l[1] * s + l[2] * c, l[3] * c - l[4] * s, l[3] * s + l[4] * c, l[5] }
    end
    return out
end
function N.MakePin(parent, isOn, set, onLeave)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(20, 20)
    b:SetPoint("TOPRIGHT", -3, -3)
    -- The close button's colours: a dark rim round a red face, lighter on hover.
    b.rim = b:CreateTexture(nil, "BACKGROUND"); b.rim:SetAllPoints()
    b.rim:SetColorTexture(0.16, 0.05, 0.03, 1)
    b.face = b:CreateTexture(nil, "BORDER")
    b.face:SetPoint("TOPLEFT", 2, -2); b.face:SetPoint("BOTTOMRIGHT", -2, 2)
    b.face:SetColorTexture(0.55, 0.10, 0.06, 1)
    b.glow = b:CreateTexture(nil, "HIGHLIGHT"); b.glow:SetAllPoints(b.face)
    b.glow:SetColorTexture(1, 0.45, 0.3, 0.3)
    b.lines = {}
    for i = 1, #N.PIN_GLYPH do b.lines[i] = b:CreateLine(nil, "ARTWORK") end
    function b:Refresh()
        local on = isOn() and true or false
        if self.on == on then return end
        self.on = on
        local r, g, bl = 1, 0.82, 0.2       -- pinned: gold
        if not on then r, g, bl = 0.75, 0.75, 0.75 end
        for i, p in ipairs(N.PinPoints(on)) do
            local l = self.lines[i]
            l:SetThickness(p[5])
            l:SetStartPoint("CENTER", self, p[1], p[2])
            l:SetEndPoint("CENTER", self, p[3], p[4])
            l:SetColorTexture(r, g, bl, 1)
        end
    end
    local function tip(self)
        ns.Tip(self, "ANCHOR_TOP")
        if isOn() then
            GameTooltip:AddLine("Pinned open", 1, 0.82, 0.2)
            GameTooltip:AddLine("Stays open as the arrow moves on to the next stop, and after a /reload. Click to unpin.", 1, 1, 1, true)
        else
            GameTooltip:AddLine("Pin it open", 1, 1, 1)
            GameTooltip:AddLine("Click: it stays open as the arrow moves on to the next stop.", 0.8, 0.8, 0.8, true)
        end
        GameTooltip:Show()
    end
    b:SetScript("OnClick", function(self)
        set(not isOn())
        self:Refresh()
        if self:IsMouseOver() then tip(self) end
    end)
    b:SetScript("OnEnter", tip)
    b:SetScript("OnLeave", function() GameTooltip:Hide(); if onLeave then onLeave() end end)
    b:Refresh()
    return b
end

local function makeDrawer(f)
    local BG = { 0.04, 0.04, 0.07, 0.92 }
    -- The pin: shows whether the drawer is pinned open, a click switches it.
    -- Unpinned, it folds once the mouse leaves it (like a hover-opened one).
    f.pin = N.MakePin(f, function() return ns.db.nav.drawerOpen == true end, function(on)
        ns.db.nav.drawerOpen = on or nil
        f.byHover = not on
    end, function() if N.FoldIfAway then N.FoldIfAway() end end)
    if f.hero and f.hero.dist then   -- (the pin takes the top-right corner)
        f.hero.dist:ClearAllPoints()
        f.hero.dist:SetPoint("BOTTOMRIGHT", -10, 8)
    end
    f.lip = f:CreateTexture(nil, "BACKGROUND")
    f.lip:SetSize(90, 5)
    f.lip:SetPoint("BOTTOM", f, "TOP", 0, 0)
    f.lip:SetColorTexture(BG[1], BG[2], BG[3], BG[4])
    local tab = CreateFrame("Button", nil, f)
    tab:SetSize(64, 14)
    tab:SetPoint("TOP", f, "BOTTOM", 0, 0)
    tab.bg = tab:CreateTexture(nil, "BACKGROUND"); tab.bg:SetAllPoints()
    tab.bg:SetColorTexture(BG[1], BG[2], BG[3], BG[4])
    tab.arms = { tab:CreateLine(nil, "ARTWORK"), tab:CreateLine(nil, "ARTWORK") }
    for k, l in ipairs(tab.arms) do
        l:SetThickness(2)
        l:SetStartPoint("CENTER", tab, (k == 1 and -1 or 1) * 6, -2)
        l:SetEndPoint("CENTER", tab, 0, 3)
        l:SetColorTexture(1, 1, 1, 0.75)
    end
    tab:SetScript("OnEnter", function(self)
        for _, l in ipairs(self.arms) do l:SetColorTexture(1, 1, 1, 1) end
        ns.Tip(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Fold the drawer back up", 1, 1, 1)
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function(self)
        for _, l in ipairs(self.arms) do l:SetColorTexture(1, 1, 1, 0.75) end
        GameTooltip:Hide()
    end)
    tab:SetScript("OnClick", function() f:Fold(true) end)
    f.tab = tab
    -- Slide: grow out from the arrow's side when it opens, shrink back when it folds.
    local function slide(from, to, done)
        local g = f:CreateAnimationGroup()
        local a = g:CreateAnimation("Scale")
        if a.SetScaleFrom then a:SetScaleFrom(1, from); a:SetScaleTo(1, to)
        else a:SetFromScale(1, from); a:SetToScale(1, to) end
        a:SetOrigin("TOP", 0, 0)
        a:SetDuration(0.14)
        a:SetSmoothing(from < to and "OUT" or "IN")
        if done then g:SetScript("OnFinished", done) end
        g.scale = a
        return g
    end
    f.openAnim = slide(0.05, 1)
    f.foldAnim = slide(1, 0.05, function() f:Hide() end)
    function f:SetSlideOrigin(point)
        self.openAnim.scale:SetOrigin(point, 0, 0)
        self.foldAnim.scale:SetOrigin(point, 0, 0)
    end
    f:HookScript("OnShow", function(self) self.foldAnim:Stop(); self.openAnim:Play() end)
    -- byYou: you folded it (the tab, a click on it or the arrow), so it's no
    -- longer pinned open; a hover-opened drawer folding by itself leaves that alone.
    function f:Fold(byYou)
        if byYou then ns.db.nav.drawerOpen = nil end
        self.pin:Refresh()
        if not self:IsShown() or self.foldAnim:IsPlaying() then return end
        self.openAnim:Stop(); self.foldAnim:Play()
    end
    -- A hover-opened drawer folds once the mouse is off it and the arrow.
    f:HookScript("OnLeave", function() if N.FoldIfAway then N.FoldIfAway() end end)
    -- Shift-drag: your own place for it (saved). A plain click folds it.
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() then self:StartMoving(); self.dragging = true end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local a, _, r, x, y = self:GetPoint()
        ns.db.nav.drawerPoint = { a, r, x, y }
        self.lip:Hide()
        ns:Print("the drawer stays here now (right-click the arrow: \"Drawer next to the arrow\" puts it back).")
    end)
    f:SetScript("OnMouseUp", function(self)
        if self.dragging then self.dragging = nil return end
        if IsShiftKeyDown() then return end
        self:Fold(true)
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
    local task = fillHero(panel, g, string.format("%d yd", current.d or 0))
    panel.pin:Refresh()

    local lines = {}
    if g.title and g.title ~= task then lines[#lines + 1] = "|cffffd200" .. g.title .. "|r" end
    if g.blockedBy then lines[#lines + 1] = "|cffff7070Blocked: " .. g.blockedBy .. "|r" end
    for _, l in ipairs(g.details or {}) do
        if not l:find("^Quest: ") and not l:find("^Objective: ") then lines[#lines + 1] = "|cffcccccc" .. l .. "|r" end
    end
    lines[#lines + 1] = "|cff888888" .. (N.how == "path" and "Following a trail you've walked before."
        or "Straight line: no known trail yet.") .. "|r"
    -- The whole trip, in the order Flow plans to do it.
    if N.plan and #N.plan > 1 then
        lines[#lines + 1] = " "
        lines[#lines + 1] = string.format("|cffffd200Then|r |cff888888(%d stops, about %d yd)|r",
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
    -- side of the arrow with room, or where you Shift-dragged it.
    if not panel:IsShown() then panel.side = placeDrawer(panel, frame) end
    panel:Show()
end

-------------------------------------------------------------------------------
-- Stop card: Flow's small view of one stop, opened by clicking it anywhere.
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

local function uiLink(parent, label, fn)
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
    b:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 1); N:ClickCursor(true) end)
    b:SetScript("OnLeave", function(self) self.text:SetTextColor(0.35, 0.7, 1); N:ClickCursor(false) end)
    b:SetScript("OnClick", function() fn(); N:ClickCursor(false) end)
    return b
end


local function buildCard()
    local f = buildPanel("FlowStopCard")
    f:SetFrameStrata("FULLSCREEN_DIALOG")          -- above the world map
    f:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "FlowStopCard")         -- Esc closes it
    f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.close:SetPoint("TOPRIGHT", 2, 2)
    f.close:SetScale(0.8)
    N.Draggable(f, "cardPoint", "beside what you click")
    f.hero.dist:ClearAllPoints()
    f.hero.dist:SetPoint("BOTTOMRIGHT", -10, 8)
    f.links = {
        quest = uiLink(f, "Select in quest log", function()
            N:OpenInGame(f.goal)
            ns:Print("selected in your quest log: press L (or M) to read it.")
        end),
        map = uiLink(f, "Show on map", function()
            local g = f.goal
            if ns.mapOverlay then ns.mapOverlay:Focus(g.key, 20) end
            if not WorldMapFrame:IsShown() then ns:Print("press M: Flow highlights it on your map.") end
        end),
        first = uiLink(f, "Go here next", function() N:Select(f.goal.key); f:Hide() end),
    }
    return f
end

function N:ShowStop(goal, anchor)
    GameTooltip:Hide()   -- the card says it all: the hover tooltip would just cover it
    card = card or buildCard()
    if card:IsShown() and card.goal and card.goal.key == goal.key then card:Hide() return end  -- click again: close
    card.goal = goal
    local p, pt = N:PlayerPos(), nil
    for _, s in ipairs(N.plan or {}) do if s.goal.key == goal.key then pt = s.point break end end
    pt = pt or (goal.points and goal.points[1])
    local d = (p and pt and pt.wx and pt.cont == p.cont) and dist(p.wx, p.wy, pt.wx, pt.wy)
    local task = fillHero(card, goal, d and string.format("%d yd", d) or "")

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
    f.arrow = N:MakeArrow(f)
    N.arrowFrame = f
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.text:SetPoint("TOP", f, "BOTTOM", 0, -2)
    f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.sub:SetPoint("TOP", f.text, "BOTTOM", 0, -2)
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local a, _, r, x, y = self:GetPoint()
        ns.db.nav.point = { a, r, x, y }
    end)
    f:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            -- Menu: this stop, then route and order choices, unhide all.
            local items = {}
            if current and current.follow then
                -- Following a party member (Follow.lua).
                items[#items + 1] = { title = true, text = current.goal.text or "Following" }
                items[#items + 1] = { text = "Stop following (back to the route)", func = function() ns.follow:Stop() end }
                items[#items + 1] = { sep = true }
            elseif current and current.waypoint then
                -- Following your own waypoint (not a route stop).
                items[#items + 1] = { title = true, text = current.goal.text or "Your waypoint" }
                items[#items + 1] = { text = "Clear it (back to the route)", func = function()
                    if ns.waypoint then ns.waypoint:Clear() end
                    ns:Print("waypoint cleared: back to your route")
                end }
                items[#items + 1] = { sep = true }
            elseif current then
                local g = current.goal
                items[#items + 1] = { title = true, text = g.text or g.title or "This stop" }
                items[#items + 1] = { text = "Open it", func = function() N:OpenStop(g) end }
                items[#items + 1] = { text = "Hide this stop", func = function() N:Hide(g.key) end }
                items[#items + 1] = { sep = true }
            end
            for _, it in ipairs(ns.menu:RouteItems()) do items[#items + 1] = it end
            items[#items + 1] = { sep = true }
            items[#items + 1] = { text = "3D arrow", checked = ns.db.nav.arrowStyle ~= "flat",
                func = function() N:SetArrowStyle(ns.db.nav.arrowStyle == "flat" and "3d" or "flat") end }
            -- (Only once you've Shift-dragged the drawer somewhere of its own.)
            if ns.db.nav.drawerPoint then
                items[#items + 1] = { text = "Drawer next to the arrow (again)", func = function()
                    ns.db.nav.drawerPoint = nil
                    if panel and panel:IsShown() then panel.side = placeDrawer(panel, frame) end
                end }
            end
            ns.menu:Open(items)
        elseif panel and panel:IsShown() and not panel.byHover then
            panel:Fold(true)
        else
            -- A click pins it open (a hover-opened panel becomes pinned), and
            -- it stays open across a /reload until you fold it.
            showPanel()
            ns.db.nav.drawerOpen = true
            if panel then panel.byHover = false; panel.pin:Refresh() end
        end
    end)
    -- The text under the arrow (stop name, distance) clicks like the arrow:
    -- left = this panel, right = the menu.
    f.textHit = CreateFrame("Button", nil, f)
    f.textHit:SetPoint("TOP", f, "BOTTOM", 0, 0)
    f.textHit:SetSize(240, 34)
    f.textHit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f.textHit:SetScript("OnClick", function(_, button) f:GetScript("OnClick")(f, button) end)
    -- Hover the arrow (or ring, or its text): the stop's details, e.g. quest progress.
    local function tip(owner)
        if not current or (panel and panel:IsShown()) then return end   -- the drawer already shows it
        ns.Tip(owner, "ANCHOR_BOTTOM")
        N:FillTooltip(GameTooltip, current.goal, not N.arrived and "Click: details and the trip. Right-click: options." or nil)
        -- In an area: every other quest stop you're in the area for, with progress.
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
    -- In the area (ring showing): hovering opens the full panel, and leaving
    -- closes it again unless you clicked it open. Elsewhere: a tooltip, and a
    -- click opens the panel.
    local function enter(owner)
        if N.arrived and current and not (panel and panel:IsShown()) then
            showPanel()
            panel.byHover = true
        elseif not (N.arrived and panel and panel:IsShown()) then
            tip(owner)
        end
    end
    -- Leaving the arrow folds a hover-opened drawer, unless you moved onto
    -- the drawer (to pin it): then it folds when you leave the drawer. A
    -- moment's grace for crossing the gap between them.
    function N.FoldIfAway(now)
        if not (panel and panel.byHover) then return end
        if not now then C_Timer.After(0.3, function() N.FoldIfAway(true) end) return end
        if panel:IsMouseOver() or f:IsMouseOver() or (f.textHit and f.textHit:IsMouseOver()) then return end
        panel:Fold(); panel.byHover = false
    end
    local function leave()
        GameTooltip:Hide()
        N.FoldIfAway()
    end
    f:SetScript("OnEnter", function() enter(f) end)
    f:SetScript("OnLeave", leave)
    f.textHit:SetScript("OnEnter", function() enter(f) end)
    f.textHit:SetScript("OnLeave", leave)
    f:Hide()
    return f
end

-- In a quest's area: within AREA yards of any of its spawn points (objective
-- stops only; a vendor or trainer is one spot).
local AREA = 45
function N:InArea(goal, p)
    if not (goal and goal.area and p) then return false end
    for _, pt in ipairs(goal.points or {}) do
        if pt.wx and pt.cont == p.cont and dist(p.wx, p.wy, pt.wx, pt.wy) < AREA then return true end
    end
    return false
end

-- The nearest spot in a stop's area where its thing spawns (a Bundle of
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

-- A nameplate on screen for one of the stop's mobs / NPCs (goal.npcs): the
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
        pcall(ns.minimapPin.Update, ns.minimapPin, p, { cont = cont, wx = wx, wy = wy }, { text = "Your corpse" })
    end
    frame:Show()
    return true
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
    if cfg.learn then record(p) end

    -- Dead: the arrow turns red and points back to your corpse.
    if UnitIsDeadOrGhost("player") and N:ShowCorpse(p) then return end

    local choice = choose(p)          -- (keeps the route planned, waypoint or not)
    -- A party member you follow (Follow.lua), else your own waypoint, else the route.
    choice = (ns.follow and ns.follow.Choice(p)) or N.WaypointChoice(p) or choice
    current = choice
    N.current = choice  -- for Flow Actions (Modules/Rotation/Actions.lua)
    if ns.minimapPin then pcall(ns.minimapPin.Update, ns.minimapPin, p, choice and choice.point, choice and choice.goal) end
    local tk = choice and choice.goal.key
    local planKey = N.plan and #N.plan > 0 and (N.plan[1].goal.key .. ":" .. #N.plan) or ""
    if tk ~= N.lastTargetKey or planKey ~= N.lastPlanKey then
        N.lastTargetKey, N.lastPlanKey = tk, planKey
        -- Mark the NPC of the new stop above its nameplate, and (smaller) the
        -- NPCs of the next stops.
        if ns.questMarks and ns.questMarks.SetRouteTarget then
            pcall(ns.questMarks.SetRouteTarget, choice and choice.goal.npcs, N.NextStopNames(N.plan, tk, 5))
        end
    end
    if not choice then
        if #goals == 0 and not ns.quests:Source() then
            frame.text:SetText("No directions yet")
            frame.sub:SetText("Install Questie + QuestieDB for quest locations")
            frame.arrow:Hide()
            frame:Show()
        else
            frame:Hide()
        end
        return
    end

    local wx, wy, how, length = steer(p, choice)
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
    -- Reaching a shared stop clears it for the whole party.
    local partyId = g.key:match("^party:(.+)$")
    if partyId and choice.d < 15 and ns.party then
        ns.party:Done(partyId)
        ns:Print("reached a shared stop: " .. (g.title or "?"))
    end
    frame.text:SetText(g.text or g.title or "Next goal")
    -- A stop with its own icon (craft here: the profession; use from your
    -- bags: a bag) shows it bouncing in the ring when you're there.
    if frame.arrow.SetCenterIcon then frame.arrow:SetCenterIcon(g.icon) end
    -- Arrived: at the stop, or anywhere in a quest's area (near any spawn of
    -- its mobs / objects, not just the one point the route picked). Then the
    -- arrow is a pulsing ring - unless one of the quest's mobs or NPCs has a
    -- nameplate on screen: then the arrow points straight at it.
    local here = choice.d < ARRIVED * 2 or N:InArea(g, p)
    N.arrived = here
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
            frame.sub:SetText(choice.d < ARRIVED * 2 and "You're here" or "You're in the area")
        end
    else
        frame.sub:SetText(string.format("%d yd%s%s", choice.d,
            (not facing and b) and (" " .. compass(b)) or "",
            how == "path" and string.format(" (trail, %d yd walk)", length)
                or (how == "entrance" and " (it's inside: entrance first)" or "")))
        frame.arrow:SetArrived(false)
    end
    -- Right on the spot (on a spawn spot, or at the stop itself): the pillars
    -- run a wave.
    if frame.arrow.SetWave then
        frame.arrow:SetWave(here and frame.arrow.arrived and ((spotD and spotD <= SPOT_ON) or choice.d < ARRIVED * 2))
    end
    local c = choice.waypoint and ns.theme.waypoint or ns.theme.route   -- your waypoint: green
    frame.arrow:SetVertexColor(c[1], c[2], c[3])
    frame:Show()
    if panel and panel:IsShown() then showPanel()
    elseif ns.db.nav.drawerOpen and not N.drawerRestored then
        -- Pinned open before the /reload: open again, once, now there's a stop.
        N.drawerRestored = true
        showPanel()
        if panel then panel.byHover = false end
    end
end

-------------------------------------------------------------------------------
-- Wiring
-------------------------------------------------------------------------------

-- busy: something changed (quest, level, item...) and the route is being
-- redone; the Flow Tracker spins its icon meanwhile. The quiet refresh every
-- 10 s doesn't count, or it would spin all the time.
-- The refresh gathers one stop source per frame (~15 frames, a quarter
-- second), then plans in the frame after: all in one frame, a busy refresh
-- could take 30+ ms, a hitch you can see. A change that comes in while it
-- gathers gets one more refresh straight after.
local pendingCollect, gathering, again, busy = false, false, false, false
function N.Busy() return busy end
local collectSoon
local function finishRefresh()
    pendingCollect, gathering, busy = false, false, false
    if again then again = false; collectSoon(false) end
end
local function collectSpread()
    gathering = true
    local sources = {}
    for key, provider in ns:Each("navGoal") do sources[#sources + 1] = { key = key, provider = provider } end
    local list, i = {}, 0
    local function step()
        i = i + 1
        local s = sources[i]
        if s then
            -- gatherFrom pcalls the source; this catches the rest, so a bad
            -- stop can't leave the refresh stuck (no route updates ever again).
            local ok, err = pcall(gatherFrom, s.key, s.provider, list)
            if not ok and ns.db.rotation.debug then ns:Print("nav goal " .. s.key .. ": " .. tostring(err)) end
            C_Timer.After(0, step)
            return
        end
        pcall(N.Collect, N, list)
        finishRefresh()
    end
    step()
end
collectSoon = function(quiet)
    if not quiet then busy = true end
    if pendingCollect then
        -- Waiting the 1 s: this change is picked up anyway. Gathering: the
        -- sources already read may be out of date, so go again after.
        if gathering and not quiet then again = true end
        return
    end
    pendingCollect = true
    C_Timer.After(1, collectSpread)
end
local function scheduleCollect() collectSoon(false) end
N.RequestCollect = scheduleCollect  -- other modules: re-plan soon (throttled)

-- Money changed: re-plan only when it crosses a skipped stop's cost (so it
-- comes back) or drops below a planned stop's cost (so it's skipped).
ns:On("PLAYER_MONEY", function()
    local money = GetMoney()
    for _, d in pairs(ns.db.nav.deferred or {}) do
        if d.cost and d.cost <= money then scheduleCollect() return end
    end
    for _, g in ipairs(goals or {}) do
        if g.cost and g.cost > money then scheduleCollect() return end
    end
end)

-- Per character: the stops you hid, money-blocked stops, your Custom route
-- pick. (Trails, cave entrances and settings stay shared: they're the same
-- for everyone.) Stops hidden before the split stay hidden for everyone.
ns:PerCharacter("nav.hidden", { adopt = function(old) return old end })
ns:PerCharacter("nav.deferred")
ns:PerCharacter("nav.selectedKey")
-- How many stops the map and the Flow Tracker show: each character's own, so
-- a new character always starts with "Next stop only" (nothing saved = 1),
-- simple, whatever your other characters chose.
ns:PerCharacter("nav.stopsShown")

ns:OnLoad(function(saved)
    saved.nav = saved.nav or {}
    saved.nav.graphs = saved.nav.graphs or {}
    if saved.nav.enabled == nil then saved.nav.enabled = true end
    if saved.nav.learn == nil then saved.nav.learn = true end
    -- Restore your Custom route's pick from before the reload ("selected" is
    -- the older name of "custom").
    N.loadedAt = GetTime()
    if saved.nav.sorter == "selected" then saved.nav.sorter = "custom" end
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

for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED",
                      "QUEST_TURNED_IN", "ZONE_CHANGED_NEW_AREA", "PLAYER_LEVEL_UP",
                      "SKILL_LINES_CHANGED", "TRAINER_CLOSED", "LEARNED_SPELL_IN_TAB", "LEARNED_SPELL_IN_SKILL_LINE" }) do
    ns:On(ev, scheduleCollect)
end

ns.commands.nav = function(arg)
    arg = (arg or ""):lower()
    local cfg = ns.db.nav
    if arg == "on" or arg == "off" then
        cfg.enabled = (arg == "on")
        ns:Print("navigation arrow " .. arg)
    elseif arg:find("^professions") then
        local v = arg:match("^professions%s+(%a+)")
        cfg.professions = (v ~= "off")
        N:Collect()
        ns:Print("professions on the route: " .. (cfg.professions and "on" or "off"))
    elseif arg:find("^sort") then
        -- Any registered route objective (XpValue.lua): /flow nav sort <key>.
        local key = arg:match("^sort%s+(%S+)")
        if key then
            ns.xpValue:SetMode(key)
            ns:Print("route optimises for: " .. (select(2, ns.xpValue:Objective()).label or key))
        else
            ns:Print("route objectives (now: " .. (ns.xpValue:Objective()) .. "):")
            for _, o in ipairs(ns.xpValue:List()) do print("  " .. o.key .. " - " .. o.label) end
            print("  /flow nav sort <key>")
        end
    elseif arg:find("^stops") then
        -- How many upcoming stops the map and the Flow Tracker show.
        local v = arg:match("^stops%s+(%S+)")
        local n = v and tonumber(v)
        if v == "all" or (n and n >= 1) then
            N:SetStopsShown(n)
            ns:Print("stops on the map and in the Flow Tracker: " .. N:StopsShownLabel())
        else
            ns:Print("stops shown: " .. N:StopsShownLabel() .. ". /flow nav stops 1|3|5|10|all (any number works)")
        end
    elseif arg == "xp" or arg == "xp on" or arg == "xp off" or arg == "distance" then
        ns.xpValue:Set(arg ~= "xp off" and arg ~= "distance")
        ns:Print("route sorting: " .. (ns.xpValue:On() and "most XP first" or "shortest path"))
    elseif arg == "unhide" or arg == "hidden" then
        -- Bring back every stop you hid (right-click), or list them.
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
    elseif arg == "arrow 3d" or arg == "arrow flat" then
        N:SetArrowStyle(arg:match("arrow (%a+%d?)") == "flat" and "flat" or "3d")
        ns:Print("arrow: " .. (ns.db.nav.arrowStyle == "flat" and "flat lines" or "3D"))
    elseif arg == "why" then
        -- What the route is made of, and what Flow wanted but couldn't place.
        ns:Print(string.format("route: mode %s, professions %s, Questie %s",
            N:Mode(), cfg.professions ~= false and "on" or "off",
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
        -- nearest stops): how far their nearest known spot is, and how many
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
        print("  /flow nav on|off|learn|forget. Shift-drag the arrow to move it.")
    end
end

-- Timed for /flow perf.
N.Collect = ns.perf.Wrap("route: gather stops", N.Collect)
