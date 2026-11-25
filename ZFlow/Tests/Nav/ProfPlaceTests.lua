local _, ns = ...
-- The place of a profession step in words (Nav/ProfStep.lua N.ProfPlace,
-- Nav/ProfFeed.lua F.PlaceFor, F.Placed, F.NoPlace): each step kind gets
-- the nearest KNOWN place. Saved places come first, then the player's own
-- Questie; on the map the player is on, else the nearest on the same
-- continent. With nothing known it gets none and a plain line says so; the
-- step's own words are kept. Pure: plain tables in, and a made-up Questie.
-- Made-up names and places only. Not tested in game.
--
-- Red before the code: no Questie read, no same-continent fallback, and the
-- placed step is not yet shaped so the arrow says how far it is.
local N = ns.Nav
local tests = {}

local function PP() return N.ProfPlace end
local function F() return N.ProfFeed end

local function has(t)
    local ok = type(PP()) == "table" and type(PP().Of) == "function" and type(PP().Scan) == "function"
        and type(PP().Questie) == "function"
        and type(F().PlaceFor) == "function" and type(F().Placed) == "function"
        and type(F().NoPlace) == "function"
    t.ok(ok, "N.ProfPlace gives Of, Scan and Questie; the feed gives PlaceFor, Placed and NoPlace")
    return ok
end

-- Maps 1411, 1412 and 1454 are on the player's continent, 1453 on the
-- other; the client says nothing about 1499.
local CONT = { [1411] = 1, [1412] = 1, [1454] = 1, [1453] = 2 }
-- Questie's areas and the maps they are.
local AREAS = { [14] = 1411, [17] = 1412, [1637] = 1454, [1519] = 1453 }

local function known(more)
    local k = {
        here = { map = 1411, x = 0.5, y = 0.5, faction = "Horde" },
        contOf = function(map) return CONT[map] end,
    }
    for key, v in pairs(more or {}) do k[key] = v end
    return k
end

local function trainer(map, x, prof, faction)
    return { map = map, x = x, y = 0.5, roles = { trainer = true }, trains = { [prof] = true },
             factions = { [faction or "Horde"] = true } }
end

-- A stand-in for Questie's two modules. count.scans counts the times the
-- list of NPCs was gone through (the sub-name of the lowest NPC is read
-- once a pass); count.objects the object reads.
local function questie(npcs, objects, count)
    local db = { NPCPointers = {} }
    local lowest
    for id in pairs(npcs) do
        db.NPCPointers[id] = true
        if lowest == nil or id < lowest then lowest = id end
    end
    function db.QueryNPCSingle(id, field)
        if count and id == lowest and field == "subName" then count.scans = (count.scans or 0) + 1 end
        return npcs[id] and npcs[id][field]
    end
    function db.QueryObjectSingle(id, field)
        if count then count.objects = (count.objects or 0) + 1 end
        return objects and objects[id] and objects[id][field]
    end
    local zones = {}
    function zones.GetUiMapIdByAreaId(a) return AREAS[a] end
    return db, zones
end

local NPCS = {
    [101] = { name = "Tess", subName = "Tailoring Trainer", friendlyToFaction = "H", npcFlags = 16,
              spawns = { [14] = { { 60, 50 } } } },
    [102] = { name = "Their Tess", subName = "Tailoring Trainer", friendlyToFaction = "A",
              spawns = { [14] = { { 51, 50 } } } },
    [103] = { name = "Sword Teacher", subName = "Warrior Trainer", friendlyToFaction = "AH",
              spawns = { [14] = { { 50, 50 } } } },
    [104] = { name = "Banker Test", npcFlags = 256 + 1, friendlyToFaction = "H",
              spawns = { [1637] = { { 40, 60 }, { -1, -1 } } } },
    [105] = { name = "Auctioneer Test", npcFlags = 4096, friendlyToFaction = "AH",
              spawns = { [17] = { { 20, 30 } } } },
    [106] = { name = "Nowhere Tess", subName = "Tailoring Trainer", spawns = { [9999] = { { 50, 50 } } } },
    [107] = { name = "Cook Far", subName = "Cooking Trainer", friendlyToFaction = "H",
              spawns = { [1519] = { { 50, 50 } } } },
    [108] = { name = "Just A Vendor", npcFlags = 4, spawns = { [14] = { { 50, 50 } } } },
}

