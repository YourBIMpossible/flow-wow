-- Escape and the arrows' menu (owner default N1): Escape closes an open
-- menu and does nothing else; with no menu open the key is not taken, so
-- the game's own Escape goes on as before. Only the decision and the close
-- are checked here, over the fake client's arrow handle. No key reaches
-- this from the fake client or the real one yet: see UI/ArrowMenu.lua.
local _, ns = ...

local M = ns.ArrowMenu

local function has(t)
    local ok = type(M) == "table" and type(M.Key) == "function" and type(M.OnKey) == "function"
    t.ok(ok, "ns.ArrowMenu answers Key and OnKey")
    return ok
end

-- An arrow handle of the fake client, and what its menu was told.
local function arrow()
    local c = ns.make.fakeClient()
    local h = c.arrow({})
    local told = { menu = 0, picked = {} }
    local menu = h.menu
    h.menu = function(items, fn)
        told.menu = told.menu + 1
        return menu(items, fn)
    end
    return h, told
end

local function open(h, told)
    h.show(true)
    h.menu(M.Items({ stacked = true }), function(key) told.picked[#told.picked + 1] = key end)
    told.menu = 0
end

return {
    ["escape: the key has a name"] = function(t)
        if not has(t) then return end
        t.eq(M.ESCAPE, "ESCAPE")
    end,

    ["escape: with a menu open it asks to close, and only that"] = function(t)
        if not has(t) then return end
        t.eq(M.Key("ESCAPE", true), { close = true })
    end,

    ["escape: with no menu open it asks for nothing"] = function(t)
        if not has(t) then return end
        t.eq(M.Key("ESCAPE", false), nil)
        t.eq(M.Key("ESCAPE", nil), nil)
        t.eq(M.Key("ESCAPE"), nil)
        t.eq(M.Key("ESCAPE", 1), nil, "open is true or it is not open")
        t.eq(M.Key("ESCAPE", "yes"), nil)
    end,

    ["escape: no other key asks for anything, menu open or not"] = function(t)
        if not has(t) then return end
        for _, key in ipairs({ "ENTER", "SPACE", "TAB", "E", "ESC", "escape", "Escape", " ESCAPE", "ESCAPE ", "" }) do
            t.eq(M.Key(key, true), nil, "[" .. key .. "] with a menu open")
            t.eq(M.Key(key, false), nil, "[" .. key .. "] with no menu")
        end
        t.eq(M.Key(nil, true), nil)
        t.eq(M.Key(27, true), nil)
        t.eq(M.Key({}, true), nil)
    end,

    ["escape: an open menu closes and the key is taken"] = function(t)
        if not has(t) then return end
        local h, told = arrow()
        open(h, told)
        t.ok(h.menuItems ~= nil, "the menu is open")
        t.eq(M.OnKey(h, "ESCAPE", true), true, "the key is taken")
        t.eq(h.menuItems, nil, "the menu is closed")
        t.eq(told.menu, 1, "the menu was told once")
    end,

    ["escape: closing chooses no row"] = function(t)
        if not has(t) then return end
        local h, told = arrow()
        open(h, told)
        M.OnKey(h, "ESCAPE", true)
        t.eq(#told.picked, 0, "nothing was chosen")
        h.choose("reset")
        t.eq(#told.picked, 0, "and nothing can be chosen from a closed menu")
    end,

    ["escape: the arrow stays as it was"] = function(t)
        if not has(t) then return end
        local h, told = arrow()
        h.place({ "CENTER", 10, 20, 1 })
        h.text({ "Kill ten boars" }, { "TOP", 0, -4, 1 })
        open(h, told)
        local draws = h.draws
        M.OnKey(h, "ESCAPE", true)
        t.eq(h.shown, true, "still shown")
        t.eq(h.point, { "CENTER", 10, 20, 1 }, "still where it was")
        t.eq(h.lines, { "Kill ten boars" }, "its text is kept")
        t.eq(h.draws, draws, "nothing was drawn")
    end,

    ["escape: with no menu open the key is not taken and nothing is told"] = function(t)
        if not has(t) then return end
        local h, told = arrow()
        h.show(true)
        t.eq(M.OnKey(h, "ESCAPE", false), false, "the key is left to the game")
        t.eq(M.OnKey(h, "ESCAPE", nil), false)
        t.eq(M.OnKey(h, "ESCAPE"), false)
        t.eq(told.menu, 0, "the menu was not touched")
        t.eq(h.menuItems, nil)
    end,

    ["escape: another key leaves an open menu open and is not taken"] = function(t)
        if not has(t) then return end
        local h, told = arrow()
        open(h, told)
        for _, key in ipairs({ "ENTER", "SPACE", "escape", "ESC", "" }) do
            t.eq(M.OnKey(h, key, true), false, "[" .. key .. "] is not taken")
        end
        t.eq(M.OnKey(h, nil, true), false)
        t.eq(told.menu, 0, "the menu was not touched")
        t.ok(h.menuItems ~= nil, "the menu is still open")
        h.choose("reset")
        t.eq(told.picked, { "reset" }, "and a row can still be chosen")
    end,

    ["escape: a second Escape is not taken"] = function(t)
        if not has(t) then return end
        local h, told = arrow()
        open(h, told)
        t.eq(M.OnKey(h, "ESCAPE", h.menuItems ~= nil), true)
        t.eq(M.OnKey(h, "ESCAPE", h.menuItems ~= nil), false, "the menu is closed: the game has the key")
        t.eq(told.menu, 1)
    end,

    ["escape: a handle that cannot close a menu takes no key"] = function(t)
        if not has(t) then return end
        t.eq(M.OnKey(nil, "ESCAPE", true), false)
        t.eq(M.OnKey({}, "ESCAPE", true), false)
        t.eq(M.OnKey({ menu = "no" }, "ESCAPE", true), false)
        t.eq(M.OnKey(7, "ESCAPE", true), false)
    end,

    ["escape: a close that breaks is not taken and is not raised"] = function(t)
        if not has(t) then return end
        local h = { menu = function() error("no menu") end }
        local ok, taken = pcall(M.OnKey, h, "ESCAPE", true)
        t.eq(ok, true, "nothing is raised into the key handler")
        t.eq(taken, false, "the key is left to the game")
    end,

    ["escape: the menu has no row for it and choosing it asks for nothing"] = function(t)
        if not has(t) then return end
        local s = { stacked = true }
        for _, r in ipairs(M.Items(s)) do
            if r.key then t.ok(r.key:lower():find("esc", 1, true) == nil, r.key) end
        end
        t.eq(M.Action("ESCAPE", s), nil)
        t.eq(M.Action("escape", s), nil)
        t.eq(M.Action("close", s), nil)
    end,
}
