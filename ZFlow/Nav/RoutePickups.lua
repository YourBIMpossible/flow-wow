local _, ns = ...
-- The quest route's pick-ups (lead section 375 item 7, TN-1; the rule of
-- legacy Flow's Goals.lua newQuests, no data of it): quests the player can
-- take now whose giver Questie places on the player's map. Read from
-- Questie at runtime (client.questieModule); nothing copied, nothing
-- accepted. Nav/TripRoute.lua adds them as optional stops (TN-2): kept
-- only when on the way.
--
-- How they are found: once per plan (never per tick), Questie's quest list
-- (QuestieDB.QuestPointers) is walked; a quest whose required level or
-- quest level is out of reach is passed over on the quick query
-- (QueryQuestSingle) before its quest table is read. The rest are read as
-- Nav/DungeonRead.lua reads them, their first giver's spawns placed by
-- ZoneDB. Of the candidates on this map the P.MAX nearest are kept.
--
-- Pure:
--   P.Candidate(q, ctx) -> true | false, why
--     q in the shape S.State takes; ctx = { level, log = { [id] = true },
--     done(id) -> true | false | nil (not known), me (S.Eligible) }
--   P.Nearest(list, here, max) -> the max nearest of list on here.map
-- Client reads: P.Read(client, here, log) -> list or nil, why. A quest
-- whose giver was seen not to offer it (Nav/QuestOffers.lua) is left out:
--   P.Keep(item, skip) -> bool
-- Not tested in game.
ns.Nav = ns.Nav or {}
local N = ns.Nav
local S = ns.DungeonStates
local P = {}
N.RoutePickups = P

P.MAX = 8        -- pick-ups offered at most
P.BELOW = 5      -- quests up to 5 levels below the player count
P.LABEL = "Pick up: %s (%s)"
P.GIVER = "quest giver"
P.SKIPPED = "skipped: more than " .. N.DETOUR .. " yd off the way"
P.WHY_NO_QUESTIE = "No quests to pick up added: Questie is not loaded."
P.WHY_NO_LIST = "No quests to pick up added: Questie gave no quest list."
P.WHY_NO_LEVEL = "No quests to pick up added: your level is not known yet."

local function list(v) return type(v) == "table" and v or {} end

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function inReach(level, reqLevel, qLevel)
    if tonumber(reqLevel) and tonumber(reqLevel) > level then return false, "from level " .. reqLevel end
    local l = tonumber(qLevel)
    if l and l > level + S.LEVEL_ABOVE then return false, "above you" end
    if l and l > 0 and l < level - P.BELOW then return false, "far below you" end
    return true
end

function P.Candidate(q, ctx)
    if type(q) ~= "table" or type(ctx) ~= "table" then return false, "not known" end
    local log = list(ctx.log)
    local done = type(ctx.done) == "function" and ctx.done or function() return nil end
    if log[q.Id] then return false, "in your log" end
    if done(q.Id) == true then return false, "done" end
    if S.Eligible(q, ctx.me) == false then return false, "not for you" end
    for _, ex in ipairs(list(q.exclusiveTo)) do
        if log[ex] or done(ex) == true then return false, "ruled out by a quest you did" end
    end
    local ok, why = inReach(tonumber(ctx.level) or 0, q.requiredLevel, q.level)
    if not ok then return false, why end
    for _, id in ipairs(list(q.preQuestGroup)) do
        if done(id) == false then return false, "an earlier quest first" end
    end
    local single = list(q.preQuestSingle)
    if #single > 0 then
        local any = false
        for _, id in ipairs(single) do
            if done(id) ~= false then any = true end
        end
        if not any then return false, "an earlier quest first" end
    end
    return true
end

