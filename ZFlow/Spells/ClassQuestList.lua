local _, ns = ...

-- Class quests not done, and class trainers, from the player's own Questie
-- (C-07, C-54). Questie is asked at runtime through client.questieModule:
-- no quest, NPC or place table ships here. Look-only: nothing is accepted,
-- handed in, trained or clicked.
--
--   the classquests word  lists the quests only your class can take that you
--                         have not handed in: level, who gives it and where.
--                         Done quests are counted, not listed. With no
--                         Questie, one line says what is missing.
--   the class trainer     ClassTrainerStep asks L.Trainers when the player
--                         has never opened a class trainer, so the route
--                         step has a place before the first visit.
--
-- Pure parts:
--   L.ClassId(token)                       Questie's class number, or nil
--   L.Quests(db, zones, classId, done, inLog)
--       -> { { id, name, level, minLevel, giver, place, state } }, lowest
--          minLevel first. state: "done" | "in log" | "not done" |
--          "not known" (the client does not say). place = { map, x, y }
--          (x, y shares) or nil.
--   L.Lines(rows, mapName)                 the word's lines (no title)
--   L.Trainers(db, zones, token, faction)  { [name] = { roles =
--       { classTrainer = true }, classes = { [token] = true }, map, x, y } }:
--       the shape ClassTrainerStep keeps for a trainer it has seen.
--
-- Questie calls, first guesses (the ones legacy Flow and Nav/DungeonRead.lua
-- make; not seen through this add-on on 16001): QuestieDB.QuestPointers,
-- QuestieDB.NPCPointers, QuestieDB.QueryQuestSingle(id, field) for
-- "requiredClasses", "name", "questLevel", "requiredLevel", "startedBy";
-- QuestieDB.QueryNPCSingle(id, field) for "name", "subName", "spawns",
-- "friendlyToFaction"; ZoneDB:GetUiMapIdByAreaId(area). A Questie class
-- trainer's subName is "<Class> Trainer" on an English client (a first
-- guess: other languages find none and the step keeps its words).

local L = {}
ns.ClassQuestList = L

L.WORD = "classquests"
L.HELP = "list the class quests you have not done, who gives them and where"
L.NO_QUESTIE = "the class quest list needs the Questie add-on; none is loaded."
L.NO_CLASS = "your class is not known yet; try again in a moment."
L.HEAD = "class quests for your class not done: %d (done: %d)"
L.NONE = "no class quest left for your class in Questie's data."
L.UNKNOWN_DONE = " (not known whether you handed it in)"

