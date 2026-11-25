local _, ns = ...
-- The owner's report: "I don't see the profession arrow. I do see all the
-- profession wording." A profession step in words (a trainer step that
-- names no trainer, a bank step) had no place, so the profession arrow had
-- nothing to point at. Through the whole add-on, loaded the way the game
-- loads it (ns.offline.addon) on a fake client, with a stand-in for the
-- planner's live read (as Tests/E2E/ProfFeedNeedle.lua):
--   a trainer of that profession saved: the same words, the arrow, and how
--     far it is;
--   a fresh account with the player's own Questie (a made-up one, as
--     Tests/E2E/KnowTrainerQuests.lua): the same, from Questie's place, and
--     Questie's NPCs are gone through once, not on every update;
--   nothing known, or Questie not there: no arrow, the words stay and a
--     plain line says no place is known.
-- Made-up names and places only. Look only. Not tested in game.
--
-- Red before the code: no Questie read, and a placed step said no distance.
local tests = {}
local N = ns.Nav

local LEARN = { kind = "learn_recipe", text = "Learn a Cooking recipe at a trainer" }
local BANK = { kind = "take_bank", text = "Take 4 Test Fish from your bank" }
local AREA, COOK, THEIR_COOK, BANKER = 14, 7101, 7102, 7103

-- A stand-in for Questie's two modules. state.scans counts the times its
-- NPCs were gone through for profession places.
local function questie(state)
    local npcs = {
        [COOK] = { name = "Cook Test", subName = "Cooking Trainer", friendlyToFaction = "H",
                   spawns = { [AREA] = { { 60, 50 } } } },
        [THEIR_COOK] = { name = "Their Cook", subName = "Cooking Trainer", friendlyToFaction = "A",
                         spawns = { [AREA] = { { 51, 50 } } } },
        [BANKER] = { name = "Banker Test", npcFlags = 256, friendlyToFaction = "AH",
                     spawns = { [AREA] = { { 50, 70 } } } },
    }
    local db = { QuestPointers = {}, NPCPointers = {} }
    for id in pairs(npcs) do db.NPCPointers[id] = true end
    function db.QueryQuestSingle() return nil end
    function db.QueryNPCSingle(id, field)
        if id == COOK and field == "npcFlags" then state.scans = (state.scans or 0) + 1 end
        return npcs[id] and npcs[id][field]
    end
    local zones = {}
    function zones.GetUiMapIdByAreaId(a) return ({ [AREA] = 1411 })[a] end
    return db, zones
end

-- opts: npcs (the account's learned.places.npcs), step (the plan's one
-- Cooking step; LEARN when not given), state (a table: the made-up Questie
-- is there and counts into it).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    local account = { layout = { arrowIntroSeen = true } }
    if opts.npcs then account.learned = { places = { npcs = opts.npcs } } end
    c.setSaved(ns.id.accountDB, account)
    c.setSaved(ns.id.charDB, { learned = { facts = { profSkill = { Cooking = { skill = 40, max = 75 } } } } })
    c.setScreen(1024, 768)
    c.setZone(1, 1411)
    c.setFacing(0)
    c.setFaction("Horde")
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    c.setMapCont(1411, 1)
    c.setProfessions({ "Cooking" })
    if opts.combat then c.setCombat(true) end
    if opts.state then
        local db, zones = questie(opts.state)
        c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    end
    local addon = ns.offline.addon(c)
    local step = opts.step or LEARN
    addon.profPlan = { plan = function(prof)
        if prof == "Cooking" then return { step } end
        return {}
    end }
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function noPlaceLine(kind)
    local W = N.ProfFeed and N.ProfFeed.NO_PLACE
    if type(W) ~= "table" or type(W[kind]) ~= "string" then return nil end
    return W[kind]:format("Cooking")
end

