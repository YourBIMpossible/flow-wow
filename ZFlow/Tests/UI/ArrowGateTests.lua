-- The guide arrows' gate over the fake client: a dead player gets the corpse
-- arrow, pointed at the corpse where the client says where it is. No game
-- client is involved.
local _, ns = ...

local A, N = ns.Arrow, ns.Nav

-- The player in the middle of map 1411 (1000 by 500 yards), facing north,
-- with a quest step 100 yards north and a vein 300 yards east.
local function start()
    local c = ns.make.fakeClient()
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
        t.eq(src.lines.quest, { "Kill boars", "100 yd" })
        c.setDead(false)
        src = source(c)
        t.eq(src.view.gate, "open")
        t.eq(src.lines.quest, { "Kill boars", "100 yd" })
        c.setCorpse(1411, 0.3, 0.5)
        t.eq(source(c).lines.quest, { "Kill boars", "100 yd" }, "a corpse place is not used while alive")
    end,

    ["dead: the gate is corpse and the quest arrow points at the corpse"] = function(t)
        local c = start()
        c.setDead(true)
        c.setCorpse(1411, 0.3, 0.5)            -- 200 yards west
        local src = source(c)
        t.eq(src.view.gate, "corpse")
        near(t, src.view.quest.distance, 200, "distance to the corpse")
        near(t, src.turns.quest, math.pi / 2, "the corpse is west: a quarter turn anticlockwise")
        t.eq(src.lines.quest, { "Corpse", "200 yd" })
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
        t.eq(src.lines.quest, { "Kill boars", "100 yd" })
        c.setDead(false)
        guide.view = { gate = "corpse" }
        src = source(c, guide)
        t.eq(src.view.gate, "corpse")
        t.eq(src.lines.quest, { "Corpse", "200 yd" })
    end,

    ["dead: the profession step and the guide handed in are left alone"] = function(t)
        local c = start()
        c.setDead(true)
        c.setCorpse(1411, 0.3, 0.5)
        local guide = steps()
        local src = source(c, guide)
        t.eq(src.lines.prof, { "Copper vein", "300 yd" })
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
        t.eq(q.lines[2], "200 yd")
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
        t.eq(c.arrows[1].lines[2], "200 yd")
    end,
}
