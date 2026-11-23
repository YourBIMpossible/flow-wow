-- N23 (lead section 274 item 2): the skill a profession trainer recipe
-- needs is kept with the trainer list and said in its lines. Pure.
local _, ns = ...

local tests = {}

local ALL = { available = true, unavailable = true, known = true }

local function reading(rows)
    return { npc = "Brenda", profession = "Tailoring", services = rows, filter = ALL }
end

tests["trainer list: the skill a recipe needs is kept"] = function(t)
    local T = ns.TrainerList
    local lists = T.Record({}, reading({
        { name = "Linen Belt", state = "available", cost = 50, skill = 25 },
        { name = "Red Linen Robe", state = "unavailable", skill = 40 },
    }), 10)
    local e = lists[T.Key("Brenda", "Tailoring")]
    if type(e) ~= "table" then t.ok(false, "kept"); return end
    t.eq(e.rows[1].skill, 25)
    t.eq(e.rows[2].skill, 40)
end

tests["trainer list: a skill that is not a whole number drops the reading"] = function(t)
    local T = ns.TrainerList
    local lists = T.Record({}, reading({ { name = "Linen Belt", state = "available", skill = 2.5 } }), 10)
    t.eq(lists[T.Key("Brenda", "Tailoring")], nil)
end

tests["trainer list: the lines say the skill"] = function(t)
    local T = ns.TrainerList
    local lists = T.Record({}, reading({
        { name = "Red Linen Robe", state = "unavailable", level = 10, skill = 40 },
        { name = "Linen Belt", state = "available" },
    }), 10)
    local lines = T.Lines(lists[T.Key("Brenda", "Tailoring")])
    t.eq(lines[1], "Red Linen Robe, level 10, skill 40, " .. T.PRICE_UNKNOWN .. ": not yet")
    t.eq(lines[2], "Linen Belt, " .. T.PRICE_UNKNOWN .. ": can learn", "no skill: nothing said")
end

return tests
