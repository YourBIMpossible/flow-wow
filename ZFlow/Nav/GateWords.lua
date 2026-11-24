local _, ns = ...
-- Z-Flow gate words (S35, lead dispatch section 395 item 3): the line a trip
-- leg gets when it crosses a gate the player walked (Nav/Gates.lua). Pure.
-- Names come only from N.GATE_WALLED (the walled capitals Gates already
-- holds); a learned gate keeps no name, so a pass between open maps is
-- named by the stop it leads to. It only says so: nothing moves the player.
-- Not tested in game.
--
-- N.GateWords(fromMap, toMap, stopLabel) -> line or nil
--   lift-only city:  "Take the lift up to <city>." /
--                    "Take the lift down to the foot of <city>."
--   portal city:     "Take the portal to <city>." / "Take the portal out of <city>."
--   walled city:     "Go in through the gate you found to reach <city>." /
--                    "Go out through the gate you found to leave <city>."
--   open maps:       "Go through the pass you found to reach <stop>."
--   nil when either map is unknown or both are the same map.
ns.Nav = ns.Nav or {}
local N = ns.Nav

N.GATE_WORDS = {
    liftUp = "Take the lift up to %s.",
    liftDown = "Take the lift down to the foot of %s.",
    portalIn = "Take the portal to %s.",
    portalOut = "Take the portal out of %s.",
    gateIn = "Go in through the gate you found to reach %s.",
    gateOut = "Go out through the gate you found to leave %s.",
    pass = "Go through the pass you found to reach %s.",
    nextStop = "the next stop",
}

local function city(map)
    local w = N.GATE_WALLED and N.GATE_WALLED[map]
    if type(w) ~= "table" or type(w.why) ~= "string" then return nil end
    local name = w.why:match("^([^:]+):")
    if not name then return nil end
    return { name = name, lift = w.lift == true, portal = w.why:find("portal", 1, true) ~= nil }
end

function N.GateWords(fromMap, toMap, stopLabel)
    if type(fromMap) ~= "number" or type(toMap) ~= "number" or fromMap == toMap then return nil end
    local W = N.GATE_WORDS
    local into, outOf = city(toMap), city(fromMap)
    if into then
        if into.lift then return W.liftUp:format(into.name) end
        if into.portal then return W.portalIn:format(into.name) end
        return W.gateIn:format(into.name)
    end
    if outOf then
        if outOf.lift then return W.liftDown:format(outOf.name) end
        if outOf.portal then return W.portalOut:format(outOf.name) end
        return W.gateOut:format(outOf.name)
    end
    local where = (type(stopLabel) == "string" and stopLabel ~= "") and stopLabel or W.nextStop
    return W.pass:format(where)
end
