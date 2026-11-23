local _, ns = ...

-- Tests for ZFlow/Items/RecipeBook.lua (section 227, P-GOALS-RECIPE): what
-- the player's own profession windows showed of each learned recipe, saved
-- for the goals list. Offline: the fake client's reads, not the game's.
-- Not tested in game.

local tests = {}

local LINEN, BOLT, BANDAGE, POTION = 2589, 2996, 1251, 858
local BOLT_ID, BANDAGE_ID, UNLEARNED_ID, UNREAD_ID = 2963, 3275, 2964, 2965

local function at(root, ...)
    for _, key in ipairs({ ... }) do
        if type(root) ~= "table" then return nil end
        root = root[key]
    end
    return root
end

-- The whole add-on on a fake client, logged in. char: the character's saved
-- data to start from.
local function start(char)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, char or {})
    c.setRecipeSchematic(BOLT_ID, { makes = BOLT, yield = 1, mats = { [LINEN] = 2 } })
    c.setRecipeSchematic(BANDAGE_ID, { makes = BANDAGE, yield = 1, mats = { [LINEN] = 1 } })
    c.setRecipeSchematic(UNLEARNED_ID, { makes = POTION, yield = 1, mats = { [LINEN] = 3 } })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function book(c) return at(c.saved(ns.id.charDB), "learned", "facts", "recipeBook") end

local function seen(c, addon, r)
    c.setRecipes(r)
    c.fire(addon.RecipeBook.EVENT)
end

local function tailoring()
    return { profession = 197, name = "Tailoring", skill = 50, max = 75, recipes = {
        { id = BOLT_ID, name = "Bolt of Linen Cloth", learned = true },
        { id = UNLEARNED_ID, name = "Not Learned", learned = false },
        { id = UNREAD_ID, name = "Unread", learned = true },
    } }
end

local function firstAid()
    return { profession = 129, name = "First Aid", skill = 40, max = 75, recipes = {
        { id = BANDAGE_ID, name = "Linen Bandage", learned = true },
    } }
end

local BOLT_ENTRY = { id = BOLT_ID, makes = BOLT, yield = 1, mats = { [LINEN] = 2 }, profession = "Tailoring" }

-- Fails before section 227: there was no book, so nothing was saved.
tests["recipe book: a profession window saves each learned recipe it can read"] = function(t)
    local c, addon = start()
    seen(c, addon, tailoring())
    t.eq(book(c), { ["Bolt of Linen Cloth"] = BOLT_ENTRY },
        "a recipe not learned, or one whose mats can't be read, is not saved")
    t.eq(addon.recipeBook.last().ok, true, tostring(addon.recipeBook.last().reason))
end

tests["recipe book: Recipes gives what ItemPlan reads; For finds the recipe that makes an item"] = function(t)
    local c, addon = start()
    seen(c, addon, tailoring())
    local B = addon.RecipeBook
    t.eq(B.Recipes(addon), { ["Bolt of Linen Cloth"] = { id = BOLT_ID, makes = BOLT, yield = 1, mats = { [LINEN] = 2 } } })
    t.eq(B.For(addon, BOLT), "Bolt of Linen Cloth")
    t.eq(B.For(addon, LINEN), nil, "no recipe seen makes it")
    local plan = addon.ItemPlan.Build({ recipe = "Bolt of Linen Cloth", count = 3 },
        { recipes = B.Recipes(addon), snapshot = addon.Resources.Fake({ bags = { [LINEN] = 20 } }) })
    t.eq(plan.ok, true, "ItemPlan can plan from it")
    t.eq(plan.rows[1].need, 6)
end

tests["recipe book: a second profession keeps the first one's recipes"] = function(t)
    local c, addon = start()
    seen(c, addon, tailoring())
    seen(c, addon, firstAid())
    t.eq(book(c), {
        ["Bolt of Linen Cloth"] = BOLT_ENTRY,
        ["Linen Bandage"] = { id = BANDAGE_ID, makes = BANDAGE, yield = 1, mats = { [LINEN] = 1 }, profession = "First Aid" },
    })
