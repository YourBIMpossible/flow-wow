-- Escape and the arrows' menu, end to end over the fake client (owner
-- decision D9, default N1): Escape closes an open menu and does nothing
-- else; with no menu open the key is not taken. c.escape() is the fake's
-- control: the player presses Escape. It answers whether the key was taken
-- (a menu closed), as the game's special frames do. No game client.
local _, ns = ...

local A = ns.Arrow
local N = ns.Nav

local function start()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setScreen(1024, 768)
    c.setZone(1, 1411)
    c.setFacing(0)
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    A.Declare(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    d.commands.arrow("demo")
    c.advance(0.1, 2)
    return k, c
end

local function saved(k)
    return N.ArrowSaved({ arrows = k.settings:get(A.SETTING) })
end

local function has(t, c)
    local q = c.arrows[1]
    local ok = type(c.escape) == "function" and q ~= nil and type(q.click) == "function"
        and type(q.choose) == "function"
    t.ok(ok, "the fake client has an Escape key and arrows that can be clicked")
    return ok
end

return {
    ["escape key: an open menu closes and the key is taken"] = function(t)
        local k, c = start()
        if not has(t, c) then return end
        local q = c.arrows[1]
        q.click("right")
        t.ok(type(q.menuItems) == "table", "the menu is open")
        t.eq(c.escape(), true, "the key is taken")
        t.eq(q.menuItems, nil, "the menu is closed")
        t.eq(k.problems:count(), 0)
    end,

    ["escape key: closing changes nothing that is saved or shown"] = function(t)
        local k, c = start()
        if not has(t, c) then return end
        local q = c.arrows[1]
        q.drag({ "CENTER", "CENTER", 200, 100 })
        local before, lines = saved(k), #q.lines
        q.click("right")
        c.escape()
        t.eq(saved(k), before, "the layout is as it was")
        t.eq(q.shown, true, "the arrow is still shown")
        t.eq(#q.lines, lines, "with its text")
        t.eq(k.problems:count(), 0)
    end,

    ["escape key: no row is chosen, then or after"] = function(t)
        local k, c = start()
        if not has(t, c) then return end
        local q = c.arrows[1]
        q.click("right")
        c.escape()
        q.choose("separate")
        t.eq(saved(k).mode, "stacked", "a closed menu chooses nothing")
        t.eq(k.problems:count(), 0)
    end,

    ["escape key: with no menu open the key is not taken"] = function(t)
        local k, c = start()
        if not has(t, c) then return end
        local q = c.arrows[1]
        local before = saved(k)
        t.eq(c.escape(), false, "the game has the key")
        t.eq(q.menuItems, nil)
        t.eq(q.shown, true)
        t.eq(saved(k), before)
        t.eq(k.problems:count(), 0)
    end,

    ["escape key: a second Escape is the game's"] = function(t)
        local _, c = start()
        if not has(t, c) then return end
        local q = c.arrows[1]
        q.click("right")
        t.eq(c.escape(), true)
        t.eq(c.escape(), false)
    end,

    ["escape key: the menu opens again after it"] = function(t)
        local k, c = start()
        if not has(t, c) then return end
        local q = c.arrows[1]
        q.click("right")
        c.escape()
        q.click("right")
        t.ok(type(q.menuItems) == "table", "open again")
        q.choose("separate")
        t.eq(saved(k).mode, "separate", "and a row works as before")
        t.eq(k.problems:count(), 0)
    end,

    ["escape key: a menu chosen from is already closed, so the key is the game's"] = function(t)
        local _, c = start()
        if not has(t, c) then return end
        local q = c.arrows[1]
        q.click("right")
        q.choose("reset")
        t.eq(c.escape(), false)
    end,

    ["escape key: a client with no arrows takes no key"] = function(t)
        local c = ns.make.fakeClient()
        if type(c.escape) ~= "function" then
            t.ok(false, "the fake client has an Escape key")
            return
        end
        t.eq(c.escape(), false)
    end,
}
