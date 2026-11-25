-- Travel spells (S33): N.TravelSpellStep over hand-written tables and
-- N.TravelSpellStepFrom over a stand-in client. Ported from legacy Flow
-- 0.35.377 Modules/Nav/TravelSpells.lua. Not tested in game.
local _, ns = ...

local N = ns.Nav

local MOONGLADE = 1450
local STEP = { map = MOONGLADE, x = 0.5, y = 0.5 }
local HERE = { position = { map = 1456, x = 0.4, y = 0.4 } } -- Thunder Bluff

local T = {}
local NAMED = function(map) return map == MOONGLADE and "Moonglade" or nil end

-- Owner, lead section 619: the spell number, the class and the level are
-- researched facts (the Forever tooltip of spell 18960), kept in the row.
T["data: Teleport: Moonglade, with the facts its tooltip gives"] = function(t)
    local s = N.TRAVEL_SPELLS[1]
    t.eq(s.name, "Teleport: Moonglade")
    t.eq(s.id, 18960)
    t.eq(s.map, MOONGLADE)
    t.eq(s.mapName, "Moonglade")
    t.eq(s.class, "DRUID")
    t.eq(s.level, 10)
    t.eq(s.area, 493, "the zone's area number")
    t.eq(s.from, nil, "where it is learned is not verified: not said")
end

T["known: a step in the spell's zone from elsewhere is one cast away"] = function(t)
    local step, why = N.TravelSpellStep(N.TRAVEL_SPELLS, STEP, HERE, "DRUID", function() return true end, NAMED)
    t.eq(why, nil)
    t.eq(step, { label = "Cast Teleport: Moonglade", text = true, spell = "Teleport: Moonglade" })
end

-- Fails before: detail = "your class trainer, from level 10" and no hint.
T["not known: the level it needs, marked to learn, no place it is learned at"] = function(t)
    local step = N.TravelSpellStep(N.TRAVEL_SPELLS, STEP, HERE, "DRUID", function() return false end, NAMED)
    t.eq(step, { label = "Learn Teleport: Moonglade", text = true, spell = "Teleport: Moonglade",
                 learn = true, hint = "Teleport: Moonglade needs level 10" })
end

T["known not said: no step, never taken as known"] = function(t)
    local step, why = N.TravelSpellStep(N.TRAVEL_SPELLS, STEP, HERE, "DRUID", function() return nil end, NAMED)
    t.eq(step, nil)
    t.eq(why, "known unknown")
end

-- Section 619: 1450 is Moonglade only when the client names it so.
-- Fails before: a step whatever the client names the map.
T["map name: the spell is tied to its map only when the client names it"] = function(t)
    local yes = function() return true end
    local step = N.TravelSpellStep(N.TRAVEL_SPELLS, STEP, HERE, "DRUID", yes, NAMED)
    t.eq(step and step.label, "Cast Teleport: Moonglade", "named Moonglade: the step")
    local a, why = N.TravelSpellStep(N.TRAVEL_SPELLS, STEP, HERE, "DRUID", yes, function() return "Winterspring" end)
    t.eq(a, nil); t.eq(why, "map not confirmed", "another name")
    local b, whyB = N.TravelSpellStep(N.TRAVEL_SPELLS, STEP, HERE, "DRUID", yes, function() return nil end)
    t.eq(b, nil); t.eq(whyB, "map not confirmed", "no name read")
    local c, whyC = N.TravelSpellStep(N.TRAVEL_SPELLS, STEP, HERE, "DRUID", yes)
    t.eq(c, nil); t.eq(whyC, "map not confirmed", "no reader")
    local d, whyD = N.TravelSpellStep(N.TRAVEL_SPELLS, STEP, HERE, "DRUID", function() return false end,
        function() return "Winterspring" end)
    t.eq(d, nil); t.eq(whyD, "map not confirmed", "not known either: no line")
end

T["no step: same map, other class, unknown class, no target"] = function(t)
    local yes = function() return true end
    local there = { position = { map = MOONGLADE, x = 0.1, y = 0.1 } }
    local _, a = N.TravelSpellStep(N.TRAVEL_SPELLS, STEP, there, "DRUID", yes, NAMED)
    t.eq(a, "same map")
    local _, b = N.TravelSpellStep(N.TRAVEL_SPELLS, STEP, HERE, "MAGE", yes, NAMED)
    t.eq(b, "no spell")
    local _, c = N.TravelSpellStep(N.TRAVEL_SPELLS, STEP, HERE, nil, yes, NAMED)
    t.eq(c, "class unknown")
    local _, d = N.TravelSpellStep(N.TRAVEL_SPELLS, { x = 0.5 }, HERE, "DRUID", yes, NAMED)
    t.eq(d, "no target")
    local _, e = N.TravelSpellStep(N.TRAVEL_SPELLS, { map = 1411, x = 0.5, y = 0.5 }, HERE, "DRUID", yes, NAMED)
    t.eq(e, "no spell", "no spell reaches that map")
