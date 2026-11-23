local _, ns = ...
-- The craft bar as a kit window (lead sections 287 and 291): CraftBar.View
-- (UI/CraftBar.lua) is what the kit draws: each learned recipe as an item
-- line with the count queued and a button each way, then Start or Stop,
-- Smelt all on the mining window, From goals and Clear, and one line that
-- says what to do or why it stopped. First the view alone (no client, no
-- kernel), then end to end on the whole add-on loaded on a fake client: the
-- view's buttons are the same clicks the bar has, so nothing crafts without
-- the click on Start. Made-up names in the first part.
-- Offline: the reads are the fake client's, not the game's. Not tested in game.
-- Fails before the code: CraftBar.View is absent and the bar answers no
-- view, so every test fails its first check.
local tests = {}

local B = ns.CraftBar or {}

local function has(t)
    t.ok(type(B.View) == "function", "CraftBar.View is a function")
    return type(B.View) == "function"
end

local function model()
    return {
        recipes = {
            { id = 7, name = "Red Bar", count = 3, difficulty = "optimal", icon = "Interface\\Icons\\INV_Ingot_02" },
            { id = 8, name = "Grey Bar", count = 0 },
        },
        running = false, smelts = true,
    }
end

local function keyed(view, key)
    for _, part in ipairs(view.children) do
        if part.key == key then return part end
    end
    return nil
end

