local _, ns = ...

-- Tests for the outgrown food and drink rule in ZFlow/Items/Disposition.lua
-- (G5), ported from Flow's Modules/Items/Disposition.lua:656-724
-- (outgrownConsumable, order 22). Pure: the items, the bags and the reads are
-- made up. Nothing is sold anywhere in here.

local D = ns.Disposition
local tests = {}

local JERKY, HAUNCH, CHEESE, WATER, MILK, STEW, POTION, CLOTH = 117, 2287, 422, 159, 1179, 5525, 118, 2589
local EAT = "Use: Restores 61 health over 18 sec. Must remain seated while eating."
local DRINK = "Use: Restores 151 mana over 18 sec. Must remain seated while drinking."
local FED = "Use: Restores 243 health over 21 sec. Must remain seated while eating. "
    .. "If you spend at least 10 seconds eating you will become well fed and gain 4 Stamina and Spirit for 15 min."

local function food(key, extra)
    local i = { key = key, name = "Some Food", count = 4, quality = 1, sellPrice = 6, classID = 0 }
    for k, v in pairs(extra or {}) do i[k] = v end
    return i
end

-- What the player carries: 4 Tough Jerky (level 1) and 12 Haunch of Meat (level 15).
local function carried(extra)
    local f = {
        [JERKY] = { kind = "food", minLevel = 1, count = 4, buffFood = false },
        [HAUNCH] = { kind = "food", minLevel = 15, count = 12, buffFood = false },
    }
    for k, v in pairs(extra or {}) do f[k] = v end
    return f
end

local function ruleOf(key)
    for idx, r in ipairs(D.RULES) do
        if r.key == key then return r, idx end
    end
    return nil
end

-- ------------------------------------------------------------- the rule itself

tests["outgrown: the rule is there, at Flow's order, just after junk"] = function(t)
    local r, at = ruleOf("outgrownConsumable")
    t.ok(r ~= nil, "the rule is there")
    if not r then return end
    t.eq(r.order, 22, "Flow's order")
    local _, junk = ruleOf("junk")
    t.eq(at, junk + 1, "listed right after junk, so the list stays in rising order")
    t.eq(D.KEEP_BETTER, 10, "how many of the better tier it takes")
    t.eq(D.TIER_STEP, 5, "how many levels make a better tier")
end

tests["outgrown: food is sold when you carry 10 or more of a better food"] = function(t)
    local d = D.Decide(food(JERKY), { consumables = carried(), level = 20 })
    t.eq(d.action, "sell")
    t.eq(d.rule, "outgrownConsumable")
    t.eq(d.reason, "outgrown: you carry 10+ better food")
    t.eq(d.basis, "recommendation")
    t.eq(d.count, 4, "all four of them")
end

tests["outgrown: the better food itself is not outgrown"] = function(t)
    local d = D.Decide(food(HAUNCH, { count = 12 }), { consumables = carried(), level = 20 })
    t.ok(d.rule ~= "outgrownConsumable", "nothing better is carried")
    t.ok(d.action ~= "sell", "so it is not sold")
end

tests["outgrown: fewer than 10 of the better food keeps it"] = function(t)
    local c = { consumables = carried({ [HAUNCH] = { kind = "food", minLevel = 15, count = 9, buffFood = false } }),
                level = 20 }
    local d = D.Decide(food(JERKY), c)
    t.ok(d.rule ~= "outgrownConsumable", "nine is not enough")
    t.ok(d.action ~= "sell", "not sold")
    c.consumables[HAUNCH].count = nil
    t.ok(D.Decide(food(JERKY), c).action ~= "sell", "a count that is not known is not enough either")
end

tests["outgrown: a food less than 5 levels better keeps it"] = function(t)
    local c = { consumables = carried({ [HAUNCH] = { kind = "food", minLevel = 5, count = 12, buffFood = false } }),
                level = 20 }
    t.ok(D.Decide(food(JERKY), c).action ~= "sell", "1 to 5 is four levels: the same tier")
    c.consumables[HAUNCH].minLevel = 6
    t.eq(D.Decide(food(JERKY), c).action, "sell", "1 to 6 is five levels: a better tier")
end

tests["outgrown: a better food above your level does not count"] = function(t)
    local c = { consumables = carried(), level = 14 }
    t.ok(D.Decide(food(JERKY), c).action ~= "sell", "you can't eat the level 15 food at 14")
    c.level = 15
    t.eq(D.Decide(food(JERKY), c).action, "sell", "at 15 you can")
end

