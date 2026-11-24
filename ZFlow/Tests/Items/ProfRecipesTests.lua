local _, ns = ...

-- Tests for ZFlow/Items/ProfRecipes.lua (P-COACH C4, DISPATCH 382-384):
-- where a missing recipe comes from, as steps in the 382 contract shape
-- { kind, text, item, count, target }. Pure: facts are made up.

local tests = {}

local SHIRT = { name = "Stylish Blue Shirt", profession = "Tailoring", item = 6390 }

local function names(key)
    if key == 6390 then return "Pattern: Stylish Blue Shirt" end
    if key == 2589 then return "Linen Cloth" end
    return nil
end

local function trainerFacts(state, skill)
    return {
        trainerLists = {
            ["Tailoring:Sewa"] = { npc = "Sewa", profession = "Tailoring", rows = {
                { name = "Bolt of Linen Cloth", state = "known" },
                { name = "Stylish Blue Shirt", state = state, cost = 200, skill = skill },
            } },
        },
        npcs = { Sewa = { map = 1411, x = 0.45, y = 0.62, roles = { trainer = true } } },
    }
end

local function shape(t, s, what)
    t.ok(type(s) == "table", what .. ": a step")
    t.ok(type(s.kind) == "string" and type(s.text) == "string" and s.text ~= "", what .. ": kind and text")
    t.ok(s.target == nil or (type(s.target.map) == "number" and type(s.target.x) == "number"
        and type(s.target.y) == "number"), what .. ": target is {map,x,y} or nil")
    t.ok(not s.text:find("%d%d%d%d"), what .. ": no item numbers in the text")
end

