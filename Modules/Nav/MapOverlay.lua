-- World map overlay: your route as numbered checkpoints and lines.
--   checkpoint label: "3 [9]" = 3rd stop, quest level 9; "!2 [8]" = 2nd quest pickup
--   colours (Theme.lua): the route and arrow colour shows the order mode
--     (purple = Most XP first, blue = Shortest path); hovering a ^ shows only
--     the route you'd follow, in legendary orange. Your own waypoint is a
--     green line and (o) of its own. /flow settings has a colour-blind palette.
--   The stop you're heading to (route stop 1) has a white ring, the rest black.
--   Click a stop: open it. The ^ in the Flow Router: go there first.

local _, ns = ...
local M = {}
ns.mapOverlay = M

local host           -- frame on the map canvas holding lines
local lines, pins = {}, {}
local nLines, nPins = 0, 0
local previewKey, hoverKey
local focusKey, focusUntil = nil, 0   -- a stop opened from the tracker / arrow menu

local function theme() return ns.theme end

-- "Point the arrow here": your own waypoint at this stop (the arrow goes there
-- first; the planned route stays as it is and carries on after).
function M.PointHere(goal)
    if not (goal and ns.waypoint) then return end
    local pt
    for _, s in ipairs(ns.nav.plan or {}) do if s.goal.key == goal.key then pt = s.point break end end
    pt = pt or (goal.points and goal.points[1])
    if pt and pt.map and pt.x then ns.waypoint:Set(pt.map, pt.x, pt.y, goal.text or goal.title) end
end

local function canvas()
    if not WorldMapFrame then return nil end
    if WorldMapFrame.GetCanvas then return WorldMapFrame:GetCanvas() end
    return WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
end

local function canvasScale()
    local sc = WorldMapFrame.ScrollContainer
    return (sc and sc.GetCanvasScale and sc:GetCanvasScale()) or 1
end

-- Position (0-1) of a route point on the map being shown.
local function toMap(pt, mapID)
    if not pt then return nil end
    if pt.map == mapID and pt.x then return pt.x, pt.y end
    if pt.wx and pt.cont and C_Map.GetMapPosFromWorldPos and CreateVector2D then
        local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, pt.cont, CreateVector2D(pt.wx, pt.wy), mapID)
        if ok and pos then
            local x, y = pos:GetXY()
            if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then return x, y end
        end
    end
end

