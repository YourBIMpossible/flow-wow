local _, ns = ...
-- The button on the bank window, end to end, on the whole add-on loaded on
-- a fake client (owner, 2026-11-23: the button on the bank said only the
-- add-on's name, so it did not say what it was for). The entry is the
-- player's: the bank window opening (BANKFRAME_OPENED), then a click on the
-- button. What is held here: the button says "Bank list", its tooltip says
-- "Bank list: what to store and take out", and a click brings the bank
-- list back after the player closed it, and with the list turned off.
-- Look only: nothing here deposits, withdraws or moves anything. Made-up
-- items. Not tested in game.
local tests = {}

local FANG, CLOTH = 3310, 3311
local INFO = {
    [FANG] = { name = "Chipped Fang", quality = 0, sellPrice = 4 },
    [CLOTH] = { name = "Worn Cloth", quality = 1, sellPrice = 13, classID = 7 },
}

local function boot()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setBagItems({ { item = FANG, count = 3 }, { item = CLOTH, count = 20 } })
    c.setItemInfo(INFO)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon, addon.problems:count()
end

local function button(c)
    for _, h in ipairs(c.windowButtons or {}) do
        if h.frame == "BankFrame" then return h end
    end
    return nil
end

local function atBank(c)
    c.setWindow("BankFrame", { shown = true })
    c.setBankOpen(true)
end

local function listShown(c)
    local w = c.kitWindows().BankList
    return type(w) == "table" and w.shown == true
end

tests["bank button: at the bank it says Bank list, and what that is"] = function(t)
    local c, addon, before = boot()
    t.eq(button(c), nil, "no bank window, no button")
    atBank(c)
    local h = button(c)
    t.ok(h ~= nil, "a button on the bank window")
    if not h then return end
    t.eq(h.spec.text, "Bank list")
    t.eq(h.spec.tip, "Bank list: what to store and take out")
    t.eq(h.spec.text:find(ns.id.title, 1, true), nil, "not only the add-on's name")
    t.eq(addon.problems:count(), before)
end

tests["bank button: a click brings back the list the player closed"] = function(t)
    local c, addon, before = boot()
    if type(c.kitWindows().BankList) ~= "table" then t.ok(false, "a kit window") return end
    atBank(c)
    t.eq(listShown(c), true, "the list opens with the bank")
    c.kitClose("BankList")
    t.eq(listShown(c), false, "closed by the player")
    local h = button(c)
    if not h then t.ok(false, "a button") return end
    h.click()
    t.eq(listShown(c), true, "the button shows it again")
    t.eq(addon.problems:count(), before)
end

tests["bank button: a click shows the list with the list turned off, until the bank closes"] = function(t)
    local c, addon, before = boot()
    if type(c.kitWindows().BankList) ~= "table" then t.ok(false, "a kit window") return end
    addon.settings:set(addon.BankList.SETTING, false)
    atBank(c)
    t.eq(listShown(c), false, "off: the bank opening shows nothing")
    local h = button(c)
    if not h then t.ok(false, "a button") return end
    h.click()
    t.eq(listShown(c), true, "asked for: shown")
    c.setBankOpen(false)
    t.eq(listShown(c), false, "the bank closing hides it")
    c.setBankOpen(true)
    t.eq(listShown(c), false, "and the next visit is off again")
    t.eq(addon.problems:count(), before)
end

tests["bank button: away from the bank the list says why it does not show"] = function(t)
    local c, addon, before = boot()
    local ok, why = addon.bankList.show()
    t.eq(ok, false)
    t.eq(why, addon.BankList.NO_BANK)
    t.eq(listShown(c), false)
    t.eq(addon.problems:count(), before)
end

return tests
