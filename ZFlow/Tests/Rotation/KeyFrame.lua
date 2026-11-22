-- Tests for ZFlow/Rotation/KeyFrame.lua (G23, T-D): the one secure button
-- that holds the key plan's attributes. It is set outside a fight only; in a
-- fight the change waits and is applied after the fight ends. The secure
-- button itself is a client need (client.secureButton) that Core/Client.lua
-- does not have yet, so these tests put a hand-written one on their own
-- fake client. Not tested in game.
local _, ns = ...

local K = ns.KeyFrame
local D = ns.RotationDriver
local tests = {}

local CLASS = "TESTCLASS"
local WRATH, MOONFIRE, CLAW = 5176, 8921, 1082 -- test values, not client data

-- The only attribute names the button may ever be given.
local ALLOWED = { type = true, spell = true, unit = true, macrotext = true }
for _, slot in ipairs({ "ctrl", "shift", "alt", "more" }) do
    ALLOWED["*type-" .. slot] = true
    ALLOWED["*spell-" .. slot] = true
    ALLOWED["*unit-" .. slot] = true
end

local function plan(key, ctrl)
    return ns.KeyPlan({ keys = { none = { key = key or "Wrath", ctrl = ctrl or "Moonfire" } } }, {})
end

local function formPlan()
    return ns.KeyPlan({ keys = { none = { key = "Wrath", ctrl = "Moonfire" }, Cat = { key = "Claw" } } },
        { forms = { { name = "Cat", index = 3 } } })
end

