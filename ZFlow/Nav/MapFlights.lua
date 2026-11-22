local _, ns = ...
-- Z-Flow flight masters on the world map (S31, LEDGER 143), the pure part.
-- Ported from legacy Flow 0.35.314-0.35.328 (Modules/Nav/MapFlights.lua:
-- MF.Pins, MF.TipLines, MF.RoleLabel, MF.WaypointOn, MF.Click, MF.SegDist,
-- MF.LineAt, MF.CanFly, MF.Short, MF.FlightText). Research:
-- WoW/from-zen/RESEARCH-S31.md. Not tested in game.
--
-- What Flow showed: green rings on flight paths you have, light blue on
-- flight masters whose path you lack, your next step's flight joined by a
-- line; a click picks one master and draws where you can fly from it (green
-- you can, red not yet); a line under the mouse says that flight's time; a
-- right click points the arrow at a master (again: clears it).
--
-- PURE PART ONLY. The pins, lines and the on/off button on the world map
-- are not ported here: the button area is Twin's (UI/WindowButtons.lua), and
-- whether frames on the world map canvas stay free of taint needs the client.
-- Advisory only: nothing flies, buys or clicks for the player.
--
-- MF.Pins(known, masters, learned, onRoute, air, same) -> pins
--   known    your flight paths: { [name] = { cont, wx, wy } } (yards in one
--            continent frame)
--   masters  flight masters known of: { name, map, x, y, cont, wx, wy }
--   learned  optional fn(master) -> true when you have that one's path
--   onRoute  optional { [name] = true }: masters that are steps on your route
--   air      optional { from, to }: your next step's flight
--   same     yards: a master this close to a path you have is its master
--   pins = { { name, kind = "have" | "new", cont, wx, wy, map, x, y, npc,
--            role = "from" | "to" | nil, onRoute } }, masters to learn
--            first, then your paths, the flight's two last. A path or master
--            with no place gives no pin (F-086).
-- MF.SETTING  "nav.mapFlights", bool, off by default as in Flow (the lead adds the row)
ns.Nav = ns.Nav or {}
local N = ns.Nav
local MF = {}
N.MapFlights = MF

MF.SAME = 250
MF.LINE_REACH = 14
MF.SETTING = "nav.mapFlights"

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function placed(p)
    return type(p) == "table" and finite(p.wx) and finite(p.wy)
end

