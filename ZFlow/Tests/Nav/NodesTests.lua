-- Tests for Nav/Nodes.lua (G22): the gathering nodes the player gathered
-- themselves are remembered per map and the nearest are said; the arrow
-- can be pointed at the nearest by a waypoint. Made-up nodes and items;
-- fake client. Not tested in game. Look only.
local _, ns = ...

local N = ns.Nav
local A = ns.Arrow
local tests = {}

local MAP = 1411
local HERB = "|cffffffff|Hitem:2447::::::::|h[Peacebloom]|h|r"
local LEAF = "|cffffffff|Hitem:765::::::::|h[Silverleaf]|h|r"

local function has(t)
    local X = N.Nodes
    local ok = type(X) == "table" and type(X.Declare) == "function"
    t.ok(ok, "Nav/Nodes.lua is loaded")
    return ok
end

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, {})
    c.setScreen(1024, 768)
    c.setZone(1, MAP)
    c.setFacing(0)
    c.setPosition(MAP, 0.5, 0.5)
    c.setMapSize(MAP, 1000, 500)
    c.setClass("WARRIOR")
    c.setFaction("Horde")
    c.setProfessions(opts.profs or { "Herbalism" })
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    N.Nodes.Declare(k, d)
    local a = A.Declare(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, a
end

local function gather(c, x, y, link, guid)
    c.setPosition(MAP, x, y)
    c.setLootWindow({ source = { guid = guid or "GameObject-0-1-2-3-1618-0000" }, items = { { item = link, count = 1 } } })
    c.fire("LOOT_OPENED")
    c.setLootWindow(nil)
end

local function nodesOf(c)
    local l = c.saved(ns.id.accountDB).learned
    return type(l) == "table" and type(l.nodes) == "table" and l.nodes[MAP] or nil
end

tests["nodes: the names and the setting row"] = function(t)
    if not has(t) then return end
    local X = N.Nodes
    t.eq({ X.NAME, X.SETTING, X.PATH, X.WORD }, { "nodes", "nav.nodes", "learned.nodes", "nodes" })
    local Model = ns.Settings.Model
    t.ok(Model.New(Model.ROWS):row(X.SETTING) ~= nil, "nav.nodes is a row of the model")
    local k = start()
    t.eq(k.settings:get(X.SETTING), true)
end

tests["nodes: a node the player gathered is remembered where they stood"] = function(t)
    if not has(t) then return end
    local _, c = start()
    gather(c, 0.5, 0.5, HERB)
    gather(c, 0.6, 0.5, LEAF, "GameObject-0-1-2-3-1617-0000")
    gather(c, 0.5001, 0.5, HERB)
    local list = nodesOf(c)
    t.ok(type(list) == "table" and #list == 2, "two nodes; the same one again is not a third")
    if type(list) ~= "table" or #list ~= 2 then return end
    t.eq({ list[1].name, list[1].prof }, { "Peacebloom", "Herbalism" })
    t.eq(list[1].n, 2)
end

tests["nodes: a creature's corpse or a player without a gathering profession keeps nothing"] = function(t)
    if not has(t) then return end
    local _, c = start()
    gather(c, 0.5, 0.5, HERB, "Creature-0-1-2-3-299-0000")
    t.eq(nodesOf(c), nil)
    local _, c2 = start({ profs = { "Tailoring" } })
    gather(c2, 0.5, 0.5, HERB)
    t.eq(nodesOf(c2), nil)
end

tests["nodes: the word says the nearest with the distance, and go points the arrow there"] = function(t)
    if not has(t) then return end
    local _, c, a = start()
    gather(c, 0.5, 0.5, HERB)
    gather(c, 0.6, 0.5, LEAF, "GameObject-0-1-2-3-1617-0000")
    c.setPosition(MAP, 0.52, 0.5)
    c.slashes[ns.id.slash]("nodes")
    local first, second
    for i, line in ipairs(c.printed) do
        if line:find("Peacebloom", 1, true) then first = first or i end
        if line:find("Silverleaf", 1, true) then second = second or i end
    end
    t.ok(first ~= nil and second ~= nil and first < second, "nearest first")
    t.ok(first ~= nil and c.printed[first]:find("20 yd", 1, true) ~= nil,
        "with yards: " .. tostring(first and c.printed[first]))
    c.slashes[ns.id.slash]("nodes go")
    c.advance(A.RELAYOUT * 2, 2)
    local h = a.heading()
    t.ok(type(h) == "table", "the arrow points")
    if type(h) ~= "table" then return end
    t.eq({ h.map, h.x, h.y }, { MAP, 0.5, 0.5 })
end

tests["nodes: only nodes of the player's own professions are shown"] = function(t)
    if not has(t) then return end
    local _, c = start({ profs = { "Mining" } })
    gather(c, 0.5, 0.5, "|cffffffff|Hitem:2770::::::::|h[Copper Ore]|h|r")
    t.ok(type(nodesOf(c)) == "table", "kept for the miner")
    c.setProfessions({ "Herbalism" })
    c.slashes[ns.id.slash]("nodes")
    local shown = false
    for _, line in ipairs(c.printed) do
        if line:find("Copper Ore", 1, true) then shown = true end
    end
    t.ok(not shown, "a mining node is not shown to an herbalist")
end

tests["nodes: the store is capped per map"] = function(t)
    if not has(t) then return end
    local list = {}
    for i = 1, N.Nodes.PER_MAP + 5 do list[i] = { x = i / 1000, y = 0.5, at = i } end
    N.Nodes.Cap(list)
    t.eq(#list, N.Nodes.PER_MAP)
    t.eq(list[1].at, 6, "the oldest went")
end

return tests