tests["outgrown: well fed food is never outgrown"] = function(t)
    local c = { consumables = carried({ [JERKY] = { kind = "food", minLevel = 1, count = 4, buffFood = true } }),
                level = 20 }
    local d = D.Decide(food(JERKY), c)
    t.ok(d.rule ~= "outgrownConsumable", "no opinion on buff food")
    t.ok(d.action ~= "sell", "not sold")
end

tests["outgrown: food whose buff is not known is never sold"] = function(t)
    local c = { consumables = carried({ [JERKY] = { kind = "food", minLevel = 1, count = 4 } }), level = 20 }
    local d = D.Decide(food(JERKY), c)
    t.ok(d.rule ~= "outgrownConsumable", "no opinion")
    t.ok(d.action ~= "sell", "not sold")
end

tests["outgrown: drink is weighed against drink, food against food"] = function(t)
    local c = { level = 20, consumables = {
        [JERKY] = { kind = "food", minLevel = 1, count = 4, buffFood = false },
        [WATER] = { kind = "drink", minLevel = 1, count = 3 },
        [MILK] = { kind = "drink", minLevel = 15, count = 20 },
    } }
    t.ok(D.Decide(food(JERKY), c).action ~= "sell", "20 better drinks say nothing about food")
    local d = D.Decide(food(WATER, { count = 3 }), c)
    t.eq(d.action, "sell", "the weaker drink is outgrown")
    t.eq(d.rule, "outgrownConsumable")
    t.eq(d.reason, "outgrown: you carry 10+ better drink")
    t.eq(d.basis, "recommendation")
    c.consumables[MILK] = nil
    c.consumables[HAUNCH] = { kind = "food", minLevel = 15, count = 12, buffFood = false }
    t.ok(D.Decide(food(WATER, { count = 3 }), c).action ~= "sell", "better food says nothing about drink")
end

tests["outgrown: a level or a kind that is not known gives no answer"] = function(t)
    local function rule(c, item) return D.Decide(item or food(JERKY), c).rule end
    t.ok(rule({ consumables = carried() }) ~= "outgrownConsumable", "your level is not known")
    t.ok(rule({ consumables = carried(), level = "20" }) ~= "outgrownConsumable", "your level is not a number")
    t.ok(rule({ level = 20 }) ~= "outgrownConsumable", "the bags were not read")
    t.ok(rule({ consumables = "?", level = 20 }) ~= "outgrownConsumable", "the facts are the wrong shape")
    t.ok(rule({ consumables = carried({ [JERKY] = { minLevel = 1, count = 4, buffFood = false } }), level = 20 })
        ~= "outgrownConsumable", "its kind is not known")
    t.ok(rule({ consumables = carried({ [JERKY] = { kind = "potion", minLevel = 1, count = 4, buffFood = false } }),
                level = 20 }) ~= "outgrownConsumable", "a kind that is neither food nor drink")
    t.ok(rule({ consumables = carried({ [JERKY] = { kind = "food", count = 4, buffFood = false } }), level = 20 })
        ~= "outgrownConsumable", "the level it needs is not known")
    t.ok(rule({ consumables = carried(), level = 20 }, food(CHEESE)) ~= "outgrownConsumable",
        "an item with no facts")
    local errors = 0
    D.Decide(food(JERKY), { consumables = "?", level = 20, onError = function() errors = errors + 1 end })
    D.Decide(food(JERKY), { consumables = { [JERKY] = "?", [HAUNCH] = 7 }, level = 20,
                            onError = function() errors = errors + 1 end })
    t.eq(errors, 0, "and none of it is an error")
end

tests["outgrown: an earlier keep rule still wins"] = function(t)
    local c = { consumables = carried(), level = 20, choices = { never = { [JERKY] = true } } }
    local d = D.Decide(food(JERKY), c)
    t.eq(d.action, "keep"); t.eq(d.rule, "neverSell")
    c.choices = { keep = { [JERKY] = true } }
    d = D.Decide(food(JERKY), c)
    t.eq(d.action, "keep"); t.eq(d.rule, "yourChoice")
    c.choices = nil
    c.questItems = { [JERKY] = { quest = "A Hungry Wolf", inLog = true } }
    d = D.Decide(food(JERKY), c)
    t.eq(d.action, "keep"); t.eq(d.rule, "questNeeds")
    c.questItems = nil
    d = D.Decide(food(JERKY, { sellPrice = 0 }), c)
    t.eq(d.action, "keep"); t.eq(d.rule, "unsellable")
end

