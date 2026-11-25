local _, ns = ...
-- E-13 (lead section 660), end to end on the whole add-on loaded on a fake
-- client: the player buys an item back at a merchant, so Z-Flow puts it on
-- the never-sell list and the sell list no longer offers it. The buy-back
-- read is client.onBoughtBack (CLIENT NEED, stubbed in the fake). Flow
-- research: Modules/Items/Vendor.lua:718-720 (BuybackItem hook, then
-- sell.never). Made-up items. Not tested in game.
--
-- Fails before the change: the fake has no c.fireBoughtBack, and nothing marks a
-- bought-back item keep.
local tests = {}

local FANG = 97
local INFO = { [FANG] = { name = "Broken Fang", quality = 0, sellPrice = 4 } }

local function boot()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setBagItems({ { bag = 0, slot = 1, item = FANG, count = 3 } })
    c.setItemInfo(INFO)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function never(c)
    local saved = c.saved(ns.id.charDB)
    local s = type(saved) == "table" and saved.settings or nil
    local sell = type(s) == "table" and s.sell or nil
    return type(sell) == "table" and type(sell.never) == "table" and sell.never or {}
end

local function said(c, part)
    for _, p in ipairs(c.printed) do
        if ns.ItemPresent.Plain(p):find(part, 1, true) then return true end
    end
    return false
end

tests["keep buy-back: an item bought back at the merchant is never sold again"] = function(t)
    local c = boot()
    c.setMerchantOpen(true)
    t.eq(type(c.fireBoughtBack), "function", "the fake has the buy-back")
    if type(c.fireBoughtBack) ~= "function" then return end
    c.fireBoughtBack("item:" .. FANG)
    c.advance(0.1, 2)
    t.eq(never(c)[FANG], true, "on the character's never-sell list")
    t.ok(said(c, "Broken Fang bought back, so it is now on your never-sell list."), "the player is told")
    c.slashes[ns.id.slash]("keep")
    t.ok(said(c, "Never sold (1):"), "the keep word lists it")
end

tests["keep buy-back: buying it back twice tells the player once"] = function(t)
    local c = boot()
    c.setMerchantOpen(true)
    if type(c.fireBoughtBack) ~= "function" then t.ok(false, "no c.fireBoughtBack") return end
    c.fireBoughtBack("item:" .. FANG)
    local n = #c.printed
    c.fireBoughtBack("item:" .. FANG)
    t.eq(#c.printed, n, "nothing more said")
end

return tests