local LEARN = { kind = "learn_recipe", text = "Learn a Tailoring recipe at a trainer" }
local TRAIN = { kind = "train_tier", text = "Train the next Tailoring rank at a trainer" }
local BANK = { kind = "take_bank", text = "Take 4 Test Bar from your bank, for Test Blade" }
local AUCTION = { kind = "buy_auction", text = "Buy 4 Test Bar at the auction house" }

tests["prof place: a trainer step gets the nearest known trainer of its profession on this map"] = function(t)
    if not has(t) then return end
    local k = known({ npcs = {
        ["Far Tess"] = trainer(1411, 0.9, "Tailoring"),
        ["Near Tess"] = trainer(1411, 0.6, "Tailoring"),
        ["Cook"] = trainer(1411, 0.51, "Cooking"),
        ["Other Side"] = trainer(1411, 0.52, "Tailoring", "Alliance"),
    } })
    t.eq(PP().Of(LEARN, "Tailoring", k), { map = 1411, x = 0.6, y = 0.5 }, "learn a recipe: the nearest tailor")
    t.eq(PP().Of(TRAIN, "Tailoring", k), { map = 1411, x = 0.6, y = 0.5 }, "train the next rank: the same")
    t.eq(PP().Of(LEARN, "Cooking", k), { map = 1411, x = 0.51, y = 0.5 }, "by profession")
    t.eq(PP().Of(LEARN, "Alchemy", k), nil, "no trainer of that profession known: no place")
    t.eq(PP().Of({ kind = "learn_recipe", npc = "Someone", text = "Learn it at Someone" }, "Tailoring", k), nil,
        "a step that names its trainer is not sent to another one")
    t.eq(LEARN.target, nil, "the step handed in is not changed")
end

tests["prof place: a trainer saved with no roles still counts, by what it trains"] = function(t)
    if not has(t) then return end
    local k = known({ npcs = { ["Tess"] = { map = 1411, x = 0.6, y = 0.5, trains = { Tailoring = true } } } })
    t.eq(PP().Of(LEARN, "Tailoring", k), { map = 1411, x = 0.6, y = 0.5 })
end

tests["prof place: with none on this map, the nearest known on the same continent"] = function(t)
    if not has(t) then return end
    local k = known({ npcs = {
        ["Across The Sea"] = trainer(1453, 0.5, "Tailoring"),
        ["Who Knows Where"] = trainer(1499, 0.5, "Tailoring"),
    } })
    t.eq(PP().Of(LEARN, "Tailoring", k), nil, "another continent, or a map the client cannot place: no place")
    k.npcs["Next Zone"] = trainer(1412, 0.5, "Tailoring")
    t.eq(PP().Of(LEARN, "Tailoring", k), { map = 1412, x = 0.5, y = 0.5 }, "the next zone, on this continent")
    k.npcs["In Town"] = trainer(1454, 0.3, "Tailoring")
    k.far = function(place) return place.map == 1454 and 100 or 900 end
    t.eq(PP().Of(LEARN, "Tailoring", k), { map = 1454, x = 0.3, y = 0.5 }, "of two on the continent, the nearer")
    k.far = function(place) return place.map == 1454 and 900 or 100 end
    t.eq(PP().Of(LEARN, "Tailoring", k), { map = 1412, x = 0.5, y = 0.5 }, "and the other way round")
    k.npcs["Here"] = trainer(1411, 0.9, "Tailoring")
    t.eq(PP().Of(LEARN, "Tailoring", k), { map = 1411, x = 0.9, y = 0.5 }, "one on this map comes first")
    local lost = known({ npcs = { ["Next Zone"] = trainer(1412, 0.5, "Tailoring") } })
    lost.contOf = nil
    t.eq(PP().Of(LEARN, "Tailoring", lost), nil, "the continents not known: another map is not pointed at")
end

