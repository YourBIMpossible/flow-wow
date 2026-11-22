-- The arrows' frame clock and frame errors (LEDGER 50, Q1 and Q2): time
-- between frames is never negative, and a frame error switches the module
-- off through the kernel. Over the fake client; no game client.
local _, ns = ...

local A = ns.Arrow

local function start(direct, own)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setScreen(1024, 768)
    c.setZone(1, 1411)
    c.setFacing(0)
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    -- Counts the calls of the arrow module's own stop, as the kernel makes
    -- them: the spec is wrapped on its way into k:Module.
    local stops, declare = 0, k.Module
    k.Module = function(self, spec)
        if type(spec) == "table" and spec.name == A.NAME and type(spec.stop) == "function" then
            local stop = spec.stop
            spec.stop = function(...)
                stops = stops + 1
                return stop(...)
            end
        end
        return declare(self, spec)
    end
    local a
    if direct then a = A.Start(k, d, own) else a = A.Declare(k, d) end
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, a, d, function() return stops end
end

-- Runs fn with every elapsed time the arrows hand to their motion noted.
local function watched(fn)
    local N, seen = ns.Nav, {}
    local real = N.ArrowStep
    N.ArrowStep = function(motion, elapsed, now)
        seen[#seen + 1] = elapsed
        return real(motion, elapsed, now)
    end
    local ok, err = pcall(fn, seen)
    N.ArrowStep = real
    if not ok then error(err, 0) end
    return seen
end

local function work(k)
    local row = k.meter:report()[A.NAME]
    return row and row.calls or 0
end

return {
    -- Q1
    ["frame clock: a clock that steps back gives a frame no negative time"] = function(t)
        local k, c, _, d = start()
        d.commands.arrow("demo")
        local at = 100
        c.now = function() return at end
        local seen = watched(function()
            c.advance(0.1, 1)
            at = 130
            c.advance(0.1, 1)
            at = 50
            c.advance(0.1, 1)
            at = 51
            c.advance(0.1, 1)
        end)
        t.ok(#seen >= 4, "the arrow drew in each frame")
        local low = 0
        for i = 1, #seen do
            if type(seen[i]) ~= "number" then
                low = "not a number"
                break
            end
            if seen[i] < low then low = seen[i] end
        end
        t.eq(low, 0, "no frame is given less than no time")
        t.eq(seen[#seen], 1, "and the clock is followed again from where it stepped back to")
        t.eq(k.problems:count(), 0)
        t.eq(k:ModuleState(A.NAME), "started")
    end,

    ["frame clock: a clock that answers nil gives a frame no time, and no error"] = function(t)
        local k, c, _, d = start()
        d.commands.arrow("demo")
        local at = 100
        c.now = function() return at end
        local seen = watched(function()
            c.advance(0.1, 1)
            at = nil
            c.advance(0.1, 1)
            c.advance(0.1, 1)
            at = 104
            c.advance(0.1, 1)
        end)
        t.ok(#seen >= 4, "the arrow drew in each frame")
        local bad = 0
        for i = 1, #seen do
            if type(seen[i]) ~= "number" or seen[i] < 0 then bad = bad + 1 end
        end
        t.eq(bad, 0, "every frame is given a time that is a number, not below 0")
        t.eq(seen[#seen], 0, "the first frame after the clock is back has no time to count from")
        t.eq(k.problems:count(), 0)
        t.eq(k:ModuleState(A.NAME), "started")
    end,

    -- Q2
    ["frame error: the module is switched off through the kernel, and its stop ran once"] = function(t)
        local k, c, a, d, stops = start()
        d.commands.arrow("demo")
        local q, p = c.arrows[1], c.arrows[2]
        t.eq(stops(), 0, "no stop while it runs")
        q.draw = function() error("boom") end
        c.advance(0.1, 1)
        t.eq(stops(), 1, "its stop ran once")
        local state, reason = k:ModuleState(A.NAME)
        t.ok(state ~= "started", "not started after a frame error")
        t.eq(state, "off")
        t.ok(type(reason) == "string" and reason:find("boom", 1, true) ~= nil, "the reason is the error")
        t.eq(k.problems:count("arrow"), 1, "one problem of the arrow")
        t.eq(k.problems:count("module"), 1, "switched off once")
        t.eq({ q.shown, p.shown }, { false, false })
        t.eq(a.state().view, nil)
        local ran, draws = work(k), p.draws
        c.fire("PLAYER_ENTERING_WORLD")
        c.advance(1, 10)
        t.eq(work(k), ran, "the kernel runs nothing of it: no handler, no frame job, no second stop")
        t.eq(p.draws, draws)
        t.eq(k.problems:count("module"), 1)
        d.commands.arrow("demo")
        t.eq({ q.shown, p.shown }, { false, false }, "the demo does not bring it back")
        t.eq(k:SwitchOff(A.NAME, "again"), false)
        t.eq(stops(), 1, "and no second stop, whatever came after")
    end,

    ["frame error: the arrows ask their owner once to switch them off, and keep no state of their own"] = function(t)
        local offs, alive, inner = {}, true, nil
        local own = {
            live = function() return alive end,
            off = function(err)
                offs[#offs + 1] = tostring(err)
                alive = false
                inner.stop()
            end,
        }
        local k, c, a, d = start(true, own)
        inner = a
        d.commands.arrow("demo")
        local q, p = c.arrows[1], c.arrows[2]
        t.eq(q.shown, true)
        local real = q.draw
        q.draw = function() error("boom") end
        c.advance(0.1, 3)
        t.eq(#offs, 1, "asked once")
        t.ok((offs[1] or ""):find("boom", 1, true) ~= nil, "with the error")
        t.eq({ q.shown, p.shown }, { false, false })
        t.eq(k.problems:count("arrow"), 1)
        -- The owner is the one source of truth: when it says the arrows
        -- live again, they do.
        q.draw = real
        alive = true
        a.relayout()
        t.eq(q.shown, true, "nothing of the arrows' own keeps them off")
    end,
}
