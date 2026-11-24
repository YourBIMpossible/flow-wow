local _, ns = ...
-- Z-Flow: the arrow's status in two lines (parity row A1-33, lead section
-- 477): what the quest arrow points at and why (the source `arrow why`
-- names), then the next stop of the planned route. `<slash> arrow status`
-- says them (UI/Arrow.lua, the lead-owned hook).
-- Compared with Flow Modules/Nav/Nav.lua `/flow nav why` (route and plan
-- lines); Flow has no status word, so this is the short form of why.
-- LOOK ONLY: it reads and prints. Not tested in game.
--
-- Pure:
--   WS.Lines(stepName, from, stops) -> two lines
--     stepName  the arrow step's label, or nil
--     from      the words `arrow why` gives for its source
--     stops     tripRoute Current() (the stops still to walk) or nil
ns.Nav = ns.Nav or {}
local N = ns.Nav
local WS = {}
N.WaypointStatus = WS

WS.WORD = "status"
WS.POINTS = "Arrow: %s (from %s)."
WS.NOTHING = "Arrow: no step now (from %s)."
WS.NEXT = "Next stop: %s."
WS.LAST = "Next stop: none, this is the route's last."
WS.NO_ROUTE = "Next stop: no route planned (the route word plans one)."

local function text(v)
    return type(v) == "string" and v ~= "" and v or nil
end

function WS.Lines(stepName, from, stops)
    local name, source = text(stepName), text(from) or "nothing"
    local first = name and WS.POINTS:format(name, source) or WS.NOTHING:format(source)
    -- tripRoute Current() is { kind, label, stops }: its stops are the list.
    if type(stops) == "table" and type(stops.stops) == "table" then stops = stops.stops end
    if type(stops) ~= "table" or #stops == 0 then return { first, WS.NO_ROUTE } end
    local i = 1
    if name and type(stops[1]) == "table" and stops[1].label == name then i = 2 end
    local nextStop = type(stops[i]) == "table" and text(stops[i].label)
    return { first, nextStop and WS.NEXT:format(nextStop) or WS.LAST }
end
