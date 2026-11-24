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

return tests
