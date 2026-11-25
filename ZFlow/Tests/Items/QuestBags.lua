local _, ns = ...

-- Tests for ZFlow/Items/QuestBags.lua (S41): quest items in the bags.
-- Pure parts only; the whole add-on path is Tests/E2E/QuestBags.lua.
-- Unknown or unreadable data says nothing: never a guess.

local Q = ns.QuestBags
local tests = {}

local GNOLL = "Gnoll Paw"
local WOOD = "Bundle of Wood"
local PAW_ID, WOOD_ID = 725, 13872

local function row(id, title, objectives, complete)
    return { id = id, title = title, complete = complete == true, objectives = objectives or {} }
end

tests["quest bags: an item objective's name is read from its text"] = function(t)
    t.eq(Q.ObjectiveItem("Gnoll Paw: 3/8"), GNOLL)
    t.eq(Q.ObjectiveItem("Bundle of Wood: 0/1"), WOOD)
    t.eq(Q.ObjectiveItem("Speak with Marshal Dughan"), nil, "no count")
    t.eq(Q.ObjectiveItem(nil), nil, "no text")
    t.eq(Q.ObjectiveItem(": 1/2"), nil, "no name")
end

tests["quest bags: learning keeps which quests asked for each item"] = function(t)
    local owners = {}
    Q.Learn(owners, { row(1, "A", { { text = "Gnoll Paw: 3/8", done = false } }),
                      row(2, "B", { { text = "Gnoll Paw: 0/2", done = false }, { done = false } }) })
    t.eq(owners, { [GNOLL] = { [1] = "A", [2] = "B" } })
    Q.Learn(owners, nil)
    t.eq(owners, { [GNOLL] = { [1] = "A", [2] = "B" } }, "an unread log changes nothing")
end

local function bag(name, classID)
    return { { name = name, classID = classID } }
end

tests["quest bags: a quest item whose only quest was handed in is a leftover"] = function(t)
    local owners = { [GNOLL] = { [1] = "A" } }
    local done = function(id) return id == 1 end
    t.eq(Q.Leftovers(owners, {}, bag(GNOLL, 12), done), { GNOLL })
    t.eq(Q.LeftoverText({ GNOLL }), "Gnoll Paw is left over from a finished quest: you can sell or destroy it.")
    t.eq(Q.LeftoverText({ GNOLL, "Murloc Eye" }),
        "Gnoll Paw, Murloc Eye are left over from finished quests: you can sell or destroy them.")
    t.eq(Q.LeftoverText({}), nil)
end

tests["quest bags: no leftover when anything is not known or still wanted"] = function(t)
    local owners = { [GNOLL] = { [1] = "A", [2] = "B" } }
    local both = function() return true end
    t.eq(Q.Leftovers(owners, { row(2, "B") }, bag(GNOLL, 12), both), {}, "another quest in the log wants it")
    t.eq(Q.Leftovers(owners, {}, bag(GNOLL, 12), function(id) return id == 1 end), {}, "one quest not handed in")
    t.eq(Q.Leftovers(owners, {}, bag(GNOLL, 12), function() return nil end), {}, "hand-in not known")
    t.eq(Q.Leftovers(owners, {}, bag(GNOLL, nil), both), {}, "kind not read")
    t.eq(Q.Leftovers(owners, {}, bag(GNOLL, 7), both), {}, "not a quest item")
    t.eq(Q.Leftovers({}, {}, bag(GNOLL, 12), both), {}, "never seen asked for")
    t.eq(Q.Leftovers(owners, nil, bag(GNOLL, 12), both), {}, "log not read")
    t.eq(Q.Leftovers(owners, {}, nil, both), {}, "bags not read")
end

tests["quest bags: an objective item the open vendor sells is a buy line"] = function(t)
    local log = { row(5, "Stormwind Errand", { { text = "Bundle of Wood: 0/1", done = false } }) }
    local wares = { { name = WOOD }, { name = "Simple Flour" } }
    t.eq(Q.ToBuy(log, wares), { { item = WOOD, quest = "Stormwind Errand" } })
    t.eq(Q.BuyText(Q.ToBuy(log, wares)), "Buy Bundle of Wood from a vendor for the quest Stormwind Errand.")
    t.eq(Q.BuyText({}), nil)
end

tests["quest bags: no buy line for a done objective, a finished quest, or unread wares"] = function(t)
    local doneObj = { row(5, "S", { { text = "Bundle of Wood: 1/1", done = true } }) }
    t.eq(Q.ToBuy(doneObj, { { name = WOOD } }), {}, "objective done")
    local complete = { row(5, "S", { { text = "Bundle of Wood: 0/1", done = false } }, true) }
    t.eq(Q.ToBuy(complete, { { name = WOOD } }), {}, "quest complete")
    local open = { row(5, "S", { { text = "Bundle of Wood: 0/1", done = false } }) }
    t.eq(Q.ToBuy(open, nil), {}, "wares not read")
    t.eq(Q.ToBuy(open, { {} }), {}, "a ware with no name")
    t.eq(Q.ToBuy(nil, { { name = WOOD } }), {}, "log not read")
end

tests["quest bags: a ware's name comes from item facts, else the link"] = function(t)
    t.eq(Q.WareName({ item = "|cffffffff|Hitem:13872::|h[Bundle of Wood]|h|r" }, function() return nil end), WOOD)
    t.eq(Q.WareName({ item = WOOD_ID }, function() return { name = WOOD } end), WOOD)
    t.eq(Q.WareName({ item = PAW_ID }, function() return nil end), nil, "nothing known")
    t.eq(Q.WareName({}, function() return { name = WOOD } end), nil, "no item")