tests["outgrown: a material of a profession of yours is not sold as outgrown"] = function(t)
    local c = { consumables = carried(), level = 20,
                materials = { [JERKY] = { { prof = "Cooking", what = "Jerky Stew" } } } }
    local d = D.Decide(food(JERKY), c)
    t.eq(d.action, "keep"); t.eq(d.rule, "professionMaterial")
    c.materials = nil
    c.everMaterials = { [JERKY] = "Cooking" }
    t.ok(D.Decide(food(JERKY), c).action ~= "sell", "nor one of a profession you ever had")
end

-- ------------------------------------------------------------- the pure parts

tests["outgrown: the verdict, from plain values"] = function(t)
    local v = D.OutgrownVerdict("food", 1, 15, false)
    t.eq(v and v.action, "sell")
    t.eq(v and v.reason, "outgrown: you carry 10+ better food")
    t.eq(v and v.basis, "recommendation")
    v = D.OutgrownVerdict("drink", 1, 15, nil)
    t.eq(v and v.action, "sell", "drink has no buff to know")
    t.eq(v and v.reason, "outgrown: you carry 10+ better drink")
    t.ok(D.OutgrownVerdict("food", 10, 15, false) ~= nil, "exactly five levels")
    t.eq(D.OutgrownVerdict("food", 11, 15, false), nil, "four levels")
    t.ok(D.OutgrownVerdict("food", 0, 5, false) ~= nil, "a food that needs no level is level 0")
    t.eq(D.OutgrownVerdict("food", 1, 15, true), nil, "well fed food")
    t.eq(D.OutgrownVerdict("food", 1, 15, nil), nil, "buff not known")
    t.eq(D.OutgrownVerdict("food", 1, 15, "no"), nil, "buff of the wrong shape")
    t.eq(D.OutgrownVerdict("food", nil, 15, false), nil, "level it needs not known")
    t.eq(D.OutgrownVerdict("food", 1, nil, false), nil, "nothing better carried")
    t.eq(D.OutgrownVerdict(nil, 1, 15, false), nil, "kind not known")
    t.eq(D.OutgrownVerdict("potion", 1, 15, false), nil, "not food or drink")
    t.eq(D.OutgrownVerdict("food", "1", 15, false), nil, "a level that is not a number")
end

tests["outgrown: the best tier you carry enough of, for your level"] = function(t)
    local f = carried({
        [STEW] = { kind = "food", minLevel = 25, count = 30, buffFood = true },
        [MILK] = { kind = "drink", minLevel = 5, count = 10 },
        [CHEESE] = { kind = "food", minLevel = 5, count = 10, buffFood = false },
    })
    t.eq(D.BestTier(f, "food", 20), 15, "the highest you can use, with 10 or more")
    t.eq(D.BestTier(f, "food", 25), 25, "at 25 the stew counts")
    t.eq(D.BestTier(f, "food", 14), 5, "below 15 the cheese is the best")
    t.eq(D.BestTier(f, "food", 4), nil, "nothing you can use with 10 or more")
    t.eq(D.BestTier(f, "drink", 20), 5, "drink apart from food")
    t.eq(D.BestTier(f, "drink", 4), nil)
    t.eq(D.BestTier(f, "food", nil), nil, "your level not known")
    t.eq(D.BestTier(f, nil, 20), nil, "no kind")
    t.eq(D.BestTier(nil, "food", 20), nil, "bags not read")
    t.eq(D.BestTier({ [1] = "?", [2] = { kind = "food" }, [3] = { kind = "food", minLevel = 5 } }, "food", 20), nil,
        "rows of the wrong shape count for nothing")
end

tests["outgrown: food or drink, from the tooltip"] = function(t)
    t.eq(D.ConsumableKind({ "Tough Jerky", EAT }), "food")
    t.eq(D.ConsumableKind({ "Refreshing Spring Water", DRINK }), "drink")
    t.eq(D.ConsumableKind({ "Stew", FED }), "food")
    t.eq(D.ConsumableKind({ "Both", EAT, DRINK }), nil, "both: not known which")
    t.eq(D.ConsumableKind({ "Minor Healing Potion", "Use: Restores 70 to 90 health." }), nil, "neither")
    t.eq(D.ConsumableKind({}), nil)
    t.eq(D.ConsumableKind(nil), nil, "tooltip not read")
    t.eq(D.ConsumableKind({ 5, false, EAT }), "food", "odd lines are passed over")
end

-- ------------------------------------------------------------- the facts

