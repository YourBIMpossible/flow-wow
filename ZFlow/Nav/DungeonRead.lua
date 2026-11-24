-- The Dungeon Quests reader (lead section 303 item 7, data route A). Reads
-- Questie at runtime through the client (client.questieModule): its
-- dungeon list (ZoneDB:GetDungeons) and its quests (QuestieDB). No quest
-- or dungeon table ships here, and nothing of DungeonJournal is used. The
-- one shipped table is which items each boss can drop, as ids only
-- (Nav/BossLootData.lua, lead DISPATCH 426).
-- A port of the index of legacy Flow's Modules/Nav/Dungeons.lua
-- (buildDungeons, buildIndex, placer, giverInside, giverAtEntrance): a
-- quest belongs to the dungeon its zone is in, else the one dungeon all its
-- objectives are in (lead section 305). A giver inside, or within
-- R.DOOR map units of an entrance Questie lists, makes a follow-up the same
-- run.
--
--   R.Available(client) -> bool        Questie's two modules are there
--   R.Start(client) -> st              st.state: "noquestie" | "failed" |
--                                      "building" | "ready"
--   R.Step(st, client, n)              files the next n quests; "ready"
--                                      once all are filed
--   R.List(st) -> { { key, name, minQ, maxQ, ids } }   in level order
--   R.Pane(st, client, key) -> the pane (Nav/DungeonStates.lua S.Pane),
--                              or one saying why there is none yet
--   R.Loot(st, client, key, book, drops, data) -> the Bosses tab's data
--     (lead DISPATCH 426): every boss of the dungeon and what it can drop,
--     from the shipped table, else the client's dungeon journal, else
--     Questie. book is this account's own seen loot, account
--     "learned.bossLoot" as UI/BossLoot.lua keeps it: it marks the drops
--     seen, it does not make the list.
--   R.Ready(train, repair, bank) -> the "Get ready" steps to put before
--     a run (FLOW-PARITY B-52): each a place the player already saw.
--   R.JournalLine(client) -> one line for the diag word: whether the
--     client's dungeon journal answers
--
-- Client reads: questieModule, level, class, raceId, faction, questLog,
-- questDone, itemInfo, itemTexture, journalBoss. Only reads. Not tested in game: every Questie call here is
-- the one legacy Flow made, not seen through this add-on on 16001.
local _, ns = ...

local R = {}
ns.DungeonRead = R

local S = ns.DungeonStates

R.SLICE = 300   -- quests filed per step
R.DOOR = 4      -- map units (0..100) from an entrance that count as at the door (legacy)

-- Dire Maul's wings and Stratholme's Gauntlet are listed by Questie as
-- dungeons of their own: one dungeon here (legacy ALIAS). Battlegrounds
-- Questie lists with the dungeons are left out (legacy SKIP).
R.ALIAS = { [10022] = 2557, [10023] = 2557, [10024] = 2557, [10025] = 2557, [10026] = 2557, [10027] = 2557,
            [10001] = 2017 }
R.SKIP = { [2597] = true, [3277] = true, [3358] = true }

R.WHY_BUILDING = { "Reading Questie's dungeon quests.",
    "This takes a moment the first time; the list fills in by itself." }
R.WHY_NO_LEVEL = { "Your level is not known yet.",
    "It is read when you log in; open this again in a moment." }
R.WHY_NO_IDS = { "Questie gave no quest list.",
    "Update or re-enable the Questie add-on; type the slash command with diag to see what it offers." }
R.WHY_LOOT_UNPLACED = { "Boss loot was seen, but not where.",
    "The bosses it came from were never seen as a creature; kill one again with loot recording on." }
-- Added to a row when the client does not say whether the quest was handed
-- in (Twin review 17:11, F2): listed, and said, never taken as not done.
R.DONE_UNKNOWN = "not known whether you handed it in"
-- Lead section 318: for the window, which computes nothing itself.
R.WHY_NO_ENTRANCE = { "No entrance known for this dungeon.",
    "Questie lists none for it; walk there once and set a waypoint by hand with the way word." }
R.WHY_NO_MATCH = { "No dungeon matches the search.", "Clear the search box to see every dungeon." }
R.ITEM_UNREAD = "Item not read yet"
R.WHY_NO_LOOT = { "No boss list for this dungeon yet.",
    "Kill a boss of this dungeon with loot recording on and it is added here with what it dropped." }
-- Lead DISPATCH 426: a boss no source names is never a bare number.
R.BOSS_UNNAMED = "Boss not named yet (its name shows once you meet it)"
R.BOSS_NO_DATA = { "What this boss drops is not known yet.", "Drops you see from it are added here." }
R.SEEN = "you have seen this drop"
-- P-TRIP (S40): the dungeon run, R.Run below.
R.WHY_NO_RUN = { "Nothing to plan for this dungeon.",
    "No quest to pick up before you go has a giver Questie places, and no entrance is known." }
