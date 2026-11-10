local _, ns = ...

-- /flow api height: what this client tells add-ons about up and down, so
-- the arrow can one day say "the stop is upstairs" or "below you". It only
-- reads and prints (the "pin" option also puts the game's own map pin on
-- the stop, so the game's navigation distance can be compared).
--   /flow api height         one report
--   /flow api height pin     the game's map pin on the current stop, then the report
--   /flow api height watch   the navigation line every second for 15 seconds
-- What it compares: the game's navigation distance to its map pin counts
-- height; Flow's own distance is flat (map coordinates). The difference
-- between the two is the height gap.

local H = {}
ns.heightProbe = H

-- The height gap (yards) from a 3D distance and a flat one; nil when the
-- 3D one isn't longer (no height to tell, or the numbers don't fit).
function H.Gap(nav, flat)
    if not (nav and flat) or nav <= flat then return nil end
    return math.sqrt(nav * nav - flat * flat)
end

-- Floors between two maps of one building or cave (the game's floor index):
-- positive = up from `fromMap`, nil when they aren't floors of one place.
function H.FloorStep(members, fromMap, toMap)
    local from, to
    for _, m in ipairs(members or {}) do
        if m.mapID == fromMap then from = m.relativeHeightIndex end
        if m.mapID == toMap then to = m.relativeHeightIndex end
    end
    if from and to then return to - from end
end

-- What a game function returns, as text ("n/a" when the client lacks it).
local function call(fn, ...)
    if type(fn) ~= "function" then return "n/a" end
    local r = { pcall(fn, ...) }
    if not r[1] then return "error" end
    local out = {}
    for i = 2, #r do out[#out + 1] = tostring(r[i]) end
    return #out > 0 and table.concat(out, ", ") or "nil"
end

local function floorsOf(map)
    if not (C_Map and C_Map.GetMapGroupID and C_Map.GetMapGroupMembersInfo and map) then return nil end
    local okG, group = pcall(C_Map.GetMapGroupID, map)
    if not (okG and group) then return nil end
    local okM, members = pcall(C_Map.GetMapGroupMembersInfo, group)
    return okM and members or nil
end

-- The stop the arrow points at now: { map, x, y, wx, wy, title }.
local function currentStop()
    local c = ns.nav and ns.nav.current
    local pt = c and c.point
    if not (pt and pt.map and pt.x and pt.y) then return nil end
    local g = c.goal or {}
    return { map = pt.map, x = pt.x, y = pt.y, wx = pt.wx, wy = pt.wy, title = g.title or g.text or g.key }
end

local function flatYards(p, wx, wy)
    if not (p and wx and wy) then return nil end
    return math.sqrt((wx - p.wx) ^ 2 + (wy - p.wy) ^ 2)
end

-- The game's navigation (to its map pin), against Flow's flat distance.
local function navLine(p)
    local N = C_Navigation
    if not N then return "navigation: no C_Navigation on this client" end
    local okD, nav = pcall(N.GetDistance)
    nav = okD and ns.api.Safe(nav) or nil
    local flat
    local wp = ns.waypoint and ns.waypoint:Get()
    if p and wp and wp.map and ns.nav then
        local cont, wx, wy = ns.nav:ToWorld(wp.map, wp.x, wp.y)
        if cont == p.cont then flat = flatYards(p, wx, wy) end
    end
    local gap = H.Gap(nav, flat)
    local okF, mark = pcall(function()
        local f = N.GetFrame and N.GetFrame()
        if not (f and f:IsShown()) then return "marker not on screen" end
        local fx, fy = f:GetCenter()
        local cx, cy = WorldFrame:GetCenter()
        return string.format("marker %+d, %+d px from the middle", fx - cx, fy - cy)
    end)
    return string.format("navigation: game says %s yd, Flow (flat) %s yd, height gap %s; state %s, clamped %s, on screen %s; %s",
        nav and string.format("%.1f", nav) or "nil", flat and string.format("%.1f", flat) or "nil",
        gap and string.format("%.1f yd", gap) or "none seen",
        call(N.GetTargetState), call(N.WasClampedToScreen), call(N.HasValidScreenPosition),
        okF and mark or "marker: error")
end

-- The report, as lines.
function H.Lines()
    local out = {}
    local p = ns.nav and ns.nav:PlayerPos()
    local map = p and p.map
    local info = map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
    local okP, _, _, z = pcall(UnitPosition, "player")
    out[#out + 1] = string.format("you: map %s (%s, type %s), height %s, indoors %s",
        tostring(map), tostring(info and info.name), tostring(info and info.mapType),
        okP and tostring(ns.api.Safe(z)) or "n/a", tostring(IsIndoors and IsIndoors()))
    local members = floorsOf(map)
    if members then
        local names = {}
        for _, m in ipairs(members) do
            names[#names + 1] = string.format("%s%s (%s)", m.mapID == map and "*" or "", tostring(m.name), tostring(m.relativeHeightIndex))
        end
        out[#out + 1] = "floors here: " .. table.concat(names, ", ")
    else
        out[#out + 1] = "floors here: none (not a building or cave with floors)"
    end
    local stop = currentStop()
    if stop then
        local flat = flatYards(p, stop.wx, stop.wy)
        local step = H.FloorStep(members, map, stop.map)
        out[#out + 1] = string.format("stop: %s on map %s, %s yd flat, floors %s",
            tostring(stop.title), tostring(stop.map), flat and string.format("%.1f", flat) or "?",
            step and string.format("%+d", step) or "n/a")
    else
        out[#out + 1] = "stop: none"
    end
    out[#out + 1] = string.format("super tracking: type %s, map pin %s, map pin tracked %s",
        call(C_SuperTrack and C_SuperTrack.GetHighestPrioritySuperTrackingType),
        call(C_Map and C_Map.HasUserWaypoint),
        call(C_SuperTrack and C_SuperTrack.IsSuperTrackingUserWaypoint))
    out[#out + 1] = navLine(p)
    out[#out + 1] = "Stand below or above a stop, /flow api height pin, then /flow copy and paste it to Claude."
    return out
end

local watchTicker
function H:Run(arg)
    arg = (arg or ""):lower()
    if arg == "pin" then
        local stop = currentStop()
        if not stop then ns:Print("no stop to pin: the arrow isn't pointing anywhere") return end
        if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint) then ns:Print("this client has no game map pin") return end
        local ok = pcall(function()
            C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(stop.map, stop.x, stop.y))
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
        end)
        ns:Print(ok and ("game map pin on " .. tostring(stop.title)) or "couldn't place the game map pin")
    elseif arg == "watch" then
        if watchTicker then watchTicker:Cancel() end
        watchTicker = C_Timer.NewTicker(1, function() ns:Print(navLine(ns.nav and ns.nav:PlayerPos())) end, 15)
        ns:Print("watching the navigation line for 15 seconds: walk up or down")
        return
    end
    ns:Print("heights:")
    for _, l in ipairs(H.Lines()) do ns:Print("  " .. l) end
end
