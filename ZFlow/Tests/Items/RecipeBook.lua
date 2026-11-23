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

-- Section 245 (RB2-1): the book reads once the window's events stop.
local function settle(c, addon) c.advance(addon.RecipeBook.SETTLE, 1) end

local function seen(c, addon, r)
    c.setRecipes(r)
    c.fire(addon.RecipeBook.EVENT)
    settle(c, addon)
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

-- The classic window only: no C_TradeSkillUI answer, these rows. how:
-- what the window says of them (section 245: collapsed, filtered, whole).
local function classic(c, addon, rows, how)
    how = how or {}
    c.setRecipes(nil)
    c.setTradeSkillRows({ name = "Tailoring", rows = rows, collapsed = how.collapsed, filtered = how.filtered,
                          whole = how.whole })
    c.fire(addon.RecipeBook.EVENT)
    settle(c, addon)
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
    -- Other modules write on the same event; count the book's own path only.
    addon.store.set = function(self, scope, path, ...)
        if path == addon.RecipeBook.PATH then writes = writes + 1 end
        return real(self, scope, path, ...)
    end
    c.fire(addon.RecipeBook.EVENT)
    settle(c, addon)
    c.fire(addon.RecipeBook.EVENT)
    settle(c, addon)
    t.eq(writes, 0, "the same window twice")
    t.eq(addon.recipeBook.last().unchanged, true)
    t.eq(addon.recipeBook.last().ok, true)
    seen(c, addon, firstAid())
    t.eq(writes, 1, "a new profession is written")
    t.eq(book(c)["Linen Bandage"] ~= nil, true)
end

-- Section 238 -------------------------------------------------------------------

local ENCHANT = "Enchant Bracer - Minor Health"
local CLASSIC_BOLT = { makes = BOLT, yield = 1, mats = { [LINEN] = 2 }, profession = "Tailoring" }

-- RF-1. Fails before: a recipe with no item product was not saved.
tests["recipe book RF-1: a recipe whose product is no item is kept with its reagents"] = function(t)
    local c, addon = start()
    c.setTradeSkillSchematic(2, { makes = BOLT, yield = 1, mats = { [LINEN] = 2 } })
    c.setTradeSkillSchematic(3, { name = ENCHANT, difficulty = "optimal", yield = 1, mats = { [LINEN] = 1 } })
    classic(c, addon, { { index = 2, name = "Bolt of Linen Cloth" }, { index = 3, name = ENCHANT } })
    t.eq(book(c)[ENCHANT], { yield = 1, mats = { [LINEN] = 1 }, difficulty = "optimal", profession = "Tailoring" })
    t.eq(addon.RecipeBook.Recipes(addon)[ENCHANT], nil, "nothing ItemPlan can make: left out of Recipes")
    t.eq(addon.RecipeBook.For(addon, BOLT), "Bolt of Linen Cloth")
end

-- RF-2. Fails before: the difficulty was not kept, and a schematic of
-- another row was saved under this row's name.
tests["recipe book RF-2: the difficulty is kept; a schematic of another recipe is not saved"] = function(t)
    local c, addon = start()
    c.setTradeSkillSchematic(2, { name = "Bolt of Linen Cloth", difficulty = "trivial", makes = BOLT, yield = 1,
        mats = { [LINEN] = 2 } })
    c.setTradeSkillSchematic(3, { name = "Linen Bandage", difficulty = "easy", makes = BANDAGE, yield = 1,
        mats = { [LINEN] = 1 } })
    classic(c, addon, { { index = 2, name = "Bolt of Linen Cloth", difficulty = "trivial" },
        { index = 3, name = "Brown Linen Robe", difficulty = "easy" } })
    t.eq(book(c), { ["Bolt of Linen Cloth"] = { makes = BOLT, yield = 1, mats = { [LINEN] = 2 },
        difficulty = "trivial", profession = "Tailoring" } }, "row 3 names another recipe: the rows moved")
end