end

tests["recipe book: a saved entry that can't be read is left out of Recipes"] = function(t)
    local c, addon = start({ learned = { facts = { recipeBook = {
        ["Bolt of Linen Cloth"] = BOLT_ENTRY,
        ["no product"] = { yield = 1, mats = { [LINEN] = 2 } },
        ["no mats"] = { makes = BOLT, yield = 1, mats = {} },
        ["a zero"] = { makes = BOLT, yield = 1, mats = { [LINEN] = 0 } },
        ["a fraction"] = { makes = BOLT, yield = 1.5, mats = { [LINEN] = 2 } },
        ["not a table"] = "bolt",
    } } } })
    t.eq(addon.RecipeBook.Recipes(addon),
        { ["Bolt of Linen Cloth"] = { id = BOLT_ID, makes = BOLT, yield = 1, mats = { [LINEN] = 2 } } })
    t.eq(book(c)["no mats"] ~= nil, true, "left as it was saved")
end

tests["recipe book: no profession window answer writes nothing"] = function(t)
    local c, addon = start()
    seen(c, addon, nil)
    t.eq(book(c), nil)
    t.eq(addon.recipeBook.last().ok, false)
end

tests["recipe book: before login the book reads as empty"] = function(t)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, { learned = { facts = { recipeBook = { ["Bolt of Linen Cloth"] = BOLT_ENTRY } } } })
    local addon = ns.offline.addon(c)
    t.eq(addon.RecipeBook.Recipes(addon), {})
    t.eq(addon.RecipeBook.For(addon, BOLT), nil)
end

-- Section 233 -------------------------------------------------------------------

-- The classic window only: no C_TradeSkillUI answer, these rows.
local function classic(c, addon, rows)
    c.setRecipes(nil)
    c.setTradeSkillRows({ name = "Tailoring", rows = rows })
    c.fire(addon.RecipeBook.EVENT)
end

-- GR2-1. Fails before: the classic rows were not read, so nothing was saved.
tests["recipe book GR2-1: no C_TradeSkillUI answer: the classic window's rows are read"] = function(t)
    local c, addon = start()
    c.setTradeSkillSchematic(2, { makes = BOLT, yield = 1, mats = { [LINEN] = 2 } })
    classic(c, addon, { { index = 2, name = "Bolt of Linen Cloth" }, { index = 3, name = "Unread" } })
    t.eq(book(c), { ["Bolt of Linen Cloth"] = { makes = BOLT, yield = 1, mats = { [LINEN] = 2 }, profession = "Tailoring" } },
        "no id from the classic read")
    t.eq(addon.recipeBook.last().ok, true)
    t.eq(addon.RecipeBook.For(addon, BOLT), "Bolt of Linen Cloth")
end

-- GR2-1. Fails before: GetRecipeSchematic absent, nothing could be read and
-- the classic rows were not tried.
tests["recipe book GR2-1: C_TradeSkillUI answers but no schematic reads: the classic rows are read"] = function(t)
    local c, addon = start()
    c.setTradeSkillSchematic(2, { makes = BOLT, yield = 1, mats = { [LINEN] = 2 } })
    c.setTradeSkillRows({ name = "Tailoring", rows = { { index = 2, name = "Bolt of Linen Cloth" } } })
    seen(c, addon, { profession = 197, name = "Tailoring", recipes = {
        { id = UNREAD_ID, name = "Bolt of Linen Cloth", learned = true } } })
    t.eq(book(c), { ["Bolt of Linen Cloth"] = { makes = BOLT, yield = 1, mats = { [LINEN] = 2 }, profession = "Tailoring" } })
end

