local _, ns = ...
-- Lead section 400 item 3. Owner, 2026-11-10: the arrow says to make a belt;
-- the player has the ore but not the bars. Through the real planner entry
-- (addon.profPlan.plan, Items/ProfPlan.lua, read from the client and the
-- store): a craft whose bars are missing names the smelt first, then the
-- craft, and the ore is counted in the bags and in the bank. Ore in the bank
-- is taken out before the smelt. Loaded the way the game loads it
-- (ns.offline.addon) on a fake client; every recipe and item is made up.
-- Not tested in game.
local tests = {}

local ORE, BAR = 1, 2
-- Test Belt: 2 bars each, sure at 50. Test Smelt: 1 ore makes 1 bar.
local BOOK = {
    ["Test Belt"] = { profession = "Blacksmithing", makes = 50, mats = { [BAR] = 2 } },
    ["Test Smelt"] = { profession = "Mining", makes = BAR, mats = { [ORE] = 1 } },
}
local COLOURS = { ["Test Belt"] = { optimal = { lo = 45, hi = 60 } } }

-- opts: ore (in the bags), bankOre (in the bank)
local function start(opts)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, { learned = {
        facts = { profSkill = { Blacksmithing = { skill = 50, max = 75 } }, recipeBook = BOOK },
        recipeColors = COLOURS,
        bankCounts = opts.bankOre and { at = 1000, counts = { [ORE] = opts.bankOre } } or nil,
    } })
    c.setZone(1, 1411); c.setFaction("Horde"); c.setFacing(0)
    c.setPosition(1411, 0.5, 0.5); c.setMapSize(1411, 1000, 500); c.setMapCont(1411, 1)
    c.setItemInfo({ [ORE] = { name = "Test Ore" }, [BAR] = { name = "Test Bar" } })
    c.setBagItems(opts.ore and { { item = ORE, count = opts.ore } } or {})
    c.setProfessions({ "Blacksmithing", "Mining" })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function index(steps, kind, item)
    for i, s in ipairs(steps or {}) do
        if s.kind == kind and (item == nil or s.item == item) then return i end
    end
    return nil
end

local function craft(steps)
    local i = index(steps, "craft")
    return i and steps[i] or {}
end

tests["smelt first e2e: ore in the bags, no bars: smelt, then make the belt"] = function(t)
    local _, addon = start({ ore = 4 })
    local steps = addon.profPlan.plan("Blacksmithing")
    t.eq(steps[1] and steps[1].kind, "make_part", "the smelt is the first step")
    t.eq(steps[1] and steps[1].text, "Smelt 4 Test Bar at a forge, for Test Belt")
    t.ok(index(steps, "make_part") < (index(steps, "craft") or 0), "smelt before craft")
    t.eq(craft(steps).count, 2, "4 bars make 2 belts")
end

tests["smelt first e2e: ore in the bank only: take it out, smelt, then make the belt"] = function(t)
    local _, addon = start({ bankOre = 4 })
    local steps = addon.profPlan.plan("Blacksmithing")
    local take, smelt, make = index(steps, "take_bank", ORE), index(steps, "make_part"), index(steps, "craft")
    t.ok(take ~= nil, "the bank ore is taken out")
    t.ok(smelt ~= nil, "the bars are smelted")
    t.ok(make ~= nil, "the belt is made")
    if not (take and smelt and make) then return end
    t.ok(take < smelt and smelt < make, "take, smelt, make")
    t.eq(steps[take].text, "Take 4 Test Ore from your bank, for Test Belt")
    t.eq(steps[take].count, 4)
    t.eq(craft(steps).count, 2)
end

tests["smelt first e2e: ore in the bags and the bank: both counted, the bank part taken"] = function(t)
    local _, addon = start({ ore = 2, bankOre = 4 })
    local steps = addon.profPlan.plan("Blacksmithing")
    local take = index(steps, "take_bank", ORE)
    t.ok(take ~= nil, "the bank ore is taken out")
    t.eq(take and steps[take].count, 4, "6 ore: 2 from the bags, 4 from the bank")
    local smelt = index(steps, "make_part")
    t.eq(smelt and steps[smelt].count, 6, "6 bars smelted")
    t.ok(take and smelt and take < smelt, "taken before the smelt")
    t.eq(craft(steps).count, 3, "6 bars make 3 belts")
end

return tests
