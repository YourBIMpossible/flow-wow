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
    -- Lead section 776: a reservation hold is not a route step unless a
    -- route stop names it (StepFor no longer takes holds).
    t.eq(TW().StepFor("Copper Bar", 88, VIEW, ROWS), nil, "no stop names it: not a route step")
    t.eq(TW().StepFor("Gnoll Paw", 1, nil, ROWS, nil), nil, "no route")
end

tests["take out why: fills the bank list, the route first, as copies"] = function(t)
    if type(TW()) ~= "table" then return t.ok(false, "not loaded") end
    local bank = { { key = 77, name = "Dig Rat", count = 8 }, { key = 5, name = "Gnoll Paw", count = 4 },
                   { key = 6, name = "Silk", count = 1 } }
    local out = TW().Fill(bank, VIEW, ROWS)
    t.eq(out[1].step, "Hand in Rat Catcher")
    t.eq(out[1].quest, "Rat Catcher", "the quest too; the rows put the route first")
    t.eq({ out[2].step, out[2].quest }, { nil, "Wanted: Gnolls" })
    t.eq({ out[3].step, out[3].quest }, { nil, nil })
    t.eq(bank[1].step, nil, "the list given is not changed")
    t.eq(TW().Fill(nil, VIEW, ROWS), {})
end

-- Lead section 776 (Twin): a thing the reservations hold in the bank that
-- no route stop names gets the reservation's own reason, from its claim
-- (Items/Resources.lua: owner, activity). Fails before: every hold was
-- called a route step.
local function grant(key, activity, bank)
    return { claim = { kind = "item", key = key, owner = activity .. ":" .. key, activity = activity, amount = bank },
             got = bank, from = { bags = 0, bank = bank } }
end

tests["take out why: a hold no stop names says the reservation's own reason"] = function(t)
    if type(TW()) ~= "table" then return t.ok(false, "not loaded") end
    local grants = { grant(88, "goal", 2), grant(90, "goal", 0), grant(91, "professions", 3) }
    t.eq(TW().HoldFor(88, grants), TW().REASONS.goal, "an item goal of yours")
    t.eq(TW().HoldFor(90, grants), nil, "nothing held in the bank")
    t.eq(TW().HoldFor(91, grants), TW().HELD_FOR:format("professions"), "another activity, by its name")
    t.eq(TW().HoldFor(92, grants), nil)
    t.eq(TW().HoldFor(88, nil), nil)
    local out = TW().Fill({ { key = 88, name = "Copper Bar", count = 2 } }, VIEW, ROWS, grants)
    t.eq({ out[1].step, out[1].hold }, { nil, TW().REASONS.goal })
end

-- e22-held follow-up (lead section 851): a claim that names no activity
-- (or an empty one) still says it is held, with the general word, never a
-- blank reason.
tests["take out why: a hold whose claim has no activity says held for something"] = function(t)
    if type(TW()) ~= "table" then return t.ok(false, "not loaded") end
    local none = { claim = { kind = "item", key = 93, owner = "x:93", amount = 1 }, got = 1, from = { bags = 0, bank = 1 } }
    local empty = { claim = { kind = "item", key = 94, owner = "x:94", activity = "", amount = 1 }, got = 1, from = { bags = 0, bank = 1 } }
    local said = TW().HELD_FOR:format(TW().SOMETHING)
    t.eq(TW().HoldFor(93, { none }), said, "no activity")
    t.eq(TW().HoldFor(94, { empty }), said, "an empty activity")
end

tests["banker rows: a held thing is taken out with the hold's reason, after the route and quests"] = function(t)
    local BR = ns.BankerRows
    local keep = { action = "keep", rule = "keepRule" }
    local rows = BR.SellRows({}, { { key = 88, name = "Copper Bar", count = 2, hold = "for one of your item goals",
                                     decision = keep } })
    t.eq(rows[1] and { rows[1].take, rows[1].reason, rows[1].next }, { "hold", "for one of your item goals", nil })
end

return tests
