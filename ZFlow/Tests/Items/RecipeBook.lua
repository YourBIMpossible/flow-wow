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

return tests
