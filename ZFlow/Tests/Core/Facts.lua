-- S26 facts learned from the game (Core/Facts.lua; ported from legacy
-- Flow's Modules/Facts.lua). Hand-made trainer rows only.
local _, ns = ...

local F = ns.Facts
local tests = {}

tests["facts: a spell's key carries its rank when there is one"] = function(t)
    t.eq(F.SpellKey("Moonfire", "Rank 2"), "Moonfire (Rank 2)")
    t.eq(F.SpellKey("Moonfire", nil), "Moonfire")
    t.eq(F.SpellKey("Moonfire", ""), "Moonfire")
end

tests["facts: the lowest level and price seen win"] = function(t)
    local spells = {}
    t.eq(F.NoteSpell(spells, "DRUID", "Rake", nil, 24, 300), true)
    t.eq(F.NoteSpell(spells, "DRUID", "Rake", nil, 26, 300), false, "a higher level does not replace")
    t.eq(F.NoteSpell(spells, "DRUID", "Rake", nil, 24, 250), true, "a lower price is kept")
    t.eq(spells.DRUID.Rake, { name = "Rake", level = 24, cost = 250 })
    t.eq(F.NoteSpell(spells, "DRUID", "Rake", nil, 20, 400), true, "a lower level replaces")
    t.eq(spells.DRUID.Rake.level, 20)
    t.eq(F.NoteSpell(spells, "DRUID", "", nil, 1, 1), false)
    t.eq(F.NoteSpell(nil, "DRUID", "Rake", nil, 1, 1), false)
end

tests["facts: the first level a trainer teaches, the lowest seen"] = function(t)
    local first = {}
    t.eq(F.NoteFirst(first, "DRUID", "Rake", 24), true)
    t.eq(F.NoteFirst(first, "DRUID", "Rake", 26), false)
    t.eq(F.NoteFirst(first, "DRUID", "Rake", 22), true)
    t.eq(first.DRUID.Rake, 22)
    t.eq(F.NoteFirst(first, "DRUID", "Rake", 0), false, "no level, no fact")
    t.eq(F.NoteFirst(first, "DRUID", "Rake", "22"), false)
end

tests["facts: a trainer read keeps its lines, and first levels only for spells not known"] = function(t)
    local facts = {}
    local rows = {
        { name = "Rake", state = "available", level = 24, cost = 300 },
        { name = "Moonfire", rank = "Rank 3", state = "available", level = 16, cost = 200 },
        { name = "Thorns", rank = "Rank 1", state = "known", level = 6, cost = 100 },
        { name = "Shred", state = "unavailable", level = 22, cost = 500 },
    }
    local n = F.TrainerRead(facts, "DRUID", rows, 1000)
    t.eq(n, 6, "four lines, two first levels")
    t.eq(facts.first.DRUID, { Rake = 24, Shred = 22 }, "not Moonfire (a later rank), not Thorns (known)")
    t.eq(facts.firstAt.DRUID.Rake, 1000)
    t.eq(facts.spells.DRUID["Moonfire (Rank 3)"].level, 16)
    t.eq(F.TrainerRead(facts, "DRUID", rows, 2000), 0, "read again: nothing new")
end

tests["facts: imported facts are kept and merged"] = function(t)
    local facts = { spells = { DRUID = { Rake = { name = "Rake", level = 20, cost = 300 } } }, first = { DRUID = { Rake = 20 } },
        lacks = { DRUID = { ["Cure Poison"] = 14 } } }
    F.TrainerRead(facts, "DRUID", { { name = "Rake", state = "available", level = 24, cost = 300 } }, 1)
    t.eq(facts.spells.DRUID.Rake.level, 20)
    t.eq(facts.first.DRUID.Rake, 20)
    t.eq(facts.lacks.DRUID["Cure Poison"], 14)
end

tests["facts: the lines count and list the first levels"] = function(t)
    local lines = F.Lines({ spells = { DRUID = { a = {}, b = {} } }, first = { DRUID = { Rake = 24, Shred = 22 } },
        lacks = { DRUID = { x = 1 } } })
    t.eq(lines[1], "learned from the game: 2 trainer line(s), 2 first level(s), 1 spell(s) trainers did not have")
    t.eq(lines[2], "  DRUID, first taught at: Rake 24, Shred 22")
    t.eq(F.Lines(nil)[1], "learned from the game: 0 trainer line(s), 0 first level(s), 0 spell(s) trainers did not have")
end

local function start()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setClass("DRUID")
    c.setClock(5000)
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    local api = F.Declare(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api
end

tests["facts module: a class trainer visit is kept for the account"] = function(t)
    local k, c, api = start()
    c.setTrainer({ npc = "Bena", services = { { name = "Rake", state = "available", level = 24, cost = 300 } },
        filter = { available = true, unavailable = true, known = true } })
    c.fire("TRAINER_SHOW")
    t.eq(api.read(), 2)
    local saved = k.store:get("account", F.PATH)
    t.eq(saved.first.DRUID.Rake, 24)
    t.eq(saved.firstAt.DRUID.Rake, 5000)
end

tests["facts module: a profession trainer, or a class not read, keeps nothing"] = function(t)
    local k, c = start()
    c.setTrainer({ npc = "Kara", profession = "Alchemy", services = { { name = "Elixir", state = "available", level = 5 } } })
    c.fire("TRAINER_SHOW")
    t.eq(k.store:get("account", F.PATH), nil)
    c.setClass(nil)
    c.setTrainer({ npc = "Bena", services = { { name = "Rake", state = "available", level = 24 } } })
    c.fire("TRAINER_SHOW")
    t.eq(k.store:get("account", F.PATH), nil)
end

tests["facts module: /zflow facts says what was learned"] = function(t)
    local _, c = start()
    c.setTrainer({ npc = "Bena", services = { { name = "Rake", state = "available", level = 24, cost = 300 } } })
    c.fire("TRAINER_SHOW")
    local before = #c.printed
    c.slashes[ns.id.slash]("facts")
    t.ok(#c.printed > before)
    t.ok(c.printed[before + 1]:find("1 trainer line(s), 1 first level(s)", 1, true) ~= nil, c.printed[before + 1])
end

return tests