local function dist(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

function MF.Pins(known, masters, learned, onRoute, air, same)
    same = finite(same) and same or MF.SAME
    known = type(known) == "table" and known or {}
    masters = type(masters) == "table" and masters or {}
    local out, used = {}, {}
    for name, f in pairs(known) do
        if placed(f) then
            local pin = { name = name, kind = "have", cont = f.cont, wx = f.wx, wy = f.wy }
            local best, bd
            for i, fm in ipairs(masters) do
                if placed(fm) and fm.cont == f.cont then
                    local d = dist(fm.wx, fm.wy, f.wx, f.wy)
                    if d <= same and (not bd or d < bd) then best, bd = i, d end
                end
            end
            if best then
                local fm = masters[best]
                pin.npc, pin.map, pin.x, pin.y = fm.name, fm.map, fm.x, fm.y
            end
            if type(air) == "table" and air.from == name then
                pin.role = "from"
            elseif type(air) == "table" and air.to == name then
                pin.role = "to"
            end
            out[#out + 1] = pin
        end
    end
    -- A master who stands by a flight path you have is its master: not one to learn.
    for _, fm in ipairs(masters) do
        if fm.name and placed(fm) then
            for _, f in pairs(known) do
                if placed(f) and f.cont == fm.cont and dist(fm.wx, fm.wy, f.wx, f.wy) <= same then used[fm.name] = true end
            end
        end
    end
    local seen = {}
    for _, fm in ipairs(masters) do
        local name = fm.name
        local isLearned = false
        if type(learned) == "function" then
            local ok, r = pcall(learned, fm)
            isLearned = ok and r == true
        end
        if name and placed(fm) and not used[name] and not seen[name] and not isLearned then
            seen[name] = true
            out[#out + 1] = { name = name, kind = "new", cont = fm.cont, wx = fm.wx, wy = fm.wy, map = fm.map,
                x = fm.x, y = fm.y, npc = name,
                onRoute = (type(onRoute) == "table" and onRoute[name]) and true or nil }
        end
    end
    local function rank(p) return (p.role and 3) or (p.kind == "have" and 2) or 1 end
    table.sort(out, function(a, b)
        if rank(a) ~= rank(b) then return rank(a) < rank(b) end
        return tostring(a.name) < tostring(b.name)
    end)
    return out
end

-- A pin's tooltip. stepText: your next step; airText: door to door by air ("4 min"; nil: not known).
function MF.TipLines(pin, stepText, airText)
    local lines = {}
    if pin.kind == "have" then
        if pin.npc then lines[#lines + 1] = "Flight master: " .. pin.npc end
        lines[#lines + 1] = "You have this flight path: you can fly here."
        if pin.role == "from" then
            lines[#lines + 1] = "Fly from here: your next step is quicker by air" .. (airText and (", " .. airText .. " in all") or "") .. "."
        elseif pin.role == "to" then
            lines[#lines + 1] = "Land here for your next step" .. (stepText and (": " .. stepText) or "") .. "."
        end
        return pin.name, lines
    end
    lines[#lines + 1] = "Flight master. You don't have this flight path yet: talk to them once (it's free), and later trips through here are shorter."
    if pin.onRoute then lines[#lines + 1] = "It's a step on your route (Flight paths to learn)." end
    return pin.name, lines
end

function MF.RoleLabel(role)
    if role == "from" then return "Fly from here" end
    if role == "to" then return "Land here: next step" end
    return nil
end

-- Is the waypoint the one a right click on this pin set? wp: { map, x, y, note }; spot: { map, x, y }.
function MF.WaypointOn(wp, pin, spot)
    if not (type(wp) == "table" and type(pin) == "table") then return false end
    if wp.note and wp.note == ((pin.npc or pin.name) .. " (flight master)") then return true end
    if type(spot) == "table" and wp.map == spot.map and finite(wp.x) and finite(spot.x) and finite(wp.y) and finite(spot.y) then
        return math.abs(wp.x - spot.x) < 0.005 and math.abs(wp.y - spot.y) < 0.005
    end
    return false
end

-- The selection after a click on a flight master: one pick; any click while one is picked clears it.
function MF.Click(sel, name)
    sel = type(sel) == "table" and sel or {}
    if not name then return sel end
    if not sel.from then return { from = name } end
    return {}
end

-- How far a point is from a stretch of line, in the same units.
function MF.SegDist(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local len2 = dx * dx + dy * dy
    local t = len2 > 0 and ((px - ax) * dx + (py - ay) * dy) / len2 or 0
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    return dist(px, py, ax + t * dx, ay + t * dy)
end

-- The line the mouse is on or near: lines { { name, ax, ay, bx, by } } -> its name, or nil.
function MF.LineAt(lines, px, py, reach)
    local best, bestD
    for _, l in ipairs(type(lines) == "table" and lines or {}) do
        local d = MF.SegDist(px, py, l.ax, l.ay, l.bx, l.by)
        if d <= reach and (not bestD or d < bestD) then best, bestD = l.name, d end
    end
    return best
end

-- Can you fly between two pins? Both are flight paths you have, on one continent.
function MF.CanFly(a, b)
    return (type(a) == "table" and type(b) == "table" and a.kind == "have" and b.kind == "have" and a.cont == b.cont) and true or false
end

-- A flight master's short name ("Crossroads" of "Crossroads, The Barrens").
function MF.Short(name) return (tostring(name or "?"):match("^([^,]+)")) end

-- What a flight between two pins says. flown: seconds the last time you flew it (nil: never);
-- estimate: a guess (nil: none), always labelled "about"; fmt(sec) -> text. -> text, can
function MF.FlightText(a, b, flown, estimate, fmt)
    local route = MF.Short(a.name) .. " to " .. MF.Short(b.name)
    if not MF.CanFly(a, b) then
        if a.cont ~= b.cont then return route .. ": not on one continent", false end
        local need = {}
        if a.kind ~= "have" then need[#need + 1] = a.npc or MF.Short(a.name) end
        if b.kind ~= "have" then need[#need + 1] = b.npc or MF.Short(b.name) end
        return route .. ": you can't fly it yet (learn the flight path at " .. table.concat(need, " and ") .. " first)", false
    end
    fmt = type(fmt) == "function" and fmt or function(s) return math.floor(s + 0.5) .. " s" end
    if finite(flown) then return route .. ": " .. fmt(flown) .. " (your last flight)", true end
    if finite(estimate) then return route .. ": about " .. fmt(estimate), true end
    return route .. ": flight time not known yet", true
end
