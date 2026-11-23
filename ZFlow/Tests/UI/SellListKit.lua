local _, ns = ...

-- The sell list on the shared window kit (lead sections 287, 291 item 3,
-- 294 item 3 and 303): the list is a kit window of item lines, not text on a
-- bare frame. Fake client; c.kitWindows() is what was drawn. Look only:
-- nothing here sells. Not tested in game.
--
-- Fails before the change: ns.SellList.Tree is nil (every tree test fails
-- "the sell list has a tree", got "nil"), and no kit window is drawn
-- (c.kitWindows().SellList is nil; the text panel is the one shown).

local L = ns.SellList
local K = ns.Kit
local tests = {}

local FANG, STONE, LEATHER = 97, 6948, 2318
local INFO = {
    [FANG] = { name = "Broken Fang", quality = 0, sellPrice = 4 },
    [STONE] = { name = "Hearthstone", quality = 1, sellPrice = 0 },
    [LEATHER] = { name = "Light Leather", quality = 1, sellPrice = 15, classID = 7 },
}
local FANG_ICON = "Interface\\Icons\\INV_Misc_Bone_08"
local NONE = { status = ns.Reservations.NONE }

-- opts: bag (stacks), kitFails (the kit cannot draw), noReservations,
-- setting (false: vendor.list off).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.saved or {})
    c.setBagItems(opts.bag or { { item = FANG, count = 3 }, { item = STONE, count = 1 } })
    c.setItemInfo(INFO)
    c.setItemTexture(FANG, FANG_ICON)
    if opts.kitFails then c.setKitFails(1) end
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    if opts.setting ~= nil then
        k:Setting({ key = L.SETTING, scope = "char", type = "bool", default = true, label = "Vendor sell list" })
    end
    if not opts.noReservations then ns.Reservations.Declare(k) end
    local api = L.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    if opts.setting == false then k.settings:set(L.SETTING, false) end
    return k, c, api
end

local function drawn(c)
    return c.kitWindows().SellList
end

local function textPanel(c)
    for _, p in ipairs(c.panels) do
        if type(p.spec) == "table" and p.spec.name == ns.id.framePrefix .. "SellList" then return p end
    end
    return nil
end

-- How many parts of that kind the record holds, and the first with that text.
local function count(rec, kind)
    local n = 0
    for _, p in ipairs(type(rec) == "table" and rec.parts or {}) do
        if p.kind == kind then n = n + 1 end
    end
    return n
end

local function shows(rec, kind, text)
    for _, p in ipairs(type(rec) == "table" and rec.parts or {}) do
        if p.kind == kind and p.text == text then return true end
    end
    return false
end

-- The checked tree of one listing, or nil (said once).
local function treeOf(t, c, r, store)
    t.eq(type(L.Tree), "function", "the sell list has a tree")
    if type(L.Tree) ~= "function" then return nil end
    local tree, why = K.Window(L.Tree(c, store, L.Held(r or NONE), r or NONE))
    t.ok(type(tree) == "table", "the kit takes it: " .. tostring(why))
    return tree
end

-- The first part of that kind whose first words are `text`.
local function part(tree, kind, text)
    local found
    K.Each(tree, function(p)
        if found == nil and p.kind == kind and (text == nil or K.TextOf(p) == text) then found = p end
    end)
    return found
end

local function bags(stacks)
    local c = ns.make.fakeClient()
    c.setBagItems(stacks)
    c.setItemInfo(INFO)
    c.setItemTexture(FANG, FANG_ICON)
    return c
end