-- Route lines and pins live one frame strata above the map, so the map's own
-- objects (lake, town art, other pins) can't cover them; frame levels alone
-- weren't enough. The map's scroll area still clips them to the map.
local STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG" }
local function aboveMap()
    local s = WorldMapFrame:GetFrameStrata()
    for i, name in ipairs(STRATA) do
        if name == s then return STRATA[math.min(i + 1, #STRATA)] end
    end
    return "DIALOG"
end

-- The stop you're heading to (set by pin, recoloured by keepUp) and the
-- arrow's colour (arrowColor, below); declared here for pin().
local targetPin, arrowColor

local function line(c, x1, y1, x2, y2, color, alpha)
    nLines = nLines + 1
    local l = lines[nLines]
    if not l then
        l = host:CreateLine(nil, "OVERLAY")
        lines[nLines] = l
    end
    local w, h = c:GetWidth(), c:GetHeight()
    l:SetThickness(2.5 / canvasScale())  -- thin, solid, fully opaque: the exact route colour
    l:SetColorTexture(color[1], color[2], color[3], alpha or 0.9)
    l:SetStartPoint("TOPLEFT", c, x1 * w, -y1 * h)
    l:SetEndPoint("TOPLEFT", c, x2 * w, -y2 * h)
    l:Show()
end

-- target: the stop you're heading to (route stop 1), drawn as Flow's target
-- marker (o) with a white ring; the other stops have black rings.
-- top: the stop under your mouse (bigger, in the hover colour, on top).
local function pin(c, x, y, label, color, stop, top, target)
    nPins = nPins + 1
    local p = pins[nPins]
    if not p then
        p = CreateFrame("Button", nil, c)
        -- A small round point: dark ring + coloured dot (the portrait mask
        -- is a white circle, tinted).
        p:SetSize(11, 11)
        local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
        p.edge = p:CreateTexture(nil, "BACKGROUND")
        p.edge:SetPoint("TOPLEFT", -2, 2)
        p.edge:SetPoint("BOTTOMRIGHT", 2, -2)
        p.edge:SetTexture(CIRCLE)
        p.edge:SetVertexColor(0, 0, 0, 0.9)
        p.hole = p:CreateTexture(nil, "BORDER", nil, 1)
        p.hole:SetTexture(CIRCLE)
        p.hole:SetVertexColor(0.05, 0.05, 0.08, 1)
        p.bg = p:CreateTexture(nil, "BORDER", nil, 2)
        p.bg:SetAllPoints()
        p.bg:SetTexture(CIRCLE)
        p.text = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        p.text:SetPoint("LEFT", p, "RIGHT", 3, 0)
        -- Like a row in the Flow Router list: hover = the stop's details (and
        -- it's highlighted), click = open it, right-click = menu. Previewing
        -- and changing the route is only the ^ handle in the list.
        p:SetScript("OnEnter", function(self)
            hoverKey = self.stop.goal.key
            ns.Tip(self, "ANCHOR_RIGHT")
            ns.nav:ClickCursor(true)
            ns.nav:FillTooltip(GameTooltip, self.stop.goal, "Click: open it. Right-click: menu. (^ in the Flow Router: go here next, a Custom route.)")
            GameTooltip:Show()
            -- Highlight in place (redrawing would move the point under the mouse).
            self:SetSize(18, 18); self.edge:SetVertexColor(1, 1, 1, 1)
            self:SetFrameLevel(self:GetFrameLevel() + 100)
        end)
        p:SetScript("OnLeave", function(self)
            ns.nav:ClickCursor(false)
            hoverKey = nil
            GameTooltip:Hide()
            if self.isTarget then
                self:SetSize(16, 16); self.edge:SetVertexColor(1, 1, 1, 1)   -- white ring: where you're heading
            else
                self:SetSize(11, 11); self.edge:SetVertexColor(0, 0, 0, 0.9)
            end
            self:SetFrameLevel(math.max(1, self:GetFrameLevel() - 100))
        end)
        p:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        p:SetScript("OnClick", function(self, button)
            local g = self.stop.goal
            if button == "RightButton" then
                local items = {
                    { title = true, text = g.text or g.title or "This stop" },
                    { text = "Open it", func = function() ns.nav:OpenStop(g, self) end },
                    { text = "Go here next (Custom route)", func = function() ns.nav:Select(g.key) end },
                    { text = "Point the arrow here (your waypoint)", func = function() M.PointHere(g) end },
                    { text = "Hide this stop", func = function() ns.nav:Hide(g.key) end },
                    { sep = true },
                }
                for _, it in ipairs(ns.menu:RouteItems()) do items[#items + 1] = it end
                ns.menu:Open(items)
                return
            end
            ns.nav:OpenStop(g, self)
        end)
        pins[nPins] = p
    end
    p.stop = stop
    p.isTarget, p.color = (target and not top) and true or false, color
    p:SetParent(c)
    -- The hovered stop: bigger, white ring, above every other pin and line.
    -- Relative to the map canvas: fixed numbers could end up under the map's own
    -- art (lakes, towns) when the canvas itself sits at a high level.
    local base = math.min(c:GetFrameLevel() + 1000, 9000)
    p:SetFrameStrata(aboveMap())
    p:SetFrameLevel(top and base + 200 or base + 100)
    local size = top and 18 or (target and 16 or 11)
    p:SetSize(size, size)
    p.text:SetFontObject((top or target) and "GameFontNormal" or "GameFontHighlightSmall")
    p:SetScale(1 / canvasScale())
    p:ClearAllPoints()
    local s = p:GetScale()
    p:SetPoint("CENTER", c, "TOPLEFT", x * c:GetWidth() / s, -y * c:GetHeight() / s)
    p.bg:ClearAllPoints()
    p.edge:ClearAllPoints(); p.edge:SetPoint("TOPLEFT", -2, 2); p.edge:SetPoint("BOTTOMRIGHT", 2, -2)
    if target and not top then
        -- (o), the stop you're heading to: a WHITE ring, a dark gap, the dot
        -- in the arrow's colour. Every other stop has a black ring.
        p.edge:SetVertexColor(1, 1, 1, 1)
        p.hole:ClearAllPoints(); p.hole:SetPoint("TOPLEFT", 1, -1); p.hole:SetPoint("BOTTOMRIGHT", -1, 1)
        p.hole:Show()
        p.bg:SetPoint("TOPLEFT", 4, -4); p.bg:SetPoint("BOTTOMRIGHT", -4, 4)
    else
        p.edge:SetVertexColor(top and 1 or 0, top and 1 or 0, top and 1 or 0, top and 1 or 0.9)
        p.hole:Hide()
        p.bg:SetAllPoints()
    end
    if target and not top then
        -- Its dot wears the arrow's colour (kept up on the map tick).
        targetPin = p
        color = arrowColor(false) or color
    end
    p.bg:SetVertexColor(color[1], color[2], color[3], 1)
    p.liveCol = color
    p.text:SetText(label)
    p.full, p.short = label, (label:gsub(" %[%d+%]", ""))   -- "3 [9]" and "3" (for the declutter)
    p.top = top and true or false
    p:Show()
    return p
end
M._pin = pin   -- (tests)

-- Draws one route as a faint dotted trail through round points, like a
-- treasure map: it shows the way without covering the map. Stops on another
-- map are skipped, and the trail joins the ones on this map. Each point's
-- label carries the stop's type icon and number ("[icon] 3 [9]"). The trail
-- from you to the stop you're heading to wears the arrow's colour (and the
-- stop's dot too), a little stronger; the rest of the route is fainter.
-- Legs are kept from the last draw; the dots are drawn again only when you
-- move or the arrow's colour changes (no animation, nothing every frame).
local legs, dots, nDots = {}, {}, 0
local DOT_GAP = 12     -- screen pixels between dots
local DOT_SIZE = 4     -- screen pixels across
local DOT_CLEAR = 9    -- no dots this close to either end (under the stops' points)
local FIRST_ALPHA, REST_ALPHA = 0.8, 0.45
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- The arrow's colour right now (Nav sets it each time it turns the arrow),
-- for the trail to where it points: the route's first stop (waypoint false)
-- or your waypoint (true). nil: the arrow points somewhere else.
function arrowColor(waypoint)
    local N = ns.nav
    if not (N and N.arrowColor) then return nil end
    if (N.arrowWaypoint and true or false) ~= waypoint then return nil end
    return N.arrowColor
end

-- Where along a leg len long the dots go: evenly, about gap apart, none
-- within clear of either end.
local function dotSpots(len, gap, clear)
    local out = {}
    local span = len - 2 * clear
    if span < gap * 0.5 then return out end
    local n = math.max(1, math.floor(span / gap + 0.5))
    local step = span / n
    for i = 0, n do out[#out + 1] = clear + i * step end
    return out
end
M._dotSpots = dotSpots   -- (tests)

-- Lines that start at you (to the first stop, to your waypoint). Between
-- route changes only these move, so the 0.5 s map tick moves just them
-- (followPlayer) instead of drawing everything again. l: a line, or nil (a
-- dotted trail: only its leg moves).
local links = { n = 0 }
local function addLink(st, l, leg)
    st.n = st.n + 1
    local k = st[st.n] or {}
    k.line, k.leg = l, leg
    st[st.n] = k
end

local function dot()
    nDots = nDots + 1
    local d = dots[nDots]
    if not d then
        d = host:CreateTexture(nil, "OVERLAY", nil, 6)
        d:SetTexture(CIRCLE)
        dots[nDots] = d
    end
    return d
end

local function drawDots()
    local c = canvas()
    if not (c and host) then return end
    local old = nDots
    nDots = 0
    local w, h, sc = c:GetWidth(), c:GetHeight(), canvasScale()
    local gap, size, clear = DOT_GAP / sc, DOT_SIZE / sc, DOT_CLEAR / sc
    for _, leg in ipairs(legs) do
        local x1, y1, x2, y2 = leg[1] * w, -leg[2] * h, leg[3] * w, -leg[4] * h
        local dx, dy = x2 - x1, y2 - y1
        local len = math.sqrt(dx * dx + dy * dy)
        local col = (leg.live ~= nil and arrowColor(leg.live)) or leg.color
        local a = leg.alpha
        if len > 0 then
            local ux, uy = dx / len, dy / len
            for _, along in ipairs(dotSpots(len, gap, clear)) do
                if nDots >= 600 then break end
                local d = dot()
                -- Only what changed is set again (size, colour, showing).
                if d.size ~= size then d:SetSize(size, size); d.size = size end
                if d.a ~= a or d.col ~= col then d:SetVertexColor(col[1], col[2], col[3], a); d.a, d.col = a, col end
                d:ClearAllPoints()
                d:SetPoint("CENTER", c, "TOPLEFT", x1 + ux * along, y1 + uy * along)
                if not d.on then d:Show(); d.on = true end
            end
        end
    end
    for i = nDots + 1, old do dots[i]:Hide(); dots[i].on = false end
end
-- Timed apart from the redraws so /flow perf shows it.
local drawDotsTimed = ns.perf.Wrap("world map (route dots)", drawDots)

-- The stop you moved to the front (the ^ handle, "Go here first"). The route
-- is planned from it, so it's stop 1 and wears the (o) like any first stop;
-- no other mark. It stays first until it's done or you click its (o).
function M.IsChosen(key)
    local sel = ns.nav and ns.nav.selection
    return key ~= nil and sel ~= nil and sel.first == key
end

-- Areas: a stop that's a whole area (mobs to kill, things to loot, a farm
-- stop) shows where its mobs live as soft discs in the route colour, under
-- the lines, instead of only the one point the route passes. Drawn for the
-- next stop and the one you're pointing at.
local blobs, nBlobs = {}, 0
local AREA_YARDS = 45                       -- same radius as the arrow's ring (Nav.lua)
local function blobRadius(c, mapID)
    local w
    if C_Map.GetMapWorldSize then
        local ok, width = pcall(C_Map.GetMapWorldSize, mapID)
        if ok then w = width end
    end
    local frac = (w and w > 0) and (AREA_YARDS / w) or 0.015
    return math.max(6, math.min(frac * c:GetWidth(), 60))
end
-- Hovering a disc: every disc of that stop lights up, and the tooltip says
-- which stop it is and what you need there (Loot Stringy Wolf Meat 9/66).
local function blobEnter(self)
    for i = 1, nBlobs do
        local b = blobs[i]
        if b.goal == self.goal then b.tex:SetVertexColor(b.color[1], b.color[2], b.color[3], 0.45) end
    end
    ns.Tip(self, "ANCHOR_CURSOR")
    GameTooltip:AddLine(string.format("|cffffffff%s|r  %s", self.label or "", self.goal.text or self.goal.title or ""), nil, nil, nil, true)
    ns.nav:FillTooltip(GameTooltip, self.goal, "Click: open it. Right-click: menu.")
    GameTooltip:Show()
end
local function blobLeave(self)
    for i = 1, nBlobs do
        local b = blobs[i]
        if b.goal == self.goal then b.tex:SetVertexColor(b.color[1], b.color[2], b.color[3], b.alpha) end
    end
    GameTooltip:Hide()
end
local function blobClick(self, button)
    local g = self.goal
    if button == "RightButton" then
        local items = {
            { title = true, text = g.text or g.title or "This stop" },
            { text = "Open it", func = function() ns.nav:OpenStop(g, self) end },
            { text = "Go here next (Custom route)", func = function() ns.nav:Select(g.key) end },
            { text = "Point the arrow here (your waypoint)", func = function() M.PointHere(g) end },
            { text = "Hide this stop", func = function() ns.nav:Hide(g.key) end },
        }
        ns.menu:Open(items)
        return
    end
    ns.nav:OpenStop(g, self)
end

-- Convex hull (monotone chain) of {x, y} points, counter-clockwise.
local function hull(p)
    table.sort(p, function(a, b) return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]) end)
    if #p < 3 then return p end
    local function cross(o, a, b) return (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1]) end
    local lower, upper = {}, {}
    for i = 1, #p do
        while #lower >= 2 and cross(lower[#lower - 1], lower[#lower], p[i]) <= 0 do lower[#lower] = nil end
        lower[#lower + 1] = p[i]
    end
    for i = #p, 1, -1 do
        while #upper >= 2 and cross(upper[#upper - 1], upper[#upper], p[i]) <= 0 do upper[#upper] = nil end
        upper[#upper + 1] = p[i]
    end
    lower[#lower] = nil; upper[#upper] = nil
    for _, q in ipairs(upper) do lower[#lower + 1] = q end
    return lower
end

-- Spawn points (pixels) -> groups of points that lie close together, each
-- its own patch of ground with its own border.
local function clusters(pts, gap)
    local group, out = {}, {}
    local function find(i) while group[i] ~= i do i = group[i] end return i end
    for i = 1, #pts do group[i] = i end
    for i = 1, #pts do
        for j = i + 1, #pts do
            local dx, dy = pts[i][1] - pts[j][1], pts[i][2] - pts[j][2]
            if dx * dx + dy * dy < gap * gap then group[find(i)] = find(j) end
        end
    end
    local byRoot = {}
    for i = 1, #pts do
        local r = find(i)
        if not byRoot[r] then byRoot[r] = {}; out[#out + 1] = byRoot[r] end
        table.insert(byRoot[r], pts[i])
    end
    return out
end
M._hull, M._clusters = hull, clusters  -- (tests)

-- The patch the route actually goes to: the group holding the point nearest
-- the route's spot for this stop (all of them when there's no route spot).
local function routePatch(groups, rx, ry)
    if not rx then return nil end
    local best, bestD
    for gi, group in ipairs(groups) do
        for _, p in ipairs(group) do
            local d = (p[1] - rx) ^ 2 + (p[2] - ry) ^ 2
            if not bestD or d < bestD then best, bestD = gi, d end
        end
    end
    return best
end
M._routePatch = routePatch  -- (tests)

-- An area's shape (its discs and the border round each patch) as flat lists
-- of 0-1 map positions: discs = x1, y1, x2, y2...; edges = x1, y1, x2, y2 per
-- border piece. Working it out is the slow part (grouping up to 80 spawns,
-- then a hull over 12 points round each), so it's kept per stop and map
-- and only worked out again when its spawns, its route spot, the map or
-- the zoom change. Shapes not drawn in a full redraw are dropped.
local shapes, shapesNext = {}, {}
M._shapeBuilds = 0   -- (tests)
local function areaShape(c, mapID, goal, routePt, allPatches)
    local r = blobRadius(c, mapID)
    local w, h = c:GetWidth(), c:GetHeight()
    local n, sum = #goal.points, 0
    for _, pt in ipairs(goal.points) do sum = sum + (pt.x or pt.wx or 0) * 7 + (pt.y or pt.wy or 0) end
    local rx, ry = toMap(routePt, mapID)
    local key = goal.key .. (allPatches and "|all|" or "|") .. tostring(mapID)
    local s = shapesNext[key] or shapes[key]
    if s and s.n == n and s.sum == sum and s.r == r and s.w == w and s.h == h
        and (allPatches or (s.rx == rx and s.ry == ry)) then
        shapesNext[key] = s
        return s
    end
    M._shapeBuilds = M._shapeBuilds + 1
    local all = {}
    for _, pt in ipairs(goal.points) do
        local x, y = toMap(pt, mapID)
        if x then all[#all + 1] = { x * w, y * h } end
    end
    local groups = clusters(all, r * 3)
    local keep = not allPatches and routePatch(groups, rx and rx * w, ry and ry * h)
    if keep then groups = { groups[keep] } end
    s = { n = n, sum = sum, r = r, w = w, h = h, rx = rx, ry = ry, discs = {}, edges = {} }
    for _, group in ipairs(groups) do
        for _, p in ipairs(group) do
            s.discs[#s.discs + 1] = p[1] / w
            s.discs[#s.discs + 1] = p[2] / h
        end
        -- A border around each patch: the outline of its discs.
        local ring = {}
        for _, p in ipairs(group) do
            for k = 0, 11 do
                local a = k * math.pi / 6
                ring[#ring + 1] = { p[1] + r * math.cos(a), p[2] + r * math.sin(a) }
            end
        end
        local edge = hull(ring)
        for i = 1, #edge do
            local a, b = edge[i], edge[i % #edge + 1]
            local e = s.edges
            e[#e + 1], e[#e + 2], e[#e + 3], e[#e + 4] = a[1] / w, a[2] / h, b[1] / w, b[2] / h
        end
    end
    shapesNext[key] = s
    return s
end
M._areaShape = areaShape   -- (tests)

-- routePt: where the route goes for this stop. Only that patch is drawn,
-- unless allPatches (the stop you point at: every place its mobs live).
local function drawArea(c, mapID, goal, color, strong, label, routePt, allPatches)
    if not (goal and goal.area and goal.points) then return end
    local s = areaShape(c, mapID, goal, routePt, allPatches)
    local r, w, h = s.r, s.w, s.h
    local alpha = strong and 0.28 or 0.1
    local discs = s.discs
    for i = 1, #discs - 1, 2 do
        local x, y = discs[i], discs[i + 1]
        if nBlobs < 300 then
            nBlobs = nBlobs + 1
            local b = blobs[nBlobs]
            if not b then
                b = CreateFrame("Button", nil, host)
                b.tex = b:CreateTexture(nil, "BACKGROUND")
                b.tex:SetAllPoints()
                b.tex:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
                b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                b:SetScript("OnEnter", blobEnter)
                b:SetScript("OnLeave", blobLeave)
                b:SetScript("OnClick", blobClick)
                blobs[nBlobs] = b
            end
            b.goal, b.label, b.color, b.alpha = goal, label, color, alpha
            b:SetFrameStrata(host:GetFrameStrata())
            b:SetFrameLevel(host:GetFrameLevel() + (strong and 3 or 1))   -- under the route's pins
            b:SetSize(r * 2, r * 2)
            b:ClearAllPoints()
            b:SetPoint("CENTER", c, "TOPLEFT", x * w, -y * h)
            b.tex:SetVertexColor(color[1], color[2], color[3], b:IsMouseOver() and 0.45 or alpha)
            b:Show()
        end
    end
    local e = s.edges
    for i = 1, #e - 3, 4 do
        line(c, e[i], e[i + 1], e[i + 2], e[i + 3], color, strong and 0.9 or 0.6)
    end
end


-- Map labels push each other apart instead of piling up: each label tries
-- eight places around its point (right first, then left, above, below and
-- the corners) and takes the first that doesn't cover another label or
-- point. No room with its level ("3 [9]"): just the number ("3"). No room at
-- all: the place where it overlaps least. The stop you point at goes first,
-- then the route in order.
local CANDS = {   -- anchor on the label, anchor on the point, x, y
    { "LEFT", "RIGHT", 3, 0 }, { "RIGHT", "LEFT", -3, 0 }, { "BOTTOM", "TOP", 0, 2 }, { "TOP", "BOTTOM", 0, -2 },
    { "BOTTOMLEFT", "TOPRIGHT", 1, 0 }, { "TOPLEFT", "BOTTOMRIGHT", 1, 0 },
    { "BOTTOMRIGHT", "TOPLEFT", -1, 0 }, { "TOPRIGHT", "BOTTOMLEFT", -1, 0 },
}
-- The label's box for candidate k, around a point at cx, cy of half size s.
function M.LabelBox(k, cx, cy, s, w, h)
    local a = CANDS[k]
    local lx, ly
    if a[2]:find("RIGHT") then lx = cx + s + a[3] elseif a[2]:find("LEFT") then lx = cx - s + a[3] else lx = cx + a[3] end
    if a[2]:find("TOP") then ly = cy + s + a[4] elseif a[2]:find("BOTTOM") then ly = cy - s + a[4] else ly = cy + a[4] end
    local l, b
    if a[1]:find("LEFT") then l = lx elseif a[1]:find("RIGHT") then l = lx - w else l = lx - w / 2 end
    if a[1]:find("BOTTOM") then b = ly elseif a[1]:find("TOP") then b = ly - h else b = ly - h / 2 end
    return l, b, l + w, b + h
end
local function overlap(l1, b1, r1, t1, l2, b2, r2, t2)
    local w = math.min(r1, r2) - math.max(l1, l2)
    local h = math.min(t1, t2) - math.max(b1, b2)
    return (w > 0 and h > 0) and w * h or 0
end
local function declutter()
    local list, boxes = {}, {}
    for i = 1, nPins do
        local p = pins[i]
        local cx, cy = p:GetCenter()
        if cx and p.full and p.full ~= "" then
            list[#list + 1] = { p = p, cx = cx, cy = cy, s = p:GetWidth() / 2 }
            boxes[#boxes + 1] = { cx - p:GetWidth() / 2, cy - p:GetHeight() / 2, cx + p:GetWidth() / 2, cy + p:GetHeight() / 2 }
        end
    end
    table.sort(list, function(a, b)
        if a.p.top ~= b.p.top then return a.p.top end
        if a.p.isTarget ~= b.p.isTarget then return a.p.isTarget end
        return (a.p.order or 0) < (b.p.order or 0)
    end)
    for _, e in ipairs(list) do
        local p = e.p
        local bestK, bestText, bestHit
        for _, text in ipairs({ p.full, p.short }) do
            p.text:SetText(text)
            local w, h = p.text:GetStringWidth() + 2, p.text:GetStringHeight() + 1
            for k = 1, #CANDS do
                local l, b, r, t = M.LabelBox(k, e.cx, e.cy, e.s, w, h)
                local hit = 0
                for _, o in ipairs(boxes) do hit = hit + overlap(l, b, r, t, o[1], o[2], o[3], o[4]) end
                if not bestHit or hit < bestHit then bestK, bestText, bestHit = k, text, hit end
                if hit == 0 then break end
            end
            if bestHit == 0 then break end
        end
        p.text:SetText(bestText)
        local a = CANDS[bestK]
        p.text:ClearAllPoints()
        p.text:SetPoint(a[1], p, a[2], a[3], a[4])
        local w, h = p.text:GetStringWidth() + 2, p.text:GetStringHeight() + 1
        local l, b, r, t = M.LabelBox(bestK, e.cx, e.cy, e.s, w, h)
        boxes[#boxes + 1] = { l, b, r, t }
    end
end
-- Draws one route as a dotted trail through round points, starting at you.
-- Stops on another map are skipped, and the trail joins the ones on this
-- map. Each point's label carries the stop's type icon and number.
local function drawRoute(c, mapID, plan, color, withPins, alpha, pinsOnly)
    if not plan then return end
    local px, py = toMap(ns.nav:PlayerPos(), mapID)
    local labels = ns.nav:PlanLabels(plan)
    local hovered
    local fromYou = px ~= nil   -- the next line drawn starts at you
    for i, s in ipairs(plan) do
        local x, y = toMap(s.point, mapID)
        local pointed = s.goal.key == hoverKey or (focusKey and s.goal.key == focusKey and GetTime() < focusUntil)
        -- Stops on the map: past your limit only the stop you point at shows (a pin, no line).
        local beyond = not ns.nav:StopVisible(i, false)
        if x and (not beyond or (pointed and withPins)) then
            if px and not pinsOnly and not beyond then
                -- From you to the first stop: the arrow's colour and stronger,
                -- so it's clear where to go now; the rest fainter. (A preview,
                -- alpha given, keeps its own colour.)
                local first = (i == 1)
                legs[#legs + 1] = { px, py, x, y, color = first and alpha == nil and theme().route or color,
                                    live = (first and alpha == nil) and false or nil,
                                    alpha = (first and FIRST_ALPHA or REST_ALPHA) * (alpha or 1) }
                if fromYou then addLink(links, nil, legs[#legs]) end
            end
            fromYou = false
            px, py = x, y
            if withPins then
                local kind = ns.theme.kinds[ns.nav:StopKind(s.goal)]
                local icon = kind and string.format("|T%s:12:12|t", kind.icon) or ""
                if pointed then
                    hovered = { x, y, icon .. labels[i], s }
                else
                    pin(c, x, y, icon .. labels[i], color, s, nil, i == 1 and not pinsOnly)
                    pins[nPins].order = i
                end
            end
        end
    end
    -- The stop you're pointing at (here or in the list) goes on top of everything.
    if hovered then
        pin(c, hovered[1], hovered[2], hovered[3], pinsOnly and color or theme().hover, hovered[4], true)
        pins[nPins].order = 0
    end
end

-- Your own waypoint on the map: a green line from you to it and a green
-- (o), apart from the route (which is drawn as usual). Right-click: clear it.
local wpPin
local function clearWaypoint()
    if ns.waypoint then ns.waypoint:Clear() end
    ns:Print("waypoint cleared: back to your route")
    GameTooltip:Hide()
    pcall(M.Redraw, M)
end
local function makeWaypointPin()
    local p = CreateFrame("Button", nil, UIParent)
    local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
    p.ring = p:CreateTexture(nil, "BACKGROUND"); p.ring:SetPoint("TOPLEFT", -2, 2); p.ring:SetPoint("BOTTOMRIGHT", 2, -2)
    p.ring:SetTexture(CIRCLE)
    p.hole = p:CreateTexture(nil, "BORDER", nil, 1); p.hole:SetPoint("TOPLEFT", 1, -1); p.hole:SetPoint("BOTTOMRIGHT", -1, 1)
    p.hole:SetTexture(CIRCLE); p.hole:SetVertexColor(0.05, 0.05, 0.08, 1)
    p.dot = p:CreateTexture(nil, "BORDER", nil, 2); p.dot:SetPoint("TOPLEFT", 4, -4); p.dot:SetPoint("BOTTOMRIGHT", -4, 4)
    p.dot:SetTexture(CIRCLE)
    p.text = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    p.text:SetPoint("LEFT", p, "RIGHT", 3, 0)
    p:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    p:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            ns.menu:Open({ { title = true, text = "Your waypoint" }, { text = "Clear it (back to the route)", func = clearWaypoint } })
        end
    end)
    p:SetScript("OnEnter", function(self)
        ns.Tip(self, "ANCHOR_RIGHT")
        local w = ns.waypoint and ns.waypoint:Get()
        GameTooltip:AddLine("Your waypoint" .. ((w and w.note) and (": " .. w.note) or ""))
        GameTooltip:AddLine("Not a stop on the route: the arrow points here in green until you get there.", 1, 1, 1, true)
        GameTooltip:AddLine("Right-click: clear it.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    p:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return p
end
local function drawWaypoint(c, mapID)
    local w = ns.waypoint and ns.waypoint:Get()
    local choice = w and ns.nav.WaypointChoice and ns.nav.WaypointChoice(ns.nav:PlayerPos())
    local x, y
    if w then x, y = toMap(choice and choice.point or { map = w.map, x = w.x, y = w.y }, mapID) end
    if not x then if wpPin then wpPin:Hide() end return end
    local col = theme().waypoint
    local px, py = toMap(ns.nav:PlayerPos(), mapID)
    if px and host then   -- (host: the map's line layer, made on the first redraw)
        legs[#legs + 1] = { px, py, x, y, color = col, live = true, alpha = FIRST_ALPHA }   -- dots, like the route
        addLink(links, nil, legs[#legs])
    end
    wpPin = wpPin or makeWaypointPin()
    wpPin:SetParent(c)
    wpPin:SetFrameStrata(aboveMap())
    wpPin:SetFrameLevel(math.min(c:GetFrameLevel() + 1000, 9000) + 150)
    wpPin:SetSize(16, 16)
    wpPin:SetScale(1 / canvasScale())
    wpPin.ring:SetVertexColor(col[1], col[2], col[3], 1)
    wpPin.dot:SetVertexColor(col[1], col[2], col[3], 1)
    wpPin.text:SetText("|cff" .. col.hex .. "Your waypoint|r")
    local s = wpPin:GetScale()
    wpPin:ClearAllPoints()
    wpPin:SetPoint("CENTER", c, "TOPLEFT", x * c:GetWidth() / s, -y * c:GetHeight() / s)
    wpPin:Show()
end
M._drawWaypoint = drawWaypoint   -- (tests)

-- The profession route (the faint arrow's stops, Nav N.profPlan): a dotted
-- path from you through its next stops and a pin on the first, in the
-- profession arrow's colour (smoked glass with a small light centre, no outline).
M.PROF_STOPS = 5
local profPin
local function makeProfPin()
    local p = CreateFrame("Button", nil, UIParent)
    local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
    p.ring = p:CreateTexture(nil, "BACKGROUND"); p.ring:SetPoint("TOPLEFT", -2, 2); p.ring:SetPoint("BOTTOMRIGHT", 2, -2)
    p.ring:SetTexture(CIRCLE)
    p.hole = p:CreateTexture(nil, "BORDER", nil, 1); p.hole:SetPoint("TOPLEFT", 1, -1); p.hole:SetPoint("BOTTOMRIGHT", -1, 1)
    p.hole:SetTexture(CIRCLE)
    p.dot = p:CreateTexture(nil, "BORDER", nil, 2); p.dot:SetPoint("TOPLEFT", 5, -5); p.dot:SetPoint("BOTTOMRIGHT", -5, 5)
    p.dot:SetTexture(CIRCLE)
    p.text = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    p.text:SetPoint("LEFT", p, "RIGHT", 3, 0)
    p:SetScript("OnEnter", function(self)
        ns.Tip(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Profession: " .. (self.label or "next stop"))
        GameTooltip:AddLine("Where the faint profession arrow points. The dotted path is your next profession stops.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    p:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return p
end
-- Profession stops worth a line on the map: not "do it where you stand".
function M.ProfStops(plan, max)
    local out = {}
    for _, s in ipairs(plan or {}) do
        if #out >= (max or M.PROF_STOPS) then break end
        if s.point and not (s.goal and s.goal.anywhere) then out[#out + 1] = s end
    end
    return out
end
local function drawProf(c, mapID)
    local stops = (ns.nav.ProfPointerOn and ns.nav:ProfPointerOn()) and M.ProfStops(ns.nav.profPlan) or {}
    local col = theme().profPointer
    local px, py = toMap(ns.nav:PlayerPos(), mapID)
    local first
    for i, s in ipairs(stops) do
        local x, y = toMap(s.point, mapID)
        if x and px and host then
            legs[#legs + 1] = { px, py, x, y, color = col, alpha = i == 1 and FIRST_ALPHA or 0.55 }
            if i == 1 then addLink(links, nil, legs[#legs]) end
        end
        if x and not first then first = { x, y, s.goal } end
        if x then px, py = x, y end
    end
    if not first then if profPin then profPin:Hide() end return end
    profPin = profPin or makeProfPin()
    profPin:SetParent(c)
    profPin:SetFrameStrata(aboveMap())
    profPin:SetFrameLevel(math.min(c:GetFrameLevel() + 1000, 9000) + 140)
    profPin:SetSize(16, 16)
    profPin:SetScale(1 / canvasScale())
    profPin.ring:Hide()   -- no light outline: this pin is meant to be discreet
    profPin.hole:SetVertexColor(col[1], col[2], col[3], 1)
    profPin.dot:SetVertexColor(0.86, 0.87, 0.9, 0.7)
    local g = first[3] or {}
    profPin.label = g.text or g.title
    profPin.text:SetText("|cffdcdde6" .. (profPin.label or "Profession") .. "|r")
    local sc = profPin:GetScale()
    profPin:ClearAllPoints()
    profPin:SetPoint("CENTER", c, "TOPLEFT", first[1] * c:GetWidth() / sc, -first[2] * c:GetHeight() / sc)
    profPin:Show()
end
M.ProfPin = function() return profPin end   -- (tests)
M.WaypointPin = function() return wpPin end

-------------------------------------------------------------------------------
-- Route panel: the trip plan as a routed quest log. It takes over the game's
-- quest log area on the right of the map when that's open, otherwise it sits
-- just outside the map on the right, so it never covers the map itself.
-- (The Flow Router is opened and closed with the square map button; the old
-- quest log / map again) and brings it back. Same numbers and colours as the
-- map pins; hover a row to preview, click to choose.
-------------------------------------------------------------------------------

local list
local MAX_ROWS = 26
local ROW_H = 18

local function collapsed() return ns.db.nav.mapListCollapsed == true end

-- The game's quest log side panel and Flow's route drawer share one slot:
-- only one is open at a time, and both can be closed (like the trackers).
-- Flow's square button sits just above the game's own side-panel button.
local function sidePanelOpen()
    local q = QuestMapFrame
    return q and q:IsShown() and q:GetWidth() > 100 or false
end

-- Flow never opens or closes the game's quest log panel itself. Doing that
-- (WorldMapFrame:HandleUserActionToggleSidePanel) from add-on code resized
-- the map from Flow's code, which tainted the map's scroll data; in a fight
-- the map's own pins were then blocked ("Button:SetPassThroughButtons()",
-- 0.35.47). So: with the quest log open, the Flow Router covers it; with it
-- closed, the Router docks beside the map (place()).
function M:SetDrawer(open)
    ns.db.nav.mapListCollapsed = not open
    M:Redraw()
end

local button
local function buildButton()
    local blizz = WorldMapFrame.SidePanelToggle
    local b = CreateFrame("Button", "FlowMapDrawerButton", WorldMapFrame)
    local w, h = 32, 32
    if blizz and blizz.GetSize then
        local bw, bh = blizz:GetSize()
        if bw and bw > 10 then w, h = bw, bh end
    end
    b:SetSize(w, h)
    if blizz then
        b:SetPoint("BOTTOM", blizz, "TOP", 0, 4)
    else
        b:SetPoint("BOTTOMRIGHT", WorldMapFrame, "BOTTOMRIGHT", -6, 46)
    end
    b:SetFrameStrata("HIGH")
    b:SetFrameLevel((blizz and blizz:GetFrameLevel() or 10) + 5)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.edge = {}
    for i, pts in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
                           { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local t = b:CreateTexture(nil, "BORDER")
        t:SetPoint(pts[1]); t:SetPoint(pts[2])
        if i <= 2 then t:SetHeight(1) else t:SetWidth(1) end
        b.edge[i] = t
    end
    -- A chevron drawn with two lines: "<" opens the drawer, ">" closes it.
    b.arms = { b:CreateLine(nil, "ARTWORK"), b:CreateLine(nil, "ARTWORK") }
    for _, l in ipairs(b.arms) do l:SetThickness(2) end
    function b:Draw()
        local open = not collapsed()
        local c = theme().route
        local hot = self:IsMouseOver()
        self.bg:SetColorTexture(open and c[1] * 0.25 or 0.05, open and c[2] * 0.25 or 0.05, open and c[3] * 0.25 or 0.08, 0.92)
        for _, t in ipairs(self.edge) do t:SetColorTexture(c[1], c[2], c[3], hot and 1 or 0.75) end
        local dir = open and 1 or -1   -- points right when open (push it away), left when closed
        local s = math.min(self:GetWidth(), self:GetHeight()) * 0.18
        for i, l in ipairs(self.arms) do
            l:SetStartPoint("CENTER", self, -dir * s * 0.6, (i == 1 and 1 or -1) * s)
            l:SetEndPoint("CENTER", self, dir * s * 0.6, 0)
            l:SetColorTexture(1, 1, 1, hot and 1 or 0.85)
        end
    end
    b:SetScript("OnClick", function() M:SetDrawer(collapsed()) end)
    b:SetScript("OnEnter", function(self)
        self:Draw()
        ns.Tip(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Flow Router")
        GameTooltip:AddLine(collapsed() and "Open Flow's route list (over the quest log if it's open, else beside the map)."
            or "Close Flow's route list.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self) self:Draw(); GameTooltip:Hide() end)
    -- The game's own quest-log button while Flow's drawer is open: the quest
    -- log is already open underneath (the drawer covers it), so the click
    -- should just close Flow's drawer and show it. A see-through Flow button
    -- sits on top of the game's button for exactly that (no Blizzard code
    -- runs). With the drawer closed it's hidden, and the game's button opens
    -- and closes the quest log as usual.
    if blizz then
        local cover = CreateFrame("Button", "FlowMapQuestLogCover", WorldMapFrame)
        cover:SetAllPoints(blizz)
        cover:SetFrameStrata(blizz:GetFrameStrata())
        cover:SetFrameLevel(blizz:GetFrameLevel() + 3)
        cover.hl = cover:CreateTexture(nil, "HIGHLIGHT")
        cover.hl:SetAllPoints(); cover.hl:SetColorTexture(1, 1, 1, 0.12)
        cover:SetScript("OnClick", function()
            ns.db.nav.mapListCollapsed = true
            M:Redraw()
        end)
        cover:SetScript("OnEnter", function(self)
            ns.Tip(self, "ANCHOR_LEFT")
            GameTooltip:AddLine("Quest log")
            GameTooltip:AddLine("Closes Flow Router and shows the quest log.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        cover:SetScript("OnLeave", function() GameTooltip:Hide() end)
        cover:Hide()
        b.cover = cover
    end
    -- Route on the map, on/off: one click, right above the drawer button. A
    -- little route (dots joined by lines) in the route colour; crossed out
    -- in red while the route is hidden.
    local r = CreateFrame("Button", "FlowMapRouteToggle", WorldMapFrame)
    r:SetSize(b:GetWidth(), b:GetHeight())
    r:SetPoint("BOTTOM", b, "TOP", 0, 4)
    r:SetFrameStrata("HIGH")
    r:SetFrameLevel(b:GetFrameLevel())
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
    r.edge = {}
    for i, pts in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
                           { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local t = r:CreateTexture(nil, "BORDER")
        t:SetPoint(pts[1]); t:SetPoint(pts[2])
        if i <= 2 then t:SetHeight(1) else t:SetWidth(1) end
        r.edge[i] = t
    end
    r.legs = { r:CreateLine(nil, "ARTWORK"), r:CreateLine(nil, "ARTWORK") }
    r.dots = {}
    local DOTS = { { -0.28, -0.22 }, { 0, 0.18 }, { 0.28, -0.12 } }
    for i = 1, 3 do
        local d = r:CreateTexture(nil, "OVERLAY")
        d:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        d:SetSize(5, 5)
        r.dots[i] = d
    end
    r.slash = r:CreateLine(nil, "OVERLAY", nil, 2)
    r.slash:SetThickness(2)
    function r:Draw()
        local on = ns.db.nav.mapLines ~= false
        local c, hot = theme().route, self:IsMouseOver()
        local w, h = self:GetWidth(), self:GetHeight()
        self.bg:SetColorTexture(0.05, 0.05, 0.08, 0.92)
        for _, t in ipairs(self.edge) do t:SetColorTexture(c[1], c[2], c[3], hot and 1 or 0.75) end
        for i, d in ipairs(self.dots) do
            d:ClearAllPoints()
            d:SetPoint("CENTER", self, "CENTER", DOTS[i][1] * w, DOTS[i][2] * h)
            d:SetVertexColor(c[1], c[2], c[3], on and 1 or 0.4)
        end
        for i, l in ipairs(self.legs) do
            l:SetThickness(1.5)
            l:SetStartPoint("CENTER", self, DOTS[i][1] * w, DOTS[i][2] * h)
            l:SetEndPoint("CENTER", self, DOTS[i + 1][1] * w, DOTS[i + 1][2] * h)
            l:SetColorTexture(1, 1, 1, on and 0.85 or 0.3)
        end
        self.slash:SetShown(not on)
        self.slash:SetStartPoint("CENTER", self, -w * 0.32, -h * 0.32)
        self.slash:SetEndPoint("CENTER", self, w * 0.32, h * 0.32)
        self.slash:SetColorTexture(1, 0.3, 0.3, 1)
    end
    r:SetScript("OnClick", function(self)
        ns.db.nav.mapLines = ns.db.nav.mapLines == false
        self:Draw()
        M:Redraw()
        if GameTooltip:IsOwned(self) then self:GetScript("OnEnter")(self) end
    end)
    r:SetScript("OnEnter", function(self)
        self:Draw()
        ns.Tip(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Flow route on the map: " .. (ns.db.nav.mapLines ~= false and "shown" or "hidden"))
        GameTooltip:AddLine("Click to " .. (ns.db.nav.mapLines ~= false and "hide" or "show") .. " it.", 1, 1, 1)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function(self) self:Draw(); GameTooltip:Hide() end)
    r:Draw()
    b.routeToggle = r
    return b
end

local function place()
    list:ClearAllPoints()
    local q = QuestMapFrame
    if q and q:IsShown() and q:GetWidth() > 100 then
        -- Cover the quest log slot exactly (the quest log is "closed" while
        -- the drawer is open).
        list:SetPoint("TOPLEFT", q, "TOPLEFT", 0, 0)
        list:SetPoint("BOTTOMRIGHT", q, "BOTTOMRIGHT", 0, 0)
    else
        -- No side panel on this client: dock outside, to the right of the map.
        list:SetPoint("TOPLEFT", WorldMapFrame, "TOPRIGHT", 2, 0)
        list:SetSize(300, math.max(200, WorldMapFrame:GetHeight()))
    end
end

-- The row handle: a ^ chevron ("go here first"), or Flow's (o) target marker
-- on the active stop. Also drawn in the help legend, so they look the same.
function M.MakeHandle(parent, size)
    local go = CreateFrame("Button", nil, parent)
    go:SetSize(size, size)
    go.bg = go:CreateTexture(nil, "BACKGROUND")
    go.bg:SetAllPoints()
    go.arms = { go:CreateLine(nil, "ARTWORK"), go:CreateLine(nil, "ARTWORK") }
    for k, l in ipairs(go.arms) do
        l:SetThickness(2)
        l:SetStartPoint("CENTER", go, (k == 1 and -1 or 1) * 4, -2)
        l:SetEndPoint("CENTER", go, 0, 3)
    end
    local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
    local function disc(sub, d)
        local t = go:CreateTexture(nil, "ARTWORK", nil, sub)
        t:SetPoint("CENTER"); t:SetSize(d, d); t:SetTexture(CIRCLE); t:Hide()
        return t
    end
    go.ring, go.hole, go.dot = disc(1, 12), disc(2, 9), disc(3, 6)
    function go:Paint(hot)
        local c = theme().route
        local on = self.active and true or false
        self.bg:SetColorTexture(c[1], c[2], c[3], on and 0 or (hot and 0.55 or 0.18))
        for _, l in ipairs(self.arms) do
            l:SetColorTexture(1, 1, 1, hot and 1 or 0.8)
            l:SetShown(not on)
        end
        self.ring:SetShown(on); self.hole:SetShown(on); self.dot:SetShown(on)
        local rc = self.ringColor or c   -- (o): the route colour (your waypoint's: green)
        self.ring:SetVertexColor(rc[1], rc[2], rc[3], 1)
        self.dot:SetVertexColor(rc[1], rc[2], rc[3], 1)
        self.hole:SetVertexColor(0.05, 0.05, 0.08, 1)
    end
    go:Paint(false)
    return go
end

-- Your waypoint's line in the Flow Router: a green (o), "Your waypoint:
-- <note>", how far, and an X to clear it. Hidden while none is set.
-- :Update() shows or hides it and returns whether it's shown.
function M.MakeWaypointRow(f)
    local w = CreateFrame("Button", nil, f)
    w:SetHeight(ROW_H - 2)
    w:SetPoint("TOPLEFT", 8, -102); w:SetPoint("TOPRIGHT", -8, -102)
    w.bg = w:CreateTexture(nil, "BACKGROUND"); w.bg:SetAllPoints()
    w.mark = M.MakeHandle(w, ROW_H - 2)
    w.mark:SetPoint("LEFT")
    w.mark.active = true
    w.mark:EnableMouse(false)
    local function clear()
        if ns.waypoint then ns.waypoint:Clear() end
        ns:Print("waypoint cleared: back to your route")
        GameTooltip:Hide()
        M:Redraw()
    end
    w.clear = CreateFrame("Button", nil, w)
    w.clear:SetSize(14, 14); w.clear:SetPoint("RIGHT", -2, 0)
    w.clear:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    w.clear:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight")
    w.clear:SetScript("OnClick", clear)
    w.clear:SetScript("OnEnter", function(self)
        ns.Tip(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Clear your waypoint")
        GameTooltip:AddLine("The arrow goes back to your route.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    w.clear:SetScript("OnLeave", function() GameTooltip:Hide() end)
    w.leg = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    w.leg:SetPoint("RIGHT", w.clear, "LEFT", -6, 0)
    w.text = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    w.text:SetPoint("LEFT", w.mark, "RIGHT", 5, 0)
    w.text:SetPoint("RIGHT", w.leg, "LEFT", -6, 0)
    w.text:SetJustifyH("LEFT"); w.text:SetWordWrap(false)
    w:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    w:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            ns.menu:Open({ { title = true, text = "Your waypoint" }, { text = "Clear it", func = clear } })
        end
    end)
    w:SetScript("OnEnter", function(self)
        ns.Tip(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Your waypoint")
        GameTooltip:AddLine("Not a stop on the route: the arrow points here in green, along the green line on the map, until you get there. Then it's back to the route below.", 1, 1, 1, true)
        GameTooltip:AddLine("X or right-click: clear it.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    w:SetScript("OnLeave", function() GameTooltip:Hide() end)
    function w:Update()
        local wp = ns.waypoint and ns.waypoint:Get()
        if not wp then self:Hide() return false end
        local col = theme().waypoint
        self.mark.ringColor = col
        self.mark:Paint(false)
        self.bg:SetColorTexture(col[1], col[2], col[3], 0.14)
        self.text:SetText("|cff" .. col.hex .. "Your waypoint|r" .. (wp.note and ("  " .. wp.note) or ""))
        local c = ns.nav.WaypointChoice and ns.nav.WaypointChoice(ns.nav:PlayerPos())
        self.leg:SetText(c and string.format("%d yd", c.d) or "other zone")
        self:Show()
        return true
    end
    w:Hide()
    return w
end

-- "?" help: a small legend drawn with the same handle and (o) marker as the rows.
local function buildHelp(f)
    local q = CreateFrame("Button", nil, f)
    q:SetSize(18, 18)
    q:SetPoint("RIGHT", f.header, "RIGHT", -6, 0)
    q:SetFrameLevel(f.header:GetFrameLevel() + 2)   -- above the header bar
    q.ring = q:CreateTexture(nil, "BACKGROUND")
    q.ring:SetAllPoints(); q.ring:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    q.text = q:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    q.text:SetPoint("CENTER"); q.text:SetText("?")

    local pop = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
    pop:SetSize(250, 82)
    pop:SetPoint("TOPRIGHT", q, "BOTTOMRIGHT", 0, -4)
    pop:SetFrameStrata("TOOLTIP")
    if pop.SetBackdrop then
        pop:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        pop:SetBackdropColor(0.02, 0.02, 0.03, 0.97)
    end
    local function line(y, handle, text)
        local fs = pop:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", handle and 30 or 8, y - 2); fs:SetPoint("RIGHT", -8, 0)
        fs:SetJustifyH("LEFT"); fs:SetText(text)
        if handle then
            local h = M.MakeHandle(pop, ROW_H - 2)
            h:SetPoint("TOPLEFT", 8, y); h:EnableMouse(false)
            h.active = handle == "active"
            pop[handle] = h
        end
    end
    line(-8, "go", "Go here next: a Custom route (orange) from it")
    line(-28, "active", "Where you're heading: always the top row")
    line(-50, nil, "Click a stop's name to open it. Right-click to hide it or for more.")
    pop:Hide()
    function q:Paint(hot)
        local c = theme().route
        self.ring:SetVertexColor(c[1], c[2], c[3], hot and 0.55 or 0.25)
        if pop.SetBackdropBorderColor then pop:SetBackdropBorderColor(c[1], c[2], c[3], 1) end
    end
    q:Paint(false)
    q:SetScript("OnEnter", function(self)
        self:Paint(true)
        pop.go:Paint(false); pop.active:Paint(false)  -- follow the current route colour
        pop:Show()
    end)
    q:SetScript("OnLeave", function(self) self:Paint(false); pop:Hide() end)
    return q
end

local function buildList()
    local f = CreateFrame("Frame", "FlowMapRoute", WorldMapFrame)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(false)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    -- Near-black, so the map doesn't show through behind the list.
    f.bg:SetColorTexture(0.015, 0.015, 0.025, 0.985)

    -- The roll-up bar: always visible. A dark header with an orange accent,
    -- a map icon, the title, and a +/- button on the right.
    local t = CreateFrame("Button", "FlowMapRouteToggle", f)
    t:SetHeight(26)
    t:SetPoint("TOPLEFT", 0, 0)
    t:SetPoint("TOPRIGHT", 0, 0)
    local o = theme().arrow
    t.bg = t:CreateTexture(nil, "BACKGROUND")
    t.bg:SetAllPoints()
    t.bg:SetColorTexture(0.11, 0.09, 0.06, 0.97)
    t.accent = t:CreateTexture(nil, "BORDER")
    t.accent:SetPoint("TOPLEFT"); t.accent:SetPoint("BOTTOMLEFT")
    t.accent:SetWidth(4)
    t.accent:SetColorTexture(o[1], o[2], o[3], 1)
    t.line = t:CreateTexture(nil, "BORDER")
    t.line:SetPoint("BOTTOMLEFT"); t.line:SetPoint("BOTTOMRIGHT")
    t.line:SetHeight(1)
    t.line:SetColorTexture(o[1], o[2], o[3], 0.8)
    t.icon = t:CreateTexture(nil, "ARTWORK")
    t.icon:SetSize(18, 18)
    t.icon:SetPoint("LEFT", 10, 0)
    t.icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
    t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    t.text = t:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t.text:SetPoint("LEFT", t.icon, "RIGHT", 8, 0)
    t.state = t:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    t.state:SetPoint("RIGHT", -32, 0)
    t.pm = t:CreateTexture(nil, "ARTWORK")
    t.pm:SetSize(18, 18)
    t.pm:SetPoint("RIGHT", -8, 0)
    t.hl = t:CreateTexture(nil, "HIGHLIGHT")
    t.hl:SetAllPoints()
    t.hl:SetColorTexture(o[1], o[2], o[3], 0.12)
    t:SetScript("OnClick", function()
        M:SetDrawer(collapsed())
    end)
    t:SetScript("OnEnter", function(self)
        ns.Tip(self, "ANCHOR_TOP")
        GameTooltip:AddLine(collapsed() and "Show Flow's routed quest list" or "Hide it and use the game's own map and quest log")
        GameTooltip:Show()
    end)
    t:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.toggle = t
    t:Hide()  -- the square map button opens and closes the drawer now

    -- How to use it, and which route to follow.
    -- Header: Flow's title bar (Theme.lua), like the Flow Tracker's and
    -- Flow Seller's; a spyglass for the route, "?" help on the right.
    local hd = ns.theme:TitleBar(f, "Flow Router", "Interface\\Icons\\INV_Misc_Spyglass_03")
    f.header = hd
    f.hint = hd   -- (older name: shown and hidden with the list)
    f.help = buildHelp(f)   -- how to use it: the "?" on the right

    local function choice(y, mode, text, tip)
        local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("TOPLEFT", 6, y)
        cb.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        cb.label:SetText(text)
        cb.mode = mode
        cb:SetScript("OnClick", function()
            ns.nav:SetMode(mode)
            M:Redraw()
        end)
        cb:SetScript("OnEnter", function(self)
            ns.Tip(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(tip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return cb
    end
    f.modeQuests = choice(-30, "quests", "Quests only",
        "Only the quests already in your log: their objectives, then turn-ins.")
    f.modeOptimal = choice(-48, "optimal", "Follow optimal path",
        "Everything worth doing nearby: your quests plus quests to pick up, trainers, and fishing or gathering when it's on the way.")

    -- Include professions (trainers to learn/raise them, and skill-up stops).
    local pc = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    pc:SetSize(20, 20)
    pc:SetPoint("TOPLEFT", 26, -68)
    pc.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pc.label:SetPoint("LEFT", pc, "RIGHT", 2, 0)
    pc.label:SetText("Include professions")
    pc:SetScript("OnClick", function(self)
        ns.db.nav.professions = self:GetChecked() and true or false
        ns.nav:Collect()
        M:Redraw()
    end)
    pc:SetScript("OnEnter", function(self)
        ns.Tip(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Trainers for professions you plan or have capped, and fishing / mining stops when a skill is behind your level.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    pc:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.profs = pc

    -- Show hidden stops (greyed out at the end of the list; click to unhide).
    local hc = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    hc:SetSize(20, 20)
    hc:SetPoint("TOPLEFT", 170, -92)
    hc.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hc.label:SetPoint("LEFT", hc, "RIGHT", 2, 0)
    hc.label:SetText("Show hidden stops")
    hc:SetScript("OnClick", function(self)
        ns.db.nav.showHidden = self:GetChecked() and true or false
        M:Redraw()
    end)
    hc:SetScript("OnEnter", function(self)
        ns.Tip(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Right-click any stop (here or on the map) to hide it. Tick this to see hidden ones and click one to bring it back.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    hc:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.showHidden = hc

    -- Show the route on the map (dotted trail, points); off = the list only.
    local rc = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    rc:SetSize(20, 20)
    rc:SetPoint("TOPLEFT", 170, -68)
    rc.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rc.label:SetPoint("LEFT", rc, "RIGHT", 2, 0)
    rc.label:SetText("Show route on map")
    rc:SetScript("OnClick", function(self) ns.db.nav.mapLines = self:GetChecked() and true or false; M:Redraw() end)
    f.showLines = rc
    hc:Hide(); hc.label:Hide()  -- hidden stops are always listed now

    -- One dropdown for the route instead of the checkboxes above (which
    -- couldn't reach Completionist, and had professions as an odd sub-box):
    -- "Route: Optimal with professions" opens the same list as the arrow's
    -- right-click menu. (The map's route on/off button sits above Flow's
    -- drawer button, so the checkbox for it goes too.)
    for _, cb in ipairs({ f.modeQuests, f.modeOptimal, pc, rc }) do cb:Hide(); cb.label:Hide(); cb.retired = true end
    local dd = CreateFrame("Button", nil, f)
    dd:SetHeight(22)
    dd:SetPoint("TOPLEFT", 8, -30); dd:SetPoint("TOPRIGHT", -8, -30)
    dd.bg = dd:CreateTexture(nil, "BACKGROUND"); dd.bg:SetAllPoints()
    dd.bg:SetColorTexture(1, 1, 1, 0.06)
    dd.hl = dd:CreateTexture(nil, "HIGHLIGHT"); dd.hl:SetAllPoints()
    dd.hl:SetColorTexture(1, 1, 1, 0.08)
    dd.text = dd:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dd.text:SetPoint("LEFT", 8, 0); dd.text:SetPoint("RIGHT", -20, 0); dd.text:SetJustifyH("LEFT")
    dd.arms = { dd:CreateLine(nil, "ARTWORK"), dd:CreateLine(nil, "ARTWORK") }
    for k, l in ipairs(dd.arms) do                         -- a small down chevron: "opens a list"
        l:SetThickness(1.5)
        l:SetStartPoint("RIGHT", dd, -14 + (k == 1 and -4 or 4), 2)
        l:SetEndPoint("RIGHT", dd, -14, -2)
        l:SetColorTexture(1, 1, 1, 0.8)
    end
    dd:SetScript("OnClick", function() ns.menu:Open(ns.menu:RouteItems()) end)
    dd:SetScript("OnEnter", function(self)
        ns.Tip(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Choose the route", 1, 1, 1)
        GameTooltip:AddLine("Current quests, optimal (with or without professions), or completionist; and the order.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    dd:SetScript("OnLeave", function() GameTooltip:Hide() end)
    function dd:Update()
        local mode, profs = ns.nav:Mode(), ns.db.nav.professions ~= false
        local what = (mode == "quests" and "Current quests") or (mode == "complete" and "Completionist")
            or (profs and "Optimal with professions" or "Optimal without professions")
        self.text:SetText("|cffffd200Route:|r " .. what)
    end
    f.routeDrop = dd

    -- Route state (XpValue.lua): one row of radios, each in its route colour.
    -- Custom route (orange) is on while you've picked the next stop yourself
    -- (a ^ in the list below); Most XP or Shortest puts you back on an
    -- optimised route.
    f.sorts = {}
    local SORTS = {
        { "xp", "Most XP", 6, "Most XP first (default): the shortest path, but quests are weighed by XP and level. More XP is worth a longer walk; quests 3+ levels above you wait." },
        { "distance", "Shortest", 92, "Shortest path: nearest stops first, XP ignored." },
        { "custom", "Custom route", 172, "On when you pick the next stop yourself (its ^ below): the route goes there first and is orange, not optimised, until you choose Most XP or Shortest again. Greyed out while you're on one of those." },
    }
    for _, sdef in ipairs(SORTS) do
        local rb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        rb:SetSize(20, 20)
        rb:SetPoint("TOPLEFT", sdef[3], -58)
        rb.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        rb.label:SetPoint("LEFT", rb, "RIGHT", 1, 0)
        rb.label:SetText(ns.theme:ModeText(sdef[1], sdef[2]))
        rb.mode = sdef[1]
        rb:SetScript("OnClick", function() ns.xpValue:SetMode(sdef[1]); M:Redraw() end)
        rb:SetScript("OnEnter", function(self)
            ns.Tip(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(sdef[4], 1, 1, 1, true)
            GameTooltip:Show()
        end)
        rb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.sorts[#f.sorts + 1] = rb
    end

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.title:SetPoint("TOPLEFT", 8, -84)
    f.title:SetPoint("TOPRIGHT", -8, -84)
    f.title:SetJustifyH("LEFT")

    -- Your own waypoint (Waypoint.lua), when you've set one: a green line
    -- above the route, not a stop in it. The arrow follows it (orange) until
    -- you get there or clear it; the route below carries on as it was.
    f.wp = M.MakeWaypointRow(f)

    -- Each row: [^] handle, then the stop.
    --   ^ handle    go here first: the route is re-planned from this stop,
    --               which moves to the top and gets the (o); hovering it
    --               previews that route
    --   (o)         the stop you're heading to, always the top row
    --   row hover   the stop's details (quest objectives and text)
    --   row click   open it (its card)
    --   right-click menu
    f.rows = {}
    for i = 1, MAX_ROWS do
        local r = CreateFrame("Button", nil, f)
        r:SetHeight(ROW_H - 2)
        r:SetPoint("TOPLEFT", 8, -102 - (i - 1) * ROW_H)
        r:SetPoint("TOPRIGHT", -8, -102 - (i - 1) * ROW_H)
        r.hl = r:CreateTexture(nil, "HIGHLIGHT")
        r.hl:SetAllPoints()
        r.hl:SetColorTexture(1, 1, 1, 0.1)
        r.go = M.MakeHandle(r, ROW_H - 2)
        r.go:SetPoint("LEFT", 0, 0)
        r.go:SetScript("OnEnter", function(self)
            self:Paint(true); ns.nav:ClickCursor(true)
            local row = self:GetParent()
            hoverKey = row.key
            ns.Tip(self, "ANCHOR_RIGHT")
            if self.active then
                GameTooltip:AddLine("Where you're heading")
                GameTooltip:AddLine(M.IsChosen(row.key) and "Your pick (Custom route). Click to go back to the optimised route."
                    or "The next stop on your route.", 1, 1, 1, true)
            else
                M:Preview(row.key)
                GameTooltip:AddLine("Go here next")
                GameTooltip:AddLine("Makes it your next stop: a Custom route (orange) until you choose Most XP or Shortest again. The orange line on the map is that route.", 1, 1, 1, true)
            end
            GameTooltip:Show()
        end)
        r.go:SetScript("OnLeave", function(self)
            self:Paint(false); ns.nav:ClickCursor(false)
            hoverKey = nil
            M:Preview(nil)
            GameTooltip:Hide()
        end)
        r.go:SetScript("OnClick", function(self)
            local row = self:GetParent()
            M:Preview(nil)
            if self.active then
                if M.IsChosen(row.key) then ns.nav:ClearSelection() end
            elseif row.key then
                ns.nav:Select(row.key)
            end
            GameTooltip:Hide()
            M:Redraw()
        end)
        r.leg = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        r.leg:SetPoint("RIGHT", 0, 0)
        r.leg:SetJustifyH("RIGHT")
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.text:SetPoint("LEFT", r.go, "RIGHT", 5, 0)
        r.text:SetPoint("RIGHT", r.leg, "LEFT", -6, 0)
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(false)
        r:SetScript("OnEnter", function(self)
            local g = self.blocked or self.goal
            if not g then return end
            ns.Tip(self, "ANCHOR_RIGHT")
            local footer
            if self.isHidden then footer = "Hidden. Click to bring it back."
            elseif self.blocked then footer = "Joins the route by itself once that's sorted. Right-click: menu."
            else footer = "Click: open it. ^: go here next (Custom route). Right-click: menu." end
            if not self.blocked then ns.nav:ClickCursor(true) end
            ns.nav:FillTooltip(GameTooltip, g, footer)
            GameTooltip:Show()
            if not (self.isHidden or self.blocked) then hoverKey = self.key; M:Redraw() end
        end)
        r:SetScript("OnLeave", function()
            GameTooltip:Hide()
            ns.nav:ClickCursor(false)
            if hoverKey then hoverKey = nil; M:Redraw() end
        end)
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        r:SetScript("OnClick", function(self, button)
            M:Preview(nil)
            local g = self.blocked or self.goal
            if self.isHidden then
                ns.nav:Unhide(self.key)        -- either click brings it back
            elseif button == "RightButton" and g then
                local items = {
                    { title = true, text = g.text or g.title or "This stop" },
                    { text = "Open it", func = function() ns.nav:OpenStop(g, self) end },
                    { text = "Go here next (Custom route)", disabled = self.blocked ~= nil, func = function() ns.nav:Select(g.key) end },
                    { text = "Point the arrow here (your waypoint)", func = function() M.PointHere(g) end },
                    { text = "Hide this stop", func = function() ns.nav:Hide(g.key) end },
                    { sep = true },
                }
                for _, it in ipairs(ns.menu:RouteItems()) do items[#items + 1] = it end
                ns.menu:Open(items)
            elseif self.blocked then
                ns:Print((g.text or "that stop") .. ": " .. (g.blockedBy or "blocked"))
            elseif g then
                ns.nav:OpenStop(g, self)
            end
            M:Redraw()
        end)
        f.rows[i] = r
    end
    return f
end

local function updateList()
    list = list or buildList()
    button = button or buildButton()
    button:Draw()
    if button.routeToggle then button.routeToggle:Draw() end
    local plan = ns.nav.plan
    -- Keep the panel up even with an empty route, so the mode can be switched back.
    plan = plan or {}
    if not ns.nav:PlayerPos() then list:Hide() return end
    if button.cover then button.cover:SetShown(not collapsed() and sidePanelOpen()) end
    if collapsed() then list:Hide() return end
    place()
    list:Show()
    local hidden = collapsed()
    list.toggle.text:SetText("Flow Router")
    list.toggle.state:SetText(hidden and "show" or "hide")
    list.toggle.pm:SetTexture(hidden and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
    list.bg:SetShown(not hidden)
    list.title:SetShown(not hidden)
    list.hint:SetShown(not hidden)
    list.routeDrop:SetShown(not hidden)
    list.routeDrop:Update()
    for _, rb in ipairs(list.sorts) do
        local on = ns.xpValue:Mode() == rb.mode
        rb:SetChecked(on)
        if rb.mode == "custom" then
            -- Greyed out on Most XP or Shortest: a Custom route starts by
            -- picking a stop (its ^), not here. (Its tooltip still says how.)
            rb:SetEnabled(on)
            rb.label:SetText(on and ns.theme:ModeText("custom", "Custom route") or "|cff777777Custom route|r")
        end
    end
    if hidden then
        -- Rolled up: only the bar remains, at the top of the area.
        for i = 1, MAX_ROWS do list.rows[i]:Hide() end
        list.wp:Hide()
        return
    end
    -- Your waypoint's line, then the route rows under it.
    local wpShown = list.wp:Update()
    local top = -102 - (wpShown and ROW_H or 0)
    for i = 1, MAX_ROWS do
        local r = list.rows[i]
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 8, top - (i - 1) * ROW_H)
        r:SetPoint("TOPRIGHT", -8, top - (i - 1) * ROW_H)
    end
    local following = (ns.party and ns.party:Following()) or (ns.partyHelp and ns.partyHelp:Joined())
    local nBlocked = ns.nav.blockedGoals and #ns.nav.blockedGoals or 0
    list.title:SetText(string.format("%s: %d stops, about %d yd%s%s",
        following and "Party route" or (ns.xpValue:IsCustom() and ns.theme:ModeText("custom", "Custom route")) or "Your route",
        #plan, plan[#plan] and plan[#plan].cum or 0,
        nBlocked > 0 and string.format("  |cffff7070(%d blocked, listed below)|r", nBlocked) or "",
        ns.nav.zoneNote and ("  |cff888888" .. ns.nav.zoneNote .. "|r") or ""))
    if #plan == 0 then list.title:SetText("Nothing on this route right now. Try Route: Optimal (above).") end
    local labels = ns.nav:PlanLabels(plan)
    local fit = math.min(MAX_ROWS, math.floor((list:GetHeight() - 108 - (wpShown and ROW_H or 0)) / ROW_H))
    -- Route stops first, then blocked stops (lock + reason), then (if
    -- ticked) hidden stops, greyed out.
    local blocked = ns.nav.blockedGoals or {}
    local hiddenGoals = ns.nav.hiddenGoals or {}  -- always listed, greyed out
    -- One list of rows: route stops, then blocked, then hidden. Blocked and
    -- hidden rows always get room (up to half the list), so a full route
    -- can't push them out of sight.
    local entries = {}
    local extras = #blocked + #hiddenGoals
    local reserve = math.min(extras, math.floor(fit / 2))
    for i, s in ipairs(plan) do
        if i > fit - reserve then break end
        entries[#entries + 1] = { stop = s, i = i }
    end
    for _, b in ipairs(blocked) do entries[#entries + 1] = { blocked = b } end
    for _, h in ipairs(hiddenGoals) do entries[#entries + 1] = { hidden = h } end
    for i = 1, MAX_ROWS do
        local r, e = list.rows[i], entries[i]
        if e and i <= fit and e.stop then
            local s = e.stop
            r.key, r.isHidden, r.blocked = s.goal.key, false, nil
            r.goal = s.goal
            -- The (o) is always the top row: the stop you're heading to. A
            -- stop you moved first IS the top row, so it needs no other mark.
            r.go.active = (e.i == 1)
            r.go:Paint(r.go:IsMouseOver())
            r.go:Show()
            r.text:SetText(ns.nav:FormatStop(e.i, s.goal, labels[e.i]))
            r.leg:SetText(string.format("+%d yd", s.leg or 0))
            r:Show()
        elseif e and i <= fit and e.blocked then
            local b = e.blocked
            r.key, r.isHidden, r.blocked, r.goal = b.key, false, b, b
            r.go:Hide()
            local text, why = ns.nav:FormatBlocked(b)
            r.text:SetText(text)
            r.leg:SetText(why)
            r:Show()
        elseif e and i <= fit and e.hidden then
            local h = e.hidden
            r.key, r.isHidden, r.blocked, r.goal = h.key, true, nil, h
            r.go:Hide()
            r.text:SetText("|cff777777(hidden) " .. (h.text or h.title or "?") .. "|r")
            r.leg:SetText("|cff777777click to show|r")
            r:Show()
        else
            r:Hide()
        end
    end
end
M._updateList = function() updateList() end   -- (tests)

-- The stop you point at: under the mouse, opened from the tracker, or previewed.
local function pointedKey()
    return hoverKey or (focusKey and GetTime() < focusUntil and focusKey) or previewKey or nil
end

-- What the map drawing depends on, apart from where you stand: the map and
-- its zoom, the route (each stop, its spot, its text and how many spawns it
-- has), the stop you point at, the route colour, your waypoint and whether
-- you're on this map. The route's tables are made again every few seconds
-- with the same stops in them, so this compares what's in them, not which
-- table it is. st keeps the last values; true = something changed.
local EMPTY = {}
local function setv(st, k, v)
    if st[k] ~= v then st[k] = v; return true end
    return false
end
local function changed(st, c, mapID, pointed)
    local T, p = theme(), ns.nav:PlayerPos()
    local w = ns.waypoint and ns.waypoint:Get()
    local route = T.route or { 1, 1, 1 }
    local d = false
    d = setv(st, "map", mapID or false) or d
    d = setv(st, "w", c:GetWidth()) or d
    d = setv(st, "h", c:GetHeight()) or d
    d = setv(st, "scale", canvasScale()) or d
    d = setv(st, "pointed", pointed or false) or d
    d = setv(st, "preview", previewKey or false) or d
    d = setv(st, "lines", ns.db.nav.mapLines ~= false) or d
    d = setv(st, "palette", T.palette or false) or d
    d = setv(st, "r", route[1]) or d
    d = setv(st, "g", route[2]) or d
    d = setv(st, "b", route[3]) or d
    d = setv(st, "wpMap", w and w.map or false) or d
    d = setv(st, "wpX", w and w.x or false) or d
    d = setv(st, "wpY", w and w.y or false) or d
    d = setv(st, "cont", p and p.cont or false) or d
    d = setv(st, "here", (mapID and toMap(p, mapID)) ~= nil) or d
    local plan = ns.nav.plan or EMPTY
    local sp = st.plan or {}
    st.plan = sp
    d = setv(st, "stops", #plan) or d
    d = setv(st, "limit", ns.nav:StopsShown() or false) or d   -- Stops on the map changed
    for i, s in ipairs(plan) do
        local g, pt, b = s.goal, s.point or EMPTY, (i - 1) * 6
        local key, text, n = g.key, g.text or g.title or false, g.points and #g.points or 0
        local m, x, y = pt.map or false, pt.x or pt.wx or false, pt.y or pt.wy or false
        if sp[b + 1] ~= key or sp[b + 2] ~= m or sp[b + 3] ~= x or sp[b + 4] ~= y or sp[b + 5] ~= n or sp[b + 6] ~= text then
            sp[b + 1], sp[b + 2], sp[b + 3], sp[b + 4], sp[b + 5], sp[b + 6] = key, m, x, y, n, text
            d = true
        end
    end
    return d
end
M._changed = changed   -- (tests)

-- Nothing changed but you moved: move the lines that start at you (and the
-- dots' legs with them). st = the lines (links); false = nothing to move.
local function followPlayer(st, c, mapID)
    local px, py = toMap(ns.nav:PlayerPos(), mapID)
    if not px or (px == st.px and py == st.py) then return false end
    st.px, st.py = px, py
    local w, h = c:GetWidth(), c:GetHeight()
    for i = 1, st.n do
        local k = st[i]
        if k.line then k.line:SetStartPoint("TOPLEFT", c, px * w, -py * h) end
        k.leg[1], k.leg[2] = px, py
    end
    return true
end
M._followPlayer, M._links = followPlayer, links   -- (tests)

local last = {}          -- what the last full redraw drew (changed())
M._fullDraws = 0         -- (tests)

local function fullDraw()
    local c = canvas()
    if not (c and WorldMapFrame:IsShown() and ns.nav and ns.db.nav.mapRoute ~= false) then return end
    if not host then
        host = CreateFrame("Frame", nil, c)
        host:SetAllPoints(c)
        host:EnableMouse(false)
    end
    M._fullDraws = M._fullDraws + 1
    host:SetFrameStrata(aboveMap())
    host:SetFrameLevel(math.min(c:GetFrameLevel() + 1000, 9000))
    -- Reuse frames in place and only hide leftovers afterwards: hiding the
    -- pin under the mouse would fire OnLeave and make previews flicker.
    local oldLines, oldPins = nLines, nPins
    legs = {}
    links.n = 0
    targetPin = nil
    nLines, nPins = 0, 0
    local oldBlobs = nBlobs
    nBlobs = 0
    shapesNext = {}
    local mapID = WorldMapFrame:GetMapID()
    changed(last, c, mapID, pointedKey())   -- remember what this draw is of
    links.px, links.py = toMap(ns.nav:PlayerPos(), mapID)
    if mapID and ns.db.nav.mapLines ~= false then  -- "Show route on map" (Flow Router)
        local T = theme()
        local plan = ns.nav.plan or {}
        local pointed = pointedKey()
        local labels = ns.nav:PlanLabels(plan)
        -- Every area stop gets its own bordered patch: faint, the next stop
        -- stronger, the one you point at in the hover colour. Drawn last = on top.
        local order = {}
        for i = #plan, 2, -1 do if plan[i].goal.key ~= pointed then order[#order + 1] = i end end
        if plan[1] and plan[1].goal.key ~= pointed then order[#order + 1] = 1 end
        for i, s in ipairs(plan) do if s.goal.key == pointed then order[#order + 1] = i end end
        for _, i in ipairs(order) do
            local g = plan[i].goal
            -- Only the patch the route goes to; the stop you point at shows
            -- every place its mobs live. Past your Stops on the map limit,
            -- only the stop you point at.
            if g.key == pointed then drawArea(c, mapID, g, T.hover, true, labels[i], plan[i].point, true)
            elseif ns.nav:StopVisible(i, false) then drawArea(c, mapID, g, T.route, i == 1, labels[i], plan[i].point) end
        end
        if previewKey then
            -- Only the route you'd follow, all in one colour: its lines, and the
            -- stops as points (kept where they are so the one under the mouse
            -- doesn't jump).
            drawRoute(c, mapID, ns.nav.plan, T.proposed, true, 0.95, true)
            drawRoute(c, mapID, ns.nav:PlanFor(previewKey), T.proposed, false, 0.95)
        else
            drawRoute(c, mapID, ns.nav.plan, T.route, true)
        end
        drawProf(c, mapID)
        drawWaypoint(c, mapID)
    else
        if wpPin then wpPin:Hide() end
        if profPin then profPin:Hide() end
    end
    for i = nLines + 1, oldLines do lines[i]:Hide() end
    for i = nPins + 1, oldPins do pins[i]:Hide() end
    pcall(declutter)   -- labels push apart
    for i = nBlobs + 1, oldBlobs do blobs[i]:Hide() end
    shapes = shapesNext   -- area shapes not drawn this time are dropped
    drawDots()
    updateList()
end

-- Everything drawn again: on a click, hover, preview, colour or waypoint
-- change (whoever calls it), and when the map opens.
function M:Redraw() fullDraw() end

-- The map's 0.5 s tick. Only when something on it changed (changed())
-- is it all drawn again; otherwise only the lines from you follow you and
-- the Flow Router's rows refresh. Returns true when a full redraw is due
-- (M:Tick does it, so the two are timed apart in /flow perf).
local function keepUp()
    local c = canvas()
    if not (c and WorldMapFrame:IsShown() and ns.nav and ns.db.nav.mapRoute ~= false) then return false end
    local mapID = WorldMapFrame:GetMapID()
    if not host or changed(last, c, mapID, pointedKey()) then return true end
    local moved = followPlayer(links, c, mapID)
    -- The arrow's colour changed (red to green as you close in): the stop's
    -- dot and the trail to it follow.
    local col = arrowColor(false)
    local recolor = false
    if targetPin and targetPin:IsShown() and col and targetPin.liveCol ~= col then
        targetPin.bg:SetVertexColor(col[1], col[2], col[3], 1)
        targetPin.liveCol = col
        recolor = true
    end
    if col ~= links.col or arrowColor(true) ~= links.wcol then
        links.col, links.wcol, recolor = col, arrowColor(true), true
    end
    if moved or recolor then drawDotsTimed() end
    updateList()
    return false
end
keepUp = ns.perf.Wrap("world map (keeping up with you)", keepUp)
function M:Tick()
    if keepUp() then M:Redraw() end
end

-- Highlight one stop for a few seconds (opened from the tracker or arrow menu).
function M:Focus(key, secs)
    focusKey, focusUntil = key, GetTime() + (secs or 6)
    M:Redraw()
    C_Timer.After((secs or 6) + 0.1, function() if WorldMapFrame:IsShown() then M:Redraw() end end)
end

function M:Preview(key)
    if previewKey == key then return end
    previewKey = key
    pcall(M.Redraw, M)
end

-- The quest log key (L) shows the quest log, so the Flow Router steps
-- aside while it's open, and comes back the next time you open the map
-- (M). A hook after the game's own function: nothing of the game's runs
-- from Flow's code.
function M.QuestLogOpened(mapShown)
    if mapShown and not collapsed() then
        M.asideForQuestLog = true
        ns.db.nav.mapListCollapsed = true
        pcall(M.Redraw, M)
    end
end
function M.MapClosed()
    if M.asideForQuestLog then
        M.asideForQuestLog = nil
        ns.db.nav.mapListCollapsed = false
    end
end

ns:OnLoad(function()
    if ToggleQuestLog then
        hooksecurefunc("ToggleQuestLog", function() M.QuestLogOpened(WorldMapFrame and WorldMapFrame:IsShown()) end)
    end
    local acc, open = 0, false
    local driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < ((ns.Lite and ns.Lite()) and 2 or 0.5) then return end   -- lite: every 2 s
        acc = 0
        if WorldMapFrame and WorldMapFrame:IsShown() then
            -- Just opened: draw it all; open: keep up (cheap unless it changed).
            if open then pcall(M.Tick, M) else pcall(M.Redraw, M) end
            open = true
        else
            if open then M.MapClosed() end
            open = false
        end
    end)
end)

ns.commands.map = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        ns.db.nav.mapRoute = (arg == "on")
        if arg == "off" then
            for i = 1, nLines do lines[i]:Hide() end
            for i = 1, nPins do pins[i]:Hide() end
            for i = 1, nBlobs do blobs[i]:Hide() end
            if list then list:Hide() end
            legs, links.n = {}, 0
            drawDots()   -- no legs: the dots go too
            for k in pairs(last) do last[k] = nil end
        end
        ns:Print("route on the world map " .. arg)
    else
        ns:Print("/flow map on|off. Hover a checkpoint to preview, click to choose. Alt-click the map to set a waypoint.")
    end
end

-- Timed for /flow perf (with "keeping up with you" and "route dots").
M.Redraw = ns.perf.Wrap("world map (full redraw)", M.Redraw)
