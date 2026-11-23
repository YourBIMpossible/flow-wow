local _, ns = ...

-- TaxiMark (S31): which flight master to ring on the flight map for your
-- next step. "When I go to fly somewhere, it would be really nice if the
-- target destination flight path that is recommended for my next item was
-- somehow illuminated."
--
-- This file is the pure rule only, ported from Flow's
-- Modules/Nav/TaxiMark.lua (0.35.377, :36-64); see
-- WoW/from-zen/RESEARCH-S31.md. LOOK ONLY: it picks a name and words a
-- label. It takes no flight, clicks nothing and reads nothing from the game.
--
-- The ring is drawn by the module at the end of this file (section 187
-- section 7) through client.taxiNodes and client.taxiMark: on the flight
-- map opening, Pick, then ring that name with Label; hide on its closing.
--
--   name, yards = TaxiMark.Pick(nodes, here, pt, flightSec, speed, saves)
--     nodes      the masters on the open map you can fly to, in world yards:
--                { { name, cont, wx, wy }, ... }
--     here       the name of the one you are at, or nil when not known
--     pt         your next step's spot: { cont, wx, wy }
--     flightSec  optional fn(from, to) -> seconds, or nil when not known
--     speed      yards a second on foot (TaxiMark.SPEED when not given)
--     saves      the share of the walk a flight must beat (TaxiMark.SAVES)
--     -> the master that lands you nearest the step, and how far from it;
--        nil when there is none, when the step is nearer where you stand,
--        or when the flight is not clearly quicker than walking. An input
--        that is not known gives no pick: nothing is guessed.
--   text = TaxiMark.Label(stepText)   the words under the ring
--
-- Setting (read by the module at the end of this file): "nav.taxiMark", bool, on by
-- default, as Flow's.

local TM = ns.TaxiMark or {}
ns.TaxiMark = TM

TM.SETTING = "nav.taxiMark"
TM.LABEL_MAX = 34      -- characters of the step's name under the ring (Flow: TM.LABEL_MAX)
TM.SPEED = 7           -- yards a second on foot (Flow's default in TM.Pick)
TM.SAVES = 0.8         -- a flight must beat this share of the walk (Flow: N.AIR_SAVES)

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function dist(ax, ay, bx, by)
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

function TM.Pick(nodes, here, pt, flightSec, speed, saves)
    if type(pt) ~= "table" or not finite(pt.wx) or not finite(pt.wy) or pt.cont == nil then return nil end
    local best, bd, hereD
    for _, n in ipairs(type(nodes) == "table" and nodes or {}) do
        if type(n) == "table" and n.cont == pt.cont and finite(n.wx) and finite(n.wy) then
            local d = dist(n.wx, n.wy, pt.wx, pt.wy)
            if here ~= nil and n.name == here then
                hereD = d
            elseif not bd or d < bd then
                best, bd = n.name, d
            end
        end
    end
    if not best then return nil end
    if hereD then
        if hereD <= bd then return nil end   -- the step is nearer where you stand
        local fly
        if type(flightSec) == "function" then
            local ok, sec = pcall(flightSec, here, best)
            if ok and finite(sec) then fly = sec end
        end
        speed = finite(speed) and speed > 0 and speed or TM.SPEED
        saves = finite(saves) and saves or TM.SAVES
        -- Walking is about as quick: no ring.
        if fly and fly + bd / speed >= (hereD / speed) * saves then return nil end
    end
    return best, bd
end

function TM.Label(text)
    text = tostring(text or "your next step")
    if #text > TM.LABEL_MAX then
        local cut = text:sub(1, TM.LABEL_MAX - 3)
        text = (cut:match("^(.*%S)%s+%S*$") or cut) .. "..."
    end
    local id = ns.id
    return (type(id) == "table" and id.title or "") .. ": " .. text
end

-- ------------------------------------------------------------------ module
-- Lead DISPATCH section 187 section 7: the reader of nav.taxiMark.
--
--   TM.StepFlight(k) -> flight, heading
--     heading: k.use("arrow").Heading() (the arrow's step, { cont, map, x,
--     y }) or nil. flight: k.use("flights").Last() when the arrow's step is
--     that flight's board point (the arrow says "Fly to ..."), else nil.
--     Shared with Nav/MapFlights.lua's module.
--   TM.Declare(k) -> api
--     On TAXIMAP_OPENED, and at each TM.EVERY seconds while it is open:
--     client.taxiNodes(), each node not "unreachable" put in the world
--     (client.mapCorners(read.map), Nav/Flights.lua's ToWorld); the step's
--     spot is the flight's target when the arrow is on a flight, else the
--     arrow's own step; TM.Pick (here = read.here; flight seconds: your own
--     saved time, else the straight line at your saved rate or Flights.RATE,
--     plus Flights.OVERHEAD) names the master; client.taxiMark() (made once,
--     at the first ring) rings it with TM.Label. No pick, no read or the
--     setting off: hidden. TAXIMAP_CLOSED hides it.
--     api.mark() -> the name rung, or nil;  api.hide()
--     ns.use("taxiMark") -> { Marked = name rung now, or nil }
--   LOOK ONLY: nothing is taken, selected or clicked. Not tested in game.
TM.NAME = "taxiMark"
TM.EVERY = 0.5          -- seconds between looks while the flight map is open
TM.ROW_LABEL = "Mark the flight master to fly to on the flight map"
TM.ROW_HELP = "On the open flight map, a ring on the flight master that lands you nearest your next step. "
    .. "Look only: it takes no flight."

