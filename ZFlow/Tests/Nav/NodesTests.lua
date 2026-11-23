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
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true }, learned = opts.learned })
    c.setSaved(ns.id.charDB, {})
    c.setScreen(1024, 768)
    c.setZone(1, MAP)
    c.setFacing(0)
    c.setPosition(MAP, 0.5, 0.5)
    c.setMapSize(MAP, 1000, 500)
    c.setClass("WARRIOR")
    c.setFaction("Horde")
    c.setProfessions(opts.profs or { "Herbalism" })
    c.setSpellId("Herb Gathering", 2366)
    c.setSpellId("Mining", 2575)
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

-- cast: the gathering spell fired just before the window ("Herb Gathering"
-- unless given; false for none, as a chest).
local function gather(c, x, y, link, guid, cast)
    c.setPosition(MAP, x, y)
    if cast == nil then cast = "Herb Gathering" end
    if cast then c.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", c.spellId(cast)) end
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
    gather(c, 0.5, 0.5, "|cffffffff|Hitem:2770::::::::|h[Copper Ore]|h|r", nil, "Mining")
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

-- P-GATHER (zflow-gather-5): the node's profession, chests, names.
local ORE = "|cffffffff|Hitem:2770::::::::|h[Copper Ore]|h|r"
local SWORD = "|cffffffff|Hitem:25::::::::|h[Worn Shortsword]|h|r"
local MATERIALS = {
    [2447] = { name = "Peacebloom", classID = 7, subclassID = 9 },
    [765] = { name = "Silverleaf", classID = 7, subclassID = 9 },
    [2770] = { name = "Copper Ore", classID = 7, subclassID = 7 },
    [25] = { name = "Worn Shortsword", classID = 2, subclassID = 7 },
}

local function shownLines(c, word)
    local out = {}
    for _, line in ipairs(c.printed) do
        if line:find(word, 1, true) then out[#out + 1] = line end
    end
    return out
end

tests["nodes: a herbalist-miner's node gets the profession of the gathering cast"] = function(t)
    if not has(t) then return end
    local _, c = start({ profs = { "Herbalism", "Mining" } })
    gather(c, 0.5, 0.5, ORE, nil, "Mining")
    gather(c, 0.6, 0.5, HERB, "GameObject-0-1-2-3-1617-0000", "Herb Gathering")
    local list = nodesOf(c)
    t.ok(type(list) == "table" and #list == 2, "two nodes kept")
    if type(list) ~= "table" or #list ~= 2 then return end
    t.eq({ list[1].prof, list[2].prof }, { "Mining", "Herbalism" })
    c.setProfessions({ "Herbalism" })
    c.slashes[ns.id.slash]("nodes")
    t.eq(#shownLines(c, "Copper Ore"), 0, "the ore is not shown to an herbalist")
    t.eq(#shownLines(c, "Peacebloom"), 1, "the herb is")
end

tests["nodes: without a cast, the looted material says the profession"] = function(t)
    if not has(t) then return end
    local _, c = start({ profs = { "Herbalism", "Mining" } })
    c.setItemInfo(MATERIALS)
    gather(c, 0.5, 0.5, ORE, nil, false)
    local list = nodesOf(c)
    t.ok(type(list) == "table" and #list == 1, "kept from the ore")
    if type(list) ~= "table" or #list ~= 1 then return end
    t.eq({ list[1].prof, list[1].name }, { "Mining", "Copper Ore" })
end

tests["nodes: a chest a gatherer opens is not kept"] = function(t)
    if not has(t) then return end
    local _, c = start({ profs = { "Herbalism" } })
    c.setItemInfo(MATERIALS)
    gather(c, 0.5, 0.5, SWORD, "GameObject-0-1-2-3-2843-0000", false)
    t.eq(nodesOf(c), nil, "no cast and no gathering material: a chest")
    -- A cast long ago does not make the next window a node.
    gather(c, 0.5, 0.5, HERB, nil, "Herb Gathering")
    c.advance(N.Nodes.CAST_WINDOW + 5, 1)
    gather(c, 0.7, 0.7, SWORD, "GameObject-0-1-2-3-2844-0000", false)
    local list = nodesOf(c)
    t.ok(type(list) == "table" and #list == 1, "only the herb node is kept")
end

tests["nodes: a node is named from the item's own name and shown with its profession"] = function(t)
    if not has(t) then return end
    local _, c = start({ profs = { "Mining" } })
    c.setItemInfo(MATERIALS)
    gather(c, 0.5, 0.5, 2770, nil, "Mining")
    local list = nodesOf(c)
    t.ok(type(list) == "table" and list[1] ~= nil and list[1].name == "Copper Ore",
        "named from the item info: " .. tostring(list and list[1] and list[1].name))
    c.slashes[ns.id.slash]("nodes")
    local lines = shownLines(c, "Copper Ore")
    t.ok(#lines == 1 and lines[1]:find("Mining", 1, true) ~= nil,
        "the line says the profession: " .. tostring(lines[1]))
    c.slashes[ns.id.slash]("nodes go")
    t.ok(#shownLines(c, "Copper Ore") >= 2, "the waypoint is labelled with the name")
end

tests["nodes: an old node saved without a profession still shows to any gatherer"] = function(t)
    if not has(t) then return end
    local _, c = start({ profs = { "Mining" },
        learned = { nodes = { [MAP] = { { x = 0.5, y = 0.5, name = "Old Find", n = 1, at = 0 } } } } })
    c.slashes[ns.id.slash]("nodes")
    t.eq(#shownLines(c, "Old Find"), 1)
end

return tests
