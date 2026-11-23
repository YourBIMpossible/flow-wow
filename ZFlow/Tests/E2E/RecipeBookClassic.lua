local _, ns = ...
-- Section 238 (RF-1 to RF-3): the classic profession window read into the
-- recipe book, on the whole add-on loaded on a fake client, then the goals
-- list's make command reading the book. Cases (section 236): reagent data
-- arriving late (a recipe read in part, then whole), a reload (the book
-- read back), and a read that fails, then recovers. Made-up rows; not
-- tested in game.
--
-- What the fake client cannot express: the classic window's own reads
-- (GetTradeSkillInfo, GetTradeSkillItemLink, the reagent reads). The test
-- sets the schematic each row gives (c.setTradeSkillSchematic); those reads
-- are tested in Tests/Core/ClientReadsTests.lua. Nor whether the game fires
-- TRADE_SKILL_LIST_UPDATE again when late reagent data arrives: the test
-- fires it.
local tests = {}

local LINEN, BOLT = 2589, 2996
local ENCHANT = "Enchant Bracer - Minor Health"
local ROWS = { { index = 2, name = "Bolt of Linen Cloth", difficulty = "optimal" },
               { index = 3, name = ENCHANT, difficulty = "easy" } }

local function at(root, ...)
    for _, key in ipairs({ ... }) do
        if type(root) ~= "table" then return nil end
        root = root[key]
    end
    return root
end

-- opts.account / opts.char: saved tables (a reload).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setItemInfo({ [LINEN] = { name = "Linen Cloth", quality = 1, sellPrice = 13, classID = 7 },
                    [BOLT] = { name = "Bolt of Linen Cloth", quality = 1, sellPrice = 40, classID = 7 } })
    c.setBagItems({ { item = LINEN, count = 4 } })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function book(c) return at(c.saved(ns.id.charDB), "learned", "facts", "recipeBook") end

-- The classic window open on these schematics: no C_TradeSkillUI answer.
local function window(c, addon, bolt)
    c.setRecipes(nil)
    c.setTradeSkillRows({ name = "Tailoring", rows = ROWS })
    c.setTradeSkillSchematic(2, bolt)
    c.setTradeSkillSchematic(3, { name = ENCHANT, difficulty = "easy", yield = 1, mats = { [LINEN] = 1 } })
    c.fire(addon.RecipeBook.EVENT)
end

local WHOLE = { name = "Bolt of Linen Cloth", difficulty = "optimal", makes = BOLT, yield = 1,
                mats = { [LINEN] = 2 } }
local PART = { name = "Bolt of Linen Cloth", difficulty = "optimal", makes = BOLT, yield = 1,
               mats = {}, partial = true }

-- The goals list's make word, typed: what it printed, one line.
local function make(c)
    local from = #c.printed
    c.slashes[ns.id.slash]("goal make " .. BOLT .. " 3")
    local out = {}
    for i = from + 1, #c.printed do out[#out + 1] = tostring(c.printed[i]) end
    return table.concat(out, " | ")
end

local function planned(line) return line:find("(recipe: Bolt of Linen Cloth)", 1, true) ~= nil end

tests["recipe book classic: reagents late, then whole; the enchant kept, never planned"] = function(t)
    local c, addon = start()
    window(c, addon, PART)
    t.eq(book(c)["Bolt of Linen Cloth"].partial, true, "read in part: saved, said partial")
    t.eq(book(c)[ENCHANT].makes, nil, "the enchant saved with no product")
    t.eq(book(c)[ENCHANT].mats, { [LINEN] = 1 })
    t.ok(not planned(make(c)), "read in part: make finds no recipe")
    window(c, addon, WHOLE)
    t.eq(book(c)["Bolt of Linen Cloth"].partial, nil, "the late data read: whole")
    t.eq(book(c)["Bolt of Linen Cloth"].difficulty, "optimal")
    t.ok(planned(make(c)), make(c))
    window(c, addon, PART)
    t.eq(book(c)["Bolt of Linen Cloth"].mats, { [LINEN] = 2 }, "a part read again: the whole one kept")
    t.eq(addon.RecipeBook.Recipes(addon)[ENCHANT], nil, "the enchant: nothing to plan")
end

tests["recipe book classic: the book is read back after a reload"] = function(t)
    local c, addon = start()
    window(c, addon, WHOLE)
    local c2, addon2 = start({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB) })
    t.eq(book(c2)[ENCHANT].difficulty, "easy", "the enchant read back")
    t.eq(addon2.RecipeBook.For(addon2, BOLT), "Bolt of Linen Cloth", "the whole recipe read back")
    t.ok(planned(make(c2)), make(c2))
end

tests["recipe book classic: a read that fails, then recovers"] = function(t)
    local c, addon = start()
    window(c, addon, WHOLE)
    local before = addon.recipeBook.last()
    local read = c.tradeSkillSchematic
    c.tradeSkillSchematic = function() error("schematic read failed") end
    c.fire(addon.RecipeBook.EVENT)
    t.eq(addon.recipeBook.last(), before, "the failed read reports nothing new")
    t.eq(book(c)["Bolt of Linen Cloth"].mats, { [LINEN] = 2 }, "the book kept as it was")
    t.ok(planned(make(c)), "make still reads the saved book")
    c.tradeSkillSchematic = read
    window(c, addon, PART)
    window(c, addon, { name = "Bolt of Linen Cloth", difficulty = "trivial", makes = BOLT, yield = 1,
        mats = { [LINEN] = 3 } })
    t.eq(book(c)["Bolt of Linen Cloth"].mats, { [LINEN] = 3 }, "the read recovers: the new read saved")
    t.eq(book(c)["Bolt of Linen Cloth"].difficulty, "trivial")
    t.eq(addon.recipeBook.last().ok, true)
end

return tests
