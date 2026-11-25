local _, ns = ...

-- End to end (P-TRIP, S39/S43/S40): the whole add-on on a fake client. The
-- quest route from the quest log and a made-up Questie, listed by the slash
-- word and walked by the quest arrow; spots learned from the player's own
-- play when Questie is not there; the dungeon run planned from the Dungeon
-- Quests window. Made-up quests and places; not tested in game.

local tests = {}

local MAP = 1436

local function questie()
    local quests = {
        [401] = { ObjectiveData = { { Type = "monster", Id = 9101 } } },
        [402] = { ObjectiveData = { { Type = "monster", Id = 9102 } } },
        [403] = { ObjectiveData = {}, Finisher = { NPC = { 9103 } } },
    }
    local npcs = {
        [9101] = { name = "Boar", spawns = { [40] = { { 60, 50 } } } },
        [9102] = { name = "Herb Thing", spawns = { [40] = { { 20, 50 } } } },
        [9103] = { name = "Smith", spawns = { [40] = { { 55, 50 } } } },
    }
    local db = {}
    function db.GetQuest(id) return quests[id] end
    function db.GetNPC(id) return npcs[id] end
    local zones = {}
    function zones.GetUiMapIdByAreaId(area) return ({ [40] = MAP })[area] end
    return db, zones
end

local LOG = {
    { id = 401, title = "Boars", objectives = { { text = "Boars slain: 0/4" } } },
    { id = 402, title = "Herbs", objectives = { { text = "Herbs: 0/5" } } },
    { id = 403, title = "Bandages", complete = true, objectives = { { text = "Linen: 4/4", done = true } } },
}

local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, opts.char or {})
    if opts.bags then c.setBags(opts.bags) end
    c.setClass("WARRIOR"); c.setFaction("Alliance"); c.setLevel(opts.level or 18)
    if opts.skills then c.setSkillRanks(opts.skills); c.setMoney(500000) end
    c.setZone(1, MAP); c.setPosition(MAP, opts.x or 0.5, opts.y or 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 0)
    if opts.questie ~= false then
        local db, zones = questie()
        c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    end
    c.setQuestLog(opts.log or LOG)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

local function said(c, text)
    for _, line in ipairs(c.printed or {}) do
        if tostring(line):find(text, 1, true) then return line end
    end
    return nil
end

local function first(c)
    local a = c.arrows[1]
    return a and a.lines and a.lines[1]
end

tests["trip route: the slash word lists the quest route in order and the arrow walks it"] = function(t)
    local c = boot()
    -- A1-24 (lead sections 697 and 739): before the word the arrow already
    -- walks the route planned by itself, in the quest arrow's own slot.
    t.eq(first(c), "Bandages", "before the word: the route planned by itself")
    c.slashes[ns.id.slash]("route")
    c.advance(1, 5)
    local one = said(c, "1. Bandages")
    t.ok(one ~= nil and one:find("Smith", 1, true) ~= nil and one:find("50 yd", 1, true) ~= nil, tostring(one))
    t.ok(said(c, "2. Boars") ~= nil, "Boars second")
    t.ok(said(c, "3. Herbs") ~= nil, "Herbs last")
    t.eq(first(c), "Bandages", "the arrow points at the route's first stop")
    c.slashes[ns.id.slash]("route skip")
    c.advance(1, 5)
    t.eq(first(c), "Boars", "skipped to the next stop")
    c.slashes[ns.id.slash]("route off")
    c.advance(1, 5)
    t.eq(first(c), "Boars", "the quest arrow's own pick again")
end

tests["trip route: a stop whose objective is done drops out by itself"] = function(t)
    local c = boot()
    c.slashes[ns.id.slash]("route")
    c.slashes[ns.id.slash]("route skip")
    c.advance(1, 5)
    t.eq(first(c), "Boars")
    c.setQuestLog({ { id = 401, title = "Boars", objectives = { { text = "Boars slain: 4/4", done = true } } },
                    LOG[2], LOG[3] })
    c.advance(5, 60)
    t.eq(first(c), "Herbs", "the done objective is no longer a stop")
