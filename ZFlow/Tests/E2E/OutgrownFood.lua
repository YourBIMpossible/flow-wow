local _, ns = ...
-- Outgrown food and drink (G5, lead section 451), end to end, on the whole
-- add-on loaded on a fake client: the two places that hand the rule its
-- facts. The sell list (UI/SellList.lua, SellList.Listing) lists the weak
-- food as a row to sell, so the player's own click on Sell these sells it;
-- the bag marks (Items/BagMarks.lua, B.Context) put the sell coin on its
-- slot. The better food, and food eaten for its Well Fed buff, are left
-- alone. Made-up counts; offline: the fake client's reads, not the game's.
-- Not tested in game.
--
-- Fails before the change (fork/zflow f31dd929): no rule sells food, so the
-- button reads "Nothing to sell" and no slot is marked.
local tests = {}

local JERKY, HAUNCH, STEW = 117, 2287, 5525
local EAT = "Use: Restores 61 health over 18 sec. Must remain seated while eating."
local FED = "Use: Restores 243 health over 21 sec. Must remain seated while eating. "
    .. "If you spend at least 10 seconds eating you will become well fed."
local INFO = {
    [JERKY] = { name = "Tough Jerky", quality = 1, sellPrice = 1, classID = 0, subclassID = 5, minLevel = 1 },
    [HAUNCH] = { name = "Haunch of Meat", quality = 1, sellPrice = 6, classID = 0, subclassID = 5, minLevel = 15 },
    [STEW] = { name = "Westfall Stew", quality = 1, sellPrice = 4, classID = 0, subclassID = 5, minLevel = 5 },
}
-- Twelve of the better food, so the weak one is outgrown; the stew is weak
-- too, but it is eaten for its buff.
local BAG = {
    { bag = 0, slot = 1, item = JERKY, count = 4 },
    { bag = 0, slot = 2, item = HAUNCH, count = 12 },
    { bag = 0, slot = 3, item = STEW, count = 2 },
}

local atBoot = setmetatable({}, { __mode = "k" })
local function newProblems(addon) return addon.problems:count() - atBoot[addon] end

-- level: the player's level, or false for a level the client does not give.
local function boot(level)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setBagItems(BAG)
    c.setItemInfo(INFO)
    c.setItemLines(JERKY, { "Tough Jerky", EAT })
    c.setItemLines(HAUNCH, { "Haunch of Meat", EAT })
    c.setItemLines(STEW, { "Westfall Stew", FED })
    if level == false then c.setLevel(nil) else c.setLevel(level or 20) end
    c.setWindow("MerchantFrame", { shown = true })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    c.fire("BAG_UPDATE_DELAYED")
    c.advance(1, 4)
    atBoot[addon] = addon.problems:count()
    return c, addon
end

local function part(c, key)
    local win = c.kitWindows().SellList
    for _, p in ipairs(type(win) == "table" and win.parts or {}) do
        if p.key == key then return p end
    end
    return nil
end

local function soldAt(c)
    local out = {}
    for i, s in ipairs(c.soldSlots or {}) do out[i] = s.bag .. ":" .. s.slot end
    return out
end

tests["outgrown food e2e: the sell list offers the weak food, and the player's click sells only that"] = function(t)
    local c, addon = boot()
    c.setMerchantOpen(true)
    local button = part(c, "sellThese")
    t.ok(button ~= nil, "the button on the sell list")
    if button == nil then return end
    t.eq(button.text, "Sell these", "there is a row to sell")
    t.eq(#(c.soldSlots or {}), 0, "nothing is sold before the click")
    t.eq(c.kitClick("SellList", "sellThese"), true, "the player presses it")
    c.advance(1, 10)
    t.eq(soldAt(c), { "0:1" }, "the weak food only: not the better one, not the buff food")
    t.eq(newProblems(addon), 0)
end

tests["outgrown food e2e: the bag marks put the sell coin on the weak food's slot, and no other"] = function(t)
    local c, addon = boot()
    t.eq(c.bagMarksDrawn and c.bagMarksDrawn() or nil, { [0] = { [1] = "sell" } })
    t.eq(#(c.soldSlots or {}), 0, "a mark sells nothing")
    t.eq(newProblems(addon), 0)
end

tests["outgrown food e2e: with your level not known nothing is offered or marked"] = function(t)
    local c, addon = boot(false)
    c.setMerchantOpen(true)
    local button = part(c, "sellThese")
    t.ok(button ~= nil, "the button on the sell list")
    if button == nil then return end
    t.eq(c.kitClick("SellList", "sellThese"), false, "it cannot be pressed")
    t.eq(#(c.soldSlots or {}), 0, "nothing sold")
    t.eq(c.bagMarksDrawn and c.bagMarksDrawn() or nil, {}, "nothing marked")
    t.eq(newProblems(addon), 0)
end

return tests