tests["sell list kit: a merchant window draws a kit window of item lines, and no bare panel"] = function(t)
    local _, c, api = start()
    t.ok(type(drawn(c)) == "table", "a kit window is made at the start")
    if type(drawn(c)) ~= "table" then return end
    t.eq(drawn(c).shown, false, "hidden with no merchant")
    t.eq({ drawn(c).width, drawn(c).height }, { 420, 480 })
    c.setMerchantOpen(true)
    local rec = drawn(c)
    t.eq(rec.shown, true, "shown at the merchant")
    t.eq(count(rec, "itemLine"), 2, "one line to sell, one kept")
    t.ok(shows(rec, "itemLine", "Broken Fang"), "the junk, by its name")
    t.ok(shows(rec, "itemLine", "Hearthstone"), "the kept item")
    t.ok(shows(rec, "header", "1 item to sell"), "the header counts what is to sell")
    t.ok(shows(rec, "section", "To sell") and shows(rec, "section", "Kept, and why"), "both sections")
    t.eq(textPanel(c), nil, "no text panel is made when the kit draws")
    t.eq(api.shows(), 1)
    t.ok(type(api.last()) == "table" and #api.last() > 0, "the text lines are still kept for other code")
end

tests["sell list kit: the window's title is the add-on's own, from the identity"] = function(t)
    local tree = treeOf(t, bags({ { item = FANG, count = 3 } }))
    if not tree then return end
    t.eq(tree.id, "SellList")
    t.eq(tree.title, ns.id.title .. ": Sell list")
    t.eq({ tree.width, tree.height }, { 420, 480 })
end

tests["sell list kit: an item line carries the quality, the icon, the count and the item"] = function(t)
    local tree = treeOf(t, bags({ { item = FANG, count = 3 } }))
    if not tree then return end
    local line = part(tree, "itemLine", "Broken Fang")
    t.ok(line ~= nil, "a line for the fang")
    if not line then return end
    t.eq(line.quality, 0, "the quality the colour comes from")
    t.eq(line.color.hex, K.Quality(0).hex, "poor grey")
    t.eq(line.icon, FANG_ICON, "its icon")
    t.eq(line.count, 3)
    t.eq(line.item, FANG, "the item, for the tooltip")
end

tests["sell list kit: an observed price shows as money, an estimate as a labelled note"] = function(t)
    local tree = treeOf(t, bags({ { item = FANG, count = 3 } }))
    if not tree then return end
    local line = part(tree, "itemLine", "Broken Fang")
    t.eq(line and line.money, 12, "3 x 4c, in whole copper")
    t.eq(line and line.note, nil, "money, so no note")
    -- An estimate, through the pure half: one listing as Items/Sell.lua makes it.
    t.eq(type(L.TreeOf), "function", "the tree of a listing")
    if type(L.TreeOf) ~= "function" then return end
    local P = ns.Prices
    local listing = {
        list = { ok = true, unread = 0, unsellable = 0,
            total = { known = 0, estimated = 60, unknown = 1 },
            rows = {
                { key = 3000, name = "Grey Mystery", count = 2, unit = 30, total = 60,
                  basis = P.ESTIMATED, source = "price list" },
                { key = 3001, name = "Odd Thing", count = 1, basis = P.UNKNOWN },
            } },
        kept = { ok = true, rows = {} },
    }
    local est, why = K.Window(L.TreeOf(listing))
    t.ok(type(est) == "table", "the kit takes it: " .. tostring(why))
    if not est then return end
    local guess = part(est, "itemLine", "Grey Mystery")
    t.eq(guess.money, nil, "an estimate is never shown as money")
    t.ok(type(guess.note) == "string" and guess.note:find("estimate", 1, true) ~= nil, "labelled: " .. tostring(guess.note))
    local odd = part(est, "itemLine", "Odd Thing")
    t.eq(odd.money, nil)
    t.eq(odd.note, ns.ItemPresent.VENDOR_PRICE_UNKNOWN, "an unknown price says so, with no figure")
    local foot = part(est, "footer")
    t.eq(foot.money, nil, "no price seen: no money in the footer, not 0")
    t.eq(foot.text, "Prices not known", "it says the prices are not known")
end

tests["sell list kit: the footer total says it covers only the prices seen"] = function(t)
    local P = ns.Prices
    local listing = {
        list = { ok = true, unread = 0, unsellable = 0,
            total = { known = 40, estimated = 60, unknown = 0 },
            rows = {
                { key = 3002, name = "Seen Thing", count = 2, unit = 20, total = 40, basis = P.OBSERVED },
                { key = 3000, name = "Grey Mystery", count = 2, unit = 30, total = 60,
                  basis = P.ESTIMATED, source = "price list" },
            } },
        kept = { ok = true, rows = {} },
    }
    local tree = K.Window(L.TreeOf(listing))
    if not tree then t.ok(false, "the kit takes it") return end
    local foot = part(tree, "footer")
    t.eq(foot.money, 40, "only the seen price")
    t.eq(foot.text, "Total of the prices seen", "it says what the total covers")
end

tests["sell list kit: an icon given as a file number is kept on the line"] = function(t)
    local c = bags({ { item = FANG, count = 3 } })
    c.setItemTexture(FANG, 134400)
    local tree = treeOf(t, c)
    if not tree then return end
    local line = part(tree, "itemLine", "Broken Fang")
    t.ok(line ~= nil, "the line")
    if not line then return end
    t.eq(line.icon, 134400, "the file number the client gives")
end

tests["sell list kit: the kept section says why"] = function(t)
    local tree = treeOf(t, bags({ { item = FANG, count = 3 }, { item = STONE, count = 1 } }))
    if not tree then return end
    t.ok(part(tree, "section", "Kept, and why") ~= nil, "the section")
    local kept = part(tree, "itemLine", "Hearthstone")
    t.ok(kept ~= nil, "the kept item")
    if not kept then return end
    t.eq(kept.note, "can't be sold to a merchant", "its reason")
    t.eq(kept.tone, "good")
    t.eq(kept.money, nil, "no price on what is kept")
end

tests["sell list kit: nothing to sell names what is missing, and the kept items still show"] = function(t)
    local tree = treeOf(t, bags({ { item = STONE, count = 1 } }))
    if not tree then return end
    local empty = part(tree, "empty")
    t.ok(empty ~= nil, "an empty-state line")
    if not empty then return end
    t.eq(empty.text, "Nothing to sell.")
    t.eq(empty.how, "Bags hold nothing " .. ns.id.title .. " would sell.")
    t.ok(part(tree, "itemLine", "Hearthstone") ~= nil, "what is kept still shows")
    t.eq(part(tree, "section", "To sell"), nil, "no empty section")
    t.eq(part(tree, "footer").money, 0)
end

tests["sell list kit: reservations not known offers nothing, says so, and still shows what is kept"] = function(t)
    local tree = treeOf(t, bags({ { item = FANG, count = 3 }, { item = STONE, count = 1 } }),
        { status = ns.Reservations.UNAVAILABLE })
    if not tree then return end
    local empty = part(tree, "empty")
    t.ok(empty ~= nil, "an empty-state line")
    if not empty then return end
    t.eq(empty.text, "Reservations not known.")
    t.ok(empty.how:find("Nothing is offered for sale", 1, true) == 1, empty.how)
    t.eq(part(tree, "itemLine", "Broken Fang"), nil, "nothing offered")
    t.ok(part(tree, "itemLine", "Hearthstone") ~= nil, "what is kept still shows")
    t.eq(part(tree, "footer").money, nil, "no total is claimed")
end

tests["sell list kit: the footer total is the observed sum, with the empty slot for the sell button"] = function(t)
    local _, c, api = start({ bag = { { item = FANG, count = 3 }, { item = LEATHER, count = 2 }, { item = STONE, count = 1 } } })
    c.setMerchantOpen(true)
    local tree = treeOf(t, c)
    if not tree then return end
    local sum = 0
    K.Each(tree, function(p)
        if p.kind == "itemLine" and p.money ~= nil then sum = sum + p.money end
    end)
    local footer = part(tree, "footer")
    t.eq(footer.text, "Total")
    t.eq(footer.money, sum, "the footer is the sum of the money shown")
    t.ok(sum >= 12, "the fang's 12c is in it: " .. sum)
    t.eq(footer.slot, "sellAction")
    t.eq(#footer.buttons, 0, "no button of this lane's")
    K.Each(tree, function(p)
        t.ok(p.kind ~= "button" and p.onClick == nil, "nothing to press: " .. p.kind .. " " .. p.path)
    end)
    t.eq(count(drawn(c), "button"), 1, "one button drawn: Sell these (lead section 337 item 1)")
    t.eq(type(api.window), "function", "the window is reachable for the lane that owns the button")
    if type(api.window) ~= "function" then return end
    local h = api.window()
    t.ok(type(h) == "table" and type(h.slot("sellAction")) == "table", "the slot is there")
    t.eq(h.slot("sellAction"), { slot = "sellAction" }, "and empty")
end

tests["sell list kit: unread bag slots and unsellable items still reach the player"] = function(t)
    t.eq(type(L.TreeOf), "function", "the tree of a listing")
    if type(L.TreeOf) ~= "function" then return end
    local tree, why = K.Window(L.TreeOf({
        list = { ok = true, unread = 2, unsellable = 1, rows = {}, total = { known = 0, estimated = 0, unknown = 0 } },
        kept = { ok = true, rows = {} },
    }))
    t.ok(type(tree) == "table", tostring(why))
    if not tree then return end
    t.ok(part(tree, "line", "2 bag slots could not be read") ~= nil, "the unread slots")
    t.ok(part(tree, "line", "1 item to sell can't be sold to a merchant") ~= nil, "the unsellable item")
end

tests["sell list kit: bags not read say so, with no figure"] = function(t)
    local tree = treeOf(t, ns.make.fakeClient())
    if not tree then return end
    local empty = part(tree, "empty")
    t.ok(empty ~= nil and empty.how == ns.ItemSell.BAGS_UNREAD, "why it cannot be listed")
    t.eq(part(tree, "footer").money, nil)
    t.eq(part(tree, "itemLine"), nil)
end

tests["sell list kit: the merchant closing hides it; the player's own close holds for the visit"] = function(t)
    local k, c = start()
    c.setMerchantOpen(true)
    if type(drawn(c)) ~= "table" then t.ok(false, "a kit window") return end
    c.setMerchantOpen(false)
    t.eq(drawn(c).shown, false, "hidden when the merchant closes")
    c.setMerchantOpen(true)
    t.eq(drawn(c).shown, true)
    t.eq(c.kitClose("SellList"), true, "the player closes it")
    c.fire(L.BAG_EVENT)
    t.eq(drawn(c).shown, false, "a bag change does not bring it back in this visit")
    t.eq(k.use(L.NAME).Show(), true, "asking for it does")
    t.eq(drawn(c).shown, true)
    c.setMerchantOpen(false)
    c.setMerchantOpen(true)
    t.eq(drawn(c).shown, true, "and a new visit shows it again")
end

tests["sell list kit: where the player left it is saved and used at the next login"] = function(t)
    local _, c = start()
    if type(drawn(c)) ~= "table" then t.ok(false, "a kit window") return end
    t.eq(drawn(c).point, L.DEFAULT_POINT, "its own place at first")
    t.eq(c.kitDrag("SellList", { "CENTER", "CENTER", 10, 20 }, 500, 400), true)
    local saved = c.saved(ns.id.accountDB)
    t.eq(saved.layout and saved.layout.sellList, { point = { "CENTER", "CENTER", 10, 20 }, width = 500, height = 400 })
    local _, c2 = start({ saved = saved })
    t.eq(drawn(c2).point, { "CENTER", "CENTER", 10, 20 })
    t.eq({ drawn(c2).width, drawn(c2).height }, { 500, 400 })
end

tests["sell list kit: a client that cannot draw the kit falls back to the text panel"] = function(t)
    local k, c, api = start({ kitFails = true })
    t.eq((k:ModuleState(L.NAME)), "started")
    t.eq(drawn(c), nil, "no kit window")
    c.setMerchantOpen(true)
    local p = textPanel(c)
    t.ok(p ~= nil, "the text panel is made in its place")
    if not p then return end
    t.eq(p.shown, true, "and shown")
    t.eq(p.lines, api.last(), "with the list as text")
    c.setMerchantOpen(false)
    t.eq(p.shown, false)
end

tests["sell list kit: vendor.list off draws nothing; the window button still shows it"] = function(t)
    local k, c = start({ setting = false })
    c.setMerchantOpen(true)
    if type(drawn(c)) ~= "table" then t.ok(false, "a kit window") return end
    t.eq(drawn(c).shown, false, "off: not shown by itself")
    t.eq(count(drawn(c), "itemLine"), 0, "and nothing was listed")
    t.eq(k.use(L.NAME).Show(), true)
    t.eq(drawn(c).shown, true, "asked for: shown")
    t.eq(count(drawn(c), "itemLine"), 2, "the fang to sell and the kept stone")
end

return tests