-- The profession arrow is up with the step's words first and a line that
-- says how far (yards), and its needle is drawn.
local function pointsAt(t, c, text, yards, what)
    local p = c.arrows[2]
    t.eq(p and p.shown, true, what .. ": the profession arrow is up")
    local lines = p and type(p.lines) == "table" and p.lines or {}
    t.eq(lines[1], text, what .. ": the step's own words first")
    t.eq(#lines, 2, what .. ": then one line more")
    t.ok(type(lines[2]) == "string" and lines[2]:find(yards .. " yd", 1, true) ~= nil,
        what .. ": it says how far: " .. tostring(lines[2]))
    c.advance(0.1, 2)
    t.ok(p and type(p.drawn) == "table" and p.drawn.body ~= 0, what .. ": the needle is drawn")
end

tests["prof place: a trainer step in words with a saved trainer shows the arrow, its words and how far"] = function(t)
    local c, addon = start({ npcs = { ["Cook Saved"] = { map = 1411, x = 0.6, y = 0.5, roles = { trainer = true },
        trains = { Cooking = true }, factions = { Horde = true } } } })
    local before = addon.problems:count()
    pointsAt(t, c, LEARN.text, 100, "a saved trainer 100 yards east")
    t.eq(addon.problems:count(), before, "no problem raised")
end

tests["prof place: a fresh account with Questie shows the arrow from Questie's trainer, scanned once"] = function(t)
    local state = {}
    local c = start({ state = state })
    pointsAt(t, c, LEARN.text, 100, "Questie's trainer of the player's faction")
    c.advance(30, 120)
    t.eq(state.scans, 1, "Questie's NPCs were gone through once, not on every update")
    t.eq(c.arrows[2].lines and c.arrows[2].lines[1], LEARN.text, "and the arrow still has its step")
end

-- Lead section 564: Questie is not gone through in combat; it is picked up
-- when combat ends.
tests["prof place: Questie is not read in combat, and is read once combat ends"] = function(t)
    local state = {}
    local c = start({ state = state, combat = true })
    c.advance(30, 120)
    t.eq(state.scans, nil, "in combat: Questie's NPCs are not gone through")
    c.setCombat(false)
    c.advance(5, 20)
    t.eq(state.scans, 1, "combat over: gone through once")
    pointsAt(t, c, LEARN.text, 100, "Questie's trainer, after combat")
end

tests["prof place: a bank step on a fresh account points at Questie's banker"] = function(t)
    local state = {}
    local c = start({ state = state, step = BANK })
    -- The banker stands at 0.5, 0.7 of a map 500 yards tall: 100 yards south.
    pointsAt(t, c, BANK.text, 100, "Questie's banker")
    t.eq(state.scans, 1)
end

tests["prof place: a saved trainer comes before Questie's"] = function(t)
    local state = {}
    local c = start({ state = state, npcs = { ["Cook Saved"] = { map = 1411, x = 0.8, y = 0.5,
        roles = { trainer = true }, trains = { Cooking = true }, factions = { Horde = true } } } })
    pointsAt(t, c, LEARN.text, 300, "the saved trainer 300 yards east, not Questie's at 100")
    t.eq(state.scans, nil, "and Questie was not gone through at all")
end

tests["prof place: with nothing known and no Questie there is no arrow, the words stay, a line says so"] = function(t)
    local c, addon = start()
    local before = addon.problems:count()
    local p = c.arrows[2]
    t.eq(p and p.shown, true, "the profession frame is up for its words")
    t.ok(noPlaceLine("trainer") ~= nil, "the feed has a line for no trainer place known")
    t.eq(p and p.lines, { LEARN.text, noPlaceLine("trainer") }, "the step's words, then the plain line")
    c.advance(0.1, 2)
    t.eq(p and type(p.drawn) == "table" and p.drawn.body, 0, "no needle: no place is made up")
    t.eq(addon.problems:count(), before, "no problem raised")
end

tests["prof place: a trainer of another profession, or of the other faction, is not pointed at"] = function(t)
    local c = start({ npcs = {
        ["Tailor Test"] = { map = 1411, x = 0.6, y = 0.5, roles = { trainer = true },
            trains = { Tailoring = true }, factions = { Horde = true } },
        ["Their Cook"] = { map = 1411, x = 0.4, y = 0.5, roles = { trainer = true },
            trains = { Cooking = true }, factions = { Alliance = true } },
    } })
    local p = c.arrows[2]
    t.eq(p and p.lines, { LEARN.text, noPlaceLine("trainer") }, "words and the plain line")
    c.advance(0.1, 2)
    t.eq(p and type(p.drawn) == "table" and p.drawn.body, 0, "no needle")
end

return tests
