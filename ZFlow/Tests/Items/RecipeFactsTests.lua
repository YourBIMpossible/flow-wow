local _, ns = ...
-- Lead section 406 item 3: the profession plan reads recipe facts through
-- ns.RecipeFacts, seen in game first, then the shipped table (empty as
-- shipped). Made-up recipes, trainers and skills; not tested in game.
local tests = {}

local RF = ns.RecipeFacts
local P = ns.ProfPlan

local function store(data)
    return { get = function(_, scope, path) return data[scope .. ":" .. path] end }
end

local function seenOnly()
    return store({
        ["char:learned.facts.recipeBook"] = { ["Rough Thing"] = { profession = "Tailoring" } },
        ["char:learned.trainerLists"] = { Ann = { profession = "Tailoring", npc = "Ann",
            rows = { { name = "Rough Thing", skill = 1, state = "known" }, { name = "Red Thing", skill = 40 } } } },
    })
end

tests["recipe facts: the shipped table ships empty"] = function(t)
    t.eq(RF.SHIPPED, {})
end

tests["recipe facts: with the shipped table empty, the plan reads what was seen"] = function(t)
    local s = seenOnly()
    local facts = RF.Read(s)
    t.eq(facts.book, s:get("char", "learned.facts.recipeBook"))
    t.eq(facts.trainerLists, s:get("char", "learned.trainerLists"))
end

tests["recipe facts: nothing seen and nothing shipped is nil, never empty"] = function(t)
    local facts = RF.Read(store({}))
    t.eq(facts.book, nil)
    t.eq(facts.trainerLists, nil)
end

tests["recipe facts: shipped rows fill in after the seen ones and never replace them"] = function(t)
    local shipped = { Tailoring = {
        { name = "Red Thing", skill = 35 },
        { name = "Rough Thing", skill = 1 },
        { name = "Blue Thing", skill = 70 },
        { name = "Odd" },
    } }
    local facts = RF.Read(seenOnly(), shipped)
    t.eq(facts.trainerLists.Ann.rows[2], { name = "Red Thing", skill = 40 }, "the seen row stands")
    t.eq(facts.trainerLists[RF.SHIPPED_KEY:format("Tailoring")],
        { profession = "Tailoring", rows = { { name = "Blue Thing", skill = 70 } } },
        "only the row no seen list has; a row with no skill is left out")
end

tests["recipe facts: a shipped recipe already in the book reads as known"] = function(t)
    local facts = RF.Read(store({ ["char:learned.facts.recipeBook"] = { Cloth = { profession = "Tailoring" } } }),
        { Tailoring = { { name = "Cloth", skill = 1 }, { name = "Bolt", skill = 5 } } })
    t.eq(facts.trainerLists[RF.SHIPPED_KEY:format("Tailoring")].rows,
        { { name = "Cloth", skill = 1, state = "known" }, { name = "Bolt", skill = 5 } })
end

tests["recipe facts: a shipped row reaches the plan as a learn step with no trainer named"] = function(t)
    local facts = RF.Read(store({ ["char:learned.facts.recipeBook"] = {} }),
        { Tailoring = { { name = "Bolt", skill = 5 } } })
    local steps = P.Plan({ prof = "Tailoring", skill = 10, max = 75, book = facts.book,
        trainerLists = facts.trainerLists, bags = {}, bank = {} })
    t.eq(steps[1] and steps[1].kind, "learn_recipe")
    t.eq(steps[1] and steps[1].recipe, "Bolt")
    t.eq(steps[1] and steps[1].npc, nil)
end

tests["recipe facts: the plan's input is built through the interface"] = function(t)
    local input = P.Input(nil, seenOnly(), "Tailoring")
    t.eq(input.trainerLists.Ann.npc, "Ann")
    t.eq(input.book["Rough Thing"].profession, "Tailoring")
end

return tests
