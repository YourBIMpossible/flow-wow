-- Escape and the arrows' menu on the client (Core/Client.lua, owner
-- decision D9): the menu's catcher has a global name and is listed in the
-- game's UISpecialFrames, so the game hides it at Escape and takes the key
-- only then; hidden by the game, the menu is closed (no owner, no choice).
-- Over a stub environment that records every call. No game client is
-- involved: this checks which calls land on which object, not what the
-- game does with the list. Not seen in game on 16001.
local _, ns = ...

local function stub(kind)
    local o = { kind = kind, calls = {} }
    return setmetatable(o, { __index = function(_, name)
        -- Fields a test reads (a frame's name and parent) are data, not
        -- methods: an unset one reads as nil, as on a game frame.
        if name == "name" or name == "parent" then return nil end
        return function(self, ...)
            self.calls[#self.calls + 1] = { name = name, ... }
            if name == "CreateTexture" or name == "CreateFontString" then return stub(name) end
            return nil
        end
    end })
end

-- As the game: a frame made with a name is a global of that name.
local function env()
    local made = {}
    local e = { UIParent = stub("UIParent"), UISpecialFrames = { "SomeOtherWindow" } }
    e.CreateFrame = function(kind, name, parent)
        local f = stub(kind)
        f.name, f.parent = name, parent
        made[#made + 1] = f
        if type(name) == "string" then e[name] = f end
        return f
    end
    return e, made
end

local SPEC = { name = "TestArrow", size = 56, art = 64, artPath = "x\\" }
local OTHER = { name = "TestNeedle", size = 56, art = 64, artPath = "x\\" }
local ITEMS = { { text = "Reset", key = "reset" } }

local function shown(o)
    local on = true
    for _, cl in ipairs(o.calls) do
        if cl.name == "Show" then on = true elseif cl.name == "Hide" then on = false end
    end
    return on
end

local function script(o, name)
    local out
    for _, cl in ipairs(o.calls) do
        if cl.name == "SetScript" and cl[1] == name then out = cl[2] end
    end
    return out
end

-- The catcher: the button made on UIParent itself. -> it, how many
local function catcherOf(e, made)
    local found, n = nil, 0
    for _, f in ipairs(made) do
        if f.kind == "Button" and f.parent == e.UIParent then found, n = found or f, n + 1 end
    end
    return found, n
end

-- The first row of the open menu: a button on the panel, which is the
-- frame made on the catcher.
local function firstRow(made, catcher)
    local panel
    for _, f in ipairs(made) do
        if f.kind == "Frame" and f.parent == catcher then panel = f end
    end
    for _, f in ipairs(made) do
        if panel and f.kind == "Button" and f.parent == panel then return f end
    end
    return nil
end

local function listed(e, name)
    local n = 0
    for i = 1, #e.UISpecialFrames do
        if e.UISpecialFrames[i] == name then n = n + 1 end
    end
    return n
end

-- A client, one arrow with its menu open, and the catcher.
local function opened(e, made, spec)
    local c = ns.make.client(e)
    local h = c.arrow(spec or SPEC)
    local got = {}
    local ok = pcall(h.menu, ITEMS, function(key) got[#got + 1] = key end)
    local catcher = catcherOf(e, made)
    return h, catcher, got, ok, c
end

return {
    ["escape route: the catcher has a global name of the arrow's own"] = function(t)
        local e, made = env()
        local _, catcher = opened(e, made)
        if not catcher then
            t.ok(false, "a catcher was made")
            return
        end
        t.eq(catcher.name, "TestArrowMenu")
        t.eq(catcher.kind, "Button", "still the full-screen button")
    end,

    ["escape route: the catcher is listed in the game's special frames, after what was there"] = function(t)
        local e, made = env()
        opened(e, made)
        t.eq(e.UISpecialFrames, { "SomeOtherWindow", "TestArrowMenu" })
    end,

    ["escape route: it is listed once, however often a menu opens and from either arrow"] = function(t)
        local e, made = env()
        local h, _, _, _, c = opened(e, made)
        local p = c.arrow(OTHER)
        h.menu(nil)
        h.menu(ITEMS, function() end)
        p.menu(ITEMS, function() end)
        h.menu(ITEMS, function() end)
        local _, n = catcherOf(e, made)
        t.eq(n, 1, "one catcher for both arrows")
        t.eq(listed(e, "TestArrowMenu"), 1)
        t.eq(#e.UISpecialFrames, 2, "and nothing else was added")
    end,

    ["escape route: hidden by the game, the menu is closed and a row tells nothing"] = function(t)
        local e, made = env()
        local h, catcher, got = opened(e, made)
        if not catcher then
            t.ok(false, "a catcher was made")
            return
        end
        local onHide = script(catcher, "OnHide")
        t.ok(type(onHide) == "function", "the catcher hears that it was hidden")
        if type(onHide) ~= "function" then return end
        local row = firstRow(made, catcher)
        local click = row and script(row, "OnClick")
        t.ok(type(click) == "function", "the row takes a click")
        if type(click) ~= "function" then return end
        -- The game's Escape: it hides the listed frame itself.
        catcher:Hide()
        t.ok(pcall(onHide, catcher), "the close raises nothing")
        click(row, "LeftButton")
        t.eq(#got, 0, "no row was chosen by Escape, and none can be after it")
        t.eq(shown(catcher), false, "the catcher is not put back")
        -- And the menu opens again as before.
        h.menu(ITEMS, function(key) got[#got + 1] = key end)
        t.eq(shown(catcher), true, "the next menu shows it")
        click(row, "LeftButton")
        t.eq(got, { "reset" }, "and a row can be chosen again")
    end,

    ["escape route: hidden with no menu open, nothing is raised and nothing is shown"] = function(t)
        local e, made = env()
        local h, catcher = opened(e, made)
        if not catcher then
            t.ok(false, "a catcher was made")
            return
        end
        local onHide = script(catcher, "OnHide")
        t.ok(type(onHide) == "function", "the catcher hears that it was hidden")
        if type(onHide) ~= "function" then return end
        h.menu(nil)
        t.ok(pcall(onHide, catcher))
        t.ok(pcall(onHide, catcher), "twice over")
        t.eq(shown(catcher), false)
    end,

    ["escape route: a client without the list still opens the menu"] = function(t)
        local e, made = env()
        e.UISpecialFrames = nil
        local _, catcher, _, ok = opened(e, made)
        t.ok(ok, "nothing is raised")
        t.eq(e.UISpecialFrames, nil, "no list is made up")
        t.ok(catcher ~= nil and shown(catcher), "the menu is open")
    end,

    ["escape route: a list that is not a table is left alone"] = function(t)
        local e, made = env()
        e.UISpecialFrames = "no"
        local _, catcher, _, ok = opened(e, made)
        t.ok(ok, "nothing is raised")
        t.eq(e.UISpecialFrames, "no")
        t.ok(catcher ~= nil and shown(catcher), "the menu is open")
    end,

    ["escape route: a name that is already taken is not taken over"] = function(t)
        local e, made = env()
        local theirs = { theirs = true }
        e.TestArrowMenu = theirs
        local _, catcher, _, ok = opened(e, made)
        t.ok(ok, "nothing is raised")
        t.eq(e.TestArrowMenu, theirs, "the other frame keeps its name")
        t.ok(catcher ~= nil and catcher.name == nil, "the catcher is made without a name")
        t.eq(e.UISpecialFrames, { "SomeOtherWindow" }, "and the frame of another is not listed as ours")
        t.ok(catcher ~= nil and shown(catcher), "the menu still opens")
    end,

    ["escape route: an arrow without a name gives a menu without one"] = function(t)
        local e, made = env()
        local _, catcher, _, ok = opened(e, made, { size = 56, art = 64, artPath = "x\\" })
        t.ok(ok, "nothing is raised")
        t.ok(catcher ~= nil and catcher.name == nil, "no name is made up")
        t.eq(e.UISpecialFrames, { "SomeOtherWindow" })
        t.ok(catcher ~= nil and shown(catcher), "the menu still opens")
    end,

    ["escape route: a click beside the menu still closes it"] = function(t)
        local e, made = env()
        local _, catcher, got = opened(e, made)
        if not catcher then
            t.ok(false, "a catcher was made")
            return
        end
        local on = script(catcher, "OnClick")
        t.ok(type(on) == "function", "the catcher takes a click")
        if type(on) == "function" then on(catcher, "LeftButton") end
        t.eq(shown(catcher), false)
        t.eq(#got, 0)
    end,
}
