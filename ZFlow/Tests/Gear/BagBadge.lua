local _, ns = ...

-- Tests for ZFlow/Gear/BagBadge.lua (G14, section 393): an item in the bags
-- that is an upgrade over what is worn carries a small badge on its bag
-- slot naming the role it is for (D dps, T tank, H heal). Look only. Fake
-- client (setBagItems, setItem, setWorn, markBagSlots, bagMarks) and a real
-- kernel. Made-up items; not tested in game.
--
-- Red before the code: ns.GearBagBadge does not exist.

local tests = {}
local function BB() return ns.GearBagBadge end

local STA, STR = "ITEM_MOD_STAMINA_SHORT", "ITEM_MOD_STRENGTH_SHORT"
local WORN, TOUGH, STRONG, WEAK, PLATE = "item:11", "item:12", "item:13", "item:14", "item:15"

local function packs()
    return { WARRIOR = {
        weights = {
            dps = { evidence = "first guess", values = { [STR] = 1, [STA] = 0.35 } },
            tank = { evidence = "first guess", values = { [STA] = 1, [STR] = 0.6 } },
        },
        proficiency = { evidence = "first guess", [4] = { [0] = true, [1] = true, [2] = true, [3] = true } },
    } }
end

local function helm(stats, unmet)
    return { kind = "INVTYPE_HEAD", stats = stats, classID = 4, subclassID = 3, minLevel = 1, unmet = unmet or {} }
end

local function client()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR")
    c.setLevel(10)
    c.setDualWield(false)
    c.setItem(WORN, helm({ [STA] = 2, [STR] = 2 }))
    c.setItem(TOUGH, helm({ [STA] = 10 }))
    c.setItem(STRONG, helm({ [STR] = 10 }))
    c.setItem(WEAK, helm({ [STA] = 1 }))
    c.setItem(PLATE, helm({ [STR] = 30 }, { "Plate" }))
    c.setWorn(1, WORN)
    return c
end

local function bags(...)
    local out = {}
    for i, link in ipairs({ ... }) do out[i] = { bag = 0, slot = i, item = link, count = 1 } end
    return out
end

tests["bag badge: the module and its words exist"] = function(t)
    t.eq(type(BB()), "table", "ns.GearBagBadge")
    if type(BB()) ~= "table" then return end
    t.eq(type(BB().Marks), "function", "GearBagBadge.Marks")
    t.eq(BB().LETTER, { dps = "D", tank = "T", heal = "H" })
end

tests["bag badge: an upgrade in the bags is badged with the chosen role"] = function(t)
    if type(BB()) ~= "table" then return t.ok(false, "ns.GearBagBadge") end
    local c = client()
    c.setBagItems(bags(WEAK, STRONG, TOUGH))
    -- Both helms beat the worn one for both roles (see the next test); a
    -- chosen role puts only its own letter on them, and the weak one none.
    t.eq(BB().Marks(c, packs(), "dps"), { { bag = 0, slot = 2, text = "D" }, { bag = 0, slot = 3, text = "D" } },
        "dps only")
    t.eq(BB().Marks(c, packs(), "tank"), { { bag = 0, slot = 2, text = "T" }, { bag = 0, slot = 3, text = "T" } },
        "tank only")
end

tests["bag badge: no role chosen - each upgrade names every role it is for"] = function(t)
    if type(BB()) ~= "table" then return t.ok(false, "ns.GearBagBadge") end
    local c = client()
    c.setBagItems(bags(STRONG, TOUGH, WEAK))
    t.eq(BB().Marks(c, packs(), ""), {
        { bag = 0, slot = 1, text = "DT" },
        { bag = 0, slot = 2, text = "DT" },
    }, "both beat the worn helm for both roles; the weak one for neither")
end

tests["bag badge: an item you cannot use, or not read yet, is never badged"] = function(t)
    if type(BB()) ~= "table" then return t.ok(false, "ns.GearBagBadge") end
    local c = client()
    c.setBagItems(bags(PLATE, "item:99", STRONG))
    t.eq(BB().Marks(c, packs(), "dps"), { { bag = 0, slot = 3, text = "D" } })
end

tests["bag badge: the bags not readable - nil"] = function(t)
    if type(BB()) ~= "table" then return t.ok(false, "ns.GearBagBadge") end
    t.eq(BB().Marks(client(), packs(), "dps"), nil)
    t.eq(BB().Marks({}, packs(), "dps"), nil)
end

tests["bag badge: the module draws on login and bag changes; off draws none"] = function(t)
    if type(BB()) ~= "table" then return t.ok(false, "ns.GearBagBadge") end
    local c = client()
    c.setBagItems(bags(WEAK))
    local k = ns.Kernel({}, c)
    BB().Declare(k, packs())
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    t.eq(k:ModuleState(BB().NAME), "started")
    t.eq(c.bagMarks(), {})
    c.setBagItems(bags(WEAK, STRONG))
    c.fire("BAG_UPDATE_DELAYED")
    t.eq(c.bagMarks(), { { bag = 0, slot = 2, text = "DT" } }, "no role chosen")
    t.eq(k.settings:set(BB().SETTING, false), true)
    c.fire("BAG_UPDATE_DELAYED")
    t.eq(c.bagMarks(), {})
end

return tests
