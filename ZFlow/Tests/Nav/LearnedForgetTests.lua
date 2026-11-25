local _, ns = ...

-- F-new-4: forgetting one wrongly learned place or quest spot, and
-- resetting the first levels learned from class trainers. Only saved data
-- is touched. Made-up names and places; not tested in game.

local tests = {}

local function boot(account, char)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, account or {})
    c.setSaved(ns.id.charDB, char or {})
    c.setClass("WARRIOR"); c.setFaction("Alliance"); c.setLevel(10)
    c.setClock(1700000000)
    ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c
end

local function run(c, line)
    c.printed = {}
    c.slashes[ns.id.slash](line)
end

local function said(c, text)
    for _, line in ipairs(c.printed or {}) do
        if tostring(line):find(text, 1, true) then return line end
    end
    return nil
end

local function places()
    return {
        ["Creature-0-1-2-3-111-0"] = { name = "Brog Hamfist", guid = "Creature-0-1-2-3-111-0", map = 1, x = 0.5, y = 0.5, kinds = { vendor = true }, n = 1 },
        ["Creature-0-1-2-3-222-0"] = { name = "Innkeeper Farley", guid = "Creature-0-1-2-3-222-0", map = 1, x = 0.4, y = 0.4, kinds = { innkeeper = true }, n = 2 },
    }
end

tests["forget: pure, a place goes by name (any case) or by key, the rest stays"] = function(t)
    local F = ns.Nav.LearnedForget
    local svc, npcs = places(), { ["Brog Hamfist"] = { map = 1, x = 0.5, y = 0.5 }, Other = { map = 2 } }
    local gone = F.ForgetPlace(svc, npcs, "brog hamfist")
    t.eq(#gone, 2, "the character's entry and the imported one")
    t.eq(svc["Creature-0-1-2-3-111-0"], nil)
    t.eq(npcs["Brog Hamfist"], nil)
    t.ok(svc["Creature-0-1-2-3-222-0"] ~= nil, "another place stays")
    t.ok(npcs.Other ~= nil)
    t.eq(#F.ForgetPlace(svc, npcs, "Creature-0-1-2-3-222-0"), 1, "by its key")
    t.eq(#F.ForgetPlace(svc, npcs, "Nobody"), 0)
    t.eq(#F.ForgetPlace(nil, nil, "Nobody"), 0)
end

tests["forget: pure, a quest spot goes whole, one objective, or the hand-in"] = function(t)
    local F = ns.Nav.LearnedForget
    local book = { [100] = { [1] = { { map = 1, x = 0.1, y = 0.1 } }, [2] = { { map = 1, x = 0.2, y = 0.2 } }, [0] = { { map = 1, x = 0.3, y = 0.3 } } },
        [200] = { [1] = { { map = 1, x = 0.5, y = 0.5 } } } }
    t.eq(F.ForgetSpot(book, 100, "done"), 1)
    t.eq(book[100][0], nil)
    t.eq(F.ForgetSpot(book, 100, "2"), 1)
    t.eq(book[100][2], nil)
    t.ok(book[100][1] ~= nil, "objective 1 stays")
    t.eq(F.ForgetSpot(book, 200, nil), 1, "the whole quest")
    t.eq(book[200], nil)
    t.eq(F.ForgetSpot(book, 300, nil), 0, "nothing learned for it")
    t.eq(F.ForgetSpot(book, 100, "9"), 0)
end

tests["forget: the places word with no name only counts and explains"] = function(t)
    local c = boot({ learned = { places = { npcs = { Somebody = { map = 1, x = 0.1, y = 0.1 } } } } },
        { learned = { places = { services = places() } } })
    run(c, "places")
    t.ok(said(c, ns.id.title .. ": ") ~= nil, "something is said")
    t.ok(said(c, "places forget") ~= nil, "says how to forget one")
    local saved = c.saved(ns.id.charDB).learned.places.services
    t.ok(saved["Creature-0-1-2-3-111-0"] ~= nil and saved["Creature-0-1-2-3-222-0"] ~= nil, "nothing wiped")
    run(c, "places forget")
    t.ok(c.saved(ns.id.charDB).learned.places.services["Creature-0-1-2-3-111-0"] ~= nil, "no name: nothing wiped")
end

tests["forget: the places word forgets the one named and says so"] = function(t)
    local c = boot({ learned = { places = { npcs = { ["Brog Hamfist"] = { map = 1, x = 0.5, y = 0.5 } } } } },
        { learned = { places = { services = places() } } })
    run(c, "places forget brog hamfist")
    t.ok(said(c, "Brog Hamfist") ~= nil, "names what was removed")
    local svc = c.saved(ns.id.charDB).learned.places.services
    t.eq(svc["Creature-0-1-2-3-111-0"], nil)
    t.ok(svc["Creature-0-1-2-3-222-0"] ~= nil, "the innkeeper stays")
    t.eq(c.saved(ns.id.accountDB).learned.places.npcs["Brog Hamfist"], nil, "the imported one too")
    run(c, "places forget Nobody Here")
    t.ok(said(c, "Nobody Here") ~= nil, "says nothing matched, by the name given")
    t.ok(c.saved(ns.id.charDB).learned.places.services["Creature-0-1-2-3-222-0"] ~= nil)
end

tests["forget: the spots word forgets one quest's spot and says so"] = function(t)
    local book = { [100] = { [1] = { { map = 1, x = 0.1, y = 0.1, n = 1 } }, [0] = { { map = 1, x = 0.3, y = 0.3, n = 1 } } } }
    local c = boot({ learned = { places = { questSpots = book } } })
    run(c, "spots")
    t.ok(said(c, "spots forget") ~= nil, "bare word explains")
    t.ok(c.saved(ns.id.accountDB).learned.places.questSpots[100][1] ~= nil, "bare word wipes nothing")
    run(c, "spots forget 100 done")
    t.ok(said(c, "100") ~= nil)
    local saved = c.saved(ns.id.accountDB).learned.places.questSpots
    t.eq(saved[100][0], nil, "the hand-in spot is gone")
    t.ok(saved[100][1] ~= nil, "objective 1 stays")
    run(c, "spots forget 555")
    t.ok(said(c, "555") ~= nil, "says nothing matched")
end

tests["forget: facts reset clears the first levels and keeps the trainer lines"] = function(t)
    local c = boot({ learned = { facts = { spells = { WARRIOR = { Charge = { name = "Charge", level = 4 } } },
        first = { WARRIOR = { Charge = 4, Rend = 6 } }, firstAt = { WARRIOR = { Charge = 1 } } } } })
    run(c, "facts")
    t.ok(c.saved(ns.id.accountDB).learned.facts.first.WARRIOR.Charge == 4, "the bare word keeps them")
    run(c, "facts reset")
    t.ok(said(c, "2") ~= nil, "says how many")
    local f = c.saved(ns.id.accountDB).learned.facts
    t.eq(f.first, {})
    t.eq(f.firstAt, {})
    t.eq(f.spells.WARRIOR.Charge.level, 4, "trainer lines stay")
end

return tests
