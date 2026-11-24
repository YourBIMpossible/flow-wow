local _, ns = ...
-- G2 end to end, on the whole add-on loaded on a fake client: with the
-- vendor automations from the import turned on in the account data, the
-- sell list at a merchant says first what each would do and that Z-Flow
-- does none of it by itself. Nothing is sold, also after the window has
-- been open a while and the bags changed. A grey trade good is shown as
-- kept, never offered. Made-up items. Not run: no Lua on this machine.
-- Not tested in game.
--
-- Fails before: no such lines, and the grey trade good is offered.
local tests = {}

local BONE, SCRAP = 3300, 3304
local INFO = {
    [BONE] = { name = "Cracked Bone", quality = 0, sellPrice = 5 },
    [SCRAP] = { name = "Frayed Scrap", quality = 0, sellPrice = 3, classID = 7 },
}
local BAG = {
    { bag = 0, slot = 1, item = BONE, count = 2 },
    { bag = 0, slot = 2, item = SCRAP, count = 4 },
}

local atBoot = setmetatable({}, { __mode = "k" })
local function newProblems(addon) return addon.problems:count() - atBoot[addon] end

local function boot(sell)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { settings = { sell = sell or {} } })
    c.setSaved(ns.id.charDB, {})
    c.setBagItems(BAG)
    c.setItemInfo(INFO)
    c.setWindow("MerchantFrame", { shown = true })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    atBoot[addon] = addon.problems:count()
    return c, addon
end

local function parts(c)
    local w = c.kitWindows().SellList
    return type(w) == "table" and w.parts or {}
end

local function lineAt(c, text)
    for i, p in ipairs(parts(c)) do
        if p.kind == "line" and p.text == text then return i end
    end
    return nil
end

-- The item lines of a listing made now, through the module's own Tree
-- (the drawn parts carry only kind, path, key and text): name -> { index,
-- part }, index in Kit.Each order with the lines too.
local function treeParts(c, addon)
    local tree = ns.Kit.Window(addon.SellList.Tree(c, addon.store, nil, { status = addon.Reservations.NONE }))
    local items, lines, i = {}, {}, 0
    ns.Kit.Each(tree, function(p)
        i = i + 1
        if p.kind == "itemLine" and p.name then items[p.name] = { index = i, part = p } end
        if p.kind == "line" and p.text then lines[p.text] = i end
    end)
    return items, lines
end

local function title() return tostring(ns.id.title) end

tests["sell auto e2e: junk and repair on - the merchant's sell list says what is not done, first"] = function(t)
    local c, addon = boot({ autoJunk = true, autoRepair = true })
    c.setMerchantOpen(true)
    local junk = "Sell junk automatically is on, but " .. title()
        .. " sells nothing by itself. Grey items it would sell: 1 item."
    local repair = "Repair automatically is on, but " .. title() .. " repairs nothing by itself: "
        .. "use the merchant's Repair button. The repair cost is not read yet."
    local j, r = lineAt(c, junk), lineAt(c, repair)
    t.ok(j ~= nil, "the junk line is shown")
    t.ok(r ~= nil, "the repair line is shown")
    t.ok(j and r and j < r, "junk first, then repair")
    local items, lines = treeParts(c, addon)
    local bone = items["Cracked Bone"]
    t.ok(bone ~= nil and lines[junk] ~= nil and lines[junk] < bone.index, "above the rows to sell")
    t.eq(#c.soldSlots, 0, "nothing was sold")
    c.advance(30, 60)
    c.setBagItems({ { bag = 0, slot = 1, item = BONE, count = 2 } })
    c.advance(5, 20)
    t.eq(#c.soldSlots, 0, "still nothing sold after the window stayed open and the bags changed")
    t.eq(newProblems(addon), 0)
end

tests["sell auto e2e: all off - no such line"] = function(t)
    local c, addon = boot()
    c.setMerchantOpen(true)
    for _, p in ipairs(parts(c)) do
        t.ok(not (p.kind == "line" and tostring(p.text):find("automatically is on", 1, true)),
            "no automation line: " .. tostring(p.text))
    end
    t.eq(newProblems(addon), 0)
end

tests["sell auto e2e: the grey trade good is kept with why, never offered"] = function(t)
    local c, addon = boot()
    c.setMerchantOpen(true)
    local items = treeParts(c, addon)
    local scrap = items["Frayed Scrap"] and items["Frayed Scrap"].part
    t.ok(scrap ~= nil, "the material has a line")
    t.eq(scrap and scrap.note, addon.SellList.MATERIAL_KEPT, "kept, with why")
    t.eq(scrap and scrap.money, nil, "no price offered for it")
    local bone = items["Cracked Bone"] and items["Cracked Bone"].part
    t.ok(bone ~= nil and bone.note ~= addon.SellList.MATERIAL_KEPT, "the grey bone is still offered")
    t.eq(newProblems(addon), 0)
end

return tests
