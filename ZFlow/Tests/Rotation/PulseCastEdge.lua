-- Tests for ZFlow/Rotation/Pulse.lua and ZFlow/Rotation/CastEdge.lua (S14):
-- the suggestion pulse and the cast edge. The glow, the edge bar and the
-- cast read are client needs that Core/Client.lua does not have yet, so
-- these tests put hand-written ones on their own fake client and icon.
-- Not tested in game.
local _, ns = ...

local P = ns.Pulse
local CE = ns.CastEdge
local D = ns.RotationDriver
local tests = {}

local CLASS = "TESTCLASS"
local WRATH, MOONFIRE = 5176, 8921 -- test values, not client data

local function near(t, got, want, what)
    t.ok(type(got) == "number" and math.abs(got - want) < 1e-9,
        (what or "value") .. ": got " .. tostring(got) .. ", wanted " .. tostring(want))
end

local function pack()
    return {
        spells = { Wrath = { evidence = "test" }, Moonfire = { evidence = "test" } },
        lists = { default = {
            { spell = "Moonfire", target = true, reason = "Moonfire" },
            { spell = "Wrath", target = true, reason = "Wrath" },
        } },
        keys = { none = { key = "Wrath" } },
    }
end

-- A thing that can be dimmed: it keeps every brightness it was given.
local function region()
    local r = { alphas = {}, shown = nil }
    function r.setAlpha(a) r.alpha = a; r.alphas[#r.alphas + 1] = a end
    function r.show(on) r.shown = on and true or false end
    function r.setColor(red, green, blue) r.color = { red, green, blue } end
    return r
end

-- A frame source: what client.onFrame is. frames() calls every listener.
local function source()
    local s = { fns = {}, asked = 0, cancelled = 0 }
    function s.onFrame(fn)
        s.asked = s.asked + 1
        s.fns[fn] = true
        return function()
            s.cancelled = s.cancelled + 1
            s.fns[fn] = nil
        end
    end
    function s.frame()
        for fn in pairs(s.fns) do fn(0.016) end
    end
    return s
end

-- ------------------------------------------------------------ Pulse.Alpha
tests["pulse: names and the values taken from Flow"] = function(t)
    t.eq(P.NAME, "pulse")
    t.eq(P.COLOR, { 1, 0.5, 0 })
    t.eq(P.PERIOD, 0.9)
    t.eq(P.LOW, 0.3)
end

tests["pulse alpha: bright at the start of a beat, dimmest halfway"] = function(t)
    near(t, P.Alpha(0), 1, "start")
    near(t, P.Alpha(P.PERIOD / 2), P.LOW, "halfway")
    near(t, P.Alpha(P.PERIOD), 1, "the next beat")
    near(t, P.Alpha(P.PERIOD / 4), P.LOW + (1 - P.LOW) * 0.5, "a quarter")
end

tests["pulse alpha: never under the low and never over 1"] = function(t)
    for i = 0, 200 do
        local a = P.Alpha(i * 0.0137)
        t.ok(a >= P.LOW - 1e-9 and a <= 1 + 1e-9, "out of range at step " .. i)
    end
end

tests["pulse alpha: a period and a low of its own"] = function(t)
    near(t, P.Alpha(1, 2, 0.5), 0.5, "halfway through 2 s")
    near(t, P.Alpha(2, 2, 0.5), 1, "a whole beat")
    near(t, P.Alpha(P.PERIOD / 2, 0, nil), P.LOW, "a period of 0 is not used")
end

tests["pulse alpha: a moment that is not known gives a steady 1"] = function(t)
    t.eq(P.Alpha(nil), 1)
    t.eq(P.Alpha("soon"), 1)
end

-- -------------------------------------------------------------- Pulse.New
tests["pulse set: the frame listener is asked for at the first add only"] = function(t)
    local s = source()
    local p = P.New({ onFrame = s.onFrame, now = function() return 0 end })
    t.eq(s.asked, 0, "nothing runs while nothing pulses")
    t.eq(p.running(), false)
    local a, b = region(), region()
    t.eq(p.add(a), true)
    t.eq(p.add(b), true)
    t.eq(p.add(a), true, "twice is once")
    t.eq(s.asked, 1)
    t.eq(p.count(), 2)
    t.eq(p.has(a), true)
    t.eq(p.running(), true)
end

tests["pulse set: every region is on the same beat"] = function(t)
    local s = source()
    local now = 0
    local p = P.New({ onFrame = s.onFrame, now = function() return now end })
    local a, b = region(), region()
    p.add(a)
    p.add(b)
    now = P.PERIOD / 2
    s.frame()
    near(t, a.alpha, P.LOW, "a")
    near(t, b.alpha, P.LOW, "b")
    now = P.PERIOD
    s.frame()
    near(t, a.alpha, 1, "a, a beat later")
    near(t, b.alpha, 1, "b, a beat later")
end

tests["pulse set: a removed region is left at full, or at what was asked"] = function(t)
    local s = source()
    local now = P.PERIOD / 2
    local p = P.New({ onFrame = s.onFrame, now = function() return now end })
    local a, b = region(), region()
    p.add(a)
    p.add(b)
    t.eq(p.remove(a), true)
    t.eq(a.alpha, 1)
    t.eq(p.has(a), false)
    t.eq(s.cancelled, 0, "one still pulses")
    local n = #a.alphas
    s.frame()
    t.eq(#a.alphas, n, "a removed region is not touched again")
    t.eq(p.remove(b, 0.5), true)
    t.eq(b.alpha, 0.5)
    t.eq(s.cancelled, 1, "the listener is cancelled when the set is empty")
    t.eq(p.running(), false)
    t.eq(p.remove(b), false, "it is not there twice")
    p.add(a)
    t.eq(s.asked, 2, "and asked for again at the next add")
end

tests["pulse set: what cannot be dimmed is refused"] = function(t)
    local s = source()
    local p = P.New({ onFrame = s.onFrame })
    t.eq(p.add(nil), false)
    t.eq(p.add({}), false)
    t.eq(p.add("glow"), false)
    t.eq(p.count(), 0)
    t.eq(s.asked, 0)
end

tests["pulse set: a region that raises does not stop the others"] = function(t)
    local s = source()
    local now = 0
    local p = P.New({ onFrame = s.onFrame, now = function() return now end })
    local bad = { setAlpha = function() error("boom") end }
    local good = region()
    p.add(bad)
    p.add(good)
    now = P.PERIOD / 2
    t.eq(pcall(s.frame), true)
    near(t, good.alpha, P.LOW, "the good one")
end

tests["pulse set: with no clock everything is steady at full"] = function(t)
    local s = source()
    local p = P.New({ onFrame = s.onFrame, now = function() error("no clock") end })
    local a = region()
    p.add(a)
    s.frame()
    t.eq(a.alpha, 1)
end

tests["pulse set: a frame source that gives no cancel is asked once"] = function(t)
    local asked = 0
    local p = P.New({ onFrame = function() asked = asked + 1 end })
    local a = region()
    p.add(a)
    p.remove(a)
    p.add(a)
    t.eq(asked, 1)
end

-- --------------------------------------------------------- CastEdge.Progress
tests["cast edge: names and the values taken from Flow"] = function(t)
    t.eq(CE.NAME, "castEdge")
    t.eq(CE.HEIGHT, 3)
    t.eq(CE.COLOR, { 1, 0.82, 0.1 })
end

tests["cast edge progress: a cast fills from 0 to 1"] = function(t)
    t.eq(CE.Progress(1000, 3000, 1000), 0)
    t.eq(CE.Progress(1000, 3000, 2000), 0.5)
    t.eq(CE.Progress(1000, 3000, 3000), 1)
end

tests["cast edge progress: a channel drains from 1 to 0"] = function(t)
    t.eq(CE.Progress(1000, 3000, 1000, true), 1)
    t.eq(CE.Progress(1000, 3000, 2500, true), 0.25)
    t.eq(CE.Progress(1000, 3000, 3000, true), 0)
end

tests["cast edge progress: just past the end is still full, then it is over"] = function(t)
    t.eq(CE.Progress(1000, 3000, 3050), 1, "2.5% past")
    t.eq(CE.Progress(1000, 3000, 3050, true), 0, "a channel 2.5% past")
    t.eq(CE.Progress(1000, 3000, 3200), nil, "10% past")
    t.eq(CE.Progress(1000, 3000, 900), nil, "before it began")
end

tests["cast edge progress: no cast and times that make no sense give nothing"] = function(t)
    t.eq(CE.Progress(nil, nil, 1000), nil)
    t.eq(CE.Progress(1000, nil, 1000), nil)
    t.eq(CE.Progress(1000, 3000, nil), nil)
    t.eq(CE.Progress(3000, 3000, 3000), nil, "no length")
    t.eq(CE.Progress(3000, 1000, 2000), nil, "ends before it starts")
    t.eq(CE.Progress("1000", "3000", 2000), nil, "texts are not times")
end

-- ------------------------------------------------------------- the modules
-- opts.glow / opts.edge false: the icon handle lacks it. opts.casting
-- false: the client has no cast read.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSpellId("Wrath", WRATH)
    c.setSpellId("Moonfire", MOONFIRE)
    c.setSpell(WRATH, { known = true, usable = true, noPower = false })
    c.setSpell(MOONFIRE, { known = true, usable = true, noPower = false })
    c.setSpellCooldown(WRATH, false)
    c.setSpellCooldown(MOONFIRE, false)
    local hasTarget = opts.target ~= false
    c.target = function()
        if not hasTarget then return nil end
        return { exists = true, hostile = true, dead = false }
    end
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setDead(false)
    c.setClass(CLASS)
    local cast = {}
    if opts.casting ~= false then
        c.casting = function()
            if cast.raise then error("boom") end
            return cast.startMs, cast.endMs, cast.channel
        end
    end
    local icon = {}
    if opts.glow ~= false then icon.glow = region() end
    if opts.edge ~= false then
        local e = { sets = 0, shown = false }
        function e.set(p) e.p = p; e.sets = e.sets + 1 end
        function e.show(on) e.shown = on and true or false end
        icon.edge = e
    end
    local function iconOf()
        if opts.icon == false then return nil end
        return icon
    end
    local k = ns.Kernel({}, c)
    D.Declare(k, { [CLASS] = pack() })
    local pulse = P.Declare(k, iconOf)
    local edge = CE.Declare(k, iconOf)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    if opts.rotation ~= false then k.settings:set(D.SETTING, true) end
    local w = { k = k, c = c, icon = icon, cast = cast, pulse = pulse, edge = edge }
    function w.noTarget() hasTarget = false end
    return w
end

local function tick(c) c.advance(D.EVERY + 0.05, 1) end

tests["pulse module: the glow pulses while a spell is suggested"] = function(t)
    local w = start()
    tick(w.c)
    local g = w.icon.glow
    t.eq(w.pulse.lit(), g)
    t.eq(w.pulse.count(), 1)
    t.eq(g.shown, true)
    t.eq(g.color, { P.COLOR[1], P.COLOR[2], P.COLOR[3] })
    local n = #g.alphas
    w.c.advance(0.1, 4)
    t.ok(#g.alphas > n, "the brightness moves with the frames")
    for i = 1, #g.alphas do
        t.ok(g.alphas[i] >= P.LOW - 1e-9 and g.alphas[i] <= 1 + 1e-9, "brightness out of range")
    end
    t.eq(w.k.problems:count(P.NAME), 0)
end

tests["pulse module: the rotation switched off, nothing pulses"] = function(t)
    local w = start({ rotation = false })
    w.c.advance(2, 10)
    t.eq(w.pulse.lit(), nil)
    t.eq(w.pulse.count(), 0)
    t.eq(#w.icon.glow.alphas, 0)
    t.eq(w.k.problems:count(P.NAME), 0)
end

tests["pulse module: switched off again, the glow is hidden and left at full"] = function(t)
    local w = start()
    tick(w.c)
    t.eq(w.pulse.count(), 1)
    w.k.settings:set(D.SETTING, false)
    tick(w.c)
    t.eq(w.pulse.lit(), nil)
    t.eq(w.pulse.count(), 0)
    t.eq(w.icon.glow.shown, false)
    t.eq(w.icon.glow.alpha, 1)
end

tests["pulse module: an icon with no glow is one problem, said once"] = function(t)
    local w = start({ glow = false })
    tick(w.c)
    tick(w.c)
    tick(w.c)
    t.eq(w.pulse.lit(), nil)
    t.eq(w.pulse.count(), 0)
    t.eq(w.k.problems:count(P.NAME), 1)
end

tests["pulse module: no icon yet is not a problem"] = function(t)
    local w = start({ icon = false })
    tick(w.c)
    t.eq(w.pulse.count(), 0)
    t.eq(w.k.problems:count(P.NAME), 0)
end

tests["cast edge module: the edge follows the cast"] = function(t)
    local w = start()
    local e = w.icon.edge
    tick(w.c)
    t.eq(e.shown, false, "no cast, no edge")
    t.eq(w.edge.shown(), false)
    local now = w.c.now() * 1000
    w.cast.startMs, w.cast.endMs = now, now + 2000
    w.c.advance(1, 1)
    t.eq(e.shown, true)
    t.eq(w.edge.shown(), true)
    near(t, e.p, 0.5, "halfway")
    w.c.advance(0.5, 1)
    near(t, e.p, 0.75, "three quarters")
    w.c.advance(1, 1)
    t.eq(e.shown, false, "over: hidden")
    t.eq(w.k.problems:count(CE.NAME), 0)
end

tests["cast edge module: a channel drains"] = function(t)
    local w = start()
    local now = w.c.now() * 1000
    w.cast.startMs, w.cast.endMs, w.cast.channel = now, now + 4000, true
    w.c.advance(1, 1)
    near(t, w.icon.edge.p, 0.75, "a quarter gone")
    t.eq(w.icon.edge.shown, true)
end

tests["cast edge module: the cast stopped, the edge is hidden"] = function(t)
    local w = start()
    local now = w.c.now() * 1000
    w.cast.startMs, w.cast.endMs = now, now + 4000
    w.c.advance(1, 1)
    t.eq(w.icon.edge.shown, true)
    w.cast.startMs, w.cast.endMs = nil, nil
    w.c.advance(0.1, 1)
    t.eq(w.icon.edge.shown, false)
end

tests["cast edge module: the rotation switched off, nothing is drawn"] = function(t)
    local w = start({ rotation = false })
    local now = w.c.now() * 1000
    w.cast.startMs, w.cast.endMs = now, now + 4000
    w.c.advance(1, 4)
    t.eq(w.icon.edge.shown, false)
    t.eq(w.icon.edge.sets, 0)
end

tests["cast edge module: a client with no cast read is one problem and draws nothing"] = function(t)
    local w = start({ casting = false })
    w.c.advance(2, 10)
    t.eq(w.icon.edge.sets, 0)
    t.eq(w.icon.edge.shown, false)
    t.eq(w.k.problems:count(CE.NAME), 1)
end

tests["cast edge module: an icon with no edge bar is one problem, said once"] = function(t)
    local w = start({ edge = false })
    local now = w.c.now() * 1000
    w.cast.startMs, w.cast.endMs = now, now + 4000
    w.c.advance(1, 5)
    t.eq(w.edge.shown(), false)
    t.eq(w.k.problems:count(CE.NAME), 1)
end

tests["cast edge module: a cast read that raises draws nothing and stops nothing"] = function(t)
    local w = start()
    w.cast.raise = true
    t.eq(pcall(w.c.advance, 1, 5), true)
    t.eq(w.icon.edge.shown, false)
    t.eq(w.icon.edge.sets, 0)
end

return tests
