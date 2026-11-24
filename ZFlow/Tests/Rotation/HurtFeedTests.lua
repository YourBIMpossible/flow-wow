local _, ns = ...
-- G26 (CAPABILITY-RECONCILE 2026-11-24): the self-heal step reads hurt,
-- Flow's estimate in seconds of being hit, but nothing fed it, so a heal
-- was suggested only on the game's low-health warning. The driver now
-- keeps the estimate the way Flow did (Modules/Rotation/Engine.lua:215,
-- :277-283): up while in a fight, by how much an enemy is on you (no
-- client read of that, so Flow's own "the game won't say" rate, 0.5); down
-- out of a fight; at least 40 while the low-health warning is on; 0 to 60;
-- 0 when dead. The read gets it as a whole number of seconds. Suggest only:
-- nothing is cast here. Not run: no Lua on this machine. Not tested in game.
--
-- Fails before: D.StepHurt is nil and the snapshot's hurt is always nil.
local tests = {}
local D = ns.RotationDriver

local CLASS = "TESTCLASS"
local MEND = 5185

local function pack()
    return {
        spells = { Mend = { evidence = "test" } },
        lists = { default = {} },
        heals = { self = { "Mend" }, hots = {}, lingers = {} },
        keys = { none = { key = "Mend" } },
    }
end

local function client()
    local c = ns.make.fakeClient()
    c.setSpellId("Mend", MEND)
    c.setSpell(MEND, { known = true, usable = true, noPower = false })
    c.setSpellCooldown(MEND, false)
    c.setInRange(MEND, true)
    c.setDead(false)
    c.setCombat(false)
    c.setLowHealth(false)
    return c
end

local function near(t, got, want, what)
    t.ok(type(got) == "number" and math.abs(got - want) < 1e-6, what .. ": " .. tostring(got) .. " ~ " .. want)
end

tests["hurt feed: one step of Flow's estimate"] = function(t)
    t.eq(type(D.StepHurt), "function", "the step is there")
    if type(D.StepHurt) ~= "function" then return end
    near(t, D.StepHurt(0, 10, true, 0.5, false, false), 5, "in a fight, half on you, ten seconds")
    near(t, D.StepHurt(0, 10, true, 1, false, false), 10, "fully on you")
    near(t, D.StepHurt(9, 3, false, 0.5, false, false), 8, "out of a fight: a third of a second a second")
    near(t, D.StepHurt(9, 2, false, 0.5, true, false), 3, "eating: three a second")
    near(t, D.StepHurt(5, 0.2, true, 0.5, false, true), 40, "the low-health warning: at least 40")
    near(t, D.StepHurt(59, 10, true, 1, false, false), 60, "never above 60")
    near(t, D.StepHurt(1, 10, false, 0.5, false, false), 0, "never below 0")
    t.eq(D.HURT.max, 60)
    t.eq(D.HURT.unknownHit, 0.5)
end

tests["hurt feed: the read hands the snapshot the estimate given"] = function(t)
    local c = client()
    t.eq(D.Read(c, pack(), {}, nil, { hurt = 12 })("hurt"), 12)
    t.eq(D.Read(c, pack(), {}, nil, {})("hurt"), nil, "none given: not known")
    t.eq(D.Read(c, pack(), {}, nil, { hurt = "12" })("hurt"), nil, "not a number: not known")
    local v = D.Step(c, pack(), nil, nil, nil, nil, { hurt = 7 })
    t.eq(v.snapshot.hurt, 7, "into the snapshot")
end

-- The driver on a kernel, the rotation switched on.
local function start()
    local c = client()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setClass(CLASS)
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    local api = D.Declare(k, { [CLASS] = pack() })
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    k.settings:set(D.SETTING, true)
    c.advance(D.EVERY + 0.05, 1)
    return k, c, api
end

local function hurt(api) return api.view() and api.view().snapshot and api.view().snapshot.hurt end

tests["hurt feed module: out of a fight from the start, the estimate is 0"] = function(t)
    local _, c, api = start()
    c.advance(5, 50)
    t.eq(hurt(api), 0)
end

tests["hurt feed module: forty seconds in a fight is about 20, and the heal step suggests Mend"] = function(t)
    local _, c, api = start()
    c.setCombat(true)
    c.advance(41, 410)
    local h = hurt(api)
    t.ok(type(h) == "number" and h >= 20 and h <= 21, "about 20 s of hits: " .. tostring(h))
    t.eq(h, h and math.floor(h), "a whole number")
    local s = api.view().suggestion
    t.eq(s and s.spell, "Mend", "the heal is suggested at the in-fight threshold")
    t.ok(s and tostring(s.reason):find("Flow's estimate", 1, true) ~= nil, "and says it is the estimate")
end

tests["hurt feed module: the low-health warning lifts it to 40; out of the fight it falls"] = function(t)
    local _, c, api = start()
    c.setCombat(true)
    c.setLowHealth(true)
    c.advance(D.EVERY + 0.05, 1)
    t.ok((hurt(api) or 0) >= 40, "at least 40: " .. tostring(hurt(api)))
    c.setLowHealth(false)
    c.setCombat(false)
    local before = hurt(api) or 0
    c.advance(30, 300)
    local after = hurt(api) or 0
    t.ok(after <= before - 9 and after >= before - 11, "about 10 less after 30 s: " .. before .. " -> " .. after)
end

tests["hurt feed module: dead is 0; combat not known leaves it as it was"] = function(t)
    local _, c, api = start()
    c.setCombat(true)
    c.advance(20, 200)
    local was = hurt(api) or 0
    t.ok(was >= 9, "hurt from the fight: " .. was)
    c.setCombatUnknown(true)
    c.advance(10, 100)
    t.eq(hurt(api), was, "not known: no step")
    c.setCombatUnknown(false)
    c.setCombat(true)
    c.advance(D.EVERY + 0.05, 1)
    t.ok((hurt(api) or 0) <= was + 1, "the unknown time is not counted as fighting: " .. tostring(hurt(api)))
    c.setDead(true)
    c.advance(D.EVERY + 0.05, 1)
    t.eq(hurt(api), 0, "dead: 0")
end

return tests
