local _, ns = ...
-- Lead section 422 item 1: between trainer ranks, with every trainer recipe
-- known and grey, the profession plan still names a step. Learned at run
-- time only: a recipe seen for sale at a vendor the player opened (its
-- profession and skill read from the tooltip) is "buy it from that vendor"
-- when it would give a point; with nothing known, one plain line with the
-- nearest gathering or the next trainer rank. Never a step on another
-- continent. Whole add-on loaded the way the game loads it
-- (ns.offline.addon) on a fake client; every name is made up. Not tested
-- in game.
local tests = {}

local PROF = "Blacksmithing"
local OLD = "Test Dull Hinge"
local RECIPE_ITEM = 9501
local RECIPE_NAME = "Plans: Test Glimmer Blade"
local LATER_ITEM = 9502
local CLOTH_ITEM = 9503

-- A Blacksmithing character at 50 of 75: its one recipe grey, the seen
-- trainer's list all known. opts: rows (more trainer rows), nodes
-- (GatherMate2 rows on map 1411).
local function start(opts)
    opts = opts or {}
    local rows = { { name = OLD, skill = 1, state = "known" } }
    for _, r in ipairs(opts.rows or {}) do rows[#rows + 1] = r end
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { learned = { places = { npcs = {
        ["Test Smith Trainer"] = { map = 1411, x = 0.2, y = 0.2, trains = { [PROF] = true } },
    } } } })
    c.setSaved(ns.id.charDB, { learned = {
        facts = {
            profSkill = { [PROF] = { skill = 50, max = 75 } },
            recipeBook = { [OLD] = { profession = PROF, makes = 9100, mats = { [9001] = 1 } } },
        },
        recipeColors = { [OLD] = { trivial = { lo = 30, hi = 300 } } },
        trainerLists = { ["Test Smith Trainer"] = { profession = PROF, npc = "Test Smith Trainer", rows = rows } },
    } })
    c.setZone(1, 1411); c.setFaction("Horde"); c.setLevel(20)
    c.setPosition(1411, 0.5, 0.5); c.setMapSize(1411, 1000, 500)
    c.setMapCont(1411, 1); c.setMapCont(1412, 2)
    c.setProfessions({ PROF })
    if opts.nodes then c.setGatherMateNodes(1411, opts.nodes) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

-- The player opens a vendor at map 1411 (0.3, 0.4) that sells the recipe
-- (needs 45), a later recipe (needs 60) and cloth (no profession line).
local function openVendor(c)
    c.setItemInfo({
        [RECIPE_ITEM] = { name = RECIPE_NAME },
        [LATER_ITEM] = { name = "Plans: Test Later Blade" },
        [CLOTH_ITEM] = { name = "Test Cloth" },
    })
    c.setItemLines(RECIPE_ITEM, { RECIPE_NAME, "Requires " .. PROF .. " (45)" })
    c.setItemLines(LATER_ITEM, { "Plans: Test Later Blade", "Requires " .. PROF .. " (60)" })
    c.setItemLines(CLOTH_ITEM, { "Test Cloth" })
    c.setServiceNpc(nil, "Test Vendor")
    c.setPosition(1411, 0.3, 0.4)
    c.setMerchant({
        { item = "item:" .. CLOTH_ITEM, price = 10, stack = 1 },
        { item = "item:" .. RECIPE_ITEM, price = 500, stack = 1 },
        { item = "item:" .. LATER_ITEM, price = 900, stack = 1 },
    })
    c.setMerchantOpen(true)
    c.setMerchantOpen(false)
    c.setPosition(1411, 0.5, 0.5)
end

local function plan(addon)
    local p = addon.profPlan and addon.profPlan.plan
    if type(p) ~= "function" then return {}, "no plan", nil end
    return p(PROF)
end

local function kindsOf(steps)
    local out = {}
    for i, s in ipairs(type(steps) == "table" and steps or {}) do out[i] = s.kind end
    return out
end