end

tests["trip route: without Questie, a spot learned where the count went up is used"] = function(t)
    local log = { { id = 501, title = "Rats", objectives = { { text = "Rats slain: 0/5" } } } }
    local c, addon = boot({ questie = false, log = log, x = 0.3, y = 0.7 })
    c.setQuestLog({ { id = 501, title = "Rats", objectives = { { text = "Rats slain: 1/5" } } } })
    c.advance(3, 20)
    local book = addon.store:get("account", ns.Nav.QuestSpots.PATH)
    local spot = type(book) == "table" and book[501] and book[501][1] and book[501][1][1]
    t.eq(spot and { spot.map, spot.x, spot.y }, { MAP, 0.3, 0.7 }, "learned where the player stood")
    c.setPosition(MAP, 0.5, 0.5)
    c.advance(1, 5)
    c.slashes[ns.id.slash]("route")
    c.advance(1, 5)
    local line = said(c, "1. Rats")
    t.ok(line ~= nil and line:find("283 yd", 1, true) ~= nil, tostring(line))
    t.eq(first(c), "Rats")
end

tests["trip route: the setting rows are there"] = function(t)
    local _, addon = boot()
    local route = addon.settings:row(ns.Nav.TripRoute.SETTING)
    local learn = addon.settings:row(ns.Nav.QuestSpots.SETTING)
    t.eq(route and route.group, "travel.route")
    t.eq(learn and learn.group, "travel.route")
    t.eq(route and route.default, true)
    t.eq(learn and learn.default, true)
end

-- Lead section 372: Live checks a turn-in stop on the route again; one no
-- longer ready leaves the route as a held line and comes back when ready.
tests["trip route: a turn-in no longer ready is held with its reason and comes back"] = function(t)
    local c = boot()
    c.slashes[ns.id.slash]("route")
    c.advance(1, 5)
    t.eq(first(c), "Bandages")
    c.setQuestLog({ LOG[1], LOG[2], { id = 403, title = "Bandages", objectives = { { text = "Linen: 3/4" } } } })
    c.advance(5, 60)
    t.eq(first(c), "Boars", "the held turn-in is not walked")
    c.slashes[ns.id.slash]("route")
    c.advance(1, 5)
    local T = ns.Nav.TripRoute
    local held = said(c, T.HELD_LINE:format(T.HELD_NOT_COMPLETE))
    t.ok(held ~= nil and held:find("Bandages", 1, true) ~= nil, tostring(held))
    c.setQuestLog(LOG)
    c.advance(5, 60)
    t.eq(first(c), "Bandages", "ready again: back on the route")
end

-- S40: the dungeon run from the Dungeon Quests window.
local DM = 1581

local function dungeonQuestie()
    local quests = {
        [101] = { Id = 101, name = "Red Silk", level = 18, requiredLevel = 14, zoneOrSort = DM,
            Starts = { NPC = { 501 } } },
    }
    local npcs = { [501] = { name = "Gryan", friendlyToFaction = "A", spawns = { [40] = { { 30, 40 } } } } }
    local db = { QuestPointers = { [101] = true } }
    function db.GetQuest(id) return quests[id] end
    function db.GetNPC(id) return npcs[id] end
    function db.QueryQuestSingle(id, field)
        local q = quests[id]
        if not q then return nil end
        if field == "questLevel" then return q.level end
        return q[field]
    end
    local zones = {}
    function zones.GetUiMapIdByAreaId(area) return ({ [40] = MAP })[area] end
    function zones:GetDungeons()
        return { [DM] = { "The Deadmines", {}, nil, { { 40, 42.5, 71.8 } } } }
    end
    return db, zones
end

