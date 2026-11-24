local _, ns = ...
-- Z-Flow: "There: <name>" (parity row A1-17, lead section 481). When a
-- creature the arrow's quest step needs has a nameplate in view, the
-- arrow's second line names it.
-- WHICH CREATURES: the quest's unfinished objectives, as the nameplate
-- quest marks find them (UI/PlateQuests.lua PQ.Index, Questie's objective
-- data only: your learned drops are not passed; read, not changed). Only from data,
-- never from a name. Without Questie, or with no such plate: nil.
-- WHICH PLATE: the first in view by unit (nameplate1 before nameplate2):
-- the client tells no screen position, so "nearest the middle" is not
-- known here.
-- THE NAME: Questie's GetNPC(id).name, else the plate's name from
-- client.plateEnemies(), else nil (no words without a name).
-- Reads: client.plates(fn), client.plateCreature(unit), client.plateEnemies(),
-- client.questLog() through N.QuestLogRows, client.questieModule("QuestieDB").
-- Compared with Flow Modules/Nav/Nav.lua N:VisibleTarget and its
-- "There: " .. tgt.name: Flow matches the step's npc names against
-- UnitName on each plate, skips the dead, picks the plate nearest the
-- screen middle and turns the arrow to it. Here: creature ids, the first
-- plate, and the arrow is not turned (no plate position read); the dead
-- are not skipped (no read for it).
-- LOOK ONLY: nothing is clicked or targeted. Not tested in game.
--
-- Pure:
--   PT.Wanted(index, quest) -> { [npc id] = true }
--   PT.Pick(units, creatureOf, wanted) -> unit, npc id   (or nil)
--   PT.Words(name) -> "There: <name>" or nil
-- Module "plateTarget" provides There(quest) -> text or nil.
ns.Nav = ns.Nav or {}
local N = ns.Nav
local PT = {}
N.PlateTarget = PT

PT.NAME = "plateTarget"
PT.THERE = "There: %s"

function PT.Wanted(index, quest)
    local out = {}
    if type(index) ~= "table" or quest == nil then return out end
    for npc, list in pairs(index) do
        for _, e in ipairs(type(list) == "table" and list or {}) do
            if type(e) == "table" and e.quest == quest then out[npc] = true end
        end
    end
    return out
end

local function plateNumber(unit)
    return tonumber(tostring(unit):match("^nameplate(%d+)$")) or math.huge
end

function PT.Pick(units, creatureOf, wanted)
    if type(units) ~= "table" or type(wanted) ~= "table" then return nil end
    local list = {}
    for unit in pairs(units) do list[#list + 1] = unit end
    table.sort(list, function(a, b) return plateNumber(a) < plateNumber(b) end)
    for _, unit in ipairs(list) do
        local ok, npc = pcall(creatureOf, unit)
        if ok and npc ~= nil and wanted[npc] then return unit, npc end
    end
    return nil
end

function PT.Words(name)
    if type(name) ~= "string" or name == "" then return nil end
    return PT.THERE:format(name)
end

function PT.Declare(k)
    local api = {}
    local ctx
    local cancel
    local inView = {}

    local function ask(name, ...)
        local c = ctx and ctx.client
        if type(c) ~= "table" or type(c[name]) ~= "function" then return nil end
        local ok, v = pcall(c[name], ...)
        if ok then return v end
        return nil
    end

    local function dbCall(db, name, id)
        if type(db) ~= "table" or type(db[name]) ~= "function" then return nil end
        local ok, v = pcall(db[name], id)
        if ok and v ~= nil then return v end
        ok, v = pcall(db[name], db, id)
        if ok then return v end
        return nil
    end

    local function onPlate(what, unit)
        if what == "added" then inView[unit] = true elseif what == "removed" then inView[unit] = nil end
    end

    local function nameOf(db, unit, npc)
        local npcRow = dbCall(db, "GetNPC", npc)
        if type(npcRow) == "table" and type(npcRow.name) == "string" and npcRow.name ~= "" then return npcRow.name end
        for _, row in ipairs(ask("plateEnemies") or {}) do
            if type(row) == "table" and row.unit == unit and type(row.name) == "string" then return row.name end
        end
        return nil
    end

    function api.There(quest)
        if not ctx or quest == nil or next(inView) == nil then return nil end
        local PQ, db = ns.PlateQuests, ask("questieModule", "QuestieDB")
        if not PQ or type(PQ.Index) ~= "function" or type(db) ~= "table" then return nil end
        local rows = N.QuestLogRows and N.QuestLogRows(ctx.client) or nil
        local ok, index = pcall(PQ.Index, rows, db, nil)
        if not ok then return nil end
        local unit, npc = PT.Pick(inView, function(u) return ask("plateCreature", u) end, PT.Wanted(index, quest))
        if not unit then return nil end
        return PT.Words(nameOf(db, unit, npc))
    end

    k:Module({
        name = PT.NAME,
        needs = { "client" },
        provides = { There = function(quest) return api.There(quest) end },
        start = function(c)
            ctx = c
            local c2 = c.client
            if type(c2) == "table" and type(c2.plates) == "function" then
                local ok, off = pcall(c2.plates, onPlate)
                if ok and type(off) == "function" then cancel = off end
            end
        end,
        stop = function()
            if cancel then pcall(cancel) end
            cancel, ctx, inView = nil, nil, {}
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.plateTarget = PT.Declare(ns)