function P.Nearest(items, here, max)
    here = type(here) == "table" and here or {}
    local w, h = 1, 1
    if type(here.size) == "table" and finite(here.size.w) and finite(here.size.h) then
        w, h = here.size.w, here.size.h
    end
    local canMeasure = finite(here.x) and finite(here.y)
    local out = {}
    for _, it in ipairs(list(items)) do
        local p = type(it) == "table" and it.place
        if type(p) == "table" and p.map == here.map and finite(p.x) and finite(p.y) then
            local dx = canMeasure and (p.x - here.x) * w or 0
            local dy = canMeasure and (p.y - here.y) * h or 0
            out[#out + 1] = { item = it, d = dx * dx + dy * dy }
        end
    end
    table.sort(out, function(a, b)
        if a.d ~= b.d then return a.d < b.d end
        return (tonumber(a.item.quest) or 0) < (tonumber(b.item.quest) or 0)
    end)
    local kept = {}
    for i = 1, math.min(#out, tonumber(max) or P.MAX) do kept[i] = out[i].item end
    return kept
end

-- A pick-up stays unless the quest's giver was seen not to offer it
-- (Nav/QuestOffers.lua). skip(id) -> true drops it; no skip keeps all.
function P.Keep(item, skip)
    if type(skip) ~= "function" or type(item) ~= "table" then return true end
    return skip(item.quest) ~= true
end

local function dropped(id)
    local off = ns.questOffers
    if type(off) ~= "table" or type(off.dropped) ~= "function" then return false end
    local ok, v = pcall(off.dropped, id)
    return ok and v == true
end

-- --------------------------------------------------------------- reads

local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if not ok then return nil end
    return v
end

local function questie(client, name)
    local m = ask(client, "questieModule", name)
    return type(m) == "table" and m or nil
end

local function quick(db, id, name)
    if type(db.QueryQuestSingle) ~= "function" then return nil end
    local ok, v = pcall(db.QueryQuestSingle, id, name)
    if ok then return v end
    return nil
end

local function mapOf(zones, area)
    if type(zones.GetUiMapIdByAreaId) ~= "function" then return nil end
    local ok, m = pcall(zones.GetUiMapIdByAreaId, area)
    if ok and type(m) == "number" then return m end
    ok, m = pcall(zones.GetUiMapIdByAreaId, zones, area)
    if ok and type(m) == "number" then return m end
    return nil
end

-- The giver's point on map, nearest the player (the first when the player's
-- place is not known), in shares 0..1; or nil.
local function giverPoint(zones, spawns, here, areaMap)
    local best, bestD
    for area, pts in pairs(list(spawns)) do
        local m = areaMap[area]
        if m == nil then
            m = mapOf(zones, area) or false
            areaMap[area] = m
        end
        if m == here.map then
            for _, pt in ipairs(list(pts)) do
                if type(pt) == "table" and finite(pt[1]) and finite(pt[2])
                    and pt[1] >= 0 and pt[1] <= 100 and pt[2] >= 0 and pt[2] <= 100 then
                    local x, y = pt[1] / 100, pt[2] / 100
                    local d = (finite(here.x) and finite(here.y)) and ((x - here.x) ^ 2 + (y - here.y) ^ 2) or 0
                    if best == nil or d < bestD then best, bestD = { map = m, x = x, y = y }, d end
                end
            end
        end
    end
    return best
end

-- log: { [id] = true } of the quests in the player's log.
function P.Read(client, here, log)
    local db, zones = questie(client, "QuestieDB"), questie(client, "ZoneDB")
    if not db or not zones or type(db.GetQuest) ~= "function" then return nil, P.WHY_NO_QUESTIE end
    if type(db.QuestPointers) ~= "table" then return nil, P.WHY_NO_LIST end
    local level = tonumber(ask(client, "level"))
    if not level then return nil, P.WHY_NO_LEVEL end
    local class = ask(client, "class")
    local ctx = {
        level = level, log = type(log) == "table" and log or {},
        me = { raceId = ask(client, "raceId"), classId = class and S.CLASS_ID[class] or nil,
               faction = ask(client, "faction") },
        done = function(id) return ask(client, "questDone", id) end,
    }
    local found, areaMap, npcs = {}, {}, {}
    for id in pairs(db.QuestPointers) do
        if type(id) == "number" and not ctx.log[id]
            and inReach(level, quick(db, id, "requiredLevel"), quick(db, id, "questLevel")) then
            local ok, qt = pcall(db.GetQuest, id)
            local starts = ok and type(qt) == "table" and type(qt.Starts) == "table" and qt.Starts or nil
            local giver = starts and type(starts.NPC) == "table" and starts.NPC[1] or nil
            if giver and type(db.GetNPC) == "function" then
                local npc = npcs[giver]
                if npc == nil then
                    local okN, v = pcall(db.GetNPC, giver)
                    npc = okN and type(v) == "table" and v or false
                    npcs[giver] = npc
                end
                local place = npc and giverPoint(zones, npc.spawns, here, areaMap)
                if place then
                    local q = { Id = id, name = qt.name, level = qt.level, requiredLevel = qt.requiredLevel,
                        preQuestSingle = qt.preQuestSingle, preQuestGroup = qt.preQuestGroup,
                        exclusiveTo = qt.exclusiveTo, requiredRaces = qt.requiredRaces,
                        requiredClasses = qt.requiredClasses, requiredMinRep = qt.requiredMinRep,
                        requiredMaxRep = qt.requiredMaxRep, requiredSkill = qt.requiredSkill,
                        requiredSpell = qt.requiredSpell,
                        giverFaction = type(npc.friendlyToFaction) == "string" and npc.friendlyToFaction or nil }
                    if type(qt.name) == "string" and P.Candidate(q, ctx) and P.Keep({ quest = id }, dropped) then
                        local who = type(npc.name) == "string" and npc.name ~= "" and npc.name or P.GIVER
                        found[#found + 1] = { kind = "pickup", quest = id, label = P.LABEL:format(qt.name, who),
                                              place = place }
                    end
                end
            end
        end
    end
    return P.Nearest(found, here, P.MAX)
end
