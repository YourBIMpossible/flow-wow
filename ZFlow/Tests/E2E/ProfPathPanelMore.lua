local _, ns = ...
-- P-PATH-2, the lead's ruling on the second panel (option b): the tests
-- the accepted panel did not have, and the arrow menu's row. The whole
-- add-on on a fake client, with a stand-in for Items/ProfPath.lua (the
-- section 450 plan shape).
--   Its place and fold are saved and come back in a new session.
--   A list update never moves it.
--   The setting off: the profession window opens nothing; chat still does.
--   The minimap menu's row and the arrow menu's Flow windows row open it.
--   A bank never seen says so on the material's own line, never 0.
-- Look only: nothing is crafted, bought or trained. Offline test, fake
-- client lines. Not tested in game.
--
-- Red before the code: the arrow menu has no profession path row and the
-- module gives no Close.
local tests = {}

local PPP = ns.ProfPathPanel
local ID = "ProfPathPanel"

local PLAN = {
    id = "Blacksmithing", rev = 1, prof = "Blacksmithing", skill = 50, max = 75, status = "ok", selected = 1,
    ranges = {
        { from = 50, to = 60, recipe = "Test Buckle", crafts = 10, sure = true },
        { from = 60, to = 75, recipe = "Test Nail", crafts = 18, sure = false },
    },
    materials = {
        { name = "Test Bar", need = 20, net = 4 },
        { name = "Test Flux", need = 6, net = "unknown", bankSeen = false },
    },
}

-- opts.char: the character's saved table.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setScreen(1024, 768)
    c.setMinimap({ size = 140 })
    c.setRecipes({ profession = 164, name = "Blacksmithing", skill = 50, max = 75, recipes = {} })
    local addon = ns.offline.addon(c)
    addon.ProfPath = { Path = function() return PLAN end }
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    return c, addon
end

local function window(c) return c.kitWindows()[ID] end
local function shown(c)
    local w = window(c)
    return w ~= nil and w.shown == true
end
local function part(c, key)
    local w = window(c)
    for _, p in ipairs(w and w.parts or {}) do
        if p.key == key then return p end
    end
    return nil
end
local function kept(addon)
    local v = addon.store:get("char", PPP.PATH)
    if type(v) ~= "table" then return {} end
    return v
end

tests["prof path more: a list update never moves it, and the place is saved"] = function(t)
    local c, addon = start()
    c.fire("TRADE_SKILL_SHOW")
    if not shown(c) then t.ok(false, "no window"); return end
    local there = { "TOPLEFT", "BOTTOMLEFT", 612, 344 }
    t.ok(c.kitDrag(ID, there), "the player moves it")
    c.fire("TRADE_SKILL_LIST_UPDATE")
    t.eq(window(c).point, there, "a list update does not move it back")
    c.fire("TRADE_SKILL_LIST_UPDATE")
    t.eq(window(c).point, there, "nor the next one")
    t.eq(kept(addon).point, there, "the place is saved")
end

tests["prof path more: the saved place and fold come back in a new session"] = function(t)
    local there = { "TOPLEFT", "BOTTOMLEFT", 500, 300 }
    local c = start({ char = { layout = { profPath = { point = there, open = true } } } })
    c.fire("TRADE_SKILL_SHOW")
    if not shown(c) then t.ok(false, "no window"); return end
    t.eq(window(c).point, there, "where it was left")
    t.ok(part(c, "range1") ~= nil and part(c, "range2") ~= nil, "left open: the brackets are listed")
    local c2 = start({ char = { layout = { profPath = { point = there, open = false } } } })
    c2.fire("TRADE_SKILL_SHOW")
    t.eq(part(c2, "range1"), nil, "left folded: one line")
    t.eq(part(c2, "head") and part(c2, "head").text, "Blacksmithing 50/75: 50-60 Test Buckle")
end

tests["prof path more: a place saved wrong is not used"] = function(t)
    local c = start({ char = { layout = { profPath = { point = { "TOPLEFT", 4 }, open = "yes" } } } })
    c.fire("TRADE_SKILL_SHOW")
    if not shown(c) then t.ok(false, "no window"); return end
    t.eq(window(c).point, PPP.DEFAULT_POINT, "the panel's own first place")
    t.eq(part(c, "range1"), nil, "and folded")
end

