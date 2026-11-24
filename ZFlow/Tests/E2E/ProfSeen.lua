local _, ns = ...
-- What the player's own client shows about professions, saved
-- (Nav/ProfSeen.lua), on the whole add-on loaded on a fake client, through
-- the real entry: the profession window's TRADE_SKILL_LIST_UPDATE saves the
-- skill reading; a TRAINER_SHOW saves the trainer and marks a visit at the
-- cap. It only reads: nothing crafts, trains or buys. Made-up names; not
-- tested in game.
local tests = {}

local MINING, MAP, NPC = 186, 1411, "Test Trainer"
local READINGS, NPCS = "learned.facts.profSkill", "learned.places.npcs"

-- opts.char: the character saved table.
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setZone(1, MAP); c.setPosition(MAP, 0.4, 0.6); c.setFaction("Horde")
    c.setClock(1000)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function last(addon)
    local api = addon.use("profSeen")
    if type(api) ~= "table" or type(api.Last) ~= "function" then return {} end
    return api.Last() or {}
end

local function nothingActs(t, c)
    t.eq(#c.crafts, 0, "nothing is crafted")
    t.eq(#c.soldSlots, 0, "nothing is sold")
end

tests["prof seen: the profession window saves the skill reading"] = function(t)
    local c, addon = boot()
    c.setRecipes({ profession = MINING, name = "Mining", skill = 50, max = 75, recipes = {} })
    c.fire("TRADE_SKILL_LIST_UPDATE"); c.advance(2, 4)
    local saved = addon.store:get("char", READINGS)
    t.eq(saved and saved.Mining, { line = MINING, skill = 50, max = 75, at = 1000 })
    t.eq(last(addon).ok, true, "the reading is reported saved")
    nothingActs(t, c)
end

tests["prof seen: a trainer show saves the trainer and marks the visit at the cap"] = function(t)
    local c, addon = boot({ char = { learned = { facts = { profSkill = {
        Mining = { line = MINING, skill = 75, max = 75, at = 900 } } } } } })
    c.setTrainer({ profession = "Mining", npc = NPC })
    c.fire("TRAINER_SHOW"); c.advance(2, 4)
    local npcs = addon.store:get("account", NPCS)
    local e = npcs and npcs[NPC]
    t.ok(type(e) == "table", "the trainer is saved")
    if type(e) ~= "table" then return end
    t.eq(e.map, MAP); t.eq(e.x, 0.4); t.eq(e.y, 0.6)
    t.eq(e.roles, { trainer = true })
    t.eq(e.trains, { Mining = true })
    t.eq(e.factions, { Horde = true })
    t.eq(e.seen, 1000); t.eq(e.n, 1)
    local readings = addon.store:get("char", READINGS)
    t.eq(readings and readings.Mining and readings.Mining.visitedAtCap, 75, "the visit at this cap is marked")
    t.eq(last(addon).visited, true)
    nothingActs(t, c)
end

tests["prof seen: unknown data writes nothing"] = function(t)
    local c, addon = boot()
    c.setRecipes({ profession = MINING, name = "Mining", skill = 50, max = 0, recipes = {} })
    c.fire("TRADE_SKILL_LIST_UPDATE"); c.advance(2, 4)
    local saved = addon.store:get("char", READINGS)
    t.eq(saved and saved.Mining, nil, "a max of 0 is not a reading")
    t.eq(last(addon).ok, false)
    c.setTrainer({ npc = NPC })
    c.fire("TRAINER_SHOW"); c.advance(2, 4)
    local npcs = addon.store:get("account", NPCS)
    t.eq(npcs and npcs[NPC], nil, "a trainer whose profession is not known is not saved")
    t.eq(last(addon).reason, "the trainer's profession is not known")
    nothingActs(t, c)
end

return tests
