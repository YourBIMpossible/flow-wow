-- The Dungeon Quests reader (lead section 303 item 7, data route A). Reads
-- Questie at runtime through the client (client.questieModule): its
-- dungeon list (ZoneDB:GetDungeons) and its quests (QuestieDB). No quest,
-- dungeon or loot table ships here, and nothing of DungeonJournal is used.
-- A port of the index of legacy Flow's Modules/Nav/Dungeons.lua
-- (buildDungeons, buildIndex): a quest belongs to the dungeon its zone is
-- in. Not yet ported: legacy's placing of a quest by where its objectives
-- are, and the giver-at-the-entrance check (so a follow-up whose giver is
-- at the door reads as the next run).
--
--   R.Available(client) -> bool        Questie's two modules are there
--   R.Start(client) -> st              st.state: "noquestie" | "failed" |
--                                      "building" | "ready"
--   R.Step(st, client, n)              files the next n quests; "ready"
--                                      once all are filed
--   R.List(st) -> { { key, name, minQ, maxQ, ids } }   in level order
--   R.Pane(st, client, key) -> the pane (Nav/DungeonStates.lua S.Pane),
--                              or one saying why there is none yet
--
-- Client reads: questieModule, level, class, raceId, faction, questLog,
-- questDone. Only reads. Not tested in game: every Questie call here is
-- the one legacy Flow made, not seen through this add-on on 16001.
local _, ns = ...

local R = {}
ns.DungeonRead = R

local S = ns.DungeonStates

R.SLICE = 300   -- quests filed per step

-- Dire Maul's wings and Stratholme's Gauntlet are listed by Questie as
-- dungeons of their own: one dungeon here (legacy ALIAS). Battlegrounds
-- Questie lists with the dungeons are left out (legacy SKIP).
R.ALIAS = { [10022] = 2557, [10023] = 2557, [10024] = 2557, [10025] = 2557, [10026] = 2557, [10027] = 2557,
            [10001] = 2017 }
R.SKIP = { [2597] = true, [3277] = true, [3358] = true }

R.WHY_BUILDING = { "Reading Questie's dungeon quests.",
    "This takes a moment the first time; the list fills in by itself." }
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
            d = { key = key, name = name or ("Dungeon " .. tostring(key)), ids = {} }
            byKey[key] = d
            areaTop[key] = key
        end
        return d
    end
    for area, entry in pairs(list) do
        if type(area) == "number" and not R.SKIP[area] and type(entry) == "table" then
            local d = top(area)
            areaTop[area] = d.key
            for _, alt in ipairs(type(entry[2]) == "table" and entry[2] or {}) do areaTop[alt] = d.key end
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
    return { state = "building", byKey = byKey, areaTop = areaTop, ids = ids, at = 0, dungeonOf = {}, quests = {} }
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
        if ok and type(npc) == "table" and type(npc.friendlyToFaction) == "string" then
            out.giverFaction = npc.friendlyToFaction
        end
    end
    st.quests[id] = out
    return out
end

local function waiting(why, title)
    return { title = title, why = why, groups = {}, count = 0, unplaced = 0 }
end

function R.Pane(st, client, key)
    if type(st) ~= "table" or st.state == "noquestie" then return S.Pane({ available = false }) end
    if st.state == "failed" then return waiting(R.WHY_LIST) end
    if st.state ~= "ready" then return waiting(R.WHY_BUILDING) end
    local d = key ~= nil and st.byKey[key] or nil
    if not d then return S.Pane({ available = true }) end
    local db = questieModule(client, "QuestieDB")
    if not db then return S.Pane({ available = false }) end
    local log, rows = {}, ask(client, "questLog")
    for _, row in ipairs(type(rows) == "table" and rows or {}) do
        if type(row) == "table" and type(row.id) == "number" then log[row.id] = true end
    end
    local done = setmetatable({}, { __index = function(_, id) return ask(client, "questDone", id) == true end })
    local class = ask(client, "class")
    local me = { raceId = ask(client, "raceId"), classId = class and S.CLASS_ID[class] or nil,
        faction = ask(client, "faction") }
    local ctx = {
        level = tonumber(ask(client, "level")) or 0,
        log = log, done = done,
        get = function(id) return quest(st, db, id) end,
        eligible = function(q) return S.Eligible(q, me) end,
        dungeonOf = function(id) return st.dungeonOf[id] end,
        inside = function(q) return q.startsByItem == true end,
    }
    local quests = {}
    for _, id in ipairs(d.ids) do
        local q = quest(st, db, id)
        if q then quests[#quests + 1] = q end
    end
    return S.Pane({ available = true, dungeon = d, quests = quests, ctx = ctx })
end