local function bootDungeon()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setRaceId(1); c.setFaction("Alliance"); c.setLevel(18)
    c.setQuestDone(101, false)
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 0)
    local db, zones = dungeonQuestie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    c.setQuestLog({})
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    c.slashes[ns.id.slash]("dungeons")
    c.advance(2, 20)
    return c, addon
end

tests["dungeon run: R.Run gives the givers to pick up from, then the entrance"] = function(t)
    local c = bootDungeon()
    local R = ns.DungeonRead
    local st = R.Start(c)
    while st.state == "building" do R.Step(st, c, R.SLICE) end
    local run, why = R.Run(st, c, DM)
    t.ok(run ~= nil, why and why[1])
    local steps = run and run.steps or {}
    t.eq(#steps, 2)
    t.eq(steps[1] and steps[1].kind, "giver")
    t.ok(steps[1] and steps[1].label:find("Red Silk", 1, true) ~= nil, steps[1] and steps[1].label)
    t.eq(steps[1] and steps[1].detail, "Gryan")
    t.eq(steps[1] and steps[1].place, { map = MAP, x = 0.3, y = 0.4 })
    t.eq(steps[2] and steps[2].kind, "entrance")
    t.eq(steps[2] and steps[2].place, { map = MAP, x = 0.425, y = 0.718 })
    local none, noWhy = R.Run(st, c, 99999)
    t.eq(none, nil)
    t.ok(type(noWhy) == "table" and type(noWhy[1]) == "string", "why lines")
end

tests["dungeon run: Plan the run hands the run to the arrow, which walks it"] = function(t)
    local c = bootDungeon()
    t.eq(c.kitSelect("dungeons", "dungeons", 1), true)
    t.eq(c.kitClick("dungeons", "planRun"), true, "the button is there and live")
    c.advance(1, 5)
    local line = first(c)
    t.ok(line ~= nil and line:find("Red Silk", 1, true) ~= nil, tostring(line))
    c.setPosition(MAP, 0.3, 0.4)
    c.advance(2, 20)
    t.eq(first(c), "The Deadmines", "at the giver: on to the entrance")
end

-- S43 (lead dispatch section 391 item 4): the route step says how many are still needed.
local function paws(text, done)
    return { { id = 401, title = "Paws", objectives = { { text = text, done = done } } } }
end

local function lineWith(c, text)
    local a = c.arrows[1]
    for _, l in ipairs(a and a.lines or {}) do
        if tostring(l):find(text, 1, true) then return l end
    end
    return nil
end

tests["trip route: the step says how many are still needed, live from the quest log"] = function(t)
    local c = boot({ log = paws("Gnoll Paw: 4/8") })
    c.slashes[ns.id.slash]("route")
    c.advance(1, 5)
    t.ok(said(c, "1. Paws - You still need 4 of Gnoll Paw.") ~= nil, "the route list")
    t.eq(first(c), "Paws")
    t.eq(lineWith(c, "You still need"), "You still need 4 of Gnoll Paw.", "under the arrow")
    c.setQuestLog(paws("Gnoll Paw: 7/8"))
    c.advance(3, 30)
    t.eq(lineWith(c, "You still need"), "You still need 1 Gnoll Paw.", "one left: singular, read again")
    c.setQuestLog(paws("Gnoll Paw: 8/8", true))
    c.advance(3, 30)
    t.eq(lineWith(c, "You still need"), nil, "done: no need line")
end

tests["trip route: an unreadable count says no number at all"] = function(t)
    local c = boot({ log = paws(nil) })
    c.slashes[ns.id.slash]("route")
    c.advance(1, 5)
    t.eq(first(c), "Paws")
    t.eq(lineWith(c, "need"), nil, "no need line when the count cannot be read")
    for _, line in ipairs(c.printed or {}) do
        t.ok(not tostring(line):find("still need", 1, true), tostring(line))
    end
end

-- FLOW-PARITY A2-11: town stops. Full bags put a sell stop at the vendor
-- this character has seen; a seen inn near most of the quests puts a
-- set-hearthstone stop. The arrow walks to them; the player sells and sets
-- the home. Nothing is sold or set for them. Made-up places.
local TOWN = { learned = { places = { services = {
    v = { name = "Bread Seller", map = MAP, x = 0.52, y = 0.5, kinds = { vendor = true } },
    i = { name = "Inn Keeper", map = MAP, x = 0.4, y = 0.5, kinds = { innkeeper = true } },
} } } }

tests["trip route: full bags and a seen inn add sell and hearthstone stops the player walks to"] = function(t)
    local c = boot({ char = TOWN, bags = { { bag = 0, free = 0, total = 16 } } })
    c.slashes[ns.id.slash]("route")
    c.advance(1, 5)
    t.ok(said(c, "Bags full: sell at Bread Seller") ~= nil, "the sell stop is in the route")
    t.ok(said(c, "Set hearthstone: Inn Keeper") ~= nil, "the hearthstone stop is in the route")
    t.eq(first(c), "Bags full: sell at Bread Seller", "the nearest stop: the vendor")
    -- Twin's plan note 1 (lead section 552): the stop stays until the bags have
    -- room (Tests/E2E/TripRouteTownDone.lua); selling is the player's.
    c.setPosition(MAP, 0.52, 0.5); c.advance(2, 5)
    t.eq(first(c), "Bags full: sell at Bread Seller", "at the vendor with full bags the stop stays")
    c.setBags({ { bag = 0, free = 10, total = 16 } }); c.advance(2, 5)
    t.ok(first(c) ~= "Bags full: sell at Bread Seller", "sold: the stop is done")
end

tests["trip route: room in the bags, or town stops off: no sell stop"] = function(t)
    local c = boot({ char = TOWN, bags = { { bag = 0, free = 10, total = 16 } } })
    c.slashes[ns.id.slash]("route"); c.advance(1, 5)
    t.eq(said(c, "sell at"), nil, "bags not full: no sell stop")
    local addon
    c, addon = boot({ char = TOWN, bags = { { bag = 0, free = 0, total = 16 } } })
    addon.settings:set("quest.routeTown", false)
    c.slashes[ns.id.slash]("route"); c.advance(1, 5)
    t.eq(said(c, "sell at"), nil, "setting off: no sell stop")
    t.eq(said(c, "Set hearthstone"), nil, "setting off: no hearthstone stop")
end

tests["trip route: town stops are pure and guess no place"] = function(t)
    local T = ns.Nav.TripRoute
    local v = { name = "Bread Seller", map = MAP, x = 0.5, y = 0.5 }
    t.eq(T.FreeSlots({ { free = 2 }, { free = 5, family = 8 }, { free = 1, family = 0 } }), 3, "special bags not counted")
    t.eq(T.FreeSlots(nil), nil)
    local full = T.Town({ map = MAP, free = 1, vendor = v })
    t.eq(full[1].label, "Bags full: sell at Bread Seller"); t.eq(full[1].must, true)
    local near = T.Town({ map = MAP, free = 3, vendor = v })
    t.eq(near[1].label, "Sell at Bread Seller (bags nearly full)"); t.eq(near[1].must, nil, "nearly full: only when on the way")
    t.eq(#T.Town({ map = MAP, free = 4, vendor = v }), 0)
    t.eq(#T.Town({ map = MAP, free = nil, vendor = v }), 0, "bags not read: no stop")
    t.eq(#T.Town({ map = MAP + 1, free = 0, vendor = v }), 0, "vendor on another map: no stop")
    t.eq(T.Town({ map = MAP, free = 0, vendor = { map = MAP, x = 0.5, y = 0.5 } })[1].label, "Bags full: sell at a vendor")
    t.eq(T.Town({ map = MAP, inn = { map = MAP, x = 0.4, y = 0.5, name = "50%s" } })[1].label, "Set hearthstone at this inn")
end

-- FLOW-PARITY A2-08: at level 40 without riding, the riding trainer is a
-- route stop when one was seen on this map. Not seen, its place stays
-- unknown: no stop, a line under the route says so. Nothing is trained.
local NO_RIDING = { Defense = { rank = 200, max = 200 } }

tests["trip route: a riding trainer not seen yet is said under the route, with no place made up"] = function(t)
    local c = boot({ level = 40, skills = NO_RIDING })
    c.slashes[ns.id.slash]("route"); c.advance(1, 5)
    t.ok(said(c, "Riding trainer - place not seen yet: ask a city guard for the riding trainer") ~= nil,
        "the unknown place is said")
    t.eq(said(c, ". Riding trainer"), nil, "no numbered stop for it")
end

tests["trip route: a riding trainer seen on this map is a stop of the route"] = function(t)
    local c = boot({ level = 40, skills = NO_RIDING, x = 0.45 })
    c.setTrainer({ npc = "Test Rider", services = {
        { name = "Horse Riding", rank = "Apprentice", state = "available", cost = 200000, level = 40 } } })
    c.fire("TRAINER_SHOW"); c.setTrainer(nil); c.fire("TRAINER_CLOSED")
    c.setPosition(MAP, 0.5, 0.5); c.advance(2, 5)
    c.slashes[ns.id.slash]("route"); c.advance(1, 5)
    t.ok(said(c, "Riding trainer: Test Rider - " .. ns.Nav.TripRoute.RIDING_DETAIL) ~= nil, "the trainer is a stop")
    local T = ns.Nav.TripRoute
    local _, aside = T.Town({ map = MAP, riding = { label = "Riding trainer", name = "Far Rider" } })
    t.eq(aside[1].why, "not on this map: Far Rider")
end

-- Twin, lead section 545: the town stops row gates four stops (sell, repair,
-- riding trainer, set hearthstone); its label and help name all four. Red on
-- 3e9e8b77: the label names two.
tests["trip route: the town stops row names all four stops it switches"] = function(t)
    local _, addon = boot()
    local row = addon.settings:row(ns.Nav.TripRoute.TOWN_SETTING)
    t.ok(row ~= nil, "a settings row")
    if not row then return end
    t.eq(row.label, "Add town stops: selling, repair, riding trainer and hearthstone")
    local help = tostring(row.help)
    for _, word in ipairs({ "bags fill", "repair vendor", "riding trainer", "hearthstone", "nothing is done for you" }) do
        t.ok(help:find(word, 1, true) ~= nil, "the help says: " .. word)
    end
    local has = {}
    for _, syn in ipairs(type(row.synonyms) == "table" and row.synonyms or {}) do has[syn] = true end
    t.eq(has.selling, true, "found by selling")
    t.eq(has.sell, nil, "sell belongs to the bags topic alone")
    t.eq(has.repair, nil, "repair is already a bags topic word")
end

-- Lead section 655 (Lazy's 06:35 review, section 243): the route words
-- mode, steps and sort through the whole add-on (T.Declare's word), with a
-- made-up QuestXP module standing in for the player's Questie.
local function xpModule(values)
    local mod = {}
    function mod.GetQuestLogRewardXP(self, id)
        if self ~= mod then error("called without self") end
        return values[id]
    end
    return mod
end

tests["trip route words: mode quests leaves out pick-ups and town stops, and is kept"] = function(t)
    local c, addon = boot({ char = TOWN, bags = { { bag = 0, free = 0, total = 16 } } })
    c.slashes[ns.id.slash]("route mode quests")
    c.advance(1, 5)
    t.ok(said(c, ns.Nav.TripRoute.MODE_SAID.quests) ~= nil, "the mode is said")
    t.eq(addon.store:get("account", ns.Nav.TripRoute.MODE_PATH), "My quests only", "and kept, in the words Settings shows")
    t.eq(said(c, "sell at"), nil, "no town stop on quests only")
    c.slashes[ns.id.slash]("route mode optimal")
    c.advance(1, 5)
    t.eq(addon.store:get("account", ns.Nav.TripRoute.MODE_PATH), "Today's route")
    t.ok(said(c, "Bags full: sell at Bread Seller") ~= nil, "optimal: the sell stop again")
end

tests["trip route words: a mode or sort that is not one says the choice and keeps nothing"] = function(t)
    local c, addon = boot()
    c.slashes[ns.id.slash]("route mode fly")
    t.ok(said(c, ns.Nav.TripRoute.MODE_HOW) ~= nil, "how to pick a mode")
    t.eq(addon.store:get("account", ns.Nav.TripRoute.MODE_PATH), nil, "nothing kept")
    c.slashes[ns.id.slash]("route sort gold")
    t.ok(said(c, ns.Nav.TripRoute.SORT_HOW) ~= nil, "how to pick a sort")
    t.eq(addon.store:get("account", ns.Nav.TripRoute.SORT_PATH), nil, "nothing kept")
end

tests["trip route words: steps cuts the list and says how many more; all clears it"] = function(t)
    local c, addon = boot()
    c.slashes[ns.id.slash]("route")
    c.slashes[ns.id.slash]("route steps 1")
    t.eq(addon.store:get("account", ns.Nav.TripRoute.SHOWN_PATH), "1")
    t.ok(said(c, "more stops.") ~= nil, "the rest are counted")
    c.printed = {}
    c.slashes[ns.id.slash]("route steps all")
    t.eq(addon.store:get("account", ns.Nav.TripRoute.SHOWN_PATH), nil, "all: nothing kept")
    t.eq(said(c, "more stops."), nil, "every stop listed")
end

tests["trip route words: sort xp puts the quest worth the most XP first, from Questie"] = function(t)
    local c, addon = boot()
    c.setQuestieModule("QuestXP", xpModule({ [401] = 100, [402] = 900 }))
    c.slashes[ns.id.slash]("route sort xp")
    c.advance(1, 5)
    t.eq(addon.store:get("account", ns.Nav.TripRoute.SORT_PATH), "Most XP first")
    t.eq(first(c), "Herbs", "900 XP first, though it is the farthest")
    c.slashes[ns.id.slash]("route sort distance")
    c.advance(1, 5)
    t.ok(first(c) ~= "Herbs", "shortest first again: " .. tostring(first(c)))
end

tests["trip route words: sort xp with no XP from Questie says so and stays shortest first"] = function(t)
    local c = boot()
    c.slashes[ns.id.slash]("route sort xp")
    c.advance(1, 5)
    t.ok(said(c, ns.Nav.TripRoute.SORT_NO_XP) ~= nil, "no QuestXP module: said")
    t.ok(first(c) ~= "Herbs", "the order is the shortest walk: " .. tostring(first(c)))
end

-- A2-16: the route list says each quest stop's XP, from the game's reward
-- read where the client has it (client.questRewardXp, a CLIENT NEED; set
-- on the fake here), else from Questie; nothing when neither knows.
tests["trip route words: the route list says each quest's XP, the game's first"] = function(t)
    local c = boot()
    c.questRewardXp = function(id) return ({ [401] = 450 })[id] end
    c.setQuestieModule("QuestXP", xpModule({ [401] = 999, [402] = 900 }))
    c.slashes[ns.id.slash]("route")
    local boars, herbs, bandages
    for _, line in ipairs(c.printed) do
        local l = tostring(line)
        if l:find("Boars", 1, true) then boars = l end
        if l:find("Herbs", 1, true) then herbs = l end
        if l:find("Bandages", 1, true) then bandages = l end
    end
    t.ok(boars ~= nil and boars:find("450 XP", 1, true) ~= nil, "the game's answer: " .. tostring(boars))
    t.ok(herbs ~= nil and herbs:find("900 XP", 1, true) ~= nil, "Questie's: " .. tostring(herbs))
    t.ok(bandages ~= nil and bandages:find("XP", 1, true) == nil, "neither knows: no XP said: " .. tostring(bandages))
end

return tests
