-- N2 and N20 (P-KEYS slice D): the two reads the rotation key's actions
-- lean on, the real client over a hand-built environment, then
-- ClientFake's own twin. Read only: nothing is asked of the client but
-- these reads. First guesses: none of these reads was seen in game.
--   c.targetCorpse() -> nil | { exists = false }
--                     | { exists = true, dead, player, lootable, needs }
--   N20 reads the N24 c.tradeSkillTools(index) (ClientProfReadsTests).
local _, ns = ...

local tests = {}

-- A dead beast targeted, already looted, its tooltip saying Skinnable.
local function corpseEnv(extra)
    local env = { asked = {} }
    local function note(name) env.asked[#env.asked + 1] = name end
    env.UnitExists = function(unit) note(unit) return true end
    env.UnitIsDead = function(unit) note(unit) return true end
    env.UnitIsPlayer = function(unit) note(unit) return false end
    env.UnitGUID = function(unit) note(unit) return "Creature-0-1-2-3-4-5" end
    env.CanLootUnit = function(guid) note(guid) return false, true end
    env.C_TooltipInfo = { GetUnit = function(unit)
        note(unit)
        return { lines = { { leftText = "Young Wolf" }, { leftText = "Beast" }, { leftText = "Skinnable" } } }
    end }
    for k, v in pairs(extra or {}) do env[k] = v end
    return env
end

local function tipWith(text)
    return { GetUnit = function() return { lines = { { leftText = "Young Wolf" }, { leftText = text } } } end }
end

tests["c.targetCorpse: a looted skinnable beast, each field as the client gave it"] = function(t)
    local env = corpseEnv()
    t.eq(ns.make.client(env).targetCorpse(),
        { exists = true, dead = true, player = false, lootable = false, needs = "Skinning" })
    for _, unit in ipairs(env.asked) do
        t.ok(unit == "target" or unit == "Creature-0-1-2-3-4-5", "only the target is asked about: " .. tostring(unit))
    end
end

tests["c.targetCorpse: the profession the tooltip names"] = function(t)
    local function needs(text)
        return ns.make.client(corpseEnv({ C_TooltipInfo = tipWith(text) })).targetCorpse().needs
    end
    t.eq(needs("Requires Herbalism"), "Herbalism")
    t.eq(needs("Requires Mining"), "Mining")
    t.eq(needs("Requires Engineering"), "Engineering")
    t.eq(needs("Elite"), nil, "nothing to gather")
end

tests["c.targetCorpse: loot still on it"] = function(t)
    local got = ns.make.client(corpseEnv({ CanLootUnit = function() return true, true end })).targetCorpse()
    t.eq(got.lootable, true)
end

tests["c.targetCorpse: no target is { exists = false }, and nothing more is asked"] = function(t)
    local asked = 0
    local env = corpseEnv({ UnitExists = function() return false end })
    env.UnitIsDead = function() asked = asked + 1 return true end
    env.CanLootUnit = function() asked = asked + 1 return true end
    t.eq(ns.make.client(env).targetCorpse(), { exists = false })
    t.eq(asked, 0)
end

tests["c.targetCorpse: a read that fails or gives an odd answer is not known, never false"] = function(t)
    t.eq(ns.make.client(corpseEnv({ UnitExists = function() error("no") end })).targetCorpse(), nil)
    local got = ns.make.client(corpseEnv({
        UnitIsDead = function() return "yes" end,
        CanLootUnit = function() error("no") end,
        C_TooltipInfo = { GetUnit = function() error("no") end },
    })).targetCorpse()
    t.eq(got.exists, true)
    t.eq(got.dead, nil)
    t.eq(got.lootable, nil)
    t.eq(got.needs, nil)
    local bare = corpseEnv()
    bare.CanLootUnit, bare.C_TooltipInfo = nil, nil
    t.eq(ns.make.client(bare).targetCorpse().lootable, nil, "no such call")
end

tests["fake client: targetCorpse is the twin of the real read"] = function(t)
    local c = ns.make.fakeClient()
    t.eq(c.targetCorpse(), nil, "not known until set")
    c.setTargetCorpse({ exists = true, dead = true, player = false, lootable = false, needs = "Skinning" })
    local got = c.targetCorpse()
    t.eq(got.needs, "Skinning")
    got.needs = "Mining"
    t.eq(c.targetCorpse().needs, "Skinning", "a copy")
    c.setTargetCorpseFails(true)
    t.ok(not pcall(c.targetCorpse), "the read raises while failing")
    c.setTargetCorpseFails(false)
    t.eq(c.targetCorpse().needs, "Skinning", "recovers")
end

return tests
