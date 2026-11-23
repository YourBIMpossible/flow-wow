-- The Dungeon Quests reader (lead section 303 item 7, data route A). Reads
-- Questie at runtime through the client (client.questieModule): its
-- dungeon list (ZoneDB:GetDungeons) and its quests (QuestieDB). No quest,
-- dungeon or loot table ships here, and nothing of DungeonJournal is used.
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
--   R.Loot(st, client, key, book) -> the Bosses tab's data (lead section
--     305): { title, why, bosses = { { name, kills, items = { { item,
--     times } } } }, unplaced }. book is this account's own seen loot,
--     account "learned.bossLoot" as UI/BossLoot.lua keeps it; a boss is in
--     the dungeon where Questie spawns one of its creatures. Most-seen
--     items first. No loot table: only what this account saw.
--
-- Client reads: questieModule, level, class, raceId, faction, questLog,
-- questDone. Only reads. Not tested in game: every Questie call here is
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
R.WHY_NO_LOOT = { "No boss loot seen here on this account yet.",
    "Kill a boss of this dungeon with loot recording on and its drops will appear here." }
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

-- Twin review 17:11: F5 (n: entries are placed by their key), F6 (loot
-- placed nowhere says so), F7 (one boss from its e: and n: entries, merged
-- by UI/BossLoot.lua B.Lookup, the boss panel's own reading). drops: the
-- character's learned.drops, or nil.
function R.Loot(st, client, key, book, drops)
    if type(st) ~= "table" or st.state == "noquestie" then return S.Pane({ available = false }) end
    if st.state == "failed" then return waiting(st.why or R.WHY_LIST) end
    if st.state ~= "ready" then return waiting(R.WHY_BUILDING) end
    local d = key ~= nil and st.byKey[key] or nil
    if not d then return S.Pane({ available = true }) end
    local db = questieModule(client, "QuestieDB")
    if not db then return S.Pane({ available = false }) end
    local B = ns.BossLoot
    local out = { title = d.name, bosses = {}, unplaced = 0 }
    book = type(book) == "table" and book or {}
    local here, seen, named = {}, false, false
    for k, entry in pairs(book) do
        if type(entry) == "table" then
            seen = true
            local creatures = creaturesOf(k, entry)
            if #creatures == 0 then out.unplaced = out.unplaced + 1 else named = true end
            for _, npc in ipairs(creatures) do
                if placeOf(st, db, "npc", npc) == d.key then here[npc] = true end
            end
        end
    end
    local npcs = {}
    for npc in pairs(here) do npcs[#npcs + 1] = npc end
    table.sort(npcs)
    local covered = {}
    for _, npc in ipairs(npcs) do
        if not covered[npc] and type(B) == "table" and type(B.Lookup) == "function" then
            covered[npc] = true
            -- The other creatures of the same encounters are this boss too.
            for k, entry in pairs(book) do
                if type(entry) == "table" and type(entry.npcs) == "table" and entry.npcs[npc] == true then
                    for _, other in ipairs(creaturesOf(k, entry)) do covered[other] = true end
                end
            end
            local ok, got = pcall(B.Lookup, book, drops, { npc = npc })
            if ok and type(got) == "table" then
                local items = {}
                for item, times in pairs(type(got.items) == "table" and got.items or {}) do
                    if type(times) == "number" and times > 0 then items[#items + 1] = { item = item, times = times } end
                end
                table.sort(items, function(a, b)
                    if a.times ~= b.times then return a.times > b.times end
                    return tostring(a.item) < tostring(b.item)
                end)
                -- Lead section 318: each item's name, quality and icon, as the
                -- client reads them; one not read yet says so.
                for _, it in ipairs(items) do
                    local info = ask(client, "itemInfo", it.item)
                    if type(info) == "table" then
                        if type(info.name) == "string" and info.name ~= "" then it.name = info.name end
                        if type(info.quality) == "number" then it.quality = info.quality end
                    end
                    it.name = it.name or R.ITEM_UNREAD
                    local icon = ask(client, "itemTexture", it.item)
                    if type(icon) == "string" or type(icon) == "number" then it.icon = icon end
                end
                out.bosses[#out.bosses + 1] = { name = got.name, kills = tonumber(got.kills) or 0, items = items }
            end
        end
    end
    table.sort(out.bosses, function(a, b) return tostring(a.name) < tostring(b.name) end)
    if #out.bosses == 0 then
        -- Loot seen, none of it tied to any creature: that, not "no loot".
        out.why = (seen and not named) and R.WHY_LOOT_UNPLACED or R.WHY_NO_LOOT
    end
    return out
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