tests["prof path more: a click on the head unfolds and folds it, and the fold is saved"] = function(t)
    local c, addon = start()
    c.fire("TRADE_SKILL_SHOW")
    if not shown(c) then t.ok(false, "no window"); return end
    t.eq(part(c, "range1"), nil, "folded at first")
    t.ok(c.kitClick(ID, "head"), "the head is a click")
    t.ok(part(c, "range1") ~= nil, "unfolded")
    t.eq(kept(addon).open, true, "saved open")
    t.ok(c.kitClick(ID, "head"), "and again")
    t.eq(part(c, "range1"), nil, "folded again")
    t.eq(kept(addon).open, false, "saved folded")
    t.eq(shown(c), true, "folding never hides it")
end

tests["prof path more: the setting off, the profession window opens nothing; chat still does"] = function(t)
    local c, addon = start()
    addon.settings:set(PPP.SETTING, false)
    c.fire("TRADE_SKILL_SHOW")
    t.eq(shown(c), false, "off: nothing shown")
    c.slashes[ns.id.slash]("prof")
    t.eq(shown(c), true, "asked for by hand: shown")
    t.eq(addon.settings:get(PPP.SETTING), false, "the setting is left as it was")
end

tests["prof path more: the minimap menu's row opens it"] = function(t)
    local c = start()
    local b = nil
    if type(c.minimapButtons) == "table" then b = c.minimapButtons[1] end
    if not b then t.ok(false, "no minimap button"); return end
    b.click("right")
    local row
    for _, item in ipairs(b.menuItems or {}) do
        if item.key == "prof" then row = item end
    end
    t.eq(row and row.text, ns.MinimapButton.MENU_PROF)
    t.eq(shown(c), false, "not open yet")
    t.ok(pcall(b.choose, "prof"), "the click does not raise")
    t.eq(shown(c), true, "opened from the minimap menu")
end

tests["prof path more: the arrow menu's Flow windows list opens and closes it"] = function(t)
    local row
    for _, w in ipairs(ns.ArrowMenu.FLOW_WINDOWS) do
        if w.name == PPP.NAME then row = w end
    end
    t.ok(row ~= nil, "listed in the arrow menu's Flow windows")
    if not row then return end
    local c, addon = start()
    local api = addon.use(PPP.NAME)
    if type(api) ~= "table" then t.ok(false, "no module"); return end
    for _, word in ipairs({ row.open, row.close, row.shown }) do
        t.eq(type(api[word]), "function", word)
    end
    if type(api[row.close]) ~= "function" then return end
    t.eq(api[row.shown](), false, "closed at first")
    t.eq(api[row.open](), true)
    t.eq(shown(c), true, "the row opens it")
    t.eq(api[row.shown](), true)
    api[row.close]()
    t.eq(shown(c), false, "and closes it")
    t.eq(api[row.shown](), false)
end

tests["prof path more: a bank never seen says so on the material's line, never 0"] = function(t)
    local c = start()
    c.fire("TRADE_SKILL_SHOW")
    if not shown(c) then t.ok(false, "no window"); return end
    c.kitClick(ID, "head")
    t.eq(part(c, "mat1") and part(c, "mat1").text, "Test Bar: need 20", "drawn in the window")
    t.eq(part(c, "mat2") and part(c, "mat2").text, "Test Flux: need 6", "the unseen one too")
    -- The fake client's record keeps a line's text only; the short text at
    -- its right is read from the view the window is drawn from.
    local known, unseen
    for _, child in ipairs(PPP.View({ plan = PLAN, open = true, prof = "Blacksmithing" }).children) do
        if child.key == "mat1" then known = child end
        if child.key == "mat2" then unseen = child end
    end
    t.ok(known ~= nil and unseen ~= nil, "both materials are in the view")
    if not known or not unseen then return end
    t.eq(known.right, "short 4", "a counted one says how many are short")
    t.eq(unseen.text, "Test Flux: need 6", "what the path needs in all")
    t.eq(unseen.right, PPP.MAT_BANK_UNSEEN, "the same line says the bank is not seen")
    t.ok(tostring(unseen.right):find("0", 1, true) == nil and unseen.right ~= PPP.MAT_HAVE,
        "never 0, never have all: " .. tostring(unseen.right))
end

tests["prof path more: the plain panel's rows say the same, bank and all"] = function(t)
    local rows = PPP.Plain({ plan = PLAN, open = true, prof = "Blacksmithing" })
    t.eq(rows[1].text, "Blacksmithing 50/75: 50-60 Test Buckle")
    t.eq(rows[2].text, "> 50-60 Test Buckle (x10)", "the current bracket is marked")
    t.eq(rows[3].text, "  60-75 Test Nail (about x18)", "an unsure count says about")
    t.eq(rows[5].text, "Test Flux: need 6 (" .. PPP.MAT_BANK_UNSEEN .. ")")
    t.eq(#PPP.Plain({ plan = PLAN, open = false }), 1, "folded: one row")
end

return tests
