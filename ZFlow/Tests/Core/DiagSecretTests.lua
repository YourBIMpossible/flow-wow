-- Diag and secret values (L6-R). On this client the player's health is a
-- "secret" value: comparing it, or doing arithmetic on it, raises ("attempt
-- to compare ... a secret number value, while execution tainted by ..."),
-- and Diag's health probe did compare it. Diag now asks issecretvalue first
-- and records "secret" in place of the value: no compare, no arithmetic, no
-- tostring, and the value is never written into the snapshot.
--
-- The fake secret here is a table whose every operator raises. Lua 5.1 has
-- no way to make a plain number raise, and comparing one object with itself
-- never reaches a metamethod, so the tests check what was recorded: the
-- word "secret" and no value.
local _, ns = ...

local Diag = ns.Diag
local tests = {}

local function boom(what)
    return function() error("touched a secret value: " .. what, 0) end
end

local function secret()
    return setmetatable({}, {
        __tostring = boom("tostring"), __add = boom("add"), __sub = boom("sub"), __mul = boom("mul"),
        __div = boom("div"), __lt = boom("lt"), __le = boom("le"), __eq = boom("eq"), __concat = boom("concat"),
        __len = boom("len"), __index = boom("index"), __call = boom("call"),
    })
end

-- A kernel over a fake client whose game answers come from env.
local function kernel(env)
    local c = ns.make.fakeClient({ env = env })
    c.setSaved(ns.id.accountDB, {})
    return ns.Kernel({}, c), c
end

tests["diag secret: IsSecret asks the client, and 'will not say' counts as secret"] = function(t)
    local s = secret()
    local k = kernel({ issecretvalue = function(v) return v == nil and false or rawequal(v, s) end })
    t.eq(Diag.IsSecret(k.client, s), true)
    t.eq(Diag.IsSecret(k.client, 5), false)
    t.eq(Diag.IsSecret(k.client, nil), false, "nil is never asked about: the client raises on it")
    local none = kernel({})
    t.eq(Diag.IsSecret(none.client, s), false, "a client with no issecretvalue has no secret values")
    local raises = kernel({ issecretvalue = function() error("no") end })
    t.eq(Diag.IsSecret(raises.client, 5), true, "a client that will not say: treated as secret")
    local odd = kernel({ issecretvalue = function() return "yes" end })
    t.eq(Diag.IsSecret(odd.client, 5), true, "any answer but false: secret")
end

tests["diag secret: a shape records 'secret' and no value"] = function(t)
    local s = secret()
    local function isSecret(v) return rawequal(v, s) end
    local row = Diag.ShapeWith(isSecret, true, s, 5, "x")
    t.eq(row.types, { "secret", "number", "string" })
    t.eq(row.values, { v2 = 5, v3 = "x" }, "the secret one has no value entry")
    t.eq(row.ok, true)
    t.eq(row.n, 3)
    local inTable = Diag.ShapeWith(isSecret, true, { hp = s, name = "a", n = 2 })
    t.eq(inTable.values.v1, { hp = "secret", name = "a", n = 2 }, "inside a table answer too")
    t.eq(Diag.Shape(true, 5).values, { v1 = 5 }, "the plain shape is unchanged")
end

tests["diag secret: the health probe never compares, adds or prints a secret health"] = function(t)
    local s = secret()
    local k = kernel({
        UnitHealth = function() return s end,
        UnitHealthMax = function() return s end,
        issecretvalue = function(v) return rawequal(v, s) end,
    })
    local ok, snap = pcall(Diag.Collect, k, "test")
    t.ok(ok, "collecting raised: " .. tostring(snap))
    local S = snap.shapes
    t.eq(S.health.types, { "secret" }, "the health answer is recorded as secret")
    t.eq(S.health.values, {}, "with no value")
    t.eq(S.healthMax.types, { "secret" })
    t.eq(S.healthSecret.values.v1, true, "the client said it is one")
    t.eq(S.healthText, { ok = true, n = 1, types = { "secret" }, values = {} }, "not printed")
    t.eq(S.healthIsItself, { ok = true, n = 1, types = { "secret" }, values = {} }, "not compared")
    for name, row in pairs(S) do
        if type(row) == "table" and type(row.values) == "table" then
            t.ok(row.values.v1 == nil or not tostring(row.values.v1):find("touched a secret value", 1, true),
                name .. " did not touch the secret")
        end
    end
end

tests["diag secret: a client that will not say is treated the same"] = function(t)
    local s = secret()
    local k = kernel({
        UnitHealth = function() return s end,
        issecretvalue = function() error("refused") end,
    })
    local ok, snap = pcall(Diag.Collect, k, "test")
    t.ok(ok, "collecting raised: " .. tostring(snap))
    t.eq(snap.shapes.healthIsItself.types, { "secret" })
    t.eq(snap.shapes.healthText.types, { "secret" })
end

tests["diag secret: with no secret values the probe reads as before"] = function(t)
    local k = kernel({ UnitHealth = function() return 100 end, UnitHealthMax = function() return 120 end })
    local snap = Diag.Collect(k, "test")
    local S = snap.shapes
    t.eq(S.health.values, { v1 = 100 })
    t.eq(S.healthMax.values, { v1 = 120 })
    t.eq(S.healthText.values, { v1 = "100" })
    t.eq(S.healthIsItself.values, { v1 = true })
    local known = kernel({ UnitHealth = function() return 100 end, issecretvalue = function() return false end })
    t.eq(Diag.Collect(known, "test").shapes.healthIsItself.values, { v1 = true }, "a client that says 'not secret': the same")
end

tests["diag secret: nothing secret is written into saved data"] = function(t)
    local s = secret()
    local k = kernel({ UnitHealth = function() return s end, issecretvalue = function(v) return rawequal(v, s) end })
    local snap = Diag.Collect(k, "test")
    local function holds(v, seen)
        if rawequal(v, s) then return true end
        if type(v) ~= "table" or seen[v] then return false end
        seen[v] = true
        for key, x in next, v do
            if holds(key, seen) or holds(x, seen) then return true end
        end
        return false
    end
    t.eq(holds(snap, {}), false, "the secret value itself is nowhere in the snapshot")
end

return tests