-- A hand-written secure button: what CLIENT NEED 5 describes. lock() is
-- asked as the client would ask the game. reached counts the sets that got
-- as far as the game; inLock counts the sets asked for while locked.
local function button(lock)
    local h = { attrs = {}, reached = {}, inLock = 0, fail = {}, drop = {} }
    function h.set(attr, value)
        if lock() ~= false then
            h.inLock = h.inLock + 1
            return false, "lockdown"
        end
        h.reached[#h.reached + 1] = attr
        if h.onSet then h.onSet(#h.reached) end
        if h.fail[attr] then return false, "refused" end
        if not h.drop[attr] then h.attrs[attr] = value end
        return true
    end
    function h.get(attr) return h.attrs[attr] end
    return h
end

-- A key frame over a hand-written button and a lock the test holds.
local function make(opts)
    opts = opts or {}
    local s = { lock = false, form = opts.form }
    local function lock() return s.lock end
    local h = (not opts.noButton) and button(lock) or nil
    local kf = K.New({
        button = h,
        lockdown = lock,
        form = (not opts.noForm) and function() return s.form end or nil,
    })
    return kf, h, s
end

local function joined(lines) return table.concat(lines, "\n") end

-- ------------------------------------------------------------------ names
tests["key frame: names"] = function(t)
    t.eq(K.NAME, "rotationKeys")
    t.eq(K.SETTING, "rotation.keyFrame")
    t.eq(K.WORD, "keys")
    t.eq(K.TEMPLATE, "SecureActionButtonTemplate")
end

-- ---------------------------------------------------------- outside a fight
tests["key frame: outside a fight the plan's row is put on the button"] = function(t)
    local kf, h = make({ form = 0 })
    local st = kf:want(plan())
    t.eq(st.state, "set")
    t.eq(h.attrs.type, "spell")
    t.eq(h.attrs.spell, "Wrath")
    t.eq(h.attrs.unit, "target")
    t.eq(h.attrs.macrotext, nil)
    t.eq(h.attrs["*type-ctrl"], "spell")
    t.eq(h.attrs["*spell-ctrl"], "Moonfire")
    t.eq(h.attrs["*unit-ctrl"], "target")
    t.eq(h.attrs["*spell-shift"], nil, "an empty slot holds nothing")
    t.eq(st.parts, 6, "six attributes differed from an empty button")
    t.eq(#st.failed, 0)
    t.eq(h.inLock, 0)
end

tests["key frame: only the attributes of the button list are ever set"] = function(t)
    local kf, h = make({ form = 0 })
    kf:want(formPlan())
    kf:want(plan("Moonfire", "Wrath"))
    kf:want(nil)
    t.ok(#h.reached > 0, "something was set")
    for _, attr in ipairs(h.reached) do
        t.ok(ALLOWED[attr] == true, "not a button attribute: " .. tostring(attr))
    end
end

tests["key frame: the same plan again sets nothing"] = function(t)
    local kf, h = make({ form = 0 })
    kf:want(plan())
    local n = #h.reached
    local st = kf:want(plan())
    t.eq(#h.reached, n, "no set reached the game")
    t.eq(st.state, "set")
    kf:try(true)
    t.eq(#h.reached, n, "a forced try of what is in place sets nothing either")
end

tests["key frame: a changed plan sets only what differs"] = function(t)
    local kf, h = make({ form = 0 })
    kf:want(plan("Wrath", "Moonfire"))
    local n = #h.reached
    local st = kf:want(plan("Wrath", "Starfire"))
    t.eq(#h.reached, n + 1, "one attribute differed")
    t.eq(h.reached[#h.reached], "*spell-ctrl")
    t.eq(h.attrs["*spell-ctrl"], "Starfire")
    t.eq(st.parts, 1)
end

-- ------------------------------------------------------------- in a fight
tests["key frame: in a fight nothing is set and the change waits"] = function(t)
    local kf, h, s = make({ form = 0 })
    s.lock = true
    local st = kf:want(plan())
    t.eq(st.state, "waiting")
    t.eq(st.reason, "lockdown")
    t.eq(#h.reached, 0, "no set reached the game")
    t.eq(h.inLock, 0, "the button was not even asked")
    t.eq(next(h.attrs), nil)
end

tests["key frame: a lock that is not known is treated as a fight"] = function(t)
    local kf, h, s = make({ form = 0 })
    s.lock = nil
    local st = kf:want(plan())
    t.eq(st.state, "waiting")
    t.eq(st.reason, "lockdownUnknown")
    t.eq(#h.reached, 0)
    t.eq(h.inLock, 0)
    s.lock = "no"
    t.eq(kf:try(true).state, "waiting", "only a plain false lets a set through")
    t.eq(#h.reached, 0)
end

tests["key frame: what waited is applied when the fight is over"] = function(t)
    local kf, h, s = make({ form = 0 })
    s.lock = true
    kf:want(plan())
    t.eq(kf:try(true).state, "waiting", "asked again in the fight: still nothing")
    t.eq(#h.reached, 0)
    s.lock = false
    local st = kf:try(true)
    t.eq(st.state, "set")
    t.eq(h.attrs.spell, "Wrath")
    t.eq(h.attrs["*spell-ctrl"], "Moonfire")
end

tests["key frame: many changes in a fight make one apply of the last"] = function(t)
    local kf, h, s = make({ form = 0 })
    s.lock = true
    kf:want(plan("Wrath", "Moonfire"))
    kf:want(plan("Starfire", "Wrath"))
    kf:want(plan("Moonfire", "Starfire"))
    t.eq(#h.reached, 0)
    s.lock = false
    kf:try(true)
    t.eq(h.attrs.spell, "Moonfire")
    t.eq(h.attrs["*spell-ctrl"], "Starfire")
    t.eq(#h.reached, 6, "one walk, not three")
end

tests["key frame: a fight that starts in the middle of an apply stops it"] = function(t)
    local kf, h, s = make({ form = 0 })
    h.onSet = function(n)
        if n == 2 then s.lock = true end
    end
    local st = kf:want(plan())
    t.eq(st.state, "waiting")
    t.eq(st.reason, "lockdown")
    t.eq(#h.reached, 2, "the walk stopped at the fight")
    t.eq(h.inLock, 0, "the lock was asked before each set, so no set was asked in the fight")
    h.onSet = nil
    s.lock = false
    st = kf:try(true)
    t.eq(st.state, "set")
    t.eq(#h.reached, 6, "the rest was set after the fight, and nothing twice")
    t.eq(h.attrs["*unit-ctrl"], "target")
end

-- ------------------------------------------------------------ a failed apply
tests["key frame: an attribute the client refuses is named, the rest is set"] = function(t)
    local kf, h = make({ form = 0 })
    h.fail["*spell-ctrl"] = true
    local st = kf:want(plan())
    t.eq(st.state, "failed")
    t.eq(st.failed, { { attr = "*spell-ctrl", why = "refused" } })
    t.eq(st.parts, 6)
    t.eq(h.attrs.spell, "Wrath", "the others were set")
    t.eq(h.attrs["*spell-ctrl"], nil)
end

tests["key frame: a failed apply is not asked over and over"] = function(t)
    local kf, h = make({ form = 0 })
    h.fail["*spell-ctrl"] = true
    kf:want(plan())
    local n = #h.reached
    t.eq(kf:want(plan()).state, "failed", "the same plan again")
    t.eq(kf:try().state, "failed", "a plain try")
    t.eq(#h.reached, n, "neither asked the client again")
end

tests["key frame: a forced try does the failed rows again, and only those"] = function(t)
    local kf, h = make({ form = 0 })
    h.fail["*spell-ctrl"] = true
    kf:want(plan())
    local n = #h.reached
    t.eq(kf:try(true).state, "failed", "still refused")
    t.eq(#h.reached, n + 1, "one row asked again")
    h.fail["*spell-ctrl"] = nil
    local st = kf:try(true)
    t.eq(st.state, "set")
    t.eq(#st.failed, 0)
    t.eq(h.attrs["*spell-ctrl"], "Moonfire")
    t.eq(#h.reached, n + 2)
end

tests["key frame: a set the button did not keep is a failure"] = function(t)
    local kf, h = make({ form = 0 })
    h.drop.spell = true
    local st = kf:want(plan())
    t.eq(st.state, "failed")
    t.eq(st.failed, { { attr = "spell", why = "notKept" } })
end

tests["key frame: a button with no read-back is taken at its word"] = function(t)
    local kf, h = make({ form = 0 })
    h.get = nil
    h.drop.spell = true
    t.eq(kf:want(plan()).state, "set")
end

tests["key frame: a button that raises is a failure, not an error"] = function(t)
    local kf, h = make({ form = 0 })
    local real = h.set
    h.set = function(attr, value)
        if attr == "unit" then error("boom") end
        return real(attr, value)
    end
    local st = kf:want(plan())
    t.eq(st.state, "failed")
    t.eq(st.failed, { { attr = "unit", why = "refused" } })
end

tests["key frame: what is not a key plan is refused and nothing is set"] = function(t)
    local kf, h = make({ form = 0 })
    local st = kf:want("Wrath")
    t.eq(st.state, "failed")
    t.eq(st.reason, "plan")
    t.eq(#h.reached, 0)
end

tests["key frame: no secure button, nothing is done"] = function(t)
    local kf = make({ noButton = true })
    local st = kf:want(plan())
    t.eq(st.state, "noFrame")
    t.eq(kf:try(true).state, "noFrame")
end

-- ---------------------------------------------------------------- clearing
tests["key frame: wanting nothing clears what was set, outside a fight only"] = function(t)
    local kf, h, s = make({ form = 0 })
    kf:want(plan())
    s.lock = true
    local st = kf:want(nil)
    t.eq(st.state, "waiting")
    t.eq(h.attrs.spell, "Wrath", "nothing is cleared in a fight")
    s.lock = false
    st = kf:try(true)
    t.eq(st.state, "cleared")
    t.eq(next(h.attrs), nil, "the button holds nothing")
end

tests["key frame: before anything is wanted it is idle"] = function(t)
    local kf, h = make({ form = 0 })
    t.eq(kf:status().state, "idle")
    t.eq(kf:try(true).state, "idle")
    t.eq(#h.reached, 0)
end

-- ------------------------------------------------------------------- forms
tests["key frame: the row of the form you are in is used"] = function(t)
    local kf, h, s = make({ form = 3 })
    local st = kf:want(formPlan())
    t.eq(h.attrs.spell, "Claw")
    t.eq(h.attrs["*spell-ctrl"], nil, "the cat row has no ctrl")
    t.eq(st.form, 3)
    t.eq(st.formRead, true)
    s.form = 0
    st = kf:reform()
    t.eq(st.state, "set")
    t.eq(h.attrs.spell, "Wrath")
    t.eq(h.attrs["*spell-ctrl"], "Moonfire")
    t.eq(st.form, 0)
end

tests["key frame: a form change in a fight waits like any other change"] = function(t)
    local kf, h, s = make({ form = 0 })
    kf:want(formPlan())
    s.lock, s.form = true, 3
    local st = kf:reform()
    t.eq(st.state, "waiting")
    t.eq(h.attrs.spell, "Wrath", "the button keeps the row it had")
    s.lock = false
    kf:try(true)
    t.eq(h.attrs.spell, "Claw")
end

tests["key frame: a form that was not read uses the no-form row and says so"] = function(t)
    local kf, h = make({ form = nil })
    local st = kf:want(formPlan())
    t.eq(h.attrs.spell, "Wrath")
    t.eq(st.form, 0)
    t.eq(st.formRead, false)
    local kf2, h2 = make({ noForm = true })
    st = kf2:want(formPlan())
    t.eq(h2.attrs.spell, "Wrath")
    t.eq(st.formRead, false)
    t.ok(joined(K.Lines(st)):find("form not read", 1, true) ~= nil)
end

-- ------------------------------------------------------------------- lines
tests["key frame: the lines say each state in plain words"] = function(t)
    local kf, h, s = make({ form = 0 })
    t.ok(joined(K.Lines(kf:status())):find("nothing to set yet", 1, true) ~= nil)
    s.lock = true
    t.ok(joined(K.Lines(kf:want(plan()))):find("waiting for the fight to end", 1, true) ~= nil)
    s.lock = nil
    t.ok(joined(K.Lines(kf:try(true))):find("did not say whether you are in a fight", 1, true) ~= nil)
    s.lock = false
    local text = joined(K.Lines(kf:try(true)))
    t.ok(text:find("key: Wrath", 1, true) ~= nil, text)
    t.ok(text:find("ctrl: Moonfire", 1, true) ~= nil, text)
    t.eq(text:find("form not read", 1, true), nil, "the form was read")
    h.fail.spell = true
    text = joined(K.Lines(kf:want(plan("Starfire", "Moonfire"))))
    t.ok(text:find("could not be set", 1, true) ~= nil, text)
    t.ok(text:find("1 of 1 parts", 1, true) ~= nil, text)
    t.ok(text:find("spell (refused)", 1, true) ~= nil, text)
    h.fail.spell = nil
    text = joined(K.Lines(kf:want(nil)))
    t.ok(text:find("holds nothing", 1, true) ~= nil, text)
    local none = make({ noButton = true })
    t.ok(joined(K.Lines(none:want(plan()))):find("no secure button", 1, true) ~= nil)
    t.ok(joined(K.Lines(nil)):find("off", 1, true) ~= nil, "no status: it is off")
end

tests["key frame: the failure line counts the parts"] = function(t)
    local kf, h = make({ form = 0 })
    h.fail.spell, h.fail.unit = true, true
    local line = K.FailLine(kf:want(plan()))
    t.ok(line:find("2 of 6 parts", 1, true) ~= nil, line)
    t.ok(line:find("keeps what it had", 1, true) ~= nil, line)
    t.eq(K.FailLine(make({ form = 0 }):status()), nil, "no failure, no line")
end

-- ------------------------------------------------------------- in a kernel
-- The module over the fake client. client.secureButton is put on this fake
-- only: Core/ClientFake.lua has none until the lead adds the client need.
local FORBIDDEN = { "SetBinding", "SetBindingClick", "SetOverrideBinding", "SetOverrideBindingClick",
    "CastSpell", "CastSpellByName", "CastSpellByID", "UseAction", "RunMacroText",
    "RegisterStateDriver", "SecureCmdOptionParse", "Click" }

local function pack()
    return {
        spells = { Wrath = { evidence = "test" }, Moonfire = { evidence = "test" } },
        lists = { default = {
            { spell = "Moonfire", target = true, reason = "Moonfire" },
            { spell = "Wrath", target = true, reason = "Wrath" },
        } },
        keys = { none = { key = "Wrath", ctrl = "Moonfire" } },
    }
end

-- opts: noSecure (the client has no secure button), keys (the setting on),
-- rotation (the driver's setting on).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSpellId("Wrath", WRATH)
    c.setSpellId("Moonfire", MOONFIRE)
    c.setSpellId("Claw", CLAW)
    c.setSpell(WRATH, { known = true, usable = true, noPower = false })
    c.setSpell(MOONFIRE, { known = true, usable = true, noPower = false })
    c.setSpellCooldown(WRATH, false)
    c.setSpellCooldown(MOONFIRE, false)
    c.target = function() return { exists = true, hostile = true, dead = false } end
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setDead(false)
    c.setClass(CLASS)
    local made = {}
    if not opts.noSecure then
        c.secureButton = function(spec)
            local h = button(c.combatLockdown)
            h.spec = spec
            made[#made + 1] = h
            return h
        end
    end
    local calls = {}
    for _, name in ipairs(FORBIDDEN) do
        c[name] = function() calls[name] = (calls[name] or 0) + 1 end
    end
    local k = ns.Kernel({}, c)
    local diag = ns.Diag.Start(k)
    D.Declare(k, { [CLASS] = pack() })
    local api = K.Declare(k, diag)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    if opts.rotation ~= false then k.settings:set(D.SETTING, true) end
    if opts.keys ~= false then k.settings:set(K.SETTING, true) end
    return k, c, made, api, calls
end

local function tick(c) c.advance(D.EVERY + 0.05, 1) end
local function said(c, text)
    local n = 0
    for _, line in ipairs(c.printed) do
        if line:find(text, 1, true) then n = n + 1 end
    end
    return n
end
local function forbidden(calls)
    local n = 0
    for _, v in pairs(calls) do n = n + v end
    return n
end

tests["key frame module: off by default, and then no secure button is made"] = function(t)
    local k, c, made = start({ keys = false })
    c.advance(2, 10)
    t.eq(k.settings:get(K.SETTING), false)
    t.eq(#made, 0)
    t.eq(k.problems:count(), 0)
end

tests["key frame module: switched on, the plan is put on one button outside a fight"] = function(t)
    local k, c, made, api, calls = start()
    tick(c)
    t.eq(#made, 1, "one button")
    t.eq(made[1].spec, { name = ns.id.framePrefix .. "RotationKey" })
    t.eq(made[1].attrs.spell, "Wrath", "the plan's key spell, not the suggestion (Moonfire)")
    t.eq(made[1].attrs["*spell-ctrl"], "Moonfire")
    t.eq(api.status().state, "set")
    c.advance(2, 10)
    t.eq(#made, 1, "still one button")
    t.eq(#made[1].reached, 6, "later ticks with the same plan set nothing")
    t.eq(forbidden(calls), 0, "no binding, no cast, no click, no state driver")
    t.eq(k.problems:count(), 0)
end

tests["key frame module: switched on in a fight, it waits for the fight to end"] = function(t)
    local k, c, made, api = start({ keys = false })
    tick(c)
    c.setCombat(true)
    k.settings:set(K.SETTING, true)
    c.advance(2, 10)
    t.eq(#made == 0 or #made[1].reached == 0, true, "nothing set in the fight")
    c.setCombat(false)
    tick(c)
    t.eq(#made, 1)
    t.eq(made[1].attrs.spell, "Wrath")
    t.eq(made[1].inLock, 0)
    t.eq(api.status().state, "set")
end

tests["key frame module: switched off in a fight, it is cleared only after the fight"] = function(t)
    local k, c, made, api = start()
    tick(c)
    c.setCombat(true)
    k.settings:set(K.SETTING, false)
    c.advance(2, 10)
    t.eq(made[1].attrs.spell, "Wrath", "kept through the fight")
    t.eq(api.status().state, "waiting")
    c.setCombat(false)
    t.eq(next(made[1].attrs), nil, "cleared at the end of the fight")
    t.eq(made[1].inLock, 0)
    t.eq(api.status().state, "cleared")
end

tests["key frame module: the rotation switched off clears the button"] = function(t)
    local k, c, made = start()
    tick(c)
    t.eq(made[1].attrs.spell, "Wrath")
    k.settings:set(D.SETTING, false)
    tick(c)
    t.eq(next(made[1].attrs), nil)
end

tests["key frame module: a failed apply is said once and listed as a problem"] = function(t)
    local k, c, made, api = start({ keys = false })
    c.secureButton = function(spec)
        local h = button(c.combatLockdown)
        h.spec, h.fail.spell = spec, true
        made[#made + 1] = h
        return h
    end
    k.settings:set(K.SETTING, true)
    tick(c)
    t.eq(api.status().state, "failed")
    t.eq(said(c, "could not be set (1 of 6 parts)"), 1)
    t.eq(k.problems:count(K.NAME), 1)
    local n = #made[1].reached
    c.advance(2, 10)
    t.eq(#made[1].reached, n, "not asked again tick after tick")
    t.eq(said(c, "could not be set"), 1, "said once")
    made[1].fail.spell = nil
    c.setCombat(true)
    c.setCombat(false)
    t.eq(api.status().state, "set", "tried again after the next fight")
    t.eq(made[1].attrs.spell, "Wrath")
    made[1].fail.unit = true
    k.settings:set(K.SETTING, false)
    tick(c)
    t.eq(said(c, "could not be set"), 2, "a new failure after a success is said again")
end

tests["key frame module: a client with no secure button says so once"] = function(t)
    local k, c, made, api = start({ noSecure = true })
    c.advance(2, 10)
    t.eq(#made, 0)
    t.eq(api.status().state, "noFrame")
    t.eq(k.problems:count(K.NAME), 1, "said once")
end

tests["key frame module: the keys word prints the state"] = function(t)
    local k, c = start({ keys = false })
    c.slashes[ns.id.slash](K.WORD)
    t.eq(said(c, "is off"), 1)
    k.settings:set(K.SETTING, true)
    tick(c)
    c.slashes[ns.id.slash](K.WORD)
    t.eq(said(c, "key: Wrath"), 1)
    c.setCombat(true)
    c.slashes[ns.id.slash](K.WORD .. " apply")
    t.eq(said(c, "key: Wrath"), 2, "nothing waits, so it says what is set")
    for _, line in ipairs(c.printed) do
        local rest = line:gsub(ns.id.title, "")
        t.eq(rest:find("Flow", 1, true), nil, "only the title names the addon: " .. line)
    end
end

tests["key frame module: keys apply in a fight sets nothing"] = function(t)
    local k, c, made, api = start({ keys = false })
    c.secureButton = function(spec)
        local h = button(c.combatLockdown)
        h.spec, h.fail.spell = spec, true
        made[#made + 1] = h
        return h
    end
    k.settings:set(K.SETTING, true)
    tick(c)
    made[1].fail.spell = nil
    local n = #made[1].reached
    c.setLockdown(true)
    c.slashes[ns.id.slash](K.WORD .. " apply")
    t.eq(#made[1].reached, n)
    t.eq(made[1].inLock, 0)
    t.eq(api.status().state, "waiting")
    c.setLockdown(false)
    c.slashes[ns.id.slash](K.WORD .. " apply")
    t.eq(api.status().state, "set")
    t.eq(made[1].attrs.spell, "Wrath")
end

tests["key frame module: the word and its help are given to the slash command"] = function(t)
    local c = ns.make.fakeClient()
    local k = ns.Kernel({}, c)
    D.Declare(k, { [CLASS] = pack() })
    local diag = { commands = {}, help = {} }
    K.Declare(k, diag)
    t.eq(type(diag.commands[K.WORD]), "function")
    t.eq(type(K.HELP), "string")
    t.eq(diag.help[K.WORD], K.HELP)
end

return tests
