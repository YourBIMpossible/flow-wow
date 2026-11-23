local _, ns = ...

-- Conjured food and water, a shared read (lead section 197, point 2): the
-- snapshot's `conjured` map, { [conjure spell] = how many of what it makes
-- are in your bags }, read by the rotation driver from the client's item
-- count for the items a pack names in options.conjure. Any class can name
-- them; the Mage pack is the first. Not known stays not known: no count is
-- made up. Made-up items and counts; not tested in game.

local tests = {}
local R = ns.Rotation
local D = ns.RotationDriver

local PACK = { options = { conjure = {
    { spell = "Conjure Water", items = { "Conjured Water", "Conjured Fresh Water" } },
    { spell = "Conjure Food", items = { "Conjured Muffin" } },
} } }

local function client(counts)
    local c = ns.make.fakeClient()
    for item, n in pairs(counts or {}) do c.setItemCount(item, n) end
    return c
end

tests["conjured: the snapshot keeps the map, copied; not given is not known"] = function(t)
    local given = { ["Conjure Water"] = 0 }
    local s = ns.SnapshotOf({ conjured = given })
    t.eq(s.conjured, { ["Conjure Water"] = 0 })
    given["Conjure Water"] = 9
    t.eq(s.conjured["Conjure Water"], 0, "a copy")
    t.eq(ns.SnapshotOf({}).conjured, nil)
end

tests["conjured: the driver adds the counts of each spell's items"] = function(t)
    local read = D.Read(client({ ["Conjured Water"] = 4, ["Conjured Fresh Water"] = 6, ["Conjured Muffin"] = 0 }), PACK, {})
    t.eq(read("conjured"), { ["Conjure Water"] = 10, ["Conjure Food"] = 0 })
end

tests["conjured: a spell none of whose items could be counted is left out; none at all is not read"] = function(t)
    local read = D.Read(client({ ["Conjured Water"] = 2 }), PACK, {})
    t.eq(read("conjured"), { ["Conjure Water"] = 2 }, "food not counted: not there")
    t.eq(D.Read(client({}), PACK, {})("conjured"), nil, "nothing counted")
    t.eq(D.Read(client({ ["Conjured Water"] = 2 }), {}, {})("conjured"), nil, "a pack that names none")
    local bare = client({ ["Conjured Water"] = 2 })
    bare.itemCount = nil
    t.eq(D.Read(bare, PACK, {})("conjured"), nil, "a client with no item count")
end

tests["conjured: R.Conjured answers the count, or nil when not read"] = function(t)
    t.eq(R.Conjured({ conjured = { ["Conjure Water"] = 3 } }, "Conjure Water"), 3)
    t.eq(R.Conjured({ conjured = { ["Conjure Water"] = 3 } }, "Conjure Food"), nil)
    t.eq(R.Conjured({}, "Conjure Water"), nil)
    t.eq(R.Conjured({ conjured = { ["Conjure Water"] = "x" } }, "Conjure Water"), nil)
end

tests["conjured: diag names it in words when it was not read"] = function(t)
    t.eq(ns.Diag.READ_WORDS.conjured, "your conjured food and water")
end

return tests
