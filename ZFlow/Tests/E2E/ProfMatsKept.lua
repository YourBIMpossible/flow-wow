local _, ns = ...
-- Lead section 416 item 3: every item the profession plan's steps name as
-- a material is kept off the sell list and kept for the auction house
-- (owner 11-20, DISPATCH 382: a profession material is never vendored).
-- For each profession: one made-up recipe that uses one made-up grey
-- material with a vendor price, that material in the bags. The plan
-- (addon.profPlan.plan) names it; the live sell listing
-- (SellList.Listing, what the merchant window shows) must not sell it and
-- must keep it for that profession. Loaded the way the game loads it
-- (ns.offline.addon) on a fake client; made-up items. Not tested in game.
local tests = {}

local PROFS = { "Alchemy", "Blacksmithing", "Cooking", "Enchanting", "Engineering", "First Aid",
    "Leatherworking", "Tailoring", "Fishing", "Herbalism", "Mining", "Skinning" }
local RECIPE = "Test Mixture"

-- opts: prof, mat (the material's key), other (a grey item no step names, or nil),
-- noBook (no recipe: the plan names nothing), have (how many of mat, 3 by
-- default), subclassID (mat's subclass, or nil)
local function start(opts)
    local c = ns.make.fakeClient()
    local book = { [RECIPE] = { profession = opts.prof, makes = opts.mat + 500, mats = { [opts.mat] = 1 } } }
    if opts.noBook then book = {} end
    c.setSaved(ns.id.charDB, { learned = {
        facts = { profSkill = { [opts.prof] = { skill = 50, max = 75 } }, recipeBook = book },
        recipeColors = { [RECIPE] = { optimal = { lo = 45, hi = 60 } } },
    } })
    c.setZone(1, 1411); c.setFaction("Horde"); c.setFacing(0)
    c.setPosition(1411, 0.5, 0.5); c.setMapSize(1411, 1000, 500); c.setMapCont(1411, 1)
    local info = { [opts.mat] = { name = "Test Dust", quality = 0, sellPrice = 5, classID = 7,
        subclassID = opts.subclassID } }
    local bags = { { item = opts.mat, count = opts.have or 3 } }
    if opts.other then
        info[opts.other] = { name = "Broken Fang", quality = 0, sellPrice = 4, classID = 15 }
        bags[#bags + 1] = { item = opts.other, count = 1 }
    end
    c.setItemInfo(info)
    c.setBagItems(bags)
    c.setProfessions({ opts.prof })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function named(steps, item)
    for _, s in ipairs(steps or {}) do
        if s.item == item then return true end
        for _, m in ipairs(type(s.mats) == "table" and s.mats or {}) do
            if m.item == item then return true end
        end
    end
    return false
end

local function rowOf(rows, key)
    for _, r in ipairs(type(rows) == "table" and rows or {}) do
        if r.key == key then return r end
    end
    return nil
end

for i, prof in ipairs(PROFS) do
    tests["prof mats kept e2e: " .. prof .. ": a material its plan names is not sold, kept for the auction house"] = function(t)
        local mat = 7100 + i
        local c, addon = start({ prof = prof, mat = mat })
        t.ok(named(addon.profPlan.plan(prof), mat), prof .. ": the plan's steps name the material")
        local listing = ns.SellList.Listing(c, addon.store, nil, { status = ns.Reservations.NONE })
        t.ok(type(listing.list) == "table" and listing.list.ok, prof .. ": a listing")
        t.eq(rowOf(listing.list.rows, mat), nil, prof .. ": not on the sell list")
        local kept = rowOf(listing.kept.rows, mat)
        t.ok(kept ~= nil, prof .. ": kept")
        t.eq(kept and kept.rule, "professionMaterial", prof .. ": kept as a profession material")
        t.eq(kept and kept.reason, "for " .. prof .. ": " .. RECIPE, prof .. ": the reason the player sees")
        t.eq(listing.grey.rule, "kept", prof .. ": the grey line says kept, not sold")
    end
end

tests["prof mats kept e2e: a grey item no step names is still sold"] = function(t)
    local c, addon = start({ prof = "Tailoring", mat = 7190, other = 7191 })
    local listing = ns.SellList.Listing(c, addon.store, nil, { status = ns.Reservations.NONE })
    t.ok(rowOf(listing.list.rows, 7191) ~= nil, "junk is still on the sell list")
    t.eq(rowOf(listing.list.rows, 7190), nil, "the material is not")
end

-- Lead section 418 item 4 (a): gathered goods of a profession the player
-- has are kept though no plan step names them, known by the item's class
-- (Trade Goods, 7) and subclass: Cloth 5, Leather 6, Metal & Stone 7,
-- Meat 8, Herb 9. No recipe: the plan names nothing. (b): all of it is
-- spare, so the row says where the spare goes, in words only.
local GATHERED = {
    { prof = "Mining", sub = 7, word = "ore" },
    { prof = "Herbalism", sub = 9, word = "herbs" },
    { prof = "Skinning", sub = 6, word = "skins" },
    { prof = "Fishing", sub = 8, word = "fish" },
    { prof = "Tailoring", sub = 5, word = "cloth" },
    { prof = "First Aid", sub = 5, word = "cloth" },
}
for i, g in ipairs(GATHERED) do
    tests["prof mats kept e2e: " .. g.prof .. ": its gathered goods are kept with no step naming them"] = function(t)
        local mat = 7300 + i
        local c, addon = start({ prof = g.prof, mat = mat, noBook = true, have = 4, subclassID = g.sub })
        t.ok(not named(addon.profPlan.plan(g.prof), mat), g.prof .. ": no step names it")
        local listing = ns.SellList.Listing(c, addon.store, nil, { status = ns.Reservations.NONE })
        t.eq(rowOf(listing.list.rows, mat), nil, g.prof .. ": not on the sell list")
        local kept = rowOf(listing.kept.rows, mat)
        t.ok(kept ~= nil, g.prof .. ": kept")
        t.eq(kept and kept.rule, "professionMaterial", g.prof .. ": kept as a profession material")
        t.eq(kept and kept.reason, "for " .. g.prof .. ": " .. g.word .. " (spare 4: sell at the auction house)",
            g.prof .. ": the reason the player sees")
    end
end

tests["prof mats kept e2e: gathered goods of a profession the player lacks are still sold"] = function(t)
    local c, addon = start({ prof = "Mining", mat = 7390, noBook = true, have = 4, subclassID = 9 })
    local listing = ns.SellList.Listing(c, addon.store, nil, { status = ns.Reservations.NONE })
    t.ok(rowOf(listing.list.rows, 7390) ~= nil, "a herb with no Herbalism is on the sell list")
end

-- (b): more than the plan's steps need. Skill 50 of 75, orange to 60:
-- 11 crafts of one each; 20 in the bags leaves 9 spare.
tests["prof mats kept e2e: a step material held past the steps' need says the spare goes to the auction house"] = function(t)
    local c, addon = start({ prof = "Tailoring", mat = 7391, have = 20 })
    local listing = ns.SellList.Listing(c, addon.store, nil, { status = ns.Reservations.NONE })
    t.eq(rowOf(listing.list.rows, 7391), nil, "not on the sell list")
    local kept = rowOf(listing.kept.rows, 7391)
    t.ok(kept ~= nil, "kept")
    t.eq(kept and kept.reason, "for Tailoring: " .. RECIPE .. " (spare 9: sell at the auction house)",
        "the reason the player sees")
end

return tests
