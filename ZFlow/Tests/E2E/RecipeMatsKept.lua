local _, ns = ...
-- E-46 (FLOW-PARITY, lead section 683): a reagent of a recipe the player has
-- learned (seen in their own profession window, saved by Items/RecipeBook.lua)
-- is kept off the sell list, though the profession plan does not pick that
-- recipe. Flow: Modules/Items/Reagents.lua (R:UsedBy, learned from the
-- windows) read by Modules/Items/Disposition.lua:274-305 professionMaterial,
-- recipes first. Loaded the way the game loads it (ns.offline.addon) on a
-- fake client; made-up items. Not tested in game.
--
-- Fails before the change: the sell list's materials came only from the
-- plan's steps and the gathered kinds, never from the recipe book.
local tests = {}

local MAT, JUNK = 7301, 7302
local RECIPE = "Test Charm"

local function start(prof, book)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.charDB, { learned = { facts = { recipeBook = book } } })
    c.setZone(1, 1411); c.setFaction("Horde"); c.setFacing(0)
    c.setPosition(1411, 0.5, 0.5); c.setMapSize(1411, 1000, 500); c.setMapCont(1411, 1)
    c.setItemInfo({
        [MAT] = { name = "Test Bead", quality = 0, sellPrice = 5, classID = 15 },
        [JUNK] = { name = "Broken Fang", quality = 0, sellPrice = 4, classID = 15 },
    })
    c.setBagItems({ { item = MAT, count = 3 }, { item = JUNK, count = 1 } })
    c.setProfessions({ prof })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function rowOf(rows, key)
    for _, r in ipairs(type(rows) == "table" and rows or {}) do
        if r.key == key then return r end
    end
    return nil
end

tests["recipe mats kept e2e: a reagent of a learned recipe is not sold"] = function(t)
    local book = { [RECIPE] = { profession = "Jewelcrafting", makes = 7801, mats = { [MAT] = 2 } } }
    local c, addon = start("Jewelcrafting", book)
    local listing = ns.SellList.Listing(c, addon.store, nil, { status = ns.Reservations.NONE })
    t.ok(type(listing.list) == "table" and listing.list.ok, "a listing")
    t.eq(rowOf(listing.list.rows, MAT), nil, "the reagent is not on the sell list")
    local kept = rowOf(listing.kept.rows, MAT)
    t.eq(kept and kept.rule, "professionMaterial", "kept as a profession material")
    t.eq(kept and kept.reason, "for Jewelcrafting: " .. RECIPE, "the reason the player sees")
    t.ok(rowOf(listing.list.rows, JUNK) ~= nil, "junk no recipe uses is still sold")
end

tests["recipe mats kept e2e: with no recipe saved the item is sold as before"] = function(t)
    local c, addon = start("Jewelcrafting", {})
    local listing = ns.SellList.Listing(c, addon.store, nil, { status = ns.Reservations.NONE })
    t.ok(rowOf(listing.list.rows, MAT) ~= nil, "on the sell list")
end

tests["recipe mats kept: RecipeBook.Materials adds a use once per profession"] = function(t)
    local store = { get = function() return {
        ["B Charm"] = { profession = "Jewelcrafting", mats = { [MAT] = 1 } },
        ["A Charm"] = { profession = "Jewelcrafting", mats = { [MAT] = 1 } },
        ["Odd"] = { profession = "", mats = { [MAT] = 1 } },
    } end }
    local out = ns.RecipeBook.Materials(store, { [MAT] = { { prof = "Tailoring", what = "Bolt", need = 1 } } })
    t.eq(#out[MAT], 2, "the plan's use and one recipe use")
    t.eq(out[MAT][1].prof, "Tailoring", "the plan's use first, as given")
    t.eq(out[MAT][2].prof, "Jewelcrafting", "then the recipe's")
    t.eq(out[MAT][2].what, "A Charm", "the first recipe by name")
    local same = ns.RecipeBook.Materials(store, { [MAT] = { { prof = "Jewelcrafting", what = "Plan", need = 1 } } })
    t.eq(#same[MAT], 1, "a profession the plan already names is not added again")
    t.eq(ns.RecipeBook.Materials(nil, nil), nil, "no store: nil")
end

return tests