L.CLASS_ID = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5,
    SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11,
}
L.CLASS_WORD = {
    WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
    SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function hasBit(mask, n)
    return math.floor(mask / 2 ^ (n - 1)) % 2 == 1
end

function L.ClassId(token)
    if type(token) ~= "string" then return nil end
    return L.CLASS_ID[token]
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok then return nil end
    return v
end

local function mapOf(zones, area)
    if type(zones) ~= "table" or type(zones.GetUiMapIdByAreaId) ~= "function" then return nil end
    local m = call(zones.GetUiMapIdByAreaId, area)
    if type(m) == "number" then return m end
    m = call(zones.GetUiMapIdByAreaId, zones, area)
    if type(m) == "number" then return m end
    return nil
end

-- The first spawn of an NPC as { map, x, y } (shares), or nil.
local function placeOf(db, zones, npc)
    if type(npc) ~= "number" then return nil end
    local spawns = call(db.QueryNPCSingle, npc, "spawns")
    if type(spawns) ~= "table" then return nil end
    local areas = {}
    for area in pairs(spawns) do
        if type(area) == "number" then areas[#areas + 1] = area end
    end
    table.sort(areas)
    for _, area in ipairs(areas) do
        local pts = spawns[area]
        local p
        if type(pts) == "table" then p = pts[1] end
        local map = mapOf(zones, area)
        if map and type(p) == "table" and finite(p[1]) and finite(p[2]) then
            return { map = map, x = p[1] / 100, y = p[2] / 100 }
        end
    end
    return nil
end

local function ids(pointers)
    local out = {}
    if type(pointers) ~= "table" then return out end
    for id in pairs(pointers) do
        if type(id) == "number" then out[#out + 1] = id end
    end
    table.sort(out)
    return out
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

function L.Quests(db, zones, classId, done, inLog)
    local out = {}
    if type(db) ~= "table" or type(classId) ~= "number" then return out end
    for _, id in ipairs(ids(db.QuestPointers)) do
        local mask = tonumber(call(db.QueryQuestSingle, id, "requiredClasses"))
        if mask and mask > 0 and hasBit(mask, classId) then
            local row = { id = id }
            local name = call(db.QueryQuestSingle, id, "name")
            if type(name) == "string" then row.name = name else row.name = "Quest " .. id end
            local lv = call(db.QueryQuestSingle, id, "questLevel")
            if finite(lv) then row.level = lv end
            local min = call(db.QueryQuestSingle, id, "requiredLevel")
            if finite(min) then row.minLevel = min end
            local npc = giverOf(db, id)
            if npc then
                local who = call(db.QueryNPCSingle, npc, "name")
                if type(who) == "string" then row.giver = who end
                row.place = placeOf(db, zones, npc)
            end
            local d
            if type(done) == "function" then d = call(done, id) end
            if type(inLog) == "table" and inLog[id] then
                row.state = "in log"
            elseif d == true then
                row.state = "done"
            elseif d == false then
                row.state = "not done"
            else
                row.state = "not known"
            end
            out[#out + 1] = row
        end
    end
    table.sort(out, function(a, b)
        local la, lb = a.minLevel or a.level or 0, b.minLevel or b.level or 0
        if la ~= lb then return la < lb end
        return a.id < b.id
    end)
    return out
end

local function where(row, mapName)
    local p = row.place
    if type(p) ~= "table" then return "" end
    local zone
    if type(mapName) == "function" then zone = call(mapName, p.map) end
    if type(zone) ~= "string" then zone = "map " .. tostring(p.map) end
    return string.format(" in %s %.1f, %.1f", zone, p.x * 100, p.y * 100)
end

function L.Lines(rows, mapName)
    local open, doneN = {}, 0
    for _, r in ipairs(type(rows) == "table" and rows or {}) do
        if r.state == "done" then doneN = doneN + 1 else open[#open + 1] = r end
    end
    local out = { L.HEAD:format(#open, doneN) }
    if #open == 0 then
        out[#out + 1] = "  " .. L.NONE
        return out
    end
    for _, r in ipairs(open) do
        local lv = r.minLevel or r.level
        local lvText = ""
        if lv then lvText = " (level " .. lv .. ")" end
        local from = ""
        if r.giver then from = ", from " .. r.giver .. where(r, mapName) end
        local state = r.state
        if state == "not known" then state = "not done" .. L.UNKNOWN_DONE end
        out[#out + 1] = string.format("  [%d] %s%s%s: %s", r.id, r.name, lvText, from, state)
    end
    return out
end

function L.Trainers(db, zones, token, faction)
    local out = {}
    local word
    if type(token) == "string" then word = L.CLASS_WORD[token] end
    if type(db) ~= "table" or not word then return out end
    local want = word .. " Trainer"
    local side
    if faction == "Alliance" then side = "A" elseif faction == "Horde" then side = "H" end
    for _, id in ipairs(ids(db.NPCPointers)) do
        if call(db.QueryNPCSingle, id, "subName") == want then
            local friendly = call(db.QueryNPCSingle, id, "friendlyToFaction")
            local ok = true
            if side and type(friendly) == "string" and friendly ~= "" and not friendly:find(side, 1, true) then
                ok = false
            end
            local name = call(db.QueryNPCSingle, id, "name")
            local place
            if ok and type(name) == "string" then place = placeOf(db, zones, id) end
            if place and out[name] == nil then
                out[name] = { roles = { classTrainer = true }, classes = { [token] = true },
                              map = place.map, x = place.x, y = place.y }
            end
        end
    end
    return out
end

-- The word on the slash command, read when typed.
function L.Declare(k, diag)
    if not (diag and type(diag.commands) == "table") then return end
    diag.commands[L.WORD] = function()
        local client = k.client
        if type(client) ~= "table" then return end
        local function say(text) client.print(k.id.title .. ": " .. text) end
        local db
        if type(client.questieModule) == "function" then db = call(client.questieModule, "QuestieDB") end
        if type(db) ~= "table" then return say(L.NO_QUESTIE) end
        local classId = L.ClassId(call(client.class))
        if not classId then return say(L.NO_CLASS) end
        local zones = call(client.questieModule, "ZoneDB")
        local inLog = {}
        local rows = ns.Nav and ns.Nav.QuestLogRows and ns.Nav.QuestLogRows(client)
        for _, r in ipairs(type(rows) == "table" and rows or {}) do
            if type(r) == "table" and r.id ~= nil then inLog[r.id] = true end
        end
        local lines = L.Lines(L.Quests(db, zones, classId, client.questDone, inLog), client.mapName)
        for i, line in ipairs(lines) do
            if i == 1 then say(line) else client.print(line) end
        end
    end
    if type(diag.help) == "table" then diag.help[L.WORD] = L.HELP end
end

L.Declare(ns, ns.diag)
