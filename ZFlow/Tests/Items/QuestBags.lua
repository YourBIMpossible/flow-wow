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

return tests
