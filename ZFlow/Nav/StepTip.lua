local _, ns = ...
-- Z-Flow: the quest step's hover lines (parity row A1-12, lead section 488).
-- Lines Flow's tooltip has that Z-Flow's lacked, as words for the existing
-- arrow tooltip:
--   the quest level, in its colour, and what the colour says
--   the objectives with their progress (done ones green)
--   XP: about N (a note), from the quest level and yours
--   "Also here": the other route stops within ST.ALSO_YARDS of you
-- Reads: client.questLog() through N.QuestLogRows, client.level(),
-- client.position(), client.mapSize(map), Questie QuestieDB
-- QueryQuestSingle(id, "questLevel"), tripRoute Current() (read, not changed).
-- Without a quest level there is no level or XP line.
-- Compared with Flow Modules/Nav/Nav.lua N:FillTooltip and the arrow's
-- "Also here", Modules/Quests/QuestLevels.lua QL.TIERS / QL.Tier and
-- Modules/Nav/XpValue.lua X.Estimate / X.Share / the XP note: the same
-- tiers, words, curve and notes. Flow takes the real reward XP from the
-- quest log when the client gives it; this client has no such read, so XP
-- is always "about". Flow's "Also here" uses the step's area; here it is
-- the stop's place within ST.ALSO_YARDS (a first guess). Flow also obeys
-- the game's quest-level settings; those are not read here.
-- LOOK ONLY. Not tested in game.
--
-- Pure:
--   ST.Tier(level, mine) -> "red" | "orange" | "yellow" | "green" | "olive" | "grey" | nil
--   ST.LevelLine(level, mine) -> "|cff<hex>Level N|r: <says>" or nil
--   ST.Xp(level, mine) -> xp, note   (nil without both levels)
--   ST.ObjectiveLines(objectives) -> { "  <text>" ... }
--   ST.Also(stops, quest, yardsTo) -> the labels of the other stops within
--     ST.ALSO_YARDS (yardsTo(place) -> yards or nil), each quest once
--     (R-06: one stop per objective named the quest twice)
--   ST.Lines(info) -> lines; info = { level, mine, objectives, also }
-- Module "stepTip" provides Lines(quest) -> lines or nil.
ns.Nav = ns.Nav or {}
local N = ns.Nav
local ST = {}
N.StepTip = ST

ST.NAME = "stepTip"
ST.ALSO_YARDS = 50
-- Player-visible words, from Flow.
ST.TIERS = {
    red    = { hex = "ff3030", says = "5 or more levels above you: you can't do it yet" },
    orange = { hex = "ff8040", says = "3 or 4 levels above you: hard" },
    yellow = { hex = "ffff00", says = "about your level: full XP" },
    green  = { hex = "40c040", says = "a few levels below you: easy, still full XP" },
    olive  = { hex = "9aa04a", says = "well below you: the XP is dropping" },
    grey   = { hex = "808080", says = "far below you: next to no XP" },
}
ST.LEVEL = "|cff%sLevel %d|r: %s"
ST.XP = "XP: about %d (%s)"
ST.DONE = "|cff66e666  %s|r"
ST.TODO = "  %s"
ST.ALSO = "Also here"
local DECAY = { [6] = 0.8, [7] = 0.6, [8] = 0.4, [9] = 0.2 }

local function whole(v)
    return type(v) == "number" and v == v and v >= 1 and v < 1000 and math.floor(v) == v
end

function ST.Tier(level, mine)
    if not (whole(level) and whole(mine)) then return nil end
    local d = level - mine
    if d >= 5 then return "red" end
    if d >= 3 then return "orange" end
    if d >= -2 then return "yellow" end
    if d >= -5 then return "green" end
    if d >= -9 then return "olive" end
    return "grey"
end

function ST.LevelLine(level, mine)
    local tier = ST.Tier(level, mine)
    if not tier then return nil end
    return ST.LEVEL:format(ST.TIERS[tier].hex, level, ST.TIERS[tier].says)
end

