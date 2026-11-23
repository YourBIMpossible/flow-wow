local _, ns = ...
-- The sell list and the bank list on the shared window kit, end to end, on
-- the whole add-on loaded on a fake client (lead sections 287, 291 item 3,
-- 294 item 3 and 303): at a default profile the merchant window has its
-- button, a merchant opening draws a kit window of item lines, and the bank
-- does the same. Every read the lists need is set in each fixture (the bag
-- stacks, each item's facts and icon, the merchant window). Look only:
-- nothing here sells or moves anything. Made-up icons. Not tested in game.
--
-- Fails before the change: c.kitWindows().SellList is nil at the first
-- check of every test ("a kit window", got false), and the merchant button
-- is not made at a default profile (#c.windowButtons is 0, wanted 1).
local tests = {}

local FANG, STONE, CLOTH = 97, 6948, 2589
local INFO = {
    [FANG] = { name = "Broken Fang", quality = 0, sellPrice = 4 },
    [STONE] = { name = "Hearthstone", quality = 1, sellPrice = 0 },
    [CLOTH] = { name = "Linen Cloth", quality = 1, sellPrice = 13, classID = 7 },
}
local FANG_ICON = "Interface\\Icons\\INV_Misc_Bone_08"

local atBoot = setmetatable({}, { __mode = "k" })
local function newProblems(addon) return addon.problems:count() - atBoot[addon] end

-- opts: account (the saved account table: a reload), info (false: the item
-- read gives nothing yet), bag.
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, {})
    c.setBagItems(opts.bag or { { item = FANG, count = 3 }, { item = STONE, count = 1 }, { item = CLOTH, count = 20 } })
    if opts.info ~= false then c.setItemInfo(INFO) end
    c.setItemTexture(FANG, FANG_ICON)
    c.setWindow("MerchantFrame", { shown = true })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    atBoot[addon] = addon.problems:count()
    return c, addon
end

local function shows(rec, kind, text)
    for _, p in ipairs(type(rec) == "table" and rec.parts or {}) do
        if p.kind == kind and p.text == text then return true end
    end
    return false
end

local function count(rec, kind)
    local n = 0
    for _, p in ipairs(type(rec) == "table" and rec.parts or {}) do
        if p.kind == kind then n = n + 1 end
    end
    return n
end

local function textPanel(c, name)
    for _, p in ipairs(c.panels) do
        if type(p.spec) == "table" and p.spec.name == ns.id.framePrefix .. name then return p end
    end
    return nil
end

local function merchantButton(c)
    for _, h in ipairs(c.windowButtons) do
        if h.frame == "MerchantFrame" then return h end
    end
    return nil
end

tests["sell and bank look: at a default profile a merchant draws the kit sell list, and the button is there"] = function(t)
    local c, addon = boot()
    local win = c.kitWindows().SellList
    t.ok(type(win) == "table", "a kit window")
    if type(win) ~= "table" then return end
    t.eq(win.shown, false, "hidden until a merchant opens")
    local button = merchantButton(c)
    t.eq(#c.windowButtons, 1, "one window button at a default profile: the merchant's")
    t.ok(button ~= nil and button.shown == true, "shown on the merchant window")
    t.eq(addon.settings:get("buttons.merchant"), true, "on by default")
    c.setMerchantOpen(true)
    win = c.kitWindows().SellList
    t.eq(win.shown, true, "the sell list, by itself")
    t.ok(shows(win, "header", "1 item to sell"), "the header")
    t.ok(shows(win, "itemLine", "Broken Fang"), "the junk as an item line")
    t.ok(shows(win, "itemLine", "Hearthstone"), "what is kept")
    t.eq(count(win, "button"), 1, "one thing to press: the Sell these button (lead section 337 item 1)")
    t.eq(textPanel(c, "SellList"), nil, "no bare text panel")
    local h = addon.sellList.window()
    t.eq(h.slot("sellAction"), { slot = "sellAction" }, "the slot for the sell button is there, and empty")
    c.kitClose("SellList")
    t.eq(c.kitWindows().SellList.shown, false, "the player closed it")
    if button then button.click() end
    t.eq(c.kitWindows().SellList.shown, true, "the merchant window's button brings it back")
    c.setMerchantOpen(false)
    t.eq(c.kitWindows().SellList.shown, false, "the merchant closing hides it")
    t.eq(newProblems(addon), 0, "no problem listed")
end

tests["sell and bank look: nothing to sell says so, and names the add-on from the identity"] = function(t)
    local c, addon = boot({ bag = { { item = STONE, count = 1 } } })
    if type(c.kitWindows().SellList) ~= "table" then t.ok(false, "a kit window") return end
    c.setMerchantOpen(true)
    local win = c.kitWindows().SellList
    t.eq(win.shown, true)
    t.ok(shows(win, "empty", "Nothing to sell."), "the empty state")
    t.ok(shows(win, "itemLine", "Hearthstone"), "what is kept still shows")
    local tree = ns.Kit.Window(addon.SellList.Tree(c, addon.store, nil, { status = addon.Reservations.NONE }))
    local how
    ns.Kit.Each(tree, function(p) if p.kind == "empty" then how = p.how end end)
    t.eq(how, "Bags hold nothing " .. ns.id.title .. " would sell.")
    t.eq(newProblems(addon), 0)
end

tests["sell and bank look: item facts late - not read yet, then the line once they are read"] = function(t)
    local c, addon = boot({ info = false })
    if type(c.kitWindows().SellList) ~= "table" then t.ok(false, "a kit window") return end
    c.setMerchantOpen(true)
    t.eq(count(c.kitWindows().SellList, "itemLine"), 0, "nothing is claimed of an item not read")
    t.ok(not shows(c.kitWindows().SellList, "empty", "Nothing to sell."), "not read is not nothing to sell")
    t.ok(shows(c.kitWindows().SellList, "empty", "Items not read yet."), "the empty state meanwhile")
    local tree = ns.Kit.Window(addon.SellList.Tree(c, addon.store, nil, { status = addon.Reservations.NONE }))
    local how
    ns.Kit.Each(tree, function(p) if p.kind == "empty" then how = p.how end end)
    t.eq(how, "3 items were not read yet. Reopen the merchant window to list them.", "the count, and how to get it")
    c.setItemInfo(INFO)
    c.fire(addon.SellList.BAG_EVENT)
    c.advance(1, 4)
    t.ok(shows(c.kitWindows().SellList, "itemLine", "Broken Fang"), "the line once the item is read")
    t.eq(newProblems(addon), 0)
end

tests["sell and bank look: the icon read raising leaves the line without its icon, then recovers"] = function(t)
    local c, addon = boot()
    if type(c.kitWindows().SellList) ~= "table" then t.ok(false, "a kit window") return end
    local function icon()
        local tree = ns.Kit.Window(addon.SellList.Tree(c, addon.store, nil, { status = addon.Reservations.NONE }))
        local got = false
        ns.Kit.Each(tree, function(p) if p.kind == "itemLine" and p.name == "Broken Fang" then got = p.icon end end)
        return got
    end
    c.setReadFails("itemTexture", true)
    c.setMerchantOpen(true)
    t.ok(shows(c.kitWindows().SellList, "itemLine", "Broken Fang"), "the line is still drawn")
    t.eq(icon(), nil, "with no icon while the read raises")
    c.setReadFails("itemTexture", false)
    c.fire(addon.SellList.BAG_EVENT)
    t.eq(icon(), FANG_ICON, "the icon once the read works")
    t.eq(newProblems(addon), 0, "no problem listed")
end

tests["sell and bank look: after a reload the window is where it was left, and a button turned off stays off"] = function(t)
    local c, addon = boot()
    if type(c.kitWindows().SellList) ~= "table" then t.ok(false, "a kit window") return end
    t.eq(c.kitDrag("SellList", { "CENTER", "CENTER", 12, -34 }, 460, 420), true)
    t.eq(addon.settings:set("buttons.merchant", false), true)
    t.eq(merchantButton(c).shown, false, "turned off: hidden at once")
    local account = c.saved(ns.id.accountDB)
    local c2, addon2 = boot({ account = account })
    local win = c2.kitWindows().SellList
    t.eq(win.point, { "CENTER", "CENTER", 12, -34 }, "where the player left it")
    t.eq({ win.width, win.height }, { 460, 420 })
    t.eq(#c2.windowButtons, 0, "a saved off still means off: no button is made")
    t.eq(addon2.settings:get("buttons.merchant"), false)
    c2.setMerchantOpen(true)
    t.eq(c2.kitWindows().SellList.shown, true, "the list itself still shows")
    t.eq(newProblems(addon2), 0)
end

tests["sell and bank look: the bank window draws the kit bank list"] = function(t)
    local c, addon = boot()
    local win = c.kitWindows().BankList
    t.ok(type(win) == "table", "a kit window")
    if type(win) ~= "table" then return end
    t.eq(win.shown, false)
    t.ok(shows(win, "empty", "No bank data yet."), "before the first visit")
    c.setBankOpen(true)
    win = c.kitWindows().BankList
    t.eq(win.shown, true)
    t.ok(shows(win, "itemLine", "Linen Cloth"), "the cloth to bank, as an item line")
    t.eq(count(win, "button"), 0, "nothing to press")
    t.eq(textPanel(c, "BankList"), nil, "no bare text panel")
    c.setBankOpen(false)
    t.eq(c.kitWindows().BankList.shown, false)
    t.eq(newProblems(addon), 0)
end

return tests
