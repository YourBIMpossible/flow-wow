local _, ns = ...

-- N67 (research items 16 and 26): the client reads of two other add-ons'
-- data at runtime, GatherMate2's nodes on one map and Attune's progress.
-- Read only: nothing of theirs is written, and a missing add-on or a read
-- that raises is nil. Made-up add-on tables (their shapes are first guesses
-- from the research note, not seen in game); no Lua runtime on Zen, so these
-- were traced by hand. The fake client's setters are checked at the end.
local tests = {}

local MAP, OTHER = 1429, 1411
-- GatherMate2's coord packing (research item 16):
-- floor(x*1e4+.5)*1e6 + floor(y*1e4+.5)*100.
local function pack(x, y) return math.floor(x * 1e4 + 0.5) * 1e6 + math.floor(y * 1e4 + 0.5) * 100 end
local NAMES = { [1] = "Copper Vein", [2] = "Peacebloom" }

-- A made-up GatherMate2 object: nodes[map][kind] = { { coord, nodeId } }.
-- Any write to it raises, so a read that writes fails the test.
local function gatherMate(nodes, opts)
    opts = opts or {}
    local g = {}
    function g:GetNodesForZone(map, kind)
        if opts.raise then error("GetNodesForZone failed (test)") end
        local list = (nodes[map] or {})[kind] or {}
        local i = 0
        return function()
            i = i + 1
            local r = list[i]
            if r then return r[1], r[2] end
            return nil
        end
    end
    function g:DecodeLoc(coord)
        return math.floor(coord / 1e6) / 1e4, (math.floor(coord / 100) % 1e4) / 1e4
    end
    function g:GetNameForNode(_, id) return NAMES[id] end
    return setmetatable(g, { __newindex = function() error("GatherMate2 written (test)") end })
end

local function holds(v, text, depth)
    depth = depth or 0
    if depth > 20 then return false end
    if type(v) == "string" then return v:find(text, 1, true) ~= nil end
    if type(v) ~= "table" then return false end
    for key, value in pairs(v) do
        if holds(key, text, depth + 1) or holds(value, text, depth + 1) then return true end
    end
    return false
end

tests["client gatherMateNodes: no GatherMate2 is nil"] = function(t)
    t.eq(ns.make.client({}).gatherMateNodes(MAP), nil)
end

