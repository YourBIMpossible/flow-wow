local _, ns = ...
-- Lead section 774.2: who wants a bank thing, for the banker's take-out
-- rows (Items/BankerRows.lua e.step and e.quest), as Flow's Banker.lua
-- B.TakeOut callbacks: quest(id) (QuestBags.lua QG.NeededHere :419-428, a
-- quest in your log still needing it) and route(id) (B.RouteFetch /
-- B.FetchBy :228-241, a step on your route that uses it; "a step on your
-- route" when its words aren't known). From existing reads only: the quest
-- log's rows (Nav.QuestLogRows), TripRoute's View and the reservations'
-- bank holds. Pure; made-up quests and items. Fails before: no file.
local tests = {}

local function TW() return ns.TakeOutWhy end

local ROWS = {
    { id = 1, title = "Wanted: Gnolls", complete = false, objectives = { { text = "Gnoll Paw: 2/8", done = false } } },
    { id = 2, title = "Old Boots", complete = false, objectives = { { text = "Old Boot: 1/1", done = true } } },
    { id = 3, title = "Rat Catcher", complete = false, objectives = { { text = "Dig Rat: 0/8", done = false } } },
}
local VIEW = { stops = { { label = "Hand in Rat Catcher", quest = 3, place = { map = 1, x = 0.5, y = 0.5 } } } }

tests["take out why: a quest in your log that still needs it"] = function(t)
    t.eq(type(TW()), "table", "loaded")
    if type(TW()) ~= "table" then return end
    t.eq(TW().QuestFor("Gnoll Paw", ROWS), "Wanted: Gnolls")
    t.eq(TW().QuestFor("Old Boot", ROWS), nil, "its objective is done")
    t.eq(TW().QuestFor("Silk", ROWS), nil)
    t.eq(TW().QuestFor(nil, ROWS), nil)
    local done = { { id = 9, title = "Done", complete = true, objectives = { { text = "Silk: 1/2", done = false } } } }
    t.eq(TW().QuestFor("Silk", done), nil, "a quest ready to hand in needs nothing more")
end

tests["take out why: a step on your route that uses it, by its words, else plain"] = function(t)
    if type(TW()) ~= "table" then return t.ok(false, "not loaded") end
    t.eq(TW().StepFor("Dig Rat", 77, VIEW, ROWS, nil), "Hand in Rat Catcher", "the step whose quest needs it")
    local held = { Held = function(_, key) if key == 88 then return 2 end return 0 end }
    t.eq(TW().StepFor("Copper Bar", 88, VIEW, ROWS, held), TW().ON_ROUTE, "held for a step, words not known")
    t.eq(TW().StepFor("Copper Bar", 89, VIEW, ROWS, held), nil)
    t.eq(TW().StepFor("Gnoll Paw", 1, nil, ROWS, nil), nil, "no route")
end

tests["take out why: fills the bank list, the route first, as copies"] = function(t)
    if type(TW()) ~= "table" then return t.ok(false, "not loaded") end
    local bank = { { key = 77, name = "Dig Rat", count = 8 }, { key = 5, name = "Gnoll Paw", count = 4 },
                   { key = 6, name = "Silk", count = 1 } }
    local out = TW().Fill(bank, VIEW, ROWS, nil)
    t.eq(out[1].step, "Hand in Rat Catcher")
    t.eq(out[1].quest, "Rat Catcher", "the quest too; the rows put the route first")
    t.eq({ out[2].step, out[2].quest }, { nil, "Wanted: Gnolls" })
    t.eq({ out[3].step, out[3].quest }, { nil, nil })
    t.eq(bank[1].step, nil, "the list given is not changed")
    t.eq(TW().Fill(nil, VIEW, ROWS, nil), {})
end

return tests
