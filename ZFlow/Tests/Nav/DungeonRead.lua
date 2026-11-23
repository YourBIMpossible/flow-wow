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
    local npcs = {
        [501] = { name = "Gryan", friendlyToFaction = "A" },
        [502] = { name = "Wilder", friendlyToFaction = "A" },
        [503] = { name = "High Sorcerer", friendlyToFaction = "AH" },
    }
    local db = { QuestPointers = {} }
    for id in pairs(quests) do db.QuestPointers[id] = true end
    function db.GetQuest(id) return quests[id] end
    function db.GetNPC(id) return npcs[id] end
    if not over.noQuery then
        function db.QueryQuestSingle(id, field)
            local qt = quests[id]
            if not qt then return nil end
            if field == "questLevel" then return qt.level end
            return qt[field]
        end
    end
    local zones = {}
    function zones:GetDungeons()
        if over.badList then error("no list") end
        return { [DM] = { "The Deadmines" }, [SFK] = { "Shadowfang Keep" }, [AV] = { "Alterac Valley" } }
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
    c.setLevel(opts.level or 18)
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

return tests
