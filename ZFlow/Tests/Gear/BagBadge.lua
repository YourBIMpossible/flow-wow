local _, ns = ...

-- Tests for ZFlow/Gear/BagBadge.lua (G14, section 393): a gear item in the
-- bags carries a small badge on its bag slot: the letter of each role (D
-- dps, T tank, H heal) with its mark, better, worse or the same (parity row
-- E-03; before it only an upgrade was badged, with a bare letter, and the
-- texts here were "D", "T", "DT"). Look only. Fake client (setBagItems,
-- setItem, setWorn, markBagSlots, bagMarks) and a real kernel. Made-up
-- items; not tested in game. The marks themselves are tested in
-- Tests/Gear/BagBadgeArrows.lua.
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

-- One role's letter and mark, as the badge writes it.
local function P(role, way) return BB().Piece(role, way) end

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

tests["bag badge: gear in the bags is badged with the chosen role"] = function(t)
    if type(BB()) ~= "table" then return t.ok(false, "ns.GearBagBadge") end
    local c = client()
    c.setBagItems(bags(WEAK, STRONG, TOUGH))
    -- Both helms beat the worn one for both roles (see the next test) and
    -- the weak one is worse for both; a chosen role puts only its own
    -- letter on them.
    t.eq(BB().Marks(c, packs(), "dps"), {
        { bag = 0, slot = 1, text = P("dps", "down") },
        { bag = 0, slot = 2, text = P("dps", "up") },
        { bag = 0, slot = 3, text = P("dps", "up") },
    }, "dps only")
    t.eq(BB().Marks(c, packs(), "tank"), {
        { bag = 0, slot = 1, text = P("tank", "down") },
        { bag = 0, slot = 2, text = P("tank", "up") },
        { bag = 0, slot = 3, text = P("tank", "up") },
    }, "tank only")
end

tests["bag badge: no role chosen - each piece names every role"] = function(t)
    if type(BB()) ~= "table" then return t.ok(false, "ns.GearBagBadge") end
    local c = client()
    c.setBagItems(bags(STRONG, TOUGH, WEAK))
    t.eq(BB().Marks(c, packs(), ""), {
        { bag = 0, slot = 1, text = P("dps", "up") .. P("tank", "up") },
        { bag = 0, slot = 2, text = P("dps", "up") .. P("tank", "up") },
        { bag = 0, slot = 3, text = P("dps", "down") .. P("tank", "down") },
    }, "both beat the worn helm for both roles; the weak one is worse for both")
end

tests["bag badge: an item you cannot use, or not read yet, is never badged"] = function(t)
    if type(BB()) ~= "table" then return t.ok(false, "ns.GearBagBadge") end
    local c = client()
    c.setBagItems(bags(PLATE, "item:99", STRONG))
    t.eq(BB().Marks(c, packs(), "dps"), { { bag = 0, slot = 3, text = P("dps", "up") } })
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
    local weak = { bag = 0, slot = 1, text = P("dps", "down") }
    t.eq(c.bagMarks(), { weak }, "drawn at login")
    c.setBagItems(bags(WEAK, STRONG))
    c.fire("BAG_UPDATE_DELAYED")
    t.eq(c.bagMarks(), { weak, { bag = 0, slot = 2, text = P("dps", "up") } }, "no role chosen, no tank sign: dps only")
    t.eq(k.settings:set(BB().SETTING, false), true)
    c.fire("BAG_UPDATE_DELAYED")
    t.eq(c.bagMarks(), {})
end

-- Section 564 R3: equipping the piece the badge suggests never makes the
-- piece it replaced the next suggestion. Red before the code: with no role
-- chosen each role was badged, so the swap marked the old piece for tank.
local DPSY, TANKY = "item:21", "item:22"

tests["bag badge: no swap loop - the replaced piece is not the next suggestion"] = function(t)
    if type(BB()) ~= "table" then return t.ok(false, "ns.GearBagBadge") end
    local c = client()
    c.setItem(DPSY, helm({ [STR] = 4 }))
    c.setItem(TANKY, helm({ [STA] = 4 }))
    c.setWorn(1, TANKY)
    c.setBagItems(bags(DPSY))
    local k = ns.Kernel({}, c)
    k:Setting({ key = BB().ROLE, scope = "char", type = "string", default = "", label = "Your role" })
    BB().Declare(k, packs())
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    t.eq(c.bagMarks(), { { bag = 0, slot = 1, text = P("dps", "up") } }, "no role chosen: judged for dps")
    c.setWorn(1, DPSY)
    c.setBagItems(bags(TANKY))
    c.fire("BAG_UPDATE_DELAYED")
    t.eq(c.bagMarks(), { { bag = 0, slot = 1, text = P("dps", "down") } }, "after the swap the old piece is not suggested")
    t.eq(k.settings:set(BB().ROLE, "tank"), true)
    c.fire("BAG_UPDATE_DELAYED")
    t.eq(c.bagMarks(), { { bag = 0, slot = 1, text = P("tank", "up") } }, "the chosen role decides")
end

return tests
