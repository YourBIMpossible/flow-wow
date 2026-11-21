-- Where quest objectives were done, learned as you play.
--
-- "Fix all of these no known spot issues" (0.35.205). Some quests have no
-- place in the quest data (the ones new to WoW: Forever, like Stalk With The
-- Earthmother) and no marker of the game's, so Flow could only list them
-- with "no known spot". Nothing on this computer knows where they are until
-- somebody does them, so Flow remembers:
--
--   * an objective Flow couldn't place moves on (0/1 -> 1/1, 2/8 -> 3/8):
--     where you stood is kept for that objective;
--   * a quest is handed in: where you stood is kept for its turn-in.
--
-- The next time that quest is in a log (another character of yours, or the
-- rest of an objective with several counts) the step goes there, marked as
-- learned. Kept for the whole account (not per character); only quest IDs
-- and map spots, nothing about you. /flow spots lists them, and they're in
-- the export for tools\route-check.ps1.
--
--   ns.learnedSpots.Points(questID, index | "done") -> { { map, x, y } } or nil
--   ns.learnedSpots.Note(questID, index | "done", map, x, y) -> added?
--
-- A spot can be wrong (the count moved on somewhere else). Each spot keeps
-- when it was last seen and how often (at, n): one seen again is confirmed;
-- once an objective has LS.MAX, a new spot takes the place of one seen only
-- once and not for LS.STALE days. /flow spots forget <quest> [objective|done]
-- drops a quest's spots by hand.

local _, ns = ...
local LS = {}
ns.learnedSpots = LS

LS.MAX = 6        -- spots kept per objective
LS.APART = 0.02   -- two spots closer than this (map share) are one
LS.STALE = 30 * 86400   -- a spot seen once, this long ago, may make room

ns:OnLoad(function(saved) saved.learnedSpots = saved.learnedSpots or {} end)

