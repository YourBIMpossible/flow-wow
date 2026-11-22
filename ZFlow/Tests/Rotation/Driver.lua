local _, ns = ...

-- Tests for ZFlow/Rotation/Driver.lua (RD1-RD14, the cooldown line, CD1,
-- stealth and F-086): the driver over a recording client and over the fake
-- client in a kernel. Not tested in game.

local D = ns.RotationDriver
local R = ns.Rotation
local tests = {}

local WRATH, MOONFIRE = 5176, 8921
local CLASS = "TESTCLASS"

-- A pack of two spells: Moonfire first, then Wrath; Wrath on the key.
local function pack()
    return {
        spells = { Wrath = { evidence = "test" }, Moonfire = { evidence = "test" } },
        lists = { default = {
            { spell = "Moonfire", target = true, reason = "Moonfire" },
            { spell = "Wrath", target = true, reason = "Wrath" },
        } },
        keys = { none = { key = "Wrath" } },
    }
end

-- The fake client with both spells known, usable, ready and in range.
local function spellsOn(c, cooldowns)
    cooldowns = cooldowns or { Wrath = false, Moonfire = false }
    c.setSpellId("Wrath", WRATH)
    c.setSpellId("Moonfire", MOONFIRE)
    c.setSpell(WRATH, { known = true, usable = true, noPower = false })
    c.setSpell(MOONFIRE, { known = true, usable = true, noPower = false })
    c.setSpellCooldown(WRATH, cooldowns.Wrath)
    c.setSpellCooldown(MOONFIRE, cooldowns.Moonfire)
    c.setInRange(WRATH, true)
    c.setInRange(MOONFIRE, true)
    return c
end

-- What must never be called: the driver suggests, it presses nothing.
local FORBIDDEN = { "SetAttribute", "SetBinding", "SetBindingClick", "SetOverrideBinding",
    "SetOverrideBindingClick", "CastSpell", "CastSpellByName", "CastSpellByID", "UseAction",
    "RunMacroText", "SecureCmdOptionParse", "RegisterStateDriver", "CreateFrame", "frame" }

-- What client.target answers for a live enemy.
local function enemy() return { exists = true, hostile = true, dead = false } end