R.RUN_PICK_UP = "Pick up: %s"
R.RUN_GIVER = "Quest giver"
R.RUN_ENTRANCE = "Dungeon entrance"
R.WHY_LIST = { "Questie's dungeon list could not be read.",
    "Type the slash command with diag to see why." }

local function questieModule(client, name)
    if type(client) ~= "table" or type(client.questieModule) ~= "function" then return nil end
    local ok, m = pcall(client.questieModule, name)
    if ok and type(m) == "table" then return m end
    return nil
end

local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if ok then return v end
    return nil
end

function R.Available(client)
    return questieModule(client, "QuestieDB") ~= nil and questieModule(client, "ZoneDB") ~= nil
end

function R.Start(client)
    if not R.Available(client) then return { state = "noquestie" } end
    local zones = questieModule(client, "ZoneDB")
    local okList, list = false, nil
    if type(zones.GetDungeons) == "function" then okList, list = pcall(zones.GetDungeons, zones) end
    if not okList or type(list) ~= "table" then
        return { state = "failed", error = okList and "no list" or tostring(list) }
    end
    local byKey, areaTop = {}, {}
    local function top(area)
        local key = R.ALIAS[area] or area
        local d = byKey[key]
        if not d then
            local entry = type(list[key]) == "table" and list[key] or {}
            local name
            if type(zones.GetLocalizedDungeonName) == "function" then
                local okN, n = pcall(zones.GetLocalizedDungeonName, zones, key)
                if okN and type(n) == "string" and n ~= "" then name = n end
            end
            if not name and type(entry[1]) == "string" then name = entry[1] end
            d = { key = key, name = name or ("Dungeon " .. tostring(key)), ids = {}, areas = { [key] = true },
                  entrances = type(entry[4]) == "table" and entry[4] or {} }
            byKey[key] = d
            areaTop[key] = key
        end
        return d
    end
    for area, entry in pairs(list) do
        if type(area) == "number" and not R.SKIP[area] and type(entry) == "table" then
            local d = top(area)
            areaTop[area] = d.key
            d.areas[area] = true
            for _, alt in ipairs(type(entry[2]) == "table" and entry[2] or {}) do
                areaTop[alt] = d.key
                d.areas[alt] = true
            end
        end
    end
    local db = questieModule(client, "QuestieDB")
    local ids = {}
    if type(db.QuestPointers) == "table" then
        for id in pairs(db.QuestPointers) do
            if type(id) == "number" then ids[#ids + 1] = id end
        end
    end
    table.sort(ids)
    -- Twin review 17:11, F3: no quest list is said, never an empty list.
    if #ids == 0 then return { state = "failed", why = R.WHY_NO_IDS } end
    return { state = "building", byKey = byKey, areaTop = areaTop, ids = ids, at = 0, dungeonOf = {}, quests = {},
             place = { npc = {}, object = {}, item = {} } }
end

-- One field of quest id: the quick query when Questie has it, else the
-- quest itself.
local function field(db, id, name, questField)
    if type(db.QueryQuestSingle) == "function" then
        local ok, v = pcall(db.QueryQuestSingle, id, name)
        if ok then return v end
        return nil
    end
    if type(db.GetQuest) ~= "function" then return nil end
    local ok, qt = pcall(db.GetQuest, id)
    if ok and type(qt) == "table" then return qt[questField or name] end
    return nil
end

-- The dungeon a set of spawns ({ [area] = points }) lies in: its key, false
-- (outside or more than one place) or nil (no spawns).
local function topOf(st, spawns)
    if type(spawns) ~= "table" then return nil end
    local t
    for area in pairs(spawns) do
        local z = st.areaTop[area]
        if not z or (t and t ~= z) then return false end
        t = z
    end
    return t
end

local function merge(a, b)
    if a == false or b == false then return false end
    if a == nil then return b end
    if b == nil or a == b then return a end
    return false
end

-- The query of db for one kind of thing, or nil.
local function query(db, name, id, field)
    if type(db[name]) ~= "function" then return nil end
    local ok, v = pcall(db[name], id, field)
    if ok then return v end
    return nil
end

-- Where Questie places a creature, object or item: kept per id in st.place.
local function placeOf(st, db, kind, id)
    local cache = st.place[kind]
    if cache[id] == nil then
        local t
        if kind == "item" then
            local npcs = query(db, "QueryItemSingle", id, "npcDrops")
            for _, n in ipairs(type(npcs) == "table" and npcs or {}) do t = merge(t, placeOf(st, db, "npc", n)) end
            local objs = query(db, "QueryItemSingle", id, "objectDrops")
            for _, o in ipairs(type(objs) == "table" and objs or {}) do t = merge(t, placeOf(st, db, "object", o)) end
        else
            local fn = kind == "npc" and "QueryNPCSingle" or "QueryObjectSingle"
            t = topOf(st, query(db, fn, id, "spawns"))
        end
        if t == nil then cache[id] = "none" else cache[id] = t end
    end
    local t = cache[id]
    if t == "none" then return nil end
    return t
end

-- The dungeon all of a quest's objectives are in (Questie's raw form:
-- { creatures, objects, items, reputation, kill credit }), or nil.
local function placeByObjectives(st, db, obj)
    if type(obj) ~= "table" then return nil end
    local function each(v) return type(v) == "table" and v or {} end
    local tops = {}
    for _, c in ipairs(each(obj[1])) do tops[#tops + 1] = placeOf(st, db, "npc", each(c)[1]) end
    for _, o in ipairs(each(obj[2])) do tops[#tops + 1] = placeOf(st, db, "object", each(o)[1]) end
    for _, it in ipairs(each(obj[3])) do tops[#tops + 1] = placeOf(st, db, "item", each(it)[1]) end
    for _, kc in ipairs(each(obj[5])) do
        local t
        for _, n in ipairs(each(each(kc)[1])) do t = merge(t, placeOf(st, db, "npc", n)) end
        tops[#tops + 1] = t
    end
    return S.ObjectivesTop(tops)
end

function R.Step(st, client, n)
    if type(st) ~= "table" or st.state ~= "building" then return end
    local db = questieModule(client, "QuestieDB")
    if not db then
        st.state = "noquestie"
        return
    end
    local stop = math.min(#st.ids, st.at + (tonumber(n) or R.SLICE))
    for i = st.at + 1, stop do
        local id = st.ids[i]
        local zone = field(db, id, "zoneOrSort")
        local key = type(zone) == "number" and zone > 0 and st.areaTop[zone] or nil
        if not key and type(db.QueryQuestSingle) == "function" then
            key = placeByObjectives(st, db, query(db, "QueryQuestSingle", id, "objectives"))
        end
        if key then
            local d = st.byKey[key]
            d.ids[#d.ids + 1] = id
            st.dungeonOf[id] = key
            local lv = field(db, id, "questLevel", "level")
            if type(lv) == "number" and lv > 0 then
                d.minQ = math.min(d.minQ or lv, lv)
                d.maxQ = math.max(d.maxQ or lv, lv)
            end
        end
    end
    st.at = stop
    if st.at >= #st.ids then st.state = "ready" end
end

function R.List(st)
    local out = {}
    if type(st) ~= "table" or type(st.byKey) ~= "table" then return out end
    for _, d in pairs(st.byKey) do
        if #d.ids > 0 then out[#out + 1] = d end
    end
    return S.Order(out)
end

local function copyList(v)
    if type(v) ~= "table" then return nil end
    local out = {}
    for i, x in ipairs(v) do out[i] = x end
    return out
end

-- Quest id as a plain table of the fields the states read, with
-- giverFaction ("A", "H", "AH") from its first giver, or nil.
local function quest(st, db, id)
    local kept = st.quests[id]
    if kept ~= nil then return kept or nil end
    local qt
    if type(db.GetQuest) == "function" then
        local ok, v = pcall(db.GetQuest, id)
        if ok and type(v) == "table" then qt = v end
    end
    if not qt then
        st.quests[id] = false
        return nil
    end
    local starts = type(qt.Starts) == "table" and qt.Starts or {}
    local out = {
        Id = id, name = qt.name, level = qt.level, requiredLevel = qt.requiredLevel,
        preQuestSingle = copyList(qt.preQuestSingle), preQuestGroup = copyList(qt.preQuestGroup),
        exclusiveTo = copyList(qt.exclusiveTo), nextQuestInChain = qt.nextQuestInChain,
        requiredRaces = qt.requiredRaces, requiredClasses = qt.requiredClasses,
        requiredMinRep = qt.requiredMinRep, requiredMaxRep = qt.requiredMaxRep,
        requiredSkill = qt.requiredSkill, requiredSpell = qt.requiredSpell,
        startsByItem = not (type(starts.NPC) == "table" and starts.NPC[1])
            and not (type(starts.GameObject) == "table" and starts.GameObject[1])
            and (type(starts.Item) == "table" and starts.Item[1] ~= nil) or false,
    }
    local giver = type(starts.NPC) == "table" and starts.NPC[1] or nil
    if giver and type(db.GetNPC) == "function" then
        local ok, npc = pcall(db.GetNPC, giver)
        if ok and type(npc) == "table" then
            if type(npc.friendlyToFaction) == "string" then out.giverFaction = npc.friendlyToFaction end
            if type(npc.spawns) == "table" then out.giverSpawns = npc.spawns end
            if type(npc.name) == "string" and npc.name ~= "" then out.giverName = npc.name end
        end
    end
    st.quests[id] = out
    return out
end

-- The giver of q stands only inside dungeon d.
local function giverInside(q, d)
    if type(q.giverSpawns) ~= "table" then return false end
    local any = false
    for area in pairs(q.giverSpawns) do
        if not d.areas[area] then return false end
        any = true
    end
    return any
end

-- The giver of q stands inside d, or within R.DOOR of one of its entrances
-- ({ area, x, y }).
local function giverAtEntrance(q, d)
    if giverInside(q, d) then return true end
    if type(q.giverSpawns) ~= "table" then return false end
    for _, e in ipairs(d.entrances or {}) do
        local points = type(e) == "table" and q.giverSpawns[e[1]] or nil
        for _, p in ipairs(type(points) == "table" and points or {}) do
            if type(p) == "table" and type(p[1]) == "number" and type(p[2]) == "number"
                and type(e[2]) == "number" and type(e[3]) == "number"
                and math.abs(p[1] - e[2]) < R.DOOR and math.abs(p[2] - e[3]) < R.DOOR then
                return true
            end
        end
    end
    return false
end

local function waiting(why, title)
    return { title = title, why = why, groups = {}, count = 0, unplaced = 0 }
end

function R.Pane(st, client, key)
    if type(st) ~= "table" or st.state == "noquestie" then return S.Pane({ available = false }) end
    if st.state == "failed" then return waiting(st.why or R.WHY_LIST) end
    if st.state ~= "ready" then return waiting(R.WHY_BUILDING) end
    local d = key ~= nil and st.byKey[key] or nil
    if not d then return S.Pane({ available = true }) end
    local db = questieModule(client, "QuestieDB")
    if not db then return S.Pane({ available = false }) end
    -- Twin review 17:11, F1: a level not known is not level 0.
    local level = tonumber(ask(client, "level"))
    if not level then return waiting(R.WHY_NO_LEVEL, d.name) end
    local log, rows = {}, ask(client, "questLog")
    for _, row in ipairs(type(rows) == "table" and rows or {}) do
        if type(row) == "table" and type(row.id) == "number" then log[row.id] = true end
    end
    local unknown = {}
    local done = setmetatable({}, { __index = function(_, id)
        local v = ask(client, "questDone", id)
        if v == nil then unknown[id] = true end
        return v == true
    end })
    local class = ask(client, "class")
    local me = { raceId = ask(client, "raceId"), classId = class and S.CLASS_ID[class] or nil,
        faction = ask(client, "faction") }
    local ctx = {
        level = level,
        log = log, done = done,
        get = function(id) return quest(st, db, id) end,
        eligible = function(q) return S.Eligible(q, me) end,
        dungeonOf = function(id) return st.dungeonOf[id] end,
        inside = function(q) return q.startsByItem == true or giverInside(q, d) end,
        atEntrance = function(q) return giverAtEntrance(q, d) end,
    }
    local quests = {}
    for _, id in ipairs(d.ids) do
        local q = quest(st, db, id)
        if q then quests[#quests + 1] = q end
    end
    local pane = S.Pane({ available = true, dungeon = d, quests = quests, ctx = ctx })
    pane.doneUnknown = 0
    for _, g in ipairs(pane.groups) do
        for _, r in ipairs(g.rows) do
            if unknown[r.id] then
                r.note = r.note and (r.note .. "; " .. R.DONE_UNKNOWN) or R.DONE_UNKNOWN
                pane.doneUnknown = pane.doneUnknown + 1
            end
        end
    end
    return pane
end

-- The creatures a seen-loot entry names: the one in an n:<creature> key,
-- and the npcs an e:<encounter> entry kept (UI/BossLoot.lua B.Kill).
local function creaturesOf(key, entry)
    local out = {}
    local n = type(key) == "string" and tonumber(key:match("^n:(%d+)$")) or nil
    if n then out[#out + 1] = n end
    for npc in pairs(type(entry.npcs) == "table" and entry.npcs or {}) do
        if type(npc) == "number" then out[#out + 1] = npc end
    end
    return out
end

-- One item row: its name, quality and icon as the client reads them (lead
-- section 318); one not read yet says so and is counted by the caller.
local function itemRow(client, item, times)
    local it = { item = item, times = times or 0, seen = (times or 0) > 0 }
    local info = ask(client, "itemInfo", item)
    if type(info) == "table" then
        if type(info.name) == "string" and info.name ~= "" then it.name = info.name end
        -- Twin review 18:06, F4: only a quality the kit draws
        -- (whole, 0 to 5); any other is left out, never a stop.
        local q = info.quality
        if type(q) == "number" and q >= 0 and q <= 5 and q == math.floor(q) then it.quality = q end
    end
    if not it.name then it.name, it.unread = R.ITEM_UNREAD, true end
    local icon = ask(client, "itemTexture", item)
    if type(icon) == "string" or type(icon) == "number" then it.icon = icon end
    return it
end

local function idList(v)
    local out = {}
    for _, id in ipairs(type(v) == "table" and v or {}) do
        if type(id) == "number" then out[#out + 1] = id end
    end
    return out
end

-- The shipped instances (Nav/BossLootData.lua) that are the dungeon d: by
-- the area id both name; one with no area id by where Questie places its
-- creatures. Kept per table and dungeon in st.
local function instancesOf(st, db, d, data)
    st.lootInst = st.lootInst or {}
    local cache = st.lootInst[data]
    if not cache then
        cache = {}
        st.lootInst[data] = cache
    end
    if cache[d.key] then return cache[d.key] end
    local list = {}
    for _, inst in ipairs(type(data.instances) == "table" and data.instances or {}) do
        if type(inst) == "table" then
            local at
            if type(inst.area) == "number" then
                at = R.ALIAS[inst.area] or inst.area
            else
                for _, b in ipairs(type(inst.bosses) == "table" and inst.bosses or {}) do
                    for _, npc in ipairs(idList(type(b) == "table" and b.npcs or nil)) do
                        at = at or placeOf(st, db, "npc", npc) or nil
                    end
                    if at then break end
                end
            end
            if at == d.key then list[#list + 1] = inst end
        end
    end
    cache[d.key] = list
    return list
end

-- What Questie says the creatures of this dungeon drop for its quests:
-- { [creature] = { item, ... } }. The same read original Flow made
-- (Modules/Nav/Dungeons.lua droppers(): QueryItemSingle(item, "npcDrops")),
-- over the items the quests of the dungeon ask for. Kept per dungeon in st.
local function questDrops(st, db, d)
    st.lootQuest = st.lootQuest or {}
    if st.lootQuest[d.key] then return st.lootQuest[d.key] end
    local out, had = {}, {}
    for _, id in ipairs(type(d.ids) == "table" and d.ids or {}) do
        local obj = query(db, "QueryQuestSingle", id, "objectives")
        for _, entry in ipairs(type(obj) == "table" and type(obj[3]) == "table" and obj[3] or {}) do
            local item = type(entry) == "table" and entry[1] or nil
            if type(item) == "number" and not had[item] then
                had[item] = true
                for _, npc in ipairs(idList(query(db, "QueryItemSingle", item, "npcDrops"))) do
                    out[npc] = out[npc] or {}
                    out[npc][#out[npc] + 1] = item
                end
            end
        end
    end
    st.lootQuest[d.key] = out
    return out
end

-- What this account saw from the creatures npcs (UI/BossLoot.lua B.Lookup,
-- the boss panel's own reading): { name, kills, items = { [item key] = times } }.
local function ownOf(book, drops, npcs)
    local B = ns.BossLoot
    local out = { kills = 0, items = {} }
    if type(B) ~= "table" or type(B.Lookup) ~= "function" then return out end
    for _, npc in ipairs(npcs) do
        local ok, got = pcall(B.Lookup, book, drops, { npc = npc })
        if ok and type(got) == "table" then
            if out.name == nil and type(got.name) == "string" and got.name ~= "" then out.name = got.name end
            local kills = tonumber(got.kills) or 0
            if kills > out.kills then out.kills = kills end
            for item, times in pairs(type(got.items) == "table" and got.items or {}) do
                if type(times) == "number" and times > 0 and times > (out.items[item] or 0) then
                    out.items[item] = times
                end
            end
        end
    end
    return out
end

local function byTimes(a, b)
    if a.times ~= b.times then return a.times > b.times end
    return tostring(a.item) < tostring(b.item)
end

-- The bosses of a dungeon and what each can drop (lead DISPATCH 426; the
-- owner: "We need to populate the loot table from research data. We can't
-- just populate it by how many times you fought a boss."). The list comes,
-- for each boss, from the first of these that has items:
--   1. the shipped table (Nav/BossLootData.lua; data, for the tests);
--   2. the client's own dungeon journal, where the client answers
--      (client.journalBoss) and the boss has an encounter id;
--   3. Questie: the quest items it says the creatures of the boss drop.
-- What this account saw (book, drops) never makes the list: it marks a row
-- as seen (it.seen, it.times), and adds a drop it saw that no list has. A
-- boss this account killed that no list names is still shown, after the
-- listed ones, as before. The name of a boss: the journal's, else
-- Questie's, else the one seen at a kill, else R.BOSS_UNNAMED (b.named
-- false).
--   -> { title, bosses = { { name, named, kills, source, items = { { item,
--        times, seen, name, quality, icon, unread } } } }, unplaced, unread,
--        unnamed, why }
-- Twin review 17:11 stands: F5 (n: entries are placed by their key), F6
-- (loot placed nowhere says so), F7 (one boss from its e: and n: entries).
function R.Loot(st, client, key, book, drops, data)
    if type(st) ~= "table" or st.state == "noquestie" then return S.Pane({ available = false }) end
    if st.state == "failed" then return waiting(st.why or R.WHY_LIST) end
    if st.state ~= "ready" then return waiting(R.WHY_BUILDING) end
    local d = key ~= nil and st.byKey[key] or nil
    if not d then return S.Pane({ available = true }) end
    local db = questieModule(client, "QuestieDB")
    if not db then return S.Pane({ available = false }) end
    if type(data) ~= "table" then data = type(ns.BossLootData) == "table" and ns.BossLootData or {} end
    local out = { title = d.name, bosses = {}, unplaced = 0, unread = 0, unnamed = 0 }
    book = type(book) == "table" and book or {}
    local covered = {}

    local function finish(b, items)
        for _, it in ipairs(items) do
            if it.unread then out.unread = out.unread + 1 end
        end
        b.items = items
        if not b.named then out.unnamed = out.unnamed + 1 end
        out.bosses[#out.bosses + 1] = b
    end

    local function cover(npc)
        covered[npc] = true
        -- The other creatures of the same kills are this boss too.
        for k, entry in pairs(book) do
            if type(entry) == "table" and type(entry.npcs) == "table" and entry.npcs[npc] == true then
                for _, other in ipairs(creaturesOf(k, entry)) do covered[other] = true end
            end
        end
    end

    local function questieName(npcs)
        for _, npc in ipairs(npcs) do
            local n = query(db, "QueryNPCSingle", npc, "name")
            if type(n) == "string" and n ~= "" then return n end
        end
        return nil
    end

    local quest
    for _, inst in ipairs(instancesOf(st, db, d, data)) do
        for _, boss in ipairs(type(inst.bosses) == "table" and inst.bosses or {}) do
            if type(boss) == "table" then
                local npcs = idList(boss.npcs)
                for _, npc in ipairs(npcs) do cover(npc) end
                local list, source = idList(boss.items), "shipped"
                local journal
                if type(boss.e) == "number" then
                    journal = ask(client, "journalBoss", inst.id, boss.e, #list == 0)
                    if type(journal) ~= "table" then journal = nil end
                end
                if #list == 0 and journal then list, source = idList(journal.items), "journal" end
                if #list == 0 then
                    quest = quest or questDrops(st, db, d)
                    local had = {}
                    for _, npc in ipairs(npcs) do
                        for _, item in ipairs(quest[npc] or {}) do
                            if not had[item] then
                                had[item] = true
                                list[#list + 1] = item
                            end
                        end
                    end
                    source = "questie"
                end
                local own = ownOf(book, drops, npcs)
                local name = journal and type(journal.name) == "string" and journal.name ~= "" and journal.name or nil
                name = name or questieName(npcs) or own.name
                local items, listed = {}, {}
                for _, item in ipairs(list) do
                    listed[item] = true
                    items[#items + 1] = itemRow(client, item, own.items[item])
                end
                local extra = {}
                for item, times in pairs(own.items) do
                    if not listed[item] then extra[#extra + 1] = { item = item, times = times } end
                end
                table.sort(extra, byTimes)
                for _, e in ipairs(extra) do items[#items + 1] = itemRow(client, e.item, e.times) end
                if #list == 0 then source = #extra > 0 and "seen" or nil end
                finish({ name = name or R.BOSS_UNNAMED, named = name ~= nil, kills = own.kills, source = source,
                    encounter = type(boss.e) == "number" and boss.e or nil }, items)
            end
        end
    end

    -- What this account killed here that no list names.
    local here, seen, named = {}, false, false
    for k, entry in pairs(book) do
        if type(entry) == "table" then
            seen = true
            local creatures = creaturesOf(k, entry)
            if #creatures == 0 then out.unplaced = out.unplaced + 1 else named = true end
            for _, npc in ipairs(creatures) do
                if not covered[npc] and placeOf(st, db, "npc", npc) == d.key then here[npc] = true end
            end
        end
    end
    local npcs = {}
    for npc in pairs(here) do npcs[#npcs + 1] = npc end
    table.sort(npcs)
    local extras = {}
    for _, npc in ipairs(npcs) do
        if not covered[npc] then
            cover(npc)
            local own = ownOf(book, drops, { npc })
            local items = {}
            for item, times in pairs(own.items) do items[#items + 1] = { item = item, times = times } end
            table.sort(items, byTimes)
            for i, it in ipairs(items) do items[i] = itemRow(client, it.item, it.times) end
            local name = own.name or questieName({ npc })
            extras[#extras + 1] = { b = { name = name or R.BOSS_UNNAMED, named = name ~= nil, kills = own.kills,
                source = "seen" }, items = items }
        end
    end
    table.sort(extras, function(a, b) return tostring(a.b.name) < tostring(b.b.name) end)
    for _, e in ipairs(extras) do finish(e.b, e.items) end
    if #out.bosses == 0 then
        -- Loot seen, none of it tied to any creature: that, not "no loot".
        out.why = (seen and not named) and R.WHY_LOOT_UNPLACED or R.WHY_NO_LOOT
    end
    return out
end

-- One line for `<slash> diag` (lead DISPATCH 426 item 4): whether the
-- dungeon journal of this client answers for the first shipped boss that
-- has an encounter id. Read only.
function R.JournalLine(client, data)
    if type(data) ~= "table" then data = type(ns.BossLootData) == "table" and ns.BossLootData or {} end
    for _, inst in ipairs(type(data.instances) == "table" and data.instances or {}) do
        for _, boss in ipairs(type(inst) == "table" and type(inst.bosses) == "table" and inst.bosses or {}) do
            if type(boss) == "table" and type(boss.e) == "number" then
                local at = "instance " .. tostring(inst.id) .. ", encounter " .. tostring(boss.e)
                local got = ask(client, "journalBoss", inst.id, boss.e, true)
                if type(got) ~= "table" then
                    return "dungeon journal: this client does not answer (" .. at
                        .. "); boss loot comes from the shipped list."
                end
                return "dungeon journal: this client answers (" .. at .. "): name "
                    .. (type(got.name) == "string" and "given" or "not given") .. ", "
                    .. tostring(#idList(got.items)) .. " items"
                    .. (got.shown and " (journal window open: loot not asked)" or "") .. "."
            end
        end
    end
    return "dungeon journal: not asked; the shipped list names no encounter."
end

-- The dungeons of list whose name holds text, any case, as plain letters.
-- Empty or no text: the whole list.
function R.Search(list, text)
    local out = {}
    local want = type(text) == "string" and text:lower() or ""
    for _, d in ipairs(type(list) == "table" and list or {}) do
        if want == "" or (type(d.name) == "string" and d.name:lower():find(want, 1, true) ~= nil) then
            out[#out + 1] = d
        end
    end
    return out
end

-- Questie's area as the game's map, or nil (the call taken with or without
-- its module, as Nav/QuestRead.lua takes it).
local function mapOf(zones, area)
    if type(zones) ~= "table" or type(zones.GetUiMapIdByAreaId) ~= "function" then return nil end
    local ok, m = pcall(zones.GetUiMapIdByAreaId, area)
    if ok and type(m) == "number" then return m end
    ok, m = pcall(zones.GetUiMapIdByAreaId, zones, area)
    if ok and type(m) == "number" then return m end
    return nil
end

-- The first entrance Questie lists for dungeon key, as the waypoint takes
-- it: { map, x, y (percents), label, text = "x y label" }; or nil, why.
function R.Entrance(st, client, key)
    local d = type(st) == "table" and type(st.byKey) == "table" and key ~= nil and st.byKey[key] or nil
    local e = d and type(d.entrances) == "table" and d.entrances[1] or nil
    if type(e) ~= "table" or type(e[2]) ~= "number" or type(e[3]) ~= "number" then return nil, R.WHY_NO_ENTRANCE end
    local map = mapOf(questieModule(client, "ZoneDB"), e[1])
    if not map then return nil, R.WHY_NO_ENTRANCE end
    local label = d.name
    if type(label) ~= "string" or #label > 40 or label:find("[%c|]") then label = nil end
    local text = string.format("%.1f %.1f", e[2], e[3]) .. (label and (" " .. label) or "")
    return { map = map, x = e[2], y = e[3], label = label, text = text }
end

-- Where Questie places the giver of q, as a waypoint takes it: { map, x, y }
-- in shares 0..1. Of the giver's areas the lowest one that is a map, its
-- first point: the same every time. nil when not known.
local function giverPlace(zones, q)
    if type(q) ~= "table" or type(q.giverSpawns) ~= "table" then return nil end
    local areas = {}
    for area in pairs(q.giverSpawns) do
        if type(area) == "number" then areas[#areas + 1] = area end
    end
    table.sort(areas)
    for _, area in ipairs(areas) do
        local map = mapOf(zones, area)
        local p = map and q.giverSpawns[area][1]
        if type(p) == "table" and type(p[1]) == "number" and type(p[2]) == "number"
            and p[1] >= 0 and p[1] <= 100 and p[2] >= 0 and p[2] <= 100 then
            return { map = map, x = p[1] / 100, y = p[2] / 100 }
        end
    end
    return nil
end

-- The dungeon run for key (P-TRIP, S40; the rule of legacy Flow's
-- Dungeons.lua Prepare, no data of it): the givers of the quests to pick up
-- before you go, nearest next from where the player stands (givers on the
-- player's map first, then by map), then the entrance (R.Entrance).
--   -> { title, steps = { { kind = "giver" | "entrance", quest, label,
--        detail, place = { map, x, y } } }, left = { quest names whose
--        giver has no known place } }, or nil and why lines.
function R.Run(st, client, key)
    if type(st) ~= "table" or st.state ~= "ready" then
        local pane = R.Pane(st, client, key)
        return nil, pane.why or R.WHY_NO_RUN
    end
    local d = key ~= nil and st.byKey[key] or nil
    if not d then return nil, R.WHY_NO_RUN end
    local zones = questieModule(client, "ZoneDB")
    local pane = R.Pane(st, client, key)
    local givers, left = {}, {}
    for _, g in ipairs(type(pane.groups) == "table" and pane.groups or {}) do
        if g.id == "pickup" then
            for _, r in ipairs(g.rows) do
                local q = st.quests[r.id]
                local place = q and giverPlace(zones, q) or nil
                if place then
                    givers[#givers + 1] = { kind = "giver", quest = r.id, label = R.RUN_PICK_UP:format(r.name),
                        detail = q.giverName or R.RUN_GIVER, place = place }
                else
                    left[#left + 1] = r.name
                end
            end
        end
    end
    -- Nearest next: on the same map as the last stop by distance, else the
    -- lowest map. Ties keep the pane's order.
    local at = ask(client, "position")
    local last = type(at) == "table" and at or nil
    local steps = {}
    while #givers > 0 do
        local best, bestSame, bestD
        for i, s in ipairs(givers) do
            local same = last ~= nil and s.place.map == last.map
                and type(last.x) == "number" and type(last.y) == "number"
            local dist
            if same then
                local dx, dy = s.place.x - last.x, s.place.y - last.y
                dist = dx * dx + dy * dy
            else
                dist = type(s.place.map) == "number" and s.place.map or 0
            end
            if best == nil or (same and not bestSame) or (same == bestSame and dist < bestD) then
                best, bestSame, bestD = i, same, dist
            end
        end
        local s = table.remove(givers, best)
        steps[#steps + 1] = s
        last = s.place
    end
    local e = R.Entrance(st, client, key)
    if e then
        steps[#steps + 1] = { kind = "entrance", label = d.name, detail = R.RUN_ENTRANCE,
            place = { map = e.map, x = e.x / 100, y = e.y / 100 } }
    end
    if #steps == 0 then return nil, R.WHY_NO_RUN end
    return { title = d.name, steps = steps, left = left }
end

-- FLOW-PARITY B-52 (lead section 471): "Get ready on the way" before the
-- run, as advice steps put in front of it (Flow's Dungeons.lua Prepare
-- lists them): training due, a repair (sell there too) while the gear is
-- low, the bank. Each is a stop the player already saw; the player does
-- each, nothing trains, sells, repairs or banks for them.
--   R.Ready(train, repair, bank) -> steps
--     train, repair: steps as classTrainerStep / repairStep give them, or nil
--     bank: an Errand place { kind = "banker", name, map, x, y } or nil
R.READY = "Get ready: %s"
R.READY_TRAIN = "Train"
R.READY_REPAIR = "Sell and repair"
R.READY_BANK = "Bank"

local function readyStep(what, src, place)
    if type(place) ~= "table" or place.map == nil or type(place.x) ~= "number" or type(place.y) ~= "number" then
        return nil
    end
    local detail
    if type(src) == "table" and type(src.label) == "string" then detail = src.label end
    return { kind = "ready", label = R.READY:format(what), detail = detail,
             place = { map = place.map, x = place.x, y = place.y } }
end

function R.Ready(train, repair, bank)
    local out = {}
    local function add(s) if s then out[#out + 1] = s end end
    if type(train) == "table" then add(readyStep(R.READY_TRAIN, train, train.place)) end
    if type(repair) == "table" then add(readyStep(R.READY_REPAIR, repair, repair.place)) end
    if type(bank) == "table" then
        local name
        if type(bank.name) == "string" and bank.name ~= "" then name = bank.name end
        add(readyStep(R.READY_BANK, { label = name }, bank))
    end
    return out
end

-- The dungeon the client's instance name names (lead section 303 (d)), by
-- Questie's name for it, any case; nil when none matches or the list is not
-- read. A name Questie spells differently is not guessed at.
function R.DungeonNamed(st, name)
    if type(st) ~= "table" or type(st.byKey) ~= "table" or type(name) ~= "string" or name == "" then return nil end
    local want = name:lower()
    for _, d in pairs(st.byKey) do
        if type(d.name) == "string" and d.name:lower() == want then return d end
    end
    return nil
end
