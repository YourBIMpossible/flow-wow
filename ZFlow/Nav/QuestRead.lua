local _, ns = ...
-- Z-Flow quest reads (S43): the player's own quest log through the client,
-- and where its objectives and turn-ins are, asked of the installed Questie
-- at runtime through its public modules. Read-only and look-only: nothing
-- here accepts, hands in or abandons a quest, and nothing of Questie's is
-- set, changed or kept in this addon's files or saved data. A missing
-- Questie, or any error from it, is "not known", never a guess.
--
-- The client reads these lean on (CLIENT NEED; absent reads are "not known"):
--   client.questLog() -> { { id, title, complete, failed,
--                            objectives = { { text, done } } } } or nil
--   client.questieModule(name) -> Questie's module of that name, or nil
--
-- N.QuestLogRows(client) -> rows or nil
--   The log as Q.Pick takes it: rows without an id or a title are left out;
--   nil when the client has no such read, or the read fails.
--
-- N.QuestiePlaces(client, rows, map) -> places or nil
--   places as Q.Pick takes them, with the points on map only. nil when
--   Questie is not there or not ready. A quest Questie fails on has no
--   entry. Objective i of the log is taken to be Questie's ObjectiveData[i].
--
-- N.QuestWatch(client) -> { step = fn, refresh = fn }
--   step(): the quest step for where the player is now (Q.Pick), or nil.
--   The log and the places are read again only after refresh(), when the
--   player's map changes, and now and then while Questie is not ready.
ns.Nav = ns.Nav or {}
local N = ns.Nav

-- No more points than this are kept for one objective or turn-in.
N.QUEST_POINTS_MAX = 200
-- No more creatures or objects than this are looked up for one of them.
N.QUEST_SOURCES_MAX = 20
-- While Questie is not ready, it is asked again after this many steps.
N.QUEST_RETRY_STEPS = 20

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if not ok then return nil end
    return v
end

