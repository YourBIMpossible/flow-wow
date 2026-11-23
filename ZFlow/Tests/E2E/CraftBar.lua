local _, ns = ...
-- The craft bar end to end (P-CRAFT, lead section 226: #34 Smelt All, G21
-- the craft bar, craft controls), on the whole add-on loaded on a fake
-- client. The player opens a profession window, ticks counts on the bar and
-- clicks Start once: the crafts then run one after another, each started
-- when the last one finished, until the counts are made or something stops
-- them. Nothing crafts without the click.
-- Offline: the reads are the fake client's, not the game's. Not tested in game.
local tests = {}

local MINING = 186
local COPPER_BAR, TIN_BAR, SILVER_BAR = 2657, 3304, 2658
local ORE_COPPER, ORE_TIN = 2770, 2771

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, {})
    c.setItemInfo({ [ORE_COPPER] = { name = "Copper Ore" }, [ORE_TIN] = { name = "Tin Ore" } })
    c.setBags(opts.bags or { { free = 4, total = 16, family = 0 } })
    c.setRecipes({ profession = opts.profession or MINING, skill = 70, max = 75, recipes = {
        { id = COPPER_BAR, name = "Copper Bar", learned = true },
        { id = TIN_BAR, name = "Tin Bar", learned = true },
        { id = SILVER_BAR, name = "Silver Bar", learned = false },
    } })
    c.setRecipeReagents(COPPER_BAR, { { item = ORE_COPPER, count = 1 } })
    c.setRecipeReagents(TIN_BAR, { { item = ORE_TIN, count = 1 } })
    c.setRecipeUsable(COPPER_BAR, true)
    c.setRecipeUsable(TIN_BAR, true)
    c.setMoving(false)
    c.setItemCount(ORE_COPPER, opts.copper or 10)
    c.setItemCount(ORE_TIN, opts.tin or 0)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    if opts.open ~= false then c.fire("TRADE_SKILL_SHOW") end
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

tests["craft bar: one click makes the counts back to back, row after row"] = function(t)
    local c, addon = start({ tin = 5 })
    local bar = barOf(c)
    if not bar then t.ok(false, "no craft bar") return end
    t.eq(tick(bar, { [COPPER_BAR] = 2, [TIN_BAR] = 1 }), true)
    t.eq(crafted(c), { COPPER_BAR }, "the first craft on the click")
    t.eq(addon.craftBar.running(), true)
    t.ok(infos(bar):find("Making Copper Bar: 0 of 2", 1, true) ~= nil, infos(bar))
    done(c, COPPER_BAR)
    t.eq(crafted(c), { COPPER_BAR, COPPER_BAR }, "the next when the last finished")
    done(c, COPPER_BAR)
    t.eq(crafted(c), { COPPER_BAR, COPPER_BAR, TIN_BAR }, "then the next ticked recipe")
    done(c, TIN_BAR)
    t.eq(#c.crafts, 3, "no craft past the counts")
    t.eq(addon.craftBar.running(), false)
    t.ok(infos(bar):find("Made 2 x Copper Bar, 1 x Tin Bar.", 1, true) ~= nil, infos(bar))
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
    t.eq(crafted(c), { COPPER_BAR })
    t.eq(rowOf(bar, "count:" .. COPPER_BAR).value, 4)
    t.eq(rowOf(bar, "count:" .. TIN_BAR).value, 2)
    t.eq(addon.craftBar.running(), true)
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