-- A client that gives dead, inCombat and combatLockdown exactly as handed
-- in (nil included), reads spells from the fake client, and records every
-- call by name. `other` gets every name asked for that it does not have.
-- extra: target, stealthed, inRange  the read to use in place of the usual
--          one (a live enemy targeted; stealth not known; every spell in range)
--        without = { name, ... }     reads this client does not have
local function stub(dead, inCombat, lockdown, cooldowns, extra)
    extra = extra or {}
    local c = spellsOn(ns.make.fakeClient(), cooldowns)
    local calls, other = {}, {}
    local function rec(name, fn)
        return function(...)
            calls[name] = (calls[name] or 0) + 1
            return fn(...)
        end
    end
    local client = {
        dead = rec("dead", function() return dead end),
        inCombat = rec("inCombat", function() return inCombat end),
        combatLockdown = rec("combatLockdown", function() return lockdown end),
        spell = rec("spell", c.spell),
        spellId = rec("spellId", c.spellId),
        spellCooldown = rec("spellCooldown", c.spellCooldown),
        target = rec("target", extra.target or enemy),
        stealthed = rec("stealthed", extra.stealthed or function() return nil end),
        inRange = rec("inRange", extra.inRange or function() return true end),
    }
    for _, name in ipairs(extra.without or {}) do client[name] = nil end
    for _, name in ipairs(FORBIDDEN) do
        client[name] = rec(name, function() return nil end)
    end
    setmetatable(client, { __index = function(_, name)
        other[#other + 1] = tostring(name)
        return nil
    end })
    return client, calls, other
end

local function pressed(calls)
    local n = 0
    for _, name in ipairs(FORBIDDEN) do n = n + (calls[name] or 0) end
    return n
end

local function lastOf(trace) return trace[#trace] end

local function noteOf(trace, step)
    for _, row in ipairs(trace) do
        if row.step == step then return row.note end
    end
end

-- A stub, alive and out of a fight, whose target read answers `answer`.
local function aiming(answer)
    return stub(false, false, false, nil, { target = function() return answer end })
end

-- RD1-RD3 -------------------------------------------------------------

tests["rotation driver RD1: dead not known reaches the snapshot as nil, and nothing is suggested"] = function(t)
    local v = D.Step(stub(nil, false, false), pack())
    t.ok(v.snapshot.dead == nil, "the snapshot's dead is nil, not false")
    t.eq(v.suggestion, nil, "no suggestion")
    t.eq(v.trace, { { step = "dead", result = "skip", note = "not known whether you are dead" } })
    t.ok(v.why.dead == nil, "why.dead is nil")
    t.eq(v.why.step, "dead")
    t.eq(v.why.note, "not known whether you are dead")
end

tests["rotation driver RD2: dead reaches the snapshot as true, and nothing is suggested"] = function(t)
    local v = D.Step(stub(true, false, false), pack())
    t.eq(v.snapshot.dead, true)
    t.eq(v.suggestion, nil, "no suggestion")
    t.eq(v.trace, { { step = "dead", result = "skip", note = "dead" } })
    t.eq(v.why.dead, true)
    t.eq(v.why.note, "dead")
end

tests["rotation driver RD3: alive reaches the snapshot as false, and a spell is suggested"] = function(t)
    local v = D.Step(stub(false, false, false), pack())
    t.eq(v.snapshot.dead, false)
    t.eq(v.suggestion and v.suggestion.spell, "Moonfire")
    t.eq(v.suggestion and v.suggestion.step, "list")
    t.eq(lastOf(v.trace).result, "pick")
    t.eq(v.why.dead, false)
    t.eq(v.why.result, "pick")
    t.eq(v.why.spell, "Moonfire")
end

-- RD4-RD6 -------------------------------------------------------------

tests["rotation driver RD4: a fight not known reaches the snapshot as nil"] = function(t)
    local v = D.Step(stub(false, nil, false), pack())
    t.ok(v.snapshot.inCombat == nil, "the snapshot's inCombat is nil, not false")
    t.ok(v.why.inCombat == nil, "why.inCombat is nil")
    -- What the chooser makes of it (the wording the report line follows).
    t.eq(R.InFight(v.snapshot), true, "not known counts as a fight")
    t.eq(R.OutOfFight(v.snapshot), false, "and not as out of one")
end

tests["rotation driver RD5: a fight reaches the snapshot as true"] = function(t)
    local v = D.Step(stub(false, true, false), pack())
    t.eq(v.snapshot.inCombat, true)
    t.eq(v.why.inCombat, true)
end

tests["rotation driver RD6: no fight reaches the snapshot as false"] = function(t)
    local v = D.Step(stub(false, false, false), pack())
    t.eq(v.snapshot.inCombat, false)
    t.eq(v.why.inCombat, false)
end

tests["rotation driver RD4-RD6: the fight and the lock are read apart"] = function(t)
    local v = D.Step(stub(false, true, false), pack())
    t.eq(v.snapshot.inCombat, true, "a fight")
    t.eq(v.keys.ok, true, "and the keys are still taken: the lock said no")
    v = D.Step(stub(false, false, true), pack())
    t.eq(v.snapshot.inCombat, false, "no fight")
    t.eq(v.keys.refused, "lockdown", "and the keys are refused: the lock said yes")
end

-- RD7-RD9 -------------------------------------------------------------

tests["rotation driver RD7: a lock not known is refused as not known"] = function(t)
    local v = D.Step(stub(false, false, nil), pack())
    t.ok(v.lockdown == nil, "the view's lockdown is nil")
    t.eq(v.keys.ok, false)
    t.eq(v.keys.refused, "lockdownUnknown")
    t.eq(v.keys.reason, ns.cast.REFUSED.lockdownUnknown)
    t.eq(v.keys.ops, {})
    t.eq(v.attrs.ok, false)
    t.eq(v.attrs.refused, "lockdownUnknown")
    t.eq(v.attrs.button, {})
    t.eq(v.attrs.header, {})
    t.eq(v.why.refused, "lockdownUnknown")
    t.eq(v.why.reason, ns.cast.REFUSED.lockdownUnknown)
    t.ok(v.why.lockdown == nil, "why.lockdown is nil")
    t.eq(v.suggestion and v.suggestion.spell, "Moonfire", "the suggestion is still made")
end

tests["rotation driver RD8: the lock on is refused as a fight"] = function(t)
    local v = D.Step(stub(false, false, true), pack())
    t.eq(v.lockdown, true)
    t.eq(v.keys.ok, false)
    t.eq(v.keys.refused, "lockdown")
    t.eq(v.keys.reason, ns.cast.REFUSED.lockdown)
    t.eq(v.attrs.ok, false)
    t.eq(v.attrs.refused, "lockdown")
    t.eq(v.why.refused, "lockdown")
    t.eq(v.why.lockdown, true)
end

tests["rotation driver RD9: the lock off gives the key changes"] = function(t)
    local v = D.Step(stub(false, false, false), pack())
    t.eq(v.lockdown, false)
    t.eq(v.keys.ok, true)
    t.eq(v.keys.ops, { { op = "set", state = 0, slot = "key", spell = "Wrath" } })
    t.eq(v.keys.counts, { set = 1, clear = 0, unchanged = 0 })
    t.eq(v.attrs.ok, true)
    t.eq(v.attrs.spell, "Moonfire")
    t.eq(v.attrs.source, "suggestion")
    t.eq(v.attrs.form, 0, "the form is not read: state 0")
    t.eq(v.why.refused, nil)
    t.eq(v.why.lockdown, false)
end

tests["rotation driver RD9: the plan in place is handed to the key changes"] = function(t)
    local first = D.Step(stub(false, false, false), pack())
    local v = D.Step(stub(false, false, false), pack(), nil, nil, first.keys.plan)
    t.eq(v.keys.ops, { { op = "unchanged", state = 0, slot = "key", spell = "Wrath" } })
    t.eq(v.keys.changed, false)
end

tests["rotation driver RD7: an answer that is no yes or no is handed on as it came"] = function(t)
    local v = D.Step(stub(false, false, "yes"), pack())
    t.eq(v.lockdown, "yes")
    t.eq(v.keys.refused, "lockdownUnknown")
end

-- RD10 ----------------------------------------------------------------

tests["rotation driver RD10: the read answers nil for every field it does not ask the client"] = function(t)
    local client = stub(false, true, false)
    local read = D.Read(client, pack(), { Wrath = WRATH, Moonfire = MOONFIRE })
    local own = { dead = true, inCombat = true, spells = true, stealthed = true, hostile = true }
    local asked = 0
    for _, f in ipairs(R.SNAPSHOT_FIELDS) do
        if not own[f[1]] then
            asked = asked + 1
            t.ok(read(f[1]) == nil, f[1] .. " is nil")
        end
    end
    t.ok(asked > 20, "every other field was asked")
    t.ok(read("noSuchField") == nil, "an unknown field is nil")
    t.ok(read(nil) == nil, "no field is nil")
    t.eq(read("dead"), false)
    t.eq(read("inCombat"), true)
    t.eq(read("hostile"), true, "the target read: a live enemy")
    t.ok(read("stealthed") == nil, "stealth as the client answered: not known")
end

tests["rotation driver RD10: no flag, value or number is invented in the snapshot"] = function(t)
    local v = D.Step(stub(false, false, false), pack())
    local own = { dead = true, inCombat = true, hostile = true }
    for _, f in ipairs(R.SNAPSHOT_FIELDS) do
        local name, kind = f[1], f[2]
        if (kind == "flag" or kind == "value" or kind == "number") and not own[name] then
            t.ok(v.snapshot[name] == nil, name .. " is nil in the snapshot")
        elseif kind == "map" then
            t.eq(v.snapshot[name], {}, name .. " is empty")
        end
    end
    t.ok(v.snapshot.stealthed == nil, "stealthed is nil, never false")
    t.eq(v.snapshot.hostile, true, "hostile is what the target read gave")
end

-- The cooldown line -----------------------------------------------------

tests["rotation driver: a cooldown answer reaches the snapshot"] = function(t)
    local v = D.Step(stub(false, false, false, { Wrath = true, Moonfire = false }), pack())
    t.eq(v.snapshot.spells.Wrath.onCooldown, true, "on cooldown")
    t.eq(v.snapshot.spells.Moonfire.onCooldown, false, "ready")
    t.eq(v.snapshot.spells.Wrath.known, true)
    t.eq(v.snapshot.spells.Wrath.usable, true)
    t.eq(v.snapshot.spells.Wrath.noPower, false)
end

tests["rotation driver: a cooldown not known stays nil in the snapshot"] = function(t)
    local v = D.Step(stub(false, false, false, { Wrath = false }), pack())
    t.ok(v.snapshot.spells.Moonfire.onCooldown == nil, "nil, not false")
    t.eq(v.snapshot.spells.Wrath.onCooldown, false)
end

tests["rotation driver: a spell with no id is not read, and is named"] = function(t)
    local c = ns.make.fakeClient()
    c.setSpellId("Wrath", WRATH)
    c.setSpell(WRATH, { known = true, usable = true })
    c.setSpellCooldown(WRATH, false)
    local client = { dead = function() return false end, inCombat = function() return false end,
        combatLockdown = function() return false end, spell = c.spell, spellId = c.spellId,
        spellCooldown = c.spellCooldown, target = enemy }
    local v = D.Step(client, pack())
    t.eq(v.missing, { "Moonfire" }, "no id")
    t.eq(v.unread, { "Moonfire" }, "not read")
    t.eq(v.snapshot.spells.Moonfire, nil, "no row of guesses")
    t.eq(v.suggestion and v.suggestion.spell, "Wrath")
end

-- CD1 -----------------------------------------------------------------

tests["rotation driver CD1: the suggestion names the spells passed by for a cooldown not read"] = function(t)
    local v = D.Step(stub(false, false, false, { Wrath = false }), pack())
    t.eq(v.suggestion and v.suggestion.spell, "Wrath", "Moonfire was passed by")
    t.eq(v.suggestion and v.suggestion.passed, { "Moonfire" })
    t.eq(v.passed, { "Moonfire" })
end

tests["rotation driver CD1: nothing passed by, no passed on the suggestion"] = function(t)
    local v = D.Step(stub(false, false, false), pack())
    t.eq(v.suggestion and v.suggestion.spell, "Moonfire")
    t.eq(v.suggestion.passed, nil)
    t.eq(v.passed, {})
end

tests["rotation driver CD1: with no suggestion the view still names them, sorted"] = function(t)
    local v = D.Step(stub(false, false, false, {}), pack())
    t.eq(v.suggestion, nil)
    t.eq(v.passed, { "Moonfire", "Wrath" })
    local note
    for _, row in ipairs(v.trace) do
        if row.step == "list" then note = row.note end
    end
    t.ok(type(note) == "string" and note:find(R.COOLDOWN_UNKNOWN .. ": Moonfire, Wrath", 1, true) ~= nil,
        "the chooser's own reason is in the trace")
end

tests["rotation driver CD1: a spell on cooldown is not passed by for that reason"] = function(t)
    local v = D.Step(stub(false, false, false, { Wrath = false, Moonfire = true }), pack())
    t.eq(v.suggestion and v.suggestion.spell, "Wrath")
    t.eq(v.suggestion.passed, nil)
end

tests["rotation driver CD1: a spell no step weighed is not named"] = function(t)
    -- Moonfire is picked first; Wrath's cooldown was not read, but the list
    -- never came to Wrath.
    local v = D.Step(stub(false, false, false, { Moonfire = false }), pack())
    t.eq(v.suggestion and v.suggestion.spell, "Moonfire")
    t.eq(v.suggestion.passed, nil, "nothing was passed by")
    t.eq(v.passed, {}, "Wrath was never weighed")
    t.eq(lastOf(v.trace).passed, nil, "and the pick's row names none")
end

tests["rotation driver CD1: the passed list is the one the steps gave in the trace"] = function(t)
    local v = D.Step(stub(false, false, false, { Wrath = false }), pack())
    t.eq(lastOf(v.trace).step, "list")
    t.eq(lastOf(v.trace).passed, { "Moonfire" }, "the list's row names what it passed by")
    t.eq(v.passed, { "Moonfire" })
    for i = 1, #v.trace - 1 do
        t.eq(v.trace[i].passed, nil, v.trace[i].step .. ": passed nothing by")
    end
end

-- Stealth -------------------------------------------------------------

tests["rotation driver: stealthed is read through client.stealthed"] = function(t)
    local function step(answer)
        local client, calls = stub(false, false, false, nil, { stealthed = function() return answer end })
        return D.Step(client, pack()), calls
    end
    local v, calls = step(true)
    t.eq(v.snapshot.stealthed, true, "stealthed")
    t.eq(calls.stealthed, 1, "asked once")
    v = step(false)
    t.eq(v.snapshot.stealthed, false, "read: not stealthed")
    v = step(nil)
    t.ok(v.snapshot.stealthed == nil, "not known stays nil, never false")
end

tests["rotation driver: a client with no stealthed read leaves it not known"] = function(t)
    local ok, v = pcall(D.Step, stub(false, false, false, nil, { without = { "stealthed" } }), pack())
    t.ok(ok, "the step ran: " .. tostring(v))
    t.ok(ok and v.snapshot.stealthed == nil, "nil, never false")
    t.eq(ok and v.suggestion and v.suggestion.spell, "Moonfire", "and the rest is as usual")
end

-- F-086 ---------------------------------------------------------------

tests["rotation driver F-086: hostile is yes only for an enemy that is there, hostile and alive"] = function(t)
    local function hostile(answer) return D.Step(aiming(answer), pack()).snapshot.hostile end
    t.eq(hostile(enemy()), true, "there, hostile, alive")
    t.eq(hostile({ exists = false }), false, "read: no target")
    t.eq(hostile({ exists = true, hostile = false, dead = false }), false, "read: not hostile")
    t.eq(hostile({ exists = true, hostile = true, dead = true }), false, "read: dead")
    t.ok(hostile(nil) == nil, "no answer: not known")
    t.ok(hostile({}) == nil, "an empty answer: not known")
    t.ok(hostile({ exists = true }) == nil, "hostile not read: not known")
    t.ok(hostile({ exists = true, hostile = true }) == nil, "dead not read: not known")
    t.ok(hostile({ exists = true, dead = false }) == nil, "hostile not read, alive: not known")
    t.ok(hostile("yes") == nil, "an answer that is no table: not known")
end

tests["rotation driver F-086: target not known, no spell that needs one is suggested"] = function(t)
    local client, calls = aiming(nil)
    local v = D.Step(client, pack())
    t.ok(v.snapshot.hostile == nil, "hostile is nil in the snapshot, not false")
    t.eq(v.suggestion, nil, "nothing is suggested")
    t.eq(noteOf(v.trace, "list"), "no rule ready; not known whether you have a target: Moonfire, Wrath")
    t.eq(noteOf(v.trace, "farOpener"), "not known whether you have a target")
    t.eq(v.why.note, "not known whether you have a target", "the plain reason follows the trace")
    t.eq(v.passed, {}, "no cooldown was in the way")
    t.eq(calls.target, 1, "the target was asked once")
    t.eq(pressed(calls), 0, "nothing pressed")
end

tests["rotation driver F-086: a client with no target read leaves the target not known"] = function(t)
    local ok, v = pcall(D.Step, stub(false, false, false, nil, { without = { "target" } }), pack())
    t.ok(ok, "the step ran: " .. tostring(v))
    t.ok(ok and v.snapshot.hostile == nil, "hostile is nil, never false")
    t.eq(ok and v.suggestion, nil, "nothing that needs a target is suggested")
    t.eq(ok and noteOf(v.trace, "list"), "no rule ready; not known whether you have a target: Moonfire, Wrath")
end

tests["rotation driver F-086: range is read through client.inRange when the client has it"] = function(t)
    local function step(answers, without)
        local client = stub(false, false, false, nil,
            { inRange = function(id) return answers[id] end, without = without })
        return D.Step(client, pack())
    end
    local v = step({ [MOONFIRE] = false, [WRATH] = true })
    t.eq(v.snapshot.spells.Moonfire.inRange, false, "read: out of range")
    t.eq(v.snapshot.spells.Wrath.inRange, true, "read: in range")
    t.eq(v.suggestion and v.suggestion.spell, "Wrath", "the list goes on to the spell in range")
    t.eq(v.suggestion and v.suggestion.step, "list")

    v = step({ [MOONFIRE] = false, [WRATH] = false })
    t.eq(v.suggestion and v.suggestion.spell, "Moonfire", "both out of range: the far opener")
    t.eq(v.suggestion and v.suggestion.step, "farOpener")

    v = step({})
    t.ok(v.snapshot.spells.Moonfire.inRange == nil, "no answer: range stays not known")
    t.ok(v.snapshot.spells.Wrath.inRange == nil)
    v = step({ [MOONFIRE] = "far", [WRATH] = 0 })
    t.ok(v.snapshot.spells.Moonfire.inRange == nil, "an answer that is no yes or no: not known")
    t.ok(v.snapshot.spells.Wrath.inRange == nil)

    local ok, got = pcall(step, { [MOONFIRE] = false }, { "inRange" })
    t.ok(ok, "a client with no inRange read: the step ran: " .. tostring(got))
    t.ok(ok and got.snapshot.spells.Moonfire.inRange == nil, "and range is not known")
    t.eq(ok and got.suggestion, nil, "range not known: nothing that needs it is suggested")
    t.eq(ok and noteOf(got.trace, "list"), "no rule ready; " .. R.RANGE_UNKNOWN .. ": Moonfire, Wrath")
end

-- RD11 ----------------------------------------------------------------

tests["rotation driver RD11: a step presses nothing and asks only its nine reads"] = function(t)
    for _, fight in ipairs({ false, true }) do
        local client, calls, other = stub(false, fight, fight)
        local v = D.Step(client, pack())
        t.ok(v.suggestion ~= nil, "a suggestion was made")
        t.eq(pressed(calls), 0, "nothing pressed, fight " .. tostring(fight))
        t.eq(other, {}, "nothing else asked of the client")
        local names = {}
        for name in pairs(calls) do names[#names + 1] = name end
        table.sort(names)
        t.eq(names, { "combatLockdown", "dead", "inCombat", "inRange", "spell", "spellCooldown", "spellId",
            "stealthed", "target" })
        t.eq(calls.dead, 1)
        t.eq(calls.inCombat, 1)
        t.eq(calls.combatLockdown, 1)
        t.eq(calls.target, 1)
        t.eq(calls.stealthed, 1)
        t.eq(calls.inRange, 2, "once for each spell with an id")
    end
end

-- The driver in a kernel ------------------------------------------------

-- opts: class (false: not known), cooldowns, enabled (true: switched on
-- after login). A live enemy is targeted.
local function start(opts)
    opts = opts or {}
    local c = spellsOn(ns.make.fakeClient(), opts.cooldowns)
    c.target = enemy
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setDead(false)
    if opts.class ~= false then c.setClass(opts.class or CLASS) end
    local calls = {}
    for _, name in ipairs(FORBIDDEN) do
        c[name] = function() calls[name] = (calls[name] or 0) + 1 end
    end
    -- The fake's frames: the driver makes none.
    for _, name in ipairs({ "panel", "arrow" }) do
        local real = c[name]
        c[name] = function(...)
            calls[name] = (calls[name] or 0) + 1
            return real(...)
        end
    end
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    local api = D.Declare(k, { [CLASS] = pack() })
    local seen = {}
    k.bus:on("driverTest", D.EVENT, function(view) seen[#seen + 1] = view or false end)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    if opts.enabled then k.settings:set(D.SETTING, true) end
    return k, c, api, seen, calls
end

-- One tick of the driver.
local function tick(c) c.advance(D.EVERY + 0.05, 1) end

tests["rotation driver RD11: nothing is pressed over ticks in and out of a fight"] = function(t)
    local k, c, api, seen, calls = start({ enabled = true })
    tick(c)
    t.eq(api.view() and api.view().suggestion and api.view().suggestion.spell, "Moonfire", "out of a fight")
    t.eq(api.view().keys.ok, true)
    c.setCombat(true)
    tick(c)
    tick(c)
    t.eq(api.view().snapshot.inCombat, true, "in a fight")
    t.eq(api.view().keys.refused, "lockdown")
    t.eq(api.view().suggestion and api.view().suggestion.spell, "Moonfire", "still suggesting in a fight")
    c.setCombat(false)
    tick(c)
    t.eq(api.view().keys.ok, true)
    t.eq(#seen, 4, "one view published for each tick")
    t.eq(pressed(calls), 0, "nothing pressed")
    t.eq(calls.panel, nil, "no panel made")
    t.eq(calls.arrow, nil, "no arrow made")
    t.eq(k:ModuleState(D.NAME), "started")
end

tests["rotation driver RD11: the plan is never taken as applied"] = function(t)
    local _, c, api = start({ enabled = true })
    tick(c)
    tick(c)
    -- Nothing was bound, so the second tick still has every key to set.
    t.eq(api.view().keys.ops, { { op = "set", state = 0, slot = "key", spell = "Wrath" } })
end

-- RD12 ----------------------------------------------------------------

tests["rotation driver RD12: with no pack the chooser is not called"] = function(t)
    local client, calls, other = stub(false, false, false)
    local real, n = ns.Choose, 0
    ns.Choose = function(...)
        n = n + 1
        return real(...)
    end
    local ok, v = pcall(D.Step, client, nil)
    ns.Choose = real
    t.ok(ok, "the step ran: " .. tostring(v))
    t.eq(n, 0, "no call of the chooser")
    t.eq(v.pack, false)
    t.eq(v.suggestion, nil)
    t.eq(v.trace, {})
    t.eq(v.keys, nil)
    t.eq(v.attrs, nil)
    t.eq(v.why, { pack = false })
    t.eq(calls, {}, "and nothing is read")
    t.eq(other, {})
end

tests["rotation driver RD12: a class not known gives the no-pack view each tick"] = function(t)
    local k, c, api, seen = start({ class = false, enabled = true })
    tick(c)
    t.eq(api.view() and api.view().pack, false)
    t.eq(api.view().why, { pack = false })
    t.eq(api.view().suggestion, nil)
    t.eq(#seen, 1)
    t.eq(k:ModuleState(D.NAME), "started")
end

tests["rotation driver RD12: a class with no pack gives the no-pack view"] = function(t)
    local _, c, api = start({ class = "NOSUCHCLASS", enabled = true })
    tick(c)
    t.eq(api.view() and api.view().pack, false)
end

tests["rotation driver RD12: the pack is asked for again each tick"] = function(t)
    local _, c, api = start({ class = false, enabled = true })
    tick(c)
    t.eq(api.view().pack, false)
    c.setClass(CLASS)
    tick(c)
    t.eq(api.view().pack, true)
    t.eq(api.view().suggestion and api.view().suggestion.spell, "Moonfire")
end

-- RD13 ----------------------------------------------------------------

tests["rotation driver RD13: a read that fails loses that tick only"] = function(t)
    local k, c, api, seen = start({ enabled = true })
    tick(c)
    local good = api.view()
    t.eq(good.suggestion and good.suggestion.spell, "Moonfire")
    t.eq(good.stale, nil, "a good view is not stale")
    t.eq(api.errors(), 0)

    local real = c.dead
    c.dead = function() error("the read failed") end
    tick(c)
    local kept = api.view()
    t.eq(kept.stale, true, "the last good view, marked stale")
    t.eq(kept.suggestion and kept.suggestion.spell, "Moonfire", "its value is kept")
    t.eq(kept.snapshot, good.snapshot)
    t.eq(good.stale, nil, "the view handed out before is not changed")
    t.eq(api.errors(), 1)
    t.ok(type(api.lastError()) == "string" and api.lastError():find("the read failed", 1, true) ~= nil, "the error is kept")
    t.eq(seen[#seen], kept, "the stale view is published")

    c.dead = real
    tick(c)
    t.eq(api.view().stale, nil, "the next tick runs and is fresh")
    t.eq(api.view().suggestion and api.view().suggestion.spell, "Moonfire")
    t.eq(api.errors(), 1)
    t.eq(k:ModuleState(D.NAME), "started")
end

tests["rotation driver RD13: a failing first tick leaves no view"] = function(t)
    local _, c, api, seen = start({ enabled = true })
    c.dead = function() error("the read failed") end
    tick(c)
    t.eq(api.view(), nil, "nothing good to keep")
    t.eq(api.errors(), 1)
    t.eq(#seen, 0, "nothing published")
end

tests["rotation driver RD13: failing ticks never switch the driver off"] = function(t)
    local k, c, api = start({ enabled = true })
    tick(c)
    local real = c.dead
    c.dead = function() error("the read failed") end
    for _ = 1, ns.FAULT_LIMIT + 2 do tick(c) end
    t.eq(api.errors(), ns.FAULT_LIMIT + 2)
    t.eq(k:ModuleState(D.NAME), "started")
    t.eq(api.view().stale, true)
    c.dead = real
    tick(c)
    t.eq(api.view().stale, nil)
end

-- RD14 ----------------------------------------------------------------

tests["rotation driver RD14: off by default"] = function(t)
    local k, c, api, seen, calls = start()
    t.eq(k.settings:get(D.SETTING), false, "the setting's default")
    t.eq(k.settings:row(D.SETTING).default, false)
    t.eq(k:ModuleState(D.NAME), "started", "declared and started, but idle")
    c.advance(2, 10)
    t.eq(api.view(), nil, "no view")
    t.eq(#seen, 0, "nothing published")
    t.eq(pressed(calls), 0)
end

tests["rotation driver RD14: switching it on starts the tick"] = function(t)
    local k, c, api, seen = start()
    c.advance(1, 5)
    t.eq(api.view(), nil)
    t.eq(k.settings:set(D.SETTING, true), true, "the setting is taken")
    tick(c)
    t.eq(api.view() and api.view().suggestion and api.view().suggestion.spell, "Moonfire")
    t.eq(#seen, 1)
    t.eq(seen[1], api.view(), "the view is what is published")
end

tests["rotation driver RD14: switching it off stops the tick"] = function(t)
    local k, c, api, seen = start({ enabled = true })
    tick(c)
    tick(c)
    t.eq(#seen, 2)
    t.eq(k.settings:set(D.SETTING, false), true)
    tick(c)
    t.eq(api.view(), nil, "the view is dropped")
    t.eq(#seen, 3, "one last publish")
    t.eq(seen[3], false, "saying there is no view")
    c.advance(2, 10)
    t.eq(#seen, 3, "and then nothing")
    t.eq(api.view(), nil)
end

tests["rotation driver RD14: the setting row does not spell the product name"] = function(t)
    local row = ns.settings:row(D.SETTING)
    t.ok(type(row) == "table", "the addon's own row is declared")
    t.eq(row.type, "bool")
    t.eq(row.scope, "char")
    for _, text in ipairs({ row.label, row.help or "" }) do
        t.ok(not text:lower():find("flow", 1, true), "no product name in: " .. text)
    end
end

tests["rotation driver: the addon's own driver is declared, and others can reach it"] = function(t)
    t.ok(type(ns.rotationDriver) == "table" and type(ns.rotationDriver.view) == "function", "ns.rotationDriver")
    local k = start()
    local use = k.use(D.NAME)
    t.ok(type(use) == "table" and type(use.View) == "function" and type(use.Errors) == "function", "View and Errors")
    t.eq(use.View(), nil)
    t.eq(D.NAME, "rotationDriver")
    t.eq(D.EVENT, "rotation.suggested")
    t.eq(D.EVERY, 0.2)
end

return tests