tests["prof place: a bank step gets the nearest known banker, an auction step the auctioneer"] = function(t)
    if not has(t) then return end
    local k = known({ services = {
        a = { map = 1411, x = 0.2, y = 0.5, kinds = { banker = true } },
        b = { map = 1411, x = 0.45, y = 0.5, kinds = { banker = true } },
        v = { map = 1411, x = 0.5, y = 0.5, kinds = { vendor = true } },
    } })
    t.eq(PP().Of(BANK, "Blacksmithing", k), { map = 1411, x = 0.45, y = 0.5 }, "the nearest banker, never the vendor")
    t.eq(PP().Of(AUCTION, "Blacksmithing", k), nil, "no auctioneer known: no place")
    -- An entry of the account's npcs whose roles say it (an imported one).
    k.npcs = {
        ["Auctioneer Saved"] = { map = 1454, x = 0.55, y = 0.6, roles = { auction = true }, factions = { Horde = true } },
        ["Their Auctioneer"] = { map = 1411, x = 0.5, y = 0.5, roles = { auction = true }, factions = { Alliance = true } },
    }
    t.eq(PP().Of(AUCTION, "Blacksmithing", k), { map = 1454, x = 0.55, y = 0.6 },
        "the auctioneer in town, not the other faction's here")
    t.eq(PP().Of(BANK, "Blacksmithing", known({})), nil, "nothing saved: no place")
end

tests["prof place: Questie's NPCs are read by sub-name and by flag, with a place only on a map known"] = function(t)
    if not has(t) then return end
    local db, zones = questie(NPCS)
    local found, n = PP().Scan(db, zones)
    t.eq(found.trainer.Tailoring, {
        { name = "Tess", map = 1411, x = 0.6, y = 0.5, side = "H" },
        { name = "Their Tess", map = 1411, x = 0.51, y = 0.5, side = "A" },
    }, "the two with the sub-name Tailoring Trainer and a place; the one in no known area is left out")
    t.eq(found.trainer.Warrior, nil, "a class trainer is no profession trainer")
    t.eq(found.trainer.Cooking, { { name = "Cook Far", map = 1453, x = 0.5, y = 0.5, side = "H" } })
    t.eq(found.banker, { { name = "Banker Test", map = 1454, x = 0.4, y = 0.6, side = "H" } },
        "the banker bit (256); a spawn off the map is left out")
    t.eq(found.auction, { { name = "Auctioneer Test", map = 1412, x = 0.2, y = 0.3, side = "AH" } },
        "the auctioneer bit (4096)")
    t.eq(n, 5, "five places in all")
    -- Questie's own list of flags wins over the first game's numbers.
    db.npcFlags = { BANKER = 4, AUCTIONEER = 16 }
    local own = PP().Scan(db, zones)
    t.eq(own.banker, { { name = "Just A Vendor", map = 1411, x = 0.5, y = 0.5 } }, "its own banker bit")
    t.eq(own.auction, { { name = "Tess", map = 1411, x = 0.6, y = 0.5, side = "H" } }, "its own auctioneer bit")
    local none, zero = PP().Scan(nil, zones)
    t.eq(none, { trainer = {}, banker = {}, auction = {} }, "no Questie: nothing")
    t.eq(zero, 0)
end

