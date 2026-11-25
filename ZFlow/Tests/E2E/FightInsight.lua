local _, ns = ...
-- The fight insight (C-51; UI/FightInsight.lua) on the whole add-on loaded
-- on a fake client, through its real entries (Twin's review, lead section
-- 694): combat-log hits on you handed on by the client, the death event,
-- and the prompt in the advisor. The fight log (UI/FightLog.lua) is the
-- real one. Every combat-log event is written by hand. Made-up names only.
-- Not tested in game.
local tests = {}

local ME, MOB, OTHER = "Player-1-0000AAAA", "Creature-0-1-0000CCCC", "Creature-0-1-0000DDDD"

local function spell(src, srcName, id, name, amount)
    return { 1000, "SPELL_DAMAGE", false, src, srcName, 0, 0, ME, "Zarkon", 0, 0, id, name, 1, amount, 0 }
end

local function boot()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setVersion("0.1.0")
    c.setGuid("player", ME)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function log(c, ev) c.combatLog(unpack(ev, 1, 16)) end

local function prompt(addon)
    for _, p in ipairs(addon.use("advisor").List()) do
        if p.id == ns.FightInsight.PROMPT then return p.text end
    end
    return nil
end

-- Two hits from one enemy, then the death; the insight looks a second later.
local function dieTo(c, src, srcName)
    c.setCombat(true)
    log(c, spell(src, srcName, 17253, "Bite", 30))
    c.advance(1, 1)
    log(c, spell(src, srcName, 17253, "Bite", 40))
    c.fire("PLAYER_DEAD")
    c.setCombat(false)
    c.advance(2, 4)
end

-- Fails before: only a hand-made fight log was ever read.
tests["fight insight e2e: the second death to the same enemy is a prompt in the advisor"] = function(t)
    local c, addon = boot()
    dieTo(c, MOB, "Hollow Wolf")
    t.eq(prompt(addon), nil, "once is no pattern")
    c.advance(30, 30)
    dieTo(c, MOB, "Hollow Wolf")
    t.eq(prompt(addon), "You have died to Hollow Wolf 2 times this session.")
    c.advance(30, 30)
    dieTo(c, OTHER, "Gnoll Brute")
    t.eq(prompt(addon), nil, "the last death was to another enemy")
end

-- Twin's note (a): a death with no new hits on you does not name the last
-- killer again. Fails before: the hits before a death were kept after it.
tests["fight insight e2e: a second death with no new hits names nobody"] = function(t)
    local c, addon = boot()
    dieTo(c, MOB, "Hollow Wolf")
    c.fire("PLAYER_DEAD")
    c.advance(2, 4)
    t.eq(prompt(addon), nil)
    t.eq(addon.use(ns.FightInsight.NAME).Deaths(), { ["Hollow Wolf"] = 1 }, "counted once")
end

-- Twin's note (b): your own damage to yourself never names you.
tests["fight insight e2e: you are never named as who killed you"] = function(t)
    local c, addon = boot()
    dieTo(c, ME, "Zarkon")
    c.advance(30, 30)
    dieTo(c, ME, "Zarkon")
    t.eq(prompt(addon), nil)
    t.eq(addon.use(ns.FightInsight.NAME).Deaths(), {}, "no death counted to yourself")
end

return tests
