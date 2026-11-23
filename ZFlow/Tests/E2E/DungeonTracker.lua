-- The in-dungeon tracker (lead section 303 item 8 (d)), end to end on the
-- whole add-on loaded on a fake client: inside a dungeon, a small kit
-- window lists the bosses killed this visit (Nav/BossKills.lua) and this
-- dungeon's quests in your log (Nav/DungeonRead.lua). It shows nothing
-- outside, when switched off, or when the client cannot report boss kills.
-- A made-up Questie; no quest data of any add-on. Not tested in game.
local _, ns = ...
local tests = {}

local ID = "dungeonTracker"
local DM = 1581

local function questie(opts)
    opts = opts or {}
    local quests = {
        [101] = { Id = 101, name = "Red Silk", level = 18, requiredLevel = 14, zoneOrSort = DM,
            Starts = { NPC = { 501 } } },
        [102] = { Id = 102, name = "Collecting Memories", level = 18, requiredLevel = 14, zoneOrSort = DM,
            Starts = { NPC = { 501 } } },
    }
    local db = { QuestPointers = { [101] = true, [102] = true } }
    function db.GetQuest(id) return quests[id] end
    function db.GetNPC() return { name = "Gryan", friendlyToFaction = "A" } end
    function db.QueryQuestSingle(id, field)
        local q = quests[id]
        if not q then return nil end
        if field == "questLevel" then return q.level end
        return q[field]
    end
    local zones = {}
    function zones:GetDungeons()
        if opts.badList then error("no list (test)") end
        return { [DM] = { "The Deadmines" } }
    end
    return db, zones
end

-- opts: refused (event names the client does not take), outside (not in an
-- instance), name (the instance name the client says), account (saved),
-- questie (false: none), badList (Questie's dungeon list raises), noLevel.
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {}); c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setRaceId(1); c.setFaction("Alliance")
    if opts.noLevel then c.setLevel(nil) else c.setLevel(18) end
    c.setQuestDone(101, false); c.setQuestDone(102, false)
    c.setQuestLog({ { id = 101, title = "Red Silk", objectives = {} } })
    for _, e in ipairs(opts.refused or {}) do c.setEventFault(e, true) end
    if opts.outside then
        c.setInstance({ inside = false, kind = "none" })
    else
        c.setInstance({ inside = true, kind = "party" })
        c.setInstanceName(opts.name or "The Deadmines")
    end
    if opts.questie ~= false then
        local db, zones = questie(opts)
        c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(3, 30)
    return c, addon
end

