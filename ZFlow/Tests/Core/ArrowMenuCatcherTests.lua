-- The arrows' menu catcher (Core/Client.lua, AI1) and the tooltip's owner
-- check (AI2), over a stub environment that records every call. No game
-- client is involved: this checks which calls land on which object, not
-- what the game draws.
--
-- The catcher is a full-screen button. The game makes a frame shown, so a
-- catcher that is made and then left alone takes every click on the screen.
local _, ns = ...

-- A stub object: every method exists, records (name, args) and returns the
-- object's own answer for that name, if it has one.
local function stub(kind)
    local o = { kind = kind, calls = {} }
    return setmetatable(o, { __index = function(_, name)
        return function(self, ...)
            self.calls[#self.calls + 1] = { name = name, ... }
            if name == "CreateTexture" or name == "CreateFontString" then return stub(name) end
            local answer = rawget(self, "answers") and self.answers[name]
            if answer then return answer(...) end
            return nil
        end
    end })
end

-- e.panel decides what making the menu's panel (a Frame) does: "raise"
-- raises, "none" gives nothing back, anything else makes it.
local function env()
    local made = {}
    local e = { UIParent = stub("UIParent") }
    e.CreateFrame = function(kind, name, parent)
        if kind == "Frame" and e.panel == "raise" then error("no frame") end
        if kind == "Frame" and e.panel == "none" then return nil end
        local f = stub(kind)
        f.name, f.parent = name, parent
        made[#made + 1] = f
        return f
    end
    return e, made
end

local SPEC = { name = "TestArrow", size = 56, art = 64, artPath = "x\\" }
local ITEMS = { { text = "Reset", key = "reset" } }

-- Whether a frame is on screen after the calls it has had: made shown, as
-- the game makes one, then as its last Show or Hide left it.
local function shown(o)
    local on = true
    for _, cl in ipairs(o.calls) do
        if cl.name == "Show" then on = true elseif cl.name == "Hide" then on = false end
    end
    return on
end

-- The first Show or Hide a frame was given.
local function firstSeen(o)
    for _, cl in ipairs(o.calls) do
        if cl.name == "Show" or cl.name == "Hide" then return cl.name end
    end
    return nil
end

local function script(o, name)
    local out
    for _, cl in ipairs(o.calls) do
        if cl.name == "SetScript" and cl[1] == name then out = cl[2] end
    end
    return out
end

local function count(o, name)
    local n = 0
    for _, cl in ipairs(o.calls) do
        if cl.name == name then n = n + 1 end
    end
    return n
end

-- How many catchers there are: buttons made on UIParent itself.
local function catchers(e, made)
    local n = 0
    for _, f in ipairs(made) do
        if f.kind == "Button" and f.parent == e.UIParent then n = n + 1 end
    end
    return n
end

-- An arrow whose first menu is opened with the panel failing as `how`.
-- Returns the handle, the catcher (nil when none was made), env, made and
-- whether the call came back without raising.
local function failedOpen(how)
    local e, made = env()
    local c = ns.make.client(e)
    local h = c.arrow(SPEC)
    local before = #made
    e.panel = how
    local ok = pcall(h.menu, ITEMS, function() end)
    return h, made[before + 1], e, made, ok
end

return {
    ["catcher: the panel's CreateFrame raising on the first open leaves the catcher hidden"] = function(t)
        local _, catcher, _, _, ok = failedOpen("raise")
        t.ok(ok, "the failure is not thrown at the caller")
        if not catcher then
            t.ok(false, "a catcher was made before the panel")
            return
        end
        t.eq(catcher.kind, "Button")
        t.eq(shown(catcher), false, "a made catcher with no menu is not on screen")
    end,

    ["catcher: the panel's CreateFrame giving nothing on the first open leaves the catcher hidden"] = function(t)
        local _, catcher = failedOpen("none")
        if not catcher then
            t.ok(false, "a catcher was made before the panel")
            return
        end
        t.eq(shown(catcher), false)
    end,

    ["catcher: it is hidden when made, before anything shows it"] = function(t)
        local e, made = env()
        local c = ns.make.client(e)
        local h = c.arrow(SPEC)
        local before = #made
        h.menu(ITEMS, function() end)
        local catcher = made[before + 1]
        if not catcher then
            t.ok(false, "a catcher was made")
            return
        end
        t.eq(firstSeen(catcher), "Hide", "hidden first")
        t.eq(shown(catcher), true, "and shown once the menu has opened fully")
    end,

    ["catcher: after a failed first open the next open uses the same catcher and shows it"] = function(t)
        local h, catcher, e, made = failedOpen("raise")
        if not catcher then
            t.ok(false, "a catcher was made before the panel")
            return
        end
        local before = catchers(e, made)
        e.panel = nil
        local got = {}
        h.menu(ITEMS, function(key) got[#got + 1] = key end)
        t.eq(catchers(e, made), before, "no second catcher")
        t.eq(shown(catcher), true, "shown with the menu open")
        local on = script(catcher, "OnClick")
        t.ok(type(on) == "function", "the catcher takes a click")
        if type(on) == "function" then on(catcher, "LeftButton") end
        t.eq(shown(catcher), false, "a click beside the menu closes it")
        t.eq(#got, 0, "and tells nothing")
    end,

    ["catcher: a click on a catcher that is on screen with no menu open hides it"] = function(t)
        -- The close with no owner set: the catcher must still go.
        local _, catcher = failedOpen("raise")
        if not catcher then
            t.ok(false, "a catcher was made before the panel")
            return
        end
        catcher:Show()
        local on = script(catcher, "OnClick")
        t.ok(type(on) == "function", "the catcher takes a click")
        if type(on) == "function" then on(catcher, "LeftButton") end
        t.eq(shown(catcher), false)
    end,

    ["catcher: closing a menu hides it and the next menu shows it again"] = function(t)
        local e, made = env()
        local c = ns.make.client(e)
        local h = c.arrow(SPEC)
        local before = #made
        h.menu(ITEMS, function() end)
        local catcher = made[before + 1]
        if not catcher then
            t.ok(false, "a catcher was made")
            return
        end
        t.eq(shown(catcher), true)
        h.menu(nil)
        t.eq(shown(catcher), false, "menu(nil) hides it")
        h.menu(ITEMS, function() end)
        t.eq(shown(catcher), true, "and it comes back with the next menu")
    end,

    ["panel (F4): clamped to the screen and opened 4px right of and below the pointer, as Flow's menu"] = function(t)
        local e, made = env()
        e.GetCursorPosition = function() return 100, 200 end
        e.UIParent.answers = { GetEffectiveScale = function() return 2 end }
        local c = ns.make.client(e)
        local h = c.arrow(SPEC)
        local before = #made
        h.menu(ITEMS, function() end)
        local panel
        for i = before + 1, #made do
            if made[i].kind == "Frame" and not panel then panel = made[i] end
        end
        if not panel then
            t.ok(false, "a panel was made")
            return
        end
        local clamped, point = false, nil
        for _, cl in ipairs(panel.calls) do
            if cl.name == "SetClampedToScreen" and cl[1] == true then clamped = true end
            if cl.name == "SetPoint" then point = cl end
        end
        t.eq(clamped, true, "the panel cannot open off the screen edge")
        t.eq(point and { point[1], point[3], point[4], point[5] }, { "TOPLEFT", "BOTTOMLEFT", 54, 96 })
    end,

    -- ---------------------------------------------------------------- AI2
    ["tip: a tooltip that cannot say whose it is is left alone"] = function(t)
        local e = env()
        e.GameTooltip = stub("GameTooltip")
        local c = ns.make.client(e)
        local h = c.arrow(SPEC)
        h.tip({ "Quest arrow" })
        -- IsOwned answers nothing here: not known is not "ours".
        h.tip(nil)
        t.eq(count(e.GameTooltip, "Hide"), 0, "not hidden on a guess")

        h.tip({ "Quest arrow" })
        e.GameTooltip.answers = { IsOwned = function() error("no such method") end }
        t.ok(pcall(h.tip, nil), "a raising IsOwned is not thrown at the caller")
        t.eq(count(e.GameTooltip, "Hide"), 0)

        h.tip({ "Quest arrow" })
        e.GameTooltip.answers = { IsOwned = function() return true end }
        h.tip(nil)
        t.eq(count(e.GameTooltip, "Hide"), 1, "hidden when IsOwned answers true")
    end,
}