local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if not ok then return nil end
    return v
end

local function same(a, b)
    return type(a) == "table" and type(b) == "table" and a.map ~= nil and a.map == b.map
        and finite(a.x) and finite(a.y) and finite(b.x) and finite(b.y)
        and math.abs(a.x - b.x) < 1e-6 and math.abs(a.y - b.y) < 1e-6
end

function TM.StepFlight(k)
    local use = type(k) == "table" and k.use or nil
    if type(use) ~= "function" then return nil, nil end
    local heading
    local arrow = use("arrow")
    if type(arrow) == "table" and type(arrow.Heading) == "function" then
        local ok, h = pcall(arrow.Heading)
        if ok and type(h) == "table" then heading = h end
    end
    if not heading then return nil, nil end
    local flights = use("flights")
    if type(flights) == "table" and type(flights.Last) == "function" then
        local ok, last = pcall(flights.Last)
        if ok and type(last) == "table" and same(last.board, heading) and type(last.there) == "table" then
            return last, heading
        end
    end
    return nil, heading
end

function TM.Declare(k)
    local api = {}
    local ctx, handle, marked
    local open = false
    local F = function() return ns.Nav and ns.Nav.Flights or nil end

    local function on()
        if not ctx then return false end
        local ok, v = pcall(ctx.settings.get, ctx.settings, TM.SETTING)
        return not (ok and v == false)
    end

    local function stored(scope, path)
        local ok, v = pcall(ctx.store.get, ctx.store, scope, path)
        if ok then return v end
        return nil
    end

    function api.hide()
        marked = nil
        if handle then pcall(handle.hide) end
    end

    -- The step's spot in world yards, or nil.
    local function spot(client, Flights)
        local flight, heading = TM.StepFlight(k)
        if flight then
            local th = flight.there
            if th.cont ~= nil and finite(th.wx) and finite(th.wy) then return { cont = th.cont, wx = th.wx, wy = th.wy } end
            return nil
        end
        if not heading or heading.map == nil then return nil end
        local cont, wx, wy = Flights.ToWorld(ask(client, "mapCorners", heading.map), heading.x, heading.y)
        if cont == nil then return nil end
        return { cont = cont, wx = wx, wy = wy }
    end

    function api.mark()
        if not ctx then return nil end
        local Flights = F()
        if not on() or type(Flights) ~= "table" then api.hide() return nil end
        local client = ctx.client
        local read = ask(client, "taxiNodes")
        if type(read) ~= "table" or read.map == nil or type(read.nodes) ~= "table" then api.hide() return nil end
        local corners = ask(client, "mapCorners", read.map)
        local nodes, byName, shares = {}, {}, {}
        for _, n in ipairs(read.nodes) do
            if type(n) == "table" and type(n.name) == "string" and n.state ~= "unreachable" then
                local cont, wx, wy = Flights.ToWorld(corners, n.x, n.y)
                if cont ~= nil then
                    local node = { name = n.name, cont = cont, wx = wx, wy = wy }
                    nodes[#nodes + 1] = node
                    byName[n.name] = node
                    shares[n.name] = { x = n.x, y = n.y }
                end
            end
        end
        local pt = spot(client, Flights)
        if not pt then api.hide() return nil end
        local times = stored("account", Flights.TIMES)
        local rate = stored("account", Flights.RATE_PATH)
        rate = finite(rate) and rate > 0 and rate or Flights.RATE
        local function seconds(from, to)
            local own = type(times) == "table" and times[from .. ">" .. to] or nil
            if finite(own) and own > 0 then return own end
            local a, b = byName[from], byName[to]
            if not a or not b then return nil end
            return dist(a.wx, a.wy, b.wx, b.wy) / rate + Flights.OVERHEAD
        end
        local name = TM.Pick(nodes, read.here, pt, seconds)
        if not name then api.hide() return nil end
        if not handle then
            handle = ask(client, "taxiMark")
            if type(handle) ~= "table" then handle = nil return nil end
        end
        local at = shares[name]
        local ok, done = pcall(handle.mark, { name = name, x = at.x, y = at.y }, TM.Label(nil))
        if not ok or done ~= true then api.hide() return nil end
        marked = name
        return name
    end

    k:Setting({ key = TM.SETTING, scope = "account", type = "bool", default = true, group = "Arrows",
        label = TM.ROW_LABEL, help = TM.ROW_HELP })

    k:Module({
        name = TM.NAME,
        needs = { "client", "store", "bus", "settings" },
        provides = { Marked = function() return marked end },
        ticks = { { every = TM.EVERY, when = "always", run = function() if open then api.mark() end end } },
        start = function(c)
            ctx = c
            c.bus:on(TM.NAME, "TAXIMAP_OPENED", function()
                open = true
                api.mark()
            end)
            c.bus:on(TM.NAME, "TAXIMAP_CLOSED", function()
                open = false
                api.hide()
            end)
        end,
        stop = function()
            open = false
            api.hide()
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.taxiMark = TM.Declare(ns)
