local _, ns = ...
-- UI/FightInsight.lua (parity row C-51; lead section 664): an advice prompt
-- from the fight log, for dying to the same enemy more than once. A made-up
-- fight log on a fake client. Offline only: not tested in game.
local tests = {}
local FI = ns.FightInsight
local A = ns.Advisor

local function death(...)
    local hits = {}
    for i, from in ipairs({ ... }) do hits[i] = { name = "Melee", amount = 10, from = from or nil } end
    return { timed = true, at = 100, window = 10, hits = hits }
end

-- log.next: the death the fight log holds after the next death.
local function start()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    local k = ns.Kernel({}, c)
    local advisor = A.Declare(k)
    local log = { held = nil }
    function log.death() return log.held end
    local api = FI.Declare(k, function() return log end)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    local function die(d)
        log.held = d
        c.fire(FI.DEAD)
        c.advance(FI.EVERY + 0.1, 2)
    end
    local function prompt()
        for _, p in ipairs(advisor.List()) do
            if p.id == FI.PROMPT then return p.text end
        end
        return nil
    end
    return { c = c, k = k, api = api, die = die, prompt = prompt, log = log }
end

tests["fight insight: who killed you is whoever landed the last hit that named anyone"] = function(t)
    t.eq(FI.Killer(death("Gnoll Brute", "Murloc")), "Murloc")
    t.eq(FI.Killer({ hits = { { from = "Gnoll Brute" }, { name = "Falling" }, { from = "" } } }), "Gnoll Brute",
        "a hit that names nobody is passed over")
    t.eq(FI.Killer({ hits = { { name = "Falling" } } }), nil, "nobody named: not known")
    t.eq(FI.Killer({ hits = {} }), nil)
    t.eq(FI.Killer(nil), nil)
    t.eq(FI.Killer({}), nil)
end

tests["fight insight: the line names the enemy and the count"] = function(t)
    t.eq(FI.Text("Gnoll Brute", 2), "You have died to Gnoll Brute 2 times this session.")
    t.eq(FI.Text("", 2), nil)
    t.eq(FI.Text("Gnoll Brute", nil), nil)
end

-- Fails before: there is no such module, and no prompt comes from a death.
tests["fight insight: one death says nothing, the second to the same enemy is a prompt"] = function(t)
    local w = start()
    t.eq(w.prompt(), nil)
    w.die(death("Gnoll Brute"))
    t.eq(w.prompt(), nil, "once is no pattern")
    t.eq(w.api.Deaths(), { ["Gnoll Brute"] = 1 })
    w.die(death("Gnoll Brute"))
    t.eq(w.prompt(), "You have died to Gnoll Brute 2 times this session.")
    w.die(death("Gnoll Brute"))
    t.eq(w.prompt(), "You have died to Gnoll Brute 3 times this session.", "the count goes on")
    t.eq(w.k.problems:count(), 0)
end

tests["fight insight: the prompt is for your last death, and goes when that was to another enemy"] = function(t)
    local w = start()
    w.die(death("Gnoll Brute"))
    w.die(death("Gnoll Brute"))
    w.die(death("Murloc"))
    t.eq(w.prompt(), nil, "a first death to another enemy")
    t.eq(w.api.Deaths(), { ["Gnoll Brute"] = 2, Murloc = 1 }, "the counts are kept")
    w.die(death("Gnoll Brute"))
    t.eq(w.prompt(), "You have died to Gnoll Brute 3 times this session.")
end

tests["fight insight: a death nobody is named for counts for nobody and guesses no enemy"] = function(t)
    local w = start()
    w.die(death("Gnoll Brute"))
    w.die(death("Gnoll Brute"))
    w.die({ timed = true, at = 200, window = 10, hits = { { name = "Falling", amount = 500 } } })
    t.eq(w.prompt(), nil, "not known who: the old prompt is taken back")
    t.eq(w.api.Deaths(), { ["Gnoll Brute"] = 2 })
    w.die(nil)
    t.eq(w.prompt(), nil, "the fight log holds no death")
    t.eq(w.api.Deaths(), { ["Gnoll Brute"] = 2 })
end

tests["fight insight: a death is counted once, however many looks follow"] = function(t)
    local w = start()
    w.die(death("Gnoll Brute"))
    w.c.advance(10, 20)
    t.eq(w.api.Deaths(), { ["Gnoll Brute"] = 1 })
end

tests["fight insight: a fight log that raises or is not there says nothing and breaks nothing"] = function(t)
    local w = start()
    w.log.death = function() error("the fight log refused") end
    w.c.fire(FI.DEAD)
    w.c.advance(FI.EVERY + 0.1, 2)
    t.eq(w.prompt(), nil)
    t.eq(w.api.Deaths(), {})
    w.log.death = nil
    w.c.fire(FI.DEAD)
    w.c.advance(FI.EVERY + 0.1, 2)
    t.eq(w.api.Deaths(), {})
    t.eq(w.k.problems:count(), 0)
    t.eq(type(ns.fightInsight), "table", "the addon's own is declared")
end

return tests