tests["prof place: saved places come first, then Questie, on this map and then on the continent"] = function(t)
    if not has(t) then return end
    local found = PP().Scan(questie(NPCS))
    local asked = 0
    local function q()
        asked = asked + 1
        return found
    end
    local k = known({ questie = q })
    t.eq(PP().Of(LEARN, "Tailoring", k), { map = 1411, x = 0.6, y = 0.5 },
        "nothing saved: Questie's tailor of the player's faction, not the nearer one of the other")
    t.eq(PP().Of(BANK, "Tailoring", k), { map = 1454, x = 0.4, y = 0.6 }, "Questie's banker, in town on this continent")
    t.eq(PP().Of(AUCTION, "Tailoring", k), { map = 1412, x = 0.2, y = 0.3 }, "Questie's auctioneer")
    t.eq(PP().Of(LEARN, "Cooking", k), nil, "Questie's only cook is across the sea: no place")
    t.eq(PP().Of(LEARN, "Alchemy", k), nil, "Questie knows no such trainer: no place")
    asked = 0
    k.npcs = { ["Saved Tess"] = trainer(1411, 0.9, "Tailoring") }
    t.eq(PP().Of(LEARN, "Tailoring", k), { map = 1411, x = 0.9, y = 0.5 }, "a saved one on this map wins, farther as it is")
    t.eq(asked, 0, "and Questie is not asked at all")
    k.npcs = { ["Saved Tess"] = trainer(1412, 0.9, "Tailoring") }
    t.eq(PP().Of(LEARN, "Tailoring", k), { map = 1411, x = 0.6, y = 0.5 }, "Questie's on this map before a saved one elsewhere")
    k.services = { s = { map = 1412, x = 0.7, y = 0.7, kinds = { banker = true } } }
    t.eq(PP().Of(BANK, "Tailoring", k), { map = 1412, x = 0.7, y = 0.7 }, "elsewhere: the saved banker before Questie's")
    k.questie = function() return nil end
    t.eq(PP().Of(AUCTION, "Tailoring", k), nil, "Questie not readable yet: no place")
    k.questie = function() error("questie not ready") end
    t.eq(PP().Of(AUCTION, "Tailoring", k), nil, "a Questie read that raises: no place")
end

tests["prof place: a gathering step gets the nearest node of its own profession gathered here"] = function(t)
    if not has(t) then return end
    local k = known({ nodes = {
        { x = 0.3, y = 0.3, prof = "Herbalism" },
        { x = 0.4, y = 0.4, prof = "Mining" },
        { x = 0.8, y = 0.8, prof = "Mining" },
        { x = 0.5, y = 0.5 },
    } })
    local MINE = { kind = "gather_skill", gather = "Mining", text = "Mine any ore vein you find" }
    t.eq(PP().Of(MINE, "Mining", k), { map = 1411, x = 0.4, y = 0.4 }, "the first Mining node, nearest first")
    t.eq(PP().Of({ kind = "gather_skill", gather = "Fishing", text = "Fish" }, "Fishing", k), nil,
        "no node of that profession: no place")
    t.eq(PP().Of(MINE, "Mining", known({})), nil, "no node gathered: no place")
    -- None gathered on this map: where Questie puts a node gathered before.
    local asked
    local spots = known({ spots = function(prof)
        asked = prof
        return { { map = 1411, x = 0.9, y = 0.5 }, { map = 1411, x = 0.55, y = 0.5 }, { map = 1412, x = 0.5, y = 0.5 } }
    end })
    t.eq(PP().Of(MINE, "Mining", spots), { map = 1411, x = 0.55, y = 0.5 }, "the nearest of Questie's on this map")
    t.eq(asked, "Mining")
    spots.spots = function() return { { map = 1412, x = 0.5, y = 0.5 } } end
    t.eq(PP().Of(MINE, "Mining", spots), nil, "only on another map: no place")
end

