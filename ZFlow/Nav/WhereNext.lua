local _, ns = ...
-- Where to quest next (Flow-parity row A2-14): the zones on the player's
-- continent that have quests the player can take at their level, with a
-- count for each. Data only: no window, no word, no arrow; nothing acts.
-- The surface is another module's, built on ns.use("whereNext").Zones().
--
-- Every quest fact is read from the player's own Questie at run time
-- (client.questieModule): no zone, level or quest table ships here. What is
-- not known stays not known: no answer is a nil and a reason, never a
-- guess and never a zero.
--
-- The rule is legacy Flow's (Modules/Nav/WhereNext.lua, W.Scan and
-- W.InWindow; no data of it). A quest counts when:
--   * its level is a number above 0, from X.BELOW under the player's level
--     to X.ABOVE over it, and the level it is given from is no more than
--     X.AHEAD over the player's;
--   * it is not in the player's log, and the client does not say it was
--     handed in (not known whether: it counts, and info.doneKnown is false);
--   * its races and classes masks, when it has them, hold the player's race
--     and class (a race or class the client does not say rules nothing
--     out; info.raceKnown, info.classKnown);
--   * it is not a quest of an event Questie says is off (QuestieEvent:
--     eventQuests, activeQuests).
-- As in Flow the quests that must come first are not looked at here.
-- Its zone is its own area (zoneOrSort above 0), else the lowest area its
-- first giver stands in; the area's map is ZoneDB's. A quest whose area has
-- no map is counted in info.noZone and in no zone.
--
-- Pure:
--   X.InWindow(questLevel, minLevel, myLevel) -> bool
--   X.ForMe(q, me) -> bool      q = { requiredRaces, requiredClasses },
--                               me = { raceId, classId }
--   X.Events(mod) -> { set, active } or nil; X.Offered(id, events) -> bool
--   X.Takes(q, ctx) -> true | false, why
--     q = { id, level, minLevel, requiredRaces, requiredClasses };
--     ctx = { level, me, log = { [id] = true }, done(id) -> true | false |
--     nil, events }. With true, why is X.DONE_UNKNOWN when done(id) gave
--     neither true nor false.
--   X.AreaOf(zoneOrSort, spawns) -> area or nil
--   X.Rank(counts, least) -> { { map, count } }, most quests first, then
--     the lower map; counts = { [map] = n }.
--   X.OnCont(list, cont, contOf) -> the entries (copies) whose map
--     contOf(map) says is on cont.
--   X.ScanStart(db, ctx) -> pass or nil; X.ScanStep(pass, zones, count) ->
--     done: the pass a part at a time, count quests a call. pass.counts,
--     pass.seen, pass.noZone and pass.doneKnown are the answer once done.
--   X.Reader() -> reader: the cost control, one for the session.
--     reader.zones(client) -> list, nil, info | nil, reason. It reads
--       nothing of Questie's quests itself: it gives the kept answer, or
--       says the answer is wanted.
--     reader.work(client) -> is there more to do? The first call of a pass
--       lists the quests, each later one goes through X.STEP of them.
--       Nothing is done before zones() was asked, and nothing in combat.
--       One pass a level, and its answer is kept for the session. A pass
--       in which Questie gave no quest level at all (Questie still
--       loading) is done again no sooner than X.RETRY seconds later and
--       X.TRIES times in all, then kept as "no quest data".
--
-- Module "whereNext": provides Zones() -> list, nil, info | nil, reason
--   list = { { map, name, count } }, most quests first, then the lower
--     map: the zones on the continent of the map the player is on with at
--     least one quest to take. name is client.mapName(map), absent when
--     the client does not say. The list is the kept one: do not change it.
--   info = { level, doneKnown, logKnown, raceKnown, classKnown, noZone }
--   reason: one of the X.WHY_ texts.
-- Not tested in game: Questie's names (QuestPointers, QueryQuestSingle with
-- "questLevel", "requiredLevel", "requiredRaces", "requiredClasses",
-- "zoneOrSort", "startedBy"; QueryNPCSingle with "spawns";
-- ZoneDB.GetUiMapIdByAreaId; QuestieEvent.eventQuests, activeQuests) are the
-- ones Spells/ClassQuestList.lua and legacy Flow read.
ns.Nav = ns.Nav or {}
local N = ns.Nav
local X = {}
N.WhereNext = X

