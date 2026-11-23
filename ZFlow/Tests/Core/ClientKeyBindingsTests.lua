-- N57 (key-binding capture and unbind; lead section 249 item 2, Plexy's
-- note 1 of section 250): the binding wrappers and the key-capture overlay
-- the real client adds, over a hand-built environment, then ClientFake's
-- twins. Every read the client does not give is nil (not known), never ""
-- or {}; every write refuses while the lock is not a plain false and never
-- raises. Made-up keys and actions. Not seen in game.
--   c.bindingKeys(action)            -> { key, ... } | nil
--   c.bindingAction(key, forAction)  -> action text ("" for none) | nil
--   c.setBindingClick(key, button)   -> true | false, why      (acting)
--   c.clearBinding(key, forAction)   -> true | false, why      (acting)
--   c.saveBindings()                 -> true | false, why      (acting)
--   c.overrideBindingClick(key, button) -> true | false, why   (acting)
--   c.clearOverrideKeys()            -> true | false, why      (acting)
--   c.keyCapture(spec)               -> h | nil                (show)
local _, ns = ...

local tests = {}

local ACTION = "CLICK ZFlowRotationKey:LeftButton"
local OTHER = "TOGGLEWORLDMAP"                         -- made up for these tests
local CONTEXT = 7                                      -- made up

