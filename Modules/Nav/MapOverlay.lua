-- World map overlay: your route as numbered checkpoints and lines.
--   checkpoint label: "3 [9]" = 3rd step, quest level 9; "!2 [8]" = 2nd quest pickup
--   colours (Theme.lua): the route and arrow colour shows the order mode
--     (purple = Most XP first, blue = Shortest path); hovering a ^ shows only
--     the route you'd follow, in legendary orange. Your own waypoint is a
--     green line and (o) of its own. /flow settings has a colour-blind palette.
--   The step you're heading to (route step 1) has a white ring, the rest black.
--   Click a step: open it. The ^ in the Flow Router: go there first.

local _, ns = ...
local M = {}
ns.mapOverlay = M

-- "Show the route on the world map" is two saved keys: nav.mapRoute (/flow
-- map on|off: the whole overlay) and nav.mapLines (the route itself: Flow
-- Settings' box and the Flow Router's buttons). /flow map off used to leave
-- the box ticked, and ticking it did nothing (F-091). Shown = both on;
-- turning it on from any of them turns both on.
function M:RouteShown()
    local n = ns.db.nav
    return n.mapRoute ~= false and n.mapLines ~= false
end
function M:SetRouteShown(on)
    local n = ns.db.nav
    if on then
        if n.mapRoute == false then n.mapRoute = true end
        n.mapLines = true
    else
        n.mapLines = false
    end
end

-- The trail's `live` flag: false = your next step (the arrow's colour, by
-- its distance), nil = a plain route leg (its own colour). Written out:
-- `x and false or nil` is always nil in Lua, which kept the next step's
-- trail in the route colour (0.35.127).
function M.LegLive(first, alpha)
    if first and alpha == nil then return false end
    return nil
end

local host           -- frame on the map canvas holding lines
local lines, pins = {}, {}
local nLines, nPins = 0, 0
local previewKey, hoverKey
-- Pointing at a step in a list (the Flow Router's rows, the Flow Tracker):
-- the map shows that step alone, between the step before and the one after
-- (drawSolo). Pointing at a pin on the map itself doesn't: the pins stay.
local hoverSolo = false
local focusKey, focusUntil = nil, 0   -- a step opened from the tracker / arrow menu

local function theme() return ns.theme end

-- "Point the arrow here": your own waypoint at this step (the arrow goes there
-- first; the planned route stays as it is and carries on after).
function M.PointHere(goal)
    if not (goal and ns.waypoint) then return end
    local pt = ns.nav:Spot(goal)   -- (the same spot the arrow and the step card use)
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
-- The same, wherever it falls: beside the map too (x or y under 0 or over 1).
-- For a line that leaves the map towards a step in the next zone.
local function toMapRaw(pt, mapID)
    if not pt then return nil end
    if pt.map == mapID and pt.x then return pt.x, pt.y end
    if pt.wx and pt.cont and C_Map.GetMapPosFromWorldPos and CreateVector2D then
        local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, pt.cont, CreateVector2D(pt.wx, pt.wy), mapID)
        if ok and pos then
            local x, y = pos:GetXY()
            if x and y then return x, y end
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

-- The step you're heading to (set by pin, recoloured by keepUp) and the
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