function N.QuestLogRows(client)
    local log = ask(client, "questLog")
    if type(log) ~= "table" then return nil end
    local rows = {}
    for _, r in ipairs(log) do
        if type(r) == "table" and r.id ~= nil and type(r.title) == "string" and r.title ~= "" then
            local row = { id = r.id, title = r.title, complete = r.complete == true, failed = r.failed == true,
                          objectives = {} }
            if type(r.objectives) == "table" then
                for i, o in ipairs(r.objectives) do
                    local text = type(o) == "table" and type(o.text) == "string" and o.text ~= "" and o.text or nil
                    row.objectives[i] = { text = text, done = type(o) == "table" and o.done == true }
                end
            end
            rows[#rows + 1] = row
        end
    end
    return rows
end

-- A function of a Questie module, called both ways it is written in
-- Questie: db.Fn(id), then db:Fn(id). An error is no answer.
local function call(mod, name, id)
    if type(mod) ~= "table" or type(mod[name]) ~= "function" then return nil end
    local ok, v = pcall(mod[name], id)
    if ok and v ~= nil then return v end
    ok, v = pcall(mod[name], mod, id)
    if ok then return v end
    return nil
end

-- Adds the points of a spawn table ({ [areaId] = { { x, y }, ... } }, x and
-- y 0..100) to a spot: those on map are kept, others only noted.
local function addSpawns(spot, spawns, zones, map, areaMap)
    if type(spawns) ~= "table" then return end
    for area, list in pairs(spawns) do
        if type(list) == "table" then
            local m = areaMap[area]
            if m == nil then
                m = call(zones, "GetUiMapIdByAreaId", area) or false
                areaMap[area] = m
            end
            for _, pt in ipairs(list) do
                if m and type(pt) == "table" and finite(pt[1]) and finite(pt[2])
                    and pt[1] >= 0 and pt[1] <= 100 and pt[2] >= 0 and pt[2] <= 100 then
                    if m == map then
                        if #spot.points < N.QUEST_POINTS_MAX then
                            spot.points[#spot.points + 1] = { map = m, x = pt[1] / 100, y = pt[2] / 100 }
                        end
                    else
                        spot.other = true
                    end
                end
            end
        end
    end
end

local function addFrom(spot, db, fn, ids, zones, map, areaMap)
    if type(ids) == "number" then ids = { ids } end
    if type(ids) ~= "table" then return end
    for n, id in ipairs(ids) do
        if n > N.QUEST_SOURCES_MAX then break end
        local thing = call(db, fn, id)
        if type(thing) == "table" then
            addSpawns(spot, thing.spawns, zones, map, areaMap)
            if spot.name == nil and type(thing.name) == "string" and thing.name ~= "" then spot.name = thing.name end
        end
    end
end

local function closed(spot, keepName)
    local out = { points = spot.points, elsewhere = #spot.points == 0 and spot.other == true }
    if keepName then out.name = spot.name end
    return out
end

local function objectiveSpot(db, zones, o, map, areaMap)
    local spot = { points = {} }
    if type(o) ~= "table" then return closed(spot) end
    if o.Type == "monster" then
        addFrom(spot, db, "GetNPC", o.Id, zones, map, areaMap)
    elseif o.Type == "object" then
        addFrom(spot, db, "GetObject", o.Id, zones, map, areaMap)
    elseif o.Type == "item" then
        local item = call(db, "GetItem", o.Id)
        if type(item) == "table" then
            addFrom(spot, db, "GetNPC", item.npcDrops, zones, map, areaMap)
            addFrom(spot, db, "GetObject", item.objectDrops, zones, map, areaMap)
        end
    end
    -- A place the objective carries itself (an "event" objective does).
    addSpawns(spot, o.Coordinates, zones, map, areaMap)
    return closed(spot)
end

local function turnInSpot(db, zones, quest, map, areaMap)
    local spot = { points = {} }
    local f = quest.Finisher or quest.Finishes
    if type(f) == "table" then
        addFrom(spot, db, "GetNPC", f.NPC, zones, map, areaMap)
        addFrom(spot, db, "GetObject", f.GameObject, zones, map, areaMap)
        if f.Type == "monster" then addFrom(spot, db, "GetNPC", f.Id, zones, map, areaMap) end
        if f.Type == "object" then addFrom(spot, db, "GetObject", f.Id, zones, map, areaMap) end
        if spot.name == nil and type(f.Name) == "string" and f.Name ~= "" then spot.name = f.Name end
    end
    if type(quest.finishedBy) == "table" then
        addFrom(spot, db, "GetNPC", quest.finishedBy[1], zones, map, areaMap)
        addFrom(spot, db, "GetObject", quest.finishedBy[2], zones, map, areaMap)
    end
    return closed(spot, true)
end

function N.QuestiePlaces(client, rows, map)
    if type(rows) ~= "table" then return nil end
    local db = ask(client, "questieModule", "QuestieDB")
    -- Before Questie has loaded its data the module is there but empty.
    if type(db) ~= "table" or type(db.GetQuest) ~= "function" then return nil end
    local zones = ask(client, "questieModule", "ZoneDB")
    local places, areaMap = {}, {}
    for _, row in ipairs(rows) do
        local ok, entry = pcall(function()
            local quest = call(db, "GetQuest", row.id)
            if type(quest) ~= "table" then return nil end
            local e = { objectives = {} }
            if type(quest.ObjectiveData) == "table" then
                for i in ipairs(row.objectives or {}) do
                    if quest.ObjectiveData[i] ~= nil then
                        e.objectives[i] = objectiveSpot(db, zones, quest.ObjectiveData[i], map, areaMap)
                    end
                end
            end
            e.turnIn = turnInSpot(db, zones, quest, map, areaMap)
            return e
        end)
        if ok and entry then places[row.id] = entry end
    end
    return places
end

function N.QuestWatch(client)
    local Q = N.QuestSource
    local rows, places, map
    local stale, waited = true, 0

    local function refresh() stale = true end

    local function step()
        local at = ask(client, "position")
        local here = {}
        if type(at) == "table" then here.map, here.x, here.y = at.map, at.x, at.y end
        if here.map ~= map then stale = true end
        if places == nil then
            waited = waited + 1
            if waited >= N.QUEST_RETRY_STEPS then stale = true end
        end
        if stale then
            stale, waited, map = false, 0, here.map
            rows = N.QuestLogRows(client)
            places = rows and N.QuestiePlaces(client, rows, map) or nil
        end
        if rows == nil then return nil end
        local zone = ask(client, "zone")
        here.cont = type(zone) == "table" and zone.cont or nil
        if here.map ~= nil then
            local size = ask(client, "mapSize", here.map)
            if type(size) == "table" then here.size = { w = size.w, h = size.h } end
        end
        return Q.Pick(rows, places, here)
    end

    return { step = step, refresh = refresh }
end
