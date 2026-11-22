local _, ns = ...
-- Z-Flow flight map mark (S31, LEDGER 143): which flight master on the open
-- flight map lands the player nearest their next step. Ported from legacy
-- Flow 0.35.312-0.35.328 (Modules/Nav/TaxiMark.lua: TM.Pick, TM.Label).
-- Research: WoW/from-zen/RESEARCH-S31.md. Not tested in game.
--
-- PURE PART ONLY. Flow also drew a click-through ring of dots over the game's
-- own flight-map button. That frame is not ported here: whether a frame
-- laid over TaxiFrame / FlightMapFrame is free of taint on this client needs
-- the client (RESEARCH-S31.md). Advisory only: nothing here takes a flight,
-- clicks a node or calls any Take* function.
--
-- N.TaxiMark.Pick(nodes, here, spot, flightSec, speed, saves) -> name, yards | nil
--   nodes      the flight masters on the open map you can fly to, in yards in
--              one continent frame: { name, cont, wx, wy }
--   here       the name of the node the player stands at, or nil
--   spot       the next step's place { cont, wx, wy }
--   flightSec  optional fn(from, to) -> seconds or nil
--   speed      yards a second on foot (default 7)
--   saves      the share of the walk a flight must beat (default 0.8)
--   Nothing when the step is nearer the node you stand at, or about as
--   quick to walk to from there. A node or step with no place is never
--   used (F-086).
-- N.TaxiMark.Label(text) -> the words under the mark, cut at a word to
--   LABEL_MAX bytes with "..."; "your next step" when there is no text. The
--   caller adds the add-on's title (ns.id) when it wants one.
-- N.TaxiMark.SETTING  "nav.taxiMark", bool, on by default (the lead adds the row)
ns.Nav = ns.Nav or {}
local N = ns.Nav
local TM = {}
N.TaxiMark = TM

TM.DOTS, TM.DOT = 12, 4
TM.SPIN = 0.5
TM.LABEL_MAX = 34
TM.SETTING = "nav.taxiMark"

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function placed(p)
    return type(p) == "table" and p.cont ~= nil and finite(p.wx) and finite(p.wy)
end

local function dist(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

function TM.Pick(nodes, here, spot, flightSec, speed, saves)
    if not placed(spot) then return nil end
    local best, bd, hereD
    for _, n in ipairs(type(nodes) == "table" and nodes or {}) do
        if placed(n) and n.cont == spot.cont then
            local d = dist(n.wx, n.wy, spot.wx, spot.wy)
            if here ~= nil and n.name == here then
                hereD = d
            elseif not bd or d < bd then
                best, bd = n.name, d
            end
        end
    end
    if not best then return nil end
    if hereD then
        if hereD <= bd then return nil end
        local fly = nil
        if type(flightSec) == "function" then
            local ok, s = pcall(flightSec, here, best)
            if ok and finite(s) then fly = s end
        end
        speed = finite(speed) and speed > 0 and speed or 7
        if fly and fly + bd / speed >= (hereD / speed) * (finite(saves) and saves or 0.8) then return nil end
    end
    return best, bd
end

function TM.Label(text)
    if text == nil or text == "" then return "your next step" end
    text = tostring(text)
    if #text > TM.LABEL_MAX then
        local cut = text:sub(1, TM.LABEL_MAX - 3)
        text = (cut:match("^(.*%S)%s+%S*$") or cut) .. "..."
    end
    return text
end
