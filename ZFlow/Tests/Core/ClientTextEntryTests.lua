-- c.textEntry (row N73): a small plain frame with one edit box, for a line
-- the player types (UI/Feedback.lua). The real client over a hand-built
-- environment; every frame is a recording stub. Not tested in game.
-- Fails before: Core/Client.lua has no textEntry.
local _, ns = ...

-- opts: noAutoFocus (the edit box will not turn auto-focus off), noEdit (no
-- edit box can be made).
local function gameEnv(opts)
    opts = opts or {}
    local env = { made = {}, UIParent = {} }
    local function frame(kind, template, parent)
        local f = { kind = kind, template = template, parent = parent, scripts = {}, shown = true, focus = false }
        function f:SetScript(name, fn) self.scripts[name] = fn end
        function f:SetPoint() end
        function f:SetAllPoints() end
        function f:SetSize(w, h) self.w, self.h = w, h end
        function f:SetFrameStrata(strata) self.strata = strata end
        function f:EnableMouse() end
        function f:SetColorTexture() end
        function f:Show() self.shown = true end
        function f:Hide()
            local was = self.shown
            self.shown = false
            if was and self.scripts.OnHide then self.scripts.OnHide(self) end
        end
        function f:IsVisible() return self.shown end
        function f:SetText(s) self.text = s end
        function f:GetText() return self.text end
        function f:ClearFocus() self.focus = false end
        function f:CreateTexture() return frame("Texture") end
        function f:CreateFontString() return frame("FontString") end
        if kind == "EditBox" and not opts.noAutoFocus then
            function f:SetAutoFocus(on) self.autoFocus = on end
        end
        env.made[#env.made + 1] = f
        return f
    end
    function env.CreateFrame(kind, name, parent, template)
        if kind == "EditBox" and opts.noEdit then return nil end
        local f = frame(kind, template, parent)
        f.name = name
        return f
    end
    return env
end

-- The first thing of that kind made for the entry (after env.from: what
-- the client made for itself before is not the entry's).
local function one(env, kind)
    for i = (env.from or 0) + 1, #env.made do
        if env.made[i].kind == kind then return env.made[i] end
    end
    return nil
end

local function make(opts, spec)
    local env = gameEnv(opts)
    local c = ns.make.client(env)
    if type(c.textEntry) ~= "function" then return env, nil, false end
    env.from = #env.made
    return env, c.textEntry(spec or { name = "MadeUpEntry", width = 400 }), true
end

return {
    ["textEntry: a plain frame and one edit box, hidden when made, that never takes the keyboard by itself"] = function(t)
        local env, h, there = make()
        t.ok(there, "the client has textEntry")
        if not there then return end
        t.eq(type(h), "table")
        local f, edit = one(env, "Frame"), one(env, "EditBox")
        t.ok(f ~= nil and edit ~= nil, "a frame and an edit box")
        t.eq(f.shown, false, "hidden until asked")
        t.eq(f.name, "MadeUpEntry")
        t.eq(f.parent, env.UIParent)
        t.eq(edit.template, "InputBoxTemplate")
        t.eq(edit.autoFocus, false, "auto-focus is off")
        t.eq(h.shown(), false)
        for i = env.from + 1, #env.made do
            local made = env.made[i]
            t.ok(made.template == nil or made.template == "InputBoxTemplate", "no secure template: " .. tostring(made.template))
        end
    end,

    ["textEntry: ask shows the words and the text; Enter hides it and tells what was typed, once"] = function(t)
        local env, h, there = make()
        t.ok(there, "the client has textEntry")
        if not there then return end
        local f, edit, words = one(env, "Frame"), one(env, "EditBox"), one(env, "FontString")
        local got = {}
        h.ask("Describe it", "as it was", function(text) got[#got + 1] = text end)
        t.eq(f.shown, true)
        t.eq(h.shown(), true)
        t.eq(words.text, "Describe it")
        t.eq(edit.text, "as it was", "what was written before is there to change")
        edit.text = "The arrow spins"
        edit.scripts.OnEnterPressed(edit)
        t.eq(got, { "The arrow spins" })
        t.eq(f.shown, false, "hidden after Enter")
        edit.scripts.OnEnterPressed(edit)
        t.eq(#got, 1, "told once")
    end,

    ["textEntry: Escape and show(false) hide it and tell nothing; an fn that raises stays inside"] = function(t)
        local env, h, there = make()
        t.ok(there, "the client has textEntry")
        if not there then return end
        local f, edit = one(env, "Frame"), one(env, "EditBox")
        local got = 0
        h.ask("w", "", function() got = got + 1 end)
        edit.text = "typed"
        edit.scripts.OnEscapePressed(edit)
        t.eq(f.shown, false)
        edit.scripts.OnEnterPressed(edit)
        t.eq(got, 0, "Escape told nothing, and Enter after it tells nothing")
        h.ask("w", "", function() got = got + 1 end)
        h.show(false)
        t.eq(f.shown, false)
        edit.scripts.OnEnterPressed(edit)
        t.eq(got, 0)
        h.ask("w", "", function() error("the caller broke") end)
        local ok = pcall(edit.scripts.OnEnterPressed, edit)
        t.eq(ok, true, "nothing is raised into the frame's script")
        h.ask(nil, nil, nil)
        t.eq(edit.text, "", "no text given is an empty box")
        t.eq(pcall(edit.scripts.OnEnterPressed, edit), true)
    end,

    ["textEntry: a client that will not turn auto-focus off, or makes no edit box, gets none"] = function(t)
        local _, h, there = make({ noAutoFocus = true })
        t.ok(there, "the client has textEntry")
        if not there then return end
        t.eq(h, nil, "no box that would take the keyboard by itself")
        local _, none = make({ noEdit = true })
        t.eq(none, nil)
    end,

    ["textEntry: a name that is already a global is not taken over"] = function(t)
        local env = gameEnv()
        env.MadeUpEntry = {}
        local c = ns.make.client(env)
        t.ok(type(c.textEntry) == "function", "the client has textEntry")
        if type(c.textEntry) ~= "function" then return end
        env.from = #env.made
        t.eq(type(c.textEntry({ name = "MadeUpEntry" })), "table")
        t.eq(one(env, "Frame").name, nil)
    end,
}
