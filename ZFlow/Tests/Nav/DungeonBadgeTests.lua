local _, ns = ...

-- Tests for ZFlow/Nav/DungeonBadge.lua (FLOW-PARITY B-55): the dungeon key
-- badge's text, tooltip and click, as data. Pure. Made-up dungeons.

local tests = {}

local function B() return ns.DungeonBadge end

tests["dungeon badge: the best run is the one with the highest measured ratio"] = function(t)
    local list = { { key = 1, name = "A", ratio = 1.2 }, { key = 2, name = "B" }, { key = 3, name = "C", ratio = 2.5 } }
    t.eq(B().Best(list).key, 3)
    t.eq(B().Best({ { key = 1, name = "A" } }), nil, "nothing measured: no suggestion")
    t.eq(B().Best(nil), nil)
end

tests["dungeon badge: no badge inside a dungeon or with no run"] = function(t)
    t.eq(B().Status({ inside = true, prepared = { key = 1, name = "A", ratio = 2 } }), nil)
    t.eq(B().Status({}), nil)
    t.eq(B().Status(nil), nil)
end

tests["dungeon badge: a suggested run shows its ratio and prepares on click"] = function(t)
    local s = B().Status({ best = { key = 3, name = "C", ratio = 2.46 }, solo = false, tip = { "C: 2 of 5 in your log" } })
    t.eq(s.text, "2.5x")
    t.eq(s.tone, "good")
    t.eq(s.action, "prepare"); t.eq(s.key, 3)
    t.eq(s.clickText, B().PREPARE)
    t.eq(s.tip, { "C: 2 of 5 in your log" })
end

tests["dungeon badge: the prepared run wins, cancels on click; alone it is muted and says it needs a group"] = function(t)
    local s = B().Status({ prepared = { key = 1, name = "A" }, best = { key = 3, name = "C", ratio = 2 }, solo = true })
    t.eq(s.key, 1)
    t.eq(s.text, "?", "not measured")
    t.eq(s.tone, "muted")
    t.eq(s.action, "cancel"); t.eq(s.clickText, B().CANCEL)
    t.eq(s.tip[#s.tip], B().NEEDS_GROUP)
end

-- §639: Build gathers Status's input from the game and the modules.
local function fakeK(o)
    local mods = o.mods or {}
    return {
        client = {
            instance = function() return { inside = o.inside == true, kind = o.kind or "none" } end,
            grouped = function() return o.grouped end,
        },
        use = function(name) return mods[name] end,
    }
end

local ST = { byKey = {
    [1] = { key = 1, name = "A", ids = { 11 }, minQ = 10 },
    [2] = { key = 2, name = "B", ids = { 12 }, minQ = 20 },
    [3] = { key = 3, name = "Empty", ids = {}, minQ = 15 },
} }

local RATIOS = { A = 1.2, B = 2.5 }
local VISIT = { Ratio = function(name) return RATIOS[name] end }

tests["dungeon badge: Build picks the best measured run, grouped, with its rate in the tip"] = function(t)
    local s = B().Build(fakeK({ grouped = true, mods = { dungeonVisit = VISIT } }), ST)
    t.eq(s.inside, false)
    t.eq(s.solo, false)
    t.eq(s.prepared, nil, "no dungeonRun module: no prepared run")
    t.eq(s.best.key, 2); t.eq(s.best.ratio, 2.5)
    t.eq(s.tip[1], "B")
    t.eq(B().Status(s).text, "2.5x")
end

tests["dungeon badge: Build takes the prepared run from dungeonRun when it is there"] = function(t)
    local run = { State = function() return { key = 1, name = "A" } end }
    local s = B().Build(fakeK({ grouped = false, mods = { dungeonVisit = VISIT, dungeonRun = run } }), ST)
    t.eq(s.prepared.key, 1); t.eq(s.prepared.ratio, 1.2)
    t.eq(s.solo, true)
    t.eq(s.tip[1], "A")
end

tests["dungeon badge: Build inside a dungeon, or with nothing read, gives no badge"] = function(t)
    t.eq(B().Status(B().Build(fakeK({ inside = true, kind = "party", mods = { dungeonVisit = VISIT } }), ST)), nil)
    t.eq(B().Status(B().Build(fakeK({ grouped = true }), nil)), nil)
    t.eq(B().Status(B().Build(nil, nil)), nil)
end

return tests
