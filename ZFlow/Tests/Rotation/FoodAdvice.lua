local _, ns = ...

-- P-FOOD remainder (BASELINE-RECONCILE-2026-11-23 N6, N9, N10, N11), advice
-- only: each answer is a look-only suggestion (look = true) or a list; no
-- item is used, no spell cast. Made-up snapshots; not tested in game.

local tests = {}

local function A() return ns.FoodAdvice end

-- N6: with a stone and an edged weapon out of combat at a kill step, the
-- key offers the stone once.
tests["food advice N6: a stone with an edged weapon at a kill step is offered once, look only"] = function(t)
    local seen = {}
    local s = { inCombat = false, killStep = true, weaponEdged = true, weaponBuffed = false,
                buffs = {}, preFight = { { name = "Solid Sharpening Stone", item = 7964, kind = "stone" } } }
    local a = A().PreFight(s, seen)
    t.eq(type(a) == "table" and a.item, "Solid Sharpening Stone", "the stone is offered")
    t.eq(type(a) == "table" and a.look, true, "look only")
    t.eq(A().PreFight(s, seen), nil, "not offered a second time")
end

tests["food advice N6: no offer in a fight, off a kill step, or on a blunt weapon"] = function(t)
    local stone = { { name = "Solid Sharpening Stone", item = 7964, kind = "stone" } }
    t.eq(A().PreFight({ inCombat = true, killStep = true, weaponEdged = true, buffs = {}, preFight = stone }, {}), nil, "in a fight")
    t.eq(A().PreFight({ inCombat = false, killStep = false, weaponEdged = true, buffs = {}, preFight = stone }, {}), nil, "no kill step")
    t.eq(A().PreFight({ inCombat = false, killStep = true, weaponEdged = false, buffs = {}, preFight = stone }, {}), nil, "blunt weapon")
    t.eq(A().PreFight({ inCombat = false, killStep = true, weaponEdged = true, weaponBuffed = true, buffs = {}, preFight = stone }, {}), nil, "already on the weapon")
end

tests["food advice N6: an elixir whose buff is not on you is offered near an enemy"] = function(t)
    local s = { inCombat = false, enemyNear = true, buffs = {},
                preFight = { { name = "Elixir of Lion's Strength", item = 2454, kind = "elixir", buff = "Lion's Strength" } } }
    local a = A().PreFight(s, {})
    t.eq(type(a) == "table" and a.item, "Elixir of Lion's Strength", "elixir offered")
    s.buffs["Lion's Strength"] = true
    t.eq(A().PreFight(s, {}), nil, "buff on: not offered")
end

-- N9: the saved order is the order offered.
tests["food advice N9: the saved recovery order is the order offered"] = function(t)
    t.eq(table.concat(A().RecoverOrder(nil), ","), "bandage,food,heal,drink", "default order")
    local saved = { order = { "heal", "food", "bandage", "drink" }, off = { food = true } }
    t.eq(table.concat(A().RecoverOrder(saved), ","), "heal,bandage,drink", "saved order, food off")
    local s = { inCombat = false, healthLow = true, manaLow = true,
                have = { bandage = "Heavy Linen Bandage", food = "Bread", heal = "Lesser Heal", drink = "Water" } }
    local a = A().Recover(s, saved)
    t.eq(type(a) == "table" and a.step, "heal", "first saved step offered")
    t.eq(type(a) == "table" and a.look, true, "look only")
end

tests["food advice N9: drink only at low mana, nothing in a fight"] = function(t)
    local s = { inCombat = false, healthLow = false, manaLow = true, have = { drink = "Water" } }
    t.eq(A().Recover(s, nil).step, "drink", "drink at low mana")
    s.manaLow = false
    t.eq(A().Recover(s, nil), nil, "nothing needed")
    t.eq(A().Recover({ inCombat = true, healthLow = true, have = { food = "Bread" } }, nil), nil, "in a fight")
end

-- N10: near a lit fire without the buff, the key places then sits.
tests["food advice N10: near a lit fire without the camp buff, place then sit"] = function(t)
    local s = { inCombat = false, fireNear = true, buffs = {}, campObjects = { "Bedroll" } }
    local a = A().Camp(s)
    t.eq(type(a) == "table" and table.concat(a.steps, ","), "place Bedroll,sit", "place then sit")
    t.eq(type(a) == "table" and a.look, true, "look only")
    s.buffs[A().CAMP_BUFF] = true
    t.eq(A().Camp(s), nil, "buff on: nothing")
    t.eq(A().Camp({ inCombat = false, fireNear = false, buffs = {} }), nil, "no fire: nothing")
end

-- N11: status icons above the key (repair, camp; a registry for more).
tests["food advice N11: status icon registry has repair and camp, and takes more"] = function(t)
    local s = { durabilityLow = true, fireNear = true, buffs = {} }
    local names = {}
    for _, i in ipairs(A().StatusIcons(s)) do names[#names + 1] = i.name end
    t.eq(table.concat(names, ","), "repair,camp", "repair and camp shown")
    t.eq(#A().StatusIcons({ durabilityLow = false, fireNear = false, buffs = {} }), 0, "none shown")
    A().RegisterStatus("test", function(st) return st.testOn == true end)
    t.eq(#A().StatusIcons({ testOn = true, buffs = {} }), 1, "a registered icon shows")
    A().UnregisterStatus("test")
end

return tests
