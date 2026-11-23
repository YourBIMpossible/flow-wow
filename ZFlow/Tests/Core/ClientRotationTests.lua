-- The rotation helper's client reads (F6): form(), petBattle(), vehicle()
-- and secureButton(). The real client over a hand-built environment (`env`
-- stands in for the game's globals), then the fake. Not tested in game.
local _, ns = ...

local function boom() error("the client refused") end

-- issecretvalue that refuses nil, as the client's does.
local function strictSecret(env, secret)
    env.issecretvalue = function(v)
        if v == nil then error("issecretvalue: nil") end
        return secret ~= nil and secret(v) or false
    end
end

-- An environment that makes frames and records how: env.made lists
-- { kind, name, parent, template, frame }. lock: what InCombatLockdown
-- answers (env.lock, changed between calls). Each frame records every
-- method called on it in frame.calls.
local function secureEnv(lock)
    local env = { made = {}, lock = lock, lockAsked = 0, UIParent = { isParent = true } }
    function env.InCombatLockdown()
        env.lockAsked = env.lockAsked + 1
        return env.lock
    end
    function env.CreateFrame(kind, name, parent, template)
        local f = { attrs = {}, calls = {} }
        function f:Hide() self.calls[#self.calls + 1] = "Hide" end
        function f:SetAttribute(attr, value)
            self.calls[#self.calls + 1] = "SetAttribute"
            if env.refuse then error("blocked") end
            self.attrs[attr] = value
        end
        function f:GetAttribute(attr)
            self.calls[#self.calls + 1] = "GetAttribute"
            return self.attrs[attr]
        end
        env.made[#env.made + 1] = { kind = kind, name = name, parent = parent, template = template, frame = f }
        return f
    end
    return env
end

local function count(list, what)
    local n = 0
    for _, v in ipairs(list) do
        if v == what then n = n + 1 end
    end
    return n
end

return {
    -- ------------------------------------------------------------- form
    ["client form: the number the client gives, 0 for no form"] = function(t)
        local env = { GetShapeshiftForm = function() return 3 end }
        strictSecret(env)
        t.eq(ns.make.client(env).form(), 3)
        env.GetShapeshiftForm = function() return 0 end
        t.eq(ns.make.client(env).form(), 0)
    end,

    ["client form: not known when the client has no such call, fails, or gives no number"] = function(t)
        t.eq(ns.make.client({}).form(), nil, "no call")
        t.eq(ns.make.client({ GetShapeshiftForm = boom }).form(), nil, "a failed call")
        t.eq(ns.make.client({ GetShapeshiftForm = function() return nil end }).form(), nil, "no answer")
        t.eq(ns.make.client({ GetShapeshiftForm = function() return "1" end }).form(), nil, "text is no number")
        t.eq(ns.make.client({ GetShapeshiftForm = function() return true end }).form(), nil)
    end,

    ["client form: a secret answer is not known"] = function(t)
        local env = { GetShapeshiftForm = function() return 2 end }
        strictSecret(env, function() return true end)
        t.eq(ns.make.client(env).form(), nil)
    end,

    ["client form: it names no unit"] = function(t)
        local args
        local env = { GetShapeshiftForm = function(...)
            args = select("#", ...)
            return 1
        end }
        ns.make.client(env).form()
        t.eq(args, 0)
    end,

    -- -------------------------------------------------------- petBattle
    ["client petBattle: true and false as the client gives them"] = function(t)
        local env = { C_PetBattles = { IsInBattle = function() return true end } }
        t.eq(ns.make.client(env).petBattle(), true)
        env.C_PetBattles.IsInBattle = function() return false end
        t.eq(ns.make.client(env).petBattle(), false)
    end,

    ["client petBattle: not known without the call, on a failure, or on no plain answer"] = function(t)
        t.eq(ns.make.client({}).petBattle(), nil, "no C_PetBattles")
        t.eq(ns.make.client({ C_PetBattles = {} }).petBattle(), nil, "no IsInBattle")
        t.eq(ns.make.client({ C_PetBattles = "x" }).petBattle(), nil)
        t.eq(ns.make.client({ C_PetBattles = { IsInBattle = boom } }).petBattle(), nil, "a failed call")
        t.eq(ns.make.client({ C_PetBattles = { IsInBattle = function() return nil end } }).petBattle(), nil)
        t.eq(ns.make.client({ C_PetBattles = { IsInBattle = function() return 1 end } }).petBattle(), nil)
    end,

    ["client petBattle: a secret answer is not known"] = function(t)
        local env = { C_PetBattles = { IsInBattle = function() return true end } }
        strictSecret(env, function() return true end)
        t.eq(ns.make.client(env).petBattle(), nil)
    end,

    -- ---------------------------------------------------------- vehicle
    ["client vehicle: true and false, asked only about you"] = function(t)
        local asked = {}
        local answer = true
        local env = { UnitInVehicle = function(unit)
            asked[#asked + 1] = unit
            return answer
        end }
        t.eq(ns.make.client(env).vehicle(), true)
        answer = false
        t.eq(ns.make.client(env).vehicle(), false)
        t.eq(asked, { "player", "player" })
    end,

    ["client vehicle: not known without the call, on a failure, or on no plain answer"] = function(t)
        t.eq(ns.make.client({}).vehicle(), nil, "no call")
        t.eq(ns.make.client({ UnitInVehicle = boom }).vehicle(), nil, "a failed call")
        t.eq(ns.make.client({ UnitInVehicle = function() return nil end }).vehicle(), nil)
        t.eq(ns.make.client({ UnitInVehicle = function() return 1 end }).vehicle(), nil)
    end,

    ["client vehicle: a secret answer is not known"] = function(t)
        local env = { UnitInVehicle = function() return false end }
        strictSecret(env, function() return true end)
        t.eq(ns.make.client(env).vehicle(), nil)
    end,

    -- ----------------------------------------------------- secureButton
    ["client secureButton: made as a button from the key frame's template, under the screen"] = function(t)
        local env = secureEnv(false)
        local h = ns.make.client(env).secureButton({ name = "TestKey" })
        t.eq(type(h), "table")
        t.eq(#env.made, 1)
        t.eq(env.made[1].kind, "Button")
        t.eq(env.made[1].name, "TestKey")
        t.eq(env.made[1].parent, env.UIParent)
        t.eq(env.made[1].template, "SecureActionButtonTemplate")
        t.eq(env.made[1].template, ns.KeyFrame.TEMPLATE, "the template the key frame names")
    end,

    ["client secureButton: nil when the client makes no frame"] = function(t)
        t.eq(ns.make.client({}).secureButton({ name = "TestKey" }), nil, "no CreateFrame")
        t.eq(ns.make.client({ CreateFrame = boom }).secureButton({ name = "TestKey" }), nil, "a failed call")
        t.eq(ns.make.client({ CreateFrame = function() return nil end }).secureButton({}), nil, "no frame back")
    end,

    ["client secureButton: hidden when made outside a fight"] = function(t)
        local env = secureEnv(false)
        ns.make.client(env).secureButton({ name = "TestKey" })
        t.eq(count(env.made[1].frame.calls, "Hide"), 1)
    end,

    ["client secureButton: made in a fight, or with the lock not known, the frame is not touched"] = function(t)
        local env = secureEnv(true)
        ns.make.client(env).secureButton({ name = "TestKey" })
        t.eq(#env.made[1].frame.calls, 0, "in a fight")
        env = secureEnv(nil)
        ns.make.client(env).secureButton({ name = "TestKey" })
        t.eq(#env.made[1].frame.calls, 0, "the lock gave no answer")
        env = secureEnv(false)
        env.InCombatLockdown = nil
        ns.make.client(env).secureButton({ name = "TestKey" })
        t.eq(#env.made[1].frame.calls, 0, "no lock call")
    end,

    ["client secureButton: set outside a fight puts the attribute on the frame"] = function(t)
        local env = secureEnv(false)
        local h = ns.make.client(env).secureButton({ name = "TestKey" })
        local ok, why = h.set("type", "spell")
        t.eq(ok, true)
        t.eq(why, nil)
        t.eq(env.made[1].frame.attrs.type, "spell")
        t.eq(h.get("type"), "spell")
        t.eq(h.get("spell"), nil, "nothing held for it")
    end,

    ["client secureButton: set asks the lock each time, before the frame"] = function(t)
        local env = secureEnv(false)
        local h = ns.make.client(env).secureButton({ name = "TestKey" })
        local before = env.lockAsked
        h.set("type", "spell")
        h.set("spell", "Wrath")
        t.eq(env.lockAsked - before, 2)
    end,

    ["client secureButton: set in a fight is refused and the frame is not asked"] = function(t)
        local env = secureEnv(false)
        local h = ns.make.client(env).secureButton({ name = "TestKey" })
        h.set("type", "spell")
        env.lock = true
        local ok, why = h.set("type", "item")
        t.eq(ok, false)
        t.eq(why, "lockdown")
        t.eq(count(env.made[1].frame.calls, "SetAttribute"), 1, "only the one from outside the fight")
        t.eq(h.get("type"), "spell", "what it held stays")
    end,

    ["client secureButton: a lock that is not a plain false is the lock"] = function(t)
        local env = secureEnv(false)
        local h = ns.make.client(env).secureButton({ name = "TestKey" })
        for _, answer in ipairs({ "nil", 1, "no", 0 }) do
            env.lock = answer ~= "nil" and answer or nil
            local ok, why = h.set("type", "spell")
            t.eq(ok, false, tostring(answer))
            t.eq(why, "lockdown", tostring(answer))
        end
        env.InCombatLockdown = boom
        t.eq({ h.set("type", "spell") }, { false, "lockdown" }, "the lock call failed")
        env.InCombatLockdown = nil
        t.eq({ h.set("type", "spell") }, { false, "lockdown" }, "no lock call")
        t.eq(count(env.made[1].frame.calls, "SetAttribute"), 0)
    end,

    ["client secureButton: a frame that refuses the attribute is refused, not an error"] = function(t)
        local env = secureEnv(false)
        local h = ns.make.client(env).secureButton({ name = "TestKey" })
        env.refuse = true
        local ok, why = h.set("type", "spell")
        t.eq(ok, false)
        t.eq(why, "refused")
        t.eq(h.get("type"), nil)
    end,

    ["client secureButton: a frame with no attribute methods refuses and holds nothing"] = function(t)
        local env = { InCombatLockdown = function() return false end, CreateFrame = function() return {} end }
        local h = ns.make.client(env).secureButton({ name = "TestKey" })
        t.eq({ h.set("type", "spell") }, { false, "refused" })
        t.eq(h.get("type"), nil)
    end,

    ["client secureButton: nothing but making, hiding and attributes is asked of the client"] = function(t)
        local env = secureEnv(false)
        local called = {}
        for _, name in ipairs({ "SetBinding", "SetBindingClick", "SetOverrideBinding", "SetOverrideBindingClick",
            "RegisterStateDriver", "CastSpellByName", "CastSpellByID", "UseAction", "RunMacroText" }) do
            env[name] = function() called[#called + 1] = name end
        end
        local h = ns.make.client(env).secureButton({ name = "TestKey" })
        h.set("type", "spell")
        h.get("type")
        t.eq(called, {})
        local f = env.made[1].frame
        t.eq(#f.calls, count(f.calls, "Hide") + count(f.calls, "SetAttribute") + count(f.calls, "GetAttribute"))
    end,

    -- -------------------------------------------------------------- fake
    ["fake client: form, petBattle and vehicle start not known and follow their setters"] = function(t)
        local c = ns.make.fakeClient()
        t.eq(c.form(), nil)
        t.eq(c.petBattle(), nil)
        t.eq(c.vehicle(), nil)
        c.setForm(0)
        t.eq(c.form(), 0)
        c.setForm(3)
        t.eq(c.form(), 3)
        c.setForm(nil)
        t.eq(c.form(), nil)
        c.setPetBattle(true)
        c.setVehicle(false)
        t.eq(c.petBattle(), true)
        t.eq(c.vehicle(), false)
        c.setPetBattle(nil)
        t.eq(c.petBattle(), nil)
    end,

    ["fake client: a secure button holds what is set outside a fight"] = function(t)
        local c = ns.make.fakeClient()
        local h = c.secureButton({ name = "TestKey" })
        t.eq(c.secureButtons, { h })
        t.eq(h.spec.name, "TestKey")
        t.eq({ h.set("type", "spell") }, { true })
        t.eq(h.attrs, { type = "spell" })
        t.eq(h.get("type"), "spell")
    end,

    ["fake client: a secure button refuses in a fight and while the lock is not known"] = function(t)
        local c = ns.make.fakeClient()
        local h = c.secureButton({ name = "TestKey" })
        c.setCombat(true)
        t.eq({ h.set("type", "spell") }, { false, "lockdown" })
        c.setCombat(false)
        t.eq({ h.set("type", "spell") }, { true })
        c.setLockdown(nil)
        t.eq({ h.set("type", "item") }, { false, "lockdown" })
        t.eq(h.get("type"), "spell")
    end,

    ["fake client: an attribute can be made to fail or to be dropped"] = function(t)
        local c = ns.make.fakeClient()
        local h = c.secureButton({ name = "TestKey" })
        c.failSecureAttr("type", true)
        t.eq({ h.set("type", "spell") }, { false, "refused" })
        c.failSecureAttr("type", false)
        c.dropSecureAttr("type", true)
        t.eq({ h.set("type", "spell") }, { true })
        t.eq(h.get("type"), nil, "answered true, kept nothing")
        c.dropSecureAttr("type", false)
        t.eq({ h.set("type", "spell") }, { true })
        t.eq(h.get("type"), "spell")
    end,

    ["fake client: no frames, no secure button"] = function(t)
        local c = ns.make.fakeClient()
        c.setFrames(false)
        t.eq(c.secureButton({ name = "TestKey" }), nil)
        t.eq(#c.secureButtons, 0)
    end,

    -- Section 246 (N63-E): the fake logs every set, kept or refused, and
    -- names the ones that would make a button a macro.
    ["fake client: every secure set is logged, and a macro is named"] = function(t)
        local c = ns.make.fakeClient()
        local h = c.secureButton({ name = "TestKey" })
        h.set("type", "spell")
        h.set("*type-alt", "item")
        h.set("*item-alt", "item:5512")
        h.set("macrotext", nil)
        t.eq(#h.given, 4, "four sets on the button")
        t.eq(#c.secureGiven, 4, "four over every button")
        t.eq(c.secureGiven[3], { name = "TestKey", attr = "*item-alt", value = "item:5512" })
        t.eq(#c.secureMacros(), 0, "no macro: a cleared macro text is none")
        c.setCombat(true)
        h.set("shift-type1", "macro")
        t.eq(#c.secureGiven, 5, "a refused set is logged too")
        c.setCombat(false)
        h.set("*macrotext-alt", "/use item:5512")
        local m = c.secureMacros()
        t.eq(#m, 2, "both named")
        t.eq(m[1].attr, "shift-type1")
        t.eq(m[2].attr, "*macrotext-alt")
    end,

    -- Section 249 (CT-2): upper case and the plain "macro" attribute are
    -- caught too; each on its own fresh client.
    ["fake client: MACRO in any case and the plain macro attribute are named"] = function(t)
        local cases = {
            { "type", "MACRO" }, { "Type", "Macro" }, { "*TYPE-alt", "macro" },
            { "macro", "MyMacro" }, { "macro", 3 }, { "*macro-alt", "X" },
            { "MacroText", "/cast Wrath" }, { "MACROTEXT", "/startattack" },
        }
        for _, case in ipairs(cases) do
            local c = ns.make.fakeClient()
            local h = c.secureButton({ name = "TestKey" })
            h.set(case[1], case[2])
            local m = c.secureMacros()
            t.eq(#m, 1, tostring(case[1]) .. " = " .. tostring(case[2]) .. ": named")
        end
        local c = ns.make.fakeClient()
        local h = c.secureButton({ name = "TestKey" })
        h.set("type", "spell"); h.set("macro", nil); h.set("MACROTEXT", nil); h.set("spell", "Macro Shield")
        t.eq(#c.secureMacros(), 0, "cleared macro rows and a spell named Macro are none")
    end,
}
