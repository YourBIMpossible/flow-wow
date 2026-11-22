local _, ns = ...

-- Tests for the eight keep rules ported from Flow into ZFlow/Items/Disposition.lua
-- (L6-B, G5). Each rule is pure here: the facts it needs arrive in the
-- context, as Disposition's other rules take them. Flow's source for each is
-- cited on its test. Nothing is sold anywhere in here.

local D = ns.Disposition
local tests = {}

local function cloth(extra)
    local i = { key = 2589, name = "Linen Cloth", count = 10, quality = 1, sellPrice = 13, classID = 7 }
    for k, v in pairs(extra or {}) do i[k] = v end
    return i
end

local function gearItem(extra)
    local i = { key = 1000, name = "Some Boots", count = 1, quality = 2, sellPrice = 90, classID = 4, minLevel = 20 }
    for k, v in pairs(extra or {}) do i[k] = v end
    return i
end

local function ruleOf(key)
    for _, r in ipairs(D.RULES) do
        if r.key == key then return r end
    end
    return nil
end

-- ------------------------------------------- the eight are there, in Flow's order

tests["keep rules: the eight Flow keep rules are in Z-Flow, at Flow's order"] = function(t)
    local want = { professionMaterial = 25, inSet = 15, spareBag = 28, recipe = 29.5, notGear = 30,
                   needsTraining = 35, laterOrOtherRole = 40, unscoredClass = 45 }
    for key, order in pairs(want) do
        local r = ruleOf(key)
        t.ok(r ~= nil, "rule " .. key .. " is there")
        if r then t.eq(r.order, order, key .. " keeps Flow's order") end
    end
end

-- Modules/Items/Disposition.lua:433-469 (professionMaterial)
tests["keep rules: a material your professions use is kept, saying for what"] = function(t)
    local c = { materials = { [2589] = { { prof = "First Aid", what = "Linen Bandage" }, { prof = "Tailoring" } } } }
    local d = D.Decide(cloth(), c)
    t.eq(d.action, "keep")
    t.eq(d.rule, "professionMaterial")
    t.eq(d.reason, "for First Aid: Linen Bandage; for Tailoring")
    t.eq(d.basis, "fact")
    t.eq(D.Decide(cloth(), {}).rule ~= "professionMaterial", true, "no facts: no opinion")
    t.eq(D.Decide(cloth(), { materials = { [2589] = {} } }).rule ~= "professionMaterial", true, "no profession: no opinion")
end

-- Modules/Items/Disposition.lua:638-648 (inSet)
tests["keep rules: gear in a set you keep is kept, naming the sets"] = function(t)
    local d = D.Decide(gearItem(), { sets = { [1000] = { "Feral", "Balance" } } })
    t.eq(d.action, "keep")
    t.eq(d.rule, "inSet")
    t.eq(d.reason, "in your Feral / Balance set")
    t.eq(D.Decide(gearItem(), { sets = { [1000] = {} } }).rule ~= "inSet", true, "no set: no opinion")
end

-- Modules/Items/Disposition.lua:807-841 (spareBag, its keep half)
tests["keep rules: a bag bigger than one you wear is kept to put on"] = function(t)
    local bag = { key = 4496, name = "Small Brown Pouch", count = 1, quality = 1, sellPrice = 1, classID = 1 }
    local d = D.Decide(bag, { bagSize = { [4496] = 6 }, wornBags = { 6, 6, 4, 0 } })
    t.eq(d.action, "keep")
    t.eq(d.rule, "spareBag")
    t.eq(d.reason, "a 6-slot bag, bigger than one you wear (or a bag slot is empty): put it on")
    local spare = D.Decide(bag, { bagSize = { [4496] = 6 }, wornBags = { 6, 8, 10, 6 } })
    t.ok(spare.rule ~= "spareBag", "a spare bag is not kept by this rule (selling it is not ported)")
    t.ok(D.Decide(bag, { bagSize = { [4496] = 6 } }).rule ~= "spareBag", "worn bags not read: no opinion")
    t.ok(D.Decide(bag, { wornBags = { 0 } }).rule ~= "spareBag", "size not read: no opinion")
end

