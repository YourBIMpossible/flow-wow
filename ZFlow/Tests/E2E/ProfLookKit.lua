local _, ns = ...
-- The craft bar and the skill-up helper drawn by the kit (lead sections 287,
-- 291 and 297 item 5): on a profession window each is a kit window
-- (client.kitWindow, UI/Kit.lua) built from its view, and its buttons are
-- the same clicks the plain panel has. When the kit refuses the window the
-- plain panel draws in its place, with one problem line. End to end on the
-- whole add-on loaded on a fake client.
-- Offline: the reads and the kit window are the fake client's, not the
-- game's. Not tested in game.
-- Fails before the code: no module asks the client for a kit window, so
-- c.kitWindows() holds neither window and every test fails its first check.
local tests = {}

local B = ns.CraftBar or {}
local H = ns.ProfHelper or {}

local MINING = 186
local COPPER_BAR, TIN_BAR, SILVER_BAR = 2657, 3304, 2658
local ORE_COPPER, ORE_TIN = 2770, 2771

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    if opts.fails then c.setKitFails(opts.fails) end
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setItemInfo({ [ORE_COPPER] = { name = "Copper Ore" }, [ORE_TIN] = { name = "Tin Ore" } })
    c.setBags({ { free = 4, total = 16, family = 0 } })
    c.setRecipes({ profession = MINING, skill = 70, max = 75, recipes = {
        -- A numbered icon: the kit takes icon text only.
        { id = COPPER_BAR, name = "Copper Bar", learned = true, difficulty = "easy", icon = 133216 },
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
    if opts.off then addon.settings:set(opts.off, false) end
    if opts.open ~= false then
        c.fire("TRADE_SKILL_SHOW")
        c.fire("TRADE_SKILL_LIST_UPDATE")
        c.advance(addon.RecipeBook.SETTLE, 1)
    end
    return c, addon
end

-- The kit window of that id as the fake client holds it, or nil.
local function kit(c, id)
    if type(c.kitWindows) ~= "function" then return nil end
    return c.kitWindows()[id]
end

-- The kit window, shown; fails the test when it is not there.
local function shownKit(t, c, id)
    local w = kit(c, id)
    t.ok(w ~= nil, id .. " is a kit window")
    if w == nil then return nil end
    t.eq(w.shown, true, id .. " is shown")
    return w
end

local function part(w, key)
    for _, p in ipairs(w and w.parts or {}) do
        if p.key == key then return p end
    end
    return nil
end

local function textOf(w, key)
    local p = part(w, key)
    if p == nil then return nil end
    return p.text
end

local function panelOf(c, name)
    for _, p in ipairs(c.rowPanels or {}) do
        if type(p.spec) == "table" and p.spec.name == ns.id.framePrefix .. name then return p end
    end
    return nil
end

local function panelShown(c, name)
    local p = panelOf(c, name)
    if p == nil then return false end
    return p.shown()
end

local function hostProblems(addon)
    local kind = ns.KitHost and ns.KitHost.PROBLEM or "kitHost"
    return addon.problems:count(kind)
end

-- -------------------------------------------------------------- craft bar
tests["prof look kit: the craft bar is a kit window on a profession window"] = function(t)
    local c, addon = start()
    local w = shownKit(t, c, "CraftBar")
    if not w then return end
    t.eq(w.parts[1].kind, "header")
    t.eq(textOf(w, "status"), B.HINT)
    t.eq(textOf(w, "start"), "Start")
    t.ok(part(w, "more:" .. COPPER_BAR) ~= nil, "a count button for a learned recipe")
    t.eq(part(w, "more:" .. SILVER_BAR), nil, "none for a recipe not learned")
    t.ok(part(w, "all") ~= nil, "Smelt all on the mining window")
    t.eq(panelShown(c, "CraftBar"), false, "the plain panel stays hidden")
    t.eq(hostProblems(addon), 0)
end

tests["prof look kit: no profession window, no craft bar"] = function(t)
    local c = start({ open = false })
    local w = kit(c, "CraftBar")
    t.ok(w == nil or w.shown == false, "not shown")
    c.fire("TRADE_SKILL_SHOW")
    if not shownKit(t, c, "CraftBar") then return end
    c.fire("TRADE_SKILL_CLOSE")
    t.eq(kit(c, "CraftBar").shown, false, "hidden with the window")
end

tests["prof look kit: the craft bar's kit buttons are the bar's clicks; Start asks the count once"] = function(t)
    local c, addon = start()
    if not shownKit(t, c, "CraftBar") then return end
    t.eq(c.kitClick("CraftBar", "more:" .. COPPER_BAR), true)
    t.eq(c.kitClick("CraftBar", "more:" .. COPPER_BAR), true)
    t.eq(#c.crafts, 0, "counts ask nothing")
    t.eq(c.kitClick("CraftBar", "less:" .. TIN_BAR), false, "a button that is off takes no click")
    t.eq(c.kitClick("CraftBar", "start"), true)
    t.eq(c.crafts, { { id = COPPER_BAR, n = 2 } }, "one ask, the count as the repeat count")
    t.eq(addon.craftBar.running(), true)
    local w = kit(c, "CraftBar")
    t.eq(textOf(w, "start"), "Stop", "the window is drawn again")
    t.eq(c.kitClick("CraftBar", "clear"), false, "only Stop while a craft runs")
    t.eq(c.kitClick("CraftBar", "start"), true)
    t.eq(addon.craftBar.running(), false, "Stop stops")
    t.eq(#c.crafts, 1, "Stop asks no craft")
end

tests["prof look kit: closing the craft bar's kit window stops the run"] = function(t)
    local c, addon = start()
    if not shownKit(t, c, "CraftBar") then return end
    c.kitClick("CraftBar", "more:" .. COPPER_BAR)
    c.kitClick("CraftBar", "start")
    t.eq(addon.craftBar.running(), true)
    t.eq(c.kitClose("CraftBar"), true)
    t.eq(addon.craftBar.running(), false)
    t.eq(#c.crafts, 1)
end

tests["prof look kit: the craft bar off in settings: no kit window, no plain panel"] = function(t)
    local c = start({ off = B.SETTING })
    local w = kit(c, "CraftBar")
    t.ok(w == nil or w.shown == false, "no kit window shown")
    t.eq(panelShown(c, "CraftBar"), false)
end

-- ----------------------------------------------------------------- helper
tests["prof look kit: the skill-up helper is a kit window on a profession window"] = function(t)
    local c, addon = start()
    local w = shownKit(t, c, "ProfHelper")
    if not w then return end
    t.eq(w.parts[1].kind, "header")
    t.eq(w.parts[1].text, H.HEAD_NONAME:format(70, 75), "a numbered profession names none")
    t.eq(textOf(w, "goal"), H.NO_GOAL)
    t.ok(part(w, "goalUp") ~= nil, "Goal +")
    t.eq(panelShown(c, "ProfHelper"), false, "the plain panel stays hidden")
    t.eq(hostProblems(addon), 0)
end

tests["prof look kit: Goal + on the helper's kit window keeps the goal on the character"] = function(t)
    local c = start()
    if not shownKit(t, c, "ProfHelper") then return end
    t.eq(c.kitClick("ProfHelper", "goalDown"), false, "no goal to lower")
    t.eq(c.kitClick("ProfHelper", "goalUp"), true)
    local goal = 70 + H.GOAL_STEP
    local saved = c.saved(ns.id.charDB)
    t.eq(saved.state.profGoals[MINING], goal)
    local text = textOf(kit(c, "ProfHelper"), "goal")
    t.ok(type(text) == "string" and text:find(H.GOAL:format(goal), 1, true) == 1, "the window is drawn again: " .. tostring(text))
    t.eq(#c.crafts, 0, "the helper never crafts")
end

tests["prof look kit: the helper closed by the player stays closed until the window opens again"] = function(t)
    local c = start()
    if not shownKit(t, c, "ProfHelper") then return end
    t.eq(c.kitClose("ProfHelper"), true)
    c.advance(H.EVERY * 3, 6)
    c.fire("TRADE_SKILL_LIST_UPDATE")
    t.eq(kit(c, "ProfHelper").shown, false, "the look at the setting does not bring it back")
    c.fire("TRADE_SKILL_CLOSE")
    c.fire("TRADE_SKILL_SHOW")
    t.eq(kit(c, "ProfHelper").shown, true, "the next profession window shows it")
end

tests["prof look kit: the helper off in settings hides its kit window at the next look"] = function(t)
    local c, addon = start()
    if not shownKit(t, c, "ProfHelper") then return end
    addon.settings:set(H.SETTING, false)
    c.advance(H.EVERY * 2, 4)
    t.eq(kit(c, "ProfHelper").shown, false)
    addon.settings:set(H.SETTING, true)
    c.advance(H.EVERY * 2, 4)
    t.eq(kit(c, "ProfHelper").shown, true, "on again with the window still open")
end

-- --------------------------------------------------------------- fallback
tests["prof look kit: the kit refuses the windows: both plain panels draw, one problem each"] = function(t)
    local c, addon = start({ fails = math.huge })
    t.ok(ns.KitHost ~= nil, "UI/KitHost.lua is loaded")
    t.eq(kit(c, "CraftBar"), nil)
    t.eq(kit(c, "ProfHelper"), nil)
    t.eq(panelShown(c, "CraftBar"), true, "the craft bar's plain panel")
    t.eq(panelShown(c, "ProfHelper"), true, "the helper's plain panel")
    local bar = panelOf(c, "CraftBar")
    t.ok(bar ~= nil and #bar.rows > 0, "the plain panel has its rows")
    t.eq(hostProblems(addon), 2)
    c.fire("TRADE_SKILL_LIST_UPDATE")
    c.fire("TRADE_SKILL_CLOSE")
    c.fire("TRADE_SKILL_SHOW")
    t.eq(hostProblems(addon), 2, "said once for each window, not at every draw")
    if bar == nil then return end
    t.eq(bar.press("count:" .. COPPER_BAR, 2), true)
    t.eq(bar.press("start"), true)
    t.eq(c.crafts, { { id = COPPER_BAR, n = 2 } }, "the plain panel still reaches the bar's click")
end

tests["prof look kit: a kit window that fails later hands over to the plain panel, still shown"] = function(t)
    local c, addon = start()
    if not shownKit(t, c, "CraftBar") then return end
    c.setKitFails(1)
    -- The count click draws the bar again; that draw is refused.
    c.kitClick("CraftBar", "more:" .. COPPER_BAR)
    t.eq(kit(c, "CraftBar").shown, false, "the kit window is put away")
    t.eq(panelShown(c, "CraftBar"), true, "the plain panel takes over")
    t.eq(hostProblems(addon), 1)
    local bar = panelOf(c, "CraftBar")
    if bar == nil then return end
    t.eq(bar.press("start"), true)
    t.eq(c.crafts, { { id = COPPER_BAR, n = 1 } }, "the count ticked on the kit window is kept")
end

tests["prof look kit: a numbered recipe icon does not cost the window"] = function(t)
    local K = ns.Kit
    t.ok(type(K) == "table" and type(K.Window) == "function", "ns.Kit.Window is there")
    if type(K) ~= "table" or type(K.Window) ~= "function" then return end
    local bar, whyBar = K.Window(B.View({ recipes = { { id = 7, name = "Red Bar", count = 1, icon = 133216 } } }))
    t.ok(type(bar) == "table", "craft bar: " .. tostring(whyBar))
    local helper, whyHelper = K.Window(H.View({ profession = "Mining", skill = 1, max = 75,
        recipes = { { name = "Red Bar", chance = "sure", icon = 133216 } } }))
    t.ok(type(helper) == "table", "helper: " .. tostring(whyHelper))
end

return tests
