-- target() and inRange(): what the client says about your target, and
-- whether one of your spells reaches it. Both only read, and name no unit
-- but "player" and "target". The real client over a hand-built
-- environment (`env` stands in for the game's globals), then the fake.
local _, ns = ...

local MOONFIRE = 8921

local function boom() error("the client refused") end

-- issecretvalue that refuses nil, as the client's does.
local function strictSecret(env, secret)
    env.issecretvalue = function(v)
        if v == nil then error("issecretvalue: nil") end
        return secret ~= nil and secret(v) or false
    end
end

-- A client with a target: `say` holds the three answers and can be changed
-- between reads. `asked` lists every unit the client was asked about.
local function targetEnv(say)
    local env = { asked = {} }
    local function note(...)
        for i = 1, select("#", ...) do env.asked[#env.asked + 1] = (select(i, ...)) end
    end
    env.UnitExists = function(...) note(...) return say.exists end
    env.UnitCanAttack = function(...) note(...) return say.hostile end
    env.UnitIsDead = function(...) note(...) return say.dead end
    return env
end

-- A client whose C_Spell.IsSpellInRange answers `say.inRange`.
local function rangeEnv(say)
    local env = { calls = {} }
    env.C_Spell = {
        IsSpellInRange = function(...)
            env.calls[#env.calls + 1] = { n = select("#", ...), ... }
            return say.inRange
        end,
    }
    return env
end

return {
    -- ------------------------------------------------------------- target
    ["target() gives exists, hostile and dead as the client says"] = function(t)
        local say = { exists = true, hostile = true, dead = false }
        local c = ns.make.client(targetEnv(say))
        local r = c.target()
        t.eq(type(r), "table")
        t.eq(r.exists, true)
        t.eq(r.hostile, true)
        t.eq(r.dead, false)
        say.hostile, say.dead = false, true
        r = c.target()
        t.eq(r.exists, true)
        t.eq(r.hostile, false)
        t.eq(r.dead, true)
    end,

    ["target() with no target says so, and asks nothing more"] = function(t)
        local say = { exists = false, hostile = true, dead = true }
        local env = targetEnv(say)
        local r = ns.make.client(env).target()
        t.eq(type(r), "table")
        t.eq(r.exists, false)
        t.eq(r.hostile, nil, "nothing is said about a target that is not there")
        t.eq(r.dead, nil)
        t.eq(#env.asked, 1, "only UnitExists was called")
    end,

    ["target() is nil when the client does not say whether there is a target"] = function(t)
        local say = { exists = true, hostile = true, dead = false }
        local env = targetEnv(say)
        local c = ns.make.client(env)
        say.exists = nil
        t.eq(c.target(), nil, "no answer is not 'no target'")
        say.exists = 1
        t.eq(c.target(), nil, "a number is not an answer")
        say.exists = "yes"
        t.eq(c.target(), nil, "a string is not an answer")
        say.exists = true
        strictSecret(env, function(v) return v == true end)
        t.eq(c.target(), nil, "a secret answer")
        strictSecret(env)
        t.eq(c.target().exists, true)
        env.UnitExists = boom
        t.eq(c.target(), nil, "the call fails")
        env.UnitExists = nil
        t.eq(c.target(), nil, "no call")
    end,

    ["target() leaves hostile not known when the client does not say"] = function(t)
        local say = { exists = true, hostile = nil, dead = false }
        local env = targetEnv(say)
        local c = ns.make.client(env)
        t.eq(c.target().hostile, nil, "no answer is not 'friendly'")
        t.eq(c.target().dead, false, "the other answer still stands")
        say.hostile = 1
        t.eq(c.target().hostile, nil, "a number")
        say.hostile = true
        strictSecret(env, function() return true end)
        t.eq(c.target(), nil, "all secret: exists is not known either")
        strictSecret(env)
        env.UnitCanAttack = boom
        t.eq(c.target().hostile, nil, "the call fails")
        t.eq(c.target().exists, true)
        env.UnitCanAttack = nil
        t.eq(c.target().hostile, nil, "no call")
    end,

    ["target() leaves dead not known when the client does not say"] = function(t)
        local say = { exists = true, hostile = true, dead = nil }
        local env = targetEnv(say)
        local c = ns.make.client(env)
        t.eq(c.target().dead, nil, "no answer is not 'alive'")
        t.eq(c.target().hostile, true, "the other answer still stands")
        say.dead = 0
        t.eq(c.target().dead, nil, "a number")
        say.dead = "no"
        t.eq(c.target().dead, nil, "a string")
        env.UnitIsDead = boom
        t.eq(c.target().dead, nil, "the call fails")
        env.UnitIsDead = nil
        t.eq(c.target().dead, nil, "no call")
    end,

    ["target() keeps a secret hostile or dead answer as not known"] = function(t)
        local say = { exists = true, hostile = false, dead = false }
        local env = targetEnv(say)
        local c = ns.make.client(env)
        -- false is secret, true is not: exists is read, the other two are not.
        strictSecret(env, function(v) return v == false end)
        local r = c.target()
        t.eq(r.exists, true)
        t.eq(r.hostile, nil)
        t.eq(r.dead, nil)
    end,

    ["target() asks about no unit but player and target"] = function(t)
        local say = { exists = true, hostile = true, dead = false }
        local env = targetEnv(say)
        ns.make.client(env).target()
        t.ok(#env.asked >= 3, "the three calls were made")
        for _, unit in ipairs(env.asked) do
            t.ok(unit == "player" or unit == "target", "asked about " .. tostring(unit))
        end
    end,

    ["target() gives a new table each time"] = function(t)
        local c = ns.make.client(targetEnv({ exists = true, hostile = true, dead = false }))
        local a = c.target()
        a.hostile = false
        t.eq(c.target().hostile, true)
    end,

    -- ------------------------------------------------------------ inRange
    ["inRange() is true or false as the client says, and nil when it does not say"] = function(t)
        local say = { inRange = true }
        local env = rangeEnv(say)
        local c = ns.make.client(env)
        t.eq(c.inRange(MOONFIRE), true)
        say.inRange = false
        t.eq(c.inRange(MOONFIRE), false)
        say.inRange = nil
        t.eq(c.inRange(MOONFIRE), nil, "no answer is not 'out of range'")
        say.inRange = 1
        t.eq(c.inRange(MOONFIRE), nil, "a number is not an answer")
        say.inRange = 0
        t.eq(c.inRange(MOONFIRE), nil, "0 is not 'out of range'")
        say.inRange = "yes"
        t.eq(c.inRange(MOONFIRE), nil, "a string is not an answer")
        say.inRange = true
        strictSecret(env, function(v) return v == true end)
        t.eq(c.inRange(MOONFIRE), nil, "a secret answer")
        strictSecret(env)
        t.eq(c.inRange(MOONFIRE), true)
        env.C_Spell.IsSpellInRange = boom
        t.eq(c.inRange(MOONFIRE), nil, "the call fails")
        env.C_Spell.IsSpellInRange = nil
        t.eq(c.inRange(MOONFIRE), nil, "no call")
        env.C_Spell = nil
        t.eq(c.inRange(MOONFIRE), nil, "no C_Spell")
    end,

    ["inRange() asks about the spell id and the target, nothing else"] = function(t)
        local env = rangeEnv({ inRange = true })
        t.eq(ns.make.client(env).inRange(MOONFIRE), true)
        t.eq(#env.calls, 1)
        t.eq(env.calls[1].n, 2)
        t.eq(env.calls[1][1], MOONFIRE)
        t.eq(env.calls[1][2], "target")
    end,

    ["inRange() does not ask the client about something that is not a spell id"] = function(t)
        local env = rangeEnv({ inRange = true })
        local c = ns.make.client(env)
        t.eq(c.inRange(nil), nil)
        t.eq(c.inRange("8921"), nil)
        t.eq(c.inRange({}), nil)
        t.eq(c.inRange(true), nil)
        t.eq(#env.calls, 0, "the client was not asked")
    end,

    -- --------------------------------------------------------------- fake
    ["fake: target() is nil until set"] = function(t)
        local c = ns.make.fakeClient()
        t.eq(c.target(), nil)
        c.setTarget({ exists = true, hostile = true, dead = false })
        local r = c.target()
        t.eq(r.exists, true)
        t.eq(r.hostile, true)
        t.eq(r.dead, false)
        c.setTarget({ exists = true })
        r = c.target()
        t.eq(r.exists, true)
        t.eq(r.hostile, nil, "a field left out is not known")
        t.eq(r.dead, nil)
        c.setTarget(nil)
        t.eq(c.target(), nil)
    end,

    ["fake: no target carries nothing else, as the real client's does"] = function(t)
        local c = ns.make.fakeClient()
        c.setTarget({ exists = false, hostile = true, dead = true })
        local r = c.target()
        t.eq(r.exists, false)
        t.eq(r.hostile, nil)
        t.eq(r.dead, nil)
    end,

    ["fake: target() gives a copy, and keeps none of the table it was set from"] = function(t)
        local c = ns.make.fakeClient()
        local set = { exists = true, hostile = true, dead = false }
        c.setTarget(set)
        set.hostile = false
        t.eq(c.target().hostile, true)
        c.target().hostile = false
        t.eq(c.target().hostile, true)
    end,

    ["fake: inRange() is nil until set, one spell at a time"] = function(t)
        local c = ns.make.fakeClient()
        t.eq(c.inRange(MOONFIRE), nil)
        c.setInRange(MOONFIRE, true)
        t.eq(c.inRange(MOONFIRE), true)
        t.eq(c.inRange(5176), nil, "another spell is still not known")
        c.setInRange(MOONFIRE, false)
        t.eq(c.inRange(MOONFIRE), false)
        c.setInRange(MOONFIRE, nil)
        t.eq(c.inRange(MOONFIRE), nil)
        t.eq(c.inRange("8921"), nil)
        t.eq(c.inRange(nil), nil)
    end,
}
