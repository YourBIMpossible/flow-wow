local _, ns = ...

-- The bank list on the shared window kit (lead sections 287, 291 item 3 and
-- 303): a kit window of item lines, not text on a bare frame. Fake client;
-- c.kitWindows() is what was drawn. Look only: nothing here moves an item.
-- Not tested in game.
--
-- Fails before the change: ns.BankList.Tree is nil ("the bank list has a
-- tree", got "nil"), and c.kitWindows().BankList is nil (the text panel is
-- the one shown).

local B = ns.BankList
local K = ns.Kit
local tests = {}

local CLOTH, POTION = 2589, 858
local INFO = {
    [CLOTH] = { name = "Linen Cloth", quality = 1, sellPrice = 13, classID = 7 },
    [POTION] = { name = "Lesser Healing Potion", quality = 1, sellPrice = 20, classID = 0 },
}
local CLOTH_ICON = "Interface\\Icons\\INV_Fabric_Linen_01"
local NONE = { status = ns.Reservations.NONE }

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.saved or {})
    c.setBagItems(opts.bag or { { item = CLOTH, count = 20 }, { item = POTION, count = 5 } })
    c.setItemInfo(INFO)
    c.setItemTexture(CLOTH, CLOTH_ICON)
    if opts.kitFails then c.setKitFails(1) end
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    ns.Reservations.Declare(k)
    local api = B.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api
end

local function drawn(c)
    return c.kitWindows().BankList
end

local function textPanel(c)
    for _, p in ipairs(c.panels) do
        if type(p.spec) == "table" and p.spec.name == ns.id.framePrefix .. "BankList" then return p end
    end
    return nil
end

local function shows(rec, kind, text)
    for _, p in ipairs(type(rec) == "table" and rec.parts or {}) do
        if p.kind == kind and p.text == text then return true end
    end
    return false
end

local function treeOf(t, c, r)
    t.eq(type(B.Tree), "function", "the bank list has a tree")
    if type(B.Tree) ~= "function" then return nil end
    local tree, why = K.Window(B.Tree(c, nil, B.Held(r or NONE), r or NONE))
    t.ok(type(tree) == "table", "the kit takes it: " .. tostring(why))
    return tree
end

local function part(tree, kind, text)
    local found
    K.Each(tree, function(p)
        if found == nil and p.kind == kind and (text == nil or K.TextOf(p) == text) then found = p end
    end)
    return found
end

local function bags(stacks)
    local c = ns.make.fakeClient()
    if stacks then c.setBagItems(stacks) end
    c.setItemInfo(INFO)
    c.setItemTexture(CLOTH, CLOTH_ICON)
    return c
end

