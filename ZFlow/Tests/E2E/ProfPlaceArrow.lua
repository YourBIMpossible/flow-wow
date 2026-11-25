local _, ns = ...
-- The owner's report: "I don't see the profession arrow. I do see all the
-- profession wording." A profession step in words (a trainer step that
-- names no trainer) had no place, so the profession arrow had nothing to
-- point at. Through the whole add-on, loaded the way the game loads it
-- (ns.offline.addon) on a fake client, with a stand-in for the planner's
-- live read (as Tests/E2E/ProfFeedNeedle.lua): with a trainer of that
-- profession saved, the same words now come with the arrow; with none
-- saved there is no arrow, the words stay and a plain line says no place
-- is known. Made-up names and places only. Look only. Not tested in game.
--
-- Red before the code: the step stays in words, so no needle is drawn, and
-- no line says that no place is known.
local tests = {}
local N = ns.Nav

local LEARN = { kind = "learn_recipe", text = "Learn a Cooking recipe at a trainer" }

-- npcs: the account's learned.places.npcs, or nil for none saved.
local function start(npcs)
    local c = ns.make.fakeClient()
    local account = { layout = { arrowIntroSeen = true } }
    if npcs then account.learned = { places = { npcs = npcs } } end
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
    local addon = ns.offline.addon(c)
    addon.profPlan = { plan = function(prof)
        if prof == "Cooking" then return { LEARN } end
        return {}
    end }
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function noPlaceLine()
    local W = N.ProfFeed and N.ProfFeed.NO_PLACE
    if type(W) ~= "table" or type(W.trainer) ~= "string" then return nil end
    return W.trainer:format("Cooking")
end

tests["prof place: a trainer step in words with a known trainer shows the profession arrow, words kept"] = function(t)
    local c, addon = start({ ["Cook Test"] = { map = 1411, x = 0.6, y = 0.5, roles = { trainer = true },
        trains = { Cooking = true }, factions = { Horde = true } } })
    local before = addon.problems:count()
    local p = c.arrows[2]
    t.eq(p and p.shown, true, "the profession arrow is up")
    t.eq(p and p.lines, { LEARN.text }, "with the step's own words, and nothing taken away or made up")
    c.advance(0.1, 2)
    t.ok(p and type(p.drawn) == "table" and p.drawn.body ~= 0, "the needle is drawn: it has a place to point at")
    t.eq(addon.problems:count(), before, "no problem raised")
end

tests["prof place: with no trainer known there is no arrow, the words stay, and a line says so"] = function(t)
    local c, addon = start(nil)
    local before = addon.problems:count()
    local p = c.arrows[2]
    t.eq(p and p.shown, true, "the profession frame is up for its words")
    t.eq(p and p.lines and p.lines[1], LEARN.text, "the step's own words first")
    t.ok(noPlaceLine() ~= nil, "the feed has a line for no trainer place known")
    t.eq(p and p.lines, { LEARN.text, noPlaceLine() }, "then the plain line: no place is known")
    c.advance(0.1, 2)
    t.eq(p and type(p.drawn) == "table" and p.drawn.body, 0, "no needle: no place is made up")
    t.eq(addon.problems:count(), before, "no problem raised")
end

tests["prof place: a trainer of another profession, or of the other faction, is not pointed at"] = function(t)
    local c = start({
        ["Tailor Test"] = { map = 1411, x = 0.6, y = 0.5, roles = { trainer = true },
            trains = { Tailoring = true }, factions = { Horde = true } },
        ["Their Cook"] = { map = 1411, x = 0.4, y = 0.5, roles = { trainer = true },
            trains = { Cooking = true }, factions = { Alliance = true } },
    })
    local p = c.arrows[2]
    t.eq(p and p.lines and p.lines[1], LEARN.text)
    c.advance(0.1, 2)
    t.eq(p and type(p.drawn) == "table" and p.drawn.body, 0, "no needle")
end

return tests
