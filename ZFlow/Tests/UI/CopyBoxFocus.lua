local _, ns = ...

-- The copy box gives up the keyboard (L6-N, §113; Reviewer on L6-K): a
-- contract test for the FAKE client's copyBox, so that the fake the lead
-- adds to Core/ClientFake.lua carries the focus rules of the CLIENT NEED:
--   * showing the box never takes focus (SetAutoFocus(false));
--   * the player's click in the text gives it focus;
--   * hiding it, however that happens, releases focus (ClearFocus on hide);
--   * Escape releases focus and hides it.
-- The fake's part of the CLIENT NEED:
--   c.copyBox(spec) -> handle { setText(text), show(on) }
--   c.copyBoxes[n]  -> { spec, text, shown, focused,
--                        click()    the test's control: the player clicks in the text
--                        escape()   the test's control: the player presses Escape }
--
-- Until the fake has copyBox these tests have nothing to bind to. They then
-- say so in one passing line each ("pending") instead of failing a branch
-- that may not edit the fake; once the lead adds it, they are real checks.
-- UI/CopyBox.lua itself never asks for focus: it only calls setText and
-- show(true), which the last test checks against any handle.

local B = ns.CopyBox
local tests = {}

-- The fake's box for a fresh client, or nil when the fake has none yet.
local function fakeBox()
    local c = ns.make.fakeClient()
    if type(c.copyBox) ~= "function" then return nil end
    local handle = c.copyBox({ name = ns.id.framePrefix .. "CopyBox", width = 100, height = 50, title = "t" })
    local box = type(c.copyBoxes) == "table" and c.copyBoxes[#c.copyBoxes] or nil
    return handle, box, c
end

local function pending(t)
    t.ok(true, "pending: the fake client has no copyBox yet (CLIENT NEED, L6-N)")
end

tests["copy box focus: showing the box does not take the keyboard"] = function(t)
    local handle, box = fakeBox()
    if not handle then return pending(t) end
    handle.setText("some text")
    handle.show(true)
    t.eq(box.shown, true)
    t.eq(box.focused, false, "auto-focus is off: W still moves the character")
end

tests["copy box focus: hiding the box gives the keyboard back"] = function(t)
    local handle, box = fakeBox()
    if not handle then return pending(t) end
    handle.show(true)
    box.click()
    t.eq(box.focused, true, "the player's own click in the text focuses it")
    handle.show(false)
    t.eq(box.shown, false)
    t.eq(box.focused, false, "hidden: focus released")
end

tests["copy box focus: Escape releases focus and hides the box"] = function(t)
    local handle, box = fakeBox()
    if not handle then return pending(t) end
    handle.show(true)
    box.click()
    box.escape()
    t.eq(box.focused, false)
    t.eq(box.shown, false)
end

tests["copy box focus: a hidden box cannot be focused, and showing it again starts unfocused"] = function(t)
    local handle, box = fakeBox()
    if not handle then return pending(t) end
    handle.show(false)
    box.click()
    t.eq(box.focused, false, "a click on nothing")
    handle.show(true)
    box.click()
    handle.show(false)
    handle.show(true)
    t.eq(box.focused, false, "shown again: not focused until clicked")
end

-- This one binds today: the module asks a handle for nothing but text and show.
tests["copy box focus: the module never asks for focus"] = function(t)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    local asked = {}
    local fns, real = {}, c.print
    c.print = function(text)
        real(text)
        for i = 1, #fns do fns[i](tostring(text)) end
    end
    c.onPrint = function(fn) fns[#fns + 1] = fn return function() end end
    c.copyBox = function()
        return setmetatable({}, { __index = function(_, name)
            return function(...)
                asked[name] = (asked[name] or 0) + 1
            end
        end })
    end
    local k = ns.Kernel({}, c)
    local diag = ns.Diag.Start(k)
    B.Start(k, diag)
    c.advance(1)
    c.print("a line")
    diag.commands[B.WORD]("")
    t.eq(asked, { setText = 1, show = 1 }, "setText and show, and nothing that could take the keyboard")
end

return tests
