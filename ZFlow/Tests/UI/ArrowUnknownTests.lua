-- Owner decisions D2 and D10 on the frames, over the fake client.
-- D2: with the direction unknown the arrow art is not drawn; the faded
-- frame and its "direction unknown" line stay. A profession needle that is
-- "off" still shows its text on its own frame, with no needle drawn: stacked,
-- that frame is on the quest arrow and the lines stand on the other side of
-- it from the quest lines (lead section 341).
-- D10: a trainer on another map is a line of text, with no needle and no
-- distance. No game client is involved. Not seen in game.
local _, ns = ...

local A, N = ns.Arrow, ns.Nav

local OTHER_MAP = "Mining trainer \226\128\148 other map"

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    local saved = opts.saved or {}
    if type(saved.layout) ~= "table" then saved.layout = {} end
    if saved.layout.arrowIntroSeen == nil then saved.layout.arrowIntroSeen = true end
    c.setSaved(ns.id.accountDB, saved)
    c.setScreen(1024, 768)
    c.setZone(1, 1411)
    if opts.facing ~= false then c.setFacing(opts.facing or 0) end
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    local k = ns.Kernel({}, c)
    -- The profession step is its own module behind nav.profArrow (N25).
    N.ProfStepDeclare(k)
    local d = ns.Diag.Start(k)
    local a = A.Start(k, d)
    k:Boot()
    if opts.before then opts.before(c) end
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, a, d
end

local QUEST = { place = { cont = 1, map = 1411, x = 0.5, y = 0.3 }, label = "Kill boars" }
local PROF = { place = { cont = 1, map = 1411, x = 0.8, y = 0.5 }, label = "Copper vein", on = true }
-- A step with nowhere to turn to: text only.
local TEXT = { label = "Vein on another map", still = true }

-- A character with Mining at its cap and one saved trainer. Made-up rows.
local function capped(trainerMap, waypoint)
    local _, c, a = start({
        saved = { learned = { places = { npcs = {
            ["Test Trainer"] = { map = trainerMap, x = 0.8, y = 0.5, trains = { Mining = true },
                                 factions = { Horde = true }, seen = 10 },
        } } } },
        -- Before the login, as the game has it: the saved character is there.
        before = function(c)
            c.setSaved(ns.id.charDB, { learned = { facts = { profSkill = {
                Mining = { skill = 75, max = 75 },
            } } } })
            c.setFaction("Horde")
            if waypoint then c.setWaypoint(1411, 0.5, 0.3) end
        end,
    })
    a.relayout()
    return c, a
end

