-- The arrow acceptance of F1, end to end over the fake client: the two
-- arrows separate, keep their places over a reload, restack from the menu
-- and separate again to the same places, and the quest arrow keeps its
-- colour while the separated echo stays the fainter one, in its purple. The pure layout
-- rules are in Tests/Nav/ArrowLayout.lua; these pin the module on top of
-- them. No game client is involved.
local _, ns = ...

local A, N = ns.Arrow, ns.Nav

local STACK = { "CENTER", "CENTER", 200, 100 }
local FAR = { "CENTER", "CENTER", -300, -200 }

-- saved: the account table of an earlier start (a reload), or nil.
local function start(saved)
    local c = ns.make.fakeClient()
    saved = saved or {}
    if type(saved.layout) ~= "table" then saved.layout = {} end
    saved.layout.arrowIntroSeen = true
    c.setSaved(ns.id.accountDB, saved)
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
    return k, c, d
end

-- The saved layout as the arrows read it.
local function layout(c)
    local saved = c.saved(ns.id.accountDB).layout
    return N.ArrowSaved({ arrows = type(saved) == "table" and saved.arrows or nil })
end

-- Both arrows, and the hand of the fake on them; without them the test
-- fails here.
local function both(t, c)
    local q, p = c.arrows[1], c.arrows[2]
    local ok = q ~= nil and p ~= nil and type(q.drag) == "function" and type(q.choose) == "function"
    t.ok(ok, "the fake client has both arrows and its hand on them")
    return ok, q, p
end

-- Stacked at STACK, then the needle on its own at FAR.
local function apart(c, d)
    c.arrows[1].drag(STACK)
    d.commands.arrow("separate")
    c.arrows[2].drag(FAR)
end

local function near(a, b)
    return math.abs(a[1] - b[1]) + math.abs(a[2] - b[2]) + math.abs(a[3] - b[3]) < 0.02
end

return {
    ["arrow acceptance: separation and both places survive a reload"] = function(t)
        local k, c, d = start()
        local ok = both(t, c)
        if not ok then return end
        apart(c, d)
        t.eq(layout(c).mode, "separate")

        local k2, c2 = start(c.saved(ns.id.accountDB))
        local ok2, q, p = both(t, c2)
        if not ok2 then return end
        t.eq(layout(c2).mode, "separate", "still separate after the reload")
        t.eq(q.point, STACK, "the quest arrow where it was left")
        t.eq(p.point, FAR, "the needle where it was left")
        t.eq(p.attached, nil, "not fixed to the quest arrow")
        t.eq(p.under, false)
        t.eq({ q.shown, p.shown }, { true, true })
        t.eq(k.problems:count() + k2.problems:count(), 0)
    end,

    ["arrow acceptance: Restack from the menu puts the profession arrow back behind the quest arrow, which stays"] = function(t)
        local k, c, d = start()
        local ok, q, p = both(t, c)
        if not ok then return end
        apart(c, d)
        q.click("right")
        q.choose("restack")
        t.eq(layout(c).mode, "stacked")
        t.eq(p.attached, nil, "the profession arrow has its own place, below the quest arrow")
        t.eq(p.under, false, "slid below it (no spread known): not behind, it takes the mouse itself")
        t.eq(q.under, false, "the quest arrow in front")
        t.eq(p.lookIs, "pointer", "drawn as the quest arrow's echo again, no needle")
        t.eq(p.faded, N.ECHO_ALPHA, "see-through")
        t.eq(p.point, { STACK[1], STACK[2], STACK[3], STACK[4] - (N.ARROW_SIZE + N.ARROW_GAP) },
            "the demo gives no spread: slid one arrow and a gap straight down")
        t.eq(layout(c).points.quest, STACK, "the quest arrow did not move")
        t.eq(q.point, STACK)
        t.eq(k.problems:count(), 0)
    end,

    ["arrow acceptance: restacked arrows separate again to the place the needle had"] = function(t)
        local k, c, d = start()
        local ok, q, p = both(t, c)
        if not ok then return end
        apart(c, d)
        q.click("right")
        q.choose("restack")
        t.eq(layout(c).points.prof, FAR, "the place of the needle is kept while stacked")
        q.click("right")
        q.choose("separate")
        t.eq(layout(c).mode, "separate")
        t.eq(p.point, FAR)
        t.eq(q.point, STACK)
        t.eq(k.problems:count(), 0)
    end,

    ["arrow acceptance: a restacked layout is stacked after a reload too"] = function(t)
        local _, c, d = start()
        local ok, q = both(t, c)
        if not ok then return end
        apart(c, d)
        q.click("right")
        q.choose("restack")

        local k2, c2 = start(c.saved(ns.id.accountDB))
        local ok2, q2, p2 = both(t, c2)
        if not ok2 then return end
        t.eq(layout(c2).mode, "stacked")
        t.eq(q2.point, STACK)
        t.eq(p2.attached, nil)
        t.eq(p2.under, false, "slid below it (no spread known): not behind, it takes the mouse itself")
        t.eq(p2.lookIs, "pointer", "no needle")
        t.eq(p2.point, { STACK[1], STACK[2], STACK[3], STACK[4] - (N.ARROW_SIZE + N.ARROW_GAP) })
        t.eq(k2.problems:count(), 0)
    end,

    ["arrow acceptance: the quest arrow keeps its colour when the arrows separate"] = function(t)
        local k, c, d = start()
        local ok, q = both(t, c)
        if not ok then return end
        c.advance(3, 60)
        local stacked = q.drawn and q.drawn.colour
        t.ok(type(stacked) == "table" and #stacked == 3, "the quest arrow is drawn in a colour")
        if type(stacked) ~= "table" then return end
        stacked = { stacked[1], stacked[2], stacked[3] }
        apart(c, d)
        c.advance(3, 60)
        t.ok(near(q.drawn.colour, stacked), "the same colour stacked and separate")
        t.eq(k.problems:count(), 0)
    end,

    ["arrow acceptance: the separated echo wears its own purple by distance and stays the fainter arrow"] = function(t)
        local k, c, d = start()
        local ok, q, p = both(t, c)
        if not ok then return end
        apart(c, d)
        c.advance(3, 60)
        local r, g, b = N.EchoColor("zone", N.ARROW_DEMO_PROF or A.DEMO.profDistance)
        t.ok(near(p.drawn.colour, { r, g, b }), "the echo's purple at that distance")
        local qr, qg, qb = N.ArrowColor("zone", N.ARROW_DEMO_PROF or A.DEMO.profDistance)
        t.ok(not near(p.drawn.colour, { qr, qg, qb }), "not the colour the quest arrow would have there")
        t.eq(p.lookIs, "pointer", "the echo's look, no needle")
        t.eq(q.faded, 1, "the quest arrow at full opacity")
        t.eq(p.faded, N.ECHO_ALPHA)
        t.ok(p.faded < q.faded, "the echo is the fainter one")
        t.eq(k.problems:count(), 0)
    end,
}
