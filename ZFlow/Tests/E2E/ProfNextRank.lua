local _, ns = ...
-- A2-09 (lead section 667): the next profession rank before the cap. When
-- what the trainer window showed for this cap (char learned.facts.tierSeen:
-- the skill and level the next rank asks for) is met, the trainer is a
-- step although the skill is not at its cap yet; a trainer show then marks
-- the visit, so the player is not sent again for this cap. Whole add-on
-- loaded on a fake client; made-up names and places. Not tested in game.
local tests = {}

local MAP, NPC = 1411, "Test Trainer"
local READINGS = "learned.facts.profSkill"

local function boot(level)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { learned = { places = { npcs = {
        [NPC] = { map = MAP, x = 0.6, y = 0.5, roles = { trainer = true }, trains = { Cooking = true },
                  factions = { Horde = true }, seen = 100, n = 1 } } } } })
    c.setSaved(ns.id.charDB, { learned = { facts = {
        profSkill = { Cooking = { line = 185, skill = 55, max = 75, at = 50 } },
        tierSeen = { Cooking = { cap = 75, skill = 50, level = 10, category = "available" } },
    } } })
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setMapSize(MAP, 1000, 500)
    c.setMapCont(MAP, 1); c.setFaction("Horde"); c.setLevel(level); c.setClock(1000)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

tests["prof next rank e2e: near the cap and ready: the trainer, then the visit marks it"] = function(t)
    local c, addon = boot(20)
    local N = addon.Nav
    local step = N.ProfStepFrom(c, addon.store)
    t.eq(type(step) == "table" and step.place, { cont = 1, map = MAP, x = 0.6, y = 0.5 }, "the trainer is the step")
    c.setTrainer({ profession = "Cooking", npc = NPC })
    c.fire("TRAINER_SHOW"); c.advance(2, 4)
    local readings = addon.store:get("char", READINGS)
    t.eq(readings and readings.Cooking and readings.Cooking.visitedAtCap, 75, "the visit at this cap is marked")
    local again, why = N.ProfStepFrom(c, addon.store)
    t.eq(again, nil, "not sent again")
    t.eq(why, "visited")
end

tests["prof next rank e2e: level below what the trainer said: no step, no visit"] = function(t)
    local c, addon = boot(9)
    local step, why = addon.Nav.ProfStepFrom(c, addon.store)
    t.eq(step, nil)
    t.eq(why, "not capped")
    c.setTrainer({ profession = "Cooking", npc = NPC })
    c.fire("TRAINER_SHOW"); c.advance(2, 4)
    local readings = addon.store:get("char", READINGS)
    t.eq(readings and readings.Cooking and readings.Cooking.visitedAtCap, nil, "no visit before it is ready")
end

return tests