-- Pure: adds a spot to a list unless one is already there (then that one is
-- seen again). A full list makes room only by a stale spot: seen once, more
-- than LS.STALE before now (a spot with no time is kept). -> added?
function LS.Add(list, map, x, y, max, apart, now)
    if not (map and x and y) then return false end
    apart = apart or LS.APART
    for _, p in ipairs(list) do
        if p.map == map and math.abs(p.x - x) < apart and math.abs(p.y - y) < apart then
            p.n, p.at = (p.n or 1) + 1, now or p.at
            return false
        end
    end
    local spot = { map = map, x = x, y = y, n = 1, at = now }
    if #list < (max or LS.MAX) then
        list[#list + 1] = spot
        return true
    end
    local oldest
    for i, p in ipairs(list) do
        if (p.n or 1) <= 1 and p.at and now and now - p.at > LS.STALE
            and (not oldest or p.at < list[oldest].at) then oldest = i end
    end
    if not oldest then return false end
    list[oldest] = spot
    return true
end

-- Pure: drops a quest's learned spots, one objective's ("done": the turn-in)
-- or all. -> how many spots went.
function LS.Forget(spots, questID, index)
    local q = spots and spots[questID]
    if not q then return 0 end
    local n = 0
    for i, list in pairs(q) do
        if index == nil or i == index then
            n = n + #list
            q[i] = nil
        end
    end
    if next(q) == nil then spots[questID] = nil end
    return n
end

function LS.Note(questID, index, map, x, y)
    if not (questID and index and ns.db and ns.db.learnedSpots) then return false end
    local q = ns.db.learnedSpots[questID] or {}
    ns.db.learnedSpots[questID] = q
    q[index] = q[index] or {}
    return LS.Add(q[index], map, x, y, nil, nil, time())
end

function LS.Points(questID, index)
    local q = ns.db and ns.db.learnedSpots and ns.db.learnedSpots[questID]
    local list = q and q[index]
    -- (None of your own: what players shared, that came with Flow. Facts.lua)
    if (not list or #list == 0) and ns.facts and ns.facts.SharedSpots then return ns.facts.SharedSpots(questID, index) end
    if not list or #list == 0 then return nil end
    local out = {}
    for _, p in ipairs(list) do out[#out + 1] = { map = p.map, x = p.x, y = p.y } end
    return out
end

-- Pure: which objectives moved on. before, now: { [index] = count done }.
function LS.Moved(before, now)
    local out = {}
    for i, n in pairs(now or {}) do
        if before and before[i] ~= nil and n > before[i] then out[#out + 1] = i end
    end
    table.sort(out)
    return out
end

-- Is this step one Flow couldn't place? (Only those are learned: a quest
-- the data places is already right.)
local function unplaced(key)
    for _, g in ipairs(ns.nav and ns.nav.blockedGoals or {}) do
        if g.key == key then return true end
    end
    return false
end

local seen = {}   -- [questID] = { [index] = count done }
local function look()
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetQuestObjectives) then return end
    local here
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        local id = info and not info.isHeader and info.questID
        if id then
            local now = {}
            for j, o in ipairs(C_QuestLog.GetQuestObjectives(id) or {}) do
                local n = ns.api.Safe(o.numFulfilled)
                now[j] = type(n) == "number" and n or (o.finished and 1 or 0)
            end
            for _, j in ipairs(LS.Moved(seen[id], now)) do
                -- (Also once it has a learned spot: more spots for the same thing.)
                if unplaced(id .. ":" .. j) or LS.Points(id, j) then
                    here = here or (ns.nav and ns.nav:PlayerPos())
                    if here and LS.Note(id, j, here.map, here.x, here.y) then
                        ns:Log("spots", string.format("learned: quest %d objective %d at map %d %.1f, %.1f", id, j, here.map, here.x * 100, here.y * 100))
                        if ns.nav and ns.nav.RequestCollect then ns.nav.RequestCollect("learned a quest spot") end
                    end
                end
            end
            seen[id] = now
        end
    end
end
ns:On("QUEST_LOG_UPDATE", function() pcall(look) end)

-- Handed in: where its turn-in is.
ns:On("QUEST_TURNED_IN", function(questID)
    local id = ns.api.Safe(questID)
    local here = ns.nav and ns.nav:PlayerPos()
    if type(id) == "number" and here and LS.Note(id, "done", here.map, here.x, here.y) then
        ns:Log("spots", string.format("learned: quest %d is handed in at map %d %.1f, %.1f", id, here.map, here.x * 100, here.y * 100))
    end
end)

function LS.Lines()
    local out, n = {}, 0
    for id, q in pairs(ns.db.learnedSpots or {}) do
        for index, list in pairs(q) do
            for _, p in ipairs(list) do
                n = n + 1
                if n <= 40 then
                    out[#out + 1] = string.format("quest %s %s: map %s %.1f, %.1f", tostring(id),
                        index == "done" and "turn-in" or ("objective " .. tostring(index)), tostring(p.map), p.x * 100, p.y * 100)
                end
            end
        end
    end
    table.sort(out)
    table.insert(out, 1, string.format("Flow has learned %d quest spot(s) from where you did them", n))
    return out
end
ns.commands.spots = function(arg)
    local id, which = (arg or ""):match("^forget%s+(%d+)%s*(%S*)$")
    if id then
        local index = which == "done" and "done" or tonumber(which)
        local n = LS.Forget(ns.db.learnedSpots, tonumber(id), index)
        ns:Print(string.format("forgot %d learned spot(s) for quest %s%s", n, id, which ~= "" and (" " .. which) or ""))
        if n > 0 and ns.nav and ns.nav.RequestCollect then ns.nav.RequestCollect("forgot a quest spot") end
        return
    end
    for i, l in ipairs(LS.Lines()) do if i == 1 then ns:Print(l) else print("  " .. l) end end
end
ns:Register("help", "spots", { order = 59, title = "Learned quest spots", lines = {
    "A quest Flow can't place (\"no known spot\") is learned where you do it: the next time, the step goes there.",
    "/flow spots: the list. /flow spots forget <quest> [objective|done]: drop a wrong one.",
} })