-- RF-3. Fails before: a recipe read in part was not saved.
tests["recipe book RF-3: a recipe read in part is kept, said partial, and left out of Recipes"] = function(t)
    local c, addon = start()
    c.setTradeSkillSchematic(2, { makes = BOLT, yield = 1, mats = {}, partial = true })
    classic(c, addon, { { index = 2, name = "Bolt of Linen Cloth" } })
    t.eq(book(c), { ["Bolt of Linen Cloth"] = { makes = BOLT, yield = 1, mats = {}, partial = true,
        profession = "Tailoring" } })
    t.eq(addon.RecipeBook.Recipes(addon), {}, "read in part: not planned from")
    t.eq(addon.RecipeBook.For(addon, BOLT), nil)
    c.setTradeSkillSchematic(2, { makes = BOLT, yield = 1, mats = { [LINEN] = 2 } })
    c.fire(addon.RecipeBook.EVENT)
    settle(c, addon)
    t.eq(book(c), { ["Bolt of Linen Cloth"] = CLASSIC_BOLT }, "read whole later: the whole one saved")
    t.eq(addon.RecipeBook.For(addon, BOLT), "Bolt of Linen Cloth")
end

-- RF-3. Fails before: the part read wrote over the whole one.
tests["recipe book RF-3: a recipe read in part does not write over the same recipe saved whole"] = function(t)
    local c, addon = start({ learned = { facts = { recipeBook = { ["Bolt of Linen Cloth"] = CLASSIC_BOLT } } } })
    c.setTradeSkillSchematic(2, { makes = BOLT, yield = 1, mats = { [LINEN] = 1 }, partial = true })
    classic(c, addon, { { index = 2, name = "Bolt of Linen Cloth" } })
    t.eq(book(c), { ["Bolt of Linen Cloth"] = CLASSIC_BOLT })
    t.eq(addon.recipeBook.last().ok, true)
    t.eq(addon.RecipeBook.For(addon, BOLT), "Bolt of Linen Cloth")
end

-- Section 245 -------------------------------------------------------------------

local ROBE = 6238
local CLASSIC_ROBE = { makes = ROBE, yield = 1, mats = { [LINEN] = 3 }, profession = "Tailoring" }

-- RB2-2. Fails at 1b4e461f: every row the classic window gave was read, so
-- the read counted as every learned recipe and the robe, hidden under a
-- collapsed header, was dropped as no longer learned (the fake had no
-- collapsed, filtered or whole to give).
tests["recipe book RB2-2: a classic read with rows hidden drops nothing"] = function(t)
    local c, addon = start({ learned = { facts = { recipeBook = {
        ["Bolt of Linen Cloth"] = CLASSIC_BOLT, ["Brown Linen Robe"] = CLASSIC_ROBE } } } })
    c.setTradeSkillSchematic(2, { makes = BOLT, yield = 1, mats = { [LINEN] = 2 } })
    local rows = { { index = 2, name = "Bolt of Linen Cloth" } }
    classic(c, addon, rows, { collapsed = true })
    t.eq(book(c)["Brown Linen Robe"], CLASSIC_ROBE, "a header collapsed: the robe stays")
    t.eq(addon.recipeBook.last().ok, true)
    classic(c, addon, rows, { collapsed = false, filtered = true })
    t.eq(book(c)["Brown Linen Robe"], CLASSIC_ROBE, "a filter on: the robe stays")
    classic(c, addon, rows)
    t.eq(book(c)["Brown Linen Robe"], CLASSIC_ROBE, "the window says nothing either way: the robe stays")
    classic(c, addon, rows, { collapsed = false, filtered = false, whole = true })
    t.eq(book(c), { ["Bolt of Linen Cloth"] = CLASSIC_BOLT },
        "the window says every learned recipe is shown: the robe is no longer learned")
end

-- Lead section 245 item 1 (LOW). Fails at 1b4e461f: the saved enchant has
-- no product, so it did not read as whole, and the part read wrote over it.
tests["recipe book: a recipe read in part does not write over a saved enchant"] = function(t)
    local saved = { yield = 1, mats = { [LINEN] = 1 }, difficulty = "optimal", profession = "Tailoring" }
    local c, addon = start({ learned = { facts = { recipeBook = { [ENCHANT] = saved } } } })
    c.setTradeSkillSchematic(3, { name = ENCHANT, yield = 1, mats = {}, partial = true })
    classic(c, addon, { { index = 3, name = ENCHANT } })
    t.eq(book(c)[ENCHANT], saved, "the saved enchant kept")
    t.eq(addon.recipeBook.last().ok, true)