-- GR2-1. Fails before: this was ok with nothing saved, said as nothing at all.
tests["recipe book GR2-1: a window seen but not read says so, not no window"] = function(t)
    local c, addon = start()
    seen(c, addon, { profession = 197, name = "Tailoring", recipes = {
        { id = UNREAD_ID, name = "Unread", learned = true } } })
    t.eq(book(c), nil, "nothing written")
    t.eq(addon.recipeBook.last().ok, false)
    t.eq(addon.recipeBook.last().reason, addon.RecipeBook.UNREAD)
    local lines = addon.ItemGoals.Run(addon, "make 2996 3")
    t.ok(type(lines) == "table" and type(lines[1]) == "string"
        and lines[1]:find("could not read its recipes", 1, true) ~= nil, tostring(lines and lines[1]))
    seen(c, addon, nil)
    t.eq(addon.recipeBook.last().reason, "no profession window answered", "no window: the other reason")
    lines = addon.ItemGoals.Run(addon, "make 2996 3")
    t.ok(type(lines) == "table" and type(lines[1]) == "string"
        and lines[1]:find("No recipe you have seen", 1, true) ~= nil, tostring(lines and lines[1]))
end

-- GR2-3. Fails before: the second of one name was written over the first.
tests["recipe book GR2-3: two recipes of one name are both saved, and said"] = function(t)
    local c, addon = start()
    seen(c, addon, { profession = 197, name = "Tailoring", recipes = {
        { id = BANDAGE_ID, name = "Bolt of Linen Cloth", learned = true },
        { id = BOLT_ID, name = "Bolt of Linen Cloth", learned = true } } })
    t.eq(book(c), {
        ["Bolt of Linen Cloth"] = BOLT_ENTRY,
        ["Bolt of Linen Cloth (" .. BANDAGE_ID .. ")"] = { id = BANDAGE_ID, makes = BANDAGE, yield = 1,
            mats = { [LINEN] = 1 }, profession = "Tailoring" },
    }, "the lower id keeps the name")
    t.eq(addon.recipeBook.last().collided, 1)
end

-- GR2-3. Fails before: a recipe once saved stayed saved.
tests["recipe book GR2-3: a recipe no longer learned is dropped; another profession's is kept"] = function(t)
    local c, addon = start()
    local ROBE = { id = UNLEARNED_ID, name = "Brown Linen Robe", learned = true }
    local BOLT_ROW = { id = BOLT_ID, name = "Bolt of Linen Cloth", learned = true }
    seen(c, addon, firstAid())
    seen(c, addon, { profession = 197, name = "Tailoring", recipes = { BOLT_ROW, ROBE } })
    t.ok(book(c)["Brown Linen Robe"] ~= nil, "saved")
    seen(c, addon, { profession = 197, name = "Tailoring", recipes = { BOLT_ROW,
        { id = UNREAD_ID, name = "Unread", learned = true } } })
    t.ok(book(c)["Brown Linen Robe"] ~= nil, "a read with a recipe that could not be read drops nothing")
    seen(c, addon, { profession = 197, name = "Tailoring", recipes = { BOLT_ROW,
        { id = UNLEARNED_ID, name = "Brown Linen Robe", learned = false } } })
    t.eq(book(c), {
        ["Bolt of Linen Cloth"] = BOLT_ENTRY,
        ["Linen Bandage"] = { id = BANDAGE_ID, makes = BANDAGE, yield = 1, mats = { [LINEN] = 1 }, profession = "First Aid" },
    })
end

-- GR2-4. Fails before: every TRADE_SKILL_LIST_UPDATE wrote the whole book.
tests["recipe book GR2-4: a read that changes nothing writes nothing"] = function(t)
    local c, addon = start()
    seen(c, addon, tailoring())
    local writes, real = 0, addon.store.set
    addon.store.set = function(self, ...)
        writes = writes + 1
        return real(self, ...)
    end
    c.fire(addon.RecipeBook.EVENT)
    c.fire(addon.RecipeBook.EVENT)
    t.eq(writes, 0, "the same window twice")
    t.eq(addon.recipeBook.last().unchanged, true)
    t.eq(addon.recipeBook.last().ok, true)
    seen(c, addon, firstAid())
    t.eq(writes, 1, "a new profession is written")
    t.eq(book(c)["Linen Bandage"] ~= nil, true)
end

return tests
