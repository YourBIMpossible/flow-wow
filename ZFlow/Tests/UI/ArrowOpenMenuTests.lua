-- The arrows' menu opened without a click on an arrow (F9: the world-map
-- button asks the "arrow" module for OpenMenu). Over the fake client; no
-- game client.
local _, ns = ...

local A = ns.Arrow

local function start(noLogin)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setScreen(1024, 768)
    c.setZone(1, 1411)
    c.setFacing(0)
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    local a = A.Declare(k, d)
    k:Boot()
    if not noLogin then
        c.fire("ADDON_LOADED", ns.id.addon)
        c.fire("PLAYER_LOGIN")
        c.fire("PLAYER_ENTERING_WORLD")
    end
    return k, c, a
end

local function openMenus(c)
    local n = 0
    for _, h in ipairs(c.arrows) do
        if h.menuItems ~= nil then n = n + 1 end
    end
    return n
end

return {
    ["arrow open menu: before the start it answers false and opens nothing"] = function(t)
        local _, c, a = start(true)
        t.eq(a.openMenu(), false)
        t.eq(openMenus(c), 0)
    end,

    ["arrow open menu: after login it opens the menu on one arrow"] = function(t)
        local _, c, a = start()
        t.ok(#c.arrows > 0, "there are arrows")
        t.eq(openMenus(c), 0, "closed until asked")
        t.eq(a.openMenu(), true)
        t.eq(openMenus(c), 1, "one menu, not one on each arrow")
    end,

    ["arrow open menu: the menu has the rows a right click gives"] = function(t)
        local _, c, a = start()
        a.openMenu()
        local items
        for _, h in ipairs(c.arrows) do items = items or h.menuItems end
        t.ok(type(items) == "table" and #items > 0, "rows")
    end,

    ["arrow open menu: the module provides it by name"] = function(t)
        local k, c = start()
        local arrow = k.use(A.NAME)
        t.ok(type(arrow) == "table" and type(arrow.OpenMenu) == "function", "OpenMenu is provided")
        if type(arrow) ~= "table" or type(arrow.OpenMenu) ~= "function" then return end
        t.eq(arrow.OpenMenu(), true)
        t.eq(openMenus(c), 1)
    end,

    ["arrow open menu: a client with no frames answers false"] = function(t)
        local c = ns.make.fakeClient()
        c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
        c.setFrames(false)
        local k = ns.Kernel({}, c)
        local a = A.Declare(k, ns.Diag.Start(k))
        k:Boot()
        c.fire("ADDON_LOADED", ns.id.addon)
        c.fire("PLAYER_LOGIN")
        c.fire("PLAYER_ENTERING_WORLD")
        t.eq(a.openMenu(), false)
    end,
}
