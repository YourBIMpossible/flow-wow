local _, ns = ...
-- The fight log (G29, G30; UI/FightLog.lua) on the whole add-on loaded on a
-- fake client, through its real entries: the combat start and end events,
-- the combat log the client hands on, the death event, and the slash word
-- "fights". The player reads what is said in chat. Unknown data: the
-- client will not say who you are, and a client with no combat log at all.
-- Every combat-log event is written by hand. Offline: the fake client's
-- feed, not the game's. Not tested in game. Made-up names only.
local tests = {}

local ME, MOB = "Player-1-0000AAAA", "Creature-0-1-0000CCCC"

-- One combat-log event, in the client's own order (16 places).
local function spell(sub, src, srcName, dst, dstName, id, name, amount)
    return { 1000, sub, false, src, srcName, 0, 0, dst, dstName, 0, 0, id, name, 1, amount, 0 }
end
local function swing(src, srcName, dst, dstName, amount)
    return { 1000, "SWING_DAMAGE", false, src, srcName, 0, 0, dst, dstName, 0, 0, amount }
end

-- opts.me: the player's id (nil: not known); opts.log: what setCombatLog takes.
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setVersion("0.1.0")
    if opts.log ~= nil then c.setCombatLog(opts.log) end
    if opts.me then c.setGuid("player", opts.me) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function log(c, ev) c.combatLog(unpack(ev, 1, 16)) end

local function said(c, rest)
    local before = #c.printed
    c.slashes[ns.id.slash](rest)
    local out = {}
    for i = before + 1, #c.printed do out[#out + 1] = c.printed[i] end
    return out
end

local function has(lines, text)
    for _, l in ipairs(lines) do
        if tostring(l):find(text, 1, true) then return true end
    end
    return false
end

-- One fight of ten seconds: you hit twice, the wolf bites you once.
local function fight(c)
    c.setCombat(true)
    log(c, spell("SPELL_DAMAGE", ME, "Zarkon", MOB, "Hollow Wolf", 78, "Heroic Strike", 50))
    c.advance(4, 4)
    log(c, swing(ME, "Zarkon", MOB, "Hollow Wolf", 70))
    log(c, spell("SPELL_DAMAGE", MOB, "Hollow Wolf", ME, "Zarkon", 17253, "Bite", 30))
    c.advance(6, 6)
    c.setCombat(false)
end

tests["fight log: a fight is listed by the slash word with what you dealt and took, and its spells by number"] = function(t)
    local c = boot({ me = ME })
    t.eq(said(c, "fights"), { ns.id.title .. ": " .. ns.Fights.NONE }, "before any fight: none")

    local before = #c.printed
    fight(c)
    local during = {}
    for i = before + 1, #c.printed do during[#during + 1] = c.printed[i] end
    t.ok(not has(during, "dealt"), "nothing about the fight is said until it is asked for")

    local out = said(c, "fights")
    t.eq(out[1], ns.id.title .. ": fights (1 kept, newest first):", "the list's head")
    t.eq(#out, 2, "one fight, one row")
    local row = tostring(out[2])
    t.eq(row:sub(1, #ns.id.title + 8), ns.id.title .. ": 1. 10s", "the first fight, ten seconds: " .. row)
    t.ok(row:find("dealt 120 in 2 hits", 1, true) ~= nil, "what you dealt: " .. row)
    t.ok(row:find("taken 30 in 1 hit", 1, true) ~= nil, "what you took: " .. row)

    local one = said(c, "fights 1")
    t.ok(has(one, "dealt: " .. ns.Fights.MELEE .. " 70 (1 hit), Heroic Strike 50 (1 hit)"), "your spells, biggest first")
    t.ok(has(one, "taken: Bite 30 (1 hit)"), "what hit you")
    t.ok(has(said(c, "fights 7"), "there is no fight 7; 1 is kept."), "a fight that is not kept is said so")
    t.eq(c.target and c.target() or nil, nil, "no target was picked for you")
end

tests["fight log: at your death what hit you is said, and the death word says it again"] = function(t)
    local c = boot({ me = ME })
    c.setCombat(true)
    log(c, spell("SPELL_DAMAGE", MOB, "Hollow Wolf", ME, "Zarkon", 17253, "Bite", 30))
    c.advance(2, 2)
    local before = #c.printed
    c.fire("PLAYER_DEAD")
    local out = {}
    for i = before + 1, #c.printed do out[#out + 1] = c.printed[i] end
    t.ok(has(out, "you died."), "the death is said at once")
    t.ok(has(out, "Bite 30 from Hollow Wolf"), "with what hit you")
    local again = said(c, "fights death")
    t.ok(has(again, "you died.") and has(again, "Bite 30 from Hollow Wolf"), "the word says the last death")
end

tests["fight log: unknown data: with no id for you nothing is counted as yours and it says why; with no log it says none can be kept"] = function(t)
    local c = boot()
    fight(c)
    local out = said(c, "fights")
    t.eq(out[1], ns.id.title .. ": fights (1 kept, newest first):", "the fight is still kept")
    t.ok(has(out, "dealt 0"), "nothing counted as dealt by you")
    t.ok(not has(out, "dealt 120"), "no damage guessed as yours")
    t.eq(out[#out], ns.id.title .. ": " .. ns.FightLog.NO_ME, "and why")

    local c2 = boot({ me = ME, log = "none" })
    fight(c2)
    t.eq(said(c2, "fights"), { ns.id.title .. ": " .. ns.FightLog.NO_LOG }, "no combat log: it says so")
    t.eq(said(c2, "fights death"), { ns.id.title .. ": " .. ns.FightLog.NO_LOG }, "the death word too")
    local before = #c2.printed
    c2.fire("PLAYER_DEAD")
    local dead = {}
    for i = before + 1, #c2.printed do dead[#dead + 1] = c2.printed[i] end
    t.ok(not has(dead, "you died."), "no death report made up without a log")
end

return tests
