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

-- opts: prof, mat (the material's key), other (a grey item no step names, or nil)
local function start(opts)
    local c = ns.make.fakeClient()
    local book = { [RECIPE] = { profession = opts.prof, makes = opts.mat + 500, mats = { [opts.mat] = 1 } } }
    c.setSaved(ns.id.charDB, { learned = {
        facts = { profSkill = { [opts.prof] = { skill = 50, max = 75 } }, recipeBook = book },
        recipeColors = { [RECIPE] = { optimal = { lo = 45, hi = 60 } } },
    } })
    c.setZone(1, 1411); c.setFaction("Horde"); c.setFacing(0)
    c.setPosition(1411, 0.5, 0.5); c.setMapSize(1411, 1000, 500); c.setMapCont(1411, 1)
    local info = { [opts.mat] = { name = "Test Dust", quality = 0, sellPrice = 5, classID = 7 } }
    local bags = { { item = opts.mat, count = 3 } }
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

return tests