tests["prof recipes: a recipe in your bags says right-click it to learn it"] = function(t)
    local steps = ns.ProfRecipes.Steps(SHIRT, { stacks = { { item = 6390, count = 1 } }, nameOf = names })
    t.eq(#steps, 1, "one step")
    shape(t, steps[1], "bags")
    t.eq(steps[1].kind, "learn_recipe", "learn it")
    t.eq(steps[1].text, "Pattern: Stylish Blue Shirt is in your bags: right-click it to learn it.", "plain sentence")
    t.eq(steps[1].item, 6390, "the recipe item")
    t.eq(steps[1].count, 1, "one")
    t.eq(steps[1].target, nil, "bags need no arrow")
end

tests["prof recipes: a recipe in your bags is found by name when the item is not given"] = function(t)
    local steps = ns.ProfRecipes.Steps({ name = "Stylish Blue Shirt", profession = "Tailoring" },
        { stacks = { { item = 2589, count = 4 }, { item = 6390, count = 1 } }, nameOf = names })
    t.eq(steps[1] and steps[1].kind, "learn_recipe", "found by name")
    t.eq(steps[1] and steps[1].item, 6390, "and points at the item")
end

tests["prof recipes: a seen trainer gives the name, the cost and where it stands"] = function(t)
    local steps = ns.ProfRecipes.Steps(SHIRT, trainerFacts("available"))
    t.eq(#steps, 1, "one step")
    shape(t, steps[1], "trainer")
    t.eq(steps[1].kind, "learn_recipe", "learn it")
    t.eq(steps[1].text, "Learn Stylish Blue Shirt from Sewa, your Tailoring trainer, for 2s.", "plain sentence")
    t.eq(steps[1].target and steps[1].target.map, 1411, "the arrow goes to the trainer seen")
    t.eq(steps[1].target and steps[1].target.x, 0.45, "at the place seen")
end

tests["prof recipes: a trainer never seen in the world has no target, no guessed place"] = function(t)
    local f = trainerFacts("available")
    f.npcs = nil
    local steps = ns.ProfRecipes.Steps(SHIRT, f)
    t.eq(steps[1] and steps[1].kind, "learn_recipe", "still learn it")
    t.eq(steps[1] and steps[1].target, nil, "no coordinates")
end

tests["prof recipes: a recipe the trainer has but you cannot learn yet says the skill"] = function(t)
    local steps = ns.ProfRecipes.Steps(SHIRT, trainerFacts("unavailable", 110))
    t.eq(steps[1] and steps[1].text,
        "Learn Stylish Blue Shirt from Sewa, your Tailoring trainer, for 2s, once your Tailoring is 110.", "says when")
end

tests["prof recipes: a recipe you already know gives no step"] = function(t)
    t.eq(#ns.ProfRecipes.Steps(SHIRT, trainerFacts("known")), 0, "nothing to do")
end

tests["prof recipes: only a vendor actually seen, with the price seen"] = function(t)
    local book = {}
    ns.Prices.Record(book, 6390, "vendor", 400, { source = "merchant window", seenAt = 1 })
    local steps = ns.ProfRecipes.Steps(SHIRT, { prices = book, nameOf = names })
    t.eq(#steps, 1, "one step")
    shape(t, steps[1], "vendor")
    t.eq(steps[1].kind, "buy_vendor", "buy it")
    t.eq(steps[1].text, "A vendor you visited sells Pattern: Stylish Blue Shirt for 4s: buy it, then right-click it to learn it.", "plain sentence")
    t.eq(steps[1].item, 6390, "the recipe item")
    t.eq(steps[1].target, nil, "the vendor place is not saved: no guess")
    t.eq(#ns.ProfRecipes.Steps(SHIRT, { prices = {}, nameOf = names }) , 1, "no price seen: only the unknown step")
    t.eq(ns.ProfRecipes.Steps(SHIRT, { prices = {}, nameOf = names })[1].kind, "learn_recipe", "not a vendor step")
end

tests["prof recipes: bags first, then the trainer, then the vendor"] = function(t)
    local f = trainerFacts("available")
    f.stacks, f.nameOf, f.prices = { { item = 6390, count = 1 } }, names, {}
    ns.Prices.Record(f.prices, 6390, "vendor", 400, { seenAt = 1 })
    local steps = ns.ProfRecipes.Steps(SHIRT, f)
    t.eq(#steps, 3, "three sources")
    t.eq(steps[1].text:find("in your bags", 1, true) ~= nil, true, "bags first")
    t.eq(steps[2].text:find("from Sewa", 1, true) ~= nil, true, "trainer second")
    t.eq(steps[3].kind, "buy_vendor", "vendor last")
end

tests["prof recipes: nothing known says the one thing to do so it will know"] = function(t)
    local steps = ns.ProfRecipes.Steps(SHIRT, {})
    t.eq(#steps, 1, "never silent")
    shape(t, steps[1], "unknown")
    t.eq(steps[1].kind, "learn_recipe", "a learn step")
    t.eq(steps[1].text, "Z-Flow does not know where to learn Stylish Blue Shirt yet: talk to your Tailoring trainer once so it can check.", "plain sentence")
    t.eq(steps[1].target, nil, "no guessed place")
    t.eq(#ns.ProfRecipes.Steps(SHIRT), 1, "no facts at all: the same")
end

tests["prof recipes: a recipe that is not one gives no step and no error"] = function(t)
    t.eq(#ns.ProfRecipes.Steps(nil, {}), 0, "nil")
    t.eq(#ns.ProfRecipes.Steps({ profession = "Tailoring" }, {}), 0, "no name")
    t.eq(#ns.ProfRecipes.Steps("Stylish Blue Shirt", {}), 0, "not a table")
end

tests["prof recipes: the trainer list of another profession is not used"] = function(t)
    local f = trainerFacts("available")
    f.trainerLists["Tailoring:Sewa"].profession = "Leatherworking"
    local steps = ns.ProfRecipes.Steps(SHIRT, f)
    t.eq(steps[1] and steps[1].text:find("Sewa", 1, true), nil, "not that trainer")
end

return tests