local function lines(view)
    local out = {}
    for _, part in ipairs(view.children) do
        if part.kind == "itemLine" then out[#out + 1] = part end
    end
    return out
end

-- Every click the view passed on, as { key, value }.
local function clicks()
    local said = {}
    return said, function(key, value) said[#said + 1] = { key, value } end
end

-- ------------------------------------------------------------------- view
tests["craft bar view: a kit window with a header and the hint"] = function(t)
    if not has(t) then return end
    local view = B.View(model())
    t.eq(view.id, "CraftBar")
    t.eq(view.title, B.TITLE)
    t.eq(view.children[1].kind, "header")
    t.eq(keyed(view, "status").label, B.HINT)
end

tests["craft bar view: the status line says why it stopped when there is a reason"] = function(t)
    if not has(t) then return end
    local m = model()
    m.status = "Stopped: you moved."
    t.eq(keyed(B.View(m), "status").label, "Stopped: you moved.")
end

tests["craft bar view: each recipe is an item line with its count, icon and skill colour"] = function(t)
    if not has(t) then return end
    local got = lines(B.View(model()))
    t.eq(#got, 2)
    t.eq({ got[1].name, got[1].count, got[1].icon }, { "Red Bar", 3, "Interface\\Icons\\INV_Ingot_02" })
    t.eq(got[1].color.hex, "ff8040", "orange, the helper's colours")
    t.eq({ got[2].name, got[2].count }, { "Grey Bar", 0 })
    t.eq(got[2].color, nil, "a colour not read is left to the kit")
end

tests["craft bar view: a button each way sets the count, within 0 and the most a run takes"] = function(t)
    if not has(t) then return end
    local said, act = clicks()
    local view = B.View(model(), act)
    keyed(view, "more:7").onClick()
    keyed(view, "less:7").onClick()
    t.eq(said, { { "count:7", 4 }, { "count:7", 2 } })
    t.eq(keyed(view, "less:8").enabled, false, "nothing to lower")
    keyed(view, "less:8").onClick()
    t.eq(#said, 2, "a button that is off passes nothing on")
    local m = model()
    m.recipes[1].count = ns.CraftQueue.MAX
    t.eq(keyed(B.View(m), "more:7").enabled, false)
end

tests["craft bar view: Start, Smelt all, From goals and Clear pass the bar's own clicks on"] = function(t)
    if not has(t) then return end
    local said, act = clicks()
    local view = B.View(model(), act)
    t.eq(keyed(view, "start").text, "Start")
    for _, key in ipairs({ "start", "all", "goals", "clear" }) do keyed(view, key).onClick() end
    t.eq(said, { { "start" }, { "all" }, { "goals" }, { "clear" } })
end

tests["craft bar view: Smelt all only on a window that smelts"] = function(t)
    if not has(t) then return end
    local m = model()
    m.smelts = false
    t.eq(keyed(B.View(m), "all"), nil)
end

tests["craft bar view: while a craft runs only Stop is on"] = function(t)
    if not has(t) then return end
    local m = model()
    m.running = true
    local said, act = clicks()
    local view = B.View(m, act)
    t.eq({ keyed(view, "start").text, keyed(view, "start").enabled }, { "Stop", true })
    for _, key in ipairs({ "more:7", "less:7", "all", "goals", "clear" }) do
        t.eq(keyed(view, key).enabled, false, key)
        keyed(view, key).onClick()
    end
    t.eq(#said, 0)
end

tests["craft bar view: no recipe known: what is missing and how to get it, and no buttons"] = function(t)
    if not has(t) then return end
    local view = B.View({ recipes = {}, running = false, smelts = false })
    local part = keyed(view, "recipes")
    t.eq({ part.kind, part.text, part.how }, { "empty", B.NO_RECIPES, B.NO_RECIPES_HOW })
    t.ok(type(B.NO_RECIPES_HOW) == "string" and B.NO_RECIPES_HOW ~= "", "says how")
    t.eq(keyed(view, "start"), nil)
end

tests["craft bar view: the kit takes every view as a window"] = function(t)
    if not has(t) then return end
    local K = ns.Kit
    t.ok(type(K) == "table" and type(K.Window) == "function", "ns.Kit.Window is there (UI/Kit.lua, zflow-kit-api)")
    if type(K) ~= "table" or type(K.Window) ~= "function" then return end
    local running = model()
    running.running = true
    for label, m in pairs({ full = model(), running = running, none = { recipes = {} } }) do
        local tree, why = K.Window(B.View(m))
        t.ok(type(tree) == "table", label .. ": " .. tostring(why))
    end
end

-- ------------------------------------------------------------- end to end
local MINING = 186
local COPPER_BAR, TIN_BAR, SILVER_BAR = 2657, 3304, 2658
local ORE_COPPER, ORE_TIN = 2770, 2771

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setItemInfo({ [ORE_COPPER] = { name = "Copper Ore" }, [ORE_TIN] = { name = "Tin Ore" } })
    c.setBags({ { free = 4, total = 16, family = 0 } })
    c.setRecipes({ profession = MINING, skill = 70, max = 75, recipes = {
        { id = COPPER_BAR, name = "Copper Bar", learned = true, difficulty = "easy" },
        { id = TIN_BAR, name = "Tin Bar", learned = true },
        { id = SILVER_BAR, name = "Silver Bar", learned = false },
    } })
    c.setRecipeSchematic(COPPER_BAR, { makes = 2840, yield = 1, mats = { [ORE_COPPER] = 1 } })
    c.setRecipeSchematic(TIN_BAR, { makes = 3576, yield = 1, mats = { [ORE_TIN] = 1 } })
    c.setRecipeUsable(COPPER_BAR, true)
    c.setRecipeUsable(TIN_BAR, true)
    c.setMoving(false)
    c.setItemCount(ORE_COPPER, 10)
    c.setItemCount(ORE_TIN, 0)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    if opts.open ~= false then
        c.fire("TRADE_SKILL_SHOW")
        c.fire("TRADE_SKILL_LIST_UPDATE")
        c.advance(addon.RecipeBook.SETTLE, 1)
        -- The bar opens collapsed (lead section 341); these cases are for
        -- the open bar, so the heading is clicked once here.
        if opts.folded ~= true then c.kitClick("CraftBar", "fold") end
    end
    return c, addon
end

-- The bar's view now, or nil; fails the test when the bar answers none.
local function viewOf(t, addon)
    local api = addon.craftBar
    local ok = type(api) == "table" and type(api.view) == "function"
    t.ok(ok, "the bar answers a view")
    if not ok then return nil end
    return api.view()
end

tests["craft bar view e2e: no window open, no view; closing the window ends it"] = function(t)
    local c, addon = start({ open = false })
    local api = addon.craftBar
    t.ok(type(api) == "table" and type(api.view) == "function", "the bar answers a view")
    if not (type(api) == "table" and type(api.view) == "function") then return end
    t.eq(api.view(), nil)
    c.fire("TRADE_SKILL_SHOW")
    t.ok(api.view() ~= nil, "the open window has a view")
    c.fire("TRADE_SKILL_CLOSE")
    t.eq(api.view(), nil)
end

tests["craft bar view e2e: the learned recipes, each with no count, and Smelt all on mining"] = function(t)
    local _, addon = start()
    local view = viewOf(t, addon)
    if not view then return end
    local got = lines(view)
    t.eq(#got, 2, "the recipe not learned is not listed")
    t.eq({ got[1].name, got[1].count, got[1].color.hex }, { "Copper Bar", 0, "40c040" })
    t.eq({ got[2].name, got[2].count }, { "Tin Bar", 0 })
    t.ok(keyed(view, "all") ~= nil, "Smelt all")
    t.eq(keyed(view, "status").label, B.HINT)
end

tests["craft bar view e2e: a count button asks no craft; Start asks the count once"] = function(t)
    local c, addon = start()
    local view = viewOf(t, addon)
    if not view then return end
    keyed(view, "more:" .. COPPER_BAR).onClick()
    view = addon.craftBar.view()
    keyed(view, "more:" .. COPPER_BAR).onClick()
    t.eq(#c.crafts, 0, "counts ask nothing")
    t.eq(addon.craftBar.running(), false)
    view = addon.craftBar.view()
    t.eq(lines(view)[1].count, 2)
    keyed(view, "start").onClick()
    t.eq(c.crafts, { { id = COPPER_BAR, n = 2 } }, "one ask, the count as the repeat count")
    t.eq(addon.craftBar.running(), true)
    view = addon.craftBar.view()
    t.eq(keyed(view, "start").text, "Stop")
    t.eq(keyed(view, "clear").enabled, false)
    keyed(view, "start").onClick()
    t.eq(addon.craftBar.running(), false, "Stop stops")
end

tests["craft bar view e2e: Start with no count says to tick one"] = function(t)
    local _, addon = start()
    local view = viewOf(t, addon)
    if not view then return end
    keyed(view, "start").onClick()
    t.eq(addon.craftBar.running(), false)
    t.eq(keyed(addon.craftBar.view(), "status").label, B.NOTHING)
end

return tests
