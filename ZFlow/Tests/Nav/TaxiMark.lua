local _, ns = ...

-- Tests for ZFlow/Nav/TaxiMark.lua (S31, LEDGER 143): which flight master
-- to ring on the flight map for your next step, ported from Flow's
-- Modules/Nav/TaxiMark.lua (see WoW/from-zen/RESEARCH-S31.md). Pure:
-- hand-written world spots. Nothing is drawn and no flight is taken.

local TM = ns.TaxiMark
local tests = {}

local function nodes()
    return {
        { name = "Here", cont = 1, wx = 0, wy = 0 },
        { name = "Near Step", cont = 1, wx = 5000, wy = 100 },
        { name = "Far", cont = 1, wx = 9000, wy = 9000 },
        { name = "Other Continent", cont = 2, wx = 5000, wy = 0 },
        { name = "No Place", cont = 1 },
    }
end

local STEP = { cont = 1, wx = 5000, wy = 0 }

-- Flow :36-54.
tests["taxi mark: the master you can fly to that lands you nearest your next step"] = function(t)
    local name, yd = TM.Pick(nodes(), "Here", STEP)
    t.eq(name, "Near Step")
    t.eq(yd, 100)
end

tests["taxi mark: nothing when the step is nearer where you stand"] = function(t)
    local step = { cont = 1, wx = 50, wy = 0 }
    t.eq(TM.Pick(nodes(), "Here", step), nil)
end

tests["taxi mark: nothing when walking is about as quick as flying"] = function(t)
    -- From Here the step is 5000 yd: 714 s on foot at 7 yd a second. A flight
    -- must beat 0.8 of that (571 s) with its own walk (100 yd, 14 s) added.
    t.eq((TM.Pick(nodes(), "Here", STEP, function() return 300 end)), "Near Step", "300 s in the air: worth it")
    t.eq(TM.Pick(nodes(), "Here", STEP, function() return 600 end), nil, "600 s in the air: walk")
    t.eq((TM.Pick(nodes(), "Here", STEP, function() return nil end)), "Near Step", "flight time not known: still the nearest")
    t.eq((TM.Pick(nodes(), "Here", STEP, function() return 300 end, 3.5)), "Near Step", "a slower walk: flying is worth more")
    t.eq(TM.Pick(nodes(), "Here", STEP, function() return 300 end, 14), nil, "twice as fast on foot: 300 s in the air is not worth it")
    t.eq((TM.Pick(nodes(), "Here", STEP, function() return 300 end, 14, 0.95)), "Near Step", "a looser share lets it through")
    t.eq(TM.SPEED, 7)
    t.eq(TM.SAVES, 0.8)
end

tests["taxi mark: without knowing where you stand, the nearest to the step"] = function(t)
    t.eq((TM.Pick(nodes(), nil, STEP)), "Near Step")
end

tests["taxi mark: missing inputs give no pick, never a guess"] = function(t)
    t.eq(TM.Pick(nodes(), "Here", nil), nil, "no next step")
    t.eq(TM.Pick(nodes(), "Here", { wx = 1, wy = 1 }), nil, "a step with no continent")
    t.eq(TM.Pick(nodes(), "Here", { cont = 1 }), nil, "a step with no place")
    t.eq(TM.Pick(nil, "Here", STEP), nil, "no flight map read")
    t.eq(TM.Pick({ { name = "Other Continent", cont = 2, wx = 5000, wy = 0 } }, nil, STEP), nil, "nothing on the step's continent")
    t.eq(TM.Pick({ { name = "Here", cont = 1, wx = 0, wy = 0 } }, "Here", STEP), nil, "only where you stand")
end

-- Flow :57-64.
tests["taxi mark: the words under the ring"] = function(t)
    t.eq(TM.Label("Kill 8 boars"), ns.id.title .. ": Kill 8 boars")
    t.eq(TM.Label(nil), ns.id.title .. ": your next step")
    t.eq(TM.LABEL_MAX, 34)
    local long = TM.Label("Bring the letter to the innkeeper in the far town")
    t.eq(long, ns.id.title .. ": Bring the letter to the...", "cut at a word, with three dots")
    t.ok(#long - #(ns.id.title .. ": ") <= TM.LABEL_MAX, "never longer than the limit")
    t.eq(TM.Label(string.rep("x", 50)), ns.id.title .. ": " .. string.rep("x", 31) .. "...", "one long word: cut hard")
end

tests["taxi mark: look only - nothing takes a flight"] = function(t)
    for name in pairs(TM) do
        local n = tostring(name):lower()
        t.ok(not (n:find("take") or n:find("^fly$") or n:find("click")), "no acting function: " .. n)
    end
end

return tests