end

T["player position unknown: still a step (the spell is one way from anywhere else)"] = function(t)
    local step = N.TravelSpellStep(N.TRAVEL_SPELLS, STEP, {}, "DRUID", function() return true end, NAMED)
    t.eq(step and step.label, "Cast Teleport: Moonglade")
end

-- Section 619: known is asked of the game by the spell's number.
T["from client: class, position, the map's name and known by the spell number"] = function(t)
    local asked
    local client = {
        class = function() return "DRUID" end,
        position = function() return { map = 1456, x = 0.4, y = 0.4 } end,
        mapName = function(map) return map == MOONGLADE and "Moonglade" or nil end,
        spell = function(id) asked = id; return id == 18960 and { known = true } or nil end,
    }
    t.eq(N.TravelSpellStepFrom(STEP, client).label, "Cast Teleport: Moonglade")
    t.eq(asked, 18960, "asked by the number in the row")
    client.spell = function() return { known = false } end
    t.eq(N.TravelSpellStepFrom(STEP, client).hint, "Teleport: Moonglade needs level 10")
    client.spell = function() return nil end
    local _, why = N.TravelSpellStepFrom(STEP, client)
    t.eq(why, "known unknown", "no answer: not known, not guessed")
    client.mapName = nil
    local _, whyMap = N.TravelSpellStepFrom(STEP, client)
    t.eq(whyMap, "map not confirmed", "a client with no map names")
    local _, none = N.TravelSpellStepFrom(STEP, nil)
    t.eq(none, "class unknown")
end

-- Lead section 621: who teaches it, and for how much, only from a trainer
-- list the player opened.
T["trainer record: the trainer and cost a saved list gives the spell"] = function(t)
    local SPELL = "Teleport: Moonglade"
    local lists = {
        b = { npc = "Zed", rows = { { name = SPELL, state = "unavailable" } } },
        a = { npc = "Turak Runetotem", rows = { { name = "Moonfire", state = "known", cost = 10 },
                                                { name = SPELL, state = "unavailable", cost = 300 } } },
    }
    t.eq(N.TravelSpellTaught(lists, SPELL), { npc = "Turak Runetotem", cost = 300 }, "the first list by key")
    t.eq(N.TravelSpellTaught({ b = lists.b }, SPELL), { npc = "Zed" }, "no cost read: none said")
    t.eq(N.TravelSpellTaught(lists, "Hibernate"), nil, "not listed")
    t.eq(N.TravelSpellTaught(nil, SPELL), nil)
    t.eq(N.TravelSpellTaught({ x = { rows = { { name = SPELL } } } }, SPELL), nil, "no trainer name: nothing")
end

T["not known, with a trainer record: the line names that trainer and cost"] = function(t)
    local no = function() return false end
    local needs = "Teleport: Moonglade needs level 10"
    local step = N.TravelSpellStep(N.TRAVEL_SPELLS, STEP, HERE, "DRUID", no, NAMED,
        function() return { npc = "Turak Runetotem", cost = 300 } end)
    t.eq(step and step.hint, N.TRAVEL_TAUGHT_COST:format(needs, "Turak Runetotem", ns.Prices.Coin(300)))
    local bare = N.TravelSpellStep(N.TRAVEL_SPELLS, STEP, HERE, "DRUID", no, NAMED,
        function() return { npc = "Turak Runetotem" } end)
    t.eq(bare and bare.hint, N.TRAVEL_TAUGHT:format(needs, "Turak Runetotem"), "no cost read: the trainer only")
    local none = N.TravelSpellStep(N.TRAVEL_SPELLS, STEP, HERE, "DRUID", no, NAMED, function() return nil end)
    t.eq(none and none.hint, needs, "no record: the level only")
end

-- Lead section 623 item 3: the level is the client's.
T["not known: needs the level below it, not learned yet at it or above"] = function(t)
    local no = function() return false end
    local function hint(level)
        local step = N.TravelSpellStep(N.TRAVEL_SPELLS, STEP, HERE, "DRUID", no, NAMED, nil, { level = level })
        return step and step.hint
    end
    t.eq(hint(9), "Teleport: Moonglade needs level 10")
    t.eq(hint(10), "Teleport: Moonglade: not learned yet")
    t.eq(hint(40), "Teleport: Moonglade: not learned yet")
    t.eq(hint(nil), "Teleport: Moonglade needs level 10", "level not read: the cited fact only")
    local step = N.TravelSpellStep(N.TRAVEL_SPELLS, STEP, HERE, "DRUID", no, NAMED,
        function() return { npc = "Turak Runetotem" } end, { level = 12 })
    t.eq(step and step.hint, N.TRAVEL_TAUGHT:format("Teleport: Moonglade: not learned yet", "Turak Runetotem"))
