-- The arrow style as the player changes it (inventory rows 4 to 11): the
-- setting, the word, the list for a menu, the one-time move of an old "3d",
-- and which arrow is drawn from lines. Over the fake client; no game client.
local _, ns = ...

local A = ns.Arrow

-- opts: saved (the account table), lines = false (the client draws no lines).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    local saved = opts.saved or {}
    if type(saved.layout) ~= "table" then saved.layout = {} end
    saved.layout.arrowIntroSeen = true
    c.setSaved(ns.id.accountDB, saved)
    c.setScreen(1024, 768)
    c.setZone(1, 1411)
    c.setFacing(0)
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    if opts.lines == false and type(c.setLines) == "function" then c.setLines(false) end
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    local a = A.Declare(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, a, d
end

local function said(c, text)
    for i = 1, #c.printed do
        if tostring(c.printed[i]):find(text, 1, true) then return true end
    end
    return false
end

local function style(k) return k.store:get("account", "layout.arrowStyle") end

-- The tests below need the style answers; without them each fails here.
local function has(t, a)
    local ok = type(a) == "table" and type(a.style) == "function" and type(a.styles) == "function"
        and type(a.setStyle) == "function"
    t.ok(ok, "the arrows answer style, styles and setStyle")
    return ok
end

return {
    ["style: modern by default; the quest arrow is drawn from its pictures"] = function(t)
        local k, c, a, d = start()
        if not has(t, a) then return end
        d.commands.arrow("demo")
        c.advance(0.1, 2)
        local q = c.arrows[1]
        t.eq(a.style(), "modern")
        t.ok(q.draws > 0, "drawn")
        t.eq(q.shaped, nil, "no lines")
        t.eq(k.problems:count(), 0)
    end,

    ["style: the word sets it, saves it and says its name"] = function(t)
        local k, c, a, d = start()
        if not has(t, a) then return end
        d.commands.arrow("demo")
        d.commands.arrow("flat")
        t.eq(style(k), "flat")
        t.eq(k.settings:get(A.STYLE), "flat", "the setting row reads the same place")
        t.eq(a.style(), "flat")
        t.ok(said(c, "arrow style: Flat lines."), "said")
        d.commands.arrow("3d")
        t.eq(style(k), "3d")
        t.ok(said(c, "arrow style: 3D (pillars)."), "said")
        d.commands.arrow("modern")
        t.eq(a.style(), "modern")
        t.ok(said(c, "arrow style: Modern."), "said")
        t.eq(k.problems:count(), 0)
    end,

    ["style: the usage line names the three styles"] = function(t)
        local _, c, _, d = start()
        d.commands.arrow("what")
        t.ok(said(c, "modern | 3d | flat"), "usage")
    end,

    ["style: flat and 3d draw the quest arrow from lines; the needle keeps its pictures"] = function(t)
        local _, c, a, d = start()
        if not has(t, a) then return end
        d.commands.arrow("demo")
        d.commands.arrow("flat")
        local q, p = c.arrows[1], c.arrows[2]
        local qDraws, pDraws = q.draws, p.draws
        c.advance(0.1, 2)
        t.ok(type(q.shaped) == "table", "the quest arrow got shapes")
        if type(q.shaped) ~= "table" then return end
        t.eq(q.shaped.nl, 9, "the flat arrow, in lines")
        t.eq(q.draws, qDraws, "and no picture frame")
        t.ok(p.draws > pDraws, "the needle is drawn as before")
        t.eq(p.shaped, nil)
        d.commands.arrow("3d")
        c.advance(0.1, 1)
        t.eq(q.shaped.nl, 69, "the 3D arrow, in lines")
        d.commands.arrow("near")
        c.advance(0.1, 1)
        t.eq(q.shaped.nl, 16, "arrived: the pillars only")
    end,

    ["style: back to modern, the lines are cleared and the pictures drawn again"] = function(t)
        local _, c, a, d = start()
        if not has(t, a) then return end
        d.commands.arrow("demo")
        d.commands.arrow("flat")
        c.advance(0.1, 2)
        local q = c.arrows[1]
        t.ok(type(q.shaped) == "table", "lines first")
        local draws = q.draws
        d.commands.arrow("modern")
        c.advance(0.1, 2)
        t.eq(q.shaped, nil, "cleared")
        t.ok(q.draws > draws, "drawn from pictures")
    end,

    ["style: a saved style is used from the start"] = function(t)
        local _, c, a, d = start({ saved = { layout = { arrowStyle = "flat", arrowModern = true } } })
        if not has(t, a) then return end
        d.commands.arrow("demo")
        c.advance(0.1, 2)
        t.eq(a.style(), "flat")
        t.ok(type(c.arrows[1].shaped) == "table", "lines")
    end,

    ["style: a client that draws no lines keeps the modern arrow, and says so"] = function(t)
        local k, c, a, d = start({ lines = false, saved = { layout = { arrowStyle = "flat", arrowModern = true } } })
        if not has(t, a) then return end
        d.commands.arrow("demo")
        c.advance(0.1, 2)
        local q = c.arrows[1]
        t.eq(a.style(), "modern", "what is drawn")
        t.eq(q.shaped, nil)
        t.ok(q.draws > 0, "pictures")
        t.eq(style(k), "flat", "the saved choice is not thrown away")
        d.commands.arrow("3d")
        t.ok(said(c, "this client cannot draw that style"), "said")
        t.eq(style(k), "flat", "and nothing is saved")
        t.eq(k.problems:count(), 0)
    end,

    -- Row 10
    ["style: the list for a menu, in order, with the one in use ticked"] = function(t)
        local _, _, a, d = start()
        if not has(t, a) then return end
        t.eq(a.styles(), {
            { key = "modern", label = "Modern", on = true },
            { key = "3d", label = "3D (pillars)", on = false },
            { key = "flat", label = "Flat lines", on = false },
        })
        d.commands.arrow("flat")
        t.eq(a.styles()[3].on, true)
        t.eq(a.styles()[1].on, false)
        t.eq({ a.setStyle("3d") }, { true })
        t.eq(a.style(), "3d")
        local ok, reason = a.setStyle("round")
        t.eq(ok, false)
        t.ok(type(reason) == "string" and reason ~= "", "with a reason")
        t.eq(a.style(), "3d")
    end,

    -- Row 11
    ["migration: a saved 3d from before the modern arrow becomes modern, once"] = function(t)
        local k, _, a, d = start({ saved = { layout = { arrowStyle = "3d" } } })
        if not has(t, a) then return end
        t.eq(a.style(), "modern")
        t.eq(style(k), nil, "the old choice is cleared")
        t.eq(k.store:get("account", "layout.arrowModern"), true, "marked")
        d.commands.arrow("3d")
        t.eq(style(k), "3d", "choosing it afterwards holds")
        t.eq(k.problems:count(), 0)
    end,

    ["migration: with the mark set a saved 3d stays; flat is never moved"] = function(t)
        local k, _, a = start({ saved = { layout = { arrowStyle = "3d", arrowModern = true } } })
        if not has(t, a) then return end
        t.eq(a.style(), "3d")
        t.eq(style(k), "3d")
        local k2, _, a2 = start({ saved = { layout = { arrowStyle = "flat" } } })
        t.eq(a2.style(), "flat")
        t.eq(k2.store:get("account", "layout.arrowModern"), true)
    end,

    ["style: on a kernel that never starts the arrows, the answers are safe"] = function(t)
        local c = ns.make.fakeClient()
        local k = ns.Kernel({}, c)
        local a = A.Declare(k, ns.Diag.Start(k))
        if not has(t, a) then return end
        t.eq(a.style(), "modern")
        t.eq(#a.styles(), 3)
        t.eq((a.setStyle("flat")), false)
    end,
}
