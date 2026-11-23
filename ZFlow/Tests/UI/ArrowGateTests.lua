-- The guide arrows' gate over the fake client: a dead player gets the corpse
-- arrow, pointed at the corpse where the client says where it is. No game
-- client is involved.
local _, ns = ...

local A, N = ns.Arrow, ns.Nav

-- The player in the middle of map 1411 (1000 by 500 yards), facing north,
-- with a quest step 100 yards north and a vein 300 yards east.
local function start()
    local c = ns.make.fakeClient()
    -- An install that has seen the intro (Tests/UI/ArrowIntroTests.lua has
    -- the intro itself).
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setScreen(1024, 768)
    c.setZone(1, 1411)
    c.setFacing(0)
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    local a = A.Start(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return c, a
end

local function steps()
    return {
        quest = { place = { cont = 1, map = 1411, x = 0.5, y = 0.3 }, label = "Kill boars" },
        prof = { place = { cont = 1, map = 1411, x = 0.8, y = 0.5 }, label = "Copper vein", on = true },
    }
end

local function source(c, guide)
    return A.GuideSource(c, {}, guide or steps())
end

local function near(t, got, want, msg)
    t.ok(type(got) == "number" and math.abs(got - want) < 1e-6, msg .. " (got " .. tostring(got) .. ")")
end

return {
    ["alive, or not known to be dead: the gate is open and the quest is the target"] = function(t)
        local c = start()
        local src = source(c)
        t.eq(src.view.gate, "open", "the client does not say")
        t.eq(src.lines.quest, { "Kill boars", "100 yd N" })
        c.setDead(false)
        src = source(c)
        t.eq(src.view.gate, "open")
        t.eq(src.lines.quest, { "Kill boars", "100 yd N" })
        c.setCorpse(1411, 0.3, 0.5)
        t.eq(source(c).lines.quest, { "Kill boars", "100 yd N" }, "a corpse place is not used while alive")
    end,

    ["dead: the gate is corpse and the quest arrow points at the corpse"] = function(t)
        local c = start()
        c.setDead(true)
        c.setCorpse(1411, 0.3, 0.5)            -- 200 yards west
        local src = source(c)
        t.eq(src.view.gate, "corpse")
        near(t, src.view.quest.distance, 200, "distance to the corpse")
        near(t, src.turns.quest, math.pi / 2, "the corpse is west: a quarter turn anticlockwise")
        t.eq(src.lines.quest, { "Corpse", "200 yd W" })
        t.eq(src.view.quest.target, { cont = 1, zone = 1411 })
    end,

    ["dead: the same gate N.ArrowGate gives"] = function(t)
        local c = start()
        c.setDead(true)
        t.eq(source(c).view.gate, N.ArrowGate(true, true, false, true, true))
        c.setPosition(nil)
        t.eq(source(c).view.gate, N.ArrowGate(true, true, false, false, true), "no position: shut")
    end,

    ["dead, corpse place unknown: corpse gate, no distance, no turn, not the quest"] = function(t)
        local c = start()
        c.setDead(true)
        local src = source(c)
        t.eq(src.view.gate, "corpse")
        t.eq(src.view.quest.distance, nil)
        t.eq(src.turns.quest, nil)
        t.eq(src.lines.quest, { "Corpse", ns.Arrow.UNKNOWN_TURN })
    end,

    ["dead: a corpse on a map with no size has no distance"] = function(t)
        local c = start()
        c.setDead(true)
        c.setCorpse(1412, 0.3, 0.5)
        local src = source(c)
        t.eq(src.view.gate, "corpse")
        t.eq(src.view.quest.distance, nil)
        t.eq(src.turns.quest, nil)
        t.eq(src.lines.quest, { "Corpse", ns.Arrow.UNKNOWN_TURN })
    end,

    ["dead: a corpse place that is not a place is unknown"] = function(t)
        local c = start()
        c.setDead(true)
        c.corpse = function() return { map = 1411, x = "left", y = 0.5 } end
        t.eq(source(c).lines.quest, { "Corpse", ns.Arrow.UNKNOWN_TURN })
        c.corpse = function() error("the client refused") end
        local src = source(c)
        t.eq(src.view.gate, "corpse")
        t.eq(src.lines.quest, { "Corpse", ns.Arrow.UNKNOWN_TURN })
    end,

    ["a client without the two reads, or whose dead read fails: open"] = function(t)
        local c = start()
        c.dead, c.corpse = nil, nil
        t.eq(source(c).view.gate, "open")
        c.dead = function() error("the client refused") end
        t.eq(source(c).view.gate, "open")
        c.dead = function() return "yes" end
        t.eq(source(c).view.gate, "open", "only a plain true is dead")
    end,

    ["the guide's own gate wins, and only a corpse gate retargets"] = function(t)
        local c = start()
        c.setDead(true)
        c.setCorpse(1411, 0.3, 0.5)
        local guide = steps()
        guide.view = { gate = "open" }
        local src = source(c, guide)
        t.eq(src.view.gate, "open")
        t.eq(src.lines.quest, { "Kill boars", "100 yd N" })
        c.setDead(false)
        guide.view = { gate = "corpse" }
        src = source(c, guide)
        t.eq(src.view.gate, "corpse")
        t.eq(src.lines.quest, { "Corpse", "200 yd W" })
    end,

    ["dead: the profession step and the guide handed in are left alone"] = function(t)
        local c = start()
        c.setDead(true)
        c.setCorpse(1411, 0.3, 0.5)
        local guide = steps()
        local src = source(c, guide)
        t.eq(src.lines.prof, { "Copper vein", "300 yd E" })
        t.eq(guide, steps())
    end,

    ["dead, on the frames: the quest arrow is shown in corpse mode and corpse red"] = function(t)
        local c, a = start()
        c.setDead(true)
        c.setCorpse(1411, 0.3, 0.5)
        local guide = steps()
        a.setGuide(function() return guide end)
        local q = c.arrows[1]
        t.eq(q.shown, true)
        t.eq(q.lines[1], "Corpse")
        t.eq(q.lines[2], "200 yd W")
        local view = a.state().view
        t.eq(view.quest.mode, "corpse")
        t.eq(view.quest.colour, { N.CORPSE_RED[1], N.CORPSE_RED[2], N.CORPSE_RED[3] })
        c.setDead(false)
        a.relayout()
        t.eq(q.lines[1], "Kill boars")
        t.eq(a.state().view.quest.mode, "arrow")
    end,

    ["dead with no quest step: the corpse arrow is still shown"] = function(t)
        local c, a = start()
        c.setDead(true)
        c.setCorpse(1411, 0.3, 0.5)
        a.setGuide(function() return {} end)
        t.eq(c.arrows[1].shown, true)
        t.eq(c.arrows[1].lines[1], "Corpse")
        t.eq(c.arrows[1].lines[2], "200 yd W")
    end,
    -- ------------------------------------------------- dead, ghost, elsewhere
    ["the two authored lines"] = function(t)
        t.ok(type(A.RELEASE_LABEL) == "string" and A.RELEASE_LABEL ~= "", "a release label")
        t.eq(A.CORPSE_ELSEWHERE, "corpse is on another map")
    end,

    ["dead, not a ghost: no place, and the one line is the release label"] = function(t)
        local c = start()
        c.setDead(true)
        c.setGhost(false)
        local src = source(c)
        t.eq(src.view.gate, "corpse")
        t.eq(src.view.quest.distance, nil)
        t.eq(src.turns.quest, nil)
        t.eq(src.lines.quest, { A.RELEASE_LABEL })
    end,

    ["dead, not a ghost: a corpse place the client gives is not pointed at"] = function(t)
        local c = start()
        c.setDead(true)
        c.setGhost(false)
        c.setCorpse(1411, 0.3, 0.5)
        local src = source(c)
        t.eq(src.view.quest.distance, nil)
        t.eq(src.turns.quest, nil)
        t.eq(src.lines.quest, { A.RELEASE_LABEL })
    end,

    ["a ghost on the corpse's map: pointed at the corpse"] = function(t)
        local c = start()
        c.setDead(true)
        c.setGhost(true)
        c.setCorpse(1411, 0.3, 0.5)
        local src = source(c)
        t.eq(src.view.gate, "corpse")
        near(t, src.view.quest.distance, 200, "distance to the corpse")
        near(t, src.turns.quest, math.pi / 2, "the corpse is west")
        t.eq(src.lines.quest, { "Corpse", "200 yd W" })
    end,

    ["a ghost, the corpse not on this map: the label and the other-map line"] = function(t)
        local c = start()
        c.setDead(true)
        c.setGhost(true)
        c.setCorpse(false)          -- the client answered: on no position of this map
        local src = source(c)
        t.eq(src.view.gate, "corpse")
        t.eq(src.view.quest.distance, nil)
        t.eq(src.turns.quest, nil)
        t.eq(src.lines.quest, { "Corpse", A.CORPSE_ELSEWHERE })
        t.eq(src.still.quest, true, "nowhere to turn to")
    end,

    ["a ghost: a corpse read that fails, is absent or is no place is unknown, not elsewhere"] = function(t)
        local c = start()
        c.setDead(true)
        c.setGhost(true)
        c.corpse = function() error("the client refused") end
        t.eq(source(c).lines.quest, { "Corpse", A.UNKNOWN_TURN })
        c.corpse = nil
        t.eq(source(c).lines.quest, { "Corpse", A.UNKNOWN_TURN })
        c.corpse = function() return { map = 1411, x = "left", y = 0.5 } end
        t.eq(source(c).lines.quest, { "Corpse", A.UNKNOWN_TURN })
    end,

    ["ghost unknown: as before, nothing guessed"] = function(t)
        local c = start()
        c.setDead(true)
        t.eq(source(c).lines.quest, { "Corpse", A.UNKNOWN_TURN }, "no corpse place")
        c.setCorpse(1411, 0.3, 0.5)
        t.eq(source(c).lines.quest, { "Corpse", "200 yd W" }, "a corpse place")
        c.ghost = function() error("the client refused") end
        t.eq(source(c).lines.quest, { "Corpse", "200 yd W" }, "the ghost read fails")
        c.ghost = function() return 1 end
        t.eq(source(c).lines.quest, { "Corpse", "200 yd W" }, "only a plain true or false counts here")
        c.ghost = nil
        t.eq(source(c).lines.quest, { "Corpse", "200 yd W" }, "no ghost read")
    end,

    ["alive: a ghost read of false or unknown changes nothing"] = function(t)
        local c = start()
        c.setDead(false)
        c.setGhost(false)
        local src = source(c)
        t.eq(src.view.gate, "open")
        t.eq(src.lines.quest, { "Kill boars", "100 yd N" })
        c.setGhost(nil)
        t.eq(source(c).view.gate, "open")
        c.ghost = function() return 1 end
        t.eq(source(c).view.gate, "open", "only a plain true counts")
    end,

    ["a plain true from either read opens the corpse gate (C3)"] = function(t)
        local c = start()
        c.setGhost(true)                    -- dead: unknown
        c.setCorpse(1411, 0.3, 0.5)
        local src = source(c)
        t.eq(src.view.gate, "corpse", "dead unknown, ghost true")
        t.eq(src.lines.quest, { "Corpse", "200 yd W" })
        c.dead = function() error("the client refused") end
        t.eq(source(c).view.gate, "corpse", "the dead read fails, ghost true")
        c.dead = nil
        t.eq(source(c).view.gate, "corpse", "no dead read, ghost true")
        c = start()
        c.setDead(false)
        c.setGhost(true)
        t.eq(source(c).view.gate, "corpse", "dead false, ghost true")
        c = start()
        c.setDead(true)
        t.eq(source(c).view.gate, "corpse", "dead true, ghost unknown")
        c = start()
        t.eq(source(c).view.gate, "open", "neither known")
    end,

    ["a ghost, cannot tell where the corpse is: Corpse and direction unknown, not still (C1)"] = function(t)
        local c = start()
        c.setDead(true)
        c.setGhost(true)                    -- the corpse read answers nil
        local src = source(c)
        t.eq(src.lines.quest, { "Corpse", A.UNKNOWN_TURN })
        t.eq(src.still.quest, nil)
        t.eq(src.lost.quest, true)
    end,

    -- H1 changes C1's rule here: with the ghost read unknown, a corpse read
    -- of false is no longer shown as another map.
    ["ghost unknown: no position on this map is direction unknown, not another map (H1)"] = function(t)
        local c = start()
        c.setDead(true)
        c.setCorpse(false)
        local src = source(c)
        t.eq(src.lines.quest, { "Corpse", A.UNKNOWN_TURN }, "the body may lie at the player's feet")
        t.eq(src.still.quest, nil, "not still")
        t.eq(src.lost.quest, true)
        t.eq(src.view.quest.distance, nil)
        local unknown = { function() error("the client refused") end, function() return 1 end,
                          function() return nil end, function() return "yes" end }
        for i = 1, #unknown do
            c.ghost = unknown[i]
            t.eq(source(c).lines.quest, { "Corpse", A.UNKNOWN_TURN }, "ghost read " .. i)
        end
        c.ghost = nil
        t.eq(source(c).lines.quest, { "Corpse", A.UNKNOWN_TURN }, "no ghost read")
    end,

    ["the other-map line needs a plain true from the ghost read (H1)"] = function(t)
        local c = start()
        c.setDead(true)
        c.setCorpse(false)
        c.setGhost(true)
        local src = source(c)
        t.eq(src.lines.quest, { "Corpse", A.CORPSE_ELSEWHERE })
        t.eq(src.still.quest, true)
        c.setGhost(false)
        t.eq(source(c).lines.quest, { A.RELEASE_LABEL }, "not released: the release label still wins")
        c.setGhost(nil)
        t.eq(source(c).lines.quest, { "Corpse", A.UNKNOWN_TURN }, "unknown again")
    end,

    ["on the frames: ghost unknown and no position on this map is faded, with the line (H1)"] = function(t)
        local c, a = start()
        c.setDead(true)
        c.setCorpse(false)
        a.setGuide(function() return steps() end)
        local q = c.arrows[1]
        t.eq(q.lines, { "Corpse", A.UNKNOWN_TURN })
        t.eq(q.faded, a.state().view.quest.alpha * A.LOST_ALPHA, "direction unknown: faded")
        c.setGhost(true)
        a.relayout()
        t.eq(q.lines, { "Corpse", A.CORPSE_ELSEWHERE })
        t.eq(q.faded, a.state().view.quest.alpha, "a ghost, another map: the view's own alpha")
    end,

    -- H2: still is for a step with nowhere to go. A step with a place has a
    -- direction, and when that is unknown it is said.
    ["still on a step with a place silences nothing (H2)"] = function(t)
        local c = start()
        c.setFacing(nil)
        local guide = steps()
        guide.quest.still = true
        local src = source(c, guide)
        t.eq(src.turns.quest, nil, "no facing: no turn")
        t.eq(src.lines.quest, { "Kill boars", "100 yd N", A.UNKNOWN_TURN })
        t.eq(src.lost.quest, true)
        t.eq(src.still.quest, nil, "a step with a place is not still")
        guide.quest.place = nil
        src = source(c, guide)
        t.eq(src.lines.quest, { "Kill boars" }, "no place: still, as before")
        t.eq(src.still.quest, true)
        t.eq(src.lost.quest, nil)
    end,

    ["on the frames: a still step with a place and no facing is faded (H2)"] = function(t)
        local c, a = start()
        c.setFacing(nil)
        c.setPosition(1411, 0.5, 0.9)       -- far from the step: not the ring
        local guide = steps()
        guide.quest.still = true
        a.setGuide(function() return guide end)
        local q = c.arrows[1]
        t.ok(a.state().view.quest.mode ~= "ring", "an arrow, not the ring")
        -- Third: the last of its own lines (the needle's are on its own frame).
        t.eq(q.lines[3], A.UNKNOWN_TURN)
        t.eq(q.faded, a.state().view.quest.alpha * A.LOST_ALPHA)
    end,

    ["on the frames: a still step is not faded; an unknown direction is (C2)"] = function(t)
        local c, a = start()
        c.setDead(true)
        c.setGhost(false)
        a.setGuide(function() return steps() end)
        local q = c.arrows[1]
        t.eq(q.lines, { A.RELEASE_LABEL })
        t.eq(q.faded, a.state().view.quest.alpha, "release: the view's own alpha")
        c.setGhost(true)
        c.setCorpse(false)
        a.relayout()
        t.eq(q.lines, { "Corpse", A.CORPSE_ELSEWHERE })
        t.eq(q.faded, a.state().view.quest.alpha, "another map: the view's own alpha")
        c.setCorpse(nil)
        a.relayout()
        t.eq(q.lines, { "Corpse", A.UNKNOWN_TURN })
        t.eq(q.faded, a.state().view.quest.alpha * A.LOST_ALPHA, "direction unknown: faded")
    end,

    ["dead, not a ghost, on the frames: shown with the release label, then the corpse once a ghost"] = function(t)
        local c, a = start()
        c.setDead(true)
        c.setGhost(false)
        c.setCorpse(1411, 0.3, 0.5)
        a.setGuide(function() return steps() end)
        local q = c.arrows[1]
        t.eq(q.shown, true)
        t.eq(q.lines, { A.RELEASE_LABEL })
        t.eq(a.state().view.quest.mode, "corpse")
        c.setGhost(true)
        a.relayout()
        t.eq(q.lines, { "Corpse", "200 yd W" })
    end,

    ["dead: a corpse answer whose map is not a number is no place (IT4)"] = function(t)
        local c = start()
        c.setDead(true)
        c.setGhost(true)
        c.corpse = function() return { map = 1411, x = 0.5, y = 0.3 } end
        local src = source(c)
        t.ok(type(src.view.quest.distance) == "number", "a numbered map: a place")
        local none = { "1411", true, {}, function() end }
        for i = 1, #none do
            c.corpse = function() return { map = none[i], x = 0.5, y = 0.3 } end
            src = source(c)
            t.eq(src.view.gate, "corpse")
            t.eq(src.lines.quest, { "Corpse", ns.Arrow.UNKNOWN_TURN }, "direction unknown: answer " .. i)
            t.eq(src.view.quest.distance, nil, "no distance: answer " .. i)
            t.eq(src.turns.quest, nil, "no turn: answer " .. i)
        end
    end,
}
