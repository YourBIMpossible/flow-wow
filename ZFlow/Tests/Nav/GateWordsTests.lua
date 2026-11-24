local _, ns = ...

-- Tests for S35 (lead dispatch section 395 item 3): the words a trip leg
-- gets when it crosses a gate the player walked (Nav/GateWords.lua). Pure;
-- the walled capitals are Nav/Gates.lua's own table. Made-up stop labels.

local tests = {}

local N = ns.Nav
local MULGORE, TB, ORG, DURO, DARN, TELD = 1412, 1456, 1454, 1411, 1457, 1438
local W = function() return N.GateWords end

tests["lift: up into Thunder Bluff from its foot"] = function(t)
    t.eq(W()(MULGORE, TB, "bank"), "Take the lift up to Thunder Bluff.")
end

tests["lift: down out of Thunder Bluff to its foot"] = function(t)
    t.eq(W()(TB, MULGORE, "camp"), "Take the lift down to the foot of Thunder Bluff.")
end

tests["walled city: in and out through the gate the player found"] = function(t)
    t.eq(W()(DURO, ORG, "bank"), "Go in through the gate you found to reach Orgrimmar.")
    t.eq(W()(ORG, DURO, "camp"), "Go out through the gate you found to leave Orgrimmar.")
end

tests["portal city: the portal, both ways"] = function(t)
    t.eq(W()(TELD, DARN, "bank"), "Take the portal to Darnassus.")
    t.eq(W()(DARN, TELD, "camp"), "Take the portal out of Darnassus.")
end

tests["open maps: a pass to the stop, by its label"] = function(t)
    t.eq(W()(1426, 1437, "mail"), "Go through the pass you found to reach mail.")
    t.eq(W()(1426, 1437, nil), "Go through the pass you found to reach the next stop.")
    t.eq(W()(1426, 1437, ""), "Go through the pass you found to reach the next stop.")
end

tests["unknown: no maps or the same map says nothing"] = function(t)
    t.eq(W()(nil, TB, "bank"), nil)
    t.eq(W()(MULGORE, nil, "bank"), nil)
    t.eq(W()(TB, TB, "bank"), nil)
    t.eq(W()("x", TB, "bank"), nil)
end

tests["trip words: a gate leg gets the gate line, other legs keep via"] = function(t)
    t.eq(N.Trip.GateVia({ via = "gate", label = "Way to Thunder Bluff" }, MULGORE, TB, "bank"),
        "Take the lift up to Thunder Bluff.")
    t.eq(N.Trip.GateVia({ via = "crossing", label = "Boat to Tirisfal dock" }, DURO, 1420, "mail"),
        "via Boat to Tirisfal dock")
    t.eq(N.Trip.GateVia({ label = "Mail" }, DURO, 1420, "mail"), nil, "no travel step: no words")
    t.eq(N.Trip.GateVia(nil, DURO, 1420, "mail"), nil)
    t.eq(N.Trip.GateVia({ via = "gate", label = "Way to your next step" }, nil, TB, "bank"),
        "via Way to your next step", "map unknown: the plain via, nothing guessed")
end

return tests
