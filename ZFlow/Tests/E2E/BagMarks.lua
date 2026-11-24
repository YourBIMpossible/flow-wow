local _, ns = ...
-- G4 bag marks end to end, on the whole add-on loaded on a fake client: a
-- bag change (BAG_UPDATE_DELAYED) draws a mark on the slots the add-on has
-- an opinion on. Look only: nothing is used, sold or moved.
-- Offline: the reads are the fake client's, not the game's. Not tested in game.
-- Made-up items only.
local tests = {}

local INFO = {
    [7001] = { name = "Cracked Pot", quality = 0, sellPrice = 3, classID = 15 },
    [7002] = { name = "Sealed Note", quality = 1, sellPrice = 0, classID = 12 },
    [7003] = { name = "Smooth Stone", quality = 1, sellPrice = 2, classID = 7 },
}

local function start(on)
    local c = ns.make.fakeClient()
    local account = {}
    if on ~= nil then account.settings = { bags = { marks = on } } end
    c.setSaved(ns.id.accountDB, account)
    c.setSaved(ns.id.charDB, {})
    c.setItemInfo(INFO)
    c.setBagItems({})
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

-- Fails before: Items/BagMarks.lua and c.markBagSlots are absent.
tests["bag marks: a bag change marks junk and a quest item, and nothing else"] = function(t)
    local c = start()
    t.eq(c.bagMarksDrawn and c.bagMarksDrawn() or nil, {}, "empty bags: no marks")
    c.setBagItems({
        { bag = 0, slot = 1, item = "item:7001:0:0:0:0:0:0:0", count = 4 },
        { bag = 0, slot = 2, item = "item:7002:0:0:0:0:0:0:0", count = 1 },
        { bag = 1, slot = 3, item = "item:7003:0:0:0:0:0:0:0", count = 9 },
    })
    c.fire("BAG_UPDATE_DELAYED")
    t.eq(c.bagMarksDrawn and c.bagMarksDrawn() or nil, { [0] = { [1] = "sell", [2] = "quest" } })
    c.setBagItems({ { bag = 0, slot = 2, item = "item:7002:0:0:0:0:0:0:0", count = 1 } })
    c.fire("BAG_UPDATE_DELAYED")
    t.eq(c.bagMarksDrawn(), { [0] = { [2] = "quest" } }, "the sold junk's mark goes")
    t.eq(#(c.soldSlots or {}), 0, "nothing sold by the add-on")
end

-- Fails before: the setting row bags.marks is absent.
tests["bag marks: the setting off draws none"] = function(t)
    local c = start(false)
    c.setBagItems({ { bag = 0, slot = 1, item = "item:7001:0:0:0:0:0:0:0", count = 4 } })
    c.fire("BAG_UPDATE_DELAYED")
    t.eq(c.bagMarksDrawn and c.bagMarksDrawn() or nil, {})
end

-- G4 remaining: the in-game context carries the gear and the profession
-- materials. Warrior weights (ZFlow/Classes/Warrior.lua): dps Strength 1.0,
-- Stamina 0.35. The worn helm (2 Stamina, 2 Strength) scores 2.7 for dps;
-- the bag helm (10 Strength) 10: an upgrade you can wear now. The cloth is
-- a mat of a recipe this character's own profession window was read with
-- (char learned.facts.recipeBook). Made-up items.
local WORN, STRONG, WEAK, CLOTH = "item:7101", "item:7102", "item:7103", "item:7104"
local STA, STR = "ITEM_MOD_STAMINA_SHORT", "ITEM_MOD_STRENGTH_SHORT"

local function helm(stats)
    return { kind = "INVTYPE_HEAD", stats = stats, classID = 4, subclassID = 3, minLevel = 1, unmet = {} }
end

local function startGear(char)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, char or {})
    c.setClass("WARRIOR")
    c.setLevel(10)
    c.setDualWield(false)
    c.setWeaponSkills({ "Swords", "Defense" })
    c.setItemInfo({
        [7101] = { name = "Worn Cap", quality = 1, sellPrice = 5, classID = 4, minLevel = 1 },
        [7102] = { name = "Strong Cap", quality = 2, sellPrice = 9, classID = 4, minLevel = 1 },
        [7103] = { name = "Weak Cap", quality = 1, sellPrice = 4, classID = 4, minLevel = 1 },
        [7104] = { name = "Plain Cloth", quality = 1, sellPrice = 1, classID = 7 },
    })
    c.setItem(WORN, helm({ [STA] = 2, [STR] = 2 }))
    c.setItem(STRONG, helm({ [STR] = 10 }))
    c.setItem(WEAK, helm({ [STA] = 1 }))
    c.setWorn(1, WORN)
    c.setBagItems({})
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

-- Fails before: BankList.Context alone carries no gear, level or role.
tests["bag marks: an upgrade from the real gear read, not a worse piece"] = function(t)
    local c = startGear({ settings = { spec = { role = "dps" } } })
    c.setBagItems({
        { bag = 0, slot = 1, item = STRONG, count = 1 },
        { bag = 0, slot = 2, item = WEAK, count = 1 },
    })
    c.fire("BAG_UPDATE_DELAYED")
    t.eq(c.bagMarksDrawn(), { [0] = { [1] = "upgrade" } })
end

-- Fails before: BankList.Context carries no materials.
tests["bag marks: a mat of a saved recipe is marked kept for a profession"] = function(t)
    local book = { ["Plain Bandage"] = { makes = 7105, yield = 1, mats = { [7104] = 2 }, profession = "First Aid" } }
    local c = startGear({ learned = { facts = { recipeBook = book } } })
    c.setBagItems({ { bag = 1, slot = 4, item = CLOTH, count = 6 } })
    c.fire("BAG_UPDATE_DELAYED")
    t.eq(c.bagMarksDrawn(), { [1] = { [4] = "material" } })
end

-- No role chosen: the class pack's first role (as the gear why word).
tests["bag marks: no role chosen still marks the upgrade"] = function(t)
    local c = startGear()
    c.setBagItems({ { bag = 0, slot = 1, item = STRONG, count = 1 } })
    c.fire("BAG_UPDATE_DELAYED")
    t.eq(c.bagMarksDrawn(), { [0] = { [1] = "upgrade" } })
end

return tests
