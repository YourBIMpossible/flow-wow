local _, ns = ...

-- MapFlights (S31): flight masters on the world map.
--   "have": a flight path you have, so you can fly there;
--   "new":  a flight master whose path you don't have yet (free: talk to
--           them once), the same ones as Nav/FlightPaths.lua's goals;
--   the two of your next step's flight ("from", "to"), drawn last.
-- Click a flight master to see where you can fly from it; the next click
-- clears. Hover one for its name and what it is for.
--
-- This file is the pure rules only, ported from Flow's
-- Modules/Nav/MapFlights.lua (0.35.377, :44-130 and :240-299); see
-- WoW/from-zen/RESEARCH-S31.md. LOOK ONLY: it makes lists and words. It
-- draws nothing, changes nothing on the game's map and takes no flight.
--
-- The drawing is NOT built here: it needs a surface on the world map that
-- the client boundary does not have yet (CLIENT NEED client.mapPins, posted
-- with this item), and the world-map button is another seat's.
--
-- Everything is in world yards, as Flow kept it: { cont, wx, wy }.
--
--   pins = MapFlights.Pins(known, masters, learned, onRoute, air, same)
--     known    your flight paths: { [name] = { cont, wx, wy } }
--              (char "learned.flights.nodes")
--     masters  flight masters known of: { { name, map, x, y, cont, wx, wy } }
--     learned  optional fn(master) -> true when you have that one's path
--              although no flight path of yours stands by them
--     onRoute  optional { [name] = true } for those whose step is on your route
--     air      optional { from, to }: your next step's flight
--     same     yards (MapFlights.SAME): a master this close to a path you
--              have is its master, not one to learn
--     -> { { name, kind = "have" | "new", cont, wx, wy, map, x, y, npc,
--            role = "from" | "to" | nil, onRoute } }, in drawing order:
--        new, then have, then the two with a role; by name inside each
--   title, lines = MapFlights.TipLines(pin, stepText, airText)
--   label        = MapFlights.RoleLabel(role)
--   sel          = MapFlights.Click(sel, name)       { from = name } or {}
--   can          = MapFlights.CanFly(a, b)
--   short        = MapFlights.Short(name)            "Crossroads" of "Crossroads, The Barrens"
--   text, can    = MapFlights.FlightText(a, b, flown, estimate, fmt)
--   d            = MapFlights.SegDist(px, py, ax, ay, bx, by)
--   name         = MapFlights.LineAt(lines, px, py, reach)
--
-- Setting (for the module, when built): "nav.mapFlights", bool, off by
-- default, as Flow's (the map is busy enough until the player asks).

local MF = ns.MapFlights or {}
ns.MapFlights = MF

MF.SETTING = "nav.mapFlights"
MF.SAME = 250           -- yards (Flow: MF.SAME)
MF.LINE_REACH = 14      -- pixels on screen: this near a line is "on it" (Flow: MF.LINE_REACH)

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function dist(ax, ay, bx, by)
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

local function placed(t)
    return type(t) == "table" and finite(t.wx) and finite(t.wy)
end

function MF.Pins(known, masters, learned, onRoute, air, same)
    same = finite(same) and same or MF.SAME
    known = type(known) == "table" and known or {}
    masters = type(masters) == "table" and masters or {}
    local out, used = {}, {}
    for name, f in pairs(known) do
        if placed(f) then
            local pin = { name = name, kind = "have", cont = f.cont, wx = f.wx, wy = f.wy }
            -- Its flight master, when one is known: their name, and their
            -- zone's map for the arrow.
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
    -- A flight master who stands by a flight path you have is its master:
    -- not one to learn.
    for _, fm in ipairs(masters) do
        if placed(fm) and fm.name then
            for _, f in pairs(known) do
                if placed(f) and f.cont == fm.cont and dist(fm.wx, fm.wy, f.wx, f.wy) <= same then
                    used[fm.name] = true
                end
            end
        end
    end
    local seen = {}
    for _, fm in ipairs(masters) do
        local name = type(fm) == "table" and fm.name or nil
        if name and placed(fm) and not used[name] and not seen[name] then
            local has = false
            if type(learned) == "function" then
                local ok, yes = pcall(learned, fm)
                has = ok and yes and true or false
            end
            if not has then
                seen[name] = true
                out[#out + 1] = {
                    name = name, kind = "new", cont = fm.cont, wx = fm.wx, wy = fm.wy,
                    map = fm.map, x = fm.x, y = fm.y, npc = name,
                    onRoute = (type(onRoute) == "table" and onRoute[name]) and true or nil,
                }
            end
        end
    end
    local function rank(p) return (p.role and 3) or (p.kind == "have" and 2) or 1 end
    table.sort(out, function(a, b)
        if rank(a) ~= rank(b) then return rank(a) < rank(b) end
        return tostring(a.name) < tostring(b.name)
    end)
    return out
end

-- A pin's words. stepText: your next step; airText: how long it takes by
-- air, door to door ("4 min"; nil: not known, and then none is claimed).
function MF.TipLines(pin, stepText, airText)
    local lines = {}
    if pin.kind == "have" then
        if pin.npc then lines[#lines + 1] = "Flight master: " .. pin.npc end
        lines[#lines + 1] = "You have this flight path: you can fly here."
        if pin.role == "from" then
            lines[#lines + 1] = "Fly from here: your next step is quicker by air"
                .. (airText and (", " .. airText .. " in all") or "") .. "."
        elseif pin.role == "to" then
            lines[#lines + 1] = "Land here for your next step" .. (stepText and (": " .. stepText) or "") .. "."
        end
        return pin.name, lines
    end
    lines[#lines + 1] = "Flight master. You don't have this flight path yet: talk to them once (it's free), "
        .. "and later trips through here are shorter."
    if pin.onRoute then lines[#lines + 1] = "It's a step on your route (Flight paths to learn)." end
    return pin.name, lines
end

function MF.RoleLabel(role)
    if role == "from" then return "Fly from here" end
    if role == "to" then return "Land here: next step" end
    return nil
end

-- The selection after a click on a flight master: one pick, and any click
-- on a master while one is picked clears it.
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

-- The line the mouse is on or near: lines = { { name, ax, ay, bx, by } }.
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
    return (type(a) == "table" and type(b) == "table" and a.kind == "have" and b.kind == "have"
        and a.cont == b.cont) and true or false
end

function MF.Short(name)
    return (tostring(name or "?"):match("^([^,]+)"))
end

-- What a flight between two pins says. flown: its seconds the last time you
-- flew it (nil: never); estimate: a guess (nil: none; always said as "about");
-- fmt(seconds) -> text. A time that is not known is said to be not known.
function MF.FlightText(a, b, flown, estimate, fmt)
    local route = MF.Short(a.name) .. " to " .. MF.Short(b.name)
    if not MF.CanFly(a, b) then
        if a.cont ~= b.cont then return route .. ": not on one continent", false end
        local need = {}
        if a.kind ~= "have" then need[#need + 1] = a.npc or MF.Short(a.name) end
        if b.kind ~= "have" then need[#need + 1] = b.npc or MF.Short(b.name) end
        return route .. ": you can't fly it yet (learn the flight path at " .. table.concat(need, " and ") .. " first)", false
    end
    fmt = type(fmt) == "function" and fmt or function(s) return string.format("%.0f", math.floor(s + 0.5)) .. " s" end
    if finite(flown) then return route .. ": " .. fmt(flown) .. " (your last flight)", true end
    if finite(estimate) then return route .. ": about " .. fmt(estimate), true end
    return route .. ": flight time not known yet", true
end
