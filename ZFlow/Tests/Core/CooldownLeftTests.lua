local _, ns = ...
-- Lead section 404 item 2: client.spellCooldownLeft(id), the seconds left on
-- one of your spells' cooldown, or nil when not known. Built on the same
-- cooldown read as spellCooldown(); it only reads. Made-up spells and times
-- on a made-up client environment. Not tested in game.
local tests = {}

local function env(rows, now)
    local e = {}
    e.C_Spell = { GetSpellCooldown = function(id) return rows[id] end }
    e.GetTime = function() return now end
    return e
end

local function bare(rows, now)
    local e = {}
    e.GetSpellCooldown = function(id)
        local r = rows[id]
        if not r then return nil end
        return r[1], r[2], r[3] == nil and 1 or r[3]
    end
    e.GetTime = function() return now end
    return e
end

tests["cooldown left: a running cooldown gives the seconds left"] = function(t)
    local c = ns.make.client(env({ [8921] = { startTime = 100, duration = 30, isOnGCD = false } }, 110))
    t.eq(c.spellCooldownLeft(8921), 20)
    c = ns.make.client(bare({ [8921] = { 90, 30 } }, 100))
    t.eq(c.spellCooldownLeft(8921), 20, "through the bare global")
end

tests["cooldown left: ready, or the cooldown run out, gives 0"] = function(t)
    local c = ns.make.client(env({ [8921] = { startTime = 0, duration = 0, isOnGCD = false } }, 110))
    t.eq(c.spellCooldownLeft(8921), 0)
    c = ns.make.client(env({ [8921] = { startTime = 50, duration = 30, isOnGCD = false } }, 110))
    t.eq(c.spellCooldownLeft(8921), 0, "past its end is 0, never below")
end

tests["cooldown left: not known is nil, never 0"] = function(t)
    local c = ns.make.client(env({}, 110))
    t.eq(c.spellCooldownLeft(8921), nil, "no such spell")
    t.eq(c.spellCooldownLeft("8921"), nil, "not an id")
    c = ns.make.client({})
    t.eq(c.spellCooldownLeft(8921), nil, "no cooldown call")
    c = ns.make.client(bare({ [8921] = { 0, 30, 0 } }, 110))
    t.eq(c.spellCooldownLeft(8921), nil, "waiting to start")
    local e = env({ [8921] = { startTime = 100, duration = 30, isOnGCD = false } }, 110)
    e.GetTime = nil
    t.eq(ns.make.client(e).spellCooldownLeft(8921), nil, "no clock")
end

tests["cooldown left: a secret answer is nil"] = function(t)
    local e = env({ [8921] = { startTime = 100, duration = 30, isOnGCD = false } }, 110)
    e.issecretvalue = function(v) return v == 30 end
    t.eq(ns.make.client(e).spellCooldownLeft(8921), nil)
end

tests["fake: spellCooldownLeft gives what was set; never set is nil"] = function(t)
    local c = ns.make.fakeClient()
    t.eq(c.spellCooldownLeft(8921), nil)
    c.setSpellCooldownLeft(8921, 12)
    t.eq(c.spellCooldownLeft(8921), 12)
    c.setSpellCooldownLeft(8921, nil)
    t.eq(c.spellCooldownLeft(8921), nil)
end

return tests
