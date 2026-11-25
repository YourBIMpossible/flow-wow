local _, ns = ...

-- Lead section 740 (F-28): client.queued() and client.acceptGroup() on a
-- made-up game through ns.make.client(env). Not tested in game.

local tests = {}

tests["queued: a battleground or finder queue is true; no answer is unknown (lead 740)"] = function(t)
    t.eq(ns.make.client({}).queued(), nil, "no queue calls: not known")
    local status = { "none", "none", "none" }
    local env = { GetBattlefieldStatus = function(i) return status[i] end }
    local c = ns.make.client(env)
    t.eq(c.queued(), false, "every slot none: not queued")
    status[2] = "queued"
    t.eq(c.queued(), true, "a battleground queue")
    status[2] = "confirm"
    t.eq(c.queued(), true, "a battleground ready to enter")
    status[2] = "active"
    t.eq(c.queued(), false, "inside a battleground is not a queue")
    local mode = nil
    local lfg = ns.make.client({ LE_LFG_CATEGORY_LFD = 1, GetLFGMode = function() return mode end })
    t.eq(lfg.queued(), false, "finder answers no mode")
    mode = "rolecheck"
    t.eq(lfg.queued(), true, "a role check")
    mode = "lfgparty"
    t.eq(lfg.queued(), false, "in the finder's group, not queued")
    local broken = ns.make.client({ GetBattlefieldStatus = function() error("no") end })
    t.eq(broken.queued(), nil, "an erroring read is not known")
end

tests["acceptGroup: calls AcceptGroup only, and says whether it went through (lead 740)"] = function(t)
    local calls = 0
    local c = ns.make.client({ AcceptGroup = function() calls = calls + 1 end })
    t.eq(c.acceptGroup(), true); t.eq(calls, 1)
    t.eq(ns.make.client({}).acceptGroup(), false, "no AcceptGroup")
    t.eq(ns.make.client({ AcceptGroup = function() error("no") end }).acceptGroup(), false, "an error")
end

return tests