local function frame()
    local f = { scripts = {}, shown = true, texts = {} }
    function f.SetScript(self, name, fn) self.scripts[name] = fn end
    function f.Show(self) self.shown = true end
    function f.Hide(self) self.shown = false end
    function f.IsShown(self) return self.shown end
    function f.CreateFontString(self)
        local fs = {}
        function fs.SetText(_, text) f.texts[#f.texts + 1] = text end
        return fs
    end
    return f
end

local function bindEnv(extra)
    local env = { calls = {}, keys = {}, actions = {}, lock = false, frames = {} }
    local function log(...) env.calls[#env.calls + 1] = { ... } end
    env.InCombatLockdown = function() return env.lock end
    env.C_KeyBindings = { GetBindingContextForAction = function() return CONTEXT end }
    env.GetBindingKey = function(action, _, context)
        log("GetBindingKey", action, context)
        return unpack(env.keys[action] or {})
    end
    env.GetBindingAction = function(key, _, context)
        log("GetBindingAction", key, context)
        return env.actions[key] or ""
    end
    env.SetBindingClick = function(...) log("SetBindingClick", ...) return true end
    env.SetBinding = function(...) log("SetBinding", ...) return true end
    env.SetOverrideBindingClick = function(...) log("SetOverrideBindingClick", ...) return true end
    env.ClearOverrideBindings = function(...) log("ClearOverrideBindings", ...) end
    env.GetCurrentBindingSet = function() return 2 end
    env.SaveBindings = function(...) log("SaveBindings", ...) end
    env.CreateFrame = function()
        local f = frame()
        env.frames[#env.frames + 1] = f
        return f
    end
    env.UIParent = frame()
    for k, v in pairs(extra or {}) do env[k] = v end
    return env
end

local function called(env, name)
    local out = {}
    for _, c in ipairs(env.calls) do
        if c[1] == name then out[#out + 1] = c end
    end
    return out
end

local WRITES = { "SetBindingClick", "SetBinding", "SetOverrideBindingClick", "ClearOverrideBindings", "SaveBindings" }

-- Fails before: Core/Client.lua has none of the binding wrappers.
tests["c.bindingKeys: the action's keys in the game's order, with the action's context; none is an empty list"] = function(t)
    local env = bindEnv()
    env.keys[ACTION] = { "CTRL-F", "G" }
    local c = ns.make.client(env)
    t.ok(type(c.bindingKeys) == "function", "the read is there")
    if type(c.bindingKeys) ~= "function" then return end
    t.eq(c.bindingKeys(ACTION), { "CTRL-F", "G" })
    t.eq(called(env, "GetBindingKey")[1][3], CONTEXT, "the context is passed (Plexy note 1, change 1)")
    env.keys[ACTION] = nil
    t.eq(c.bindingKeys(ACTION), {}, "no key bound is an empty list")
end

tests["c.bindingKeys and c.bindingAction: a raise or no call is nil, never a guess"] = function(t)
    local raising = ns.make.client(bindEnv({
        GetBindingKey = function() error("no") end,
        GetBindingAction = function() error("no") end,
    }))
    if type(raising.bindingKeys) ~= "function" or type(raising.bindingAction) ~= "function" then
        t.ok(false, "the reads are there")
        return
    end
    t.eq(raising.bindingKeys(ACTION), nil)
    t.eq(raising.bindingAction("F", ACTION), nil)
    local bare = ns.make.client(bindEnv({ GetBindingKey = false, GetBindingAction = false }))
    t.eq(bare.bindingKeys(ACTION), nil)
    t.eq(bare.bindingAction("F", ACTION), nil)
end

tests["c.bindingAction: what the key does, \"\" for nothing, with our action's context"] = function(t)
    local env = bindEnv()
    env.actions.M = OTHER
    local c = ns.make.client(env)
    if type(c.bindingAction) ~= "function" then t.ok(false, "the read is there") return end
    t.eq(c.bindingAction("M", ACTION), OTHER)
    t.eq(c.bindingAction("N", ACTION), "")
    t.eq(called(env, "GetBindingAction")[1][3], CONTEXT)
end

tests["binding writes: each goes to its one client call, out of combat only"] = function(t)
    local env = bindEnv()
    local c = ns.make.client(env)
    for _, name in ipairs({ "setBindingClick", "clearBinding", "saveBindings", "overrideBindingClick", "clearOverrideKeys" }) do
        t.ok(type(c[name]) == "function", "the write is there: " .. name)
        if type(c[name]) ~= "function" then return end
    end
    t.eq(c.setBindingClick("CTRL-F", "ZFlowRotationKey"), true)
    t.eq(called(env, "SetBindingClick")[1], { "SetBindingClick", "CTRL-F", "ZFlowRotationKey", "LeftButton" })
    t.eq(c.clearBinding("M", ACTION), true)
    t.eq(called(env, "SetBinding")[1], { "SetBinding", "M", nil, CONTEXT })
    t.eq(c.saveBindings(), true)
    t.eq(called(env, "SaveBindings")[1], { "SaveBindings", 2 }, "the current set, as the game's panel saves it")
    t.eq(c.overrideBindingClick("M", "ZFlowRotationKey"), true)
    local o = called(env, "SetOverrideBindingClick")[1]
    t.eq({ o[3], o[4], o[5], o[6] }, { true, "M", "ZFlowRotationKey", "LeftButton" })
    t.ok(type(o[2]) == "table", "an owner frame of the client's")
    t.eq(c.clearOverrideKeys(), true)
    t.eq(called(env, "ClearOverrideBindings")[1][2], o[2], "the same owner")
end

tests["binding writes: refused in combat and with the lock not read; nothing is called"] = function(t)
    for _, lock in ipairs({ "on", "raises", "absent" }) do
        local env = bindEnv()
        if lock == "on" then env.lock = true end
        if lock == "raises" then env.InCombatLockdown = function() error("no") end end
        if lock == "absent" then env.InCombatLockdown = nil end
        local c = ns.make.client(env)
        if type(c.setBindingClick) ~= "function" then t.ok(false, "the writes are there") return end
        local results = {
            { c.setBindingClick("F", "ZFlowRotationKey") }, { c.clearBinding("F", ACTION) }, { c.saveBindings() },
            { c.overrideBindingClick("F", "ZFlowRotationKey") }, { c.clearOverrideKeys() },
        }
        for i, r in ipairs(results) do
            t.eq(r[1], false, lock .. ": write " .. i .. " refused")
            t.eq(r[2], "lockdown", lock .. ": write " .. i .. " says why")
        end
        for _, name in ipairs(WRITES) do t.eq(#called(env, name), 0, lock .. ": not called: " .. name) end
    end
end

tests["binding writes: a raise or a refusal is false and why, never an error"] = function(t)
    local env = bindEnv({
        SetBindingClick = function() error("boom") end,
        SetBinding = function() return false end,
        GetCurrentBindingSet = function() return nil end,
    })
    local c = ns.make.client(env)
    if type(c.setBindingClick) ~= "function" then t.ok(false, "the writes are there") return end
    local ok, why = c.setBindingClick("F", "ZFlowRotationKey")
    t.eq(ok, false)
    t.ok(type(why) == "string" and why:find("boom", 1, true) ~= nil, tostring(why))
    t.eq((c.clearBinding("F", ACTION)), false, "SetBinding said false")
    t.eq((c.saveBindings()), false, "no binding set read: nothing saved")
    t.eq(#called(env, "SaveBindings"), 0)
    local bare = ns.make.client(bindEnv({ SetBindingClick = false }))
    t.eq((bare.setBindingClick("F", "ZFlowRotationKey")), false, "no call: refused")
end

tests["making the client binds nothing and saves nothing"] = function(t)
    local env = bindEnv()
    local c = ns.make.client(env)
    if type(c.keyCapture) == "function" then c.keyCapture({ name = "ZFlowKeyCapture" }) end
    for _, name in ipairs(WRITES) do t.eq(#called(env, name), 0, "not called: " .. name) end
end

tests["c.keyCapture: the overlay takes one key press as a chord; Escape cancels; a bare modifier waits"] = function(t)
    local env = bindEnv({
        IsKeyPressIgnoredForBinding = function(key) return key == "LSHIFT" end,
        CreateKeyChordStringUsingMetaKeyState = function(key) return "CTRL-" .. key end,
    })
    local c = ns.make.client(env)
    t.ok(type(c.keyCapture) == "function", "the overlay is there")
    if type(c.keyCapture) ~= "function" then return end
    local h = c.keyCapture({ name = "ZFlowKeyCapture" })
    t.ok(type(h) == "table", "a handle")
    if type(h) ~= "table" then return end
    local f = env.frames[#env.frames]
    t.eq(h.open(), false, "made hidden")
    local got, cancelled = {}, 0
    t.eq(h.start("Press a key", function(key) got[#got + 1] = key end, function() cancelled = cancelled + 1 end), true)
    t.eq(h.open(), true)
    t.ok(type(f.scripts.OnKeyDown) == "function", "listens to key presses")
    f.scripts.OnKeyDown(f, "LSHIFT")
    t.eq(got, {}, "a bare modifier is not a key")
    t.eq(h.open(), true, "still waiting")
    f.scripts.OnKeyDown(f, "F")
    t.eq(got, { "CTRL-F" }, "the chord the game builds")
    t.eq(h.open(), false, "closed after one key")
    h.start("Press a key", function(key) got[#got + 1] = key end, function() cancelled = cancelled + 1 end)
    f.scripts.OnKeyDown(f, "ESCAPE")
    t.eq(cancelled, 1)
    t.eq(#got, 1, "Escape is never a key")
    t.eq(h.open(), false)
    for _, name in ipairs(WRITES) do t.eq(#called(env, name), 0, "the overlay binds nothing: " .. name) end
end

tests["c.keyCapture: without the game's chord builder the modifiers held make the chord"] = function(t)
    local env = bindEnv({
        IsAltKeyDown = function() return false end,
        IsControlKeyDown = function() return true end,
        IsShiftKeyDown = function() return true end,
    })
    local c = ns.make.client(env)
    if type(c.keyCapture) ~= "function" then t.ok(false, "the overlay is there") return end
    local h = c.keyCapture({})
    local got
    h.start("", function(key) got = key end, function() end)
    local f = env.frames[#env.frames]
    f.scripts.OnKeyDown(f, "RCTRL")
    t.eq(got, nil, "a bare modifier is not a key")
    f.scripts.OnKeyDown(f, "F")
    t.eq(got, "CTRL-SHIFT-F")
end

-- Fails before: Core/Diag.lua's NAMES lacks the names never asked of 16001.
tests["the binding names these wrappers ask, and Plexy's never-asked ones, are in the capture's name list"] = function(t)
    local listed = {}
    for _, name in ipairs(ns.Diag.NAMES) do listed[name] = true end
    for _, name in ipairs({ "SetBinding", "SetBindingClick", "SetOverrideBindingClick", "ClearOverrideBindings",
        "GetBindingKey", "SaveBindings", "GetCurrentBindingSet",
        "GetBindingAction", "SetOverrideBinding", "SetBindingSpell", "SetBindingMacro", "SetBindingItem",
        "GetBinding", "GetNumBindings", "LoadBindings", "C_KeyBindings.GetBindingContextForAction",
        "C_KeyBindings.GetBindingByKey", "C_KeyBindings.GetBindingIndex", "RunBinding",
        "CreateKeyChordStringUsingMetaKeyState", "IsKeyPressIgnoredForBinding", "GetConvertedKeyOrButton" }) do
        t.ok(listed[name], name)
    end
end

-- The fake's twins -----------------------------------------------------------

tests["the fake client has every binding twin and its test switches"] = function(t)
    local c = ns.make.fakeClient()
    for _, name in ipairs({ "bindingKeys", "bindingAction", "setBindingClick", "clearBinding", "saveBindings",
        "overrideBindingClick", "clearOverrideKeys", "keyCapture",
        "setBindings", "bindingMap", "savedBindingMap", "overrideKeys", "bindingCalls",
        "setBindingReads", "setBindingWriteFault", "pressKey", "keyCaptureOpen" }) do
        t.ok(type(c[name]) == "function", name)
    end
end

tests["the fake's bindings: set, saved apart from live, read back, refused in combat"] = function(t)
    local c = ns.make.fakeClient()
    if type(c.setBindings) ~= "function" then t.ok(false, "the twins are there") return end
    c.setLockdown(false)
    c.setBindings({ { "M", OTHER } })
    t.eq(c.bindingAction("M", ACTION), OTHER)
    t.eq(c.bindingAction("F", ACTION), "")
    t.eq(c.setBindingClick("F", "ZFlowRotationKey"), true)
    t.eq(c.bindingKeys(ACTION), { "F" })
    t.eq(c.savedBindingMap().F, nil, "not saved until saveBindings")
    t.eq(c.saveBindings(), true)
    t.eq(c.savedBindingMap().F, ACTION)
    c.setLockdown(true)
    t.eq({ c.clearBinding("F", ACTION) }, { false, "lockdown" })
    c.setLockdown(nil)
    t.eq({ c.saveBindings() }, { false, "lockdown" }, "not known counts as locked")
    c.setLockdown(false)
    c.setBindingReads(false)
    t.eq(c.bindingKeys(ACTION), nil)
    t.eq(c.bindingAction("M", ACTION), nil)
    c.setBindingReads(true)
    c.setBindingWriteFault(1)
    t.eq(pcall(c.setBindingClick, "G", "ZFlowRotationKey"), false, "the fault raises once")
    t.eq(c.setBindingClick("G", "ZFlowRotationKey"), true, "then fine")
    t.eq(c.bindingCalls(), { "setBindingClick", "saveBindings", "setBindingClick" })
end

return tests