end

-- Parity row C-10 (lead section 664): for each quest item in the bags, why
-- you hold it and what to do with it. As Flow's Modules/Quests/QuestBags.lua
-- (QG.QuestOf :55-63: the quest an item is for, a finished one first; its
-- answers turnin, finish and sell). Fails before: there is no Q.Answers.
tests["quest bag answers: hand in, keep or drop, each with its quest"] = function(t)
    local owners = { [GNOLL] = { [1] = "Gnoll Trouble" }, ["Murloc Eye"] = { [2] = "Eyes" },
                     ["Old Key"] = { [3] = "The Key" } }
    local rows = { row(1, "Gnoll Trouble", { { text = "Gnoll Paw: 8/8", done = true } }, true),
                   row(2, "Eyes", { { text = "Murloc Eye: 2/8", done = false } }) }
    local bags = { { name = GNOLL, classID = 12 }, { name = "Murloc Eye", classID = 12 },
                   { name = "Old Key", classID = 12 }, { name = "Linen Cloth", classID = 7 } }
    local done = function(id) return id == 3 end
    t.eq(Q.Answers(owners, rows, bags, done), {
        { item = GNOLL, answer = "handIn", quest = "Gnoll Trouble", questId = 1 },
        { item = "Murloc Eye", answer = "keep", quest = "Eyes", questId = 2 },
        { item = "Old Key", answer = "drop", quest = "The Key", questId = 3 },
    }, "no row for what is no quest item")
end

tests["quest bag answers: a finished quest comes before one in progress, and an item is said once"] = function(t)
    local owners = { [GNOLL] = { [1] = "A", [2] = "B" } }
    local rows = { row(1, "A", { { text = "Gnoll Paw: 3/8", done = false } }),
                   row(2, "B", { { text = "Gnoll Paw: 2/2", done = true } }, true) }
    local bags = { { name = GNOLL, classID = 12 }, { name = GNOLL, classID = 12 } }
    t.eq(Q.Answers(owners, rows, bags, function() return nil end),
        { { item = GNOLL, answer = "handIn", quest = "B", questId = 2 } })
end

tests["quest bag answers: what is not known is said to be not known, never guessed"] = function(t)
    local bags = { { name = GNOLL, classID = 12 } }
    t.eq(Q.Answers({}, {}, bags, function() return true end), { { item = GNOLL, answer = "unknown" } },
        "no quest ever seen asking for it")
    local owners = { [GNOLL] = { [1] = "A" } }
    t.eq(Q.Answers(owners, {}, bags, function() return nil end),
        { { item = GNOLL, answer = "unknown", quest = "A", questId = 1 } }, "left the log, hand-in not known")
    t.eq(Q.Answers(owners, {}, bags, function() return false end)[1].answer, "unknown", "left the log, not handed in")
    t.eq(Q.Answers(owners, nil, bags, function() return true end), {}, "log not read: nothing")
    t.eq(Q.Answers(owners, {}, nil, function() return true end), {}, "bags not read: nothing")
    t.eq(Q.Answers(owners, {}, { { name = GNOLL } }, function() return true end), {}, "item kind not read")
    t.eq(Q.Answers(owners, {}, bags, nil), {}, "no hand-in read")
end

tests["quest bag answers: a quest that failed is no hand-in"] = function(t)
    local owners = { [GNOLL] = { [1] = "A" } }
    local failed = row(1, "A", { { text = "Gnoll Paw: 8/8", done = true } }, true)
    failed.failed = true
    t.eq(Q.Answers(owners, { failed }, { { name = GNOLL, classID = 12 } }, function() return nil end)[1].answer,
        "keep")
end

tests["quest bag answers: the line for each answer, and the hand-in prompt"] = function(t)
    t.eq(Q.AnswerLine({ item = GNOLL, answer = "handIn", quest = "Gnoll Trouble" }),
        "Gnoll Paw: for Gnoll Trouble, which is ready to hand in. Hand it in.")
    t.eq(Q.AnswerLine({ item = GNOLL, answer = "keep", quest = "Gnoll Trouble" }),
        "Gnoll Paw: for Gnoll Trouble, still in progress. Keep it.")
    t.eq(Q.AnswerLine({ item = GNOLL, answer = "drop", quest = "Gnoll Trouble" }),
        "Gnoll Paw: left over from Gnoll Trouble, which you handed in. You can sell or destroy it.")
    t.eq(Q.AnswerLine({ item = GNOLL, answer = "unknown" }),
        "Gnoll Paw: a quest item, but which quest it is for is not known.")
    t.eq(Q.AnswerLine({ item = GNOLL, answer = "unknown", quest = "A" }),
        "Gnoll Paw: for A, which is not in your log; whether you handed it in is not known.")
    t.eq(Q.AnswerLine(nil), nil)
    t.eq(Q.HandInText({ { item = GNOLL, answer = "handIn", quest = "Gnoll Trouble" },
                        { item = "Murloc Eye", answer = "keep", quest = "Eyes" } }),
        "Gnoll Paw is for Gnoll Trouble, which is ready to hand in.")
    t.eq(Q.HandInText({ { item = GNOLL, answer = "handIn", quest = "A" }, { item = "Eye", answer = "handIn", quest = "B" } }),
        "Quest items ready to hand in: Gnoll Paw (A), Eye (B).")
    t.eq(Q.HandInText({ { item = GNOLL, answer = "keep", quest = "A" } }), nil)
    t.eq(Q.HandInText(nil), nil)
end

return tests
