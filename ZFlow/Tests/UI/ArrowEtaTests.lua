-- The arrow's time to arrive (G40), over the fake client: after the
-- distance and the compass word, about how long the straight line takes at
-- the speed the player moves now. No game client is involved. Not seen in
-- game.
local _, ns = ...

local A = ns.Arrow

-- The player in the middle of map 1411 (1000 by 500 yards), facing north.
local function start(speed)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setScreen(1024, 768)
    c.setZone(1, 1411)
    c.setFacing(0)
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    c.setSpeed(speed)
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    A.Start(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return c
end

local function at(x, y, label)
    return { place = { cont = 1, map = 1411, x = x, y = y }, label = label }
end

local function lines(c, guide) return A.GuideSource(c, {}, guide).lines end

return {
    ["arrow eta: the words"] = function(t)
        t.eq(A.EtaText(100, 7), "about 15 sec")
        t.eq(A.EtaText(100, 14), "about 10 sec", "mounted: sooner")
        t.eq(A.EtaText(3, 7), "about 5 sec", "never less than five")
        t.eq(A.EtaText(413, 7), "about 60 sec", "just under a minute")
        t.eq(A.EtaText(420, 7), "about 1 min", "a minute and over: minutes")
        t.eq(A.EtaText(2100, 7), "about 5 min")
        t.eq(A.EtaText(100, 0), "about 15 sec", "standing still: at a run on foot")
    end,

    ["arrow eta: nothing is said without a distance or a speed"] = function(t)
        t.eq(A.EtaText(nil, 7), nil)
        t.eq(A.EtaText(100, nil), nil)
        t.eq(A.EtaText(100, -1), nil)
        t.eq(A.EtaText(0 / 0, 7), nil)
        t.eq(A.EtaText(100, math.huge), nil)
        t.eq(A.EtaText("100", 7), nil)
    end,

    ["arrow eta: the time stands after the distance and the compass word"] = function(t)
        local c = start(7)
        t.eq(lines(c, { quest = at(0.5, 0.3, "Kill boars") }).quest, { "Kill boars", "100 yd N, about 15 sec" })
        c.setSpeed(14)
        t.eq(lines(c, { quest = at(0.8, 0.5, "Kill boars") }).quest, { "Kill boars", "300 yd E, about 25 sec" })
    end,

    ["arrow eta: both arrows say their own"] = function(t)
        local c = start(0)
        local guide = { quest = at(0.5, 0.3, "Kill boars"), prof = at(0.8, 0.5, "Copper vein") }
        guide.prof.on = true
        local out = lines(c, guide)
        t.eq(out.quest, { "Kill boars", "100 yd N, about 15 sec" })
        t.eq(out.prof, { "Copper vein", "300 yd E, about 45 sec" })
    end,

    ["arrow eta: at the place it is you're here, with no time"] = function(t)
        local c = start(7)
        t.eq(lines(c, { quest = at(0.5, 0.5, "Kill boars") }).quest, { "Kill boars", A.HERE_TEXT })
    end,

    ["arrow eta: the speed not read: the distance line as before"] = function(t)
        local c = start(nil)
        t.eq(lines(c, { quest = at(0.5, 0.3, "Kill boars") }).quest, { "Kill boars", "100 yd N" })
    end,
}