local function texts(rec)
    local out = {}
    for _, p in ipairs(rec and rec.parts or {}) do
        if p.text ~= nil then out[#out + 1] = tostring(p.text) end
    end
    return table.concat(out, " | ")
end

local function shown(c)
    local rec = c.kitWindows()[ID]
    return rec ~= nil and rec.shown == true, rec
end

tests["dungeon tracker: inside a dungeon it shows this dungeon's quests in your log and no kill yet"] = function(t)
    local c = boot()
    local on, rec = shown(c)
    t.eq(on, true, "shown inside")
    local words = texts(rec)
    t.ok(words:find("Red Silk", 1, true) ~= nil, "the quest in your log: " .. words)
    t.ok(words:find("Collecting Memories", 1, true) == nil, "a quest not in your log is not listed")
    t.ok(words:find(ns.DungeonTracker.NO_KILL, 1, true) ~= nil, "no boss yet says so")
end

tests["dungeon tracker: a boss killed is listed at once"] = function(t)
    local c = boot()
    c.fire("ENCOUNTER_END", 1001, "Rhahk'Zor", 1, 5, 1)
    c.advance(0.2, 2)
    local _, rec = shown(c)
    t.ok(texts(rec):find("Rhahk'Zor", 1, true) ~= nil, texts(rec))
end

tests["dungeon tracker: nothing when the client cannot report boss kills"] = function(t)
    local c = boot({ refused = { "ENCOUNTER_END", "BOSS_KILL" } })
    t.eq((shown(c)), false)
    local c2 = boot({ refused = { "BOSS_KILL" } })
    t.eq((shown(c2)), true, "one of the two is enough")
end

tests["dungeon tracker: nothing outside a dungeon, and hidden on leaving"] = function(t)
    local c = boot({ outside = true })
    t.eq((shown(c)), false)
    local c2 = boot()
    t.eq((shown(c2)), true)
    c2.setInstance({ inside = false, kind = "none" })
    c2.fire("PLAYER_ENTERING_WORLD")
    c2.advance(0.2, 2)
    t.eq((shown(c2)), false, "hidden on leaving")
end

tests["dungeon tracker: its setting, on by default, switches it off"] = function(t)
    local c, addon = boot()
    local row = addon.settings:row(ns.DungeonTracker.SETTING)
    t.ok(row ~= nil, "a settings row")
    t.eq(row and row.default, true)
    t.ok(row and type(row.help) == "string" and row.help:find("boss kills", 1, true) ~= nil, "says when it shows")
    addon.settings:set(ns.DungeonTracker.SETTING, false)
    c.advance(0.2, 2)
    t.eq((shown(c)), false)
end

tests["dungeon tracker: a dungeon the list does not know still lists the kills, and says it"] = function(t)
    local c = boot({ name = "Nowhere Keep" })
    c.fire("ENCOUNTER_END", 1001, "Somebody", 1, 5, 1)
    c.advance(0.2, 2)
    local on, rec = shown(c)
    t.eq(on, true)
    t.ok(texts(rec):find("Somebody", 1, true) ~= nil, texts(rec))
    t.ok(texts(rec):find(ns.DungeonTracker.NOT_KNOWN, 1, true) ~= nil, texts(rec))
end

-- Twin review (lead section 286): the tracker says the real reason, never
-- "no quest" or "not known which dungeon" in its place.
tests["dungeon tracker 286: your level not known says so, not that you have no quest here"] = function(t)
    local c = boot({ noLevel = true })
    local _, rec = shown(c)
    local words = texts(rec)
    t.ok(words:find(ns.DungeonRead.WHY_NO_LEVEL[1], 1, true) ~= nil, words)
    t.ok(words:find(ns.DungeonTracker.NO_QUEST, 1, true) == nil, "not the no-quest line")
end

tests["dungeon tracker 286: no Questie, or a dungeon list that failed, says so, not that the dungeon is unknown"] = function(t)
    local c = boot({ questie = false })
    local _, rec = shown(c)
    local words = texts(rec)
    t.ok(words:find(ns.DungeonStates.WHY.noQuestie[1], 1, true) ~= nil, words)
    t.ok(words:find(ns.DungeonTracker.NOT_KNOWN, 1, true) == nil, "not the unknown-dungeon line")
    local c2 = boot({ badList = true })
    local _, rec2 = shown(c2)
    local words2 = texts(rec2)
    t.ok(words2:find(ns.DungeonRead.WHY_LIST[1], 1, true) ~= nil, words2)
    t.ok(words2:find(ns.DungeonTracker.NOT_KNOWN, 1, true) == nil, "not the unknown-dungeon line")
end

-- Twin low note: once stopped, a later refresh shows nothing.
tests["dungeon tracker: stopped, it does not come back on a refresh"] = function(t)
    local c, addon = boot()
    t.eq((shown(c)), true)
    addon:SwitchOff(ns.DungeonTracker.NAME, "test")
    t.eq((shown(c)), false, "hidden when stopped")
    c.fire("PLAYER_ENTERING_WORLD")
    c.fire("ENCOUNTER_END", 1001, "Rhahk'Zor", 1, 5, 1)
    c.advance(0.2, 2)
    t.eq((shown(c)), false, "still hidden")
end

return tests
