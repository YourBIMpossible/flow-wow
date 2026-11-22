-- client.onPrint and client.copyBox (F10; L6-K, with the focus rules of
-- L6-N), on the real client over a hand-built env, and on the fake. The
-- frames here record what was asked of them. Not tested in game.
local _, ns = ...

-- A frame that records every method called on it, as { name, args... }.
-- `without` names methods this frame does not have.
local function frame(kind, name, template, calls, without)
    local f = { kind = kind, name = name, template = template, scripts = {}, shown = true, text = "" }
    local own = {}
    function own.SetScript(_, what, fn) f.scripts[what] = fn end
    function own.Show() f.shown = true end
    function own.Hide()
        local was = f.shown
        f.shown = false
        if was and f.scripts.OnHide then f.scripts.OnHide() end
    end
    function own.IsShown() return f.shown end
    function own.SetText(_, text)
        f.text = text
        if f.scripts.OnTextChanged then f.scripts.OnTextChanged() end
    end
    function own.GetText() return f.text end
    function own.CreateTexture() return frame("Texture", nil, nil, calls, without) end
    function own.CreateFontString() return frame("FontString", nil, nil, calls, without) end
    return setmetatable(f, { __index = function(_, method)
        if without and without[method] then return nil end
        return function(self, ...)
            calls[#calls + 1] = { kind = kind, method = method, ... }
            if own[method] then return own[method](self, ...) end
        end
    end })
end

-- env: a client's globals with CreateFrame. Every global name read is in
-- env.read. opts.without: methods no frame has. opts.kinds: the frame
-- kinds CreateFrame makes (all when nil).
local function world(opts)
    opts = opts or {}
    local calls, made, read = {}, {}, {}
    local globals = { UIParent = {}, printed = {} }
    globals.print = function(text) globals.printed[#globals.printed + 1] = text end
    globals.CreateFrame = function(kind, name, _, template)
        if opts.kinds and not opts.kinds[kind] then error("no such frame kind") end
        local f = frame(kind, name, template, calls, opts.without)
        made[#made + 1] = f
        return f
    end
    local env = setmetatable({}, { __index = function(_, key)
        read[key] = true
        return globals[key]
    end })
    local function one(kind)
        for i = 1, #made do
            if made[i].kind == kind then return made[i] end
        end
        return nil
    end
    -- How many times `method` was called on frames of `kind`, and the
    -- first argument of the last call.
    local function called(kind, method)
        local n, arg = 0, nil
        for i = 1, #calls do
            if calls[i].kind == kind and calls[i].method == method then n, arg = n + 1, calls[i][1] end
        end
        return n, arg
    end
    return env, { calls = calls, made = made, read = read, globals = globals, one = one, called = called }
end

local SPEC = { name = "ZCopyBox", width = 400, height = 200, title = "select, then copy" }

return {
    -- ------------------------------------------------------------ onPrint

    ["client onPrint: every line said reaches the listener, as text"] = function(t)
        local env, w = world()
        local c = ns.make.client(env)
        local got = {}
        c.onPrint(function(text) got[#got + 1] = text end)
        c.print("one")
        c.print(2)
        t.eq(got, { "one", "2" })
        t.eq(w.globals.printed, { "one", "2" }, "and is still said")
    end,

    ["client onPrint: cancel stops it, and only it"] = function(t)
        local c = ns.make.client((world()))
        local a, b = {}, {}
        local cancel = c.onPrint(function(text) a[#a + 1] = text end)
        c.onPrint(function(text) b[#b + 1] = text end)
        c.print("one")
        cancel()
        c.print("two")
        t.eq(a, { "one" })
        t.eq(b, { "one", "two" })
    end,

    ["client onPrint: a listener that raises does not stop the line being said"] = function(t)
        local env, w = world()
        local c = ns.make.client(env)
        c.onPrint(function() error("boom") end)
        t.eq(pcall(c.print, "one"), true)
        t.eq(pcall(c.print, "two"), true)
        t.eq(w.globals.printed, { "one", "two" })
    end,

    ["client onPrint: a client with no print still feeds the listener"] = function(t)
        local c = ns.make.client({})
        local got = {}
        c.onPrint(function(text) got[#got + 1] = text end)
        t.eq(pcall(c.print, "one"), true)
        t.eq(got, { "one" })
    end,

    ["client onPrint: what is not a function is not kept, and a cancel is still given"] = function(t)
        local c = ns.make.client((world()))
        local cancel = c.onPrint("not a function")
        t.eq(type(cancel), "function")
        t.eq(pcall(cancel), true)
        t.eq(pcall(c.print, "one"), true)
    end,

    ["fake onPrint: the fake feeds listeners the same way"] = function(t)
        local c = ns.make.fakeClient()
        local got = {}
        local cancel = c.onPrint(function(text) got[#got + 1] = text end)
        c.onPrint(function() error("boom") end)
        c.print("one")
        c.print(2)
        cancel()
        c.print("three")
        t.eq(got, { "one", "2" })
        t.eq(c.printed, { "one", "2", "three" })
    end,

    -- ------------------------------------------------------------ copyBox

    ["client copyBox: a new box is hidden, with the focus rules set"] = function(t)
        local env, w = world()
        local c = ns.make.client(env)
        local h = c.copyBox(SPEC)
        t.ok(type(h) == "table", "a handle")
        if type(h) ~= "table" then return end
        t.eq(type(h.setText), "function")
        t.eq(type(h.show), "function")
        t.eq(w.one("Frame").shown, false, "hidden until shown")
        t.eq(w.one("Frame").name, "ZCopyBox")
        local n, arg = w.called("EditBox", "SetAutoFocus")
        t.eq(n, 1)
        t.eq(arg, false, "SetAutoFocus(false)")
        n, arg = w.called("EditBox", "SetMaxLetters")
        t.eq(n, 1)
        t.eq(arg, 0, "SetMaxLetters(0): no limit")
        n, arg = w.called("EditBox", "SetMultiLine")
        t.eq(n, 1)
        t.eq(arg, true)
        t.eq((w.called("EditBox", "SetFocus")), 0, "focus is never asked for")
    end,

    ["client copyBox: showing it and setting its text never ask for focus"] = function(t)
        local env, w = world()
        local h = ns.make.client(env).copyBox(SPEC)
        h.setText("line one\nline two")
        h.show(true)
        t.eq(w.one("Frame").shown, true)
        t.eq(w.one("EditBox").text, "line one\nline two")
        t.eq((w.called("EditBox", "SetFocus")), 0)
        t.eq((w.called("EditBox", "HighlightText")), 0)
    end,

    ["client copyBox: hiding it releases focus"] = function(t)
        local env, w = world()
        local h = ns.make.client(env).copyBox(SPEC)
        h.show(true)
        local before = (w.called("EditBox", "ClearFocus"))
        h.show(false)
        t.eq(w.one("Frame").shown, false)
        t.ok((w.called("EditBox", "ClearFocus")) > before, "ClearFocus on hide")
    end,

    ["client copyBox: hidden by the client itself, it still releases focus"] = function(t)
        local env, w = world()
        local h = ns.make.client(env).copyBox(SPEC)
        h.show(true)
        local before = (w.called("EditBox", "ClearFocus"))
        t.ok(type(w.one("Frame").scripts.OnHide) == "function", "an OnHide handler")
        w.one("Frame"):Hide()
        t.ok((w.called("EditBox", "ClearFocus")) > before, "ClearFocus from OnHide")
    end,

    ["client copyBox: Escape releases focus and hides it"] = function(t)
        local env, w = world()
        local h = ns.make.client(env).copyBox(SPEC)
        h.show(true)
        local escape = w.one("EditBox").scripts.OnEscapePressed
        t.ok(type(escape) == "function", "an OnEscapePressed handler")
        if type(escape) ~= "function" then return end
        local before = (w.called("EditBox", "ClearFocus"))
        escape()
        t.ok((w.called("EditBox", "ClearFocus")) > before, "ClearFocus on Escape")
        t.eq(w.one("Frame").shown, false)
    end,

    ["client copyBox: it is its own edit box; no chat frame or chat edit box is read"] = function(t)
        local env, w = world()
        local h = ns.make.client(env).copyBox(SPEC)
        h.setText("text")
        h.show(true)
        h.show(false)
        for key in pairs(w.read) do
            t.ok(not tostring(key):find("Chat", 1, true), "a chat global was read: " .. tostring(key))
        end
        local edits = 0
        for i = 1, #w.made do
            if w.made[i].kind == "EditBox" then edits = edits + 1 end
        end
        t.eq(edits, 1, "one edit box, made for the box")
        t.eq((w.called("EditBox", "HookScript")), 0)
    end,

    ["client copyBox: typing changes nothing; the text is put back"] = function(t)
        local env, w = world()
        local h = ns.make.client(env).copyBox(SPEC)
        h.setText("kept")
        local edit = w.one("EditBox")
        edit:SetText("kept and typed")     -- as the player typing would
        t.eq(edit.text, "kept")
        h.setText("next")
        t.eq(edit.text, "next")
    end,

    ["client copyBox: nil when the client makes no frame"] = function(t)
        t.eq(ns.make.client({}).copyBox(SPEC), nil)
        t.eq(ns.make.client((world({ kinds = {} }))).copyBox(SPEC), nil)
    end,

    ["client copyBox: nil when the client makes no edit box"] = function(t)
        local env = world({ kinds = { Frame = true, ScrollFrame = true, Button = true } })
        t.eq(ns.make.client(env).copyBox(SPEC), nil)
    end,

    ["client copyBox: no box when auto-focus cannot be turned off"] = function(t)
        local env, w = world({ without = { SetAutoFocus = true } })
        t.eq(ns.make.client(env).copyBox(SPEC), nil)
        t.eq(w.one("Frame").shown, false, "and what was made stays hidden")
    end,

    ["client copyBox: a client with no scroll frame or close button still gives a box"] = function(t)
        local env, w = world({ kinds = { Frame = true, EditBox = true } })
        local h = ns.make.client(env).copyBox(SPEC)
        t.ok(type(h) == "table")
        if type(h) ~= "table" then return end
        h.setText("text")
        h.show(true)
        t.eq(w.one("Frame").shown, true)
        t.eq(w.one("EditBox").text, "text")
    end,

    ["client copyBox: a spec that is not a table, and a box with no name"] = function(t)
        local env, w = world()
        local c = ns.make.client(env)
        t.ok(type(c.copyBox(nil)) == "table")
        t.eq(rawget(w.one("Frame"), "name"), nil)
        for i = 1, #w.made do
            t.ok(rawget(w.made[i], "template") ~= "UIPanelScrollFrameTemplate", "the template needs a name")
        end
    end,

    -- ------------------------------------------------------------ the fake

    ["fake copyBox: every box is listed, hidden and unfocused when new"] = function(t)
        local c = ns.make.fakeClient()
        local h = c.copyBox(SPEC)
        t.eq(#c.copyBoxes, 1)
        local box = c.copyBoxes[1]
        t.eq(box.spec, SPEC)
        t.eq(box.shown, false)
        t.eq(box.focused, false)
        h.setText("text")
        t.eq(box.text, "text")
    end,

    ["fake copyBox: the box gives up focus on hide"] = function(t)
        local c = ns.make.fakeClient()
        local h = c.copyBox(SPEC)
        local box = c.copyBoxes[1]
        h.show(true)
        t.eq(box.focused, false, "shown: not focused")
        box.click()
        t.eq(box.focused, true)
        h.show(false)
        t.eq(box.shown, false)
        t.eq(box.focused, false, "hidden: focus given up")
        box.click()
        t.eq(box.focused, false, "a hidden box takes no click")
    end,

    ["fake copyBox: Escape gives up focus and hides it"] = function(t)
        local c = ns.make.fakeClient()
        local h = c.copyBox(SPEC)
        local box = c.copyBoxes[1]
        h.show(true)
        box.click()
        box.escape()
        t.eq(box.focused, false)
        t.eq(box.shown, false)
    end,
}