tests["bank list kit: the bank window draws a kit window of item lines, and no bare panel"] = function(t)
    local _, c, api = start()
    t.ok(type(drawn(c)) == "table", "a kit window is made at the start")
    if type(drawn(c)) ~= "table" then return end
    t.eq(drawn(c).shown, false, "hidden until the bank opens")
    t.ok(shows(drawn(c), "empty", "No bank data yet."), "before the first visit it says what is missing")
    c.setBankOpen(true)
    local rec = drawn(c)
    t.eq(rec.shown, true)
    t.ok(shows(rec, "itemLine", "Linen Cloth"), "the cloth, as an item line")
    t.ok(not shows(rec, "itemLine", "Lesser Healing Potion"), "the potion stays")
    t.ok(shows(rec, "section", "To bank"), "its section")
    t.eq(textPanel(c), nil, "no text panel when the kit draws")
    t.eq(api.shows(), 1)
    t.ok(type(api.last()) == "table" and #api.last() > 0, "the text lines are still kept")
    c.setBankOpen(false)
    t.eq(drawn(c).shown, false, "hidden when the bank closes")
end

tests["bank list kit: the title is the add-on's own, and a line carries quality, icon, count and why"] = function(t)
    local tree = treeOf(t, bags({ { item = CLOTH, count = 20 } }))
    if not tree then return end
    t.eq(tree.id, "BankList")
    t.eq(tree.title, ns.id.title .. ": Bank list")
    t.eq({ tree.width, tree.height }, { 420, 480 })
    local line = part(tree, "itemLine", "Linen Cloth")
    t.ok(line ~= nil, "a line for the cloth")
    if not line then return end
    t.eq(line.quality, 1)
    t.eq(line.icon, CLOTH_ICON)
    t.eq(line.count, 20)
    t.eq(line.note, "kept for later", "why it goes to the bank")
    t.eq(line.item, CLOTH)
    t.eq(line.money, nil, "no price on the bank list")
    local footer = part(tree, "footer")
    t.eq(footer.text, "1 kind of item to bank")
    t.eq(footer.slot, nil, "no action slot")
    t.eq(#footer.buttons, 0)
    K.Each(tree, function(p) t.ok(p.kind ~= "button" and p.onClick == nil, "nothing to press: " .. p.kind) end)
end

tests["bank list kit: nothing to bank, bags not read and items not read each say what is missing"] = function(t)
    local none = treeOf(t, bags({ { item = POTION, count = 5 } }))
    if not none then return end
    t.eq(part(none, "empty").text, "Nothing to bank.")
    local unread = treeOf(t, bags(nil))
    t.eq(part(unread, "empty").how, ns.ItemPresent.BAGS_UNREAD)
    local c = bags({ { item = CLOTH, count = 20 }, { item = POTION, count = 5 } })
    c.setItemInfo(nil)
    local blind = treeOf(t, c)
    t.eq(part(blind, "empty").text, "Can't tell what to bank.")
    t.eq(part(blind, "empty").how, "2 items were not read yet.")
    t.eq(part(blind, "itemLine"), nil)
end

tests["bank list kit: reservations not known is said on the list"] = function(t)
    local tree = treeOf(t, bags({ { item = CLOTH, count = 20 } }), { status = ns.Reservations.UNAVAILABLE })
    if not tree then return end
    t.ok(part(tree, "line", B.RESERVATIONS_UNKNOWN) ~= nil, "the line that says so")
    t.ok(part(tree, "itemLine", "Linen Cloth") ~= nil, "the list is still made")
end

tests["bank list kit: a client that cannot draw the kit falls back to the text panel"] = function(t)
    local _, c, api = start({ kitFails = true })
    t.eq(drawn(c), nil, "no kit window")
    c.setBankOpen(true)
    local p = textPanel(c)
    t.ok(p ~= nil, "the text panel in its place")
    if not p then return end
    t.eq(p.shown, true)
    t.eq(p.lines, api.last())
end

tests["bank list kit: where the player left it is saved"] = function(t)
    local _, c = start()
    if type(drawn(c)) ~= "table" then t.ok(false, "a kit window") return end
    t.eq(c.kitDrag("BankList", { "CENTER", "CENTER", -30, 40 }, 440, 300), true)
    local saved = c.saved(ns.id.accountDB)
    t.eq(saved.layout and saved.layout.bankList, { point = { "CENTER", "CENTER", -30, 40 }, width = 440, height = 300 })
    local _, c2 = start({ saved = saved })
    t.eq(drawn(c2).point, { "CENTER", "CENTER", -30, 40 })
end

tests["bank list kit: an icon given as a file number is kept on the line"] = function(t)
    local c = bags({ { item = CLOTH, count = 20 } })
    c.setItemTexture(CLOTH, 134400)
    local tree = treeOf(t, c)
    if not tree then return end
    local line = part(tree, "itemLine", "Linen Cloth")
    t.ok(line ~= nil, "the line")
    if not line then return end
    t.eq(line.icon, 134400, "the file number the client gives")
end

tests["bank list kit: closed by the player, it stays closed for that bank visit"] = function(t)
    local k, c = start()
    if type(drawn(c)) ~= "table" then t.ok(false, "a kit window") return end
    c.setBankOpen(true)
    t.eq(drawn(c).shown, true)
    t.eq(c.kitClose("BankList"), true)
    k.bus:emit(ns.Reservations.CHANGED)
    t.eq(drawn(c).shown, false, "a change of the claims does not bring it back")
    c.setBankOpen(false)
    c.setBankOpen(true)
    t.eq(drawn(c).shown, true, "the next bank visit shows it again")
end

return tests