tests["prof place: a craft at an anvil gets one seen on the continent, else a blacksmithing trainer"] = function(t)
    if not has(t) then return end
    local CRAFT = { kind = "craft", station = "anvil", text = "Make 2 Test Blade at an anvil" }
    local SMELT = { kind = "make_part", station = "forge", text = "Smelt 2 Test Bar at a forge" }
    local k = known({ stations = { { kind = "forge", map = 1412, x = 0.7, y = 0.3 },
                                   { kind = "anvil", map = 1453, x = 0.1, y = 0.1 },
                                   { kind = "fire", map = 1454, x = 0.2, y = 0.2 } } })
    t.eq(PP().Of(CRAFT, "Blacksmithing", k), { map = 1412, x = 0.7, y = 0.3 }, "a forge stands by an anvil")
    t.eq(PP().Of(SMELT, "Mining", k), { map = 1412, x = 0.7, y = 0.3 }, "the smelt: the forge")
    t.eq(PP().Of({ kind = "craft", station = "fire", text = "Cook 2 Test Stew at a fire" }, "Cooking", k), nil,
        "a fire is never looked for")
    t.eq(PP().Of({ kind = "craft", text = "Make 2 Test Bandage" }, "First Aid", k), nil, "a craft with no station")
    local smith = known({ npcs = { ["Smith Test"] = trainer(1411, 0.3, "Blacksmithing"),
                                   ["Tess"] = trainer(1411, 0.5, "Tailoring") } })
    t.eq(PP().Of(CRAFT, "Blacksmithing", smith), { map = 1411, x = 0.3, y = 0.5 },
        "no station seen: a blacksmithing trainer works by one")
    t.eq(PP().Of(CRAFT, "Blacksmithing", known({})), nil, "nothing known: no place")
    k.stations[#k.stations + 1] = { kind = "anvil", map = 1411, x = 0.5, y = 0.52 }
    k.npcs = smith.npcs
    t.eq(PP().Of(CRAFT, "Blacksmithing", k), nil, "one on this map is the plan's own step: no second place")
end

tests["prof place: unknown stays unknown"] = function(t)
    if not has(t) then return end
    local full = known({ npcs = { ["Tess"] = trainer(1411, 0.6, "Tailoring") } })
    for _, kind in ipairs({ "buy_vendor", "find_material", "open_window", "no_point", "gather", "buy_recipe" }) do
        t.eq(PP().Of({ kind = kind, text = "words" }, "Tailoring", full), nil, kind .. ": no place is looked for")
    end
    local lost = known({ npcs = full.npcs })
    lost.here = nil
    t.eq(PP().Of(LEARN, "Tailoring", lost), nil, "where the player is is not known: no place")
    lost.here = { map = 1411 }
    t.eq(PP().Of(LEARN, "Tailoring", lost), nil, "the map without the spot on it: no place")
    t.eq(PP().Of(LEARN, "Tailoring", nil), nil)
    t.eq(PP().Of(nil, "Tailoring", full), nil)
end

-- A client with only the reads the reader asks: its time and Questie.
local function clientOf(db, zones, clock)
    return {
        now = function() return clock.t end,
        questieModule = function(name)
            if name == "QuestieDB" then return db end
            if name == "ZoneDB" then return zones end
            return nil
        end,
    }
end

-- Asks for the places, then lets the reader work (as its owner does, a part
-- a frame) until it has no more to do, and gives what it has then.
local function settle(reader, client)
    reader.places(client)
    for _ = 1, 200 do
        if type(reader.work) ~= "function" or not reader.work(client) then break end
    end
    return reader.places(client)
end

tests["prof place: Questie is scanned once and the answer kept, however often it is asked"] = function(t)
    if not has(t) then return end
    local count, clock = {}, { t = 100 }
    local db, zones = questie(NPCS, nil, count)
    local reader, client = PP().Questie(), clientOf(db, zones, clock)
    local first = settle(reader, client)
    t.eq(first and first.banker and #first.banker, 1, "the scan's answer")
    for i = 1, 50 do
        clock.t = 100 + i
        t.eq(settle(reader, client), first, "the same answer, kept")
    end
    t.eq(count.scans, 1, "one pass over Questie's NPCs for all of that")
end

-- Lead section 564 (no hitch): asking never reads Questie itself; the work
-- is done a part at a time by reader.work, PP.STEP NPCs a call at most.
tests["prof place: asking reads nothing; the scan is done a part a call, and only once asked for"] = function(t)
    if not has(t) then return end
    local step = PP().STEP
    t.ok(type(step) == "number" and step >= 1, "PP.STEP says how many NPCs a call")
    if type(step) ~= "number" or step < 1 then return end
    local npcs, reads = {}, 0
    for id = 1, step * 2 + 1 do npcs[id] = { name = "Nobody " .. id } end
    npcs[step * 2 + 1] = { name = "Late Banker", npcFlags = 256, spawns = { [14] = { { 50, 50 } } } }
    local db = { NPCPointers = {} }
    for id in pairs(npcs) do db.NPCPointers[id] = true end
    function db.QueryNPCSingle(id, field)
        if field == "subName" then reads = reads + 1 end
        return npcs[id] and npcs[id][field]
    end
    local zones = {}
    function zones.GetUiMapIdByAreaId(a) return AREAS[a] end
    local reader, client = PP().Questie(), clientOf(db, zones, { t = 100 })
    t.ok(type(reader.work) == "function", "the reader has work to be called a frame at a time")
    if type(reader.work) ~= "function" then return end
    t.eq(reader.work(client), false, "not asked for yet: no work")
    t.eq(reads, 0, "and nothing read")
    t.eq(reader.places(client), nil, "asked: no answer yet")
    t.eq(reads, 0, "asking reads nothing itself")
    local most, calls = 0, 0
    while calls < 20 do
        local was = reads
        local more = reader.work(client)
        calls = calls + 1
        if reads - was > most then most = reads - was end
        if reader.places(client) ~= nil or not more then break end
    end
    t.ok(most <= step, "no call went through more than PP.STEP NPCs: " .. most)
    t.eq(reads, step * 2 + 1, "every NPC was gone through once")
    t.ok(calls >= 3, "over three calls or more: " .. calls)
    local found = reader.places(client)
    t.eq(found and found.banker and #found.banker, 1, "the answer is whole: the last NPC is in it")
    t.eq(reader.work(client), false, "done: no more work")
end

tests["prof place: Questie absent gives nothing; an empty answer is retried within bounds"] = function(t)
    if not has(t) then return end
    local clock = { t = 100 }
    local reader = PP().Questie()
    t.eq(reader.places(clientOf(nil, nil, clock)), nil, "no Questie: nothing, and nothing made up")
    -- Questie there, with no NPC of use yet (still loading).
    local count = {}
    local db, zones = questie({ [1] = { name = "Nobody" } }, nil, count)
    local client = clientOf(db, zones, clock)
    settle(reader, client)
    t.eq(count.scans, 1, "asked once it is there")
    clock.t = 105
    settle(reader, client)
    t.eq(count.scans, 1, "not again within the wait")
    for i = 1, 40 do
        clock.t = 105 + i * 11
        settle(reader, client)
        settle(reader, client)
    end
    t.eq(count.scans, PP().TRIES, "then no more than the tries in all, however long it is asked")
    -- It arrives late, within the tries: its answer is used and kept.
    local late, lateCount, lateClock = PP().Questie(), {}, { t = 100 }
    local empty, emptyZones = questie({ [1] = { name = "Nobody" } }, nil, lateCount)
    settle(late, clientOf(empty, emptyZones, lateClock))
    lateClock.t = 120
    local full, fullZones = questie(NPCS, nil, lateCount)
    local got = settle(late, clientOf(full, fullZones, lateClock))
    t.eq(got and got.auction and #got.auction, 1, "the later answer has the places")
end

tests["prof place: a client with no time still stops asking after the tries"] = function(t)
    if not has(t) then return end
    local count, clock = {}, { t = 0 }
    local db, zones = questie({ [1] = { name = "Nobody" } }, nil, count)
    local reader, client = PP().Questie(), clientOf(db, zones, clock)
    for _ = 1, 30 do settle(reader, client) end
    t.eq(count.scans, PP().TRIES, "the tries come in a row, and end")
end

tests["prof place: an object's places on a map are read once and kept"] = function(t)
    if not has(t) then return end
    local count, clock = {}, { t = 100 }
    local objects = { [1731] = { spawns = { [14] = { { 30, 40 }, { 70, 80 } }, [17] = { { 10, 10 } } } } }
    local db, zones = questie({}, objects, count)
    local reader, client = PP().Questie(), clientOf(db, zones, clock)
    local want = { { map = 1411, x = 0.3, y = 0.4 }, { map = 1411, x = 0.7, y = 0.8 } }
    t.eq(reader.spots(client, { 1731 }, 1411), want, "its places on that map only")
    t.eq(reader.spots(client, { 1731 }, 1411), want)
    t.eq(reader.spots(client, { 1731 }, 1412), { { map = 1412, x = 0.1, y = 0.1 } })
    t.eq(count.objects, 1, "one read of the object for all three")
    t.eq(reader.spots(client, { 9 }, 1411), {}, "an object Questie does not know: nothing")
    t.eq(reader.spots(client, {}, 1411), {})
end

tests["prof feed: a pick in words asks for a place; one with its own, or held back, does not"] = function(t)
    if not has(t) then return end
    local asked = 0
    local function place(step, prof)
        asked = asked + 1
        if step.kind == "learn_recipe" and prof == "Tailoring" then return { map = 1411, x = 0.6, y = 0.5 } end
        return nil
    end
    t.eq(F().PlaceFor({ prof = "Tailoring", step = LEARN, rank = 4 }, place), { map = 1411, x = 0.6, y = 0.5 })
    t.eq(F().PlaceFor({ prof = "Cooking", step = LEARN, rank = 4 }, place), nil, "none known: none")
    t.eq(asked, 2)
    local own = { kind = "learn_recipe", text = "Learn it at Tess", target = { map = 1411, x = 0.1, y = 0.1 } }
    t.eq(F().PlaceFor({ prof = "Tailoring", step = own, rank = 2 }, place), nil, "the plan's own place stands")
    t.eq(F().PlaceFor({ prof = "Tailoring", step = LEARN, rank = 5, held = true }, place), nil, "held back: words")
    t.eq(F().PlaceFor({ prof = "Tailoring", rank = 6, text = "Open your Tailoring window once" }, place), nil)
    t.eq(asked, 2, "none of those three asked")
    t.eq(F().PlaceFor({ prof = "Tailoring", step = LEARN }, function() return { map = 1411, x = 7, y = 0.5 } end), nil,
        "an answer that is no place on a map is not used")
    t.eq(F().PlaceFor({ prof = "Tailoring", step = LEARN }, nil), nil)
end

-- One pick in words (Tailoring) and another profession with its own line.
local function picked(step)
    return F().Pick({
        names = { "Cooking", "Tailoring" },
        readings = { Cooking = { skill = 40, max = 75 }, Tailoring = { skill = 10, max = 75 } },
        plan = function(prof)
            if prof == "Tailoring" then return { step } end
            return {}
        end,
    })
end

tests["prof feed: a placed step is shaped so the arrow says how far, and keeps every word"] = function(t)
    if not has(t) then return end
    local result = picked(LEARN)
    t.eq(result.pick and result.pick.rank, 4, "a step in words keeps its rank")
    local step = F().Placed(result, { map = 1454, x = 0.4, y = 0.5 }, 1)
    t.eq(step.place, { cont = 1, map = 1454, x = 0.4, y = 0.5 })
    t.eq(step.radius, N.PROF_NEAR)
    t.eq(step.label, LEARN.text, "its own words are the label")
    t.eq(step.also, { "Open your Cooking window once" }, "the other profession's line, as before")
    t.eq(step.lines, nil, "no lines: the arrow then says the label, the also lines and how far")
    t.eq(step.still, nil, "it has somewhere to turn to")
    -- Words over the label limit go under the profession's name; what to
    -- look for is kept, right under them.
    local long = { kind = "craft", station = "anvil", look = "Look for an anvil, by a blacksmith in a town.",
                   text = "Make 2 Test Blade at an anvil (Tailoring 10 of 75)" }
    local far = F().Placed(picked(long), { map = 1411, x = 0.3, y = 0.5 }, nil)
    t.eq(far.label, "Tailoring")
    t.eq(far.detail, long.text, "the whole of the step's words")
    t.eq(far.also, { long.look, "Open your Cooking window once" }, "what to look for, then the other professions")
    t.eq(far.place, { map = 1411, x = 0.3, y = 0.5 })
    t.eq(F().Placed(result, nil, 1), nil, "no place: no placed step")
    t.eq(F().Placed(result, { map = 1454, x = 2, y = 0.5 }, 1), nil, "not a place on a map: none")
    t.eq(F().Placed({ rows = {} }, { map = 1454, x = 0.4, y = 0.5 }, 1), nil, "no pick: none")
end

tests["prof feed: with no place known a plain line says so, by the kind of place"] = function(t)
    if not has(t) then return end
    local W = F().NO_PLACE
    t.ok(type(W) == "table", "the words are there")
    if type(W) ~= "table" then return end
    local function note(kind, prof, more)
        local step = { kind = kind, text = "words" }
        for key, v in pairs(more or {}) do step[key] = v end
        return F().NoPlace({ prof = prof, step = step, rank = 4 })
    end
    t.eq(note("learn_recipe", "Tailoring"), W.trainer:format("Tailoring"))
    t.eq(note("train_tier", "Tailoring"), W.trainer:format("Tailoring"))
    t.eq(note("take_bank", "Tailoring"), W.banker)
    t.eq(note("buy_auction", "Tailoring"), W.auction)
    t.eq(note("gather_skill", "Mining"), W.node:format("Mining"))
    t.eq(note("gather_skill", "Skinning"), nil, "a profession with no nodes: no line about nodes")
    t.eq(note("craft", "Blacksmithing", { station = "anvil" }), nil, "a station step says what to look for itself")
    t.eq(note("buy_vendor", "Tailoring"), nil)
    t.eq(note("learn_recipe", "Tailoring", { target = { map = 1411, x = 0.1, y = 0.1 } }), nil, "it has a place")
    t.eq(F().NoPlace({ prof = "Tailoring", step = LEARN, held = true }), nil, "held back: its own words say where")
    t.eq(F().NoPlace({ prof = "Tailoring", rank = 6 }), nil)
    t.eq(F().NoPlace(nil), nil)
end

tests["prof feed: the no-place line comes right under the step's own words, before the other professions"] = function(t)
    if not has(t) then return end
    local result = picked(LEARN)
    t.eq(result.pick and result.pick.prof, "Tailoring")
    local note = F().NoPlace(result.pick)
    local step = F().Step(result, note)
    t.eq(step.lines, { LEARN.text, F().NO_PLACE.trainer:format("Tailoring"), "Open your Cooking window once" })
    t.eq(step.place, nil, "and no place is made up")
    t.eq(step.still, true)
    t.eq(F().Step(result).lines, { LEARN.text, "Open your Cooking window once" }, "no line handed in: as before")
end

-- Parity row A1-21 (Nav/NodeRest.lua): a gathered node that is resting
-- (just looted, or found empty) is not the one a gathering step points at;
-- the next one is. Red before: PP.From hands on every node, resting or not.
tests["prof place: a resting node is passed over, the next one is pointed at"] = function(t)
    if not has(t) then return end
    local list = {
        { node = { x = 0.6, y = 0.5, prof = "Mining", id = 1 }, d = 10 },
        { node = { x = 0.7, y = 0.5, prof = "Mining", id = 2 }, d = 20 },
    }
    local rested = { [1] = true }
    local function use(name)
        if name == "nodes" then return { Nearest = function() return list, true end } end
        if name == "nodeRest" then return { Resting = function(n) return rested[n.id] == true end } end
        return nil
    end
    local client = { position = function() return { map = 1411, x = 0.5, y = 0.5 } end }
    local step = { kind = "gather_skill", text = "Gather to raise Mining", gather = "Mining" }
    local to = PP().Of(step, "Mining", PP().From(client, nil, use, "node", {}))
    t.eq(to, { map = 1411, x = 0.7, y = 0.5 }, "the node that is not resting")
    rested = {}
    to = PP().Of(step, "Mining", PP().From(client, nil, use, "node", {}))
    t.eq(to, { map = 1411, x = 0.6, y = 0.5 }, "rested again: the nearest one")
    rested = { [1] = true, [2] = true }
    t.eq(PP().Of(step, "Mining", PP().From(client, nil, use, "node", {})), nil, "every one resting: none, and none made up")
    -- No rest module (it failed to load): every node counts, as before.
    local function plain(name)
        if name == "nodes" then return use(name) end
        return nil
    end
    to = PP().Of(step, "Mining", PP().From(client, nil, plain, "node", {}))
    t.eq(to, { map = 1411, x = 0.6, y = 0.5 }, "no rest module: as before")
end

return tests
