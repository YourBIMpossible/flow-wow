-- The pet read (lead section 197, the shared pet-state contract): the real
-- client over a hand-built environment, then ClientFake's own twin. Read
-- only: no pet command is asked of the client.
--   c.pet() -> nil | { exists = false }
--            | { exists = true, dead, inCombat, family, happiness, powerKind }
-- nil is "not known", never "no pet". Every field is nil when not known,
-- never false, 0 or "".
local _, ns = ...

local tests = {}

-- A hunter's wolf, alive, out of a fight, content, on focus-free mana (2).
-- `asked` keeps every unit asked about, in order.
local function petEnv(extra)
    local env = { asked = {} }
    local function note(unit) env.asked[#env.asked + 1] = unit end
    env.UnitExists = function(unit) note(unit) return unit == "pet" end
    env.UnitIsDead = function(unit) note(unit) return false end
    env.UnitAffectingCombat = function(unit) note(unit) return false end
    env.UnitCreatureFamily = function(unit) note(unit) return "Wolf" end
    env.GetPetHappiness = function() return 2 end
    env.UnitPowerType = function(unit) note(unit) return 2 end
    for k, v in pairs(extra or {}) do env[k] = v end
    return env
end

tests["c.pet: a pet that is out, each field as the client gave it"] = function(t)
    local env = petEnv()
    t.eq(ns.make.client(env).pet(), {
        exists = true, dead = false, inCombat = false, family = "Wolf", happiness = "content", powerKind = 2,
    })
    for _, unit in ipairs(env.asked) do t.eq(unit, "pet", "only the pet is asked about") end
end

tests["c.pet: happiness 1 to 3 in words; anything else not known"] = function(t)
    local words = { "unhappy", "content", "happy" }
    for n, word in ipairs(words) do
        local env = petEnv({ GetPetHappiness = function() return n end })
        t.eq(ns.make.client(env).pet().happiness, word, "happiness " .. n)
    end
    for _, odd in ipairs({ 0, 4, 1.5, "1", true }) do
        local env = petEnv({ GetPetHappiness = function() return odd end })
        t.eq(ns.make.client(env).pet().happiness, nil, "not a mood: " .. tostring(odd))
    end
    t.eq(ns.make.client(petEnv({ GetPetHappiness = function() return nil end })).pet().happiness, nil,
        "a demon: no happiness")
    t.eq(ns.make.client(petEnv({ GetPetHappiness = function() return 0 / 0 end })).pet().happiness, nil, "NaN")
end

tests["c.pet: no pet is { exists = false }, and nothing more is asked"] = function(t)
    local env = petEnv({ UnitExists = function() return false end })
    local asked = 0
    env.UnitIsDead = function() asked = asked + 1 return true end
    env.GetPetHappiness = function() asked = asked + 1 return 1 end
    t.eq(ns.make.client(env).pet(), { exists = false })
    t.eq(asked, 0, "no second question with no pet")
end

tests["c.pet: nil when whether there is a pet is not known"] = function(t)
    t.eq(ns.make.client({}).pet(), nil, "no reads at all")
    t.eq(ns.make.client(petEnv({ UnitExists = function() error("no") end })).pet(), nil, "raised")
    t.eq(ns.make.client(petEnv({ UnitExists = function() return nil end })).pet(), nil, "no answer")
    t.eq(ns.make.client(petEnv({ UnitExists = function() return 1 end })).pet(), nil, "not a yes or no")
    local secret = petEnv({ issecretvalue = function(v)
        if v == nil then error("issecretvalue: nil") end
        return v == true
    end })
    t.eq(ns.make.client(secret).pet(), nil, "the answer to exists is secret")
end

tests["c.pet: a field not known is nil, never false, 0 or empty"] = function(t)
    local env = petEnv({
        UnitIsDead = function() error("no") end,
        UnitAffectingCombat = function() return nil end,
        UnitCreatureFamily = function() return "" end,
        UnitPowerType = function() return "MANA" end,
    })
    env.GetPetHappiness = nil
    t.eq(ns.make.client(env).pet(), { exists = true })
    local missing = petEnv()
    missing.UnitIsDead, missing.UnitAffectingCombat, missing.UnitCreatureFamily = nil, nil, nil
    missing.UnitPowerType, missing.GetPetHappiness = nil, nil
    t.eq(ns.make.client(missing).pet(), { exists = true }, "reads the client does not have")
end

tests["c.pet: a secret field is nil; issecretvalue refusing nil breaks nothing"] = function(t)
    local env = petEnv({
        UnitCreatureFamily = function() return nil end,
        GetPetHappiness = function() return nil end,
        issecretvalue = function(v)
            if v == nil then error("issecretvalue: nil") end
            return v == 2 or v == false
        end,
    })
    t.eq(ns.make.client(env).pet(), { exists = true },
        "dead and inCombat (false), happiness and power (2) secret; family not given")
end

tests["c.pet: only reads; no pet command is called"] = function(t)
    local env = petEnv()
    local called = 0
    for _, name in ipairs({ "CastPetAction", "PetAttack", "PetFollow", "PetPassiveMode", "CastSpellByName" }) do
        env[name] = function() called = called + 1 end
    end
    ns.make.client(env).pet()
    t.eq(called, 0)
end

tests["fake client: the pet is not known until set; a copy each time"] = function(t)
    local c = ns.make.fakeClient()
    t.eq(c.pet(), nil, "not known at the start")
    c.setPet({ exists = false, dead = true, family = "Wolf" })
    t.eq(c.pet(), { exists = false }, "no pet: nothing more")
    c.setPet({ exists = true, dead = false, inCombat = true, family = "Cat", happiness = "unhappy", powerKind = 2 })
    t.eq(c.pet(), { exists = true, dead = false, inCombat = true, family = "Cat", happiness = "unhappy", powerKind = 2 })
    local got = c.pet()
    got.dead = true
    t.eq(c.pet().dead, false, "a copy each time")
    c.setPet({ exists = true, dead = "no", inCombat = 1, family = "", happiness = "glum", powerKind = "MANA" })
    t.eq(c.pet(), { exists = true }, "odd fields are not known")
    c.setPet(nil)
    t.eq(c.pet(), nil, "taken back: not known")
    c.setPet({ dead = false })
    t.eq(c.pet(), nil, "exists not given: not known")
end

return tests
