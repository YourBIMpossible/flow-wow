local _, ns = ...
-- Parity rows E-64 and E-63, the data halves (lead section 784): gathering
-- nodes near you, as Flow's Modules/Crafting/Nearby.lua (NB.Count and NB.Line
-- :140-180, the tracker line within NB.RADIUS of you and your next step;
-- NB.MinimapGroups :209, clouds of spawn spots per profession). Spots come
-- only from the player's own GatherMate2 read (Nav/AddonSources.lua,
-- client.gatherMateNodes); no node table is copied (section 611). Our own
-- words (section 757). Made-up nodes on a 1000 x 1000 yard map.
-- Fails before: no such file.
local tests = {}

local function NN() return ns.Nav and ns.Nav.NearbyNodes end

local SIZE = { w = 1000, h = 1000 }
local function n(kind, name, x, y) return { kind = kind, node = name, x = x, y = y, source = "GatherMate2" } end
local NODES = {
    n("Mining", "Iron Deposit", 0.50, 0.50), n("Mining", "Iron Deposit", 0.55, 0.50),
    n("Mining", "Iron Deposit", 0.52, 0.53), n("Herb Gathering", "Kingsblood", 0.48, 0.50),
    n("Herb Gathering", "Kingsblood", 0.50, 0.46), n("Mining", "Gold Vein", 0.90, 0.90),
    n("Fishing", "Oily Blackmouth School", 0.50, 0.51), n("Treasure", "Chest", 0.50, 0.50),
}
local HERE = { x = 0.50, y = 0.50 }
local BOTH = { Mining = true, Herbalism = true }

tests["nearby nodes: counted within the radius of you or your next step, by your professions"] = function(t)
    t.eq(type(NN()), "table", "loaded")
    if type(NN()) ~= "table" then return end
    t.eq(NN().RADIUS, 120)
    local counts = NN().Count(NODES, { HERE }, 120, SIZE, BOTH)
    t.eq(counts, {
        { name = "Iron Deposit", prof = "Mining", count = 3 },
        { name = "Kingsblood", prof = "Herbalism", count = 2 },
    }, "most first; the far vein, fishing and treasure left out")
    t.eq(NN().Count(NODES, { HERE }, 120, SIZE, { Mining = true }),
        { { name = "Iron Deposit", prof = "Mining", count = 3 } }, "only the professions you know")
    local next = { x = 0.90, y = 0.90 }
    local both = NN().Count(NODES, { HERE, next }, 120, SIZE, BOTH)
    t.eq(#both, 3, "your next step's nodes too")
    t.eq(NN().Count(NODES, { HERE }, 120, nil, BOTH), {}, "map size not known: nothing")
    t.eq(NN().Count(nil, { HERE }, 120, SIZE, BOTH), {})
end

tests["nearby nodes: the tracker line, in our words"] = function(t)
    if type(NN()) ~= "table" then return t.ok(false, "not loaded") end
    local counts = NN().Count(NODES, { HERE }, 120, SIZE, BOTH)
    t.eq(NN().Line(counts), "Gather near you: Iron Deposit x3, Kingsblood x2")
    t.eq(NN().Line({}), nil, "nothing near: no line")
    local many = {}
    for i = 1, 5 do many[i] = { name = "Node " .. i, prof = "Mining", count = 1 } end
    t.eq(NN().Line(many, 3), "Gather near you: Node 1 x1, Node 2 x1, Node 3 x1, and 2 more")
end

tests["nearby nodes: clouds for the minimap, spots near each other grouped per profession"] = function(t)
    if type(NN()) ~= "table" then return t.ok(false, "not loaded") end
    t.eq(NN().CLOUD, 15)
    local groups = NN().Groups(NODES, HERE, 15, 120, SIZE, BOTH)
    local mining, herbs = 0, 0
    for _, g in ipairs(groups) do
        t.ok(type(g.x) == "number" and type(g.y) == "number" and g.count >= 1, "a cloud has a place and a count")
        if g.prof == "Mining" then mining = mining + g.count end
        if g.prof == "Herbalism" then herbs = herbs + g.count end
    end
    t.eq({ mining, herbs }, { 3, 2 }, "every near spot in one cloud or another; the far vein left out")
    local one = NN().Groups({ n("Mining", "Iron Deposit", 0.50, 0.50), n("Mining", "Iron Deposit", 0.505, 0.50) },
        HERE, 15, 120, SIZE, BOTH)
    t.eq(#one, 1, "five yards apart: one cloud")
    t.eq(one[1] and one[1].count, 2)
    t.eq(NN().Groups(NODES, HERE, 15, 120, nil, BOTH), {}, "map size not known: none")
end

return tests
