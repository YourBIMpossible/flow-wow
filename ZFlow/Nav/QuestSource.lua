local _, ns = ...
-- Z-Flow quest source (S43): which of the player's own quests the quest
-- arrow points at. Pure: plain tables in, a step or nil out; nothing handed
-- in is changed, nothing is remembered. No quest, place or route data is
-- authored here: the rows are the player's quest log and the places are
-- what the reader (Nav/QuestRead.lua) was given at runtime.
--
-- Q.Pick(rows, places, here, focus) -> step or nil
--   rows    the quest log, in its own order:
--           { { id, title, complete, failed, objectives = { { text, done } } } }
--           complete: a plain true when the quest is ready to hand in.
--           failed: a plain true; such a quest is never a step.
--   places  { [id] = { objectives = { [i] = spot }, turnIn = spot } } or nil
--           spot = { points = { { map, x, y } }, elsewhere = bool, name }
--           points are on the map the reader was asked for, x and y shares
--           0..1. elsewhere: a place is known, on another map only. name
--           (turnIn only): who takes the quest in, when that is known.
--           Anything absent is "not known".
--   here    { map, x, y, cont, size = { w, h } in yards or nil }
--           every field may be absent.
--   focus   { quest = id or nil, watched = { id, ... } or nil } or nil:
--           the quest the player picked out, and the watch list of the
--           player, as the client says them (client.questFocus). nil, or a
--           table with neither, is "the player picked nothing".
--
-- The quest the player picked out comes first (section 131). When
-- focus.quest is a quest in the log that is not failed and has something
-- left, the step is that quest's and no other quest is looked at:
--   its nearest unfinished objective on the map the player is on; for a
--   complete quest the nearest point where it is handed in; else words
--   only for that quest, as in rule 3.
-- A picked quest that is not in the log (handed in, abandoned), is failed,
-- or has nothing left gives no step of its own.
-- Then, when focus.watched names quests that are in the log, rules 1 to 3
-- are asked of those quests alone; when that gives no step, of the whole
-- log. With no focus the answer is that of rules 1 to 3 on the whole log.
--
-- Rules 1 to 3, the first that gives a step:
--   1. the nearest point of an unfinished objective, on the map the player
--      is on, of a quest that is neither complete nor failed;
--   2. the nearest point where a complete quest is handed in, on that map;
--   3. words only (no place, so no needle): the first quest in the log with
--      something left to do. Its last line is Q.ELSEWHERE when a place is
--      known on another map (and the player's own map is known), else
--      Q.UNKNOWN_PLACE.
--   nil when the log has no such quest.
-- Nearest is in yards when here.size is known, else in map shares. With the
-- player's x, y not known a point cannot be chosen, so rule 3 answers.
--
--   step with a place: { quest = id, objective = i or nil, turnIn = bool,
--                        label = title, detail = line,
--                        place = { cont, map, x, y } }
--   step without:      { quest, objective, turnIn, label, detail,
--                        lines = { title, line, why }, still = true }
--   the shape Arrow.GuideSource takes as given.quest. detail is the
--   objective's own text, or Q.TurnInLine(name) for a turn-in.
ns.Nav = ns.Nav or {}
local N = ns.Nav
local Q = {}
N.QuestSource = Q

-- The setting row the quest arrow's source is switched by. The row is the
-- lead's to add to Settings/Model.lua: bool, on by default.
Q.SETTING = "quest.arrow"

-- Player-visible words, authored here.
Q.UNKNOWN_PLACE = "location unknown"
Q.ELSEWHERE = "on another map"
Q.TURN_IN = "Turn in"
Q.TURN_IN_TO = "Turn in: %s"

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function Q.TurnInLine(name)
    if type(name) == "string" and name ~= "" then return Q.TURN_IN_TO:format(name) end
    return Q.TURN_IN
end

local function usable(row)
    return type(row) == "table" and row.id ~= nil and type(row.title) == "string" and row.failed ~= true
end

-- The objectives of a row still to do: { { i, text } }.
local function open(row)
    local out = {}
    if type(row.objectives) ~= "table" then return out end
    for i, o in ipairs(row.objectives) do
        if type(o) == "table" and o.done ~= true then
            out[#out + 1] = { i = i, text = type(o.text) == "string" and o.text or nil }
        end
    end
    return out
end

local function spotOf(places, id, i)
    local p = type(places) == "table" and places[id] or nil
    if type(p) ~= "table" then return nil end
    local spot
    if i == nil then spot = p.turnIn
    elseif type(p.objectives) == "table" then spot = p.objectives[i] end
    return type(spot) == "table" and spot or nil
end

-- The nearest point of a spot on the player's map: the point and how far,
-- squared (yards with a size, else shares).
local function nearest(spot, here)
    if type(spot) ~= "table" or type(spot.points) ~= "table" then return nil end
    local w, h = 1, 1
    if type(here.size) == "table" and finite(here.size.w) and finite(here.size.h) then
        w, h = here.size.w, here.size.h
    end
    local best, bestD
    for _, pt in ipairs(spot.points) do
        if type(pt) == "table" and pt.map == here.map and finite(pt.x) and finite(pt.y) then
            local dx, dy = (pt.x - here.x) * w, (pt.y - here.y) * h
            local d = dx * dx + dy * dy
            if not best or d < bestD then best, bestD = pt, d end
        end
    end
    return best, bestD
end

local function placed(row, i, detail, pt, here)
    return { quest = row.id, objective = i, turnIn = i == nil, label = row.title, detail = detail,
             place = { cont = here.cont, map = pt.map, x = pt.x, y = pt.y } }
end

local function worded(row, i, detail, spot, here)
    -- Elsewhere is said only when the map the player is on is known.
    local why = (here.map ~= nil and type(spot) == "table" and spot.elsewhere == true)
        and Q.ELSEWHERE or Q.UNKNOWN_PLACE
    local lines = { row.title }
    if detail ~= nil then lines[#lines + 1] = detail end
    lines[#lines + 1] = why
    return { quest = row.id, objective = i, turnIn = i == nil, label = row.title, detail = detail,
             lines = lines, still = true }
end

-- The step of one quest alone: its nearest unfinished objective on this
-- map, for a complete quest its nearest turn-in, else that quest in words.
-- nil when the quest has nothing left to do.
local function ofQuest(row, places, here, canPoint)
    if row.complete == true then
        local spot = spotOf(places, row.id, nil)
        local pt = canPoint and nearest(spot, here) or nil
        if pt then return placed(row, nil, Q.TurnInLine(spot.name), pt, here) end
        return worded(row, nil, Q.TurnInLine(spot and spot.name), spot, here)
    end
    local todo = open(row)
    if #todo == 0 then return nil end
    if canPoint then
        local best, bestD
        for _, o in ipairs(todo) do
            local pt, d = nearest(spotOf(places, row.id, o.i), here)
            if pt and (not best or d < bestD) then
                best, bestD = placed(row, o.i, o.text, pt, here), d
            end
        end
        if best then return best end
    end
    local o = todo[1]
    return worded(row, o.i, o.text, spotOf(places, row.id, o.i), here)
end

-- Rules 1 to 3 over these rows.
local function byRules(rows, places, here, canPoint)
    if canPoint then
        -- 1. the nearest unfinished objective on this map.
        local best, bestD
        for _, row in ipairs(rows) do
            if usable(row) and row.complete ~= true then
                for _, o in ipairs(open(row)) do
                    local pt, d = nearest(spotOf(places, row.id, o.i), here)
                    if pt and (not best or d < bestD) then
                        best, bestD = placed(row, o.i, o.text, pt, here), d
                    end
                end
            end
        end
        if best then return best end
        -- 2. the nearest turn-in of a complete quest on this map.
        for _, row in ipairs(rows) do
            if usable(row) and row.complete == true then
                local spot = spotOf(places, row.id, nil)
                local pt, d = nearest(spot, here)
                if pt and (not best or d < bestD) then
                    best, bestD = placed(row, nil, Q.TurnInLine(spot.name), pt, here), d
                end
            end
        end
        if best then return best end
    end

    -- 3. words only: the first quest in the log with something left to do.
    for _, row in ipairs(rows) do
        if usable(row) then
            if row.complete == true then
                local spot = spotOf(places, row.id, nil)
                return worded(row, nil, Q.TurnInLine(spot and spot.name), spot, here)
            end
            local o = open(row)[1]
            if o then return worded(row, o.i, o.text, spotOf(places, row.id, o.i), here) end
        end
    end
    return nil
end

function Q.Pick(rows, places, here, focus)
    if type(rows) ~= "table" then return nil end
    here = type(here) == "table" and here or {}
    local canPoint = here.map ~= nil and finite(here.x) and finite(here.y)

    if type(focus) == "table" then
        -- The quest the player picked out, when it is still to be done.
        if focus.quest ~= nil then
            for _, row in ipairs(rows) do
                if usable(row) and row.id == focus.quest then
                    local step = ofQuest(row, places, here, canPoint)
                    if step then return step end
                    break
                end
            end
        end
        -- Then the quests the player watches, before the rest of the log.
        if type(focus.watched) == "table" then
            local on = {}
            for _, id in ipairs(focus.watched) do on[id] = true end
            local mine = {}
            for _, row in ipairs(rows) do
                if type(row) == "table" and row.id ~= nil and on[row.id] then mine[#mine + 1] = row end
            end
            if #mine > 0 then
                local step = byRules(mine, places, here, canPoint)
                if step then return step end
            end
        end
    end
    return byRules(rows, places, here, canPoint)
end