end

-- Section 623 item 1: the names the map may be called (the player's
-- Questie, in their language) take the place of the English one.
T["map name: the names given are the ones that count"] = function(t)
    local yes = function() return true end
    local german = function() return "Mondlichtung" end
    local a = N.TravelSpellStep(N.TRAVEL_SPELLS, STEP, HERE, "DRUID", yes, german, nil,
        { mapNames = { "Moonglade", "Mondlichtung" } })
    t.eq(a and a.label, "Cast Teleport: Moonglade", "one of the names")
    local b, why = N.TravelSpellStep(N.TRAVEL_SPELLS, STEP, HERE, "DRUID", yes, german, nil,
        { mapNames = { "Moonglade", "Reflet-de-Lune" } })
    t.eq(b, nil); t.eq(why, "map not confirmed")
    local c, whyC = N.TravelSpellStep(N.TRAVEL_SPELLS, STEP, HERE, "DRUID", yes, german, nil, { mapNames = {} })
    t.eq(c, nil); t.eq(whyC, "map not confirmed", "no names given: the English one, which is not it")
end

-- Lead section 625: the map's name is compared with the client's own name
-- for the row's area, so the check holds in every language.
T["from client: map 1450 is the spell's zone when the client names its area the same"] = function(t)
    local map, area = "Mondlichtung", "Mondlichtung"
    local client = {
        class = function() return "DRUID" end,
        position = function() return { map = 1456, x = 0.4, y = 0.4 } end,
        mapName = function(m) return m == MOONGLADE and map or nil end,
        areaName = function(a) return a == 493 and area or nil end,
        spell = function() return { known = true } end,
    }
    t.eq(N.TravelSpellStepFrom(STEP, client).label, "Cast Teleport: Moonglade", "a German client, both the same")
    area = "Winterquell"
    local _, why = N.TravelSpellStepFrom(STEP, client)
    t.eq(why, "map not confirmed", "the area has another name")
    area = "Moonglade"
    local _, whyEn = N.TravelSpellStepFrom(STEP, client)
    t.eq(whyEn, "map not confirmed", "an area name read is the only one that counts, never the English one too")
    area = nil
    local _, whyNone = N.TravelSpellStepFrom(STEP, client)
    t.eq(whyNone, "map not confirmed", "no area name, and the map is not the English name")
    map = "Moonglade"
    t.eq(N.TravelSpellStepFrom(STEP, client).label, "Cast Teleport: Moonglade",
        "no area name read: the English name is the fallback")
    map, area = nil, nil
    local _, whyBoth = N.TravelSpellStepFrom(STEP, client)
    t.eq(whyBoth, "map not confirmed", "neither name read: no step")
    map, area = nil, "Mondlichtung"
    local _, whyMap = N.TravelSpellStepFrom(STEP, client)
    t.eq(whyMap, "map not confirmed", "the map's name not read: no step")
end

-- Section 623 item 2: the trainer row is matched by the spell's name as
-- the client says it, when the client says one.
T["from client: the trainer row is matched by the client's name for the spell"] = function(t)
    local store = { get = function(_, scope, path)
        if scope == "char" and path == N.TRAVEL_LISTS then
            return { a = { npc = "Turak Runentotem", rows = { { name = "Teleportieren: Mondlichtung" } } } }
        end
    end }
    local client = {
        class = function() return "DRUID" end,
        level = function() return 12 end,
        position = function() return { map = 1456, x = 0.4, y = 0.4 } end,
        mapName = function() return "Moonglade" end,
        spell = function() return { known = false, name = "Teleportieren: Mondlichtung" } end,
    }
    local want = N.TRAVEL_TAUGHT:format("Teleport: Moonglade: not learned yet", "Turak Runentotem")
    t.eq(N.TravelSpellStepFrom(STEP, client, store).hint, want, "the client's name finds the row")
    client.spell = function() return { known = false } end
    t.eq(N.TravelSpellStepFrom(STEP, client, store).hint, "Teleport: Moonglade: not learned yet",
        "no name from the client: the English name, which is not in this list")
end

T["planner: a step a cast away counts as legacy's ten-second cast"] = function(t)
    t.eq(N.TRAVEL_SPELL_YARDS, 120)
end

return T