tests["client gatherMateNodes: the nodes of the map asked, kind, place and name, nothing written"] = function(t)
    local env = { GatherMate2 = gatherMate({
        [MAP] = { Mining = { { pack(0.25, 0.5), 1 } }, ["Herb Gathering"] = { { pack(0.1, 0.2), 2 } } },
        [OTHER] = { Mining = { { pack(0.9, 0.9), 1 } } },
    }) }
    local rows = ns.make.client(env).gatherMateNodes(MAP)
    t.eq(rows, {
        { kind = "Mining", x = 0.25, y = 0.5, node = "Copper Vein" },
        { kind = "Herb Gathering", x = 0.1, y = 0.2, node = "Peacebloom" },
    })
    t.eq(#ns.make.client(env).gatherMateNodes(OTHER), 1, "another map: its own node only")
    t.eq(ns.make.client(env).gatherMateNodes(4000), {}, "a map with none: an empty list, GatherMate2 is there")
end

tests["client gatherMateNodes: a read that raises, or a bad map, is nil"] = function(t)
    local env = { GatherMate2 = gatherMate({ [MAP] = { Mining = { { pack(0.25, 0.5), 1 } } } }, { raise = true }) }
    t.eq(ns.make.client(env).gatherMateNodes(MAP), nil)
    local fine = ns.make.client({ GatherMate2 = gatherMate({}) })
    t.eq(fine.gatherMateNodes(nil), nil)
    t.eq(fine.gatherMateNodes("1429"), nil)
    t.eq(ns.make.client({ GatherMate2 = "not a table" }).gatherMateNodes(MAP), nil)
end

tests["client gatherMateNodes: at most GATHERMATE_NODES_MAX rows"] = function(t)
    local many = {}
    for i = 1, 600 do many[i] = { pack((i % 100) / 100, 0.5), 1 } end
    local rows = ns.make.client({ GatherMate2 = gatherMate({ [MAP] = { Mining = many } }) }).gatherMateNodes(MAP)
    t.eq(type(rows), "table")
    if type(rows) == "table" then t.eq(#rows, 500) end
end

-- A made-up Attune: its list and this character's progress, keyed by a
-- made-up "<name>-<realm>" the read must never hand out.
local function attuneEnv()
    return {
        Attune_Data = { attunes = {
            { ID = 1, NAME = "Molten Core" }, { ID = 2, NAME = "Onyxia" }, { ID = 3, NAME = "Blackwing Lair" },
        } },
        Attune_DB = { toons = { ["Madeup-Testrealm"] = { attuned = { [1] = 100, [2] = 40 } } } },
        UnitName = function() return "Madeup" end,
        GetRealmName = function() return "Testrealm" end,
    }
end

tests["client attuneProgress: each attunement with this character's percent, no name handed out"] = function(t)
    local env = attuneEnv()
    local rows = ns.make.client(env).attuneProgress()
    t.eq(rows, {
        { id = 1, name = "Molten Core", percent = 100 },
        { id = 2, name = "Onyxia", percent = 40 },
        { id = 3, name = "Blackwing Lair" },
    })
    t.ok(not holds(rows, "Madeup"), "the character's name is not in the answer")
    t.eq(env.Attune_DB.toons["Madeup-Testrealm"].attuned, { [1] = 100, [2] = 40 }, "nothing written")
end

tests["client attuneProgress: no Attune, no saved data, or a read that raises is nil"] = function(t)
    t.eq(ns.make.client({}).attuneProgress(), nil)
    local env = attuneEnv()
    env.Attune_DB = nil
    t.eq(ns.make.client(env).attuneProgress(), nil)
    env = attuneEnv()
    env.Attune_Data = setmetatable({}, { __index = function() error("Attune_Data failed (test)") end })
    t.eq(ns.make.client(env).attuneProgress(), nil)
end

tests["client attuneProgress: another character's progress only: percents not known"] = function(t)
    local env = attuneEnv()
    env.UnitName = function() return "Other" end
    local rows = ns.make.client(env).attuneProgress()
    t.eq(rows, {
        { id = 1, name = "Molten Core" }, { id = 2, name = "Onyxia" }, { id = 3, name = "Blackwing Lair" },
    })
end

tests["client addon sources are listed in Diag.NAMES"] = function(t)
    local listed = {}
    for _, name in ipairs(ns.Diag.NAMES) do listed[name] = true end
    for _, name in ipairs({ "GatherMate2", "Attune_Data", "Attune_DB" }) do t.ok(listed[name], name) end
end

tests["fake client: gatherMateNodes and attuneProgress as set, copies, asks counted"] = function(t)
    local c = ns.make.fakeClient()
    t.eq(c.gatherMateNodes(MAP), nil, "nothing set: no GatherMate2")
    t.eq(c.attuneProgress(), nil, "nothing set: no Attune")
    local set = { { kind = "Mining", x = 0.25, y = 0.5, node = "Copper Vein" } }
    c.setGatherMateNodes(MAP, set)
    local got = c.gatherMateNodes(MAP)
    t.eq(got, set)
    t.ok(got ~= set and got[1] ~= set[1], "a copy")
    t.eq(c.gatherMateNodes(OTHER), {}, "GatherMate2 there, none on that map")
    t.eq(c.gatherMateAsks, 3)
    c.setGatherMateNodes(nil)
    t.eq(c.gatherMateNodes(MAP), nil, "taken away")
    local progress = { { id = 2, name = "Onyxia", percent = 40 } }
    c.setAttuneProgress(progress)
    t.eq(c.attuneProgress(), progress)
    t.ok(c.attuneProgress() ~= progress, "a copy")
end

return tests
