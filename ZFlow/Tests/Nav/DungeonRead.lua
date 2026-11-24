-- The Dungeon Quests reader (lead section 303 item 7, data route A): the
-- dungeon list and each dungeon's quests read from Questie at runtime
-- through the client (client.questieModule), the index built in slices,
-- and the pane for one dungeon. Fake client and a made-up Questie: no
-- quest data of any add-on is in this file. Not tested in game.
local _, ns = ...
local tests = {}

local R = ns.DungeonRead
local S = ns.DungeonStates

local DM, SFK, AV = 1581, 209, 2597

-- A made-up Questie: three quests in the Deadmines (one by its zone, two
-- more), one in Shadowfang Keep, one in no dungeon.
local function questie(over)
    over = over or {}
    local quests = {
        [101] = { Id = 101, name = "Red Silk", level = 18, requiredLevel = 14, zoneOrSort = DM,
            Starts = { NPC = { 501 } } },
        [102] = { Id = 102, name = "Collecting Memories", level = 18, requiredLevel = 14, zoneOrSort = DM,
            Starts = { NPC = { 502 } } },
        [103] = { Id = 103, name = "The Defias Brotherhood", level = 22, requiredLevel = 20, zoneOrSort = DM,
            Starts = { NPC = { 501 } }, preQuestSingle = { 102 }, nextQuestInChain = 0 },
        [201] = { Id = 201, name = "Arugal Must Die", level = 27, requiredLevel = 18, zoneOrSort = SFK,
            Starts = { NPC = { 503 } } },
        [999] = { Id = 999, name = "Somewhere Else", level = 10, requiredLevel = 5, zoneOrSort = 12 },
    }
    -- over.more (lead section 305): quests filed by where their objectives
    -- are, a giver at the entrance and a giver inside. Zone 40 is outside.
    if over.more then
        quests[105] = { Id = 105, name = "Oh Brother", level = 20, requiredLevel = 15, zoneOrSort = 40,
            Starts = { NPC = { 502 } }, objectives = { { { 601 } } } }
        quests[106] = { Id = 106, name = "Split Up", level = 20, requiredLevel = 15, zoneOrSort = 40,
            Starts = { NPC = { 502 } }, objectives = { { { 601 }, { 602 } } } }
        quests[107] = { Id = 107, name = "At The Door", level = 18, requiredLevel = 14, zoneOrSort = DM,
            Starts = { NPC = { 504 } }, preQuestSingle = { 101 } }
        quests[108] = { Id = 108, name = "Deep Inside", level = 18, requiredLevel = 14, zoneOrSort = DM,
            Starts = { NPC = { 505 } } }
    end
    local npcs = {
        [501] = { name = "Gryan", friendlyToFaction = "A" },
        [502] = { name = "Wilder", friendlyToFaction = "A" },
        [503] = { name = "High Sorcerer", friendlyToFaction = "AH" },
        [504] = { name = "Door Keeper", friendlyToFaction = "A", spawns = { [40] = { { 42.6, 71.9 } } } },
        [505] = { name = "Prisoner", friendlyToFaction = "A", spawns = { [DM] = { { 10, 10 } } } },
        [601] = { name = "Cookie", spawns = { [DM] = { { 20, 20 } } } },
        [602] = { name = "Outside Thug", spawns = { [40] = { { 30, 30 } } } },
    }
    local db = { QuestPointers = {} }
    for id in pairs(quests) do db.QuestPointers[id] = true end
    if over.noPointers then db.QuestPointers = nil end
    function db.GetQuest(id) return quests[id] end
    function db.GetNPC(id) return npcs[id] end
    if not over.noQuery then
        function db.QueryQuestSingle(id, field)
            local qt = quests[id]
            if not qt then return nil end
            if field == "questLevel" then return qt.level end
            return qt[field]
        end
        function db.QueryNPCSingle(id, field)
            local n = npcs[id]
            return n and n[field] or nil
        end
    end
    local zones = {}
    -- Area 40 (outside the Deadmines) is on map 1436.
    function zones.GetUiMapIdByAreaId(area) return ({ [40] = 1436 })[area] end
    function zones:GetDungeons()
        if over.badList then error("no list") end
        local dm = { "The Deadmines" }
        if over.more then dm = { "The Deadmines", {}, nil, { { 40, 42.5, 71.8 } } } end
        return { [DM] = dm, [SFK] = { "Shadowfang Keep" }, [AV] = { "Alterac Valley" } }
    end
    return db, zones, quests
