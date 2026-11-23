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
    -- The profession step is its own module behind nav.profArrow (N25).
    N.ProfStepDeclare(k)
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

-- The wiring (G1, G2, PS1): what a character has saved about a profession
-- and its trainer, as Nav/ProfSeen.lua writes it. Made-up rows, test only.
local function profStart(skill, max, visitedAtCap, trainerMap)
    local _, c, a = start({ saved = { learned = { places = { npcs = {
        ["Test Trainer"] = { map = trainerMap or 1411, x = 0.8, y = 0.5, trains = { Mining = true },
                             factions = { Horde = true }, seen = 10 },
    } } } } })
    c.setSaved(ns.id.charDB, { learned = { facts = { profSkill = {
        Mining = { skill = skill, max = max, visitedAtCap = visitedAtCap },
    } } } })
    c.setFaction("Horde")
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    c.setWaypoint(1411, 0.5, 0.3)
    return c, a
end

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
        t.eq(q.lines, { "Kill boars", "100 yd N", A.UNKNOWN_TURN })
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
        t.eq(q.lines, { "Kill boars", "100 yd N", "Copper vein", "300 yd E" })
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

    -- AF1
    ["a broken arrow stays hidden: a loading screen, the demo and a guide do not bring it back"] = function(t)
        local k, c, a, d = start()
        c.setPosition(1411, 0.5, 0.5)
        c.setMapSize(1411, 1000, 500)
        login(c)
        cmd(d, "demo")
        local q, p = c.arrows[1], c.arrows[2]
        q.draw = function() error("boom") end
        c.advance(0.1, 5)
        t.eq(k.problems:count(), 1)
        c.fire("PLAYER_ENTERING_WORLD")
        t.eq(q.shown, false, "after the next loading screen")
        t.eq(p.shown, false)
        cmd(d, "demo")
        t.eq(q.shown, false, "after the demo command")
        t.eq(p.shown, false)
        cmd(d, "demo")
        t.eq(q.shown, false, "after the demo command again")
        t.eq(p.shown, false)
        a.setGuide(function()
            return { quest = { place = { cont = 1, map = 1411, x = 0.5, y = 0.3 }, label = "Kill boars" } }
        end)
        a.relayout()
        c.advance(1, 10)
        t.eq(q.shown, false, "after a guide and more frames")
        t.eq(p.shown, false)
        t.eq(a.state().view, nil)
        t.eq(k.problems:count(), 1, "still the one problem")
    end,

    -- AR13
    ["the halo, beam and beam texcoords go to the client from Nav/ArrowMotion"] = function(t)
        local _, c = start()
        for i = 1, 2 do
            local spec = c.arrows[i].spec
            t.eq(spec.halo, { N.HALO_W, N.HALO_H, N.HALO_Y })
            t.eq(spec.beam, { N.BEAM_W, N.BEAM_H })
            t.eq(spec.beamUp, { N.BeamCoords(false) })
            t.eq(spec.beamDown, { N.BeamCoords(true) })
        end
    end,

    -- AF6
    ["at the step with facing unknown: the ring, no unknown-direction line and no fade"] = function(t)
        local _, c, a = start()
        c.setPosition(1411, 0.5, 0.5)
        c.setMapSize(1411, 1000, 500)
        c.setFacing(nil)
        login(c)
        a.setGuide(function()
            return { quest = { place = { cont = 1, map = 1411, x = 0.5, y = 0.5 }, label = "Kill boars" } }
        end)
        local q = c.arrows[1]
        t.eq(q.shown, true)
        t.eq(a.state().view.quest.mode, "ring")
        for i = 1, #(q.lines or {}) do
            t.ok(q.lines[i] ~= A.UNKNOWN_TURN, "a ring points nowhere: nothing to call unknown")
        end
        t.eq(q.faded, a.state().view.quest.alpha, "the view's own alpha, not the lost fade")
    end,

    ["Lines: the unknown-direction line is once per stack and never on a ring"] = function(t)
        local U = A.UNKNOWN_TURN
        local function view(qMode, pMode, to)
            return { quest = { shown = true, mode = qMode, text = { shown = true } },
                     prof = { shown = true, mode = pMode, text = { shown = true, to = to } } }
        end
        local function lines() return { quest = { "Q", U }, prof = { "P", U } } end
        local both = { quest = true, prof = true }
        local out = A.Lines(view("arrow", "arrow", "quest"), lines(), both)
        t.eq(out.quest, { "Q", U, "P" }, "one stack: said once")
        t.eq(out.prof, {})
        out = A.Lines(view("arrow", "arrow", "prof"), lines(), both)
        t.eq(out.quest, { "Q", U })
        t.eq(out.prof, { "P", U }, "two stacks: once each")
        out = A.Lines(view("ring", "arrow", "quest"), lines(), both)
        t.eq(out.quest, { "Q", "P", U }, "the ring's is left out, the needle's stays")
        out = A.Lines(view("arrow", "ring", "prof"), lines(), both)
        t.eq(out.prof, { "P" })
        out = A.Lines(view("ring", "ring", "quest"), lines(), both)
        t.eq(out.quest, { "Q", "P" })
        out = A.Lines(view("ring", "ring", "quest"), lines())
        t.eq(out.quest, { "Q", U, "P", U }, "lines not marked as the unknown line are a guide's own: kept")
        out = A.Lines(view("ring", "arrow", "quest"), lines(), { prof = true })
        t.eq(out.quest, { "Q", U, "P", U }, "only a marked arrow's last line is the unknown line")
    end,

    -- ACB6: the height the text needs is that of the lines kept.
    ["the text side is chosen from the lines that are shown, not from a dropped one (ACB6)"] = function(t)
        -- Arrow top at 728 of 768: two lines (28 + 4) fit above it, three (42 + 4) do not.
        local saved = { layout = { arrows = { points = { quest = { "TOP", "TOP", 0, -40 } } } } }
        local _, c, a = start({ saved = saved })
        c.setPosition(1411, 0.5, 0.5)
        c.setMapSize(1411, 1000, 500)
        c.setFacing(nil)
        login(c)
        a.setGuide(function()
            return { quest = { place = { cont = 1, map = 1411, x = 0.5, y = 0.5 }, label = "Kill boars" } }
        end)
        local q = c.arrows[1]
        t.eq(a.state().view.quest.mode, "ring")
        t.eq(#q.lines, 2, "the unknown-direction line is dropped on the ring")
        t.eq(a.state().view.quest.text.side, "above", "two lines fit above")
        t.eq(q.textPoint, { "BOTTOM", "TOP", 0, N.TEXT_GAP_ABOVE })

        -- Three lines shown: they do not fit, and that is still seen.
        a.setGuide(function()
            return { quest = { place = { cont = 1, map = 1411, x = 0.5, y = 0.5 }, lines = { "a", "b", "c" } } }
        end)
        t.eq(#q.lines, 3)
        t.eq(a.state().view.quest.text.side, "below")

        -- A height the step gives is the guide's: left alone.
        a.setGuide(function()
            return { quest = { place = { cont = 1, map = 1411, x = 0.5, y = 0.5 }, label = "Kill boars",
                               textHeight = 3 * A.LINE_HEIGHT } }
        end)
        t.eq(#q.lines, 2)
        t.eq(a.state().view.quest.text.side, "below", "the given height stands")
    end,

    ["Lines: the second answer is how many of each arrow's own lines are kept (ACB6)"] = function(t)
        local U = A.UNKNOWN_TURN
        local function view(qMode, pMode, to, qText, pText)
            return { quest = { shown = true, mode = qMode, text = { shown = qText ~= false } },
                     prof = { shown = true, mode = pMode, text = { shown = pText ~= false, to = to } } }
        end
        local function lines() return { quest = { "Q", U }, prof = { "P", U } } end
        local both = { quest = true, prof = true }
        local _, kept = A.Lines(view("ring", "arrow", "quest"), lines(), both)
        t.eq(kept, { quest = 1, prof = 2 })
        _, kept = A.Lines(view("arrow", "arrow", "quest"), lines(), both)
        t.eq(kept, { quest = 2, prof = 1 }, "said once in the stack: the second is not counted")
        _, kept = A.Lines(view("arrow", "arrow", "prof"), lines(), both)
        t.eq(kept, { quest = 2, prof = 2 })
        _, kept = A.Lines(view("arrow", "arrow", "prof"), lines())
        t.eq(kept, { quest = 2, prof = 2 })
        _, kept = A.Lines(view("ring", "ring", "prof", false, true), lines(), both)
        t.eq(kept, { prof = 1 }, "text not shown: no count")
    end,

    ["wiring G1: a capped profession adds the trainer needle and the waypoint stays the quest arrow"] = function(t)
        local c, a = profStart(75, 75)
        login(c)
        a.relayout()
        local q, p = c.arrows[1], c.arrows[2]
        t.eq(q.shown, true, "the waypoint is still the quest arrow")
        t.eq(p.shown, true, "the profession needle is shown")
        t.eq(q.lines, { N.WAYPOINT_LABEL, "100 yd N", "Mining trainer", "300 yd E" })
        t.ok(a.state().view.prof.mode ~= "off")
        c.setWaypoint(nil)
        a.relayout()
        t.eq(q.shown, false, "no waypoint: no quest arrow")
        t.eq(p.shown, true, "the needle does not need a waypoint")
        a.setGuide(function() return { quest = { place = { cont = 1, map = 1411, x = 0.5, y = 0.3 }, label = "Own" } } end)
        t.eq(q.lines, { "Own", "100 yd N" }, "a guide that was set is taken whole: nothing is added to it")
        t.eq(p.shown, false)
    end,

    ["wiring G2: with no profession step the needle is off and the quest arrow is unchanged"] = function(t)
        local plain = select(2, start())
        plain.setPosition(1411, 0.5, 0.5)
        plain.setMapSize(1411, 1000, 500)
        plain.setWaypoint(1411, 0.5, 0.3)
        login(plain)
        local want = plain.arrows[1]
        t.eq(want.lines, { N.WAYPOINT_LABEL, "100 yd N" })
        for name, given in pairs({ ["not capped"] = { 50, 75 }, ["visited"] = { 75, 75, 75 } }) do
            local c, a = profStart(given[1], given[2], given[3])
            login(c)
            a.relayout()
            local q, p = c.arrows[1], c.arrows[2]
            t.eq(a.state().view.prof.mode, "off", name)
            t.eq(p.shown, false, name)
            t.eq(q.shown, true, name)
            t.eq(q.lines, want.lines, name)
            t.eq(q.point, want.point, name)
            t.eq(q.faded, want.faded, name)
            t.eq(q.scaled, want.scaled, name)
            t.eq(q.textPoint, want.textPoint, name)
        end
    end,

    -- Was PS1 (the other map's size is asked for). Owner decision D10: a
    -- trainer on another map is text only, so no distance is worked out and
    -- that size is not needed.
    ["wiring D10: a trainer on another map is one line of text, with no distance"] = function(t)
        local c, a = profStart(75, 75, nil, 1412)
        c.setMapSize(1412, 800, 400)
        login(c)
        a.relayout()
        local q, p = c.arrows[1], c.arrows[2]
        t.eq(q.lines, { N.WAYPOINT_LABEL, "100 yd N", "Mining trainer \226\128\148 other map" })
        t.eq(p.shown, false, "no needle")
    end,
}
