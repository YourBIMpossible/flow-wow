local _, ns = ...
-- The "Sell these" button (lead section 337 item 1), end to end, on the
-- whole add-on loaded on a fake client: the button on the sell list's kit
-- window sells the rows the list shows, by bag and slot, only on the
-- player's own click, with the merchant open and out of combat, one stack
-- per frame. A merchant closing stops it; a slot that changed is skipped;
-- a buyback note follows. Made-up items and slots. Not tested in game.
--
-- Fails before the change: the sell list has no "Sell these" button
-- (no part keyed sellThese), and the fake client has no sell call
-- (c.soldSlots is nil).
local tests = {}

local FANG, SCRAP, STONE, CLOTH = 97, 2934, 6948, 2589
local INFO = {
    [FANG] = { name = "Broken Fang", quality = 0, sellPrice = 4 },
    [SCRAP] = { name = "Ruined Leather Scraps", quality = 0, sellPrice = 1 },
    [STONE] = { name = "Hearthstone", quality = 1, sellPrice = 0 },
    [CLOTH] = { name = "Linen Cloth", quality = 1, sellPrice = 13, classID = 7 },
}
-- Two stacks of fangs and one of scraps to sell; the rest is kept.
local BAG = {
    { bag = 0, slot = 1, item = FANG, count = 3 },
    { bag = 0, slot = 2, item = STONE, count = 1 },
    { bag = 0, slot = 3, item = CLOTH, count = 20 },
    { bag = 0, slot = 4, item = FANG, count = 2 },
    { bag = 1, slot = 1, item = SCRAP, count = 1 },
}

local atBoot = setmetatable({}, { __mode = "k" })
local function newProblems(addon) return addon.problems:count() - atBoot[addon] end

local function boot(bag)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setBagItems(bag or BAG)
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

local function shows(c, kind, text)
    local win = c.kitWindows().SellList
    for _, p in ipairs(type(win) == "table" and win.parts or {}) do
        if p.kind == kind and p.text == text then return true end
    end
    return false
end

local function sold(c)
    return type(c.soldSlots) == "table" and #c.soldSlots or -1
end

local function frame(c) c.advance(0.02, 1) end

local BUYBACK = "Sold 6 items. Changed your mind? Buy them back on the merchant's Buyback tab."

tests["sell these: a click sells the listed rows, one stack per frame, then the buyback note"] = function(t)
    local c, addon = boot()
    c.setMerchantOpen(true)
    local button = part(c, "sellThese")
    t.ok(button ~= nil, "the button on the sell list")
    if button == nil then return end
    t.eq(button.kind, "button")
    t.eq(button.text, "Sell these")
    t.ok(shows(c, "header", "2 items to sell"), "the list shows two rows")
    t.eq(c.kitClick("SellList", "sellThese"), true, "the player presses it")
    t.eq(sold(c), 1, "one stack at the click")
    frame(c)
    t.eq(sold(c), 2, "the next one frame later")
    frame(c)
    t.eq(sold(c), 3, "the last one frame later")
    frame(c); frame(c)
    t.eq(sold(c), 3, "only the listed stacks")
    local where = {}
    for i, s in ipairs(c.soldSlots) do where[i] = s.bag .. ":" .. s.slot end
    t.eq(where, { "0:1", "0:4", "1:1" }, "by bag and slot, the kept ones left alone")
    t.ok(shows(c, "line", BUYBACK), "the buyback note")
    t.eq(newProblems(addon), 0)
end

tests["sell these: nothing is sold on merchant open, nor without a click"] = function(t)
    local c, addon = boot()
    c.setMerchantOpen(true)
    c.advance(2, 40)
    t.eq(sold(c), 0, "nothing at open")
    c.setMerchantOpen(false)
    c.setMerchantOpen(true)
    c.advance(2, 40)
    t.eq(sold(c), 0, "nothing at a second open")
    t.ok(part(c, "sellThese") ~= nil, "the button is there to press")
    t.eq(newProblems(addon), 0)
end

tests["sell these: nothing is sold in combat, and a run stops when combat starts"] = function(t)
    local c, addon = boot()
    c.setMerchantOpen(true)
    c.setCombat(true)
    c.kitClick("SellList", "sellThese")
    c.advance(1, 10)
    t.eq(sold(c), 0, "a click in combat sells nothing")
    t.ok(shows(c, "line", "Nothing sold: you are in combat."), "and says why")
    c.setCombat(false)
    t.eq(c.kitClick("SellList", "sellThese"), true)
    t.eq(sold(c), 1)
    c.setCombat(true)
    c.advance(1, 10)
    t.eq(sold(c), 1, "combat stops the run")
    t.ok(shows(c, "line", "Sold 3 items, then stopped: you are in combat. Changed your mind? Buy them back on the merchant's Buyback tab."),
        "what was sold, why it stopped, and the buyback note")
    c.setCombat(false)
    c.advance(1, 10)
    t.eq(sold(c), 1, "it does not start again by itself")
    t.eq(newProblems(addon), 0)
end

tests["sell these: a merchant closing stops the run, and a new visit does not start it"] = function(t)
    local c, addon = boot()
    c.setMerchantOpen(true)
    c.kitClick("SellList", "sellThese")
    t.eq(sold(c), 1)
    c.setMerchantOpen(false)
    c.advance(1, 10)
    t.eq(sold(c), 1, "nothing after the close")
    c.setMerchantOpen(true)
    c.advance(1, 10)
    t.eq(sold(c), 1, "nothing at the next open")
    t.eq(newProblems(addon), 0)
end

tests["sell these: a slot that changed after the click is skipped"] = function(t)
    local c, addon = boot({
        { bag = 0, slot = 1, item = FANG, count = 3 },
        { bag = 0, slot = 4, item = FANG, count = 2 },
    })
    c.setMerchantOpen(true)
    c.kitClick("SellList", "sellThese")
    t.eq(sold(c), 1)
    -- The player put cloth where the second stack of fangs was.
    c.setBagItems({ { bag = 0, slot = 4, item = CLOTH, count = 2 } })
    c.advance(1, 10)
    t.eq(sold(c), 1, "the changed slot is not sold")
    t.ok(shows(c, "line", "Sold 3 items; 1 stack skipped, as its bag slot changed. Changed your mind? Buy them back on the merchant's Buyback tab."),
        "the skip is said")
    t.eq(newProblems(addon), 0)
end

tests["sell these: an empty list says why on the button, and it cannot be pressed"] = function(t)
    local c, addon = boot({ { bag = 0, slot = 1, item = STONE, count = 1 } })
    c.setMerchantOpen(true)
    local button = part(c, "sellThese")
    t.ok(button ~= nil, "the button is there")
    if button == nil then return end
    t.eq(button.text, "Nothing to sell", "it says why")
    t.eq(c.kitClick("SellList", "sellThese"), false, "it cannot be pressed")
    t.eq(sold(c), 0)
    t.eq(newProblems(addon), 0)
end

return tests