-- Modules/Items/Disposition.lua:762-805 (recipe, its keep branches)
tests["keep rules: a recipe you can learn, or will be able to, is kept"] = function(t)
    local recipe = { key = 2408, name = "Pattern: Fine Leather Gloves", count = 1, quality = 1, sellPrice = 25, classID = 9 }
    local learn = D.Decide(recipe, { recipes = { [2408] = { prof = "Leatherworking", rank = 40, need = 15 } } })
    t.eq(learn.action, "keep")
    t.eq(learn.rule, "recipe")
    t.eq(learn.reason, "a Leatherworking recipe you can learn: right-click it")
    local later = D.Decide(recipe, { recipes = { [2408] = { prof = "Leatherworking", rank = 10, need = 15 } } })
    t.eq(later.reason, "a Leatherworking recipe: learn it at Leatherworking 15 (you have 10)")
    local known = D.Decide(recipe, { recipes = { [2408] = { prof = "Leatherworking", rank = 40, need = 15, known = true } } })
    t.ok(known.rule ~= "recipe", "one you know is not kept by this rule")
    local other = D.Decide(recipe, { recipes = { [2408] = { prof = "Leatherworking" } } })
    t.ok(other.rule ~= "recipe", "not your profession: not kept by this rule")
    local bound = { key = 2408, count = 1, quality = 1, sellPrice = 0, classID = 9, bound = true }
    local keptBound = D.Decide(bound, { recipes = { [2408] = { prof = "Tailoring", known = true, rank = 50 } }, rules = { ruleOf("recipe") } })
    t.eq(keptBound.reason, "a Tailoring recipe you already know, and vendors won't take it", "Flow's bound-and-unsellable keep")
end

-- Modules/Items/Disposition.lua:843-847 (notGear)
tests["keep rules: not gear is kept, once the gear read says so"] = function(t)
    local d = D.Decide(cloth({ classID = 0 }), { gearRead = true, gear = {} })
    t.eq(d.action, "keep")
    t.eq(d.rule, "notGear")
    t.eq(d.reason, "not gear (materials, food, potions...)")
    t.ok(D.Decide(cloth({ classID = 0 }), {}).rule ~= "notGear", "gear not read: not taken for 'not gear'")
    t.ok(D.Decide(cloth({ classID = 0 }), { gearRead = true, gear = { [2589] = { canUse = true } } }).rule ~= "notGear",
        "gear: not this rule")
    t.eq(ruleOf("notGear").generic, true, "a fallback: not listed among other reasons")
end

-- Modules/Items/Disposition.lua:849-858 (needsTraining)
tests["keep rules: an upgrade once you train its weapon skill is kept"] = function(t)
    local g = { [1000] = { needsTraining = true, skill = "Swords", diffs = { feral = 3 } } }
    local d = D.Decide(gearItem(), { gearRead = true, gear = g, role = "feral" })
    t.eq(d.rule, "needsTraining")
    t.eq(d.reason, "upgrade once you train Swords (weapon master)")
    g[1000].skill = nil
    t.eq(D.Decide(gearItem(), { gearRead = true, gear = g, role = "feral" }).reason,
        "upgrade once you train its weapon skill (weapon master)")
    g[1000].diffs.feral = 0.2
    t.ok(D.Decide(gearItem(), { gearRead = true, gear = g, role = "feral" }).rule ~= "needsTraining", "not better: no")
    t.ok(D.Decide(gearItem(), { gearRead = true, gear = { [1000] = { needsTraining = true, diffs = { feral = 3 } } } }).rule
        ~= "needsTraining", "no role known: no opinion")
end