function ST.Xp(level, mine)
    if not (whole(level) and whole(mine)) then return nil end
    local full = level <= 10 and 80 + 55 * level or 630 + 95 * (level - 10)
    local below = mine - level
    local share = below <= 5 and 1 or DECAY[below] or 0.1
    local above = level - mine
    local note
    if above >= 3 then note = ("%d levels above you: slower and riskier"):format(above)
    elseif above == 2 then note = "2 levels above you"
    elseif share < 1 then note = ("%d%% XP: going grey"):format(share * 100)
    elseif below >= 3 then note = "full XP for now; it starts to drop at level " .. (level + 6)
    else note = "full XP" end
    return math.floor(full * share + 0.5), note
end

function ST.ObjectiveLines(objectives)
    local out = {}
    for _, o in ipairs(type(objectives) == "table" and objectives or {}) do
        if type(o) == "table" and type(o.text) == "string" and o.text ~= "" then
            out[#out + 1] = (o.done and ST.DONE or ST.TODO):format(o.text)
        end
    end
    return out
end

function ST.Also(stops, quest, yardsTo)
    local out, seen = {}, {}
    if type(stops) ~= "table" or type(yardsTo) ~= "function" then return out end
    for _, s in ipairs(stops) do
        if type(s) == "table" and type(s.label) == "string" and (s.quest == nil or s.quest ~= quest) then
            local key = s.quest
            if key == nil then key = "label:" .. s.label end
            if not seen[key] then
                local ok, d = pcall(yardsTo, s.place)
                if ok and type(d) == "number" and d <= ST.ALSO_YARDS then
                    seen[key] = true
                    out[#out + 1] = s.label
                end
            end
        end
    end
    return out
end

function ST.Lines(info)
    local out = {}
    if type(info) ~= "table" then return out end
    local level = ST.LevelLine(info.level, info.mine)
    if level then out[#out + 1] = level end
    for _, l in ipairs(ST.ObjectiveLines(info.objectives)) do out[#out + 1] = l end
    local xp, note = ST.Xp(info.level, info.mine)
    if xp then out[#out + 1] = ST.XP:format(xp, note) end
    local also = type(info.also) == "table" and info.also or {}
    if #also > 0 then
        out[#out + 1] = ST.ALSO
        for _, a in ipairs(also) do out[#out + 1] = "  " .. tostring(a) end
    end
    return out
end

function ST.Declare(k)
    local api = {}
    local ctx

    local function ask(name, ...)
        local c = ctx and ctx.client
        if type(c) ~= "table" or type(c[name]) ~= "function" then return nil end
        local ok, v = pcall(c[name], ...)
        if ok then return v end
        return nil
    end

    local function questLevel(quest)
        local db = ask("questieModule", "QuestieDB")
        if type(db) ~= "table" or type(db.QueryQuestSingle) ~= "function" then return nil end
        local ok, v = pcall(db.QueryQuestSingle, quest, "questLevel")
        if ok and type(v) == "number" then return v end
        return nil
    end

    local function yards(a, b)
        if type(a) ~= "table" or type(b) ~= "table" or a.map ~= b.map then return nil end
        local size = ask("mapSize", a.map)
        if type(size) ~= "table" or type(size.w) ~= "number" or type(size.h) ~= "number" then return nil end
        local dx, dy = (a.x - b.x) * size.w, (a.y - b.y) * size.h
        return math.sqrt(dx * dx + dy * dy)
    end

    local function alsoHere(quest)
        local out = {}
        local ok, walk = pcall(ctx.use, "tripRoute")
        if not ok or type(walk) ~= "table" or type(walk.Current) == "nil" then return out end
        local fine, cur = pcall(walk.Current)
        local stops = fine and type(cur) == "table" and cur.stops or nil
        local here = ask("position")
        return ST.Also(stops, quest, function(place) return yards(here, place) end)
    end

    function api.Lines(quest)
        if not ctx or quest == nil then return nil end
        local row
        for _, r in ipairs(N.QuestLogRows and N.QuestLogRows(ctx.client) or {}) do
            if r.id == quest then row = r break end
        end
        if not row then return nil end
        local lines = ST.Lines({ level = questLevel(quest), mine = ask("level"),
                                 objectives = row.objectives, also = alsoHere(quest) })
        return #lines > 0 and lines or nil
    end

    k:Module({
        name = ST.NAME,
        needs = { "client" },
        provides = { Lines = function(quest) return api.Lines(quest) end },
        start = function(c) ctx = c end,
        stop = function() ctx = nil end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.stepTip = ST.Declare(ns)