-- target: the step you're heading to (route step 1), drawn as Flow's target
-- marker (o) with a faint white ring; the other steps have black rings.
M.TARGET_SIZE = 12          -- was 16: the heading-there pin drowned the map
M.TARGET_RING_ALPHA = 0.45
-- The step you point at: was 18, a red blot over its neighbours ("make the
-- red dot smaller, so it looks like it fills the centre of the point").
M.HOVER_SIZE = 12
-- top: the step under your mouse (bigger, in the hover colour, on top).
-- Pure: a checkpoint's label without its quest level ("3 [9]" -> "3"), plain or coloured (QuestLevels.lua).
function M.ShortLabel(label)
    local s = tostring(label or ""):gsub(" |cff%x%x%x%x%x%x%[%d+%]|r", "")
    s = s:gsub(" %[%d+%]", "")
    return s
end
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
        -- Like a row in the Flow Router list: hover = the step's details (and
        -- it's highlighted), click = open it, right-click = menu. Previewing
        -- and changing the route is only the ^ handle in the list.
        p:SetScript("OnEnter", function(self)
            hoverKey = self.stop.goal.key
            hoverSolo = false
            ns.Tip(self, "ANCHOR_RIGHT")
            ns.nav:ClickCursor(true)
            ns.nav:FillTooltip(GameTooltip, self.stop.goal, "Click: open it. Right-click: menu. (^ in the Flow Router: go here next, a Custom route.)")
            GameTooltip:Show()
            -- Highlight in place (redrawing would move the point under the mouse).
            self:SetSize(M.HOVER_SIZE, M.HOVER_SIZE); self.edge:SetVertexColor(1, 1, 1, 1)
            self:SetFrameLevel(self:GetFrameLevel() + 100)
        end)
        p:SetScript("OnLeave", function(self)
            ns.nav:ClickCursor(false)
            hoverKey = nil
            GameTooltip:Hide()
            if self.isTarget then
                self:SetSize(M.TARGET_SIZE, M.TARGET_SIZE)                   -- faint white ring: where you're heading
                self.edge:SetVertexColor(1, 1, 1, M.TARGET_RING_ALPHA)
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
                    { title = true, text = g.text or g.title or "This step" },
                    { text = "Open it", func = function() ns.nav:OpenStop(g, self) end },
                    { text = "Go here next (Custom route)", func = function() ns.nav:Select(g.key) end },
                    { text = "Point the arrow here (your waypoint)", func = function() M.PointHere(g) end },
                    { text = "Hide this step", func = function() ns.nav:Hide(g.key) end },
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
    p:SetAlpha(1)
    p.isTarget, p.color = (target and not top) and true or false, color
    p:SetParent(c)
    -- The hovered step: bigger, white ring, above every other pin and line.
    -- Relative to the map canvas: fixed numbers could end up under the map's own
    -- art (lakes, towns) when the canvas itself sits at a high level.
    local base = math.min(c:GetFrameLevel() + 1000, 9000)
    p:SetFrameStrata(aboveMap())
    p:SetFrameLevel(top and base + 200 or base + 100)
    local size = top and M.HOVER_SIZE or (target and M.TARGET_SIZE or 11)
    p:SetSize(size, size)
    p.text:SetFontObject((top or target) and "GameFontNormal" or "GameFontHighlightSmall")
    p:SetScale(1 / canvasScale())
    p:ClearAllPoints()
    local s = p:GetScale()
    p:SetPoint("CENTER", c, "TOPLEFT", x * c:GetWidth() / s, -y * c:GetHeight() / s)
    p.bg:ClearAllPoints()
    p.edge:ClearAllPoints(); p.edge:SetPoint("TOPLEFT", -2, 2); p.edge:SetPoint("BOTTOMRIGHT", 2, -2)
    if target and not top then
        -- (o), the step you're heading to: a thin, faint white ring, a dark
        -- gap, the dot in the arrow's colour. Kept small so it marks the spot
        -- without drowning the map. Every other step has a black ring.
        p.edge:ClearAllPoints(); p.edge:SetPoint("TOPLEFT", -1, 1); p.edge:SetPoint("BOTTOMRIGHT", 1, -1)
        p.edge:SetVertexColor(1, 1, 1, M.TARGET_RING_ALPHA)
        p.hole:ClearAllPoints(); p.hole:SetPoint("TOPLEFT", 0, 0); p.hole:SetPoint("BOTTOMRIGHT", 0, 0)
        p.hole:Show()
        p.bg:SetPoint("TOPLEFT", 2, -2); p.bg:SetPoint("BOTTOMRIGHT", -2, 2)
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
    p.full, p.short = label, M.ShortLabel(label)   -- "3 [9]" and "3" (for the declutter)
    p.top = top and true or false
    p:Show()
    return p
end
M._pin = pin   -- (tests)

-- Draws one route as a faint dotted trail through round points, like a
-- treasure map: it shows the way without covering the map. Steps on another
-- map are skipped, and the trail joins the ones on this map. Each point's
-- label carries the step's type icon and number ("[icon] 3 [9]"). The trail
-- from you to the step you're heading to wears the arrow's colour (and the
-- step's dot too), a little stronger; the rest of the route is fainter.
-- Legs are kept from the last draw; the dots are drawn again only when you
-- move or the arrow's colour changes. The dots drift slowly toward the next
-- step, so the trail shows which way it goes (0.35.170): the game moves them
-- (a looping animation on each dot), so still nothing of Flow's runs per frame.
local legs, dots, nDots = {}, {}, 0
local DOT_GAP = 12     -- screen pixels between dots
local DOT_SIZE = 4     -- screen pixels across
local DOT_CLEAR = 9    -- no dots this close to either end (under the steps' points)
local DOT_CYCLE = 2    -- seconds a dot takes to drift to the next dot's place (6 pixels a second)
local FIRST_ALPHA, REST_ALPHA = 0.8, 0.45
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- Does the trail move? Yes, unless you turned it off ("Path moves along the
-- route") or Flow is in lite mode.
function M.PathMoves()
    if ns.Lite and ns.Lite() then return false end
    return ns.db.nav.pathMotion ~= false
end

-- "Path opacity" (Flow Settings, /flow map opacity): 0.1 to 1. The default,
-- 0.5, is the look the trail always had (the leg to your next step at 0.8,
-- the rest at 0.45); 1 doubles that, up to fully solid.
M.PATH_ALPHA = 0.5
function M.PathAlpha()
    local v = tonumber(ns.db.nav.pathAlpha) or M.PATH_ALPHA
    return math.max(0.1, math.min(1, v))
end
function M:SetPathAlpha(v)
    v = math.max(0.1, math.min(1, tonumber(v) or M.PATH_ALPHA))
    ns.db.nav.pathAlpha = v
    M.PathChanged()
    return v
end
-- A leg's own alpha under your setting (pure: the tests pass both).
function M.LegAlpha(alpha, setting)
    return math.max(0.05, math.min(1, (alpha or 1) * (setting or M.PATH_ALPHA) / M.PATH_ALPHA))
end

-- The arrow's colour right now (Nav sets it each time it turns the arrow),
-- for the trail to where it points: the route's first step (waypoint false)
-- or your waypoint (true). nil: the arrow points somewhere else.
function arrowColor(waypoint)
    local N = ns.nav
    if not (N and N.arrowColor) then return nil end
    if (N.arrowWaypoint and true or false) ~= waypoint then return nil end
    return N.arrowColor
end

-- Where along a leg len long the dots go: evenly, about gap apart, none
-- within clear of either end. Also returns the step between two dots.
-- moving: the last dot is left out, because each dot drifts one step on, to
-- the next dot's place (the last of them to where that one would be).
local function dotSpots(len, gap, clear, moving)
    local out = {}
    local span = len - 2 * clear
    if span < gap * 0.5 then return out, 0 end
    local n = math.max(1, math.floor(span / gap + 0.5))
    local step = span / n
    for i = 0, moving and n - 1 or n do out[#out + 1] = clear + i * step end
    return out, step
end
M._dotSpots = dotSpots   -- (tests)

-- Lines that start at you (to the first step, to your waypoint). Between
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

-- A dot drifts one step (ox, oy) to the next dot's place, then starts again,
-- over and over: the trail seems to flow toward the step. The game moves it
-- (a looping Translation). No ox: it stands still.
local canDrift = true   -- false once this client refused the animation
local function drift(d, ox, oy)
    if not ox then
        if d.moving then d.ag:Stop(); d.moving = false end
        return
    end
    if not d.ag then
        local ok, err = pcall(function()
            d.ag = d:CreateAnimationGroup()
            d.ag:SetLooping("REPEAT")
            d.tr = d.ag:CreateAnimation("Translation")
            d.tr:SetDuration(DOT_CYCLE)
        end)
        if not ok then
            canDrift, d.ag = false, nil
            ns:Log("map", "the trail can't move on this client: " .. tostring(err))
            return
        end
    end
    -- The same step as before: it carries on (a redraw doesn't restart it).
    if d.moving and math.abs(d.ox - ox) < 0.01 and math.abs(d.oy - oy) < 0.01 then return end
    d.ag:Stop()
    d.tr:SetOffset(ox, oy)
    d.ox, d.oy, d.moving = ox, oy, true
    -- Started partway, by the clock: every dot is at the same point of its
    -- step, so the leg from you (drawn again as you walk) doesn't jump back.
    d.ag:Play(false, GetTime() % DOT_CYCLE)
end
M._drift = drift   -- (tests)

local function drawDots()
    local c = canvas()
    if not (c and host) then return end
    local old = nDots
    nDots = 0
    local w, h, sc = c:GetWidth(), c:GetHeight(), canvasScale()
    local gap, size, clear = DOT_GAP / sc, DOT_SIZE / sc, DOT_CLEAR / sc
    local moving = canDrift and M.PathMoves()
    local strength = M.PathAlpha()
    for _, leg in ipairs(legs) do
        local x1, y1, x2, y2 = leg[1] * w, -leg[2] * h, leg[3] * w, -leg[4] * h
        local dx, dy = x2 - x1, y2 - y1
        local len = math.sqrt(dx * dx + dy * dy)
        local col = (leg.live ~= nil and arrowColor(leg.live)) or leg.color
        local a = M.LegAlpha(leg.alpha, strength)
        if len > 0 then
            local ux, uy = dx / len, dy / len
            local spots, step = dotSpots(len, gap, clear, moving)
            for _, along in ipairs(spots) do
                if nDots >= 600 then break end
                local d = dot()
                -- Only what changed is set again (size, colour, showing).
                if d.size ~= size then d:SetSize(size, size); d.size = size end
                if d.a ~= a or d.col ~= col then d:SetVertexColor(col[1], col[2], col[3], a); d.a, d.col = a, col end
                d:ClearAllPoints()
                d:SetPoint("CENTER", c, "TOPLEFT", x1 + ux * along, y1 + uy * along)
                if not d.on then d:Show(); d.on = true end
                if moving then drift(d, ux * step, uy * step) else drift(d) end
            end
        end
    end
    for i = nDots + 1, old do dots[i]:Hide(); dots[i].on = false; drift(dots[i]) end
end

-- The map closed: the dots stop drifting (they start again at the next draw).
function M.StopDots()
    for i = 1, #dots do drift(dots[i]) end
end

-- "Path opacity" or "Path moves" changed: the trail is drawn again if the map is open.
function M.PathChanged()
    if WorldMapFrame and WorldMapFrame:IsShown() then pcall(drawDots) end
end
-- Timed apart from the redraws so /flow perf shows it.
local drawDotsTimed = ns.perf.Wrap("world map (route dots)", drawDots)

-- The step you moved to the front (the ^ handle, "Go here first"). The route
-- is planned from it, so it's step 1 and wears the (o) like any first step;
-- no other mark. It stays first until it's done or you click its (o).
function M.IsChosen(key)
    local sel = ns.nav and ns.nav.selection
    return key ~= nil and sel ~= nil and sel.first == key
end

-- Areas: a step that's a whole area (mobs to kill, things to loot, a farm
-- step) shows where its mobs live as soft discs in the route colour, under
-- the lines, instead of only the one point the route passes. Drawn for the
-- next step and the one you're pointing at.
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
-- Hovering a disc: every disc of that step lights up, and the tooltip says
-- which step it is and what you need there (Loot Stringy Wolf Meat 9/66).
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
            { title = true, text = g.text or g.title or "This step" },
            { text = "Open it", func = function() ns.nav:OpenStop(g, self) end },
            { text = "Go here next (Custom route)", func = function() ns.nav:Select(g.key) end },
            { text = "Point the arrow here (your waypoint)", func = function() M.PointHere(g) end },
            { text = "Hide this step", func = function() ns.nav:Hide(g.key) end },
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
-- the route's spot for this step (all of them when there's no route spot).
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
-- then a hull over 12 points round each), so it's kept per step and map
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

-- routePt: where the route goes for this step. Only that patch is drawn,
-- unless allPatches (the step you point at: every place its mobs live).
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
-- all: the place where it overlaps least. The step you point at goes first,
-- then the route in order.
local CANDS = {   -- anchor on the label, anchor on the point, x, y
    { "LEFT", "RIGHT", 3, 0 }, { "RIGHT", "LEFT", -3, 0 }, { "BOTTOM", "TOP", 0, 2 }, { "TOP", "BOTTOM", 0, -2 },
    { "BOTTOMLEFT", "TOPRIGHT", 1, 0 }, { "TOPLEFT", "BOTTOMRIGHT", 1, 0 },
    { "BOTTOMRIGHT", "TOPLEFT", -1, 0 }, { "TOPRIGHT", "BOTTOMLEFT", -1, 0 },
}
-- Further out, when there's no room right by the point ("it gets to be a lot
-- with numbers and dots and paths: can the text float out a little further",
-- 0.35.204): the same eight places one and two steps away. A label out
-- there gets a thin line back to its point.
M.LABEL_NEAR = #CANDS
M.LABEL_STEP = 13
M.LABEL_PAD = 2      -- room kept between a label and anything else
for ring = 1, 2 do
    local g = M.LABEL_STEP * ring
    local d = math.floor(g * 0.7 + 0.5)
    for k = 1, M.LABEL_NEAR do
        local a = CANDS[k]
        local dx = a[2]:find("RIGHT") and 1 or (a[2]:find("LEFT") and -1 or 0)
        local dy = a[2]:find("TOP") and 1 or (a[2]:find("BOTTOM") and -1 or 0)
        local step = (dx ~= 0 and dy ~= 0) and d or g
        CANDS[#CANDS + 1] = { a[1], a[2], a[3] + dx * step, a[4] + dy * step }
    end
end
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
-- Pure: the place for one label. cx, cy, s: its point and half size; sizes:
-- { { w, h }, ... } for its texts, longest first; boxes: what's taken
-- ({ l, b, r, t } each); own: the index in boxes of its own point (never in
-- the way: every place stands clear of it). The nearest place that touches
-- nothing, the label's box grown by `pad` on every side; none: the one that
-- covers least. -> place (index into the candidates), text index, overlap.
function M.PickLabel(cx, cy, s, sizes, boxes, own, pad)
    pad = pad or M.LABEL_PAD
    local bestK, bestText, bestHit
    for ti, size in ipairs(sizes) do
        for k = 1, #CANDS do
            local l, b, r, t = M.LabelBox(k, cx, cy, s, size[1], size[2])
            local hit = 0
            for i, o in ipairs(boxes) do
                if i ~= own then hit = hit + overlap(l - pad, b - pad, r + pad, t + pad, o[1], o[2], o[3], o[4]) end
            end
            if not bestHit or hit < bestHit then bestK, bestText, bestHit = k, ti, hit end
            if hit == 0 then break end
        end
        if bestHit == 0 then break end
    end
    return bestK, bestText, bestHit
end

local function declutter()
    local list, boxes = {}, {}
    for i = 1, nPins do
        local p = pins[i]
        local cx, cy = p:GetCenter()
        if p.leader then p.leader:Hide() end
        if cx and p.full and p.full ~= "" then
            boxes[#boxes + 1] = { cx - p:GetWidth() / 2, cy - p:GetHeight() / 2, cx + p:GetWidth() / 2, cy + p:GetHeight() / 2 }
            list[#list + 1] = { p = p, cx = cx, cy = cy, s = p:GetWidth() / 2, own = #boxes }
        end
    end
    table.sort(list, function(a, b)
        if a.p.top ~= b.p.top then return a.p.top end
        if a.p.isTarget ~= b.p.isTarget then return a.p.isTarget end
        return (a.p.order or 0) < (b.p.order or 0)
    end)
    for _, e in ipairs(list) do
        local p = e.p
        local texts, sizes = { p.full, p.short }, {}
        for i, text in ipairs(texts) do
            p.text:SetText(text)
            sizes[i] = { p.text:GetStringWidth() + 2, p.text:GetStringHeight() + 1 }
        end
        local k, ti = M.PickLabel(e.cx, e.cy, e.s, sizes, boxes, e.own)
        p.text:SetText(texts[ti])
        local a = CANDS[k]
        p.text:ClearAllPoints()
        p.text:SetPoint(a[1], p, a[2], a[3], a[4])
        local l, b, r, t = M.LabelBox(k, e.cx, e.cy, e.s, sizes[ti][1], sizes[ti][2])
        boxes[#boxes + 1] = { l, b, r, t }
        -- Moved away from its point: a thin line back to it.
        if k > M.LABEL_NEAR then
            if not p.leader then
                p.leader = p:CreateLine(nil, "ARTWORK")
                p.leader:SetThickness(1)
                p.leader:SetColorTexture(1, 1, 1, 0.45)
            end
            p.leader:SetStartPoint("CENTER", p, 0, 0)
            p.leader:SetEndPoint(a[1], p.text, 0, 0)
            p.leader:Show()
        end
    end
end

-- Pure: does the map show only your own waypoint? has: one is set; on: the
-- setting; pointing: you point at a step (in a list, on the tracker, a preview).
function M.WaypointOnly(has, on, pointing)
    return (has and on and not pointing) and true or false
end

-- One step alone ("as I hover over the waypoints in the Flow Router, hide
-- all the other things and routes and show just that one objective; leave
-- the previous and the next, without their area, a little muted, so I see
-- the flow to it", 0.35.204).
M.SOLO_FADE = 0.5
-- Pure: where in the plan the step you point at is (nil: not on the route).
function M.SoloAt(plan, key)
    if not key then return nil end
    for i, s in ipairs(plan or {}) do
        if s.goal and s.goal.key == key then return i end
    end
    return nil
end
-- Pure: the steps shown with it: itself, alone (0.35.289: "I don't want to
-- see the from and to when I hover an item in the Flow Router, just that one
-- item and its areas". It showed the step before and after, muted, with the
-- lines between.)
function M.SoloStops(n, at)
    if at and at >= 1 and at <= (n or 0) then return { at } end
    return {}
end
local function drawSolo(c, mapID, plan, at, T)
    local labels = ns.nav:PlanLabels(plan)
    local pts = {}
    for _, j in ipairs(M.SoloStops(#plan, at)) do
        local s = plan[j]
        if not M.FollowsYou(s) then
            local x, y = toMap(s.point, mapID)
            if x then pts[#pts + 1] = { j = j, x = x, y = y, s = s } end
        end
    end
    -- (No lines: the step alone, with its areas.)
    for _, e in ipairs(pts) do
        local kind = ns.theme.kinds[ns.nav:StopKind(e.s.goal)]
        local icon = kind and string.format("|T%s:12:12|t", kind.icon) or ""
        if e.j == at then
            pin(c, e.x, e.y, icon .. labels[e.j], T.hover, e.s, true)
            pins[nPins].order = 0
        else
            pin(c, e.x, e.y, icon .. labels[e.j], T.route, e.s)
            pins[nPins].order = e.j
            pins[nPins]:SetAlpha(M.SOLO_FADE)
        end
    end
end
-- Pure: how much lower the Router's rows start when its title wraps: the
-- height past one line, and a little room under it.
M.TITLE_LINE, M.TITLE_PAD = 13, 4
function M.TitleExtra(height, line)
    line = line or M.TITLE_LINE
    if type(height) ~= "number" or height <= line * 1.4 then return 0 end
    return math.ceil(height - line) + M.TITLE_PAD
end

-- Draws one route as a dotted trail through round points, starting at you.
-- Steps on another map are skipped, and the trail joins the ones on this
-- map. Each point's label carries the step's type icon and number.
-- A "make it where you stand" step (crafting with no station): it follows
-- you, so the world map gives it no pin, area or line.
function M.FollowsYou(s) return (s and s.goal and s.goal.anywhere) and true or false end
-- The dotted path follows the way you'd really walk (0.35.172): the leg from
-- you along the trail the arrow follows, and any leg into another region
-- (up Thunder Bluff, into the next zone) through the gate (N.LegVia). Pure:
-- the points one leg is drawn through on this map, start and end included.
--   mids: world points between the ends (or nil); place(pt) -> x, y on the
--   map shown, or nil when it isn't on it.
function M.LegChain(sx, sy, ex, ey, mids, place)
    local chain = { { sx, sy } }
    for _, m in ipairs(mids or {}) do
        local mx, my = place(m)
        if mx then chain[#chain + 1] = { mx, my } end
    end
    chain[#chain + 1] = { ex, ey }
    return chain
end

-- Your next step is on another map than the one shown (0.35.245: "currently
-- there is nothing if the next step is in a different zone"): the line still
-- starts at you and goes the way you'd walk, through the gate when it's on
-- this map, and stops at the map's edge. Looking at the step's own map, it
-- comes in from the edge (or the gate) to the step. Pure:
--   where a line from a spot on the map (ix, iy) to one beside it leaves it.
function M.ClipToMap(ix, iy, ox, oy)
    local t = 1
    local dx, dy = ox - ix, oy - iy
    if ox > 1 then t = math.min(t, (1 - ix) / dx) elseif ox < 0 then t = math.min(t, (0 - ix) / dx) end
    if oy > 1 then t = math.min(t, (1 - iy) / dy) elseif oy < 0 then t = math.min(t, (0 - iy) / dy) end
    return ix + dx * t, iy + dy * t
end
local function onMap(p) return p[1] >= 0 and p[1] <= 1 and p[2] >= 0 and p[2] <= 1 end
--   the stretches of a leg through pts ({ x, y } each, on the map or beside
--   it) that are on the map, in walking order: { x1, y1, x2, y2, from = k }.
--   A stretch between two points that are both off the map isn't drawn.
function M.LegParts(pts)
    local out = {}
    for k = 1, #pts - 1 do
        local a, b = pts[k], pts[k + 1]
        local ain, bin = onMap(a), onMap(b)
        if ain and bin then
            out[#out + 1] = { a[1], a[2], b[1], b[2], from = k }
        elseif ain then
            local cx, cy = M.ClipToMap(a[1], a[2], b[1], b[2])
            out[#out + 1] = { a[1], a[2], cx, cy, from = k }
        elseif bin then
            local cx, cy = M.ClipToMap(b[1], b[2], a[1], a[2])
            out[#out + 1] = { cx, cy, b[1], b[2], from = k }
        end
    end
    return out
end
--   does the leg to your next step cross the map's edge? (You on it and the
--   step not, or the step on it and you not.)
function M.CrossesEdge(youOn, stopOn) return (youOn and true or false) ~= (stopOn and true or false) end

local function drawRoute(c, mapID, plan, color, withPins, alpha, pinsOnly)
    if not plan then return end
    local you = ns.nav:PlayerPos()
    local px, py = toMap(you, mapID)
    local labels = ns.nav:PlanLabels(plan)
    local hovered
    local fromYou = px ~= nil   -- the next line drawn starts at you
    local broken = false        -- a hidden step since the last one drawn
    local prevPt = fromYou and you or nil   -- where the leg being drawn starts, in the world
    local function place(m) return toMap(m, mapID) end
    for i, s in ipairs(plan) do
        -- A "make it where you stand" step follows you: its spot is wherever you
        -- stood when the route was planned, so it gets no pin (it sat on your
        -- character, or where you used to be). It's listed, not placed.
        local x, y
        if not M.FollowsYou(s) then x, y = toMap(s.point, mapID) end
        -- Your next step, on another map than you: the part of the way that's on this one.
        if i == 1 and alpha == nil and not pinsOnly and you and not M.FollowsYou(s)
            and s.point and s.point.cont == you.cont and M.CrossesEdge(px, x) and ns.nav:StopVisible(i, false) then
            local pts = {}
            local function add(pt)
                local rx, ry = toMapRaw(pt, mapID)
                if rx then pts[#pts + 1] = { rx, ry } end
            end
            add(you)
            local okV, list = pcall(ns.nav.LegVia, you, s.point, true)
            for _, m in ipairs(okV and list or {}) do add(m) end
            add(s.point)
            for _, part in ipairs(M.LegParts(pts)) do
                legs[#legs + 1] = { part[1], part[2], part[3], part[4],
                                    color = theme().route, live = M.LegLive(true, nil), alpha = FIRST_ALPHA }
                if px and part.from == 1 then addLink(links, nil, legs[#legs]) end
            end
            -- (No line from you to a later step on this map: you aren't going there next.)
            px, fromYou, prevPt = nil, false, nil
        end
        local pointed = s.goal.key == hoverKey or (focusKey and s.goal.key == focusKey and GetTime() < focusUntil)
        -- Steps on the map: past your limit only the step you point at shows (a pin, no line).
        local beyond = not ns.nav:StopVisible(i, false)
        -- A step that isn't shown breaks the trail: no line from step 2 to
        -- step 5 when 3 and 4 come between (the route doesn't go that way).
        if x and beyond then broken = true end
        if x and (not beyond or (pointed and withPins)) then
            if broken and not beyond then px = nil end   -- (a new stretch starts here)
            if px and not pinsOnly and not beyond then
                -- From you to the first step: the arrow's colour and stronger,
                -- so it's clear where to go now; the rest fainter. (A preview,
                -- alpha given, keeps its own colour.)
                local first = (i == 1)
                local col = first and alpha == nil and theme().route or color
                local live, la = M.LegLive(first, alpha), (first and FIRST_ALPHA or REST_ALPHA) * (alpha or 1)
                -- (A preview keeps straight lines: it's a sketch of another order.)
                local mids
                if alpha == nil and prevPt and ns.nav.LegVia then
                    local ok, list = pcall(ns.nav.LegVia, prevPt, s.point, first and fromYou)
                    mids = ok and list or nil
                end
                local chain = M.LegChain(px, py, x, y, mids, place)
                for k = 1, #chain - 1 do
                    legs[#legs + 1] = { chain[k][1], chain[k][2], chain[k + 1][1], chain[k + 1][2],
                                        color = col, live = live, alpha = la }
                    -- Only the stretch that starts at you follows you between redraws.
                    if fromYou and k == 1 then addLink(links, nil, legs[#legs]) end
                end
            end
            fromYou = false
            px, py = x, y
            prevPt = s.point
            if not beyond then broken = false end
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
    -- The step you're pointing at (here or in the list) goes on top of everything.
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
        GameTooltip:AddLine("Not a step on the route: the arrow points here in green until you get there.", 1, 1, 1, true)
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

-- The profession route (the faint arrow's steps, Nav N.profPlan): a dotted
-- path from you through its next steps and a pin on the first, in the
-- profession arrow's colour (plain smoked glass: no outline, no centre).
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
        GameTooltip:AddLine("Profession: " .. (self.label or "next step"))
        GameTooltip:AddLine("Where the faint profession arrow points. The dotted path is your next profession steps.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    p:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return p
end
-- Profession steps worth a line on the map: not "do it where you stand".
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
    profPin.dot:Hide()
    local g = first[3] or {}
    profPin.label = g.text or g.title
    profPin.text:SetText("|cff" .. ns.theme.muted.hex .. (profPin.label or "Profession") .. "|r")   -- (the theme's muted grey)
    local sc = profPin:GetScale()
    profPin:ClearAllPoints()
    profPin:SetPoint("CENTER", c, "TOPLEFT", first[1] * c:GetWidth() / sc, -first[2] * c:GetHeight() / sc)
    profPin:Show()
end
M.ProfPin = function() return profPin end   -- (tests)

-- A prepared dungeon run's steps on another continent: the route plans only
-- the one you're on, so they get pins of their own on that continent's maps
-- (the Barrens' quest givers while you're in Silverpine), in the route colour.
local function awayStops()
    local p = ns.nav:PlayerPos()
    if not (p and ns.dungeons and ns.dungeons.AwayGoals) then return {} end
    local ok, away = pcall(ns.dungeons.AwayGoals, ns.dungeons, ns.nav:Goals(), p.cont)
    return ok and away or {}
end
M._awayStops = awayStops   -- (tests)

local function drawAway(c, mapID)
    local col = theme().route
    for _, a in ipairs(awayStops()) do
        local g = a.goal
        for _, pt in ipairs(g.points or {}) do
            local x, y = toMap(pt, mapID)
            if x then
                pin(c, x, y, (g.kind == "accept" and g.title) or g.text or g.title or "?", col, { goal = g, point = pt })
                break
            end
        end
    end
end
M.WaypointPin = function() return wpPin end

-------------------------------------------------------------------------------
-- Route panel: the trip plan as a routed quest log, just outside the map on
-- the right (to the right of the quest log), so it never covers the map or
-- the quest log (RouterDock.lua). The Flow Router opens and closes with the
-- square map button; the quest log with the game's own button. Same numbers
-- and colours as the map pins; hover a row to preview, click to choose.
-------------------------------------------------------------------------------

local list
local MAX_ROWS = 26
local ROW_H = 18

local function collapsed() return ns.db.nav.mapListCollapsed == true end

-- Flow never opens or closes the game's quest log panel itself. Doing that
-- (WorldMapFrame:HandleUserActionToggleSidePanel) from add-on code resized
-- the map from Flow's code, which tainted the map's scroll data; in a fight
-- the map's own pins were then blocked ("Button:SetPassThroughButtons()",
-- 0.35.47). The two are separate: Flow's square button sits just above the
-- game's own side-panel button, and each opens and closes its own panel.
function M:SetDrawer(open)
    ns.db.nav.mapListCollapsed = not open
    -- The list opens or closes even when drawing the route on the map fails
    -- ("I'm clicking the button for Flow Router to show the list and it
    -- doesn't pull out", 0.35.315): the failure is noted for the diagnostics.
    local ok, err = pcall(M.Redraw, M)
    if not ok then
        M.NoteError("drawing the map", err)
        if M._UpdateList then
            local ok2, err2 = pcall(M._UpdateList)
            if not ok2 then M.NoteError("the Flow Router's list", err2) end
        end
    end
end

-- Something on the map failed: logged once per message (the map draws twice
-- a second), and counted for the diagnostics' "world map" lines.
M.errors = 0
function M.NoteError(what, err)
    M.errors = M.errors + 1
    local msg = what .. " failed: " .. tostring(err)
    if msg ~= M.lastError then
        M.lastError, M.lastErrorAt = msg, date("%H:%M:%S")
        ns:Log("map", msg)
    end
end

-- Pure: which way the Flow Router button's arrow points: 1 = right (the
-- list is closed: it comes out on the right), -1 = left (open: push it back).
function M.DrawerArrow(open) return open and -1 or 1 end

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
    -- A little route list (three rows, a dot in the route's colour and a
    -- line each) with an arrow beside it that points the way the game's own
    -- quest log button does: right while the list is closed (it comes out on
    -- the right), left while it's open (0.35.315: "the arrow's just the
    -- opposite of the one that's built in").
    b.rows = {}
    for i = 1, 3 do
        local d = b:CreateTexture(nil, "ARTWORK")
        d:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        d:SetSize(5, 5)
        local l = b:CreateLine(nil, "ARTWORK")
        l:SetThickness(1.5)
        b.rows[i] = { dot = d, line = l }
    end
    b.arms = { b:CreateLine(nil, "OVERLAY"), b:CreateLine(nil, "OVERLAY") }
    for _, l in ipairs(b.arms) do l:SetThickness(2) end
    function b:Draw()
        local open = not collapsed()
        local c = theme().route
        local hot = self:IsMouseOver()
        local w, h = self:GetWidth(), self:GetHeight()
        self.bg:SetColorTexture(open and c[1] * 0.25 or 0.05, open and c[2] * 0.25 or 0.05, open and c[3] * 0.25 or 0.08, 0.92)
        for _, t in ipairs(self.edge) do t:SetColorTexture(c[1], c[2], c[3], hot and 1 or 0.75) end
        for i, r in ipairs(self.rows) do
            local y = (2 - i) * h * 0.22
            r.dot:ClearAllPoints()
            r.dot:SetPoint("CENTER", self, "CENTER", -w * 0.24, y)
            r.dot:SetVertexColor(c[1], c[2], c[3], 1)
            r.line:SetStartPoint("CENTER", self, -w * 0.13, y)
            r.line:SetEndPoint("CENTER", self, w * 0.08, y)
            r.line:SetColorTexture(1, 1, 1, hot and 0.95 or 0.75)
        end
        local dir = M.DrawerArrow(open)
        local s = math.min(w, h) * 0.13
        local cx = w * 0.28
        for i, l in ipairs(self.arms) do
            l:SetStartPoint("CENTER", self, cx - dir * s * 0.6, (i == 1 and 1 or -1) * s)
            l:SetEndPoint("CENTER", self, cx + dir * s * 0.6, 0)
            l:SetColorTexture(hot and 1 or c[1], hot and 1 or c[2], hot and 1 or c[3], 1)
        end
    end
    b:SetScript("OnClick", function() M:SetDrawer(collapsed()) end)
    b:SetScript("OnEnter", function(self)
        self:Draw()
        ns.Tip(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Flow Router")
        GameTooltip:AddLine(collapsed() and "Open Flow's route list (beside the map, right of the quest log)."
            or "Close Flow's route list.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self) self:Draw(); GameTooltip:Hide() end)
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
        local on = M:RouteShown()
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
        M:SetRouteShown(not M:RouteShown())
        self:Draw()
        M:Redraw()
        if GameTooltip:IsOwned(self) then self:GetScript("OnEnter")(self) end
    end)
    r:SetScript("OnEnter", function(self)
        self:Draw()
        ns.Tip(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Flow route on the map: " .. (M:RouteShown() and "shown" or "hidden"))
        GameTooltip:AddLine("Click to " .. (M:RouteShown() and "hide" or "show") .. " it.", 1, 1, 1)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function(self) self:Draw(); GameTooltip:Hide() end)
    r:Draw()
    b.routeToggle = r
    return b
end

-- Beside the map, to the right of the quest log (RouterDock.lua; just right
-- of the map if that file didn't load).
local function place()
    if ns.routerDock and ns.routerDock.Place then ns.routerDock.Place(list) return end
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", WorldMapFrame, "TOPRIGHT", 2, 0)
    list:SetSize(300, math.max(200, WorldMapFrame:GetHeight()))
end

-- The row handle: a ^ chevron ("go here first"), or Flow's (o) target marker
-- on the active step. Also drawn in the help legend, so they look the same.
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
        GameTooltip:AddLine("Not a step on the route: the arrow points here in green, along the green line on the map, until you get there. Then it's back to the route below.", 1, 1, 1, true)
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
    line(-50, nil, "Click a step's name to open it. Right-click to hide it or for more.")
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

    -- Include professions (trainers to learn/raise them, and skill-up steps).
    local pc = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    pc:SetSize(20, 20)
    pc:SetPoint("TOPLEFT", 26, -68)
    pc.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pc.label:SetPoint("LEFT", pc, "RIGHT", 2, 0)
    pc.label:SetText("Include professions")
    pc:SetScript("OnClick", function(self)
        ns.nav:SetKind("professions", self:GetChecked() and true or false)
        M:Redraw()
    end)
    pc:SetScript("OnEnter", function(self)
        ns.Tip(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Trainers for professions you plan or have capped, and fishing / mining stops when a skill is behind your level.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    pc:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.profs = pc

    -- Show hidden steps (greyed out at the end of the list; click to unhide).
    local hc = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    hc:SetSize(20, 20)
    hc:SetPoint("TOPLEFT", 170, -92)
    hc.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hc.label:SetPoint("LEFT", hc, "RIGHT", 2, 0)
    hc.label:SetText("Show hidden steps")
    hc:SetScript("OnClick", function(self)
        ns.db.nav.showHidden = self:GetChecked() and true or false
        M:Redraw()
    end)
    hc:SetScript("OnEnter", function(self)
        ns.Tip(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Right-click any step (here or on the map) to hide it. Tick this to see hidden ones and click one to bring it back.", 1, 1, 1, true)
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
    rc:SetScript("OnClick", function(self) M:SetRouteShown(self:GetChecked() and true or false); M:Redraw() end)
    f.showLines = rc
    hc:Hide(); hc.label:Hide()  -- hidden steps are always listed now

    -- One dropdown for the route instead of the checkboxes above (which
    -- couldn't reach Completionist, and had professions as an odd sub-box):
    -- "Route: Optimal, professions on" opens the same list as the arrow's
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
        GameTooltip:AddLine("Tick what the route includes (current quests, new quests, training, professions...), send the arrow to the nearest repairer or vendor, and pick the order.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    dd:SetScript("OnLeave", function() GameTooltip:Hide() end)
    function dd:Update()
        -- What the route includes (the menu's ticks), in a few words; or
        -- the dungeon run, while "Only the dungeon run" is on (Dungeons.lua).
        local N = ns.nav
        local what = N.KindsSummary(function(k) return N:Includes(k) end)
        local D = ns.dungeons
        if D and D.RunOnly and D:RunOnly() then
            what = "Dungeon run: " .. ((ns.db.nav.dungeonRun and ns.db.nav.dungeonRun.name) or "?")
        end
        self.text:SetText("|cffffd200Route:|r " .. what)
    end
    f.routeDrop = dd

    -- Route state (XpValue.lua): one row of radios, each in its route colour.
    -- Custom route (orange) is on while you've picked the next step yourself
    -- (a ^ in the list below); Most XP or Shortest puts you back on an
    -- optimised route.
    f.sorts = {}
    local SORTS = {
        { "distance", "Shortest", 6, "A short route by travel time (default), XP ignored. A quick plan over your nearest steps, not a guaranteed shortest." },
        { "xp", "Most XP", 92, "XP-weighted: a short route, but quests are weighed by XP and level. More XP is worth a longer walk; quests 3+ levels above you wait. Not a guaranteed most-XP order." },
        { "custom", "Custom route", 172, "On when you pick the next step yourself (its ^ below): the route goes there first and is orange, not optimised, until you choose Most XP or Shortest again (your lines wait; click this to bring them back). Greyed out while you're on one of those with none waiting." },
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
    -- above the route, not a step in it. The arrow follows it (orange) until
    -- you get there or clear it; the route below carries on as it was.
    f.wp = M.MakeWaypointRow(f)

    -- Each row: [^] handle, then the step.
    --   ^ handle    go here first: the route is re-planned from this step,
    --               which moves to the top and gets the (o); hovering it
    --               previews that route
    --   (o)         the step you're heading to, always the top row
    --   row hover   the step's details (quest objectives and text)
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
                    or "The next step on your route.", 1, 1, 1, true)
            else
                M:Preview(row.key)
                GameTooltip:AddLine("Go here next")
                GameTooltip:AddLine("Makes it your next step: a Custom route (orange) until you choose Most XP or Shortest again. The orange line on the map is that route.", 1, 1, 1, true)
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
        r.leg:SetWordWrap(false)   -- (a long reason is cut with "...", never spilled out of the Router)
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
            if not (self.isHidden or self.blocked) then hoverKey, hoverSolo = self.key, true; M:Redraw() end
        end)
        r:SetScript("OnLeave", function()
            GameTooltip:Hide()
            ns.nav:ClickCursor(false)
            if hoverKey then hoverKey, hoverSolo = nil, false; M:Redraw() end
        end)
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        r:SetScript("OnClick", function(self, button)
            M:Preview(nil)
            local g = self.blocked or self.goal
            if self.isHidden then
                ns.nav:Unhide(self.key)        -- either click brings it back
            elseif button == "RightButton" and g then
                local items = {
                    { title = true, text = g.text or g.title or "This step" },
                    { text = "Open it", func = function() ns.nav:OpenStop(g, self) end },
                    -- (A step across the sea can't be walked to, but its zeppelin or boat can: Crossings.lua.)
                    { text = "Go here next (Custom route: only its quest line)",
                      disabled = self.blocked ~= nil and not (ns.crossings and ns.crossings.CanLead(g)),
                      func = function()
                          if ns.crossings and ns.crossings.CanLead(g) then ns.crossings.Lead(g) else ns.nav:Select(g.key) end
                      end },
                    { text = "Point the arrow here (your waypoint)", func = function() M.PointHere(g) end },
                    { text = "Hide this step", func = function() ns.nav:Hide(g.key) end },
                }
                for _, it in ipairs(ns.focus and ns.focus.MenuItems(g) or {}) do items[#items + 1] = it end
                items[#items + 1] = { sep = true }
                for _, it in ipairs(ns.menu:RouteItems()) do items[#items + 1] = it end
                ns.menu:Open(items)
            elseif self.blocked then
                ns:Print((g.text or "that step") .. ": " .. (g.blockedBy or "blocked"))
            elseif g then
                ns.nav:OpenStop(g, self)
            end
            M:Redraw()
        end)
        f.rows[i] = r
    end
    return f
end

-- A locked step's reason in the Router's list: as wide as its words, never
-- wider than its column (the step's name gets the rest of the 300).
M.REASON_W = 130
function M.ReasonWidth(textWidth) return math.min((textWidth or 0) + 2, M.REASON_W) end
-- (Tests) the rows of the Router's list, once it's built.
function M._ListRows() return list and list.rows end

local function updateList()
    list = list or buildList()
    -- (Before anything else can fail: the list opens or closes.)
    if collapsed() or not ns.nav:PlayerPos() then list:Hide() end
    button = button or buildButton()
    button:Draw()
    if button.routeToggle then button.routeToggle:Draw() end
    local plan = ns.nav.plan
    -- Keep the panel up even with an empty route, so the mode can be switched back.
    plan = plan or {}
    if not ns.nav:PlayerPos() then list:Hide() return end
    if collapsed() then list:Hide() return end
    local okP, errP = pcall(place)
    if not okP then M.NoteError("placing the Flow Router", errP) end
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
            -- picking a step (its ^), not here. (Its tooltip still says how.)
            -- Not while your lines wait from before: a click brings them back.
            local focus = ns.db.nav.focus
            local waiting = type(focus) == "table" and #focus > 0
            rb:SetEnabled(on or waiting)
            rb.label:SetText((on or waiting) and ns.theme:ModeText("custom", "Custom route") or "|cff777777Custom route|r")
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
    list.title:SetText(string.format("%s: %d steps, about %d yd%s%s",
        following and "Party route" or (ns.xpValue:IsCustom() and ns.theme:ModeText("custom", "Custom route")) or "Your route",
        #plan, plan[#plan] and plan[#plan].cum or 0,
        nBlocked > 0 and string.format("  |cffff7070(%d blocked, listed below)|r", nBlocked) or "",
        ns.nav.zoneNote and ("  |cff888888" .. ns.nav.zoneNote .. "|r") or ""))
    if #plan == 0 then list.title:SetText("Nothing on this route right now. Try Route: Optimal (above).") end
    -- The title can take two lines ("... (4 blocked, listed below)  Finish the
    -- Barrens first"): the rows start under it, with a little room (0.35.279:
    -- "it runs into the first line under it").
    local extra = M.TitleExtra(list.title:GetStringHeight(), M.TITLE_LINE)
    if extra > 0 then
        for i = 1, MAX_ROWS do
            local r = list.rows[i]
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 8, top - extra - (i - 1) * ROW_H)
            r:SetPoint("TOPRIGHT", -8, top - extra - (i - 1) * ROW_H)
        end
    end
    local labels = ns.nav:PlanLabels(plan)
    local fit = math.min(MAX_ROWS, math.floor((list:GetHeight() - 108 - extra - (wpShown and ROW_H or 0)) / ROW_H))
    -- Route steps first, then blocked steps (lock + reason), then (if
    -- ticked) hidden steps, greyed out.
    local blocked = ns.nav.blockedGoals or {}
    local hiddenGoals = ns.nav.hiddenGoals or {}  -- always listed, greyed out
    -- One list of rows: route steps, then blocked, then hidden. Blocked and
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
    -- A dungeon run's steps on another continent (not on the route): where they are.
    local away = awayStops()
    for _, a in ipairs(away) do entries[#entries + 1] = { away = a } end
    if #plan == 0 and #away > 0 then
        local to = away[1].cont
        list.title:SetText(string.format("Nothing on this continent. %s",
            ns.dungeons.TravelHint(to, UnitFactionGroup("player")) or ""))
    end
    for _, h in ipairs(hiddenGoals) do entries[#entries + 1] = { hidden = h } end
    for i = 1, MAX_ROWS do
        local r, e = list.rows[i], entries[i]
        if e and i <= fit and e.stop then
            local s = e.stop
            r.key, r.isHidden, r.blocked = s.goal.key, false, nil
            r.goal = s.goal
            -- The (o) is always the top row: the step you're heading to. A
            -- step you moved first IS the top row, so it needs no other mark.
            r.go.active = (e.i == 1)
            r.go:Paint(r.go:IsMouseOver())
            r.go:Show()
            r.text:SetText(ns.nav:FormatStop(e.i, s.goal, labels[e.i]))
            r.leg:SetWidth(0)
            r.leg:SetText(string.format("+%d yd", s.trip or s.leg or 0))
            r:Show()
        elseif e and i <= fit and e.blocked then
            local b = e.blocked
            r.key, r.isHidden, r.blocked, r.goal = b.key, false, b, b
            r.go:Hide()
            local text, why = ns.nav:FormatBlocked(b)
            r.text:SetText(text)
            -- (Never wider than the row has room for: the rest is in its tooltip.)
            r.leg:SetWidth(0)
            r.leg:SetText(why)
            r.leg:SetWidth(M.ReasonWidth(r.leg.GetUnboundedStringWidth and r.leg:GetUnboundedStringWidth() or r.leg:GetStringWidth()))
            r:Show()
        elseif e and i <= fit and e.away then
            local g = e.away.goal
            r.key, r.isHidden, r.blocked, r.goal = g.key, false, nil, g
            r.go:Hide()
            r.text:SetText("|cff9a9a9a" .. (g.text or g.title or "?") .. "|r")
            r.leg:SetWidth(0)
            r.leg:SetText("|cffffd200" .. (ns.dungeons.CONTINENTS[e.away.cont] or "other continent") .. "|r")
            r:Show()
        elseif e and i <= fit and e.hidden then
            local h = e.hidden
            r.key, r.isHidden, r.blocked, r.goal = h.key, true, nil, h
            r.go:Hide()
            r.text:SetText("|cff777777(hidden) " .. (h.text or h.title or "?") .. "|r")
            r.leg:SetWidth(0)
            r.leg:SetText("|cff777777click to show|r")
            r:Show()
        else
            r:Hide()
        end
    end
end
M._updateList = function() updateList() end   -- (tests)

-- Pointing at a step somewhere else (a row of the Flow Tracker): the map,
-- when it's open, lights that step the way pointing at it in the Flow Router
-- does. nil: none.
function M.Hover(key)
    if hoverKey == key then return end
    hoverKey, hoverSolo = key, key ~= nil
    if WorldMapFrame and WorldMapFrame:IsShown() then pcall(M.Redraw, M) end
end
function M._HoverKey() return hoverKey end

-- The step you point at: under the mouse, opened from the tracker, or previewed.
local function pointedKey()
    return hoverKey or (focusKey and GetTime() < focusUntil and focusKey) or previewKey or nil
end

-- What the map drawing depends on, apart from where you stand: the map and
-- its zoom, the route (each step, its spot, its text and how many spawns it
-- has), the step you point at, the route colour, your waypoint and whether
-- you're on this map. The route's tables are made again every few seconds
-- with the same steps in them, so this compares what's in them, not which
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
    -- (A dungeon run's pins on another continent: drawAway.)
    d = setv(st, "run", (ns.dungeons and ns.dungeons:Prepared()) or false) or d
    d = setv(st, "runOnly", ns.db.nav.dungeonOnly == true) or d
    d = setv(st, "here", (mapID and toMap(p, mapID)) ~= nil) or d
    -- The arrow's way changed (a trail point passed, a gate reached): the path is drawn again.
    d = setv(st, "path", (ns.nav.PathStamp and ns.nav.PathStamp()) or false) or d
    local plan = ns.nav.plan or EMPTY
    local sp = st.plan or {}
    st.plan = sp
    d = setv(st, "stops", #plan) or d
    d = setv(st, "limit", (ns.nav:AreaMode() and "area") or ns.nav:StopsShown() or false) or d   -- Steps on the map changed
    for i, s in ipairs(plan) do
        local g, pt, b = s.goal, s.point or EMPTY, (i - 1) * 6
        local key, text, n = g.key, g.text or g.title or false, g.points and #g.points or 0
        local m, x, y = pt.map or false, pt.x or pt.wx or false, pt.y or pt.wy or false
        if sp[b + 1] ~= key or sp[b + 2] ~= m or sp[b + 3] ~= x or sp[b + 4] ~= y or sp[b + 5] ~= n or sp[b + 6] ~= text then
            sp[b + 1], sp[b + 2], sp[b + 3], sp[b + 4], sp[b + 5], sp[b + 6] = key, m, x, y, n, text
            d = true
        end
    end
    -- The faint profession arrow's step (its pin and path): redraw when it
    -- moves on too, not only when the main route does.
    local pc = ns.nav.profChoice
    local ppt = pc and pc.point or EMPTY
    d = setv(st, "profKey", pc and pc.goal and pc.goal.key or false) or d
    d = setv(st, "profX", ppt.x or ppt.wx or false) or d
    d = setv(st, "profY", ppt.y or ppt.wy or false) or d
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
    pcall(M.Banner, WorldMapFrame:GetMapID())
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
        -- Every area step gets its own bordered patch: faint, the next step
        -- stronger, the one you point at in the hover colour. Drawn last = on top.
        local order = {}
        for i = #plan, 2, -1 do if plan[i].goal.key ~= pointed then order[#order + 1] = i end end
        if plan[1] and plan[1].goal.key ~= pointed then order[#order + 1] = 1 end
        for i, s in ipairs(plan) do if s.goal.key == pointed then order[#order + 1] = i end end
        local soloAt = M.SoloAt(plan, hoverSolo and not previewKey and hoverKey or nil)
        -- Your own waypoint is set: the map shows it alone, without Flow's route
        -- ("it gets super confusing ... should we hide Flow's objectives when
        -- one is selected? we are showing so much", 0.35.210). Pointing at a
        -- step in a list still shows that step.
        local wayOnly = M.WaypointOnly(ns.waypoint ~= nil and ns.waypoint:Get() ~= nil, ns.db.nav.mapWaypointOnly ~= false,
            pointed ~= nil)
        for _, i in ipairs(order) do
            local g = plan[i].goal
            -- Only the patch the route goes to; the step you point at shows
            -- every place its mobs live. Past your Steps on the map limit,
            -- only the step you point at.
            if M.FollowsYou(plan[i]) or wayOnly then   -- (follows you: nowhere to draw; or only your waypoint shows)
            elseif soloAt and i ~= soloAt then   -- (one step alone: only its area)
            elseif g.key == pointed then drawArea(c, mapID, g, T.hover, true, labels[i], plan[i].point, true)
            elseif ns.nav:StopVisible(i, false) then
                -- Your next step (the arrow's): every place its mobs live, as on
                -- the minimap; later steps: the patch the route goes to.
                drawArea(c, mapID, g, T.route, i == 1, labels[i], plan[i].point, i == 1)
            end
        end
        if wayOnly then
            drawWaypoint(c, mapID)
            if profPin then profPin:Hide() end
        elseif previewKey then
            -- Only the route you'd follow, all in one colour: its lines, and the
            -- steps as points (kept where they are so the one under the mouse
            -- doesn't jump).
            drawRoute(c, mapID, ns.nav.plan, T.proposed, true, 0.95, true)
            drawRoute(c, mapID, ns.nav:PlanFor(previewKey), T.proposed, false, 0.95)
        elseif soloAt then
            drawSolo(c, mapID, plan, soloAt, T)
        else
            drawRoute(c, mapID, ns.nav.plan, T.route, true)
        end
        if wayOnly then   -- (drawn above)
        elseif soloAt then
            if wpPin then wpPin:Hide() end
            if profPin then profPin:Hide() end
        else
            drawAway(c, mapID)
            drawProf(c, mapID)
            drawWaypoint(c, mapID)
        end
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
    -- The arrow's colour changed (orange to green as you close in): the step's
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

-- Highlight one step for a few seconds (opened from the tracker or arrow menu).
-- "Show on map" for a step in another zone (0.35.289: "it should open the
-- right zone too"). Flow can't turn the game's map to another zone: doing
-- that from an add-on taints the map, and in a later fight its buttons are
-- blocked (0.35.47), which is why Flow never touches it. So it says where
-- the step is, across the top of the map, for as long as it's highlighted:
-- "This step is in The Barrens: right-click the map to zoom out, then click
-- The Barrens." Pure: the words, or nil when the step is on the map shown.
function M.ElsewhereText(zone, onThisMap)
    if onThisMap then return nil end
    if not zone then return "This step isn't on this map: right-click the map to zoom out and find it." end
    return string.format("This step is in %s: click \"Show on map\" again (or right-click the map) to zoom out, then click %s.", zone, zone)
end
-- The step with this key and its zone's name, from the route and what Flow can't place.
local function stepOf(key)
    if not key then return nil end
    for _, s in ipairs(ns.nav.plan or {}) do
        if s.goal and s.goal.key == key then return s.point or (s.goal.points and s.goal.points[1]) end
    end
    return nil
end
function M.Banner(mapID)
    local key = (focusKey and GetTime() < focusUntil and focusKey) or nil
    local pt = stepOf(key)
    local text
    if pt then
        local x = toMap(pt, mapID)
        local zone = pt.map and ns.nav.ZoneOf and ns.nav.ZoneOf(pt.map)
        local info = zone and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(zone)
        text = M.ElsewhereText(info and info.name or nil, x ~= nil)
    end
    if not text then
        if M.banner then M.banner:Hide() end
        return nil
    end
    if not M.banner then
        local b = CreateFrame("Frame", nil, WorldMapFrame.ScrollContainer or WorldMapFrame)
        b:SetPoint("TOP", 0, -10)
        b:SetSize(520, 22)
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetAllPoints()
        b.bg:SetColorTexture(0, 0, 0, 0.75)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        b.text:SetPoint("CENTER")
        M.banner = b
    end
    M.banner:SetFrameStrata(aboveMap())
    M.banner.text:SetText(text)
    M.banner:SetWidth(M.banner.text:GetStringWidth() + 24)
    M.banner:Show()
    return text
end

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

ns:OnLoad(function()
    local acc, open = 0, false
    local driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < ((ns.Lite and ns.Lite()) and 2 or 0.5) then return end   -- lite: every 2 s
        acc = 0
        if WorldMapFrame and WorldMapFrame:IsShown() then
            -- Just opened: draw it all; open: keep up (cheap unless it changed).
            local ok, err
            if open then ok, err = pcall(M.Tick, M) else ok, err = pcall(M.Redraw, M) end
            if not ok then M.NoteError("drawing the map", err) end
            open = true
        else
            if open then pcall(M.StopDots) end   -- (the dots stop drifting while it's closed)
            open = false
        end
    end)
end)

ns.commands.map = function(arg)
    arg = (arg or ""):lower()
    local pct = arg:match("^opacity%s+(%d+)%%?$")
    if pct then
        local v = M:SetPathAlpha(tonumber(pct) / 100)
        ns:Print(string.format("path opacity %d%%", v * 100 + 0.5))
        return
    end
    local move = arg:match("^move%s+(o[nf]f?)$")
    if move then
        ns.db.nav.pathMotion = (move == "on")
        M.PathChanged()
        ns:Print("the path on the map " .. (move == "on" and "moves toward your next steps" or "stands still"))
        return
    end
    if arg == "on" or arg == "off" then
        ns.db.nav.mapRoute = (arg == "on")
        if arg == "on" then M:SetRouteShown(true) end   -- (the route too, if a box had hidden it)
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
        ns:Print("/flow map on|off, /flow map opacity 10-100, /flow map move on|off. Hover a checkpoint to preview, click to choose. Alt-click the map to set a waypoint.")
    end
end

-- Timed for /flow perf (with "keeping up with you" and "route dots").
M.Redraw = ns.perf.Wrap("world map (full redraw)", M.Redraw)

-- For Flow's other layers on the map (MapFlights.lua: flight masters): where
-- a spot falls on the map shown, the map's canvas and zoom, the strata the
-- route is drawn in, and the Flow Router's button (theirs stacks above it).
M.ToMap, M.Canvas, M.CanvasScale, M.AboveMap = toMap, canvas, canvasScale, aboveMap
function M.DrawerButton() return button end
M._UpdateList = updateList

-- The diagnostics' "world map" lines: is the Flow Router open, where, and
-- did drawing fail.
function M.Lines()
    local out = {}
    local open = not collapsed()
    out[#out + 1] = string.format("Flow Router: %s; the list %s; button %s", open and "open" or "closed",
        list and (list:IsShown() and "shown" or "hidden") or "not built yet", button and "built" or "not built yet")
    if list and list:IsShown() then
        local l, b, w, h = list:GetRect()
        local s = list:GetEffectiveScale() / UIParent:GetEffectiveScale()
        out[#out + 1] = string.format("  the list at %s, left %d bottom %d, %d x %d (screen %d x %d)",
            tostring(ns.routerDock and ns.routerDock.lastSpot), (l or 0) * s, (b or 0) * s, (w or 0) * s, (h or 0) * s,
            UIParent:GetWidth(), UIParent:GetHeight())
    end
    out[#out + 1] = string.format("  map drawing failed %d time(s) this session%s", M.errors,
        M.lastError and (": last at " .. tostring(M.lastErrorAt) .. ", " .. M.lastError) or "")
    return out
end
