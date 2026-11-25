-- Travel spells (S33): N.TravelSpellStep over hand-written tables and
-- N.TravelSpellStepFrom over a stand-in client. Ported from legacy Flow
-- 0.35.377 Modules/Nav/TravelSpells.lua. Not tested in game.
local _, ns = ...

local N = ns.Nav

local MOONGLADE = 1450
local STEP = { map = MOONGLADE, x = 0.5, y = 0.5 }
local HERE = { position = { map = 1456, x = 0.4, y = 0.4 } } -- Thunder Bluff

local T = {}

T["data: Teleport: Moonglade and its map, as legacy Flow has them"] = function(t)
    local s = N.TRAVEL_SPELLS[1]
    t.eq(s.name, "Teleport: Moonglade")
    t.eq(s.map, MOONGLADE)
    t.eq(s.class, "DRUID")
end

-- Owner, lead section 618 ("Game facts, drop level"; section 611): no level
-- is typed into the table. The map is the one number a row may carry, and
-- no text of a row holds a digit. Fails before: the "from level 10" text.
T["data: no level is typed into the travel spells (section 618)"] = function(t)
    for i, s in ipairs(N.TRAVEL_SPELLS) do
        for key, v in pairs(s) do
            if type(v) == "number" then t.eq(key, "map", "row " .. i .. ": only the map is a number")
            elseif type(v) == "string" then t.eq(v:find("%d"), nil, "row " .. i .. " " .. key .. ": no number typed in: " .. v) end
        end
        t.eq(s.from, nil, "row " .. i .. ": no typed where-from")
    end
end

T["known: a step in the spell's zone from elsewhere is one cast away"] = function(t)
    local step, why = N.TravelSpellStep(N.TRAVEL_SPELLS, STEP, HERE, "DRUID", function() return true end)
    t.eq(why, nil)
    t.eq(step, { label = "Cast Teleport: Moonglade", text = true, spell = "Teleport: Moonglade" })
end

-- Section 618: not known, and no trainer window has listed it: the class
-- trainer, and no level. Fails before: the typed "from level 10".
T["not known, no trainer record: learn from your class trainer, no level"] = function(t)
    local step = N.TravelSpellStep(N.TRAVEL_SPELLS, STEP, HERE, "DRUID", function() return false end)
    t.eq(step, { label = "Learn Teleport: Moonglade", text = true, spell = "Teleport: Moonglade",
                 learn = true, detail = N.TRAVEL_FROM })
    t.eq(N.TRAVEL_FROM:find("%d"), nil, "no level in the words")
    local none = N.TravelSpellStep(N.TRAVEL_SPELLS, STEP, HERE, "DRUID", function() return false end,
        function() return nil end)
    t.eq(none and none.detail, N.TRAVEL_FROM, "a record without the spell: still no level")
end

-- Section 618: the level only from the player's own trainer window.
T["not known, with a trainer record: that record's level"] = function(t)
    local step = N.TravelSpellStep(N.TRAVEL_SPELLS, STEP, HERE, "DRUID", function() return false end,
        function(name) return name == "Teleport: Moonglade" and 14 or nil end)
    t.eq(step and step.detail, N.TRAVEL_FROM_LEVEL:format(14))
    local known = N.TravelSpellStep(N.TRAVEL_SPELLS, STEP, HERE, "DRUID", function() return true end,
        function() return 14 end)
    t.eq(known, { label = "Cast Teleport: Moonglade", text = true, spell = "Teleport: Moonglade" },
        "known: cast, no level")
end

T["trainer record: the level a saved trainer list gives the spell"] = function(t)
    local lists = {
        a = { npc = "Turak Runetotem", rows = { { name = "Moonfire", state = "known", level = 4 },
                                                { name = "Teleport: Moonglade", state = "unavailable", level = 10 } } },
        b = { npc = "Other", rows = { { name = "Teleport: Moonglade", state = "unavailable" } } },
    }
    t.eq(N.TravelSpellLevel(lists, "Teleport: Moonglade"), 10)
    t.eq(N.TravelSpellLevel(lists, "Hibernate"), nil, "not listed: no level")
    t.eq(N.TravelSpellLevel(nil, "Teleport: Moonglade"), nil)
    t.eq(N.TravelSpellLevel({ x = { rows = { { name = "Teleport: Moonglade", level = 0 } } } }, "Teleport: Moonglade"),
        nil, "no plain level: none")
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
