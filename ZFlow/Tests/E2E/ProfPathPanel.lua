local _, ns = ...
-- P-PATH-2 end to end (lead section 449): the whole add-on on a fake
-- client. The profession window opens the path panel; without a plan it
-- says the path is not computed yet; with a plan (a stand-in for
-- Items/ProfPath.lua, the section 450 contract) it unfolds to the
-- brackets, a click picks a bracket, a drag is kept across a reopen, and
-- the chat word opens it with the profession window closed.
-- Look only: nothing is crafted, bought or trained. Offline test, fake
-- client lines. Not tested in game.
--
-- Red before the code: no ProfPathPanel window is ever drawn.
local tests = {}

local ID = "ProfPathPanel"

local function start(path)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, {})
    c.setScreen(1024, 768)
    c.setRecipes({ profession = 164, name = "Blacksmithing", skill = 50, max = 75, recipes = {} })
    local addon = ns.offline.addon(c)
    -- The stand-in goes on the add-on copy the fake client loaded.
    if path then addon.ProfPath = { Path = function() return path end } end
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    return c
end

local function window(c) return c.kitWindows()[ID] end
local function part(w, key)
    for _, p in ipairs(w and w.parts or {}) do
        if p.key == key then return p end
    end
    return nil
end

local PLAN = {
    id = "Blacksmithing", rev = 1, prof = "Blacksmithing", skill = 50, max = 75, status = "ok", selected = 1,
    ranges = {
        { from = 50, to = 60, recipe = "Test Buckle", crafts = 10, sure = true },
        { from = 60, to = 75, recipe = "Test Nail", crafts = 18, sure = false },
    },
    materials = { { name = "Test Bar", need = 20, net = 4 } },
}

tests["e2e: the profession window opens the path panel, which says the path is not computed yet"] = function(t)
    local c = start()
    c.fire("TRADE_SKILL_SHOW")
    local w = window(c)
    t.ok(w ~= nil and w.shown == true, "the path panel is shown with the profession window")
    local head = part(w, "head")
    t.ok(head ~= nil and tostring(head.text):find("path not computed yet", 1, true) ~= nil,
        "one line, never blank")
end

tests["e2e: with a plan it unfolds, a click picks a bracket, and a drag is kept"] = function(t)
    do
        local c = start(PLAN)
        c.fire("TRADE_SKILL_SHOW")
        local w = window(c)
        t.ok(w ~= nil, "drawn")
        if not w then return end
        t.eq(part(w, "head").text, "Blacksmithing 50/75: 50-60 Test Buckle")
        t.eq(part(w, "range1"), nil, "folded: one line")
        t.ok(c.kitClick(ID, "head"), "the line unfolds")
        w = window(c)
        t.ok(part(w, "range1") ~= nil and part(w, "range2") ~= nil, "open: the brackets are listed")
        t.ok(c.kitClick(ID, "range2"), "a bracket is a click")
        w = window(c)
        t.eq(part(w, "head").text, "Blacksmithing 50/75: 60-75 Test Nail", "the line follows the picked bracket")
        t.ok(c.kitDrag(ID, { "TOPLEFT", "BOTTOMLEFT", 600, 500 }), "the player moves it")
        c.fire("TRADE_SKILL_LIST_UPDATE")
        c.fire("TRADE_SKILL_CLOSE")
        c.fire("TRADE_SKILL_SHOW")
        t.eq(window(c).point, { "TOPLEFT", "BOTTOMLEFT", 600, 500 }, "it stays where the player put it")
    end
end

tests["e2e: the chat word opens it with the profession window closed"] = function(t)
    local c = start()
    c.slashes[ns.id.slash]("prof")
    local w = window(c)
    t.ok(w ~= nil and w.shown == true, "opened from the chat word")
end

tests["e2e: once ProfPath makes the plan the old dock under the window steps aside"] = function(t)
    do
        local c = start(PLAN)
        c.fire("TRADE_SKILL_SHOW")
        local dock = c.kitWindows()["ProfDock"]
        t.ok(dock == nil or dock.shown == false, "one profession panel, not two")
        t.ok(window(c) ~= nil and window(c).shown == true)
    end
end

return tests
