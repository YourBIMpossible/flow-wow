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
-- The ring itself is NOT built here: it needs a read of the open flight map
-- and an overlay over the game's own button, which the client boundary does
-- not have yet (CLIENT NEEDs client.taxiNodes and client.taxiMark, posted
-- with this item). When they exist, the module is: on the flight map
-- opening, Pick, then ring that name with Label; hide on its closing.
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
-- Setting (for the module, when built): "nav.taxiMark", bool, on by
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
