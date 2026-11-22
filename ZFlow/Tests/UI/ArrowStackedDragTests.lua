-- A Ctrl-drag on the profession needle while the arrows are stacked (owner
-- decision D3), end to end over the fake client: let go away from the
-- stack it is on its own and the arrows are separate; let go on the stack
-- it stays stacked; without Ctrl nothing moves. The quest arrow stays where
-- it is throughout. These pin what UI/Arrow.lua and Nav/ArrowLayout.lua
-- already do with the place a drag tells them; the mouse target that lets
-- the drag start on the client is checked in Tests/Core. No game client.
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
    local q, p = c.arrows[1], c.arrows[2]
    local ok = q ~= nil and p ~= nil and type(p.drag) == "function"
    t.ok(ok, "the fake client has both arrows and the needle can be dragged")
    return ok
end

local STACK = { "CENTER", "CENTER", 200, 100 }
local FAR = { "CENTER", "CENTER", -300, -200 }

return {
    ["stacked needle drag: let go away from the stack, the arrows are separate"] = function(t)
        local k, c = start()
        if not has(t, c) then return end
        local q, p = c.arrows[1], c.arrows[2]
        t.eq(saved(k).mode, "stacked", "stacked to begin with")
        t.eq(p.under, true)
        q.drag(STACK)
        c.advance(0.1, 2)
        t.eq(saved(k).mode, "stacked", "moving the stack keeps it stacked")
        p.drag(FAR)
        c.advance(0.1, 2)
        local now = saved(k)
        t.eq(now.mode, "separate")
        t.eq(now.points.prof, FAR, "the needle is where it was let go")
        t.eq(now.points.quest, STACK, "the quest arrow did not move")
        t.eq(p.under, false, "the needle is no longer under the quest arrow")
        t.eq(p.attached, nil, "nor fixed to it")
        t.eq(q.shown, true)
        t.eq(k.problems:count(), 0)
    end,

    ["stacked needle drag: let go on the stack, the arrows stay stacked"] = function(t)
        local k, c = start()
        if not has(t, c) then return end
        local q, p = c.arrows[1], c.arrows[2]
        q.drag(STACK)
        c.advance(0.1, 2)
        p.drag({ STACK[1], STACK[2], STACK[3] + 5, STACK[4] + 5 })
        c.advance(0.1, 2)
        t.eq(saved(k).mode, "stacked")
        t.eq(saved(k).points.quest, STACK)
        t.eq(p.under, true)
        t.eq(k.problems:count(), 0)
    end,

    ["stacked needle drag: without Ctrl nothing moves and nothing is saved"] = function(t)
        local k, c = start()
        if not has(t, c) then return end
        local p = c.arrows[2]
        local before = saved(k)
        c.setMoveKey(false)
        p.drag(FAR)
        c.advance(0.1, 2)
        t.eq(saved(k), before)
        t.eq(p.under, true)
        t.eq(k.problems:count(), 0)
    end,

    ["stacked needle drag: once separate, the needle goes back under when dropped on the quest arrow"] = function(t)
        local k, c = start()
        if not has(t, c) then return end
        local q, p = c.arrows[1], c.arrows[2]
        q.drag(STACK)
        c.advance(0.1, 2)
        p.drag(FAR)
        c.advance(0.1, 2)
        t.eq(saved(k).mode, "separate")
        p.drag({ STACK[1], STACK[2], STACK[3], STACK[4] })
        c.advance(0.1, 2)
        t.eq(saved(k).mode, "stacked")
        t.eq(p.under, true)
        t.eq(k.problems:count(), 0)
    end,
}