-- Fails before: a vendor recipe that gives a point is no step.
tests["prof vendor recipes: a recipe seen at a vendor gives the buy step"] = function(t)
    local c, addon = start()
    openVendor(c)
    local steps = plan(addon)
    t.eq(kindsOf(steps), { "buy_recipe" }, "one buy step")
    local s = steps[1] or {}
    t.eq(s.item, RECIPE_ITEM, "the recipe item")
    t.eq(s.npc, "Test Vendor", "the vendor")
    t.eq(s.target, { map = 1411, x = 0.3, y = 0.4 }, "where the vendor was opened")
    t.eq(s.text, "Buy " .. RECIPE_NAME .. " from Test Vendor (" .. PROF .. " 50 of 75)", "the line")
    local saved = addon.store:get("account", "learned.vendorRecipes")
    t.eq(type(saved) == "table" and saved[CLOTH_ITEM], nil, "an item with no profession line is not kept")
    t.eq(type(saved) == "table" and type(saved[LATER_ITEM]) == "table" and saved[LATER_ITEM].skill, 60,
        "a later recipe is kept with its skill")
end

-- Fails before: no rule; after, the vendor's continent is not the player's.
tests["prof vendor recipes: a vendor on another continent gives no step"] = function(t)
    local c, addon = start()
    openVendor(c)
    -- A check that always runs: a plan with no step made no checks below.
    t.eq(kindsOf((plan(addon))), { "buy_recipe" }, "offered on the vendor's continent")
    c.setZone(2, 1412)
    c.setPosition(1412, 0.5, 0.5)
    local steps = plan(addon)
    for _, s in ipairs(steps) do
        t.ok(s.kind ~= "buy_recipe", "no buy step on another continent")
        t.ok(type(s.target) ~= "table" or s.target.map ~= 1411, "no place on another continent")
    end
end

-- Fails before: the plan ends with no step and the trainer words.
tests["prof vendor recipes: nothing known names the nearest gathering, else the next rank"] = function(t)
    local _, addon = start({ nodes = { { kind = "Herb Gathering", x = 0.6, y = 0.5, node = "Test Bloom" },
        { kind = "Mining", x = 0.9, y = 0.9, node = "Test Far Vein" } } })
    local steps = plan(addon)
    t.eq(kindsOf(steps), { "no_point" }, "one plain step")
    t.eq(steps[1] and steps[1].text, "No point yet; gather Test Bloom", "the plain line with the nearest gathering")
    t.eq(steps[1] and steps[1].target, { map = 1411, x = 0.6, y = 0.5 }, "the node's place")
    t.ok(#(steps[1] and steps[1].text or "") <= 40, "fits a label")

    local _, addon2 = start({ rows = { { name = "Test Late Rank", skill = 60, state = "unavailable" } } })
    local steps2 = plan(addon2)
    t.eq(kindsOf(steps2), { "no_point" }, "one plain step")
    t.eq(steps2[1] and steps2[1].text, "No point yet; next rank at 60", "the plain line with the next rank")
    t.eq(steps2[1] and steps2[1].target, { map = 1411, x = 0.2, y = 0.2 }, "the trainer's place")
end

-- Fails before: no buy step to drop.
tests["prof vendor recipes: a learned vendor recipe is no longer offered"] = function(t)
    local c, addon = start()
    openVendor(c)
    t.eq(kindsOf((plan(addon))), { "buy_recipe" }, "offered before it is learned")
    local book = addon.store:get("char", "learned.facts.recipeBook")
    local copy = {}
    for k, v in pairs(book or {}) do copy[k] = v end
    copy["Test Glimmer Blade"] = { profession = PROF, makes = 9200, mats = { [9001] = 2 } }
    addon.store:set("char", "learned.facts.recipeBook", copy)
    local steps = plan(addon)
    for _, s in ipairs(steps) do t.ok(s.kind ~= "buy_recipe", "a learned recipe is not bought again") end
end

return tests