return {
    ["unknown direction: the quest arrow keeps its faded frame and its line, the art is not drawn"] = function(t)
        local k, c, a = start({ facing = false })
        a.setGuide(function() return { quest = QUEST } end)
        local q = c.arrows[1]
        t.eq(q.shown, true, "the frame stays")
        t.eq(q.lines, { "Kill boars", "100 yd N", A.UNKNOWN_TURN })
        t.eq(q.faded, a.state().view.quest.alpha * A.LOST_ALPHA, "faded")
        c.advance(0.1, 2)
        t.ok(type(q.drawn) == "table", "a frame was drawn")
        if type(q.drawn) ~= "table" then return end
        t.eq({ q.drawn.body, q.drawn.shine, q.drawn.shadow }, { 0, 0, 0 }, "no arrow to mislead")
        t.eq(q.drawn.arrived, false, "and no ring")
        t.eq(k.problems:count(), 0)
    end,

    ["unknown direction: known again, the art is drawn again"] = function(t)
        local _, c, a = start({ facing = false })
        a.setGuide(function() return { quest = QUEST } end)
        local q = c.arrows[1]
        c.advance(0.1, 2)
        c.setFacing(0)
        a.relayout()
        c.advance(0.1, 2)
        t.eq(q.lines, { "Kill boars", "100 yd N" })
        t.eq(q.faded, a.state().view.quest.alpha)
        t.eq(q.drawn.body, 1)
        t.ok(q.drawn.shine > 0 and q.drawn.shadow > 0)
    end,

    ["unknown direction: a step that is still is text only, not faded"] = function(t)
        local _, c, a = start()
        a.setGuide(function() return { quest = TEXT } end)
        local q = c.arrows[1]
        t.eq(q.shown, true)
        t.eq(q.lines, { "Vein on another map" })
        t.eq(q.faded, a.state().view.quest.alpha, "nothing is unknown: not faded")
    end,

    ["unknown direction: the arrived ring is drawn as before"] = function(t)
        local _, c, a = start({ facing = false })
        c.setPosition(1411, 0.5, 0.3)
        a.setGuide(function() return { quest = QUEST } end)
        local q = c.arrows[1]
        c.advance(3, 30)
        t.eq(a.state().view.quest.mode, "ring")
        t.eq(q.drawn.arrived, true, "the ring points nowhere: it is not hidden")
        t.eq(q.faded, a.state().view.quest.alpha)
    end,

    ["needle off, stacked: its text stands opposite the quest lines, no needle is drawn"] = function(t)
        local _, c, a = start({ facing = false })
        a.setGuide(function() return { quest = QUEST, prof = PROF } end)
        local q, p = c.arrows[1], c.arrows[2]
        t.eq(a.state().view.prof.mode, "off", "no facing: the needle cannot point")
        t.eq(p.shown, true, "its frame is there for its lines (section 341)")
        t.eq(q.lines, { "Kill boars", "100 yd N", A.UNKNOWN_TURN })
        t.eq(p.lines, { "Copper vein", "300 yd E", A.UNKNOWN_TURN },
            "its lines are there; the unknown line is said once on each frame")
        c.advance(0.1, 2)
        t.eq(type(p.drawn) == "table" and p.drawn.body, 0, "no needle")
    end,

    ["needle off, stacked, by a step that is text only: the text stands opposite the quest lines"] = function(t)
        local _, c, a = start()
        a.setGuide(function() return { quest = QUEST, prof = TEXT } end)
        local q, p = c.arrows[1], c.arrows[2]
        t.eq(a.state().view.prof.mode, "off")
        t.eq(p.shown, true)
        t.eq(q.lines, { "Kill boars", "100 yd N" })
        t.eq(p.lines, { "Vein on another map" })
        t.eq(q.faded, a.state().view.quest.alpha, "the quest arrow knows its way: not faded")
        c.advance(0.1, 2)
        t.eq(q.drawn.body, 1, "and is drawn")
    end,

    ["needle off, no quest step: its own frame shows the text and no arrow"] = function(t)
        local _, c, a = start()
        a.setGuide(function() return { prof = TEXT } end)
        local q, p = c.arrows[1], c.arrows[2]
        t.eq(q.shown, false)
        t.eq(p.shown, true, "the frame is up for its text")
        t.eq(p.lines, { "Vein on another map" })
        t.eq(p.faded, a.state().view.prof.alpha, "a still step is not faded")
        c.advance(0.1, 2)
        t.ok(type(p.drawn) == "table", "a frame was drawn")
        if type(p.drawn) ~= "table" then return end
        t.eq({ p.drawn.body, p.drawn.shine, p.drawn.shadow }, { 0, 0, 0 }, "no needle")
    end,

    ["needle off, no quest step, direction unknown: faded, said, no arrow"] = function(t)
        local _, c, a = start({ facing = false })
        a.setGuide(function() return { prof = PROF } end)
        local p = c.arrows[2]
        t.eq(p.shown, true)
        t.eq(p.lines, { "Copper vein", "300 yd E", A.UNKNOWN_TURN })
        t.eq(p.faded, a.state().view.prof.alpha * A.LOST_ALPHA)
        c.advance(0.1, 2)
        t.eq(p.drawn.body, 0)
    end,

    ["needle off, separate: its own frame keeps the text where the needle stands"] = function(t)
        local _, c, a = start({ facing = false,
            saved = { layout = { arrows = { mode = "separate" } } } })
        a.setGuide(function() return { quest = QUEST, prof = PROF } end)
        local q, p = c.arrows[1], c.arrows[2]
        t.eq(q.lines, { "Kill boars", "100 yd N", A.UNKNOWN_TURN })
        t.eq(p.shown, true)
        t.eq(p.lines, { "Copper vein", "300 yd E", A.UNKNOWN_TURN })
        t.eq(p.point, a.state().view.prof.point)
        c.advance(0.1, 2)
        t.eq(p.drawn.body, 0)
    end,

    ["needle off with nothing to say: no empty frame"] = function(t)
        local _, c, a = start()
        a.setGuide(function() return { prof = { still = true } } end)
        t.eq(c.arrows[2].shown, false)
        t.eq(c.arrows[1].shown, false)
    end,

    ["needle off: hidden by the player, its text is not shown"] = function(t)
        local _, c, a = start({ facing = false,
            saved = { layout = { arrows = { hidden = { prof = true } } } } })
        a.setGuide(function() return { quest = QUEST, prof = PROF } end)
        t.eq(c.arrows[1].lines, { "Kill boars", "100 yd N", A.UNKNOWN_TURN })
        t.eq(c.arrows[2].shown, false)
    end,

    ["needle pointing: nothing changes"] = function(t)
        local _, c, a = start()
        a.setGuide(function() return { quest = QUEST, prof = PROF } end)
        local q, p = c.arrows[1], c.arrows[2]
        t.eq(p.shown, true)
        t.eq(q.lines, { "Kill boars", "100 yd N" })
        t.eq(p.lines, { "Copper vein", "300 yd E" })
        c.advance(0.1, 2)
        t.eq(p.drawn.body, 1)
        t.eq(q.drawn.body, 1)
    end,

    ["trainer on another map (D10): with a waypoint, one line opposite the quest lines, no needle, no distance"] = function(t)
        local c, a = capped(1412, true)
        local q, p = c.arrows[1], c.arrows[2]
        t.eq(a.state().view.prof.mode, "off")
        t.eq(p.shown, true, "the frame for the line (section 341)")
        t.eq(q.lines, { N.WAYPOINT_LABEL, "100 yd N" })
        t.eq(p.lines, { OTHER_MAP })
        t.eq(q.faded, a.state().view.quest.alpha)
    end,

    ["trainer on another map (D10): alone, a frame with the one line and no arrow"] = function(t)
        local c, a = capped(1412, false)
        local q, p = c.arrows[1], c.arrows[2]
        t.eq(q.shown, false)
        t.eq(p.shown, true)
        t.eq(p.lines, { OTHER_MAP })
        t.eq(p.faded, a.state().view.prof.alpha, "nothing is unknown: not faded")
        c.advance(0.1, 2)
        t.ok(type(p.drawn) == "table", "a frame was drawn")
        if type(p.drawn) ~= "table" then return end
        t.eq(p.drawn.body, 0, "no needle")
    end,

    ["trainer on another map (D10): the size of that map, once known, changes nothing"] = function(t)
        local c, a = capped(1412, true)
        c.setMapSize(1412, 800, 400)
        a.relayout()
        t.eq(c.arrows[1].lines, { N.WAYPOINT_LABEL, "100 yd N" })
        t.eq(c.arrows[2].lines, { OTHER_MAP }, "still no distance")
        t.eq(c.arrows[2].shown, true)
        t.eq(a.state().view.prof.mode, "off", "still no needle")
    end,

    ["trainer on this map: the needle and its distance as before"] = function(t)
        local c, a = capped(1411, true)
        local q, p = c.arrows[1], c.arrows[2]
        t.eq(p.shown, true)
        t.eq(q.lines, { N.WAYPOINT_LABEL, "100 yd N" })
        t.eq(p.lines, { "Mining trainer", "300 yd E" })
        t.ok(a.state().view.prof.mode ~= "off")
    end,
}
