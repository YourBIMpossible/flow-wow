local _, ns = ...
-- S23 (P-KEYS slice B): c.bindingOverride(key, forAction), what a key does
-- with override bindings counted (GetBindingAction(key, true)), on the real
-- client over a hand-built environment, then ClientFake's twin. A read
-- only: nothing is bound. "" for nothing, nil when not known, never a
-- guess. First guess: not seen in game. Made-up keys and actions.
local tests = {}

local ACTION = "CLICK ZFlowRotationKey:LeftButton"
local OTHER = "CLICK SomeClickCastButton:LeftButton"   -- made up
local CONTEXT = 7                                      -- made up

local function env(opts)
    opts = opts or {}
    local e = { calls = {} }
    e.InCombatLockdown = function() return false end
    if opts.context ~= false then
        e.C_KeyBindings = { GetBindingContextForAction = function() return CONTEXT end }
    end
    e.GetBindingAction = function(key, checkOverride, context)
        e.calls[#e.calls + 1] = { key = key, over = checkOverride, context = context }
        if opts.fails then error("GetBindingAction failed (test)") end
        if checkOverride and opts.over and opts.over[key] ~= nil then return opts.over[key] end
        return (opts.base or {})[key]
    end
    for _, name in ipairs({ "SetBinding", "SetBindingClick", "SetOverrideBindingClick", "ClearOverrideBindings", "SaveBindings" }) do
        e[name] = function() e.calls[#e.calls + 1] = { write = name } end
    end
    return e
end

local function writes(e)
    local n = 0
    for _, c in ipairs(e.calls) do if c.write then n = n + 1 end end
    return n
end

tests["c.bindingOverride: the override that wins on the key, asked with checkOverride and our context"] = function(t)
    local e = env({ base = { F = ACTION }, over = { F = OTHER } })
    local c = ns.make.client(e)
    if type(c.bindingOverride) ~= "function" then t.ok(false, "c.bindingOverride is there") return end
    t.eq(c.bindingOverride("F", ACTION), OTHER)
    local last = e.calls[#e.calls] or {}
    t.eq(last.over, true, "asked with override bindings counted")
    t.eq(last.context, CONTEXT, "with our action's context")
    t.eq(writes(e), 0, "nothing written")
end

tests["c.bindingOverride: no override gives the game's own binding; nothing bound is \"\""] = function(t)
    local c = ns.make.client(env({ base = { F = ACTION }, context = false }))
    if type(c.bindingOverride) ~= "function" then t.ok(false, "c.bindingOverride is there") return end
    t.eq(c.bindingOverride("F", ACTION), ACTION)
    t.eq(c.bindingOverride("G", ACTION), "")
end

tests["c.bindingOverride: a raise, no call, or no key is nil, never a guess"] = function(t)
    local c = ns.make.client(env({ fails = true }))
    if type(c.bindingOverride) ~= "function" then t.ok(false, "c.bindingOverride is there") return end
    t.eq(c.bindingOverride("F", ACTION), nil)
    t.eq(c.bindingOverride("", ACTION), nil)
    t.eq(c.bindingOverride(nil, ACTION), nil)
    local bare = ns.make.client({})
    t.eq(bare.bindingOverride("F", ACTION), nil)
end

tests["fake c.bindingOverride: another add-on's override wins, then ours, then the game's binding"] = function(t)
    local c = ns.make.fakeClient()
    if type(c.bindingOverride) ~= "function" or type(c.setForeignOverride) ~= "function"
        or type(c.setBindingOverrideFails) ~= "function" then
        t.ok(false, "the fake's c.bindingOverride, c.setForeignOverride and c.setBindingOverrideFails")
        return
    end
    c.setLockdown(false)
    c.setBindings({ { "F", ACTION } })
    t.eq(c.bindingOverride("F"), ACTION)
    t.eq(c.bindingOverride("G"), "")
    c.overrideBindingClick("G", "ZFlowRotationKey")
    t.eq(c.bindingOverride("G"), ACTION, "our own session override")
    c.setForeignOverride("F", OTHER)
    t.eq(c.bindingOverride("F"), OTHER)
    c.setForeignOverride("F", nil)
    t.eq(c.bindingOverride("F"), ACTION)
    c.setBindingOverrideFails(true)
    t.ok(not pcall(c.bindingOverride, "F"), "a failing read raises")
    c.setBindingOverrideFails(false)
    t.eq(c.bindingOverride("F"), ACTION, "and recovers")
    c.setBindingReads(false)
    t.eq(c.bindingOverride("F"), nil, "bindings not read: not known")
end

return tests
