-- client.panel({ closable = true }): the one panel every window uses
-- (F9 prerequisite). A close button and the Escape route, and onClose told
-- only when the player closed it. No game client is involved: a stand-in
-- for the globals of the client, and the fake.
local _, ns = ...

-- Every frame made is in env.frames, in order. Hide runs OnHide the way
-- the game does (after the frame is no longer shown). opts.noButton: the
-- client cannot make a Button. opts.noList: it has no UISpecialFrames.
local function gameEnv(opts)
    opts = opts or {}
    local env = { frames = {}, UIParent = {} }
    if not opts.noList then env.UISpecialFrames = { "SomeoneElse" } end
    function env.CreateFrame(kind, name, parent, template)
        if kind == "Button" and opts.noButton then error("no buttons") end
        local f = { kind = kind, name = name, parent = parent, template = template, scripts = {}, shown = true }
        function f:SetScript(script, fn) self.scripts[script] = fn end
        function f:GetPoint() return "CENTER", env.UIParent, "CENTER", 10, 20 end
        function f:IsShown() return self.shown end
        function f:Show() self.shown = true end
        function f:Hide()
            local was = self.shown
            self.shown = false
            if was and self.scripts.OnHide then self.scripts.OnHide(self) end
        end
        env.frames[#env.frames + 1] = f
        if name ~= nil and env[name] == nil then env[name] = f end
        return f
    end
    return env
end

-- The frame of the panel and its close button (a Button on it), or nil.
local function parts(env)
    local frame, button = env.frames[1], nil
    for i = 2, #env.frames do
        if env.frames[i].kind == "Button" and env.frames[i].parent == frame then button = env.frames[i] end
    end
    return frame, button
end

local function listed(env, name)
    local n = 0
    for i = 1, #(env.UISpecialFrames or {}) do
        if env.UISpecialFrames[i] == name then n = n + 1 end
    end
    return n
end

local function closable(env, extra)
    local spec = { name = "TestClosable", width = 200, height = 80, closable = true }
    for key, value in pairs(extra or {}) do spec[key] = value end
    return ns.make.client(env).panel(spec)
end

return {
    ["panel close: a closable panel has a close button and is in the Escape list once"] = function(t)
        local env = gameEnv()
        local h = closable(env)
        local frame, button = parts(env)
        t.ok(button ~= nil, "a button on the panel")
        t.eq(listed(env, "TestClosable"), 1)
        t.eq(env.UISpecialFrames[1], "SomeoneElse", "the list is added to, not replaced")
        t.eq(type(h.onClose), "function")
        t.eq(frame.shown, false, "a new panel is hidden")
    end,

    ["panel close: a panel not asked to be closable has neither, and no onClose"] = function(t)
        local env = gameEnv()
        local h = ns.make.client(env).panel({ name = "TestPlain" })
        local _, button = parts(env)
        t.eq(button, nil)
        t.eq(listed(env, "TestPlain"), 0)
        t.eq(h.onClose, nil)
        t.eq(#env.frames, 1, "one frame, as before")
    end,

    ["panel close: the close button hides the panel and tells onClose once"] = function(t)
        local env = gameEnv()
        local h = closable(env)
        local frame, button = parts(env)
        if not button then t.ok(false, "no close button") return end
        local calls = 0
        h.onClose(function() calls = calls + 1 end)
        h.show(true)
        t.eq(frame.shown, true)
        button.scripts.OnClick(button)
        t.eq(frame.shown, false)
        t.eq(calls, 1)
        button.scripts.OnClick(button)
        t.eq(calls, 1, "a click on a closed panel is not a second close")
    end,

    ["panel close: Escape (the game hides the listed frame) tells onClose once"] = function(t)
        local env = gameEnv()
        local h = closable(env)
        local frame = parts(env)
        local calls = 0
        h.onClose(function() calls = calls + 1 end)
        h.show(true)
        frame:Hide()
        t.eq(calls, 1)
        h.show(true)
        frame:Hide()
        t.eq(calls, 2, "shown again, closed again")
    end,

    ["panel close: show(false) is not the player closing it"] = function(t)
        local env = gameEnv()
        local h = closable(env)
        local frame = parts(env)
        local calls = 0
        h.onClose(function() calls = calls + 1 end)
        h.show(true)
        h.show(false)
        t.eq(frame.shown, false)
        t.eq(calls, 0)
    end,

    ["panel close: the whole interface being hidden is not a close"] = function(t)
        local env = gameEnv()
        local h = closable(env)
        local frame = parts(env)
        local calls = 0
        h.onClose(function() calls = calls + 1 end)
        h.show(true)
        -- The game runs OnHide when a parent is hidden; the panel itself
        -- is still shown.
        frame.scripts.OnHide(frame)
        t.eq(calls, 0)
        frame:Hide()
        t.eq(calls, 1, "and it can still be closed afterwards")
    end,

    ["panel close: onClose given in the spec is told too, and h.onClose replaces it"] = function(t)
        local env = gameEnv()
        local first, second = 0, 0
        local h = closable(env, { onClose = function() first = first + 1 end })
        local frame = parts(env)
        h.show(true)
        frame:Hide()
        t.eq({ first, second }, { 1, 0 })
        h.onClose(function() second = second + 1 end)
        h.show(true)
        frame:Hide()
        t.eq({ first, second }, { 1, 1 })
    end,

    ["panel close: a failing onClose is handed to its caller, not to the game"] = function(t)
        local env = gameEnv()
        local h = closable(env)
        local frame, button = parts(env)
        if not button then t.ok(false, "no close button") return end
        local got
        h.onClose(function() error("boom") end, function(err) got = err end)
        h.show(true)
        t.eq(pcall(button.scripts.OnClick, button), true)
        t.eq(type(got) == "string" and got:find("boom", 1, true) ~= nil, true)
        h.onClose(function() error("boom") end)
        h.show(true)
        t.eq(pcall(frame.Hide, frame), true, "no sink is no error")
    end,

    ["panel close: no name: the button alone is the close route"] = function(t)
        local env = gameEnv()
        local h = ns.make.client(env).panel({ closable = true })
        local _, button = parts(env)
        t.ok(button ~= nil)
        t.eq(#env.UISpecialFrames, 1, "nothing without a name goes in the list")
        t.eq(type(h.onClose), "function")
    end,

    ["panel close: a name that is already a global is not put in the Escape list"] = function(t)
        local env = gameEnv()
        env.TestClosable = { someone = "else" }
        local h = closable(env)
        t.eq(listed(env, "TestClosable"), 0)
        t.eq(type(h.onClose), "function", "the button is still a route")
    end,

    ["panel close: no button but the Escape list: still closable"] = function(t)
        local env = gameEnv({ noButton = true })
        local h = closable(env)
        local frame = parts(env)
        t.eq(listed(env, "TestClosable"), 1)
        local calls = 0
        t.eq(type(h.onClose), "function")
        if type(h.onClose) ~= "function" then return end
        h.onClose(function() calls = calls + 1 end)
        h.show(true)
        frame:Hide()
        t.eq(calls, 1)
    end,

    ["panel close: no button and no list: the panel is made with no onClose"] = function(t)
        local env = gameEnv({ noButton = true, noList = true })
        local h = closable(env)
        t.ok(h ~= nil, "the panel itself is still made")
        t.eq(h.onClose, nil, "no close route, and the caller can tell")
    end,

    ["panel close: the fake: close() is the player closing it"] = function(t)
        local c = ns.make.fakeClient()
        local calls = 0
        local h = c.panel({ name = "X", closable = true, onClose = function() calls = calls + 1 end })
        t.eq(type(h.onClose), "function")
        h.show(true)
        h.close()
        t.eq({ h.shown, calls }, { false, 1 })
        h.close()
        t.eq(calls, 1, "closing a hidden panel is nothing")
        h.show(true)
        h.show(false)
        t.eq(calls, 1, "show(false) is not a close")
        local second = 0
        h.onClose(function() second = second + 1 end)
        h.show(true)
        h.close()
        t.eq({ calls, second }, { 1, 1 })
    end,

    ["panel close: the fake hands a failing onClose to its caller"] = function(t)
        local c = ns.make.fakeClient()
        local h = c.panel({ closable = true })
        local got
        h.onClose(function() error("boom") end, function(err) got = err end)
        h.show(true)
        t.eq(pcall(h.close), true)
        t.eq(type(got) == "string" and got:find("boom", 1, true) ~= nil, true)
    end,

    ["panel close: the fake: a plain panel, or a client with no close route, has no onClose"] = function(t)
        local c = ns.make.fakeClient()
        t.eq(c.panel({}).onClose, nil)
        t.eq(c.panel({}).close, nil)
        c.setCloseRoute(false)
        local h = c.panel({ closable = true })
        t.ok(h ~= nil)
        t.eq(h.onClose, nil)
    end,
}
