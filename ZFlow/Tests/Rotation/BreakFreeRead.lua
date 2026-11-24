local _, ns = ...
-- Capability row G25 (lead section 404 item 4): break free fires in game.
-- The rule (Rotation/Choose.lua, breakFree) reads s.loc; until now nothing
-- filled it. client.heldBy() reads the client's loss-of-control list and
-- the driver hands it to the rule as loc. Made-up spells, packs and client
-- answers; not tested in game.
local tests = {}

local D = ns.RotationDriver

local function env(rows)
    return { C_LossOfControl = {
        GetActiveLossOfControlDataCount = function() return #rows end,
        GetActiveLossOfControlData = function(i) return rows[i] end,
    } }
end

tests["held: the client gives the kind of the hold"] = function(t)
    t.eq(ns.make.client(env({ { locType = "ROOT" } })).heldBy(), "ROOT")
    t.eq(ns.make.client(env({ { locType = "SCHOOL_INTERRUPT" }, { locType = "STUN" } })).heldBy(), "STUN",
        "a locked school is not a hold on you; the next one is")
end

tests["held: an empty list is not held"] = function(t)
    t.eq(ns.make.client(env({})).heldBy(), false)
    t.eq(ns.make.client(env({ { locType = "SCHOOL_INTERRUPT" } })).heldBy(), false)
end

tests["held: not known is nil, never not held"] = function(t)
    t.eq(ns.make.client({}).heldBy(), nil, "no such read")
    local e = env({ { locType = "ROOT" } })
    e.C_LossOfControl.GetActiveLossOfControlDataCount = function() error("refused") end
    t.eq(ns.make.client(e).heldBy(), nil, "a failed count")
    e = env({ { locType = "ROOT" } })
    e.issecretvalue = function(v) return v == "ROOT" end
    t.eq(ns.make.client(e).heldBy(), nil, "a secret kind")
    t.eq(ns.make.client(env({ "odd" })).heldBy(), nil, "an odd row")
end

tests["held: the fake gives what was set; never set is nil"] = function(t)
    local c = ns.make.fakeClient()
    t.eq(c.heldBy(), nil)
    c.setHeldBy("FEAR"); t.eq(c.heldBy(), "FEAR")
    c.setHeldBy(false); t.eq(c.heldBy(), false)
end

tests["held: the driver hands the hold to the rule as loc"] = function(t)
    local c = ns.make.fakeClient()
    local r = D.Read(c, {}, {}, nil, {})
    t.eq(r("loc"), nil, "not known")
    c.setHeldBy("ROOT"); t.eq(r("loc"), "ROOT")
    c.setHeldBy(false); t.eq(r("loc"), nil, "not held: the rule reads no hold")
    c.heldBy = function() error("read failed") end
    t.eq(r("loc"), nil, "a failed read")
end

tests["held: a root reaches the break-free rule"] = function(t)
    local pack = { lists = { default = {} },
        breakers = { { spell = "Slip", evidence = "first guess", types = { ROOT = true } } } }
    local c = ns.make.fakeClient()
    c.setHeldBy("ROOT")
    local s = { dead = false, inCombat = true, loc = D.Read(c, {}, {}, nil, {})("loc"),
        spells = { Slip = { known = true, onCooldown = false, inRange = true } } }
    local pick = ns.Choose(s, pack)
    t.eq(pick and pick.spell, "Slip")
    t.eq(pick and pick.kind, "emergency")
end

return tests
