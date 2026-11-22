-- Travel spells (S33): N.TravelSpellStep over hand-written tables and
-- N.TravelSpellStepFrom over a stand-in client. Ported from legacy Flow
-- 0.35.377 Modules/Nav/TravelSpells.lua. Not tested in game.
local _, ns = ...

local N = ns.Nav

local MOONGLADE = 1450
local STEP = { map = MOONGLADE, x = 0.5, y = 0.5 }
local HERE = { position = { map = 1456, x = 0.4, y = 0.4 } } -- Thunder Bluff

local T = {}

T["data: Teleport: Moonglade as legacy Flow has it"] = function(t)
    local s = N.TRAVEL_SPELLS[1]
    t.eq(s.name, "Teleport: Moonglade")
    t.eq(s.map, MOONGLADE)
    t.eq(s.class, "DRUID")
    t.eq(s.from, "your class trainer, from level 10")
end

T["known: a step in the spell's zone from elsewhere is one cast away"] = function(t)
    local step, why = N.TravelSpellStep(N.TRAVEL_SPELLS, STEP, HERE, "DRUID", function() return true end)
    t.eq(why, nil)
    t.eq(step, { label = "Cast Teleport: Moonglade", text = true, spell = "Teleport: Moonglade" })
end

T["not known: says where the spell comes from, and is marked to learn"] = function(t)
    local step = N.TravelSpellStep(N.TRAVEL_SPELLS, STEP, HERE, "DRUID", function() return false end)
    t.eq(step, { label = "Learn Teleport: Moonglade", text = true, spell = "Teleport: Moonglade",
                 learn = true, detail = "your class trainer, from level 10" })
end

T["known not said: no step, never taken as known"] = function(t)
    local step, why = N.TravelSpellStep(N.TRAVEL_SPELLS, STEP, HERE, "DRUID", function() return nil end)
    t.eq(step, nil)
    t.eq(why, "known unknown")
end

T["no step: same map, other class, unknown class, no target"] = function(t)
    local yes = function() return true end
    local _, a = N.TravelSpellStep(N.TRAVEL_SPELLS, STEP, { position = { map = MOONGLADE, x = 0.1, y = 0.1 } }, "DRUID", yes)
    t.eq(a, "same map")
    local _, b = N.TravelSpellStep(N.TRAVEL_SPELLS, STEP, HERE, "MAGE", yes)
    t.eq(b, "no spell")
    local _, c = N.TravelSpellStep(N.TRAVEL_SPELLS, STEP, HERE, nil, yes)
    t.eq(c, "class unknown")
    local _, d = N.TravelSpellStep(N.TRAVEL_SPELLS, { x = 0.5 }, HERE, "DRUID", yes)
    t.eq(d, "no target")
    local _, e = N.TravelSpellStep(N.TRAVEL_SPELLS, { map = 1411, x = 0.5, y = 0.5 }, HERE, "DRUID", yes)
    t.eq(e, "no spell", "no spell reaches that map")
end

T["player position unknown: still a step (the spell is one way from anywhere else)"] = function(t)
    local step = N.TravelSpellStep(N.TRAVEL_SPELLS, STEP, {}, "DRUID", function() return true end)
    t.eq(step and step.label, "Cast Teleport: Moonglade")
end

T["from client: class, position, spell id and known are read"] = function(t)
    local client = {
        class = function() return "DRUID" end,
        position = function() return { map = 1456, x = 0.4, y = 0.4 } end,
        spellId = function(name) return name == "Teleport: Moonglade" and 18960 or nil end,
        spell = function(id) return id == 18960 and { known = true } or nil end,
    }
    t.eq(N.TravelSpellStepFrom(STEP, client).label, "Cast Teleport: Moonglade")
    client.spellId = function() return nil end
    local _, why = N.TravelSpellStepFrom(STEP, client)
    t.eq(why, "known unknown", "no id: not known, not guessed")
    local _, none = N.TravelSpellStepFrom(STEP, nil)
    t.eq(none, "class unknown")
end

T["planner: a step a cast away counts as legacy's ten-second cast"] = function(t)
    t.eq(N.TRAVEL_SPELL_YARDS, 120)
end

return T
