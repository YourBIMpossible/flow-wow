-- P-PROF slice 2 (Lazy, zflow-prof-lz-2): the game's "you learn" line marks
-- the recipe known in the recipe book, as Flow's Recipes MarkKnown and
-- LearnedName. Pure: the line, the client's text and the book come in.
local _, ns = ...
local FMT = "You have learned how to create a new item: %s."

return {
    ["recipe learned: the name from the line"] = function(t)
        local R = ns.RecipeLearned
        t.eq(R.Name("You have learned how to create a new item: Spiced Wolf Ribs.", FMT), "Spiced Wolf Ribs")
        t.eq(R.Name("You have learned how to create a new item: Spiced Wolf Ribs.", nil), "Spiced Wolf Ribs", "the English text when the client has none")
        t.eq(R.Name("You receive loot: Rough Stone.", FMT), nil, "another line")
        t.eq(R.Name(nil, FMT), nil, "no line")
    end,
    ["recipe learned: marked in the book, kept when already there"] = function(t)
        local R = ns.RecipeLearned
        local book = { ["Linen Bandage"] = { id = 7, makes = 1251 } }
        local out = R.Mark(book, "Spiced Wolf Ribs")
        t.eq(out["Spiced Wolf Ribs"], { learned = true, partial = true }, "known, not read")
        t.eq(out["Linen Bandage"].id, 7, "others kept")
        t.eq(book["Spiced Wolf Ribs"], nil, "the book handed in is not changed")
        t.eq(R.Mark(book, "Linen Bandage"), nil, "already saved: nothing to write")
        t.eq(R.Mark(nil, "Spiced Wolf Ribs")["Spiced Wolf Ribs"].learned, true, "no book yet")
    end,
    ["recipe learned: a marked recipe is no prompt to learn it"] = function(t)
        local book = ns.RecipeLearned.Mark({}, "Spiced Wolf Ribs")
        local p = ns.ProfLearn.Prompts({ { item = 501, count = 1 } }, function() return "Recipe: Spiced Wolf Ribs" end, book)
        t.eq(#p, 0)
    end,
}
