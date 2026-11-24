local _, ns = ...
-- Core/Facts.lua through its real entry, on the whole add-on loaded on a
-- fake client: a class trainer's window (TRAINER_SHOW) is read into the
-- account's learned.facts, and /zflow facts says what was learned. A
-- profession trainer and a character whose class is not known are not
-- read. Made-up trainer and prices. Not tested in game.
local tests = {}

local WHEN = 1700000000

local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, {})
    c.setClass(opts.class)
    c.setLevel(12)
    c.setClock(WHEN)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function said(c, rest)
    local before = #c.printed
    c.slashes[ns.id.slash](rest)
    local out = {}
    for i = before + 1, #c.printed do out[#out + 1] = c.printed[i] end
    return out
end

local function facts(c)
    local a = c.saved(ns.id.accountDB)
    local l = type(a) == "table" and a.learned
    return type(l) == "table" and l.facts or nil
end

local function classRows()
    return {
        { name = "Charge", state = "available", level = 4, cost = 10 },
        { name = "Battle Shout", rank = "Rank 2", state = "available", level = 12, cost = 100 },
        { name = "Heroic Strike", rank = "Rank 1", state = "known", level = 1, cost = 0 },
    }
end

local function open(c, trainer)
    c.setTrainer(trainer)
    c.fire("TRAINER_SHOW")
end

local function countLine(spells, first)
    return ns.id.title .. ": learned from the game: " .. spells .. " trainer line(s), " .. first
        .. " first level(s), 0 spell(s) trainers did not have"
end

tests["trainer facts: a class trainer's window is learned and /zflow facts says it"] = function(t)
    local c = boot({ class = "WARRIOR" })
    t.eq(said(c, "facts")[1], countLine(0, 0), "nothing learned before a trainer")
    open(c, { npc = "Test Drillmaster", services = classRows() })
    local f = facts(c)
    t.eq(f and f.first and f.first.WARRIOR, { Charge = 4 }, "the first level of a spell this character lacks")
    t.eq(f and f.firstAt and f.firstAt.WARRIOR and f.firstAt.WARRIOR.Charge, WHEN)
    t.eq(f and f.spells and f.spells.WARRIOR and f.spells.WARRIOR["Battle Shout (Rank 2)"],
        { name = "Battle Shout", rank = "Rank 2", level = 12, cost = 100 })
    local lines = said(c, "facts")
    t.eq(lines[1], countLine(3, 1))
    t.eq(lines[2], ns.id.title .. ":   WARRIOR, first taught at: Charge 4")
    t.eq(#lines, 2)
end

tests["trainer facts: learned facts survive a reload"] = function(t)
    local c = boot({ class = "WARRIOR" })
    open(c, { npc = "Test Drillmaster", services = classRows() })
    local again = boot({ class = "WARRIOR", account = c.saved(ns.id.accountDB) })
    t.eq(said(again, "facts")[2], ns.id.title .. ":   WARRIOR, first taught at: Charge 4")
end

tests["trainer facts: a profession trainer is not read"] = function(t)
    local c = boot({ class = "WARRIOR" })
    open(c, { profession = "Tailoring", npc = "Test Tailor", services = classRows() })
    t.eq(facts(c), nil, "nothing saved")
    t.eq(said(c, "facts"), { countLine(0, 0) }, "only the count line")
end

tests["trainer facts: a class the game does not give leaves the facts unread"] = function(t)
    local c = boot({ class = nil })
    open(c, { npc = "Test Drillmaster", services = classRows() })
    t.eq(facts(c), nil, "nothing saved for an unknown class")
    t.eq(said(c, "facts"), { countLine(0, 0) })
end

return tests
