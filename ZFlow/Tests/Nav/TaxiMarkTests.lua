local _, ns = ...
-- S31 (LEDGER 143): your next step's flight master on the flight map.
-- Ported from legacy Flow's test "flight map: your next step's flight master
-- gets a ring" (Modules/Tests.lua, TM.Pick and TM.Label). The ring frame
-- itself is not ported here (needs the client); these are the pure parts.
local N = ns.Nav

local NODES = {
    { name = "Crossroads", cont = 1, wx = 0, wy = 0 },
    { name = "Camp Taurajo", cont = 1, wx = 2000, wy = 0 },
    { name = "Ratchet", cont = 1, wx = 0, wy = 1500 },
    { name = "Undercity", cont = 0, wx = 2100, wy = 0 },
}
local STEP = { cont = 1, wx = 2100, wy = 50 }
local function sixty() return 60 end

local T = {}

T["the flight master that lands you nearest the step"] = function(t)
    local name, yd = N.TaxiMark.Pick(NODES, "Crossroads", STEP, sixty, 7, 0.8)
    t.eq(name, "Camp Taurajo", "the nearest to the step")
    t.ok(type(yd) == "number" and yd > 100 and yd < 120, "and how far from it (got " .. tostring(yd) .. ")")
end

T["nothing to ring: standing at the nearest, or the step is a short walk"] = function(t)
    t.eq(N.TaxiMark.Pick(NODES, "Camp Taurajo", STEP, sixty, 7, 0.8), nil, "standing at the nearest one")
    t.eq(N.TaxiMark.Pick(NODES, "Crossroads", { cont = 1, wx = 300, wy = 0 }, function() return 120 end, 7, 0.8), nil,
        "a step a short walk from here: no flight")
end

T["another continent, no step, unknown flight time"] = function(t)
    t.eq(N.TaxiMark.Pick(NODES, "Crossroads", { cont = 5, wx = 0, wy = 0 }), nil, "a step on another continent: none")
    t.eq(N.TaxiMark.Pick(NODES, "Crossroads", nil), nil, "no step: nothing")
    t.eq(N.TaxiMark.Pick(NODES, "Crossroads", STEP, nil, 7), "Camp Taurajo", "flight time not known yet: the nearest still")
end

T["F-086: a node with no place is never picked; an unknown spot gives nothing"] = function(t)
    local nodes = { { name = "Nowhere", cont = 1 }, { name = "Camp Taurajo", cont = 1, wx = 2000, wy = 0 } }
    t.eq(N.TaxiMark.Pick(nodes, nil, STEP), "Camp Taurajo", "the node with no place is passed over")
    t.eq(N.TaxiMark.Pick(NODES, "Crossroads", { cont = 1 }), nil, "a step with no place: nothing")
    t.eq(N.TaxiMark.Pick(NODES, "Crossroads", { wx = 1, wy = 1 }), nil, "a step with no continent: nothing")
end

T["the words under the ring"] = function(t)
    t.eq(N.TaxiMark.Label("Turn in: The Ashenvale Hunt"), "Turn in: The Ashenvale Hunt", "the step's text as it is")
    local long = N.TaxiMark.Label(string.rep("word ", 20))
    t.ok(#long <= N.TaxiMark.LABEL_MAX, "a long step's text is cut to the limit (got " .. #long .. ")")
    t.ok(long:sub(-3) == "...", "and says so")
    t.ok(not long:find("wo...", 1, true), "cut at a word, not inside one")
    t.eq(N.TaxiMark.Label(nil), "your next step", "no text: plain words")
end

T["advisory only: the module calls nothing to fly"] = function(t)
    for k in pairs(N.TaxiMark) do
        t.ok(not tostring(k):find("Take", 1, true), "no Take* in the module: " .. tostring(k))
    end
end

T["the constants Flow used"] = function(t)
    t.eq(N.TaxiMark.DOTS, 12)
    t.eq(N.TaxiMark.DOT, 4)
    t.eq(N.TaxiMark.SPIN, 0.5)
    t.eq(N.TaxiMark.SETTING, "nav.taxiMark")
end

return T
