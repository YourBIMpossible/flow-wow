local _, ns = ...

-- Tests for ZFlow/Gear/MerchantShow.lua (F4): the merchant upgrade marks as
-- advisor prompts, shown while a merchant window is open. Through the fake
-- client (setItem with what the game marks, setWorn, setMerchant,
-- setMerchantOpen) and a real kernel with the advisor.

local M = ns.GearMerchantShow
local A = ns.Advisor
local tests = {}

local STA = "ITEM_MOD_STAMINA_SHORT"
local HELM, BETTER, WORSE, POTION = "item:1", "item:2", "item:3", "item:5"

local function packs()
    return { DRUID = {
        weights = { dps = { evidence = "first guess", values = { [STA] = 1 } } },
        proficiency = { evidence = "first guess", [4] = { [2] = true } },
    } }
end

local function row(link) return { item = link, price = 100, stack = 1 } end

local function start(rows)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setClass("DRUID")
    c.setItem(HELM, { kind = "INVTYPE_HEAD", stats = { [STA] = 4 }, unmet = {} })
    c.setItem(BETTER, { kind = "INVTYPE_HEAD", stats = { [STA] = 9 }, unmet = {} })
    c.setItem(WORSE, { kind = "INVTYPE_HEAD", stats = { [STA] = 1 }, unmet = {} })
    c.setItem(POTION, { stats = {} })
    c.setWorn(1, HELM)
    c.setMerchant(rows or {})
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    local advisor = A.Declare(k)
    local api = M.Declare(k, packs())
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, advisor, api
end

local function texts(advisor)
    local out = {}
    for i, p in ipairs(advisor.List()) do out[i] = p.text end
    return out
end

tests["merchant show: opening a merchant with an upgrade on sale shows it"] = function(t)
    local k, c, advisor, api = start({ row(WORSE), row(BETTER) })
    t.eq(k:ModuleState(M.NAME), "started")
    c.setMerchantOpen(true)
    t.eq(texts(advisor), { "1 upgrade on sale here", BETTER .. ": Upgrade for your head piece (+5, dps); 1s" })
    t.eq(api.shown(), { M.ID .. 1, M.ID .. 2 })
end

tests["merchant show: closing the merchant takes the prompts away"] = function(t)
    local _, c, advisor, api = start({ row(BETTER) })
    c.setMerchantOpen(true)
    t.eq(#advisor.List(), 2)
    c.setMerchantOpen(false)
    t.eq(advisor.List(), {})
    t.eq(api.shown(), {})
end

tests["merchant show: no upgrade among the gear on sale says so"] = function(t)
    local _, c, advisor = start({ row(WORSE), row(POTION) })
    c.setMerchantOpen(true)
    t.eq(texts(advisor), { "No upgrades on sale here" })
end

tests["merchant show: no gear on sale shows nothing"] = function(t)
    local _, c, advisor = start({ row(POTION) })
    c.setMerchantOpen(true)
    t.eq(advisor.List(), {})
end

tests["merchant show: a second merchant replaces the first one's prompts"] = function(t)
    local _, c, advisor = start({ row(BETTER) })
    c.setMerchantOpen(true)
    c.setMerchantOpen(false)
    c.setMerchant({ row(WORSE) })
    c.setMerchantOpen(true)
    t.eq(texts(advisor), { "No upgrades on sale here" })
end

tests["merchant show: the setting is on by default; off works nothing out"] = function(t)
    local k, c, advisor = start({ row(BETTER) })
    t.eq(k.settings:get(M.SETTING), true)
    t.eq(k.settings:set(M.SETTING, false), true)
    c.setMerchantOpen(true)
    t.eq(advisor.List(), {})
end

tests["merchant show: an error while working it out shows nothing and is one problem"] = function(t)
    local k, c, advisor, api = start({ row(BETTER) })
    c.gear = function() error("the read broke") end
    c.setMerchantOpen(true)
    t.eq(advisor.List(), {})
    t.eq(api.errors(), 1)
    t.eq(k.problems:count("gear"), 1)
    t.eq(k:ModuleState(M.NAME), "started")
end

tests["merchant show: an upgrade dearer than your money says so; money not read, no claim"] = function(t)
    local _, c, advisor = start({ row(BETTER) })
    c.setMoney(50)
    c.setMerchantOpen(true)
    t.eq(texts(advisor)[2], BETTER .. ": Upgrade for your head piece (+5, dps); 1s, more than you have")
    c.setMerchantOpen(false)
    c.setMoney(nil)
    c.setMerchantOpen(true)
    t.eq(texts(advisor)[2], BETTER .. ": Upgrade for your head piece (+5, dps); 1s")
    c.setMerchantOpen(false)
    c.setMoney(50)
    c.setMoneyFails(true)
    c.setMerchantOpen(true)
    t.eq(texts(advisor)[2], BETTER .. ": Upgrade for your head piece (+5, dps); 1s", "a raising read: no claim")
    t.eq(#advisor.List(), 2)
end

tests["merchant show: it only reads; nothing is bought"] = function(t)
    local _, c = start({ row(BETTER) })
    local calls = 0
    for _, name in ipairs({ "BuyMerchantItem", "PickupMerchantItem", "BuybackItem", "EquipItemByName" }) do
        c[name] = function() calls = calls + 1 end
    end
    c.setMerchantOpen(true)
    t.eq(calls, 0)
end

return tests
