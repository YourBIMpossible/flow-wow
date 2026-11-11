-- Your current route stop on the minimap: a dot in the route colour (with
-- the stop type's icon on hover). At the edge of the minimap when it's
-- further away than the minimap shows.

local _, ns = ...
local P = {}
ns.minimapPin = P

-- Minimap diameter in yards per zoom level (as used by the common map libraries).
local OUTDOOR = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 }
local INDOOR  = { [0] = 300, 240, 180, 120, 80, 50 }

local pin, profPin
local function makePin(name)
    local pin = CreateFrame("Button", name, Minimap)
    pin:SetSize(14, 14)
    pin:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
    pin.edge = pin:CreateTexture(nil, "BACKGROUND")
    pin.edge:SetPoint("TOPLEFT", -2, 2); pin.edge:SetPoint("BOTTOMRIGHT", 2, -2)
    pin.edge:SetTexture(CIRCLE)
    pin.edge:SetVertexColor(0, 0, 0, 0.9)
    -- Flow's target marker (o): ring in the route colour, a dark gap, the dot.
    pin.ring = pin:CreateTexture(nil, "BORDER")
    pin.ring:SetAllPoints()
    pin.ring:SetTexture(CIRCLE)
    pin.hole = pin:CreateTexture(nil, "ARTWORK", nil, 1)
    pin.hole:SetPoint("TOPLEFT", 2, -2); pin.hole:SetPoint("BOTTOMRIGHT", -2, 2)
    pin.hole:SetTexture(CIRCLE)
    pin.hole:SetVertexColor(0.05, 0.05, 0.08, 1)
    pin.dot = pin:CreateTexture(nil, "ARTWORK", nil, 2)
    pin.dot:SetPoint("TOPLEFT", 4, -4); pin.dot:SetPoint("BOTTOMRIGHT", -4, 4)
    pin.dot:SetTexture(CIRCLE)
    pin:SetScript("OnEnter", function(self)
        if not self.goal then return end
        ns.Tip(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Flow: " .. (self.goal.text or self.goal.title or "next stop"), 1, 1, 1, true)
        if self.yards then GameTooltip:AddLine(string.format("%d yd", self.yards), 0.8, 0.8, 0.8) end
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pin:Hide()
    return pin
end
local function build() pin = makePin("FlowMinimapPin") end

local function indoors()
    return IsIndoors and IsIndoors() or false
end

-- How the minimap shows the world right now: pixels per yard, and the turn
-- (cos, sin) of a rotating minimap. Asked once per drawing, not per spot
-- (each spot used to ask the zoom, size, indoors, rotation and facing).
local function view()
    local zoom = Minimap:GetZoom() or 0
    local yards = (indoors() and INDOOR or OUTDOOR)[zoom] or 466
    local radius = Minimap:GetWidth() / 2
    local scale = radius / (yards / 2)            -- pixels per yard
    local c, s = 1, 0
    -- Rotating minimap: turn the offset with the player's facing.
    if GetCVar and GetCVar("rotateMinimap") == "1" then
        local f = ns.api.Safe(GetPlayerFacing and GetPlayerFacing())
        if f then c, s = math.cos(f), -math.sin(f) end   -- turn by -facing: what you face is up
    end
    return scale, c, s
end

-- World point -> minimap pixels from the centre (rotation included), and
-- pixels per yard, for a view().
local function toMiniWith(p, wx, wy, scale, c, s)
    local east, south = ns.nav:Offset(p, wx, wy)
    if not east then return nil end
    local x, y = east * scale, -south * scale
    if c ~= 1 or s ~= 0 then x, y = x * c - y * s, x * s + y * c end
    return x, y, scale, east, south
end
local function toMini(p, wx, wy)
    local scale, c, s = view()
    return toMiniWith(p, wx, wy, scale, c, s)
end

-------------------------------------------------------------------------------
-- Areas on the minimap: the same areas as the world map, as soft clouds
-- for the stop the arrow points at, and, while you hover a row in
-- the Flow Tracker, for that stop in the hover colour. So you can tell at a
-- glance whether you're standing in this stop's area, the next one's, or both.
-------------------------------------------------------------------------------

-- Drawn as one cloud like the game's own quest areas, not a pile of circles:
-- the outline of all the spawn circles together, filled row by row with thin
-- strips that never overlap (overlapping see-through circles pile up colour,
-- which is what made each circle show). A smaller core on top gives the
-- soft edge. Clipped to the round minimap.
local AREA_YARDS = 45
local ROW = 2                -- pixels per strip
local CORE = 0.62            -- core radius, as a share of the area's
local discs, nDiscs = {}, 0  -- (the strips)
local hoverGoal
local areaHost

local function strip(x1, x2, y, color, alpha)
    nDiscs = nDiscs + 1
    local t = discs[nDiscs]
    if not t then
        t = areaHost:CreateTexture(nil, "BACKGROUND")
        discs[nDiscs] = t
    end
    t:SetColorTexture(color[1], color[2], color[3], alpha)
    t:ClearAllPoints()
    t:SetSize(math.max(1, x2 - x1), ROW)
    t:SetPoint("CENTER", Minimap, "CENTER", (x1 + x2) / 2, y)
    t:Show()
end

-- Where row `y` crosses the union of circles (centres in flat xs / ys, n of
-- them, radius r), clipped to the round minimap of `radius`. Writes the
-- merged spans into `out` as a flat list (a1, b1, a2, b2...) and returns
-- how many. Reuses its scratch lists: it runs for every row, several times
-- a second, and building little tables each time churned 1.3 MB a second.
local lo_, hi_ = {}, {}
function P.SpansInto(xs, ys, n, r, y, radius, out)
    local m2 = radius * radius - y * y
    if m2 <= 0 then return 0 end
    local m = math.sqrt(m2)
    local k = 0
    for i = 1, n do
        local dy = y - ys[i]
        if dy > -r and dy < r then
            local dx = math.sqrt(r * r - dy * dy)
            local a = xs[i] - dx
            -- insertion sort by start (few circles cross any one row)
            local j = k
            while j > 0 and lo_[j] > a do lo_[j + 1], hi_[j + 1] = lo_[j], hi_[j]; j = j - 1 end
            lo_[j + 1], hi_[j + 1] = a, xs[i] + dx
            k = k + 1
        end
    end
    local c = 0
    local i = 1
    while i <= k do
        local a, b = lo_[i], hi_[i]
        i = i + 1
        while i <= k and lo_[i] <= b do
            if hi_[i] > b then b = hi_[i] end
            i = i + 1
        end
        if a < -m then a = -m end
        if b > m then b = m end
        if b > a then out[c * 2 + 1], out[c * 2 + 2] = a, b; c = c + 1 end
    end
    return c
end

-- The same as a list of { x1, x2 } (tests, and anything that wants tables).
function P.Spans(pts, r, y, radius)
    local xs, ys = {}, {}
    for i, q in ipairs(pts) do xs[i], ys[i] = q[1], q[2] end
    local flat = {}
    local c = P.SpansInto(xs, ys, #pts, r, y, radius, flat)
    local out = {}
    for i = 1, c do out[i] = { flat[i * 2 - 1], flat[i * 2] } end
    return out
end

local xs_, ys_, spans_ = {}, {}, {}
-- yards: cloud radius around each spot (default the stop areas' 45 yd;
-- profession nodes use a smaller one, Crafting/Nearby.lua).
local function drawAreaMini(p, goal, color, strong, yards)
    if not (goal and goal.area and goal.points) then return end
    local radius = Minimap:GetWidth() / 2
    local n, r = 0, nil
    local vs, vc, vsin = view()
    for _, pt in ipairs(goal.points) do
        if pt.wx and pt.cont == p.cont then
            local x, y, scale = toMiniWith(p, pt.wx, pt.wy, vs, vc, vsin)
            if x then
                r = r or math.max(3, (yards or AREA_YARDS) * scale)
                if x * x + y * y < (radius + r) * (radius + r) then n = n + 1; xs_[n], ys_[n] = x, y end
            end
        end
    end
    if n == 0 then return end
    local edgeA, coreA = strong and 0.17 or 0.1, strong and 0.17 or 0.1
    -- One smooth outline per group of spawns (like the world map's areas),
    -- not a circle per spawn: the outline wrapped around all the spawn
    -- circles of the group, filled row by row; a smaller copy of it on top
    -- for the soft edge.
    local M = ns.mapOverlay
    if M and M._hull and M._clusters then
        local pts = {}
        for i = 1, n do pts[i] = { xs_[i], ys_[i] } end
        for _, group in ipairs(M._clusters(pts, r * 3)) do
            local ring = {}
            for _, q in ipairs(group) do
                for k = 0, 11 do
                    local a = k * math.pi / 6
                    ring[#ring + 1] = { q[1] + r * math.cos(a), q[2] + r * math.sin(a) }
                end
            end
            local outline = M._hull(ring)
            P.FillShape(outline, radius, color, edgeA)
            P.FillShape(P.Shrink(outline, CORE), radius, color, coreA)
        end
        return
    end
    -- (Fallback without the map module: the outline of the circles.)
    local lo, hi = math.huge, -math.huge
    for i = 1, n do
        if ys_[i] - r < lo then lo = ys_[i] - r end
        if ys_[i] + r > hi then hi = ys_[i] + r end
    end
    lo, hi = math.max(lo, -radius), math.min(hi, radius)
    local y = lo + ROW / 2
    while y < hi and nDiscs < 900 do
        local c = P.SpansInto(xs_, ys_, n, r, y, radius, spans_)
        for i = 1, c do strip(spans_[i * 2 - 1], spans_[i * 2], y, color, edgeA) end
        c = P.SpansInto(xs_, ys_, n, r * CORE, y, radius, spans_)
        for i = 1, c do strip(spans_[i * 2 - 1], spans_[i * 2], y, color, coreA) end
        y = y + ROW
    end
end

-- A convex outline (list of {x, y}) shrunk towards its middle by `f`.
function P.Shrink(poly, f)
    local cx, cy = 0, 0
    for _, v in ipairs(poly) do cx, cy = cx + v[1], cy + v[2] end
    cx, cy = cx / #poly, cy / #poly
    local out = {}
    for i, v in ipairs(poly) do out[i] = { cx + (v[1] - cx) * f, cy + (v[2] - cy) * f } end
    return out
end

-- Where row y crosses a convex outline: x from, x to (nil if it doesn't).
function P.ShapeRow(poly, y)
    local lo, hi
    local m = #poly
    for i = 1, m do
        local a, b = poly[i], poly[i % m + 1]
        local y1, y2 = a[2], b[2]
        if (y >= y1 and y <= y2) or (y >= y2 and y <= y1) then
            local x = (y1 == y2) and a[1] or (a[1] + (y - y1) * (b[1] - a[1]) / (y2 - y1))
            if not lo or x < lo then lo = x end
            if not hi or x > hi then hi = x end
            if y1 == y2 then
                if b[1] < lo then lo = b[1] end
                if b[1] > hi then hi = b[1] end
            end
        end
    end
    return lo, hi
end

-- Fill a convex outline with strips, clipped to the round minimap.
function P.FillShape(poly, radius, color, alpha)
    if not poly or #poly < 3 then return end
    local lo, hi = math.huge, -math.huge
    for _, v in ipairs(poly) do
        if v[2] < lo then lo = v[2] end
        if v[2] > hi then hi = v[2] end
    end
    lo, hi = math.max(lo, -radius), math.min(hi, radius)
    local y = lo + ROW / 2
    while y < hi and nDiscs < 900 do
        local a, b = P.ShapeRow(poly, y)
        local m2 = radius * radius - y * y
        if a and m2 > 0 then
            local m = math.sqrt(m2)
            a, b = math.max(a, -m), math.min(b, m)
            if b > a then strip(a, b, y, color, alpha) end
        end
        y = y + ROW
    end
end

-- Redraw only when something you'd see changed: you moved a pixel's worth
-- (at least 2 yards; zoomed out a pixel is ~3 yards, so less often there),
-- turned (rotating minimap), zoomed, or the stop / hovered stop changed.
local lastAreas, lastSig = 0, nil
local function signature(p, goal)
    local rot = GetCVar and GetCVar("rotateMinimap") == "1"
    local f = rot and ns.api.Safe(GetPlayerFacing and GetPlayerFacing()) or 0
    local scale = view()
    local step = (scale and scale > 0) and math.max(2, 1 / scale) or 2   -- yards per pixel
    return string.format("%d:%d:%d:%d:%s:%s:%s:%d", math.floor(p.wx / step), math.floor(p.wy / step),
        math.floor((f or 0) * 20), Minimap:GetZoom() or 0, tostring(goal and goal.key),
        tostring(hoverGoal and hoverGoal.key), tostring(ns.db.nav.minimapAreas), Minimap:GetWidth())
        .. ":" .. tostring(ns.db.nav.nearbyNodes) .. ":" .. tostring(ns.nearby and ns.nearby.version)
        .. ":" .. tostring(P.hereColor ~= nil)
end
function P:UpdateAreas(p, goal, force)
    if not Minimap then return end
    if not force and GetTime() - lastAreas < 0.2 then return end
    lastAreas = GetTime()
    if p then
        local sig = signature(p, goal)
        if not force and sig == lastSig then return end
        lastSig = sig
    end
    if not areaHost then
        areaHost = CreateFrame("Frame", nil, Minimap)
        areaHost:SetAllPoints(Minimap)
        areaHost:SetFrameLevel(Minimap:GetFrameLevel() + 2)   -- under the pin
    end
    local oldD = nDiscs
    nDiscs = 0
    if ns.db.nav.minimapPin ~= false and ns.db.nav.minimapAreas ~= false and p and not (ns.Lite and ns.Lite()) then
        if hoverGoal and hoverGoal ~= goal then drawAreaMini(p, hoverGoal, ns.theme.hover, true) end
        -- In the area, the area takes the arrow's colour (it stands in for the dot).
        drawAreaMini(p, goal, P.hereColor or ns.theme.route, hoverGoal == nil or hoverGoal == goal)
    end
    -- Ore and herbs you can gather, where they spawn near you (Crafting/Nearby.lua).
    if ns.nearby and p and not (ns.Lite and ns.Lite()) then
        local zoom = Minimap:GetZoom() or 0
        local yards = ((IsIndoors and IsIndoors()) and INDOOR or OUTDOOR)[zoom] or 466
        for _, g in ipairs(ns.nearby.MinimapGroups(p, yards / 2 + 20)) do
            drawAreaMini(p, g, g.color, true, ns.nearby.MINIMAP_YARDS)
        end
    end
    for i = nDiscs + 1, oldD do discs[i]:Hide() end
end
P.UpdateAreas = ns.perf.Wrap("minimap areas", P.UpdateAreas)   -- (/flow perf)

-- The Flow Tracker calls this while you hover one of its rows (nil = none).
function P:SetHover(goal)
    hoverGoal = goal
    P.lastP = P.lastP or (ns.nav and ns.nav:PlayerPos())
    P:UpdateAreas(P.lastP, P.lastGoal, true)
end

-- p: player position (Nav:PlayerPos), pt: the stop's point (nil: no dot),
-- goal: the stop, col: the arrow's colour { r, g, b } (the dot matches it),
-- here: you've arrived.
function P:Update(p, pt, goal, col, here)
    if not Minimap then return end
    if not pin then build() end
    P.lastP, P.lastGoal = p, goal
    P.hereColor = (here and col) or nil
    pcall(P.UpdateAreas, P, p, goal)
    if ns.db.nav.minimapPin == false or not (p and pt and pt.wx and pt.cont == p.cont) then pin:Hide() return end
    local x, y, _, east, south = toMini(p, pt.wx, pt.wy)
    if not x then pin:Hide() return end
    local radius = Minimap:GetWidth() / 2
    local d = math.sqrt(x * x + y * y)
    local edge = d > radius - 6
    if edge then x, y = x / d * (radius - 6), y / d * (radius - 6) end
    -- No arrow colour given: your waypoint, or a party member you follow, green.
    col = col or ((goal and (goal.key == "user:wp" or goal.key == "user:follow")) and ns.theme.waypoint or ns.theme.route)
    pin.dot:SetVertexColor(col[1], col[2], col[3], 1)
    pin.ring:SetVertexColor(col[1], col[2], col[3], 1)
    pin:SetSize(edge and 12 or 16, edge and 12 or 16)
    pin:SetAlpha(edge and 0.8 or 1)
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", Minimap, "CENTER", x, y)
    pin.goal, pin.yards = goal, math.floor(math.sqrt(east * east + south * south))
    pin:Show()
end

function P.Pin() return pin end   -- (tests)

-- The profession stop the faint arrow points at: its own dot in the
-- profession arrow's colour (smoked glass with a small light centre, no
-- outline). pt nil: no dot.
P.PROF_RING = { 0.86, 0.87, 0.9 }   -- (the centre's colour)
function P:UpdateProf(p, pt, goal)
    if not Minimap then return end
    if not profPin then
        profPin = makePin("FlowMinimapProfPin")
        profPin:SetFrameLevel(Minimap:GetFrameLevel() + 7)   -- under the route dot
    end
    if ns.db.nav.minimapPin == false or not (p and pt and pt.wx and pt.cont == p.cont) then profPin:Hide() return end
    local x, y, _, east, south = toMini(p, pt.wx, pt.wy)
    if not x then profPin:Hide() return end
    local radius = Minimap:GetWidth() / 2
    local d = math.sqrt(x * x + y * y)
    local edge = d > radius - 6
    if edge then x, y = x / d * (radius - 6), y / d * (radius - 6) end
    local c, r = ns.theme.profPointer, P.PROF_RING
    profPin.ring:Hide()   -- no light outline: this dot is meant to be discreet
    profPin.hole:SetVertexColor(c[1], c[2], c[3], 1)
    profPin.dot:SetVertexColor(r[1], r[2], r[3], 0.7)
    profPin:SetSize(edge and 10 or 13, edge and 10 or 13)
    profPin:SetAlpha(edge and 0.75 or 0.95)
    profPin:ClearAllPoints()
    profPin:SetPoint("CENTER", Minimap, "CENTER", x, y)
    profPin.goal, profPin.yards = goal, math.floor(math.sqrt(east * east + south * south))
    profPin:Show()
end
function P.ProfPin() return profPin end   -- (tests)

function P:Hide()
    if pin then pin:Hide() end
    if profPin then profPin:Hide() end
    P.hereColor = nil
    lastSig = nil   -- draw again next time
    for i = 1, nDiscs do discs[i]:Hide() end
    nDiscs = 0
end
