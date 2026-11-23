local _, ns = ...
-- Tests for ZFlow/Spells/ClassQuests.lua (lead section 242, DRUID-2): the
-- pure parts, the class-quest spells of a pack, the quests that left the
-- log and the words shown.
local tests = {}
local function M() return ns.ClassQuests or {} end

tests["class quests: the spells a pack marks as class quests, lowest level first"] = function(t)
    local pack = { spells = {
        ["Aquatic Form"] = { level = 16, note = "class quest" },
        ["Bear Form"] = { level = 10, note = "class quest" },
        ["Moonfire"] = { level = 4 },
        ["No Level"] = { note = "class quest" },
    } }
    local spells = M().Spells or function() return nil end
    t.eq(spells(pack), { { name = "Bear Form", level = 10 }, { name = "Aquatic Form", level = 16 } })
    t.eq(spells(nil), {})
end

tests["class quests: the rows that left the log"] = function(t)
    local gone = M().Gone or function() return nil end
    local before = { { id = 1, title = "A" }, { id = 2, title = "B" }, { id = 3, title = "C" } }
    local now = { { id = 2, title = "B" } }
    t.eq(gone(before, now), { { id = 1, title = "A" }, { id = 3, title = "C" } })
    t.eq(gone(nil, now), {})
    t.eq(gone(before, nil), {}, "a log not read says nothing left")
end

tests["class quests: the words for one spell"] = function(t)
    local text = M().Text or function() return nil end
    local spell = { name = "Bear Form", level = 10 }
    t.eq(text(spell, {}, {}), "Bear Form: ask your class trainer at level 10")
    local kept = { [7] = { title = "Q", spell = "Bear Form" }, [8] = { title = "R", spell = "Aquatic Form" } }
    t.eq(text(spell, kept, {}), "Bear Form: ask your class trainer for Q")
    t.eq(text(spell, kept, { [7] = true }), "Bear Form: Q is in your quest log")
    t.eq(text({ name = "Cat Form", level = 20 }, kept, {}), "Cat Form: ask your class trainer at level 20")
end

return tests