end

local function client(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    if opts.questie ~= false then
        local db, zones = questie(opts)
        c.setQuestieModule("QuestieDB", db)
        c.setQuestieModule("ZoneDB", zones)
    end
    c.setClass(opts.class or "WARRIOR"); c.setRaceId(opts.race or 1); c.setFaction(opts.faction or "Alliance")
    if opts.noLevel then c.setLevel(nil) else c.setLevel(opts.level or 18) end
    -- Every quest of the made-up Questie read as not handed in, unless
    -- opts.doneUnknown (Twin review, F2).
    if not opts.doneUnknown then
        for _, id in ipairs({ 101, 102, 103, 105, 106, 107, 108, 201, 999 }) do c.setQuestDone(id, false) end
    end
    return c
end

-- Builds the whole index at once.
local function indexed(c)
    local st = R.Start(c)
    local guard = 0
    while st.state == "building" and guard < 100 do
        R.Step(st, c, 2)
        guard = guard + 1
    end
    return st
end

tests["dungeon read: without Questie there is no list, and the pane says so"] = function(t)
    local c = client({ questie = false })
    t.eq(R.Available(c), false)
    local st = R.Start(c)
    t.eq(st.state, "noquestie")
    t.eq(R.Pane(st, c, DM).why, S.WHY.noQuestie)
end

tests["dungeon read: the dungeon list, battlegrounds left out, lowest quest level first"] = function(t)
    local st = indexed(client())
    t.eq(st.state, "ready")
    local names = {}
    for i, d in ipairs(R.List(st)) do names[i] = d.name end
    t.eq(names, { "The Deadmines", "Shadowfang Keep" })
    t.eq(R.List(st)[1].minQ, 18)
    t.eq(R.List(st)[1].maxQ, 22)
end

tests["dungeon read: the index is built in slices of the size asked"] = function(t)
    local c = client()
    local st = R.Start(c)
    t.eq(st.state, "building")
    R.Step(st, c, 2)
    t.eq(st.state, "building", "five quests, two a slice: not yet")
    R.Step(st, c, 2)
    R.Step(st, c, 2)
    t.eq(st.state, "ready")
    t.eq(#st.byKey[DM].ids, 3)
    t.eq(#st.byKey[SFK].ids, 1)
end

tests["dungeon read: without the quick query the quest itself is read"] = function(t)
    local st = indexed(client({ noQuery = true }))
    t.eq(st.state, "ready")
    t.eq(#st.byKey[DM].ids, 3)
end

tests["dungeon read: a dungeon list that cannot be read says so"] = function(t)
    local c = client({ badList = true })
    local st = R.Start(c)
    t.eq(st.state, "failed")
    t.eq(R.Pane(st, c, DM).why, R.WHY_LIST)
end

tests["dungeon read: the pane for one dungeon, from the log, what is handed in, race, class and faction"] = function(t)
    local c = client({ level = 18 })
    c.setQuestLog({ { id = 102, title = "Collecting Memories", objectives = {} } })
    c.setQuestDone(101, false)
    local st = indexed(c)
    local pane = R.Pane(st, c, DM)
    t.eq(pane.title, "The Deadmines")
    local where = {}
    for _, g in ipairs(pane.groups) do
        for _, r in ipairs(g.rows) do where[r.name] = g.id end
    end
    t.eq(where["Collecting Memories"], "log")
    t.eq(where["Red Silk"], "pickup")
    t.eq(where["The Defias Brotherhood"], "later", "level 20 needed, you are 18")
    local horde = client({ faction = "Horde", race = 2 })
    local hst = indexed(horde)
    local hp = R.Pane(hst, horde, DM)
    t.eq(hp.groups[5].rows[1] and hp.groups[5].rows[1].note, "the other faction's quest")
end

tests["dungeon read: a quest handed in is not listed"] = function(t)
    local c = client()
    c.setQuestDone(101, true)
    local st = indexed(c)
    local names = {}
    for _, g in ipairs(R.Pane(st, c, DM).groups) do
        for _, r in ipairs(g.rows) do names[#names + 1] = r.name end
    end
    for _, n in ipairs(names) do t.ok(n ~= "Red Silk", "handed in: not listed") end
end

tests["dungeon read: an unknown dungeon key is no dungeon picked"] = function(t)
    local c = client()
    local st = indexed(c)
    t.eq(R.Pane(st, c, 424242).why, S.WHY.noDungeon)
    t.eq(R.Pane(st, c, nil).why, S.WHY.noDungeon)
end

tests["dungeon read: while the index is building the pane says so"] = function(t)
    local c = client()
    local st = R.Start(c)
    t.eq(R.Pane(st, c, DM).why, R.WHY_BUILDING)
    t.eq(#R.WHY_BUILDING, 2)
    t.eq(#R.WHY_LIST, 2)
end

-- Lead section 305: the two parts first left out.
local function groupOf(pane, name)
    for _, g in ipairs(pane.groups) do
        for _, r in ipairs(g.rows) do
            if r.name == name then return g.id end
        end
    end
    return nil
end

tests["dungeon read 305: a quest filed outside goes to the dungeon all its objectives are in"] = function(t)
    local st = indexed(client({ more = true }))
    t.eq(st.dungeonOf[105], DM, "its one creature lives only in the Deadmines")
    t.eq(st.dungeonOf[106], nil, "objectives in two places: not filed")
end

tests["dungeon read 305: a giver at the entrance makes a follow-up the same run, not Later"] = function(t)
    local c = client({ more = true })
    local st = indexed(c)
    local pane = R.Pane(st, c, DM)
    t.eq(groupOf(pane, "At The Door"), "inside", "its giver stands at the door: same run")
    t.eq(groupOf(pane, "Deep Inside"), "inside", "its giver is inside")
    t.eq(groupOf(pane, "Red Silk"), "pickup", "a giver outside stays a pickup")
end

tests["dungeon read 305: without the entrance in Questie's list, the follow-up waits"] = function(t)
    local c = client({ more = true })
    local st = indexed(c)
    st.byKey[DM].entrances = {}
    st.quests = {}
    t.eq(groupOf(R.Pane(st, c, DM), "At The Door"), "later")
end

-- Lead section 305: the data for the Bosses tab: this account's own seen
-- loot (UI/BossLoot.lua keeps it, account "learned.bossLoot"), placed in a
-- dungeon by where Questie spawns the boss. No loot table of any kind.
-- The item and how often it was seen, of each loot row. Since lead section
-- 318 a row also carries the name, quality and icon the client read (pinned
-- in their own case below); these cases pin the order and the counts.
local function seen(items)
    local out = {}
    for i, it in ipairs(items or {}) do out[i] = { item = it.item, times = it.times } end
    return out
end

-- These cases are about what this account saw: no shipped list (lead
-- DISPATCH 426; the shipped list has its own cases below).
local EMPTY = { instances = {} }
local function ownLoot(st, c, key, b) return R.Loot(st, c, key, b, nil, EMPTY) end

local function book()
    return {
        -- As UI/BossLoot.lua writes them (B.Kill): npcs only on e: keys.
        ["e:1001"] = { name = "Cookie", kills = 3, npcs = { [601] = true },
            items = { ["item:1"] = { times = 1 }, ["item:2"] = { times = 3 } } },
        ["n:602"] = { name = "Outside Thug", kills = 1, items = { ["item:3"] = { times = 1 } } },
        ["e:1009"] = { name = "No Unit Seen", kills = 1, items = { ["item:4"] = { times = 1 } } },
    }
end

tests["dungeon read 305: the bosses of a dungeon with the loot this account saw, most seen first"] = function(t)
    local c = client({ more = true })
    local st = indexed(c)
    local loot = ownLoot(st, c, DM, book())
    t.eq(loot.why, nil)
    t.eq(#loot.bosses, 1, "only the boss that lives in the Deadmines")
    local b = loot.bosses[1]
    t.eq({ b.name, b.kills }, { "Cookie", 3 })
    t.eq(seen(b.items), { { item = 2, times = 3 }, { item = 1, times = 1 } })
    t.eq(loot.unplaced, 1, "a boss whose creature was never seen cannot be placed")
end

-- Twin review 17:11, F5: an n: entry (a creature killed outside an
-- encounter) has no npcs; its creature is in its key.
tests["dungeon read F5: an n: entry is placed by the creature in its key"] = function(t)
    local c = client({ more = true })
    local st = indexed(c)
    local loot = ownLoot(st, c, DM, { ["n:601"] = { name = "Cookie", kills = 2, items = { ["item:5"] = { times = 2 } } } })
    t.eq(loot.why, nil, "loot was seen: said, not hidden")
    t.eq(#loot.bosses, 1)
    t.eq(seen(loot.bosses[1].items), { { item = 5, times = 2 } })
end

-- F7: the e: and n: entries of one creature are one boss, as the boss
-- panel reads them (UI/BossLoot.lua B.Lookup).
tests["dungeon read F7: the encounter and the creature entries of one boss are one row"] = function(t)
    local c = client({ more = true })
    local st = indexed(c)
    local b = book()
    b["n:601"] = { name = "Cookie", kills = 1, items = { ["item:2"] = { times = 1 }, ["item:6"] = { times = 1 } } }
    local loot = ownLoot(st, c, DM, b)
    t.eq(#loot.bosses, 1, "one Cookie, not two")
    t.eq(loot.bosses[1].kills, 4)
    t.eq(seen(loot.bosses[1].items), { { item = 2, times = 4 }, { item = 1, times = 1 },
        { item = 6, times = 1 } })
end

-- F6: loot seen that cannot be placed says so, not "no loot seen".
tests["dungeon read F6: loot seen but placed nowhere says why"] = function(t)
    local c = client({ more = true })
    local st = indexed(c)
    local loot = ownLoot(st, c, DM, { ["e:1009"] = { name = "No Unit Seen", kills = 1, items = {} } })
    t.eq(loot.why, R.WHY_LOOT_UNPLACED)
    t.eq(#R.WHY_LOOT_UNPLACED, 2)
end

-- F1: a level not known stays not known.
tests["dungeon read F1: your level not known: the pane says so instead of guessing"] = function(t)
    local c = client({ noLevel = true })
    local st = indexed(c)
    t.eq(R.Pane(st, c, DM).why, R.WHY_NO_LEVEL)
    t.eq(#R.WHY_NO_LEVEL, 2)
end

-- F2: a quest whose hand-in is not known is listed and says so.
tests["dungeon read F2: not known whether a quest was handed in: listed, and the row says so"] = function(t)
    local c = client({ doneUnknown = true })
    c.setQuestDone(102, false)
    local st = indexed(c)
    local pane = R.Pane(st, c, DM)
    local notes = {}
    for _, g in ipairs(pane.groups) do
        for _, r in ipairs(g.rows) do notes[r.name] = r.note end
    end
    t.ok(notes["Red Silk"] and notes["Red Silk"]:find(R.DONE_UNKNOWN, 1, true) ~= nil, tostring(notes["Red Silk"]))
    t.eq(notes["Collecting Memories"], nil, "known not handed in: no such note")
    t.eq(pane.doneUnknown, 2)
end

-- F3: no quest list in Questie says why.
tests["dungeon read F3: Questie with no quest list says why, never an empty list"] = function(t)
    local c = client({ noPointers = true })
    local st = R.Start(c)
    t.eq(st.state, "failed")
    t.eq(R.Pane(st, c, DM).why, R.WHY_NO_IDS)
    t.eq(#R.WHY_NO_IDS, 2)
end

tests["dungeon read 305: no loot seen says so, never an empty tab"] = function(t)
    local c = client({ more = true })
    local st = indexed(c)
    t.eq(ownLoot(st, c, DM, nil).why, R.WHY_NO_LOOT)
    t.eq(ownLoot(st, c, SFK, book()).why, R.WHY_NO_LOOT, "nothing seen from this dungeon's bosses")
    t.eq(#R.WHY_NO_LOOT, 2)
    t.eq(ownLoot(R.Start(client({ questie = false })), c, DM, book()).why, S.WHY.noQuestie)
    t.eq(ownLoot(st, c, nil, book()).why, S.WHY.noDungeon)
end

-- Lead section 318: what the window shows and does, worked out here so the
-- window computes nothing.
tests["dungeon read 318: the entrance as a map point the waypoint takes"] = function(t)
    local c = client({ more = true })
    local st = indexed(c)
    local e = R.Entrance(st, c, DM)
    t.eq({ e.map, e.x, e.y, e.label }, { 1436, 42.5, 71.8, "The Deadmines" })
    t.eq(e.text, "42.5 71.8 The Deadmines", "the words the waypoint parses")
    local none, why = R.Entrance(st, c, SFK)
    t.eq(none, nil)
    t.eq(why, R.WHY_NO_ENTRANCE)
    t.eq(#R.WHY_NO_ENTRANCE, 2)
end

tests["dungeon read 318: search narrows the dungeon list, any case, empty text is all"] = function(t)
    local st = indexed(client())
    local list = R.List(st)
    local names = {}
    for i, d in ipairs(R.Search(list, "SHADOW")) do names[i] = d.name end
    t.eq(names, { "Shadowfang Keep" })
    t.eq(#R.Search(list, ""), 2)
    t.eq(#R.Search(list, nil), 2)
    t.eq(#R.Search(list, "zzz"), 0)
    t.eq(#R.Search(list, "("), 0, "a pattern sign is a plain letter")
end

tests["dungeon read 318: loot items carry their name, quality and icon as the client reads them"] = function(t)
    local c = client({ more = true })
    c.setItemInfo({ [2] = { name = "Cookie's Tenderizer", quality = 2 } })
    c.setItemTexture(2, "tex:tenderizer")
    local st = indexed(c)
    local items = ownLoot(st, c, DM, book()).bosses[1].items
    t.eq({ items[1].name, items[1].quality, items[1].icon }, { "Cookie's Tenderizer", 2, "tex:tenderizer" })
    t.eq(items[2].name, R.ITEM_UNREAD, "an item the client has not read yet says so")
end

-- Twin review 18:06, F4: a quality the kit cannot draw is left out, so one
-- odd item never stops the window.
tests["dungeon read F4: an item quality outside 0 to 5, or not whole, is left out"] = function(t)
    local c = client({ more = true })
    c.setItemInfo({ [2] = { name = "Odd", quality = 9 }, [1] = { name = "Half", quality = 2.5 } })
    local st = indexed(c)
    local items = ownLoot(st, c, DM, book()).bosses[1].items
    t.eq({ items[1].name, items[1].quality }, { "Odd", nil })
    t.eq({ items[2].name, items[2].quality }, { "Half", nil })
end

-- Lead DISPATCH 426: the boss list comes from a shipped table, never from
-- this account's kills. A made-up table, made-up creatures and items.
local function shipped()
    return { instances = { { id = 9001, area = DM, bosses = {
        { e = 501, npcs = { 601 }, items = { 11, 2 } },   -- the shipped list has it
        { e = 502, npcs = { 603 }, items = {} },          -- only the journal has it
        { npcs = { 604 }, items = {} },                   -- only Questie has it
        { npcs = { 605 }, items = {} },                   -- nothing has it
    } }, { id = 9002, area = SFK, bosses = { { npcs = { 701 }, items = { 31 } } } } } }
end

-- The made-up Questie, with one quest item (21) that creature 604 drops and
-- a name for 604.
local function withDrops(c)
    local db = c.questieModule("QuestieDB")
    local quest, npc = db.QueryQuestSingle, db.QueryNPCSingle
    function db.QueryQuestSingle(id, field)
        if id == 101 and field == "objectives" then return { nil, nil, { { 21 } } } end
        return quest(id, field)
    end
    function db.QueryNPCSingle(id, field)
        if id == 604 and field == "name" then return "Drop Giver" end
        return npc(id, field)
    end
    function db.QueryItemSingle(id, field)
        if id == 21 and field == "npcDrops" then return { 604, 605000 } end
        return nil
    end
    return c
end

local function ids(items)
    local out = {}
    for i, it in ipairs(items or {}) do out[i] = it.item end
    return out
end

-- Fails before: R.Loot built its list from the account's kills alone, so a
-- player who never ran the dungeon got R.WHY_NO_LOOT.
tests["dungeon read 426: every shipped boss and its drops show before the first kill"] = function(t)
    local c = client({ more = true })
    local st = indexed(c)
    local loot = R.Loot(st, c, DM, nil, nil, shipped())
    t.eq(loot.why, nil, "a list, not a reason")
    t.eq(#loot.bosses, 4, "the four bosses of this dungeon, none of the other one")
    local b = loot.bosses[1]
    t.eq({ b.name, b.named, b.kills, b.source }, { "Cookie", true, 0, "shipped" })
    t.eq(ids(b.items), { 11, 2 }, "in the shipped order")
    t.eq({ b.items[1].seen, b.items[2].seen }, { false, false }, "nothing seen yet")
    t.eq(#R.Loot(st, c, SFK, nil, nil, shipped()).bosses, 1, "the other dungeon has its own")
end

-- Fails before: the same, and no read order existed.
tests["dungeon read 426: read order is the shipped list, then the journal, then Questie"] = function(t)
    local c = withDrops(client({ more = true }))
    c.setJournal({ [501] = { name = "Journal Cookie", items = { 91 } },
        [502] = { name = "Journal Smith", items = { 41, 42 } } })
    local st = indexed(c)
    local loot = R.Loot(st, c, DM, nil, nil, shipped())
    local one, two, three, four = loot.bosses[1], loot.bosses[2], loot.bosses[3], loot.bosses[4]
    t.eq({ one.source, ids(one.items) }, { "shipped", { 11, 2 } }, "the journal does not replace a shipped list")
    t.eq(one.name, "Journal Cookie", "the journal's name comes first")
    t.eq({ two.name, two.source, ids(two.items) }, { "Journal Smith", "journal", { 41, 42 } })
    t.eq({ three.name, three.source, ids(three.items) }, { "Drop Giver", "questie", { 21 } })
    t.eq({ four.source, #four.items }, { nil, 0 }, "no source has it")
    -- The loot of the journal is asked only where the shipped list is empty.
    local asked = {}
    for _, a in ipairs(c.journalAsks) do asked[a.encounter] = a.withLoot end
    t.eq({ asked[501], asked[502] }, { false, true })
end

tests["dungeon read 426: a client with no journal still lists, from the shipped list and Questie"] = function(t)
    local c = withDrops(client({ more = true }))
    local st = indexed(c)
    local loot = R.Loot(st, c, DM, nil, nil, shipped())
    t.eq({ loot.bosses[1].name, loot.bosses[2].source, #loot.bosses[2].items }, { "Cookie", nil, 0 })
    t.eq(ids(loot.bosses[3].items), { 21 })
end

-- Fails before: kills were the list; there was no seen mark.
tests["dungeon read 426: own kills mark drops as seen and add what the list lacks, never the list"] = function(t)
    local c = client({ more = true })
    local st = indexed(c)
    local loot = R.Loot(st, c, DM, book(), nil, shipped())
    t.eq(#loot.bosses, 4, "Cookie is one row: the shipped boss, not a second one from the kills")
    local b = loot.bosses[1]
    t.eq(b.kills, 3)
    t.eq(ids(b.items), { 11, 2, 1 }, "shipped order, then the drop only this account saw")
    t.eq({ b.items[1].seen, b.items[2].seen, b.items[3].seen }, { false, true, true })
    t.eq(b.items[2].times, 3)
    t.eq(loot.bosses[2].kills, 0)
end

tests["dungeon read 426: a boss this account killed that the list lacks comes after the listed ones"] = function(t)
    local c = client({ more = true })
    local st = indexed(c)
    local data = { instances = { { id = 9001, area = DM, bosses = { { npcs = { 605 }, items = { 51 } } } } } }
    local loot = R.Loot(st, c, DM, book(), nil, data)
    t.eq(#loot.bosses, 2)
    t.eq({ loot.bosses[2].name, loot.bosses[2].source, loot.bosses[2].kills }, { "Cookie", "seen", 3 })
end

-- Fails before: R.BOSS_UNNAMED and R.BOSS_NO_DATA did not exist.
tests["dungeon read 426: a boss no source names is never a bare number; no data has plain words"] = function(t)
    local c = client({ more = true })
    local st = indexed(c)
    local loot = R.Loot(st, c, DM, nil, nil, shipped())
    local four = loot.bosses[4]
    t.eq({ four.name, four.named }, { R.BOSS_UNNAMED, false })
    t.ok(not R.BOSS_UNNAMED:find("%d"), "no number in the words")
    t.eq(loot.unnamed, 3, "603, 604 and 605: this Questie names none of them")
    t.eq(#R.BOSS_NO_DATA, 2)
    t.ok(not (R.BOSS_NO_DATA[1] .. R.BOSS_NO_DATA[2]):find("kill"), "not about kills")
    -- Named once seen at a kill.
    local later = R.Loot(st, c, DM, { ["n:605"] = { name = "Seen Once", kills = 1, items = {} } }, nil, shipped())
    t.eq({ later.bosses[4].name, later.bosses[4].named }, { "Seen Once", true })
end

tests["dungeon read 426: a shipped instance with no area id is placed by where Questie has its bosses"] = function(t)
    local c = client({ more = true })
    local st = indexed(c)
    local data = { instances = { { id = 9003, bosses = { { npcs = { 601 }, items = { 61 } } } },
        { id = 9004, bosses = { { npcs = { 999001 }, items = { 62 } } } } } }
    local loot = R.Loot(st, c, DM, nil, nil, data)
    t.eq(#loot.bosses, 1)
    t.eq(ids(loot.bosses[1].items), { 61 })
    t.eq(R.Loot(st, c, SFK, nil, nil, data).why, R.WHY_NO_LOOT, "placed nowhere: in no dungeon")
end

tests["dungeon read 426: a table that is not one, or holds odd rows, is no stop"] = function(t)
    local c = client({ more = true })
    local st = indexed(c)
    local odd = { instances = { 5, { id = 1, area = DM, bosses = { "x", { npcs = "no", items = { "a", 7 } } } },
        { id = 2, area = DM } } }
    local loot = R.Loot(st, c, DM, nil, nil, odd)
    t.eq(#loot.bosses, 1)
    t.eq(ids(loot.bosses[1].items), { 7 })
    t.eq(R.Loot(st, c, DM, nil, nil, { instances = "no" }).why, R.WHY_NO_LOOT)
end

-- The shipped table itself: its form, and that it is ids only.
tests["boss loot data 426: the shipped table is ids only, each instance with bosses"] = function(t)
    local data = ns.BossLootData
    t.ok(type(data) == "table" and type(data.instances) == "table", "the table is there")
    t.ok(type(data.commit) == "string" and #data.commit == 40, "the commit it was made from")
    t.ok(#data.instances > 0, "instances")
    local bad
    for _, inst in ipairs(data.instances) do
        if type(inst.id) ~= "number" or (inst.area ~= nil and type(inst.area) ~= "number") then bad = "instance" end
        for _, b in ipairs(inst.bosses) do
            for k, v in pairs(b) do
                if k ~= "e" and k ~= "npcs" and k ~= "items" then bad = "a field that is no id: " .. tostring(k) end
                if k == "e" and type(v) ~= "number" then bad = "encounter" end
            end
            for _, list in ipairs({ b.npcs, b.items }) do
                for _, id in ipairs(list) do
                    if type(id) ~= "number" then bad = "an id that is no number" end
                end
            end
        end
    end
    t.eq(bad, nil)
end

-- Lead DISPATCH 426 item 4. Fails before: R.JournalLine and
-- client.journalBoss did not exist.
tests["dungeon read 426: the diag line says whether the client's journal answers"] = function(t)
    local c = client()
    local no = R.JournalLine(c, shipped())
    t.ok(no:find("does not answer", 1, true) ~= nil, no)
    t.ok(no:find("instance 9001, encounter 501", 1, true) ~= nil, no)
    c.setJournal({ [501] = { name = "Journal Cookie", items = { 91, 92 } } })
    local yes = R.JournalLine(c, shipped())
    t.ok(yes:find("this client answers", 1, true) ~= nil, yes)
    t.ok(yes:find("name given, 2 items", 1, true) ~= nil, yes)
    c.setJournal({ [501] = { name = "Journal Cookie", items = { 91 } } }, true)
    t.ok(R.JournalLine(c, shipped()):find("loot not asked", 1, true) ~= nil, "the journal window is open")
    t.ok(R.JournalLine(c, { instances = {} }):find("not asked", 1, true) ~= nil)
    t.ok(R.JournalLine(c):find("dungeon journal", 1, true) ~= nil, "on the shipped table too")
end

tests["dungeon read 426: the diag word prints the journal line"] = function(t)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(2, 10)
    c.slashes[ns.id.slash]("diag")
    local found
    for _, line in ipairs(c.printed) do
        if tostring(line):find("dungeon journal: this client does not answer", 1, true) then found = true end
    end
    t.ok(found, "the line is in what the diag word prints")
end

return tests