end

-- GR2-4 (in part). Fails at 1b4e461f: two same-name rows with no id were
-- keyed in row order, so the same two recipes in the other order swapped
-- "name" and "name (2)", and the book was written again.
tests["recipe book GR2-4: two recipes of one name keep their keys in any row order"] = function(t)
    local c, addon = start()
    local A = { makes = BOLT, yield = 1, mats = { [LINEN] = 2 } }
    local B = { makes = BANDAGE, yield = 1, mats = { [LINEN] = 1 } }
    local rows = { { index = 2, name = "Bolt of Linen Cloth" }, { index = 3, name = "Bolt of Linen Cloth" } }
    c.setTradeSkillSchematic(2, A)
    c.setTradeSkillSchematic(3, B)
    local want = {
        ["Bolt of Linen Cloth"] = { makes = BANDAGE, yield = 1, mats = { [LINEN] = 1 }, profession = "Tailoring" },
        ["Bolt of Linen Cloth (2)"] = { makes = BOLT, yield = 1, mats = { [LINEN] = 2 }, profession = "Tailoring" },
    }
    classic(c, addon, rows)
    t.eq(book(c), want, "ordered by what each makes and takes, not by row")
    t.eq(addon.recipeBook.last().collided, 1)
    c.setTradeSkillSchematic(2, B)
    c.setTradeSkillSchematic(3, A)
    classic(c, addon, rows)
    t.eq(book(c), want, "the other row order: the same keys")
    t.eq(addon.recipeBook.last().unchanged, true, "nothing written")
end

-- RB4-1 (lead section 253, MyBuddy LOW). Fails at 8aa468bd: the client
-- never says whole, so a classic read never dropped a recipe no longer
-- learned, even with every header open and no filter on; legacy Flow
-- replaced the list each read. Now a classic read with every header
-- expanded (collapsed = false) and both filters on all (filtered = false)
-- counts as every learned recipe of that profession. Made-up rows.
tests["recipe book RB4-1: every header open and no filter: what is no longer learned is dropped"] = function(t)
    local bandage = { id = BANDAGE_ID, makes = BANDAGE, yield = 1, mats = { [LINEN] = 1 }, profession = "First Aid" }
    local c, addon = start({ learned = { facts = { recipeBook = {
        ["Bolt of Linen Cloth"] = CLASSIC_BOLT, ["Brown Linen Robe"] = CLASSIC_ROBE, ["Linen Bandage"] = bandage } } } })
    c.setTradeSkillSchematic(2, { makes = BOLT, yield = 1, mats = { [LINEN] = 2 } })
    local rows = { { index = 2, name = "Bolt of Linen Cloth" } }
    classic(c, addon, rows, { collapsed = false })
    t.eq(book(c)["Brown Linen Robe"], CLASSIC_ROBE, "filters not known: the robe stays")
    classic(c, addon, rows, { filtered = false })
    t.eq(book(c)["Brown Linen Robe"], CLASSIC_ROBE, "headers not known: the robe stays")
    classic(c, addon, rows, { collapsed = false, filtered = false })
    t.eq(addon.recipeBook.last().ok, true)
    t.eq(book(c), { ["Bolt of Linen Cloth"] = CLASSIC_BOLT, ["Linen Bandage"] = bandage },
        "nothing hidden, no filter: the robe is no longer learned; another profession's recipe stays")
end

-- RB4-1: a row whose schematic can't be read leaves the read short, so it
-- still drops nothing, headers open and no filter or not.
tests["recipe book RB4-1: a row not read: nothing dropped"] = function(t)
    local c, addon = start({ learned = { facts = { recipeBook = {
        ["Bolt of Linen Cloth"] = CLASSIC_BOLT, ["Brown Linen Robe"] = CLASSIC_ROBE } } } })
    c.setTradeSkillSchematic(2, { makes = BOLT, yield = 1, mats = { [LINEN] = 2 } })
    classic(c, addon, { { index = 2, name = "Bolt of Linen Cloth" }, { index = 3, name = "Unread" } },
        { collapsed = false, filtered = false })
    t.eq(book(c)["Brown Linen Robe"], CLASSIC_ROBE, "one row unread: the robe stays")
end

return tests
