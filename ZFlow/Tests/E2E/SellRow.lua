local _, ns = ...
-- G1 end to end, on the whole add-on loaded on a fake client: each row of
-- the sell list at the merchant has its own "Sell" button. A click sells
-- every stack of that one item, one stack a frame, and leaves the other
-- rows; nothing is sold without a click, in combat, or with the merchant
-- closed. Made-up items and slots. Not run: no Lua on this machine. Not
-- tested in game.
--
-- Fails before: there is no part keyed sellRow.<item>.
local tests = {}

local FANG, SCRAP, CLOTH = 97, 2934, 2589
local INFO = {
    [FANG] = { name = "Broken Fang", quality = 0, sellPrice = 4 },
    [SCRAP] = { name = "Ruined Leather Scraps", quality = 0, sellPrice = 1 },
    [CLOTH] = { name = "Linen Cloth", quality = 1, sellPrice = 13, classID = 7 },
}
local BAG = {
    { bag = 0, slot = 1, item = FANG, count = 3 },
    { bag = 0, slot = 3, item = CLOTH, count = 20 },
    { bag = 0, slot = 4, item = FANG, count = 2 },
    { bag = 1, slot = 1, item = SCRAP, count = 1 },
}

local atBoot = setmetatable({}, { __mode = "k" })
local function newProblems(addon) return addon.problems:count() - atBoot[addon] end

local function boot()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
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

local function part(c, key)
    local win = c.kitWindows().SellList
    for _, p in ipairs(type(win) == "table" and win.parts or {}) do
        if p.key == key then return p end
    end
    return nil
end

local function where(c)
    local out = {}
    for i, s in ipairs(c.soldSlots or {}) do out[i] = s.bag .. ":" .. s.slot end
    return out
end

local function frame(c) c.advance(0.02, 1) end

tests["sell row e2e: each row to sell has its own Sell button"] = function(t)
    local c, addon = boot()
    c.setMerchantOpen(true)
    local fang, scrap = part(c, "sellRow." .. FANG), part(c, "sellRow." .. SCRAP)
    t.ok(fang ~= nil and fang.kind == "button" and fang.text == "Sell", "the fang row's button")
    t.ok(scrap ~= nil, "the scraps row's button")
    t.eq(part(c, "sellRow." .. CLOTH), nil, "a kept item has none")
    t.ok(part(c, "sellThese") ~= nil, "Sell these is still there")
    t.eq(#(c.soldSlots or {}), 0, "nothing sold on open")
    t.eq(newProblems(addon), 0)
end

tests["sell row e2e: a click sells that item's stacks only, one a frame"] = function(t)
    local c, addon = boot()
    c.setMerchantOpen(true)
    t.eq(c.kitClick("SellList", "sellRow." .. FANG), true, "the player presses the fang row's Sell")
    t.eq(where(c), { "0:1" }, "one stack at the click")
    frame(c); frame(c); frame(c)
    t.eq(where(c), { "0:1", "0:4" }, "both fang stacks, the scraps left")
    t.eq(newProblems(addon), 0)
end

tests["sell row e2e: in combat or with the merchant closed a click sells nothing"] = function(t)
    local c = boot()
    c.setMerchantOpen(true)
    c.setCombat(true)
    c.kitClick("SellList", "sellRow." .. SCRAP)
    frame(c)
    t.eq(#(c.soldSlots or {}), 0, "in combat: nothing")
    c.setCombat(false)
    c.setMerchantOpen(false)
    c.kitClick("SellList", "sellRow." .. SCRAP)
    frame(c)
    t.eq(#(c.soldSlots or {}), 0, "merchant closed: nothing")
end

return tests
