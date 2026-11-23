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
    local loot = R.Loot(st, c, DM, book())
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
    local loot = R.Loot(st, c, DM, { ["n:601"] = { name = "Cookie", kills = 2, items = { ["item:5"] = { times = 2 } } } })
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
    local loot = R.Loot(st, c, DM, b)
    t.eq(#loot.bosses, 1, "one Cookie, not two")
    t.eq(loot.bosses[1].kills, 4)
    t.eq(seen(loot.bosses[1].items), { { item = 2, times = 4 }, { item = 1, times = 1 },
        { item = 6, times = 1 } })
end

-- F6: loot seen that cannot be placed says so, not "no loot seen".
tests["dungeon read F6: loot seen but placed nowhere says why"] = function(t)
    local c = client({ more = true })
    local st = indexed(c)
    local loot = R.Loot(st, c, DM, { ["e:1009"] = { name = "No Unit Seen", kills = 1, items = {} } })
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
    t.eq(R.Loot(st, c, DM, nil).why, R.WHY_NO_LOOT)
    t.eq(R.Loot(st, c, SFK, book()).why, R.WHY_NO_LOOT, "nothing seen from this dungeon's bosses")
    t.eq(#R.WHY_NO_LOOT, 2)
    t.eq(R.Loot(R.Start(client({ questie = false })), c, DM, book()).why, S.WHY.noQuestie)
    t.eq(R.Loot(st, c, nil, book()).why, S.WHY.noDungeon)
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
    local items = R.Loot(st, c, DM, book()).bosses[1].items
    t.eq({ items[1].name, items[1].quality, items[1].icon }, { "Cookie's Tenderizer", 2, "tex:tenderizer" })
    t.eq(items[2].name, R.ITEM_UNREAD, "an item the client has not read yet says so")
end

-- Twin review 18:06, F4: a quality the kit cannot draw is left out, so one
-- odd item never stops the window.
tests["dungeon read F4: an item quality outside 0 to 5, or not whole, is left out"] = function(t)
    local c = client({ more = true })
    c.setItemInfo({ [2] = { name = "Odd", quality = 9 }, [1] = { name = "Half", quality = 2.5 } })
    local st = indexed(c)
    local items = R.Loot(st, c, DM, book()).bosses[1].items
    t.eq({ items[1].name, items[1].quality }, { "Odd", nil })
    t.eq({ items[2].name, items[2].quality }, { "Half", nil })
end

return tests
