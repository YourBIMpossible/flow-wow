local _, ns = ...

-- Tests for ZFlow/Gear/MerchantButtons.lua (S20): upgrade marks on the
-- merchant's own item buttons. Fake client (setItem, setWorn, setMerchant,
-- setMerchantOpen, merchantRedraw, merchantMarked) and a real kernel.

local B = ns.GearMerchantButtons
local tests = {}

local STA = "ITEM_MOD_STAMINA_SHORT"
local HELM, BETTER, WORSE = "item:1", "item:2", "item:3"

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
    c.setWorn(1, HELM)
    c.setMerchant(rows or {})
    local k = ns.Kernel({}, c)
    local api = B.Declare(k, packs())
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api
end

tests["merchant buttons: the item numbers of the marks"] = function(t)
    t.eq(B.Indexes({ { index = 2 }, { index = 5 }, {}, "x" }), { [2] = true, [5] = true })
    t.eq(B.Indexes(nil), {})
end

tests["merchant buttons: opening a merchant marks its upgrades, closing takes them away"] = function(t)
    local k, c, api = start({ row(WORSE), row(BETTER) })
    t.eq(k:ModuleState(B.NAME), "started")
    c.setMerchantOpen(true)
    t.eq(c.merchantMarked(), { [2] = true })
    t.eq(api.marked(), 1)
    c.setMerchantOpen(false)
    t.eq(c.merchantMarked(), nil)
    t.eq(api.marked(), nil)
end

tests["merchant buttons: a new page is marked again"] = function(t)
    local _, c = start({ row(WORSE), row(BETTER) })
    c.setMerchantOpen(true)
    c.setMerchant({ row(BETTER), row(WORSE) })
    c.merchantRedraw()
    t.eq(c.merchantMarked(), { [1] = true })
end

tests["merchant buttons: putting on the upgrade takes its mark away"] = function(t)
    local _, c = start({ row(WORSE), row(BETTER) })
    c.setMerchantOpen(true)
    c.setWorn(1, BETTER)
    c.fire("PLAYER_EQUIPMENT_CHANGED")
    t.eq(c.merchantMarked(), {})
end

tests["merchant buttons: switched off, nothing is marked"] = function(t)
    local k, c, api = start({ row(BETTER) })
    t.eq(k.settings:set(B.SETTING, false), true)
    c.setMerchantOpen(true)
    t.eq(c.merchantMarked(), {})
    t.eq(api.marked(), 0)
end

return tests
