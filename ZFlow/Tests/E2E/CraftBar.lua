local _, ns = ...
-- The craft bar end to end (P-CRAFT, lead section 226: #34 Smelt All, G21
-- the craft bar, craft controls), on the whole add-on loaded on a fake
-- client. The player opens a profession window, ticks counts on the bar and
-- clicks Start: that click asks one craft of the first recipe with its whole
-- count as the game repeat count (lead section 234). A finish only counts;
-- the next recipe waits for the next click. Nothing crafts without the
-- click, and never from a finish, a timer or the tick.
-- Offline: the reads are the fake client's, not the game's. Not tested in game.
local tests = {}

local MINING = 186
local COPPER_BAR, TIN_BAR, SILVER_BAR = 2657, 3304, 2658
local ORE_COPPER, ORE_TIN = 2770, 2771
local ITEM_COPPER_BAR, ITEM_TIN_BAR = 2840, 3576

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
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

local function crafted(c)
    local out = {}
    for _, r in ipairs(c.crafts or {}) do out[#out + 1] = r.id end
    return out
end

-- The player ticks counts and clicks Start once.
local function tick(bar, counts)
    for id, n in pairs(counts) do bar.press("count:" .. id, n) end
    return bar.press("start")
end

tests["craft bar: shown on a profession window with a count for each learned recipe"] = function(t)
    local c, addon = start()
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    t.eq(bar.shown(), true)
    t.ok(rowOf(bar, "count:" .. COPPER_BAR) ~= nil and rowOf(bar, "count:" .. TIN_BAR) ~= nil, "a count per learned recipe")
    t.eq(rowOf(bar, "count:" .. SILVER_BAR), nil, "a recipe not learned has no count")
    t.eq(rowOf(bar, "count:" .. COPPER_BAR).value, 0, "nothing ticked at first")
    t.ok(rowOf(bar, "start") ~= nil and rowOf(bar, "all") ~= nil, "Start, and Smelt all on the mining window")
    t.eq(addon.craftBar.running(), false)
end

-- Section 231: the goals list (ItemGoals.Crafts, as it is) fills the counts.
-- A goal for a recipe in this window gets the crafts it still needs; a goal
-- already met, or for a recipe not in this window, gets none. Filling the
-- counts crafts nothing: Start is still the player click.
tests["craft bar: From goals fills the counts with the crafts each goal still needs"] = function(t)
    local c, addon = start({
        goals = {
            { item = ITEM_COPPER_BAR, count = 3, recipe = "Copper Bar" },
            { item = ITEM_TIN_BAR, count = 1, recipe = "Tin Bar" },
            { item = 2996, count = 2, recipe = "Bolt of Linen Cloth" },
        },
        bagItems = { { item = ITEM_COPPER_BAR, count = 1 }, { item = ITEM_TIN_BAR, count = 4 } },
        -- Known from another profession window: not craftable in this one.
        book = { ["Bolt of Linen Cloth"] = { id = 2963, makes = 2996, yield = 1, mats = { [2589] = 2 },
                                            profession = "Tailoring" } },
    })
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    t.ok(rowOf(bar, "goals") ~= nil, "a From goals button")
    bar.press("goals")
    t.eq(rowOf(bar, "count:" .. COPPER_BAR).value, 2, "3 wanted, 1 owned: 2 still to make")
    t.eq(rowOf(bar, "count:" .. TIN_BAR).value, 0, "a goal already met makes none")
    t.eq(rowOf(bar, "count:2963"), nil, "a recipe of another window gets no count here")
    t.eq(addon.craftBar.running(), false, "filling the counts starts nothing")
    t.eq(#c.crafts, 0, "nothing crafted")
    bar.press("start")
    t.eq(c.crafts, { { id = COPPER_BAR, n = 2 } }, "Start makes what the goals asked for")
end

tests["craft bar: From goals with no goal to craft here says so and keeps the counts"] = function(t)
    local c = start()
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    bar.press("count:" .. TIN_BAR, 2)
    bar.press("goals")
    t.eq(rowOf(bar, "count:" .. TIN_BAR).value, 2, "the ticked count stays")
    t.ok(infos(bar):find(ns.CraftBar.NO_GOALS, 1, true) ~= nil, "the bar says no goal is craftable here")
    t.eq(#c.crafts, 0)
end

tests["craft bar: From goals says so when every goal is met or belongs to another window"] = function(t)
    local c = start({
        goals = {
            { item = ITEM_TIN_BAR, count = 1, recipe = "Tin Bar" },
            { item = 2996, count = 2, recipe = "Bolt of Linen Cloth" },
        },
        bagItems = { { item = ITEM_TIN_BAR, count = 4 } },
        book = { ["Bolt of Linen Cloth"] = { id = 2963, makes = 2996, yield = 1, mats = { [2589] = 2 },
                                            profession = "Tailoring" } },
    })
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    bar.press("goals")
    t.ok(infos(bar):find(ns.CraftBar.NO_GOALS, 1, true) ~= nil, "a met goal and another window goal fill nothing")
end

tests["craft bar: nothing crafts without the click"] = function(t)
    local c = start()
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    bar.press("count:" .. COPPER_BAR, 3)
    c.fire("TRADE_SKILL_LIST_UPDATE")
    done(c, COPPER_BAR)
    c.advance(30, 60)
    t.eq(crafted(c), {}, "ticking a count crafts nothing")
end

-- Section 234: one ask per click, the count as the game repeat count; a
-- finish counts, it never asks; the next recipe waits for a click.
tests["craft bar: one click asks one recipe with its count as the repeat, the next recipe waits for a click"] = function(t)
    local c, addon = start({ tin = 5 })
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    t.eq(tick(bar, { [COPPER_BAR] = 2, [TIN_BAR] = 1 }), true)
    t.eq(c.crafts, { { id = COPPER_BAR, n = 2 } }, "one ask on the click, the count as the repeat")
    t.eq(addon.craftBar.running(), true)
    t.ok(infos(bar):find("Making Copper Bar: 0 of 2", 1, true) ~= nil, infos(bar))
    done(c, COPPER_BAR)
    t.eq(#c.crafts, 1, "a finish asks nothing")
    t.ok(infos(bar):find("Making Copper Bar: 1 of 2", 1, true) ~= nil, infos(bar))
    done(c, COPPER_BAR)
    t.eq(#c.crafts, 1, "the last finish of a recipe asks nothing")
    t.eq(addon.craftBar.running(), false, "waits for the click")
    t.eq(rowOf(bar, "start").label, "Start")
    t.ok(infos(bar):find("Click Start for Tin Bar.", 1, true) ~= nil, infos(bar))
    c.advance(30, 60)
    c.fire("TRADE_SKILL_LIST_UPDATE")
    t.eq(#c.crafts, 1, "no timer, event or tick asks the next recipe")
    t.eq(bar.press("start"), true)
    t.eq(c.crafts, { { id = COPPER_BAR, n = 2 }, { id = TIN_BAR, n = 1 } }, "the click asks the next recipe")
    done(c, TIN_BAR)
    t.eq(#c.crafts, 2, "no craft past the counts")
    t.eq(addon.craftBar.running(), false)
    t.ok(infos(bar):find("Made 2 x Copper Bar, 1 x Tin Bar.", 1, true) ~= nil, infos(bar))
end

tests["craft bar: a waiting run is dropped when the counts change"] = function(t)
    local c = start({ tin = 5 })
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    tick(bar, { [COPPER_BAR] = 1, [TIN_BAR] = 1 })
    done(c, COPPER_BAR)
    bar.press("clear")
    bar.press("count:" .. TIN_BAR, 2)
    bar.press("start")
    t.eq(c.crafts, { { id = COPPER_BAR, n = 1 }, { id = TIN_BAR, n = 2 } }, "a new run from the new counts")
end

-- Stopping mid-repeat asks the game to stop the repeat (c.stopCraftRepeat,
-- not a craft). Nothing to stop before a craft was asked.
tests["craft bar: a stop asks the game to stop the repeat"] = function(t)
    for _, how in ipairs({ "click", "moving", "window", "closed", "combat" }) do
        local c = start()
        local bar = barOf(c)
        if not bar then t.ok(false, "no craft bar") return end
        tick(bar, { [COPPER_BAR] = 3 })
        if how == "click" then bar.press("start")
        elseif how == "moving" then c.fire("PLAYER_STARTED_MOVING")
        elseif how == "window" then c.fire("TRADE_SKILL_CLOSE")
        elseif how == "closed" then bar.close()
        else c.setCombat(true); c.fire("PLAYER_REGEN_DISABLED") end
        t.eq(c.repeatStops, 1, how)
        t.eq(#c.crafts, 1, how)
    end
end

-- Section 240: one click, and the client runs the whole repeat count by
-- itself (the fake repeat runner). The bar counts each finish and asks
-- nothing more; the run is kept as done with made equal to asked.
tests["craft bar: the client runs the repeat count from one click"] = function(t)
    local c = start()
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    c.setCraftRepeat(2)
    tick(bar, { [COPPER_BAR] = 3 })
    c.advance(8, 8)
    t.eq(c.crafts, { { id = COPPER_BAR, n = 3 } }, "one ask for the whole count")
    local runs = c.saved(ns.id.charDB).learned.craftRuns
    t.eq(runs[#runs].asked, 3)
    t.eq(runs[#runs].made, 3)
    t.eq(runs[#runs].stop, "done")
    t.eq(c.repeatStops, 0)
end

-- Section 240: moving mid-repeat stops the repeat; no finish comes after.
tests["craft bar: moving mid-repeat stops the client repeat"] = function(t)
    local c = start()
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    c.setCraftRepeat(2)
    tick(bar, { [COPPER_BAR] = 3 })
    c.advance(2)
    c.fire("PLAYER_STARTED_MOVING")
    c.advance(8, 8)
    local runs = c.saved(ns.id.charDB).learned.craftRuns
    t.eq(runs[#runs].made, 1)
    t.eq(runs[#runs].stop, "moving")
    t.eq(c.repeatStops, 1)
    t.eq(#c.crafts, 1)
end

tests["craft bar: nothing to stop when no craft was asked"] = function(t)
    local c = start()
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    c.setRecipeUsable(COPPER_BAR, false, "Requires a forge")
    tick(bar, { [COPPER_BAR] = 3 })
    c.fire("PLAYER_STARTED_MOVING")
    t.eq(c.repeatStops, 0)
end

tests["craft bar: a finished cast of another spell is not a craft made"] = function(t)
    local c = start()
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    tick(bar, { [COPPER_BAR] = 2 })
    done(c, 133)
    c.fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "Cast-guid", COPPER_BAR)
    t.eq(#c.crafts, 1)
end

local function stopsWith(t, c, addon, bar, want)
    t.eq(addon.craftBar.running(), false, "stopped")
    t.ok(infos(bar):find(want, 1, true) ~= nil, "the bar says why: " .. infos(bar))
end

tests["craft bar: stops when a reagent runs out"] = function(t)
    local c, addon = start({ copper = 1 })
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    tick(bar, { [COPPER_BAR] = 3 })
    c.setItemCount(ORE_COPPER, 0)
    done(c, COPPER_BAR)
    t.eq(#c.crafts, 1)
    stopsWith(t, c, addon, bar, "Stopped: not enough Copper Ore. Made 1 of 3.")
end

tests["craft bar: stops when the bags are full"] = function(t)
    local c, addon = start()
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    tick(bar, { [COPPER_BAR] = 3 })
    c.setBags({ { free = 0, total = 16, family = 0 }, { free = 6, total = 6, family = 8 } })
    done(c, COPPER_BAR)
    t.eq(#c.crafts, 1, "a special bag's room is not room for a bar")
    stopsWith(t, c, addon, bar, "your bags are full")
end

tests["craft bar: does not start when the bags cannot be read"] = function(t)
    local c, addon = start()
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    c.setBags(nil)
    tick(bar, { [COPPER_BAR] = 3 })
    t.eq(#c.crafts, 0)
    stopsWith(t, c, addon, bar, "your bags could not be read")
end

tests["craft bar: stops when the player moves"] = function(t)
    local c, addon = start()
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    tick(bar, { [COPPER_BAR] = 3 })
    c.fire("PLAYER_STARTED_MOVING")
    done(c, COPPER_BAR)
    t.eq(#c.crafts, 1)
    stopsWith(t, c, addon, bar, "you moved")
end

tests["craft bar: the second click stops it"] = function(t)
    local c, addon = start()
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    tick(bar, { [COPPER_BAR] = 3 })
    t.eq(rowOf(bar, "start").label, "Stop")
    bar.press("start")
    done(c, COPPER_BAR)
    t.eq(#c.crafts, 1)
    stopsWith(t, c, addon, bar, "you stopped it")
    t.eq(rowOf(bar, "start").label, "Start")
end

tests["craft bar: stops on combat, and does not start in it"] = function(t)
    local c, addon = start()
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    tick(bar, { [COPPER_BAR] = 3 })
    c.setCombat(true)
    done(c, COPPER_BAR)
    t.eq(#c.crafts, 1)
    stopsWith(t, c, addon, bar, "in combat")
    bar.press("start")
    t.eq(#c.crafts, 1, "a click in combat crafts nothing")
end

tests["craft bar: combat starting stops it at once, before the craft finishes"] = function(t)
    local c, addon = start()
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    tick(bar, { [COPPER_BAR] = 3 })
    t.eq(addon.craftBar.running(), true)
    c.setCombat(true)
    c.fire("PLAYER_REGEN_DISABLED")
    stopsWith(t, c, addon, bar, "in combat")
    c.setCombat(false)
    done(c, COPPER_BAR)
    t.eq(#c.crafts, 1, "a finish after the stop starts nothing")
end

tests["craft bar: stops when the recipe cannot be made here"] = function(t)
    local c, addon = start()
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    c.setRecipeUsable(COPPER_BAR, false, "Requires a forge")
    tick(bar, { [COPPER_BAR] = 3 })
    t.eq(#c.crafts, 0)
    stopsWith(t, c, addon, bar, "Stopped: Requires a forge. Made 0 of 3.")
end

tests["craft bar: stops and hides when the profession window closes"] = function(t)
    local c, addon = start()
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    tick(bar, { [COPPER_BAR] = 3 })
    c.fire("TRADE_SKILL_CLOSE")
    done(c, COPPER_BAR)
    t.eq(#c.crafts, 1)
    t.eq(addon.craftBar.running(), false)
    t.eq(bar.shown(), false)
end

tests["craft bar: stops when a craft is interrupted"] = function(t)
    local c, addon = start()
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    tick(bar, { [COPPER_BAR] = 3 })
    c.fire("UNIT_SPELLCAST_INTERRUPTED", "player", "Cast-guid", COPPER_BAR)
    done(c, COPPER_BAR)
    t.eq(#c.crafts, 1)
    stopsWith(t, c, addon, bar, "the craft was interrupted")
end

tests["craft bar: an interrupt of another spell, or of another unit, does not stop it"] = function(t)
    local c, addon = start()
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    tick(bar, { [COPPER_BAR] = 2 })
    c.fire("UNIT_SPELLCAST_INTERRUPTED", "player", "Cast-guid", COPPER_BAR + 1)
    c.fire("UNIT_SPELLCAST_INTERRUPTED", "target", "Cast-guid", COPPER_BAR)
    t.eq(addon.craftBar.running(), true, "still running")
    done(c, COPPER_BAR)
    t.ok(infos(bar):find("Making Copper Bar: 1 of 2", 1, true) ~= nil, "the finish still counts: " .. infos(bar))
end

tests["craft bar: stops when no craft starts"] = function(t)
    local c, addon = start()
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    tick(bar, { [COPPER_BAR] = 3 })
    c.advance(15, 30)
    t.eq(#c.crafts, 1)
    stopsWith(t, c, addon, bar, "no craft started")
    done(c, COPPER_BAR)
    t.eq(#c.crafts, 1, "a late finish after the stop starts nothing")
end

tests["craft bar: stops when the client will not craft"] = function(t)
    local c, addon = start()
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    c.setCraftFails("noCall")
    tick(bar, { [COPPER_BAR] = 3 })
    stopsWith(t, c, addon, bar, "the craft could not start")
end

tests["craft bar: Smelt all ticks what the ore covers and starts on the click"] = function(t)
    local c, addon = start({ copper = 4, tin = 2 })
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    t.eq(bar.press("all"), true)
    t.eq(c.crafts, { { id = COPPER_BAR, n = 4 } }, "the click asks the first recipe, all 4 as the repeat")
    t.eq(rowOf(bar, "count:" .. COPPER_BAR).value, 4)
    t.eq(rowOf(bar, "count:" .. TIN_BAR).value, 2)
    t.eq(addon.craftBar.running(), true)
end

-- Section 234 item 2: where c.recipeSchematic gives nothing (the client has
-- no GetRecipeSchematic), the bar reads the recipe from the recipe book,
-- which the classic window read (c.tradeSkillSchematic) fills. The bar does
-- not write the book.
tests["craft bar: Smelt all reads the recipe book when the schematic read gives nothing"] = function(t)
    local c, addon = start({ copper = 4, tin = 2, schematic = false, book = {
        ["Copper Bar"] = { id = COPPER_BAR, makes = ITEM_COPPER_BAR, yield = 1, mats = { [ORE_COPPER] = 1 } },
        ["Tin Bar"] = { id = TIN_BAR, makes = ITEM_TIN_BAR, yield = 1, mats = { [ORE_TIN] = 1 } },
    } })
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    t.eq(bar.press("all"), true)
    t.eq(rowOf(bar, "count:" .. COPPER_BAR).value, 4, "the book mats cover 4 copper")
    t.eq(rowOf(bar, "count:" .. TIN_BAR).value, 2, "the book mats cover 2 tin")
    t.eq(crafted(c), { COPPER_BAR })
    t.eq(addon.craftBar.running(), true)
end

tests["craft bar: with neither read Smelt all smelts nothing"] = function(t)
    local c, addon = start({ copper = 4, schematic = false })
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    bar.press("all")
    t.eq(#c.crafts, 0, "no recipe read, no craft")
    t.eq(addon.craftBar.running(), false)
end

tests["craft bar: no Smelt all on another profession"] = function(t)
    local c = start({ profession = 164 })
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    t.eq(rowOf(bar, "all"), nil)
end

tests["craft bar: counts cannot change while it runs, and clear sets them to none"] = function(t)
    local c = start()
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    tick(bar, { [COPPER_BAR] = 3 })
    t.eq(rowOf(bar, "count:" .. COPPER_BAR).enabled, false)
    t.eq(bar.press("count:" .. COPPER_BAR, 9), false)
    bar.press("start")
    bar.press("clear")
    t.eq(rowOf(bar, "count:" .. COPPER_BAR).value, 0)
end

tests["craft bar: off in settings: never shown, nothing crafts"] = function(t)
    local c, addon = start({ open = false })
    t.eq(addon.settings:set(addon.CraftBar.SETTING, false), true)
    c.fire("TRADE_SKILL_SHOW")
    local bar = barOf(c)
    t.ok(bar == nil or bar.shown() == false, "not shown")
    t.eq(#(c.crafts or {}), 0)
end

-- Lead section 237 item 1, section 236 item 2: each craft the click asked
-- is kept on the character (learned.craftRuns, newest last, at most
-- CraftBar.RUNS_KEEP), so the capture shows whether the client took the
-- repeat count: asked, made (finishes counted), and how it ended.
local function runs(c)
    local char = c.saved(ns.id.charDB)
    return type(char.learned) == "table" and char.learned.craftRuns or nil
end

local function plain(r)
    return { recipe = r.recipe, asked = r.asked, made = r.made, stop = r.stop, why = r.why }
end

tests["craft bar: each asked craft is kept for the capture, with how it ended"] = function(t)
    local c = start({ tin = 5 })
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    tick(bar, { [COPPER_BAR] = 2, [TIN_BAR] = 1 })
    local r = runs(c)
    t.eq(type(r), "table", "kept when asked")
    if type(r) ~= "table" then return end
    t.eq(#r, 1)
    t.eq(plain(r[1]), { recipe = COPPER_BAR, asked = 2, made = 0 }, "open while it runs")
    t.eq(type(r[1].at), "number", "when it was asked")
    done(c, COPPER_BAR)
    done(c, COPPER_BAR)
    t.eq(plain(r[1]), { recipe = COPPER_BAR, asked = 2, made = 2, stop = "done" })
    bar.press("start")
    c.fire("PLAYER_STARTED_MOVING")
    t.eq(#r, 2)
    t.eq(plain(r[2]), { recipe = TIN_BAR, asked = 1, made = 0, stop = "moving" })
end

tests["craft bar: a craft the client refused is kept as refused, and the next click recovers"] = function(t)
    local c, addon = start()
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    c.setCraftFails("raised")
    tick(bar, { [COPPER_BAR] = 2 })
    t.eq(#c.crafts, 0)
    t.eq(addon.craftBar.running(), false)
    local r = runs(c) or {}
    t.eq(r[1] and plain(r[1]), { recipe = COPPER_BAR, asked = 2, made = 0, stop = "refused", why = "raised" })
    c.setCraftFails(nil)
    bar.press("start")
    t.eq(c.crafts, { { id = COPPER_BAR, n = 2 } }, "the next click asks again")
    done(c, COPPER_BAR)
    done(c, COPPER_BAR)
    t.eq(#r, 2)
    t.eq(r[2] and plain(r[2]), { recipe = COPPER_BAR, asked = 2, made = 2, stop = "done" })
end

tests["craft bar: only the newest runs are kept"] = function(t)
    local c = start({ copper = 50 })
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    local keep = ns.CraftBar.RUNS_KEEP
    t.eq(type(keep), "number")
    if type(keep) ~= "number" then return end
    for i = 1, keep + 2 do
        bar.press("count:" .. COPPER_BAR, i)
        bar.press("start")
        bar.press("start")
    end
    local r = runs(c) or {}
    t.eq(#r, keep)
    t.eq(r[1] and r[1].asked, 3, "the two oldest dropped")
    t.eq(r[keep] and r[keep].asked, keep + 2)
    t.eq(r[keep] and r[keep].stop, "click")
end

-- Section 236 item 2: a reload in the middle of a run. The new session
-- starts idle; nothing crafts from the old run, and the kept record of it
-- is read back as it was saved.
tests["craft bar: a reload mid-run starts idle, crafts nothing, keeps the record"] = function(t)
    local c = start()
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    tick(bar, { [COPPER_BAR] = 3 })
    done(c, COPPER_BAR)
    local account, char = c.saved(ns.id.accountDB), c.saved(ns.id.charDB)
    local c2, addon2 = start({ account = account, char = char })
    local bar2 = barOf(c2)
    if not bar2 then t.ok(false, "no craft bar after the reload") return end
    t.eq(addon2.craftBar.running(), false, "idle after the reload")
    done(c2, COPPER_BAR)
    c2.advance(30, 60)
    c2.fire("TRADE_SKILL_LIST_UPDATE")
    t.eq(#c2.crafts, 0, "no craft without a click in the new session")
    t.eq(rowOf(bar2, "start").label, "Start")
    local r = runs(c2) or {}
    t.eq(r[1] and plain(r[1]), { recipe = COPPER_BAR, asked = 3, made = 1 }, "read back as saved")
    t.eq(rowOf(bar2, "count:" .. COPPER_BAR).value, 0, "the counts are not kept over a reload")
    tick(bar2, { [COPPER_BAR] = 2 })
    t.eq(c2.crafts, { { id = COPPER_BAR, n = 2 } }, "a click after the reload asks from the new counts")
    t.eq(#r, 2, "the new ask is kept after the old record")
end

-- Section 236 item 2: data arriving late. The window opens before the
-- recipe can be read; Smelt all then smelts nothing. When the list update
-- brings the recipe, the next click smelts.
tests["craft bar: a recipe read that arrives late is used on the next click"] = function(t)
    local c, addon = start({ copper = 4, schematic = false })
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    bar.press("all")
    t.eq(#c.crafts, 0, "not read yet, nothing smelted")
    c.setRecipeSchematic(COPPER_BAR, { makes = ITEM_COPPER_BAR, yield = 1, mats = { [ORE_COPPER] = 1 } })
    c.fire("TRADE_SKILL_LIST_UPDATE")
    t.eq(#c.crafts, 0, "the late answer itself asks nothing")
    bar.press("all")
    t.eq(c.crafts, { { id = COPPER_BAR, n = 4 } })
    t.eq(addon.craftBar.running(), true)
end

tests["craft bar: closing the bar stops it"] = function(t)
    local c, addon = start()
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    tick(bar, { [COPPER_BAR] = 3 })
    bar.close()
    done(c, COPPER_BAR)
    t.eq(#c.crafts, 1)
    t.eq(addon.craftBar.running(), false)
end

return tests
