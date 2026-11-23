local _, ns = ...
-- Lead section 357 item 4 (P-CRAFT rows not re-checked): batch craft and
-- Smelt all re-checked against the current tree, through the bar the
-- player clicks, on the whole add-on on a fake client. Made-up counts.
-- Offline only; not tested in game (every client read is a first guess).
local tests = {}

local MINING = 186
local COPPER_BAR, TIN_BAR, SILVER_BAR = 2657, 3304, 2658
local ORE_COPPER, ORE_TIN = 2770, 2771
local ITEM_COPPER_BAR, ITEM_TIN_BAR = 2840, 3576

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    -- These cases are the plain panel: the kit window is refused, so the
    -- panel behind it draws (lead section 297 item 5, the fallback).
    if type(c.setKitFails) == "function" then c.setKitFails(math.huge) end
    c.setSaved(ns.id.accountDB, opts.account or {})
    local char = opts.char or {}
    if opts.goals then char.settings = { goals = opts.goals } end
    if opts.book then char.learned = { facts = { recipeBook = opts.book } } end
    c.setSaved(ns.id.charDB, char)
    c.setItemInfo({ [ORE_COPPER] = { name = "Copper Ore" }, [ORE_TIN] = { name = "Tin Ore" } })
    c.setBags(opts.bags or { { free = 4, total = 16, family = 0 } })
    c.setRecipes({ profession = opts.profession or MINING, skill = 70, max = 75, recipes = {
        { id = COPPER_BAR, name = "Copper Bar", learned = true },
        { id = TIN_BAR, name = "Tin Bar", learned = true },
        { id = SILVER_BAR, name = "Silver Bar", learned = false },
    } })
    -- Section 231: the bar reads the recipe from c.recipeSchematic, the read
    -- the recipe book and the goals list use (Items/RecipeBook.lua).
    if opts.schematic ~= false then
        c.setRecipeSchematic(COPPER_BAR, { makes = ITEM_COPPER_BAR, yield = 1, mats = { [ORE_COPPER] = 1 } })
        c.setRecipeSchematic(TIN_BAR, { makes = ITEM_TIN_BAR, yield = 1, mats = { [ORE_TIN] = 1 } })
    end
    if opts.bagItems then c.setBagItems(opts.bagItems) end
    c.setRecipeUsable(COPPER_BAR, true)
    c.setRecipeUsable(TIN_BAR, true)
    c.setMoving(false)
    c.setItemCount(ORE_COPPER, opts.copper or 10)
    c.setItemCount(ORE_TIN, opts.tin or 0)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    -- The window opens, then its list answers (the recipe book reads it).
    if opts.open ~= false then
        c.fire("TRADE_SKILL_SHOW")
        c.fire("TRADE_SKILL_LIST_UPDATE")
        -- Section 245 (RB2-1): the book reads once the window settles.
        c.advance(addon.RecipeBook.SETTLE, 1)
    end
    return c, addon
end

local function barOf(c)
    for _, p in ipairs(c.rowPanels or {}) do
        if type(p.spec) == "table" and p.spec.name == ns.id.framePrefix .. "CraftBar" then return p end
    end
    return nil
end

local function rowOf(bar, key)
    for _, r in ipairs(bar and bar.rows or {}) do
        if r.key == key then return r end
    end
    return nil
end

local function infos(bar)
    local out = {}
    for _, r in ipairs(bar and bar.rows or {}) do
        if r.kind == "info" then out[#out + 1] = r.text end
    end
    return table.concat(out, " | ")
end

local function done(c, id)
    c.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-guid", id)
end



tests["craft check: Smelt all with no ore says so and crafts nothing"] = function(t)
    local c, addon = start({ copper = 0, tin = 0 })
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    bar.press("all")
    t.eq(#c.crafts, 0, "no ore, no craft")
    t.eq(addon.craftBar.running(), false)
    t.ok(infos(bar):find(ns.CraftBar and ns.CraftBar.NOTHING_TO_SMELT or "Nothing to smelt", 1, true) ~= nil,
        "the bar says why, not silent: " .. infos(bar))
end

tests["craft check: Smelt all never ticks a recipe not learned"] = function(t)
    local c = start({ copper = 4, tin = 2 })
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    bar.press("all")
    local silver = rowOf(bar, "count:" .. SILVER_BAR)
    t.ok(silver == nil or silver.value == 0, "Silver Bar is not learned: not ticked")
end

tests["craft check: Smelt all in a fight crafts nothing"] = function(t)
    local c, addon = start({ copper = 4 })
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    c.setCombat(true)
    bar.press("all")
    t.eq(#c.crafts, 0, "a click in a fight crafts nothing")
    t.eq(addon.craftBar.running(), false)
end

tests["craft check: Smelt all run to the end, one click per recipe, then done"] = function(t)
    local c, addon = start({ copper = 2, tin = 1 })
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    bar.press("all")
    t.eq(c.crafts, { { id = COPPER_BAR, n = 2 } })
    done(c, COPPER_BAR); done(c, COPPER_BAR)
    t.eq(addon.craftBar.running(), false, "waits for the click")
    t.eq(#c.crafts, 1, "the finish asks nothing")
    bar.press("start")
    t.eq(c.crafts, { { id = COPPER_BAR, n = 2 }, { id = TIN_BAR, n = 1 } })
    done(c, TIN_BAR)
    t.eq(#c.crafts, 2, "nothing past the counts")
    t.eq(addon.craftBar.running(), false)
    t.ok(infos(bar):find("Made 2 x Copper Bar, 1 x Tin Bar.", 1, true) ~= nil, infos(bar))
end

tests["craft check: a recipe that takes two ore ticks what the ore covers, rounded down"] = function(t)
    local c = start({ copper = 5, open = false })
    c.setRecipeSchematic(COPPER_BAR, { makes = ITEM_COPPER_BAR, yield = 1, mats = { [ORE_COPPER] = 2 } })
    c.fire("TRADE_SKILL_SHOW"); c.fire("TRADE_SKILL_LIST_UPDATE"); c.advance(5, 10)
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    bar.press("all")
    t.eq(rowOf(bar, "count:" .. COPPER_BAR).value, 2, "5 ore at 2 each: 2")
    t.eq(c.crafts, { { id = COPPER_BAR, n = 2 } })
end

return tests
