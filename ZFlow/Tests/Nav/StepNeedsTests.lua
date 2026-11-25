local _, ns = ...

-- Tests for ZFlow/Nav/StepNeeds.lua (FLOW-PARITY A2-17): why a quest is
-- locked, in words, from Questie's pre-quest and spell fields. Pure.
-- Made-up quests and spells.

local tests = {}

local function SN() return ns.Nav.StepNeeds end

local NAMES = { [10] = "Bear Lessons", [11] = "First Part", [12] = "Other Part" }
local SPELLS = { [500] = "Bear Form" }

local function ctx(done, known, log)
    return {
        done = function(id) return done[id] end,
        log = log or {},
        questName = function(id) return NAMES[id] end,
        spellKnown = function(id) return known[id] end,
        spellName = function(id) return SPELLS[id] end,
    }
end

tests["step needs: a quest with nothing before it is not locked"] = function(t)
    t.eq(SN().Why({ Id = 1 }, ctx({}, {})), nil)
    t.eq(SN().Why(nil, ctx({}, {})), nil)
end

tests["step needs: every quest of a group must be done; the first not done is named"] = function(t)
    local q = { Id = 1, preQuestGroup = { 10, 11 } }
    t.eq(SN().Why(q, ctx({ [10] = true, [11] = false }, {})), { kind = "quest", id = 11, text = "after First Part" })
    t.eq(SN().Why(q, ctx({ [10] = true, [11] = true }, {})), nil)
end

tests["step needs: one of several earlier quests is enough"] = function(t)
    local q = { Id = 1, preQuestSingle = { 11, 12 } }
    t.eq(SN().Why(q, ctx({ [11] = false, [12] = true }, {})), nil)
    local why = SN().Why(q, ctx({ [11] = false, [12] = false }, {}))
    t.eq(why and why.text, "after First Part or Other Part")
end

tests["step needs: an earlier quest in your log says so"] = function(t)
    local why = SN().Why({ Id = 1, preQuestGroup = { 10 } }, ctx({ [10] = false }, {}, { [10] = true }))
    t.eq(why and why.text, "after Bear Lessons (in your log)")
end

tests["step needs: an earlier quest with no name is still said"] = function(t)
    local why = SN().Why({ Id = 1, preQuestGroup = { 99 } }, ctx({ [99] = false }, {}))
    t.eq(why and why.text, "after an earlier quest")
end

tests["step needs: whether a quest is done not known: not held"] = function(t)
    t.eq(SN().Why({ Id = 1, preQuestGroup = { 10 } }, ctx({}, {})), nil)
end

tests["step needs: a spell you do not know is named; one you know, or not known, does not hold"] = function(t)
    local q = { Id = 1, requiredSpell = 500 }
    t.eq(SN().Why(q, ctx({}, { [500] = false })), { kind = "spell", id = 500, text = "after you learn Bear Form" })
    t.eq(SN().Why(q, ctx({}, { [500] = true })), nil)
    t.eq(SN().Why(q, ctx({}, {})), nil, "the game cannot say: not held")
    local why = SN().Why({ Id = 1, requiredSpell = 501 }, ctx({}, { [501] = false }))
    t.eq(why and why.text, "after you learn a spell")
    t.eq(SN().Why({ Id = 1, requiredSpell = 0 }, ctx({}, {})), nil)
    t.eq(SN().Why({ Id = 1, requiredSpell = -500 }, ctx({}, { [500] = false })), nil, "a spell you must not have is not a need")
end

tests["step needs: the earlier quest comes before the spell"] = function(t)
    local why = SN().Why({ Id = 1, preQuestGroup = { 10 }, requiredSpell = 500 }, ctx({ [10] = false }, { [500] = false }))
    t.eq(why and why.kind, "quest")
end

tests["step needs: the line for a locked step"] = function(t)
    t.eq(SN().Line("Maul Practice", { text = "after you learn Bear Form" }), "Maul Practice (after you learn Bear Form)")
    t.eq(SN().Line("Maul Practice", nil), "Maul Practice")
end

return tests