X.NAME = "whereNext"
X.BELOW, X.ABOVE = 4, 3   -- quest levels this far under and over yours count
X.AHEAD = 1               -- a quest given from one level over yours counts
X.LEAST = 1               -- quests a zone needs to be listed
X.STEP = 200              -- quests gone through a frame
X.EVERY = 0.01            -- seconds between parts: every frame
X.TRIES, X.RETRY = 6, 10  -- passes while Questie gives nothing; seconds between
X.READS = 7               -- Questie reads one quest costs at most
X.DONE_UNKNOWN = "doneUnknown"

X.WHY_NO_QUESTIE = "Questie is not loaded."
X.WHY_NO_LEVEL = "your level is not known yet."
X.WHY_READING = "still reading Questie's quests."
X.WHY_NO_DATA = "Questie gave no quest data."
X.WHY_NO_CONT = "the continent you are on is not known."
X.WHY_OFF = "not started."

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok then return nil end
    return v
end

local function ask(client, name, ...)
    if type(client) ~= "table" then return nil end
    return call(client[name], ...)
end

-- Whether bit n (1-based) is set in mask, by arithmetic: no bit library.
local function hasBit(mask, n)
    return math.floor(mask / 2 ^ (n - 1)) % 2 == 1
end

-- ------------------------------------------------------------------ pure

function X.InWindow(questLevel, minLevel, myLevel)
    if not finite(questLevel) or not finite(myLevel) or questLevel <= 0 then return false end
    if questLevel < myLevel - X.BELOW or questLevel > myLevel + X.ABOVE then return false end
    return (tonumber(minLevel) or 0) <= myLevel + X.AHEAD
end

function X.ForMe(q, me)
    if type(q) ~= "table" then return true end
    if type(me) ~= "table" then me = {} end
    local races, classes = tonumber(q.requiredRaces), tonumber(q.requiredClasses)
    if races and races > 0 and type(me.raceId) == "number" and not hasBit(races, me.raceId) then return false end
    if classes and classes > 0 and type(me.classId) == "number" and not hasBit(classes, me.classId) then
        return false
    end
    return true
end

-- Questie's event module as { set = { [quest] = true }, active = its own
-- table of the quests on now }, or nil with no module.
function X.Events(mod)
    if type(mod) ~= "table" then return nil end
    local set, active = {}, {}
    if type(mod.eventQuests) == "table" then
        for _, e in ipairs(mod.eventQuests) do
            local id
            if type(e) == "table" then id = e[2] or e.questId end
            if id ~= nil then set[id] = true end
        end
    end
    if type(mod.activeQuests) == "table" then active = mod.activeQuests end
    return { set = set, active = active }
end

function X.Offered(id, events)
    if id == nil or type(events) ~= "table" or type(events.set) ~= "table" then return true end
    if not events.set[id] then return true end
    return type(events.active) == "table" and events.active[id] ~= nil and events.active[id] ~= false
end

function X.Takes(q, ctx)
    if type(q) ~= "table" or type(ctx) ~= "table" then return false, "notKnown" end
    if type(ctx.log) == "table" and ctx.log[q.id] then return false, "log" end
    if not X.InWindow(q.level, q.minLevel, ctx.level) then return false, "level" end
    if not X.ForMe(q, ctx.me) then return false, "notForYou" end
    if not X.Offered(q.id, ctx.events) then return false, "event" end
    local done = call(ctx.done, q.id)
    if done == true then return false, "done" end
    if done ~= false then return true, X.DONE_UNKNOWN end
    return true
end

function X.AreaOf(zoneOrSort, spawns)
    local own = tonumber(zoneOrSort)
    if own and own > 0 then return own end
    if type(spawns) ~= "table" then return nil end
    local best
    for area in pairs(spawns) do
        if type(area) == "number" and (best == nil or area < best) then best = area end
    end
    return best
end

