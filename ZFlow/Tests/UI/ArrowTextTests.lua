-- The arrow's own words (G40), over the fake client: the compass word
-- beside the distance, and "you're here" in place of the distance inside
-- the arrival radius. No game client is involved. Not seen in game.
local _, ns = ...

local A, N = ns.Arrow, ns.Nav

-- The player in the middle of map 1411 (1000 by 500 yards), facing north.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setScreen(1024, 768)
    c.setZone(1, 1411)
    if opts.facing ~= false then c.setFacing(opts.facing or 0) end
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

local function at(x, y, label, more)
    local step = { place = { cont = 1, map = 1411, x = x, y = y }, label = label }
    for key, v in pairs(more or {}) do step[key] = v end
    return step
end

local function lines(c, guide) return A.GuideSource(c, {}, guide).lines end

return {
    ["arrow text: the words are the ones agreed"] = function(t)
        t.eq(A.HERE_TEXT, "you're here")
        t.eq(A.DISTANCE_TEXT, "%d yd")
        t.eq(A.DISTANCE_COMPASS_TEXT, "%d yd %s")
    end,

    ["arrow text: the compass word stands after the distance"] = function(t)
        local c = start()
        t.eq(lines(c, { quest = at(0.5, 0.3, "Kill boars") }).quest, { "Kill boars", "100 yd N" })
        t.eq(lines(c, { quest = at(0.8, 0.5, "Kill boars") }).quest, { "Kill boars", "300 yd E" })
        t.eq(lines(c, { quest = at(0.5, 0.9, "Kill boars") }).quest, { "Kill boars", "200 yd S" })
        t.eq(lines(c, { quest = at(0.3, 0.5, "Kill boars") }).quest, { "Kill boars", "200 yd W" })
        t.eq(lines(c, { quest = at(0.6, 0.3, "Kill boars") }).quest, { "Kill boars", "141 yd NE" })
        t.eq(lines(c, { quest = at(0.4, 0.7, "Kill boars") }).quest, { "Kill boars", "141 yd SW" })
    end,

    ["arrow text: both arrows say their own"] = function(t)
        local c = start()
        local out = lines(c, { quest = at(0.5, 0.3, "Kill boars"), prof = at(0.8, 0.5, "Copper vein", { on = true }) })
        t.eq(out.quest, { "Kill boars", "100 yd N" })
        t.eq(out.prof, { "Copper vein", "300 yd E" })
    end,

    ["arrow text: the word is where the place lies, not which way the player faces"] = function(t)
        local c = start({ facing = math.pi / 2 })
        t.eq(lines(c, { quest = at(0.5, 0.3, "Kill boars") }).quest, { "Kill boars", "100 yd N" })
    end,

    ["arrow text: with the facing unknown the word is still said, then that the turn is unknown"] = function(t)
        local c = start({ facing = false })
        t.eq(lines(c, { quest = at(0.5, 0.3, "Kill boars") }).quest,
            { "Kill boars", "100 yd N", A.UNKNOWN_TURN })
    end,

    ["arrow text: inside the arrival radius it says the player is here, with no distance"] = function(t)
        local c = start()
        t.eq(lines(c, { quest = at(0.5, 0.48, "Kill boars") }).quest, { "Kill boars", A.HERE_TEXT }, "10 yd")
        t.eq(lines(c, { quest = at(0.5, 0.5, "Kill boars") }).quest, { "Kill boars", A.HERE_TEXT }, "the spot")
        t.eq(lines(c, { quest = at(0.5, 0.44, "Kill boars") }).quest, { "Kill boars", "30 yd N" },
            "30 yd: outside it")
    end,

    ["arrow text: a step's own radius is its arrival radius"] = function(t)
        local c = start()
        t.eq(lines(c, { quest = at(0.5, 0.3, "Kill boars", { radius = 120 }) }).quest,
            { "Kill boars", A.HERE_TEXT })
        t.eq(lines(c, { prof = at(0.8, 0.5, "Copper vein", { on = true, radius = 300 }) }).prof,
            { "Copper vein", A.HERE_TEXT })
    end,

    ["arrow text: here with no label is the one line"] = function(t)
        local c = start()
        t.eq(lines(c, { quest = at(0.5, 0.5) }).quest, { A.HERE_TEXT })
    end,

    ["arrow text: at the step nothing is unknown, so no unknown line, facing known or not"] = function(t)
        local c = start({ facing = false })
        local src = A.GuideSource(c, {}, { quest = at(0.5, 0.48, "Kill boars") })
        t.eq(src.lines.quest, { "Kill boars", A.HERE_TEXT }, "10 yd, no facing")
        t.eq(src.lost.quest, nil, "the ring points nowhere: nothing is lost")
        src = A.GuideSource(c, {}, { quest = at(0.5, 0.5, "Kill boars") })
        t.eq(src.lines.quest, { "Kill boars", A.HERE_TEXT }, "the very spot, no facing")
        t.eq(src.lost.quest, nil)
        src = A.GuideSource(c, {}, { prof = at(0.5, 0.5, "Copper vein", { on = true }) })
        t.eq(src.lines.prof, { "Copper vein", A.HERE_TEXT })
        t.eq(src.lost.prof, nil)
        -- Away from it the unknown line is still said, once.
        src = A.GuideSource(c, {}, { quest = at(0.5, 0.3, "Kill boars", { lines = { "a" } }) })
        t.eq(src.lines.quest, { "a", A.UNKNOWN_TURN })
        t.eq(src.lost.quest, true)
        c.setFacing(0)
        src = A.GuideSource(c, {}, { quest = at(0.5, 0.5, nil, { lines = { "a" } }) })
        t.eq(src.lines.quest, { "a" }, "a step's own lines at the very spot")
        t.eq(src.lost.quest, nil)
    end,

    ["arrow text: no distance, no word and no here"] = function(t)
        local c = start()
        c.setPosition(1412, 0.5, 0.5)
        local out = lines(c, { quest = at(0.5, 0.5, "Kill boars") }).quest
        t.eq(out[1], "Kill boars")
        for i = 2, #out do
            t.ok(out[i] == A.UNKNOWN_TURN, "nothing is made up: " .. tostring(out[i]))
        end
    end,

    ["arrow text: a step's own lines are left as they are"] = function(t)
        local c = start()
        t.eq(lines(c, { quest = at(0.5, 0.3, "Kill boars", { lines = { "a", "b" } }) }).quest, { "a", "b" })
        t.eq(lines(c, { quest = at(0.5, 0.5, nil, { lines = { "a" } }) }).quest, { "a" })
    end,

    ["arrow text: the corpse arrow says the word too"] = function(t)
        local c = start()
        c.setDead(true)
        c.setCorpse(1411, 0.3, 0.5)
        t.eq(lines(c, { quest = at(0.5, 0.3, "Kill boars") }).quest, { A.CORPSE_LABEL, "200 yd W" })
    end,

    ["arrow text: on the frames, here is said on the ring"] = function(t)
        local c, a = start()
        a.setGuide(function() return { quest = at(0.5, 0.3, "Kill boars") } end)
        local q = c.arrows[1]
        t.eq(q.lines, { "Kill boars", "100 yd N" })
        c.setPosition(1411, 0.5, 0.32)
        a.relayout()
        t.eq(a.state().view.quest.mode, "ring")
        t.eq(q.lines, { "Kill boars", A.HERE_TEXT })
        t.eq(N.AT_POINT, 24, "the radius these places are set by")
    end,
}
