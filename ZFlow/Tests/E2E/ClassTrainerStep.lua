local _, ns = ...
-- The class trainer step end to end (G44) on the whole add-on loaded on a
-- fake client: a level 10 warrior who has not learned Charge, Rend,
-- Thunder Clap and Hamstring. No trainer saved: words only. The trainer
-- window opened once saves the trainer, and the step then points at it.
-- Level not known: nothing. Made-up places. Look only: nothing trains.
local tests = {}

local NEW = { "Charge", "Rend", "Hamstring", "Thunder Clap" }
local OLD = { "Attack", "Battle Stance", "Heroic Strike", "Battle Shout", "Sunder Armor" }

local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setClass("WARRIOR")
    if opts.level ~= false then c.setLevel(10) end
    c.setPosition(1453, 0.5, 0.5)
    local id = 100
    for _, n in ipairs(NEW) do
        id = id + 1
        c.setSpellId(n, id)
        c.setSpell(id, { known = opts.allKnown == true })
    end
    for _, n in ipairs(OLD) do
        id = id + 1
        c.setSpellId(n, id)
        c.setSpell(id, { known = true })
    end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function api(addon)
    local a = addon.use("classTrainerStep")
    if type(a) ~= "table" or type(a.Step) ~= "function" then return nil end
    return a
end

tests["class trainer: new spells, none saved - words only, then saved and pointed at"] = function(t)
    local c, addon = boot()
    local a = api(addon)
    if not a then return t.ok(false, "no classTrainerStep") end
    local s = a.Step()
    t.ok(s ~= nil, "a step")
    t.eq(s and s.count, 4)
    t.eq(s and s.place, nil, "no trainer saved: no made-up place")
    local lines = a.Lines()
    t.ok(type(lines[1]) == "string" and lines[1]:find("4 new spells to learn", 1, true) ~= nil, "the count")
    -- The player opens the trainer window once.
    c.setPosition(1453, 0.66, 0.42)
    c.setTrainer({ npc = "Ander Germaine", services = { { name = "Charge", state = "available" } } })
    c.fire("TRAINER_SHOW")
    c.setTrainer(nil)
    c.fire("TRAINER_CLOSED")
    c.setPosition(1453, 0.5, 0.5)
    s = a.Step()
    t.eq(s and s.name, "Ander Germaine")
    t.eq(s and s.place, { map = 1453, x = 0.66, y = 0.42 })
    t.eq(a.Lines(), { "Visit your class trainer Ander Germaine: 4 new spells to learn." })
end

tests["class trainer: nothing new - no step"] = function(t)
    local _, addon = boot({ allKnown = true })
    local a = api(addon)
    if not a then return t.ok(false, "no classTrainerStep") end
    t.eq(a.Step(), nil)
    t.eq(a.Lines(), {})
end

tests["class trainer: level not known - nothing"] = function(t)
    local _, addon = boot({ level = false })
    local a = api(addon)
    if not a then return t.ok(false, "no classTrainerStep") end
    t.eq(a.Step(), nil)
end

tests["class trainer: setting off - no step"] = function(t)
    local _, addon = boot()
    local a = api(addon)
    if not a then return t.ok(false, "no classTrainerStep") end
    addon.settings:set("nav.classTrainerStep", false)
    t.eq(a.Step(), nil)
end

return tests