-- Modules/Items/Disposition.lua:860-874 (laterOrOtherRole)
tests["keep rules: an upgrade at a later level, or for a role you keep, is kept"] = function(t)
    local later = D.Decide(gearItem({ minLevel = 24 }),
        { gearRead = true, gear = { [1000] = { canUse = true, diffs = { feral = 2 } } }, role = "feral" })
    t.eq(later.rule, "laterOrOtherRole")
    t.eq(later.reason, "upgrade at level 24")
    local now = D.Decide(gearItem({ minLevel = 24 }),
        { gearRead = true, gear = { [1000] = { canUse = true, diffs = { feral = 2 } } }, role = "feral", level = 30 })
    t.eq(now.reason, "an upgrade you can wear now", "your level has reached it: not called 'later'")
    local below = D.Decide(gearItem({ minLevel = 24 }),
        { gearRead = true, gear = { [1000] = { canUse = true, diffs = { feral = 2 } } }, role = "feral", level = 20 })
    t.eq(below.reason, "upgrade at level 24", "below it: later")
    -- pairs() skips a nil, so { minLevel = nil } kept the helper's 20 (lead, L6-B merge).
    local noLevel = gearItem()
    noLevel.minLevel = nil
    local unknownLevel = D.Decide(noLevel,
        { gearRead = true, gear = { [1000] = { canUse = true, diffs = { feral = 2 } } }, role = "feral" })
    t.eq(unknownLevel.reason, "upgrade at a later level", "no level made up")
    local other = D.Decide(gearItem(), { gearRead = true, role = "feral",
        gear = { [1000] = { canUse = true, diffs = { feral = 0, balance = 4 } } },
        keptRoles = { balance = true }, roleNames = { balance = "Balance" } })
    t.eq(other.reason, "better for Balance")
    local notKept = D.Decide(gearItem(), { gearRead = true, role = "feral",
        gear = { [1000] = { canUse = true, diffs = { feral = 0, balance = 4 } } } })
    t.ok(notKept.rule ~= "laterOrOtherRole", "a role whose set you don't keep: no")
end

-- Modules/Items/Disposition.lua:876-897 (unscoredClass)
tests["keep rules: gear your class can't be scored for yet is kept"] = function(t)
    local c = { gearRead = true, classScored = false, gear = { [1000] = { canUse = true } } }
    local d = D.Decide(gearItem(), c)
    t.eq(d.rule, "unscoredClass")
    t.eq(d.reason, "gear for your class can't be scored yet, so it's kept: decide yourself")
    c.classScored = true
    t.ok(D.Decide(gearItem(), c).rule ~= "unscoredClass", "scored: no")
    c.classScored = nil
    t.ok(D.Decide(gearItem(), c).rule ~= "unscoredClass", "not known whether scored: no opinion")
end

-- ------------------------------------------------- safety of the new rules

tests["keep rules: junk still sells; the new rules never sell anything"] = function(t)
    local fang = { key = 97, name = "Broken Fang", count = 3, quality = 0, sellPrice = 4 }
    t.eq(D.Decide(fang, { gearRead = true, gear = {} }).action, "sell", "grey junk is sold before notGear")
    local everything = {
        materials = { [1000] = { { prof = "Tailoring" } } }, sets = { [1000] = { "Feral" } },
        bagSize = { [1000] = 30 }, wornBags = { 0 }, recipes = { [1000] = { prof = "Tailoring", rank = 1, need = 300 } },
        gearRead = true, gear = { [1000] = { canUse = true, needsTraining = true, diffs = { feral = 9 } } },
        role = "feral", classScored = false,
    }
    for _, key in ipairs({ "professionMaterial", "inSet", "spareBag", "recipe", "notGear",
                           "needsTraining", "laterOrOtherRole", "unscoredClass" }) do
        local r = ruleOf(key)
        for _, classID in ipairs({ 0, 1, 2, 4, 7, 9, 12 }) do
            local ok, v = pcall(r.check, gearItem({ classID = classID }), everything)
            t.ok(ok, key .. " does not raise")
            t.ok(v == nil or v.action == "keep", key .. " only keeps")
        end
    end
end

tests["keep rules: facts in the wrong shape decide nothing and raise nothing"] = function(t)
    local junk = { materials = "x", sets = 5, bagSize = true, wornBags = "x", recipes = 1, gear = "x",
                   gearRead = true, role = 7, keptRoles = "x", roleNames = 3, classScored = "no" }
    for _, key in ipairs({ "professionMaterial", "inSet", "spareBag", "recipe", "notGear",
                           "needsTraining", "laterOrOtherRole", "unscoredClass" }) do
        local ok, v = pcall(ruleOf(key).check, gearItem({ classID = 1 }), junk)
        t.ok(ok, key .. " does not raise on junk facts")
        if key ~= "notGear" then t.eq(v, nil, key .. " gives no opinion") end
    end
end

return tests
