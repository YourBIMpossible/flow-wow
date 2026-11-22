-- client.windowButton(frameName, spec): a plain button on one of the
-- game's own windows (F9). nil when the window is missing, when the client
-- does not say plainly that it is not protected, and when it does not say
-- plainly that the player is out of combat. No game client is involved: a
-- hand-written stand-in for the globals of the client, and the fake.
local _, ns = ...

-- opts: noWindow, shown (what IsShown of the window answers; "error": it
-- fails; left out: the window has no such method), visible (what IsVisible
-- of a button answers; left out: no such method),
-- protected (what IsProtected answers; "error": it fails;
-- "none": the window has no such method), combat (what InCombatLockdown
-- answers; "none": the client has neither combat read), noTemplate (a
-- template makes CreateFrame fail), noFrames (CreateFrame always fails).
local function gameEnv(opts)
    opts = opts or {}
    local env = { frames = {}, tip = { calls = {} } }
    if not opts.noWindow then
        local w = { name = "TestWindow" }
        if opts.protected ~= "none" then
            function w:IsProtected()
                if opts.protected == "error" then error("no") end
                return opts.protected or false
            end
        end
        if opts.shown ~= nil then
            function w:IsShown()
                if opts.shown == "error" then error("no") end
                return opts.shown
            end
        end
        env.TestWindow = w
    end
    if opts.combat ~= "none" then
        function env.InCombatLockdown() return opts.combat or false end
    end
    function env.CreateFrame(kind, name, parent, template)
        if opts.noFrames then error("no frames") end
        if template ~= nil and opts.noTemplate then error("no template") end
        local f = { kind = kind, name = name, parent = parent, template = template,
            scripts = {}, shown = true, attributes = 0 }
        function f:SetScript(script, fn) self.scripts[script] = fn end
        function f:SetText(text) self.text = text end
        function f:SetSize(w, h) self.width, self.height = w, h end
        function f:SetPoint(...) self.point = { ... } end
        function f:RegisterForClicks(...) self.clicks = { ... } end
        function f:SetAttribute() self.attributes = self.attributes + 1 end
        function f:Show() self.shown = true end
        function f:Hide() self.shown = false end
        if opts.visible ~= nil then
            function f:IsVisible() return opts.visible end
        end
        env.frames[#env.frames + 1] = f
        return f
    end
    local tip = env.tip
    function tip:SetOwner(owner) self.owner = owner return true end
    function tip:SetText(text) self.text = text end
    function tip:Show() self.shown = true end
    function tip:Hide() self.shown = false end
    function tip:IsOwned(who) return self.owner == who end
    env.GameTooltip = tip
    return env
end

local SPEC = { name = "TestWindowButton", text = "Menu", tip = "Shows the menu.",
    point = { "TOPRIGHT", "TOPRIGHT", -40, -4 } }

local function make(opts, spec)
    local env = gameEnv(opts)
    return ns.make.client(env).windowButton("TestWindow", spec or SPEC), env
end

return {
    ["window button: made on the window, hidden, with its text and place"] = function(t)
        local h, env = make()
        t.ok(h ~= nil, "a handle")
        t.eq(#env.frames, 1, "one frame")
        local b = env.frames[1]
        t.eq(b.kind, "Button")
        t.eq(b.parent, env.TestWindow, "a child of the window")
        t.eq(b.name, "TestWindowButton")
        t.eq(b.text, "Menu")
        t.eq(b.shown, false, "a new button is hidden")
        t.eq(b.point[1], "TOPRIGHT")
        t.eq(b.point[2], env.TestWindow)
        t.eq(b.point[4], -40)
        t.eq(b.point[5], -4)
        t.eq(b.clicks, { "LeftButtonUp" })
    end,

    ["window button: it is a plain button: no secure template, no attribute"] = function(t)
        local _, env = make()
        local b = env.frames[1]
        t.eq(b.template, "UIPanelButtonTemplate")
        t.ok(not tostring(b.template):find("Secure", 1, true), "not a secure template")
        t.eq(b.attributes, 0, "no attribute is set")
    end,

    ["window button: no window, no button"] = function(t)
        local h, env = make({ noWindow = true })
        t.eq(h, nil)
        t.eq(#env.frames, 0, "nothing is made")
    end,

    -- Section 134: the rule of section 132 is taken back. A protected
    -- window, or one that will not say, gets no button, and the reason
    -- is said.
    ["window button: a protected window gets none, and it says why"] = function(t)
        local env = gameEnv({ protected = true })
        local h, why = ns.make.client(env).windowButton("TestWindow", SPEC)
        t.eq(h, nil)
        t.eq(#env.frames, 0, "nothing is made")
        t.eq(why, "its window is protected")
    end,

    ["window button: a window that will not say whether it is protected gets none, and it says why"] = function(t)
        for _, how in ipairs({ "error", "none", "yes", 1 }) do
            local env = gameEnv({ protected = how })
            local h, why = ns.make.client(env).windowButton("TestWindow", SPEC)
            t.eq(h, nil, tostring(how))
            t.eq(#env.frames, 0, tostring(how))
            t.eq(why, "its window will not say whether it is protected", tostring(how))
        end
    end,

    ["window button: combat is said before protection"] = function(t)
        local env = gameEnv({ protected = true, combat = true })
        local h, why = ns.make.client(env).windowButton("TestWindow", SPEC)
        t.eq(h, nil)
        t.eq(why, "in combat")
    end,

    ["window state: what the client says of the window, read only"] = function(t)
        local function state(opts)
            local env = gameEnv(opts)
            return ns.make.client(env).windowState("TestWindow"), env
        end
        t.eq(state({ noWindow = true }), nil, "no window")
        t.eq(state({ shown = true }), { shown = true, protected = false })
        t.eq(state({ shown = false, protected = true }), { shown = false, protected = true })
        t.eq(state({}), { protected = false }, "no IsShown: not said")
        t.eq(state({ shown = "error", protected = "error" }), {}, "failed reads: not said")
        t.eq(state({ shown = "yes", protected = "none" }), {}, "not a plain answer: not said")
        local _, env = state({ shown = true })
        t.eq(#env.frames, 0, "nothing is made")
        t.eq(ns.make.client(gameEnv()).windowState(nil), nil, "a bad ask")
    end,

    ["window button: the handle says whether the button can be seen"] = function(t)
        t.eq(make({ visible = true }).visible(), true)
        t.eq(make({ visible = false }).visible(), false)
        t.eq(make().visible(), nil, "no such read: not said")
        t.eq(make({ visible = "yes" }).visible(), nil, "not a plain answer")
    end,

    ["window button: a protected window still gets none in combat"] = function(t)
        local h, env = make({ protected = true, combat = true })
        t.eq(h, nil)
        t.eq(#env.frames, 0)
    end,

    ["window button: it says why none was made"] = function(t)
        local function why(opts, name, spec)
            local env = gameEnv(opts)
            local h, reason = ns.make.client(env).windowButton(name or "TestWindow", spec or SPEC)
            t.eq(h, nil)
            return reason
        end
        t.eq(why({ noWindow = true }), "no window")
        t.eq(why({ combat = true }), "in combat")
        t.eq(why({ combat = "none" }), "in combat")
        t.eq(why({ noFrames = true }), "no frame")
        t.eq(why({}, ""), "bad ask")
        t.eq(why({}, "TestWindow", "text"), "bad ask")
    end,

    ["window button: none in combat, and none when the client will not say"] = function(t)
        local h, env = make({ combat = true })
        t.eq(h, nil)
        t.eq(#env.frames, 0)
        local h2, env2 = make({ combat = "none" })
        t.eq(h2, nil, "not knowing is not out of combat")
        t.eq(#env2.frames, 0)
    end,

    ["window button: a bad ask gets none"] = function(t)
        local env = gameEnv()
        local c = ns.make.client(env)
        t.eq(c.windowButton(nil, SPEC), nil)
        t.eq(c.windowButton("", SPEC), nil)
        t.eq(c.windowButton("TestWindow", nil), nil)
        t.eq(c.windowButton("TestWindow", "text"), nil)
        t.eq(#env.frames, 0)
    end,

    ["window button: a client without the template still gets a plain button"] = function(t)
        local h, env = make({ noTemplate = true })
        t.ok(h ~= nil, "a handle")
        t.eq(#env.frames, 1)
        t.eq(env.frames[1].template, nil)
    end,

    ["window button: a client that cannot make frames gets none"] = function(t)
        local h = make({ noFrames = true })
        t.eq(h, nil)
    end,

    ["window button: a name already taken is not used"] = function(t)
        local env = gameEnv()
        env.TestWindowButton = { someone = "else" }
        local h = ns.make.client(env).windowButton("TestWindow", SPEC)
        t.ok(h ~= nil, "a handle")
        t.eq(env.frames[1].name, nil, "made without a name")
        t.eq(env.TestWindowButton.someone, "else", "the other one is left alone")
    end,

    ["window button: show and hide"] = function(t)
        local h, env = make()
        h.show(true)
        t.eq(env.frames[1].shown, true)
        h.show(false)
        t.eq(env.frames[1].shown, false)
    end,

    ["window button: a click tells the caller, and only the caller"] = function(t)
        local h, env = make()
        local b = env.frames[1]
        t.eq((pcall(b.scripts.OnClick, b, "LeftButton")), true, "a click with no one listening does nothing")
        local calls, got = 0, 0
        h.onClick(function(...) calls = calls + 1 got = select("#", ...) end)
        b.scripts.OnClick(b, "LeftButton")
        t.eq(calls, 1)
        t.eq(got, 0, "nothing of the client reaches the caller")
        h.onClick(nil)
        b.scripts.OnClick(b, "LeftButton")
        t.eq(calls, 1, "taken away")
    end,

    ["window button: a caller that fails does not break the click"] = function(t)
        local h, env = make()
        local b = env.frames[1]
        local told
        h.onClick(function() error("broke") end, function(err) told = err end)
        local ok = pcall(b.scripts.OnClick, b, "LeftButton")
        t.eq(ok, true, "the error stays inside")
        t.ok(tostring(told):find("broke", 1, true) ~= nil, "failed is told the error")
        h.onClick(function() error("again") end)
        t.eq((pcall(b.scripts.OnClick, b, "LeftButton")), true, "and with no failed")
    end,

    ["window button: the tip is shown on enter and hidden on leave"] = function(t)
        local _, env = make()
        local b = env.frames[1]
        b.scripts.OnEnter(b)
        t.eq(env.tip.text, "Shows the menu.")
        t.eq(env.tip.shown, true)
        b.scripts.OnLeave(b)
        t.eq(env.tip.shown, false)
    end,

    ["window button: a tooltip someone else owns is not hidden"] = function(t)
        local _, env = make()
        local b = env.frames[1]
        b.scripts.OnEnter(b)
        env.tip.owner = { someone = "else" }
        b.scripts.OnLeave(b)
        t.eq(env.tip.shown, true)
    end,

    ["window button: no tip, no tip scripts"] = function(t)
        local _, env = make(nil, { text = "Menu" })
        t.eq(env.frames[1].scripts.OnEnter, nil)
        t.eq(env.frames[1].scripts.OnLeave, nil)
        t.ok(env.frames[1].scripts.OnClick ~= nil, "the click is still there")
    end,

    ["window button: the fake answers the same way"] = function(t)
        local c = ns.make.fakeClient()
        t.eq(c.windowButton("TestWindow", SPEC), nil, "no window until a test says so")
        c.setWindow("TestWindow", {})
        local h = c.windowButton("TestWindow", SPEC)
        t.ok(h ~= nil, "a handle")
        t.eq(h.shown, false, "a new button is hidden")
        t.eq(h.frame, "TestWindow")
        t.eq(c.windowButtons[1], h)
        local calls = 0
        h.onClick(function() calls = calls + 1 end)
        h.click()
        t.eq(calls, 0, "a hidden button cannot be clicked")
        h.show(true)
        h.click()
        t.eq(calls, 1)
        local told
        h.onClick(function() error("broke") end, function(err) told = err end)
        h.click()
        t.ok(told ~= nil, "failed is told")
        -- Section 134: a protected window gets none, as in the client.
        c.setWindow("Guarded", { protected = true })
        local g, gWhy = c.windowButton("Guarded", SPEC)
        t.eq(g, nil, "protected")
        t.eq(gWhy, "its window is protected")
        c.setWindow("Mute", { protected = "unsaid" })
        t.eq(select(2, c.windowButton("Mute", SPEC)), "its window will not say whether it is protected")
        t.eq(c.windowState("Guarded"), { protected = true })
        t.eq(c.windowState("Mute"), {})
        t.eq(c.windowState("Gone"), nil)
        t.eq(h.visible(), nil, "the window does not say whether it is open")
        c.setWindow("TestWindow", { shown = true })
        t.eq(c.windowState("TestWindow"), { shown = true, protected = false })
        t.eq(h.visible(), true)
        c.setWindow("TestWindow", { shown = false })
        t.eq(h.visible(), false)
        c.setCombat(true)
        t.eq(c.windowButton("TestWindow", SPEC), nil, "in combat")
        t.eq(select(2, c.windowButton("TestWindow", SPEC)), "in combat")
        t.eq(select(2, c.windowButton("Gone", SPEC)), "no window")
        c.setCombat(false)
        c.setWindow("TestWindow", false)
        t.eq(c.windowButton("TestWindow", SPEC), nil, "taken away")
        c.setWindow("TestWindow", {})
        c.setFrames(false)
        t.eq(c.windowButton("TestWindow", SPEC), nil, "a client with no frames")
        t.eq(select(2, c.windowButton("TestWindow", SPEC)), "no frame")
        t.eq(#c.windowButtons, 1)
    end,
}
