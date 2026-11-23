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
--
-- Lead sections 340 item 2 and 341 (the last block of this file): both
-- windows open collapsed, stand under the profession window when the client
-- says where it is, carry the product's quality, and the helper's notes name
-- each reagent and where it comes from. The older cases unfold both windows
-- in their setup (opts.folded = true leaves them as they open).
-- Red before that code: no part is keyed "fold", so the collapsed, dock,
-- quality and notes cases fail their first check.
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
    c.setItemInfo(opts.items or { [ORE_COPPER] = { name = "Copper Ore" }, [ORE_TIN] = { name = "Tin Ore" } })
    if opts.account then c.setSaved(ns.id.accountDB, opts.account) end
    if opts.screen then c.setScreen(opts.screen[1], opts.screen[2]) end
    for name, rect in pairs(opts.rects or {}) do c.setFrameRect(name, rect) end
    c.setBags({ { free = 4, total = 16, family = 0 } })
    c.setRecipes({ profession = MINING, skill = 70, max = 75, recipes = {
        -- A numbered icon, as the game hands one out.
        { id = COPPER_BAR, name = "Copper Bar", learned = true, difficulty = "easy", icon = 133216 },
        { id = TIN_BAR, name = "Tin Bar", learned = true },
        { id = SILVER_BAR, name = "Silver Bar", learned = false },
    } })
    c.setRecipeSchematic(COPPER_BAR, { makes = 2840, yield = 1, mats = { [ORE_COPPER] = 1 } })
    c.setRecipeSchematic(TIN_BAR, { makes = 3576, yield = 1, mats = { [ORE_TIN] = 1 } })
    c.setRecipeUsable(COPPER_BAR, true)
    c.setRecipeUsable(TIN_BAR, true)
    c.setMoving(false)
    c.setItemCount(ORE_COPPER, opts.copper or 10)
    c.setItemCount(ORE_TIN, 0)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    if opts.off then addon.settings:set(opts.off, false) end
    if opts.open ~= false then
        c.fire("TRADE_SKILL_SHOW")
        c.fire("TRADE_SKILL_LIST_UPDATE")
        c.advance(addon.RecipeBook.SETTLE, 1)
        -- Both windows open collapsed (section 341): the cases written for
        -- the open windows unfold them here.
        if opts.folded ~= true then
            c.kitClick("CraftBar", "fold")
            c.kitClick("ProfHelper", "fold")
        end
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

-- Whether some part of a view carries this icon, however deep it sits.
local function carriesIcon(view, icon, seen)
    if type(view) ~= "table" then return false end
    seen = seen or {}
    if seen[view] then return false end
    seen[view] = true
    if view.icon == icon then return true end
    for _, v in pairs(view) do
        if carriesIcon(v, icon, seen) then return true end
    end
    return false
end

tests["prof look kit: a numbered recipe icon is handed to the kit"] = function(t)
    local bar = B.View({ recipes = { { id = 7, name = "Red Bar", count = 1, icon = 133216 } } })
    t.ok(carriesIcon(bar, 133216), "craft bar: the recipe's file number is on its line")
    local helper = H.View({ profession = "Mining", skill = 1, max = 75,
        recipes = { { name = "Red Bar", chance = "sure", icon = 133216 } } })
    t.ok(carriesIcon(helper, 133216), "helper: the recipe's file number is on its line")
    -- Not a path and not a file number: left out, the line stays.
    local odd = B.View({ recipes = { { id = 7, name = "Red Bar", count = 1, icon = true } } })
    t.ok(not carriesIcon(odd, true), "an icon that is neither is left out")
    local K = ns.Kit
    if type(K) == "table" and type(K.Window) == "function" then
        local tree, why = K.Window(odd)
        t.ok(type(tree) == "table", "and does not cost the window: " .. tostring(why))
    end
end

-- ------------------------------------------- sections 340 item 2 and 341
local BAR_COPPER = 2840
local FRAME = "TradeSkillFrame"
-- The profession window on a 1024 x 768 screen: 180 free under it.
local RECT = { l = 16, r = 400, b = 180, t = 692 }