function X.Rank(counts, least)
    local out = {}
    if type(counts) ~= "table" then return out end
    least = tonumber(least) or X.LEAST
    for map, n in pairs(counts) do
        if type(map) == "number" and finite(n) and n >= least then out[#out + 1] = { map = map, count = n } end
    end
    table.sort(out, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.map < b.map
    end)
    return out
end

function X.OnCont(list, cont, contOf)
    local out = {}
    if cont == nil or type(list) ~= "table" or type(contOf) ~= "function" then return out end
    for _, z in ipairs(list) do
        if type(z) == "table" and contOf(z.map) == cont then out[#out + 1] = { map = z.map, count = z.count } end
    end
    return out
end

-- ------------------------------------------------------------------ scan

local function mapOf(zones, area)
    if type(zones) ~= "table" or type(zones.GetUiMapIdByAreaId) ~= "function" then return nil end
    local m = call(zones.GetUiMapIdByAreaId, area)
    if type(m) == "number" then return m end
    m = call(zones.GetUiMapIdByAreaId, zones, area)
    if type(m) == "number" then return m end
    return nil
end

-- startedBy is { { npc ids }, { object ids }, { item ids } }.
local function giverOf(db, id)
    local by = call(db.QueryQuestSingle, id, "startedBy")
    local npcs, npc
    if type(by) == "table" then npcs = by[1] end
    if type(npcs) == "table" then npc = npcs[1] end
    if type(npc) ~= "number" then return nil end
    return npc
end

-- The map of a quest's zone, or nil. Areas and givers are asked once a pass.
local function mapFor(pass, zones, id)
    local db = pass.db
    local area = X.AreaOf(call(db.QueryQuestSingle, id, "zoneOrSort"), nil)
    if area == nil then
        local npc = giverOf(db, id)
        if npc then
            local kept = pass.npcArea[npc]
            if kept == nil then
                kept = X.AreaOf(nil, call(db.QueryNPCSingle, npc, "spawns")) or false
                pass.npcArea[npc] = kept
            end
            if kept then area = kept end
        end
    end
    if area == nil then return nil end
    local map = pass.areaMap[area]
    if map == nil then
        map = mapOf(zones, area) or false
        pass.areaMap[area] = map
    end
    if not map then return nil end
    return map
end

local function look(pass, zones, id)
    local db, ctx = pass.db, pass.ctx
    local level = call(db.QueryQuestSingle, id, "questLevel")
    if not finite(level) then return end
    pass.seen = pass.seen + 1
    -- Most quests end here, on one read.
    if not X.InWindow(level, nil, ctx.level) then return end
    if type(ctx.log) == "table" and ctx.log[id] then return end
    local q = { id = id, level = level,
        minLevel = call(db.QueryQuestSingle, id, "requiredLevel"),
        requiredRaces = call(db.QueryQuestSingle, id, "requiredRaces"),
        requiredClasses = call(db.QueryQuestSingle, id, "requiredClasses") }
    local ok, why = X.Takes(q, ctx)
    if not ok then return end
    if why == X.DONE_UNKNOWN then pass.doneKnown = false end
    local map = mapFor(pass, zones, id)
    if map == nil then
        pass.noZone = pass.noZone + 1
        return
    end
    pass.counts[map] = (pass.counts[map] or 0) + 1
end

function X.ScanStart(db, ctx)
    if type(db) ~= "table" or type(db.QuestPointers) ~= "table" or type(db.QueryQuestSingle) ~= "function" then
        return nil
    end
    if type(ctx) ~= "table" or not finite(ctx.level) then return nil end
    local ids = {}
    for id in pairs(db.QuestPointers) do
        if type(id) == "number" then ids[#ids + 1] = id end
    end
    table.sort(ids)
    return { db = db, ctx = ctx, ids = ids, at = 0, level = ctx.level, counts = {}, seen = 0, noZone = 0,
             doneKnown = true, areaMap = {}, npcArea = {} }
end

function X.ScanStep(pass, zones, count)
    if type(pass) ~= "table" or type(pass.ids) ~= "table" then return true end
    local ids = pass.ids
    local last = #ids
    if finite(count) and count >= 1 and pass.at + count < last then last = pass.at + math.floor(count) end
    for at = pass.at + 1, last do
        look(pass, zones, ids[at])
    end
    pass.at = last
    return last >= #ids
end

-- ---------------------------------------------------------------- reader

-- The client's time, or nil when it has none (now() answers 0).
local function nowOf(client)
    local now = ask(client, "now")
    if finite(now) and now > 0 then return now end
    return nil
end

local function levelOf(client)
    local level = ask(client, "level")
    if finite(level) and level >= 1 then return level end
    return nil
end

-- What a pass is told about the player, read once at its start.
local function contextOf(client, level)
    local log, logKnown = {}, false
    local rows = call(N.QuestLogRows, client)
    if type(rows) == "table" then
        logKnown = true
        for _, r in ipairs(rows) do
            if type(r) == "table" and r.id ~= nil then log[r.id] = true end
        end
    end
    local raceId, classId = ask(client, "raceId"), nil
    if type(raceId) ~= "number" then raceId = nil end
    local token = ask(client, "class")
    local ids = ns.DungeonStates and ns.DungeonStates.CLASS_ID
    if type(token) == "string" and type(ids) == "table" and type(ids[token]) == "number" then classId = ids[token] end
    return { level = level, log = log, logKnown = logKnown,
        me = { raceId = raceId, classId = classId },
        done = function(id) return ask(client, "questDone", id) end,
        events = X.Events(ask(client, "questieModule", "QuestieEvent")) }
end

function X.Reader()
    local reader = {}
    local kept, pass, wanted
    local state = { tries = 0 }
    local conts = {}

    local function contOf(client, map)
        if type(map) ~= "number" then return nil end
        local c = conts[map]
        if c ~= nil then return c end
        c = ask(client, "mapCont", map)
        if c == nil then
            local corners = ask(client, "mapCorners", map)
            if type(corners) == "table" then c = corners.cont end
        end
        if c ~= nil then conts[map] = c end
        return c
    end

    local function named(client, list)
        for _, z in ipairs(list) do
            if z.name == nil then
                local name = ask(client, "mapName", z.map)
                if type(name) == "string" and name ~= "" then z.name = name end
            end
        end
        return list
    end

    function reader.zones(client)
        if type(ask(client, "questieModule", "QuestieDB")) ~= "table" then return nil, X.WHY_NO_QUESTIE end
        local level = levelOf(client)
        if not level then return nil, X.WHY_NO_LEVEL end
        if not kept or kept.level ~= level then
            if wanted ~= level then
                wanted = level
                state = { tries = 0 }
            end
            return nil, X.WHY_READING
        end
        if kept.seen == 0 then return nil, X.WHY_NO_DATA end
        local here = ask(client, "position")
        local cont
        if type(here) == "table" then cont = contOf(client, here.map) end
        if cont == nil then return nil, X.WHY_NO_CONT end
        local list = kept.lists[cont]
        if list then return named(client, list), nil, kept.info end
        list = X.OnCont(kept.ranked, cont, function(map) return contOf(client, map) end)
        -- Kept only once every zone's continent is known, so a zone the
        -- client could not place yet is asked about again.
        local whole = true
        for _, z in ipairs(kept.ranked) do
            if conts[z.map] == nil then whole = false end
        end
        if whole then kept.lists[cont] = list end
        return named(client, list), nil, kept.info
    end

    local function due(now)
        if state.tries >= X.TRIES then return false end
        if now and state.last and now >= state.last and now - state.last < X.RETRY then return false end
        return true
    end

    function reader.work(client)
        if wanted == nil or (kept and kept.level == wanted) then return false end
        if ask(client, "inCombat") == true then return false end
        if not pass then
            if not due(nowOf(client)) then return false end
            local level = levelOf(client)
            if not level then return false end
            wanted = level
            -- Questie not there, or its quest list not built yet: nothing
            -- to go through, and no try is used up.
            pass = X.ScanStart(ask(client, "questieModule", "QuestieDB"), contextOf(client, level))
            return pass ~= nil
        end
        if not X.ScanStep(pass, ask(client, "questieModule", "ZoneDB"), X.STEP) then return true end
        state.tries = state.tries + 1
        state.last = nowOf(client)
        if pass.seen > 0 or state.tries >= X.TRIES then
            local me = pass.ctx.me
            kept = { level = pass.level, seen = pass.seen, ranked = X.Rank(pass.counts, X.LEAST), lists = {},
                info = { level = pass.level, doneKnown = pass.doneKnown, logKnown = pass.ctx.logKnown,
                         raceKnown = me.raceId ~= nil, classKnown = me.classId ~= nil, noZone = pass.noZone } }
        end
        pass = nil
        return false
    end

    return reader
end

-- ---------------------------------------------------------------- module

function X.Declare(k)
    local api = {}
    local ctx
    local reader = X.Reader()

    function api.zones()
        if not ctx then return nil, X.WHY_OFF end
        return reader.zones(ctx.client)
    end

    k:Module({
        name = X.NAME,
        needs = { "client" },
        provides = { Zones = api.zones },
        ticks = {
            -- The cost rule: the pass over Questie's quests is spread over
            -- frames and waits for combat to end. With nothing wanted it
            -- does nothing.
            { every = X.EVERY, when = "outOfCombat", run = function()
                if ctx then reader.work(ctx.client) end
            end },
        },
        start = function(c) ctx = c end,
        stop = function() ctx = nil end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.whereNext = X.Declare(ns)
