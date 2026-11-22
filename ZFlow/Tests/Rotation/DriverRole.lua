-- The role the rotation plays (F6): the driver hands the role you chose
-- (the setting spec.role) to the snapshot, when the class's pack has a part
-- for it. No talent is read. Not tested in game.
local _, ns = ...

local D = ns.RotationDriver
local Ro = ns.RotationRole
local tests = {}

local CLASS = "TESTCLASS"
local WRATH = 5176

-- A hand-written pack: two roles named, no healing part. Its one list
-- suggests Wrath only when the snapshot says tank.
local function pack()
    return {
        roles = {
            dps = { name = "Claws", evidence = "test" },
            tank = { name = "Hide", evidence = "test" },
        },
        spells = { Wrath = { evidence = "test" } },
        lists = { default = {
            { spell = "Wrath", target = true, reason = "tanking", when = function(s) return s.role == "tank" end },
        } },
        keys = { none = { key = "Wrath" } },
    }
end

local function client()
    local c = ns.make.fakeClient()
    c.setSpellId("Wrath", WRATH)
    c.setSpell(WRATH, { known = true, usable = true, noPower = false })
    c.setSpellCooldown(WRATH, false)
    c.setInRange(WRATH, true)
    c.setDead(false)
    c.target = function() return { exists = true, hostile = true, dead = false } end
    return c
end

tests["driver role: the setting it reads is the role setting"] = function(t)
    t.eq(D.ROLE, "spec.role")
    t.eq(D.ROLE, Ro.SETTING)
end

tests["driver role: the read gives a role the pack has a part for"] = function(t)
    local c = client()
    t.eq(D.Read(c, pack(), {}, "tank")("role"), "tank")
    t.eq(D.Read(c, pack(), {}, "dps")("role"), "dps")
end

tests["driver role: a role the pack has no part for is not played"] = function(t)
    local c = client()
    t.eq(D.Read(c, pack(), {}, "heal")("role"), nil)
    local p = pack()
    p.roles = {}
    t.eq(D.Read(c, p, {}, "tank")("role"), nil, "the pack names no roles")
    p.roles = nil
    t.eq(D.Read(c, p, {}, "tank")("role"), nil, "the pack has no roles table")
end

tests["driver role: nothing chosen, or a value that is no role, is not known"] = function(t)
    local c = client()
    t.eq(D.Read(c, pack(), {})("role"), nil, "not handed in")
    t.eq(D.Read(c, pack(), {}, "")("role"), nil, "nothing chosen")
    t.eq(D.Read(c, pack(), {}, "bear")("role"), nil)
    t.eq(D.Read(c, pack(), {}, true)("role"), nil)
    t.eq(D.Read(c, pack(), {}, 2)("role"), nil)
end

tests["driver role: a step with no role handed in has none in its snapshot"] = function(t)
    local v = D.Step(client(), pack())
    t.eq(v.snapshot.role, nil)
    t.eq(v.suggestion, nil, "the tank step does not hold")
end

tests["driver role: a step plays the role handed in"] = function(t)
    local v = D.Step(client(), pack(), nil, nil, nil, "tank")
    t.eq(v.snapshot.role, "tank")
    t.eq(v.suggestion and v.suggestion.spell, "Wrath")
    v = D.Step(client(), pack(), nil, nil, nil, "dps")
    t.eq(v.snapshot.role, "dps")
    t.eq(v.suggestion, nil)
end

-- The two modules on one kernel, the rotation switched on.
local function start()
    local c = client()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setClass(CLASS)
    local k = ns.Kernel({}, c)
    local diag = ns.Diag.Start(k)
    diag.help = diag.help or {}
    local api = D.Declare(k, { [CLASS] = pack() })
    local role = Ro.Declare(k, diag, { [CLASS] = pack() })
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    k.settings:set(D.SETTING, true)
    return k, c, api, role
end

local function tick(c) c.advance(D.EVERY + 0.05, 1) end

tests["driver role module: nothing chosen, the view names no role"] = function(t)
    local _, c, api = start()
    tick(c)
    t.eq(api.view().pack, true)
    t.eq(api.view().snapshot.role, nil)
end

tests["driver role module: the role chosen is in the next view"] = function(t)
    local k, c, api = start()
    k.settings:set(Ro.SETTING, "tank")
    tick(c)
    t.eq(api.view().snapshot.role, "tank")
    t.eq(api.view().suggestion and api.view().suggestion.spell, "Wrath")
    k.settings:set(Ro.SETTING, "dps")
    tick(c)
    t.eq(api.view().snapshot.role, "dps")
    k.settings:set(Ro.SETTING, "")
    tick(c)
    t.eq(api.view().snapshot.role, nil)
end

tests["driver role module: the reminder sees the same role, and says nothing"] = function(t)
    local k, c, _, role = start()
    k.settings:set(Ro.SETTING, "tank")
    local before = #c.printed
    tick(c)
    t.eq(role.status().state, "same")
    t.eq(#c.printed, before)
end

tests["driver role module: a role with no part is not played, and the reminder says so once"] = function(t)
    local k, c, api, role = start()
    k.settings:set(Ro.SETTING, "heal")
    tick(c)
    tick(c)
    t.eq(api.view().snapshot.role, nil)
    t.eq(role.status().state, "noPart")
    local n = 0
    for _, line in ipairs(c.printed) do
        if line:find("no healing part", 1, true) then n = n + 1 end
    end
    t.eq(n, 1)
end

tests["driver role module: without the role module the driver runs and names no role"] = function(t)
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
    tick(c)
    t.eq(api.errors(), 0)
    t.eq(api.view().snapshot.role, nil)
end

return tests