tests["prof dock: both windows open collapsed; a click on the heading unfolds, another folds"] = function(t)
    local c = start({ folded = true })
    local bar, helper = shownKit(t, c, "CraftBar"), shownKit(t, c, "ProfHelper")
    if not bar or not helper then return end
    t.eq(bar.parts[1].kind, "header")
    t.ok(part(bar, "fold") ~= nil, "the craft bar has a heading that folds")
    t.eq(part(bar, "fold") and part(bar, "fold").kind, "section")
    t.eq(textOf(bar, "status"), B.HINT, "the status line is kept")
    t.eq(part(bar, "more:" .. COPPER_BAR), nil, "no recipe buttons while collapsed")
    t.eq(part(bar, "start"), nil, "no Start while collapsed")
    t.ok(part(helper, "fold") ~= nil, "the helper has a heading that folds")
    t.eq(textOf(helper, "goal"), H.NO_GOAL, "the goal line is kept")
    t.eq(part(helper, "goalUp"), nil, "no goal buttons while collapsed")

    t.eq(c.kitClick("CraftBar", "fold"), true)
    t.ok(part(kit(c, "CraftBar"), "start") ~= nil, "unfolded: Start")
    t.eq(part(kit(c, "ProfHelper"), "goalUp"), nil, "one window's fold is not the other's")
    t.eq(c.kitClick("ProfHelper", "fold"), true)
    t.ok(part(kit(c, "ProfHelper"), "goalUp") ~= nil, "unfolded: Goal +")
    t.eq(#c.crafts, 0, "folding asks no craft")

    -- The choice is kept for the session: the next profession window opens
    -- as the last one was left.
    c.fire("TRADE_SKILL_CLOSE")
    c.fire("TRADE_SKILL_SHOW")
    t.ok(part(kit(c, "CraftBar"), "start") ~= nil, "still unfolded at the next window")
    t.eq(c.kitClick("CraftBar", "fold"), true)
    t.eq(part(kit(c, "CraftBar"), "start"), nil, "folded again")
end

tests["prof dock: a craft under way keeps Stop on the collapsed craft bar"] = function(t)
    local c, addon = start()
    if not shownKit(t, c, "CraftBar") then return end
    c.kitClick("CraftBar", "more:" .. COPPER_BAR)
    c.kitClick("CraftBar", "start")
    t.eq(addon.craftBar.running(), true)
    t.eq(c.kitClick("CraftBar", "fold"), true, "folding is allowed while a craft runs")
    t.eq(addon.craftBar.running(), true, "and stops nothing")
    local w = kit(c, "CraftBar")
    t.eq(textOf(w, "start"), "Stop", "Stop stays in reach")
    t.eq(part(w, "more:" .. COPPER_BAR), nil, "the list is folded away")
    t.eq(c.kitClick("CraftBar", "start"), true)
    t.eq(addon.craftBar.running(), false)
    t.eq(part(kit(c, "CraftBar"), "start"), nil, "no Start on the collapsed bar once it stopped")
    t.eq(#c.crafts, 1)
end

tests["prof dock: where the two windows stand under a profession window (pure)"] = function(t)
    t.ok(type(B.Dock) == "function", "CraftBar.Dock")
    if type(B.Dock) ~= "function" then return end
    local d = B.Dock(RECT, 1024, 768)
    t.ok(type(d) == "table" and type(d.list) == "table" and type(d.goal) == "table", "both places")
    if type(d) ~= "table" or not d.list or not d.goal then return end
    local top = RECT.b - B.DOCK_GAP
    t.eq(d.list.point, { "TOPLEFT", "BOTTOMLEFT", RECT.l, top }, "the list: under its left corner")
    t.eq(d.goal.point, { "TOPLEFT", "BOTTOMLEFT", RECT.l + B.KIT_WIDTH + B.DOCK_GAP, top },
        "the goal: at the right, never on the list")
    t.eq(d.list.height, top - B.DOCK_GAP, "as high as the room under the window")
    t.eq(d.goal.height, top - B.DOCK_GAP)
    -- A wide profession window: the helper's right edge is the window's.
    local wide = B.Dock({ l = 16, r = 900, b = 180, t = 692 }, 1024, 768)
    t.eq(wide and wide.goal and wide.goal.point[3], 900 - H.KIT_WIDTH, "right edges in line")
    -- A lot of room: never higher than the window's own height.
    local tall = B.Dock({ l = 16, r = 400, b = 600, t = 760 }, 1024, 768)
    t.eq(tall and tall.list.height, B.KIT_HEIGHT)
    t.eq(tall and tall.goal.height, H.KIT_HEIGHT)
    -- Too little room under it: no dock at all.
    t.eq(B.Dock({ l = 16, r = 400, b = B.DOCK_MIN, t = 692 }, 1024, 768), nil, "no room")
    -- The helper would stand past the right edge of the screen: only the list docks.
    local narrow = B.Dock(RECT, 600, 768)
    t.ok(type(narrow) == "table" and narrow.list ~= nil and narrow.goal == nil, "the list alone")
    -- A rectangle or a screen that is not read: no dock.
    t.eq(B.Dock(nil, 1024, 768), nil)
    t.eq(B.Dock({ l = 16, r = 400, t = 692 }, 1024, 768), nil, "a side missing")
    t.eq(B.Dock({ l = 16, r = 400, b = 0 / 0, t = 692 }, 1024, 768), nil, "a side that is no number")
    t.eq(B.Dock(RECT, nil, nil), nil, "no screen size")
end

tests["prof dock: the windows are first made under the profession window"] = function(t)
    local c = start({ folded = true, screen = { 1024, 768 }, rects = { [FRAME] = RECT } })
    local bar, helper = shownKit(t, c, "CraftBar"), shownKit(t, c, "ProfHelper")
    if not bar or not helper or type(B.Dock) ~= "function" then
        t.ok(type(B.Dock) == "function", "CraftBar.Dock")
        return
    end
    local d = B.Dock(RECT, 1024, 768)
    t.eq(bar.point, d.list.point)
    t.eq(bar.height, d.list.height)
    t.eq(bar.width, B.KIT_WIDTH)
    t.eq(helper.point, d.goal.point)
    t.eq(helper.height, d.goal.height)
    -- Unfolded in a short window the body stands in a scroll.
    c.kitClick("CraftBar", "fold")
    c.kitClick("ProfHelper", "fold")
    t.eq(part(kit(c, "CraftBar"), "body") and part(kit(c, "CraftBar"), "body").kind, "scroll")
    t.eq(part(kit(c, "ProfHelper"), "body") and part(kit(c, "ProfHelper"), "body").kind, "scroll")
    t.ok(part(kit(c, "CraftBar"), "start") ~= nil, "Start is in it")
    t.ok(part(kit(c, "ProfHelper"), "goalUp") ~= nil, "Goal + is in it")
end

tests["prof dock: no profession window place read, or no room: each window at its own place"] = function(t)
    for what, opts in pairs({
        ["nothing read"] = { folded = true, screen = { 1024, 768 } },
        ["no screen"] = { folded = true, rects = { [FRAME] = RECT } },
        ["no room"] = { folded = true, screen = { 1024, 768 }, rects = { [FRAME] = { l = 16, r = 400, b = 20, t = 532 } } },
    }) do
        local c = start(opts)
        local bar, helper = shownKit(t, c, "CraftBar"), shownKit(t, c, "ProfHelper")
        if not bar or not helper then return end
        t.ok(part(bar, "fold") ~= nil, what .. ": collapsed all the same")
        t.eq(bar.point, B.KIT_POINT, what)
        t.eq(bar.height, B.KIT_HEIGHT, what)
        t.eq(helper.point, H.KIT_POINT, what)
        t.eq(helper.height, H.KIT_HEIGHT, what)
        c.kitClick("CraftBar", "fold")
        t.eq(part(kit(c, "CraftBar"), "body"), nil, what .. ": no scroll in the full window")
        t.ok(part(kit(c, "CraftBar"), "start") ~= nil, what)
    end
end

-- The item lines of a view, however deep they sit.
local function itemLines(view)
    local out = {}
    local function walk(list)
        for _, p in ipairs(type(list) == "table" and list or {}) do
            if type(p) == "table" then
                if p.kind == "itemLine" then out[#out + 1] = p end
                walk(p.children)
            end
        end
    end
    walk(type(view) == "table" and view.children or nil)
    return out
end

tests["prof dock: a recipe line carries the quality of what it makes; not read, none"] = function(t)
    local c, addon = start({ items = {
        [ORE_COPPER] = { name = "Copper Ore", quality = 1 }, [ORE_TIN] = { name = "Tin Ore" },
        [BAR_COPPER] = { name = "Copper Bar", quality = 2 },
    } })
    if not shownKit(t, c, "CraftBar") then return end
    local lines = itemLines(addon.craftBar.view())
    t.eq(#lines, 2, "the two learned recipes")
    t.eq(lines[1] and lines[1].quality, 2, "Copper Bar: the product's quality")
    t.eq(lines[2] and lines[2].quality, nil, "Tin Bar: its product is not read, so no quality is claimed")
    local helper = itemLines(addon.profHelper.view())
    t.ok(#helper >= 1, "the helper lists a recipe")
    t.eq(helper[1] and helper[1].quality, 2, "the helper's line too")
    -- The kit colours the line by it.
    local K = ns.Kit
    local tree, why = K.Window(B.View({ recipes = { { id = 7, name = "Red Bar", count = 1, quality = 3 } } }))
    t.ok(type(tree) == "table", tostring(why))
    if type(tree) ~= "table" then return end
    local hex
    K.Each(tree, function(p) if p.kind == "itemLine" then hex = p.color and p.color.hex end end)
    t.eq(hex, K.Quality(3).hex, "rare blue")
    local odd = K.Window(B.View({ recipes = { { id = 7, name = "Red Bar", count = 1, quality = 9 } } }))
    t.ok(type(odd) == "table", "a quality the kit does not know is left out and costs no window")
end

-- The helper's notes as the kit view carries them.
local function notes(addon)
    local out = {}
    local function walk(list)
        for _, p in ipairs(type(list) == "table" and list or {}) do
            if type(p) == "table" then
                if p.kind == "row" and p.key == nil and type(p.label) == "string" then out[#out + 1] = p.label end
                walk(p.children)
            end
        end
    end
    local view = addon.profHelper.view()
    walk(type(view) == "table" and view.children or nil)
    return table.concat(out, "\n")
end

tests["prof dock: the helper's notes name each reagent, never by number"] = function(t)
    local c, addon = start()
    if not shownKit(t, c, "ProfHelper") then return end
    local text = notes(addon)
    t.ok(text:find("Copper Ore", 1, true) ~= nil, "the reagent by name: " .. text)
    t.eq(text:find("item " .. ORE_COPPER, 1, true), nil, "never by number")
    t.eq(text:find("source unknown", 1, true), nil, "it is in the bags: " .. text)
end

tests["prof dock: a reagent a merchant was seen selling is bought, at the price seen"] = function(t)
    local c, addon = start({ copper = 0, account = {
        learned = { prices = { vendor = { [ORE_COPPER] = { value = 10, basis = "observed", source = "merchant" } } } },
    } })
    if not shownKit(t, c, "ProfHelper") then return end
    local text = notes(addon)
    t.ok(text:find("Copper Ore: buy 1 from a merchant", 1, true) ~= nil, "bought: " .. text)
    t.eq(text:find("source unknown", 1, true), nil, text)
end

tests["prof dock: a reagent whose name the client has not sent is still not a made-up name"] = function(t)
    local c, addon = start({ items = {} })
    if not shownKit(t, c, "ProfHelper") then return end
    local text = notes(addon)
    t.ok(text:find("item " .. ORE_COPPER, 1, true) ~= nil, "the number, said as a number: " .. text)
end

return tests