local INFO = {
    [JERKY] = { name = "Tough Jerky", classID = 0, subclassID = 5, minLevel = 1 },
    [HAUNCH] = { name = "Haunch of Meat", classID = 0, subclassID = 5, minLevel = 15 },
    [WATER] = { name = "Refreshing Spring Water", classID = 0, subclassID = 5, minLevel = 1 },
    [STEW] = { name = "Stew", classID = 0, subclassID = 5, minLevel = 25 },
    [CHEESE] = { name = "Cheese, level not read", classID = 0, subclassID = 5 },
    [POTION] = { name = "Minor Healing Potion", classID = 0, subclassID = 1, minLevel = 1 },
    [CLOTH] = { name = "Linen Cloth", classID = 7, subclassID = 5, minLevel = 0 },
}
local LINES = {
    [JERKY] = { "Tough Jerky", EAT }, [HAUNCH] = { "Haunch of Meat", EAT },
    [WATER] = { "Refreshing Spring Water", DRINK }, [STEW] = { "Stew", FED },
    [CHEESE] = { "Cheese", EAT }, [POTION] = { "Minor Healing Potion", EAT }, [CLOTH] = { "Linen Cloth", EAT },
}

local function reads()
    local asked = {}
    local function info(item) return INFO[item] end
    local function lines(item)
        asked[item] = (asked[item] or 0) + 1
        return LINES[item]
    end
    return info, lines, asked
end

tests["outgrown: the facts are read from the bags, summed by item"] = function(t)
    local info, lines, asked = reads()
    local stacks = {
        { item = JERKY, count = 4 }, { item = HAUNCH, count = 5 }, { item = HAUNCH, count = 7 },
        { item = WATER, count = 3 }, { item = STEW, count = 2 }, { item = CHEESE, count = 1 },
        { item = POTION, count = 5 }, { item = CLOTH, count = 20 }, { count = 3 }, "?",
    }
    local f = D.ConsumableFacts(stacks, info, lines)
    t.ok(type(f) == "table", "facts")
    if type(f) ~= "table" then return end
    t.eq(f[JERKY].kind, "food"); t.eq(f[JERKY].minLevel, 1); t.eq(f[JERKY].count, 4); t.eq(f[JERKY].buffFood, false)
    t.eq(f[HAUNCH].count, 12, "two stacks are one item")
    t.eq(asked[HAUNCH], 1, "and its tooltip is read once")
    t.eq(f[WATER].kind, "drink")
    t.eq(f[STEW].buffFood, true, "well fed food is told apart")
    t.eq(f[CHEESE].kind, "food"); t.eq(f[CHEESE].minLevel, nil, "a level that was not read stays unknown")
    t.eq(f[POTION], nil, "a potion is not food or drink")
    t.eq(f[CLOTH], nil, "nor is cloth")
    t.eq(asked[POTION], nil, "and their tooltips are not read")
    t.eq(D.Decide(food(JERKY), { consumables = f, level = 20 }).action, "sell", "the rule takes them as they are")
    t.ok(D.Decide(food(CHEESE), { consumables = f, level = 20 }).action ~= "sell", "level not read: not sold")
end

tests["outgrown: a stack with no count leaves its item uncounted"] = function(t)
    local info, lines = reads()
    local f = D.ConsumableFacts({ { item = JERKY, count = 4 }, { item = HAUNCH, count = 12 }, { item = HAUNCH } },
        info, lines)
    t.eq(f and f[HAUNCH] and f[HAUNCH].count, nil, "not known how many")
    t.ok(D.Decide(food(JERKY), { consumables = f, level = 20 }).action ~= "sell", "so nothing is outgrown")
    f = D.ConsumableFacts({ { item = HAUNCH }, { item = HAUNCH, count = 12 }, { item = JERKY, count = 4 } },
        info, lines)
    t.eq(f and f[HAUNCH] and f[HAUNCH].count, nil, "in either order")
end

tests["outgrown: reads that are missing or fail give no facts, never a sale"] = function(t)
    local info, lines = reads()
    local stacks = { { item = JERKY, count = 4 }, { item = HAUNCH, count = 12 } }
    t.eq(D.ConsumableFacts(nil, info, lines), nil, "bags not read")
    t.eq(D.ConsumableFacts(stacks, nil, lines), nil, "no item read")
    t.eq(D.ConsumableFacts(stacks, info, nil), nil, "no tooltip read")
    local f = D.ConsumableFacts(stacks, info, function() return nil end)
    t.eq(f and next(f), nil, "tooltips not readable yet: no kind, so no rows")
    f = D.ConsumableFacts(stacks, function() error("boom") end, lines)
    t.eq(f and next(f), nil, "an item read that raises: no rows")
    f = D.ConsumableFacts(stacks, info, function() error("boom") end)
    t.eq(f and next(f), nil, "a tooltip read that raises: no rows")
    t.ok(D.Decide(food(JERKY), { consumables = f, level = 20 }).action ~= "sell", "and nothing is sold")
end

return tests
