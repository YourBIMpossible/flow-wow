local _, ns = ...

-- Lead sections 740 and 753 (F-28, D-26): client.queued(),
-- client.acceptGroup() and client.onKeyPress(fn) on a made-up game through
-- ns.make.client(env). Not tested in game.

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

tests["onKeyPress: PreClick hook on the rotation key only; cancel stops fn (lead 753)"] = function(t)
    local hooks, other = {}, {}
    local button = { attrs = {} }
    function button:HookScript(name, fn) hooks[#hooks + 1] = { name = name, fn = fn } end
    function button:SetAttribute(k, v) self.attrs[k] = v end
    local otherButton = {}
    function otherButton:HookScript(name, fn) other[#other + 1] = name end
    local env = {}
    env[ns.id.framePrefix .. "RotationKey"] = button
    env[ns.id.framePrefix .. "Other"] = otherButton
    local c = ns.make.client(env)
    t.eq(c.onKeyPress(nil), nil, "no fn")
    local n1, n2 = 0, 0
    local cancel1 = c.onKeyPress(function() n1 = n1 + 1 end)
    local cancel2 = c.onKeyPress(function() n2 = n2 + 1; error("a bad listener") end)
    t.eq(type(cancel1), "function"); t.eq(type(cancel2), "function")
    t.eq(#hooks, 1, "hooked once"); t.eq(hooks[1].name, "PreClick"); t.eq(#other, 0, "no other button")
    hooks[1].fn(button, "LeftButton", true)
    t.eq(n1, 1); t.eq(n2, 1, "an erroring fn does not stop the others")
    cancel1()
    hooks[1].fn(button, "LeftButton", true)
    t.eq(n1, 1, "cancelled"); t.eq(n2, 2)
    t.eq(next(button.attrs), nil, "nothing set on the button")
    t.eq(ns.make.client({}).onKeyPress(function() end), nil, "no button: no hook")
end

return tests
