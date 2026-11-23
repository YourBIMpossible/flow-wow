-- S12 care key (P-KEYS slice A): the unit read the care key leans on, the
-- real client over a hand-built environment, then ClientFake's own twin.
-- Read only: nothing is asked of the client but these reads.
--   c.unitCare(unit) -> nil | { exists = false }
--                     | { exists = true, friend, isSelf, dead, hurt }
-- nil is "not known". Every field is nil when not known, never false. hurt
-- is a yes or no only; no health amount is kept or handed on. A first
-- guess: none of these reads was seen in game.
local _, ns = ...

local tests = {}

-- A friendly party member, alive, at half health. `asked` keeps every unit
-- asked about, in order.
local function careEnv(extra)
    local env = { asked = {} }
    local function note(unit) env.asked[#env.asked + 1] = unit end
    env.UnitExists = function(unit) note(unit) return true end
    env.UnitIsFriend = function(a, b) note(b) return true end
    env.UnitIsUnit = function(a, b) note(a) return false end
    env.UnitIsDead = function(unit) note(unit) return false end
    env.UnitHealth = function(unit) note(unit) return 50 end
    env.UnitHealthMax = function(unit) note(unit) return 100 end
    for k, v in pairs(extra or {}) do env[k] = v end
    return env
end

tests["c.unitCare: a hurt friend, each field as the client gave it"] = function(t)
    local env = careEnv()
    t.eq(ns.make.client(env).unitCare("party1"),
        { exists = true, friend = true, isSelf = false, dead = false, hurt = true })
    for _, unit in ipairs(env.asked) do t.eq(unit, "party1", "only that unit is asked about") end
end

tests["c.unitCare: full health is not hurt; no amount is handed on"] = function(t)
    local got = ns.make.client(careEnv({ UnitHealth = function() return 100 end })).unitCare("target")
    t.eq(got.hurt, false)
    for key, value in pairs(got) do t.ok(type(value) == "boolean", "a yes or no only: " .. key) end
end

tests["c.unitCare: no amount read, the share is asked (a first guess)"] = function(t)
    local function with(share)
        return ns.make.client(careEnv({
            UnitHealth = function() return nil end,
            UnitHealthPercent = function() return share end,
        })).unitCare("party2").hurt
    end
    t.eq(with(0.5), true, "a share of 1")
    t.eq(with(1), false, "whole")
    t.eq(with(40), true, "a share of 100")
    t.eq(with(100), false)
    t.eq(with(nil), nil, "not known")
    t.eq(with("50"), nil, "not a number")
end

tests["c.unitCare: no unit there is { exists = false }, and nothing more is asked"] = function(t)
    local env = careEnv({ UnitExists = function() return false end })
    local asked = 0
    env.UnitIsDead = function() asked = asked + 1 return true end
    env.UnitIsFriend = function() asked = asked + 1 return true end
    t.eq(ns.make.client(env).unitCare("party3"), { exists = false })
    t.eq(asked, 0)
end

tests["c.unitCare: not known stays not known"] = function(t)
    t.eq(ns.make.client({}).unitCare("target"), nil, "no reads at all")
    t.eq(ns.make.client(careEnv()).unitCare(nil), nil, "no unit")
    t.eq(ns.make.client(careEnv()).unitCare(3), nil, "not a unit name")
    local env = careEnv({
        UnitIsFriend = function() error("raised") end,
        UnitIsDead = function() return 1 end,
        UnitIsUnit = function() return nil end,
    })
    local got = ns.make.client(env).unitCare("target")
    t.eq(got, { exists = true, hurt = true }, "a raise, a 1 and a nil are each not known")
end

tests["fake c.unitCare: what was set, a copy; a read that fails, then recovers"] = function(t)
    local c = ns.make.fakeClient()
    t.eq(c.unitCare("target"), nil, "never set: not known")
    c.setUnitCare("target", { exists = true, friend = true, isSelf = false, dead = false, hurt = true })
    local got = c.unitCare("target")
    t.eq(got, { exists = true, friend = true, isSelf = false, dead = false, hurt = true })
    got.hurt = false
    t.eq(c.unitCare("target").hurt, true, "a copy")
    c.setUnitCareFails(true)
    t.eq(pcall(c.unitCare, "target"), false, "the read raises while on")
    c.setUnitCareFails(false)
    t.eq(c.unitCare("target").exists, true, "recovers")
    c.setUnitCare("target", nil)
    t.eq(c.unitCare("target"), nil)
end

return tests
