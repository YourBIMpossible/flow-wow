-- R9 (lead "done means"): the inventory list is reached without a slash
-- command, end to end on the whole
-- add-on loaded on a fake client: right-click the arrow, Show, Flow
-- windows, then Inventory. Look only: opening the list sells or moves
-- nothing. (The dungeon "Get ready" stops are reached the same way: Flow
-- windows, Dungeon quests, Plan the run; Tests/E2E/MenuWindows.lua and
-- Tests/E2E/DungeonReady.lua cover those two steps.) Not tested in game.
--
-- Fails before the change: Flow windows has no Inventory row, so the
-- InventoryList window is only reached by typing the word.
local _, ns = ...
local tests = {}

local function boot()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setRaceId(1); c.setFaction("Alliance"); c.setLevel(18)
    c.setZone(1, 1436); c.setPosition(1436, 0.5, 0.5)
    c.setWindow("WorldMapFrame", {})
    c.setBagItems({ { bag = 0, slot = 1, item = 6948, count = 1 } })
    c.setItemInfo({ [6948] = { name = "Hearthstone", quality = 1, sellPrice = 0 } })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(2, 10)
    c.slashes[ns.id.slash]("arrow demo")
    c.advance(0.1, 2)
    return c, addon
end

local function arrowProblems(addon)
    local n = 0
    for _, p in ipairs(addon.problems:list()) do
        if p.kind == "arrow" then n = n + 1 end
    end
    return n
end

local function intoWindows(t, q)
    q.click("right")
    t.eq(q.enter("show"), true, "Show opens its level")
    t.eq(q.enter("windows"), true, "Flow windows opens under Show")
end

local function rowOf(items, key)
    for _, r in ipairs(items or {}) do
        if r.key == key then return r end
    end
    return nil
end

tests["menu reach: Flow windows lists an Inventory row"] = function(t)
    local M = ns.ArrowMenu
    local found
    for _, w in ipairs(M.FLOW_WINDOWS) do
        if w.name == ns.InventoryList.NAME then found = w end
    end
    t.ok(found ~= nil, "an Inventory row in Flow windows")
    if not found then return end
    t.eq(found.text, "Inventory")
    t.eq(found.open, "Show")
    local items = M.Items({ windows = { [found.name] = true } })
    local row = rowOf(rowOf(rowOf(items, "show").children, M.FLOW).children, M.FLOW .. "." .. found.name)
    t.ok(row ~= nil and not row.disabled, "ready: not greyed")
    t.eq(M.Action(M.FLOW .. "." .. found.name, { windows = { [found.name] = true } }), { flowWindow = found.name })
end

tests["menu reach: the Inventory row opens the inventory list, no command typed"] = function(t)
    local c, addon = boot()
    local q = c.arrows[1]
    t.ok(q ~= nil, "an arrow to right-click")
    if not q then return end
    intoWindows(t, q)
    t.eq(q.pickRow("windows." .. ns.InventoryList.NAME), true, "the Inventory row")
    c.advance(1, 5)
    local rec = c.kitWindows()[ns.InventoryList.KIT_ID]
    t.eq(rec ~= nil and rec.shown, true, "the inventory list is open")
    t.eq(arrowProblems(addon), 0, "nothing went wrong in the menu")
end

return tests
