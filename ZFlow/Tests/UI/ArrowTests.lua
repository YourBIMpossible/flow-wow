-- The guide arrows over the fake client: hidden with nothing to point at,
-- the demo's stack and separation, drags and commands saved and restored,
-- and a client without frames. No game client is involved.
local _, ns = ...

local A, N = ns.Arrow, ns.Nav

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    -- An install that has seen the intro (Tests/UI/ArrowIntroTests.lua has
    -- the intro itself), so login shows only what each test sets up.
    local saved = opts.saved or {}
    if type(saved.layout) ~= "table" then saved.layout = {} end
    if saved.layout.arrowIntroSeen == nil then saved.layout.arrowIntroSeen = true end
    c.setSaved(ns.id.accountDB, saved)
    c.setScreen(1024, 768)
    c.setZone(1, 1411)
    if opts.facing ~= false then c.setFacing(opts.facing or 0) end
    if opts.noFrames then c.setFrames(false) end
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    local a = A.Start(k, d)
    k:Boot()
    return k, c, a, d
end

local function login(c)
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
end

local function cmd(d, text) d.commands.arrow(text) end

local function savedArrows(c)
    local layout = c.saved(ns.id.accountDB).layout
    return type(layout) == "table" and layout.arrows or nil
end

local function last(c) return c.printed[#c.printed] or "" end

return {
    ["two arrows are made, hidden, with the art path and sizes"] = function(t)
        local _, c, a = start()
        t.eq(#c.arrows, 2)
        local q, p = c.arrows[1], c.arrows[2]
        t.eq(q.spec.name, ns.id.framePrefix .. "QuestArrow")
        t.eq(p.spec.name, ns.id.framePrefix .. "ProfArrow")
        t.eq(q.spec.artPath, "Interface\\AddOns\\" .. ns.id.addon .. "\\Art\\")
        t.eq(q.spec.size, N.ARROW_SIZE)
        t.eq(p.spec.needle, { N.NEEDLE_W, N.NEEDLE_H })
        t.eq(q.shown, false)
        t.eq(a.handles.quest, q)
        login(c)
        c.advance(1, 10)
        t.eq(q.shown, false, "no arrow source yet: nothing to point at")
        t.eq(p.shown, false)
        t.eq(q.draws, 0)
        t.eq(c.savedExists(ns.id.accountDB) and savedArrows(c) or nil, nil, "nothing saved")
    end,

    ["demo: stacked, needle behind the quest arrow, one stack of text"] = function(t)
        local _, c, a, d = start()
        login(c)
        cmd(d, "demo")
        local q, p = c.arrows[1], c.arrows[2]
        t.eq(q.shown, true)
        t.eq(p.shown, true)
        t.eq(q.point, N.ARROW_DEFAULT_POINT)
        t.eq(p.attached, q, "stacked: the needle follows the quest arrow")
        t.eq(p.lookIs, "needle")
        t.eq(p.under, true)
        t.eq(q.under, false)
        t.eq(q.scaled, N.ON_NEEDLE_SCALE)
        t.eq(q.faded, N.ON_NEEDLE_ALPHA)
        t.eq(p.faded, N.PROF_HOLDER_ALPHA, "the needle stays the quieter arrow")
        t.eq(q.lines, { "Demo: north", "300 yd", "Demo: east" })
        t.eq(p.lines, {}, "its text is on the quest arrow")
        c.advance(0.5, 30)
        t.ok(q.draws > 0 and p.draws > 0, "both are drawn every frame")
        t.ok(a.state().demo)
    end,

    ["demo: the turn follows the real facing"] = function(t)
        local _, c, _, d = start({ facing = 0 })
        login(c)
        cmd(d, "demo")
        c.advance(3, 300)
        local q, p = c.arrows[1], c.arrows[2]
        t.ok(math.abs(q.drawn.turn - N.ArrowTurn(0, 0)) < 1e-3, "north while facing north")
        t.ok(math.abs(p.drawn.turn - N.ArrowTurn(math.pi / 2, 0)) < 1e-3)
        c.setFacing(1)
        c.advance(3, 300)
        t.ok(math.abs(q.drawn.turn - N.ArrowTurn(0, 1)) < 1e-3)
    end,

    ["demo: facing unknown is said and both arrows fade, so no direction reads as live"] = function(t)
        local _, c, _, d = start({ facing = false })
        login(c)
        cmd(d, "demo")
        local q, p = c.arrows[1], c.arrows[2]
        t.eq(q.lines[3], "facing unknown")
        t.eq(p.shown, false, "no facing: the needle has no bearing to show")
        t.eq(q.faded, 1 * A.LOST_ALPHA, "the quest arrow alone, faded")
        c.setFacing(0)
        c.advance(0.5, 5)
        t.eq(q.faded, N.ON_NEEDLE_ALPHA, "facing known again: full opacity back")
    end,

    ["a guide step with facing unknown: the line says so and the arrow fades"] = function(t)
        local _, c, a = start({ facing = false })
        c.setPosition(1411, 0.5, 0.5)
        c.setMapSize(1411, 1000, 500)
        login(c)
        a.setGuide(function()
            return { quest = { place = { cont = 1, map = 1411, x = 0.5, y = 0.3 }, label = "Kill boars" } }
        end)
        local q = c.arrows[1]
        t.eq(q.shown, true)
        t.eq(q.lines, { "Kill boars", "100 yd", A.UNKNOWN_TURN })
        t.eq(q.faded, 1 * A.LOST_ALPHA)
    end,

    ["an arrow being dragged is not re-placed until it is let go"] = function(t)
        local _, c, _, d = start()
        login(c)
        cmd(d, "demo")
        local q = c.arrows[1]
        q.held = true
        q.point = { "CENTER", "CENTER", 5, 5 }
        c.advance(1, 10)
        t.eq(q.point, { "CENTER", "CENTER", 5, 5 }, "held: left where the hand has it")
        q.held = false
        c.advance(1, 10)
        t.eq(q.point, N.ARROW_DEFAULT_POINT, "let go without a drop: back to its saved place")
    end,

    ["demo near: the quest arrow fades to its ring"] = function(t)
        local _, c, _, d = start()
        login(c)
        cmd(d, "demo")
        cmd(d, "near")
        c.advance(1, 20)
        local q = c.arrows[1]
        t.eq(q.drawn.arrived, true)
        t.eq(q.drawn.body, 0)
        t.eq(q.lines[2], "10 yd")
    end,

    ["separate: the needle has its own place, quest colours, still faint"] = function(t)
        local _, c, _, d = start()
        login(c)
        cmd(d, "demo")
        cmd(d, "separate")
        local q, p = c.arrows[1], c.arrows[2]
        t.eq(p.attached, nil)
        t.ok(p.point ~= nil, "placed on the screen")
        t.eq(p.under, false)
        t.eq(p.lookIs, "needle")
        t.eq(p.faded, N.PROF_HOLDER_ALPHA)
        t.eq(q.scaled, 1, "the quest arrow is full size once alone")
        t.eq(q.faded, 1, "and full opacity")
        t.eq(p.lines, { "Demo: east" }, "its own text")
        t.eq(savedArrows(c).mode, "separate")
        c.advance(3, 60)
        local qc, pc = q.drawn.colour, p.drawn.colour
        local r, g, b = N.ArrowColor("zone", N.ARROW_DEMO_PROF or A.DEMO.profDistance)
        t.ok(math.abs(pc[1] - r) + math.abs(pc[2] - g) + math.abs(pc[3] - b) < 0.02,
            "the needle takes the quest arrow's colour meanings")
        t.eq(#qc, 3)
    end,

    ["drag: saved, restored on the next start, restacked when dropped close"] = function(t)
        local _, c, _, d = start()
        login(c)
        cmd(d, "demo")
        c.arrows[1].drag({ "CENTER", "CENTER", 100, 50 })
        t.eq(savedArrows(c).points.quest, { "CENTER", "CENTER", 100, 50 })
        cmd(d, "separate")
        c.arrows[2].drag({ "CENTER", "CENTER", -200, -100 })
        local saved = c.saved(ns.id.accountDB)

        local _, c2, _, d2 = start({ saved = saved })
        login(c2)
        cmd(d2, "demo")
        t.eq(c2.arrows[1].point, { "CENTER", "CENTER", 100, 50 })
        t.eq(c2.arrows[2].point, { "CENTER", "CENTER", -200, -100 })
        c2.arrows[2].drag({ "CENTER", "CENTER", 110, 45 })
        t.eq(savedArrows(c2).mode, nil, "dropped on the quest arrow: stacked again")
        t.eq(c2.arrows[2].attached, c2.arrows[1])
    end,

    ["commands: stack, reset, hide and text"] = function(t)
        local _, c, _, d = start()
        login(c)
        cmd(d, "demo")
        cmd(d, "separate")
        cmd(d, "stack")
        t.eq(savedArrows(c).mode, nil, "stacked is the default mode")
        t.eq(c.arrows[2].attached, c.arrows[1])
        t.ok(savedArrows(c).points ~= nil, "the needle's own place is kept for the next separation")
        cmd(d, "hide prof")
        t.eq(c.arrows[2].shown, false)
        t.eq(savedArrows(c).hidden, { prof = true })
        cmd(d, "hide prof")
        t.eq(c.arrows[2].shown, true)
        cmd(d, "text quest")
        t.eq(c.arrows[1].lines, { "Demo: east" }, "the quest lines are off, the needle's stay")
        cmd(d, "text quest")
        c.arrows[1].drag({ "CENTER", "CENTER", 10, 10 })
        cmd(d, "reset")
        t.eq(savedArrows(c), nil)
        t.eq(c.arrows[1].point, N.ARROW_DEFAULT_POINT)
        cmd(d, "nonsense")
        t.ok(last(c):find("arrow demo", 1, true) ~= nil, "unknown words get the usage")
        cmd(d, "demo")
        t.eq(c.arrows[1].shown, false, "demo off: hidden again")
    end,

    ["before login and without frames: said, nothing done"] = function(t)
        local _, c, _, d = start()
        cmd(d, "demo")
        t.ok(last(c):find("not ready", 1, true) ~= nil)
        t.eq(c.arrows[1].shown, false)
        local _, c2, a2, d2 = start({ noFrames = true })
        t.eq(a2.handles, nil)
        login(c2)
        cmd(d2, "demo")
        t.ok(last(c2):find("cannot draw", 1, true) ~= nil)
    end,

    ["a guide's steps: shown where it says, label and yards, demo wins while on"] = function(t)
        local _, c, a, d = start()

        c.setPosition(1411, 0.5, 0.5)
        c.setMapSize(1411, 1000, 500)
        login(c)
        local steps = {
            quest = { place = { cont = 1, map = 1411, x = 0.5, y = 0.3 }, label = "Kill boars" },
            prof = { place = { cont = 1, map = 1411, x = 0.8, y = 0.5 }, label = "Copper vein", on = true },
        }
        a.setGuide(function() return steps end)
        local q, p = c.arrows[1], c.arrows[2]
        t.eq(q.shown, true)
        t.eq(p.shown, true)
        t.eq(q.lines, { "Kill boars", "100 yd", "Copper vein", "300 yd" })
        c.advance(3, 300)
        t.ok(math.abs(q.drawn.turn - N.ArrowTurn(0, 0)) < 1e-3, "the boars are north")
        cmd(d, "demo")
        t.eq(q.lines[1], "Demo: north")
        cmd(d, "demo")
        t.eq(q.lines[1], "Kill boars")
        steps.quest.lines = { "Own line" }
        a.relayout()
        t.eq(q.lines[1], "Own line")
        c.setPosition(nil)
        a.relayout()
        t.eq(q.shown, false, "the player's place unknown: the gate is shut")
        c.setPosition(1411, 0.5, 0.5)
        a.relayout()
        t.eq(q.shown, true, "the place known again: shown")
        a.setGuide(nil)
        t.eq(q.shown, false, "no guide: nothing to point at")
    end,

    ["a frame error is one problem, and the arrows stop drawing and hide"] = function(t)
        local k, c, a, d = start()
        login(c)
        cmd(d, "demo")
        local q = c.arrows[1]
        q.draw = function() error("boom") end
        c.advance(0.1, 5)
        t.eq(k.problems:count(), 1)
        local draws = c.arrows[2].draws
        c.advance(0.1, 5)
        t.eq(c.arrows[2].draws, draws, "stopped after the first error")
        t.eq(q.shown, false, "a broken arrow is taken off the screen")
        t.eq(c.arrows[2].shown, false)
        t.eq(a.state().view, nil)
    end,
}
