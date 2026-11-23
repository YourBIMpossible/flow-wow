local _, ns = ...

-- The pet state in the rotation context (lead section 197): the snapshot
-- field, the driver's read, the three helpers in Choose.lua, and the diag
-- names and words. Offline: hand-made answers, not the game's.
--   snapshot.pet  nil (not read) | { exists = false } | { exists = true, ... }
--   R.PetUp, R.NoPet, R.PetDead: true, false, or nil when it cannot be told

local D = ns.RotationDriver
local R = ns.Rotation
local tests = {}

local WOLF = { exists = true, dead = false, inCombat = false, family = "Wolf", happiness = "happy", powerKind = 2 }

local function has(list, name)
    for _, v in ipairs(list) do if v == name then return true end end
    return false
end

-- Snapshot ----------------------------------------------------------------

tests["pet snapshot: a map field, nil when not read"] = function(t)
    local kind
    for _, f in ipairs(R.SNAPSHOT_FIELDS) do if f[1] == "pet" then kind = f[2] end end
    t.eq(kind, "map", "pet is a map field")
    t.eq(ns.SnapshotOf({}).pet, nil, "not given: not known")
    t.eq(ns.SnapshotOf({ pet = "wolf" }).pet, nil, "not a table: not known")
    t.eq(ns.SnapshotOf({ pet = { exists = false } }).pet, { exists = false }, "no pet is kept as said")
    local given = {}
    for k, v in pairs(WOLF) do given[k] = v end
    local s = ns.SnapshotOf({ pet = given })
    t.eq(s.pet, WOLF)
    given.dead = true
    t.eq(s.pet.dead, false, "a copy: the snapshot shares nothing")
end

tests["pet snapshot: no health or power amount is a field of it"] = function(t)
    for name in pairs(R.FROM_AMOUNT) do t.ok(name ~= "pet", name) end
    local s = ns.SnapshotOf({ pet = { exists = true, health = { 10 } } })
    t.eq(s.pet, { exists = true }, "a table inside is left out")
end

-- Driver ------------------------------------------------------------------

tests["pet read: D.Read gives client.pet() as it answered"] = function(t)
    local c = ns.make.fakeClient()
    local read = D.Read(c, { spells = {} }, {})
    t.eq(read("pet"), nil, "not known until the client says")
    c.setPet({ exists = false })
    t.eq(read("pet"), { exists = false })
    c.setPet(WOLF)
    t.eq(read("pet"), WOLF)
    t.eq(D.Read({}, { spells = {} }, {})("pet"), nil, "a client with no pet read")
end

tests["pet read: reaches the snapshot of a step, and a pack's reads name it when not given"] = function(t)
    local c = ns.make.fakeClient()
    c.setDead(false)
    local pack = { spells = {}, lists = { default = {} }, options = { reads = { "pet" } } }
    local v = D.Step(c, pack)
    t.eq(v.snapshot.pet, nil)
    t.eq(v.notRead, { "pet" }, "named as not read")
    c.setPet(WOLF)
    v = D.Step(c, pack)
    t.eq(v.snapshot.pet, WOLF)
    t.eq(v.notRead, {}, "read now")
end

-- Choose helpers ----------------------------------------------------------

local function with(pet) return { pet = pet } end

tests["pet helpers: not read is nil for all three"] = function(t)
    for _, pet in ipairs({ false, "x" }) do
        local s = with(pet or nil)
        t.eq({ R.PetUp(s), R.NoPet(s), R.PetDead(s) }, {}, tostring(pet))
    end
    local s = with({ dead = false })
    t.eq({ R.PetUp(s), R.NoPet(s), R.PetDead(s) }, {}, "exists not known")
end

tests["pet helpers: no pet"] = function(t)
    local s = with({ exists = false })
    t.eq(R.PetUp(s), false)
    t.eq(R.NoPet(s), true)
    t.eq(R.PetDead(s), false)
end

tests["pet helpers: a live pet, a dead pet, and one not known to be either"] = function(t)
    local live = with({ exists = true, dead = false })
    t.eq({ R.PetUp(live), R.NoPet(live), R.PetDead(live) }, { true, false, false })
    local dead = with({ exists = true, dead = true })
    t.eq({ R.PetUp(dead), R.NoPet(dead), R.PetDead(dead) }, { false, false, true })
    local unsure = with({ exists = true })
    t.eq(R.PetUp(unsure), nil, "alive not known: not up")
    t.eq(R.NoPet(unsure), false, "there is one")
    t.eq(R.PetDead(unsure), nil, "dead not known")
end

-- Diag --------------------------------------------------------------------

tests["pet diag: the pet's names are asked by the capture, and the read has words"] = function(t)
    for _, name in ipairs({ "UnitExists", "UnitIsDead", "UnitAffectingCombat", "UnitPowerType",
        "UnitCreatureFamily", "GetPetHappiness" }) do
        t.ok(has(ns.Diag.NAMES, name), name)
    end
    t.eq(ns.Diag.READ_WORDS.pet, "your pet")
end

tests["pet diag: a pack whose pet is not read says so in the rotation line"] = function(t)
    local v = { pack = true, snapshot = { dead = false, inCombat = false }, lockdown = false,
        keys = { ok = true, ops = {} }, unread = {}, missing = {}, passed = {}, notRead = { "pet" },
        trace = { { step = "farOpener", result = "skip", note = "no enemy targeted" } } }
    v.why = D.Why(v.snapshot, v.trace, v.keys, v.lockdown)
    t.eq(ns.Diag.RotationLine("started", v, true),
        "rotation: nothing to suggest (no enemy targeted; not read: your pet).")
end

return tests
