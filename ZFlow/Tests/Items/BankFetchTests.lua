local _, ns = ...

-- Tests for ZFlow/Items/BankFetch.lua (FLOW-PARITY E-61, lead section 831.3):
-- a skill-plan step to take a recipe or materials out of the bank, from the
-- bank this character last saw (char "learned.bankCounts", Items/HaveTip.lua).
-- Pure: items, names and counts are made up. Flow's step:
-- Modules/Crafting/SkillPlan.lua:1022-1025 ("Bank: take out <recipe>").
--
-- Red before the code: ns.BankFetch does not exist.

local tests = {}

local function BF() return ns.BankFetch end

local BAR, LEATHER, RECIPE = 2840, 2318, 5083

local function seen(counts) return { at = 1000, counts = counts } end

tests["bank fetch: the module exists"] = function(t)
    t.eq(type(BF()), "table", "ns.BankFetch")
    if type(BF()) ~= "table" then return end
    t.eq(type(BF().Steps), "function", "BankFetch.Steps")
end

tests["bank fetch: mats short and in the bank give one step with the count"] = function(t)
    if type(BF()) ~= "table" then t.ok(false, "no module") return end
    local step, why = BF().Steps({ { item = BAR, name = "Copper Bar", count = 5 } }, seen({ [BAR] = 8 }))
    t.eq(why, nil)
    t.eq(step and step.kind, "bank")
    t.eq(step and step.items, { { key = BAR, name = "Copper Bar", count = 5 } })
    t.eq(step and step.label, "Take from your bank: 5 Copper Bar")
    t.eq(step and step.seenAt, 1000, "when the bank was seen")
end

tests["bank fetch: only what is short, at most what the bank holds"] = function(t)
    if type(BF()) ~= "table" then t.ok(false, "no module") return end
    local step = BF().Steps({ { item = BAR, name = "Copper Bar", count = 3 },
        { item = LEATHER, name = "Light Leather", count = 6 } }, seen({ [BAR] = 20, [LEATHER] = 2 }))
    t.eq(step and step.items, { { key = BAR, name = "Copper Bar", count = 3 },
        { key = LEATHER, name = "Light Leather", count = 2 } })
    t.eq(step and step.label, "Take from your bank: 3 Copper Bar, 2 Light Leather")
end

tests["bank fetch: nothing short gives no step"] = function(t)
    if type(BF()) ~= "table" then t.ok(false, "no module") return end
    local step, why = BF().Steps({ { item = BAR, name = "Copper Bar", count = 0 } }, seen({ [BAR] = 8 }))
    t.eq(step, nil)
    t.eq(why, "nothing short")
    step, why = BF().Steps({}, seen({ [BAR] = 8 }))
    t.eq(step, nil)
    t.eq(why, "nothing short")
end

tests["bank fetch: a bank never seen gives no step and says so"] = function(t)
    if type(BF()) ~= "table" then t.ok(false, "no module") return end
    local need = { { item = BAR, name = "Copper Bar", count = 5 } }
    local step, why = BF().Steps(need, nil)
    t.eq(step, nil)
    t.eq(why, "bank not seen", "not seen, never nothing in bank")
    step, why = BF().Steps(need, { at = 1000 })
    t.eq(step, nil)
    t.eq(why, "bank not seen")
end

tests["bank fetch: a seen bank without the item says none in bank"] = function(t)
    if type(BF()) ~= "table" then t.ok(false, "no module") return end
    local step, why = BF().Steps({ { item = BAR, name = "Copper Bar", count = 5 } }, seen({ [LEATHER] = 4 }))
    t.eq(step, nil)
    t.eq(why, "none in bank")
end

tests["bank fetch: a recipe in the bank and not known gives a step for it"] = function(t)
    if type(BF()) ~= "table" then t.ok(false, "no module") return end
    local step = BF().Steps({ { item = RECIPE, name = "Recipe: Test Stew", count = 1, recipe = true } },
        seen({ [RECIPE] = 1 }))
    t.eq(step and step.items, { { key = RECIPE, name = "Recipe: Test Stew", count = 1, recipe = true } })
    t.eq(step and step.label, "Take from your bank: Recipe: Test Stew")
end

tests["bank fetch: items match by Items.Key, suffix included"] = function(t)
    if type(BF()) ~= "table" then t.ok(false, "no module") return end
    local link = "|cffffffff|Hitem:" .. BAR .. ":0:0:0:0:0:0:0|h[Copper Bar]|h|r"
    local step = BF().Steps({ { item = link, name = "Copper Bar", count = 2 } }, seen({ [tostring(BAR)] = 5 }))
    t.eq(step and step.items, { { key = BAR, name = "Copper Bar", count = 2 } }, "a link matches the plain key")
    local bear = "item:15234:0:0:0:0:0:588:0"
    step = BF().Steps({ { item = bear, name = "Test Cloak of the Bear", count = 1 } }, seen({ [15234] = 3 }))
    t.eq(step, nil, "a plain item is not the suffixed one")
    step = BF().Steps({ { item = bear, name = "Test Cloak of the Bear", count = 1 } }, seen({ ["15234:588"] = 1 }))
    t.eq(step and step.items and step.items[1] and step.items[1].key, "15234:588")
end

tests["bank fetch: the plan takes a vendor recipe out of the bank instead of buying it"] = function(t)
    local P = ns.ProfPlan
    if type(BF()) ~= "table" or type(P) ~= "table" then t.ok(false, "no module") return end
    local book = { ["Test Nail"] = { profession = "Blacksmithing", makes = 51, mats = { [2] = 1 } } }
    local colours = { ["Test Nail"] = { trivial = { lo = 10, hi = 20 } } }
    local recipes = { { prof = "Blacksmithing", skill = 40, name = "Plans: Test Hook", recipe = "Test Hook",
        item = RECIPE, vendor = "Test Smith", map = 1, x = 0.5, y = 0.5 } }
    local function input(rec)
        return { prof = "Blacksmithing", skill = 50, max = 75, book = book, colours = colours,
            bags = {}, bank = {}, bankRecord = rec, vendorRecipes = recipes,
            name = function() return nil end, price = function() return nil end }
    end
    local steps = P.Plan(input(seen({ [RECIPE] = 1 })))
    t.eq(steps and steps[1] and steps[1].kind, "bank", "the recipe is in the bank")
    t.eq(steps and steps[1] and steps[1].label, "Take from your bank: Plans: Test Hook")
    steps = P.Plan(input(nil))
    t.eq(steps and steps[1] and steps[1].kind, "buy_recipe", "bank not seen: buy it")
end

return tests
