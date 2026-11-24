local _, ns = ...
-- The "use it to learn" prompt (UI/ProfLearn.lua), on the whole add-on
-- loaded on a fake client, through the real entry: on entering the world
-- and on BAG_UPDATE_DELAYED, a recipe item in the bags whose recipe the
-- saved recipe book does not hold gives one advisor prompt. Look only: the
-- item is never used, crafted with or sold. Made-up items; not tested in
-- game.
local tests = {}

local RECIPE = 5001
local ID = "aps.proflearn." .. RECIPE
local TEXT = "Recipe: Test Stew is in your bags: use it to learn Test Stew."
local INFO = { [RECIPE] = { name = "Recipe: Test Stew" } }

-- opts.char: the character saved table; opts.info: the item facts.
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setBagItems({ { item = RECIPE, count = 1 } })
    c.setItemInfo(opts.info)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function prompt(addon)
    local advisor = addon.use("advisor")
    if type(advisor) ~= "table" or type(advisor.List) ~= "function" then return nil end
    for _, p in ipairs(advisor.List()) do
        if p.id == ID then return p end
    end
    return nil
end

local function nothingActs(t, c)
    t.eq(#c.crafts, 0, "nothing is crafted")
    t.eq(#c.soldSlots, 0, "nothing is sold")
end

tests["prof learn: a recipe in the bags not in the book gives one prompt, gone when it leaves"] = function(t)
    local c, addon = boot({ info = INFO })
    local p = prompt(addon)
    t.eq(p and p.text, TEXT)
    local bag = c.bagItems() or {}
    t.eq(bag[1] and bag[1].item, RECIPE, "the recipe is not used")
    nothingActs(t, c)
    c.setBagItems({})
    c.fire("BAG_UPDATE_DELAYED"); c.advance(2, 4)
    t.eq(prompt(addon), nil, "the recipe left the bags: the prompt goes")
end

tests["prof learn: a recipe the book holds gives no prompt"] = function(t)
    local c, addon = boot({ info = INFO, char = { learned = { facts = { recipeBook = {
        ["Test Stew"] = { id = 77, makes = 6001, yield = 1, mats = {}, profession = 185 } } } } } })
    t.eq(prompt(addon), nil)
    nothingActs(t, c)
end

tests["prof learn: an item whose name is not known gives no prompt"] = function(t)
    local c, addon = boot()
    t.eq(prompt(addon), nil, "no item facts: no guess")
    nothingActs(t, c)
end

return tests
