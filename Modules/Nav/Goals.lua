-- Navigation goals from your quest log.
--   finished quest      -> go to the NPC (or object) that takes it
--   kill objective      -> nearest spawn of that mob
--   collect objective   -> nearest mob/object that drops the item
--   use/click objective -> nearest spawn of that object
-- Locations come from Questie + QuestieDB (read at runtime, see QuestData.lua).
-- Without them, the game's own quest waypoint is used where the client has one.

local _, ns = ...

local MAX_POINTS = 80   -- spawns per goal

-- Daily quest? (Questie quest flags; 0x1000 is the daily flag.)
local function isDaily(quest)
    return quest and quest.questFlags and bit and bit.band(quest.questFlags, 0x1000) ~= 0 or false
end

-- Your quest log: { { id, title, complete, objectives = { {text, finished} } } }
local function questLog()
    local out = {}
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.questID then
                local q = { id = info.questID, title = info.title, objectives = {} }
                q.complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID) or false
                for _, o in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do
                    q.objectives[#q.objectives + 1] = { text = o.text, finished = o.finished }
                end
                out[#out + 1] = q
            end
        end
    elseif GetNumQuestLogEntries then
        for i = 1, GetNumQuestLogEntries() do
            local title, _, _, isHeader, _, isComplete, _, id = GetQuestLogTitle(i)
            if not isHeader and id then
                local q = { id = id, title = title, complete = isComplete == 1, objectives = {} }
                for j = 1, GetNumQuestLeaderBoards(i) do
                    local text, _, finished = GetQuestLogLeaderBoard(j, i)
                    q.objectives[#q.objectives + 1] = { text = text, finished = finished }
                end
                out[#out + 1] = q
            end
        end
    end
    return out
end

-- Questie modules use a mix of "." and ":" calls; try both.
local function call(db, fname, id)
    local fn = db[fname]
    if type(fn) ~= "function" then return nil end
    local ok, r = pcall(fn, id)
    if ok and type(r) == "table" then return r end
    ok, r = pcall(fn, db, id)
    if ok and type(r) == "table" then return r end
end

-- Questie spawn tables are { [areaId] = { {x, y}, ... } } in 0-100 coords.
local function addSpawns(points, spawns, cap, onlyMap)
    for areaId, list in pairs(spawns or {}) do
        local map = ns.quests:UiMapForArea(areaId)
        if map and (not onlyMap or map == onlyMap) then
            for _, c in ipairs(list) do
                if #points >= (cap or MAX_POINTS) then return end
                if c[1] and c[1] >= 0 and c[2] and c[2] >= 0 then
                    points[#points + 1] = { map = map, x = c[1] / 100, y = c[2] / 100 }
                end
            end
        end
    end
end

-- Spawn tables -> at most MAX_POINTS spots, spread over all of them with the
-- ones on your map first (ns.quests.SpreadPoints): every mob that drops the
-- item gets its share, not just the first one listed.
local function pointsFrom(tables)
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
    local pts, _, known = ns.quests.SpreadPoints(tables, MAX_POINTS, { map = map })
    return pts, known
end

-- Adds the NPC's / object's spawn table to `tables`; returns its name (and the NPC).
local function npcSpawns(db, tables, id)
    local npc = call(db, "GetNPC", id)
    if npc and npc.spawns then tables[#tables + 1] = npc.spawns end
    return npc and npc.name, npc
end

local function objectSpawns(db, tables, id)
    local obj = call(db, "GetObject", id)
    if obj and obj.spawns then tables[#tables + 1] = obj.spawns end
    return obj and obj.name
end
ns.quests.LogEntries = questLog  -- shared with SkillPlan.lua

-- The goals for one quest: its turn-in, and (while unfinished) a goal per
-- objective you still need. Used for your own log and for a party member's
-- quests (Party.lua: "help Bob").
--   q    = { id, title, complete, objectives = { { text, finished, have, need } } }
--   opts = { prefix = "help:" (key prefix), who = "Bob" (shown in the text),
--            skip = function(key) -> true to leave a goal out,
--            unplaced = {} (gets { id, title, why } for what can't be placed) }
-- Appends to `goals`. A quest Flow can't place used to drop off the route
-- without a word ("Dirt-stained Map"); `unplaced` says which and why, for
-- /flow nav why and the diagnostics.
local function questGoals(db, q, goals, opts)
    opts = opts or {}
    local prefix, skip = opts.prefix or "", opts.skip or function() return false end
    local whose = opts.who and (opts.who .. ": ") or ""
    local function cant(why)
        if opts.unplaced then opts.unplaced[#opts.unplaced + 1] = { id = q.id, title = q.title, why = why } end
    end
    local quest = call(db, "GetQuest", q.id)
    if not quest then cant("Questie doesn't know this quest (a WoW: Forever one?), so Flow has no place for it") return end
    local title = q.title or quest.name
    -- Where the quest is handed in. For unfinished quests this is a later
    -- stop that the planner puts after the objectives (deps), so it can
    -- decide "finish, then turn in on the way".
    local turnSpawns, who = {}, nil
    local fin = ns.quests.FinisherOf(quest)
    for _, id in ipairs(fin.NPC or {}) do
        who = npcSpawns(db, turnSpawns, id) or who
    end
    for _, id in ipairs(fin.GameObject or {}) do
        who = objectSpawns(db, turnSpawns, id) or who
    end
    local turnIn = {
        key = prefix .. q.id .. ":done", weight = 0.8, points = pointsFrom(turnSpawns), level = quest.level,
        npcs = who and { who } or nil,
        kind = isDaily(quest) and "daily" or "turnin",
        title = title, helping = opts.who,
        text = whose .. "Turn in: " .. (title or "quest"),
        details = { (q.complete and "Quest complete. " or "After the objectives. ")
            .. "Hand it in to " .. (who or "the quest giver") .. "." },
        deps = {},
    }
    if not skip(turnIn.key) then goals[#goals + 1] = turnIn end
    if #turnIn.points == 0 then
        cant("Flow doesn't know where it's handed in (" .. (who or "no NPC or object in Questie") .. ")")
    end
    if q.complete then return end
    for i, obj in ipairs(q.objectives) do
        local od = quest.ObjectiveData and quest.ObjectiveData[i]
        -- "Raise your X skill to N": planned by SkillPlan.lua (gather,
        -- smelt, craft), not by walking to the trainer.
        local skillObj = obj.text and ns.skillPlan and ns.skillPlan.ParseObjective(obj.text)
        local key = prefix .. q.id .. ":" .. i
        if not obj.finished and not od and not skillObj then
            cant(string.format("objective %d (%s): Questie has no data for it", i, tostring(obj.text or "?")))
        end
        if not obj.finished and od and not skillObj then
            local spawns, verb, what, elite = {}, nil, nil, false
            local targets = {}  -- mob / NPC names (the arrow finds their nameplates in the area)
            if od.Type == "monster" then
                local npcRaw
                what, npcRaw = npcSpawns(db, spawns, od.Id); verb = "Kill"
                if what then targets[#targets + 1] = what end
                -- Elite mobs (Questie rank 1+): flagged and planned later; bring a friend.
                if npcRaw and (npcRaw.rank or 0) >= 1 then elite = true end
            elseif od.Type == "object" then
                what = objectSpawns(db, spawns, od.Id); verb = "Use"
            elseif od.Type == "item" then
                local item = call(db, "GetItem", od.Id)
                verb = "Collect"; what = item and item.name
                -- Elite only if EVERY mob that drops it is elite (one elite
                -- among normal kobolds doesn't make the objective elite).
                local anyNormal, anyElite = false, false
                for _, npcId in ipairs(item and item.npcDrops or {}) do
                    local dropper, npcRaw = npcSpawns(db, spawns, npcId)
                    if dropper then targets[#targets + 1] = dropper end
                    if npcRaw and (npcRaw.rank or 0) >= 1 then anyElite = true else anyNormal = true end
                end
                elite = anyElite and not anyNormal
                for _, objId in ipairs(item and item.objectDrops or {}) do objectSpawns(db, spawns, objId) end
            end
            local points, known = pointsFrom(spawns)
            -- A quest 3+ levels above you (orange or red): its mobs hit hard.
            -- Planned later, like elites, so the easier ones come first.
            local hard = (quest.level or 0) - (opts.level or UnitLevel("player")) >= ns.quests.HARD_ABOVE
            if verb and #points > 0 then
                table.insert(turnIn.deps, key)
                -- A party member's objective has no text of its own: "Kill X 3/10".
                local objText = obj.text or string.format("%s %s%s", verb, what or "",
                    obj.need and string.format(" %d/%d", obj.have or 0, obj.need) or "")
                if not skip(key) then
                    goals[#goals + 1] = {
                        key = key, points = points, known = known, title = title, level = quest.level,
                        weight = (elite or hard) and 1.6 or nil, elite = elite or nil, hard = hard or nil, helping = opts.who,
                        npcs = #targets > 0 and targets or nil, area = true, target = what,
                        kind = isDaily(quest) and "daily" or (verb == "Kill" and "kill") or (verb == "Collect" and "collect") or "use",
                        text = whose .. (elite and "[Elite] " or "") .. (title and (title .. ": ") or "") .. ns.ProgressText(objText),
                        details = (function()
                            local d = { "Quest: " .. (title or "?"), "Objective: " .. (ns.ProgressText(objText) or "?") }
                            if opts.who then d[#d + 1] = opts.who .. "'s quest: you're helping them (kill credit is shared in a party)." end
                            if elite then d[#d + 1] = "Elite: hard to solo at this level. Group up or come back stronger." end
                            if hard then d[#d + 1] = string.format("Level %d: 3 or more levels above you, so its mobs hit hard. Flow plans it after the easier ones; bring a friend or come back a level or two later.", quest.level) end
                            if verb == "Collect" and what then d[#d + 1] = "Drops from mobs/objects near the arrow: " .. what end
                            return d
                        end)(),
                    }
                end
            elseif verb then
                cant(string.format("objective %d (%s): Questie has no spot for %s", i, tostring(obj.text or "?"), tostring(what or "it")))
            elseif od then
                cant(string.format("objective %d (%s): a kind Flow can't place (%s)", i, tostring(obj.text or "?"), tostring(od.Type)))
            end
        end
    end
    -- An unfinished objective Flow can't locate (e.g. an event): don't plan
    -- the turn-in yet, it could come too early.
    local unfinished = 0
    for _, obj in ipairs(q.objectives) do if not obj.finished then unfinished = unfinished + 1 end end
    if unfinished > #turnIn.deps then
        if #turnIn.points > 0 then cant("waits for an objective Flow can't place, so the turn-in isn't planned yet") end
        turnIn.points = {}
    end
end
ns.quests.QuestGoals = questGoals   -- (Party.lua, tests)

ns:Register("navGoal", "questie", {
    collect = function()
        local db = ns.quests.QuestieDB and ns.quests.QuestieDB()
        if not db then return nil end
        local goals, unplaced = {}, {}
        for _, q in ipairs(questLog()) do questGoals(db, q, goals, { unplaced = unplaced }) end
        ns.quests.unplaced = unplaced   -- (/flow nav why)
        return goals
    end,
})

-- Spawn table -> map points (shared by pickups below).
local function spawnPoints(spawns)
    return (pointsFrom({ spawns }))
end

-- Quests you haven't picked up yet that are still worth doing (from the
-- missed-quests scan: zones you've quested in, doable, not done).
ns:Register("navGoal", "pickups", {
    collect = function()
        local list = ns.quests:Missed()
        if not list then return nil end
        -- Quest log full: picking up more is pointless.
        if ns.quests.FreeSlots and ns.quests:FreeSlots() == 0 then return nil end
        local level = UnitLevel("player")
        -- Levelling: only quests still worth the XP (down to 4 levels below you).
        -- Completionist mode: all of them, grey ones too.
        local floor = ns.nav:Mode() == "complete" and -math.huge or level - 4
        -- And not ones above you that are hard (orange or red, 3+ levels up):
        -- they come back as you level. (A level-5 tauren was offered level-8
        -- quests and found them very hard; a level-1 one was sent 700 yd for one.)
        local ceiling = level + ns.quests.HARD_ABOVE - 1
        local goals = {}
        for _, q in ipairs(list) do
            if (q.level or 0) >= floor and (q.level or 0) <= ceiling and q.starter and q.starter.spawns
                and not (ns.dungeons and ns.dungeons:Claims(q.id)) then
                goals[#goals + 1] = {
                    key = "pickup:" .. q.id, weight = 0.9, level = q.level,
                    npcs = q.starter.name and { q.starter.name } or nil,
                    kind = isDaily(q.raw) and "daily" or "accept",
                    points = spawnPoints(q.starter.spawns),
                    title = q.name,
                    text = "Accept: " .. (q.name or "quest"),
                    details = { string.format("Level %d quest from %s.", q.level or 0, q.starter.name or "?"),
                                "You haven't done it yet and it's still worth the XP." },
                }
            end
        end
        return goals
    end,
})

-- Errands: trainers to visit. Professions you planned but haven't learned,
-- professions that hit their cap, and your class trainer when there are
-- spells waiting. Locations from Places (learned spots + Questie).
ns:Register("navGoal", "errands", {
    collect = function()
        local goals = {}
        local _ = ns:ClassData()
        local wanted = {}
        local A = ns.api
        -- "Include professions" (map panel, /flow nav professions on|off).
        local includeProfs = ns.db.nav.professions ~= false

        for _, p in ipairs(includeProfs and ns:ProfessionPlan() or {}) do
            local rank, max = A.Skill(p.name)
            local why
            if not rank then why = "Learn " .. p.name
            elseif max > 0 and rank >= max and max < 300 then why = "Train the next " .. p.name .. " tier" end
            if why then
                for _, npc in ipairs(ns.places:TrainersFor(p.name)) do wanted[#wanted + 1] = npc end
                goals[#goals + 1] = { profession = p.name, optional = p.optional, why = why }
            end
        end
        if ns.quests.NPCsByName then ns.quests:NPCsByName(wanted) end  -- start lookup once

        local out = {}
        for _, g in ipairs(goals) do
            local points = {}
            local names = ns.places:TrainersFor(g.profession)
            for _, npc in ipairs(names) do
                for _, pt in ipairs(ns.places:Points(npc)) do points[#points + 1] = pt end
            end
            if #points > 0 then
                out[#out + 1] = {
                    key = "train:" .. g.profession, weight = g.optional and 1.4 or 1.0, optional = g.optional, points = points,
                    npcs = names,
                    title = g.why, text = g.why .. " (" .. table.concat(names, " / ") .. ")",
                    details = { g.why .. " at " .. table.concat(names, " or ") .. ".",
                                g.optional and "Optional, so the arrow only picks it when you're close by." or nil },
                }
            end
        end

        -- Skill-ups: gathering/fishing for planned professions that are behind
        -- your level. Optional stops, so the planner only routes you there
        -- when it's on the way (or nothing else is left).
        local level = UnitLevel("player")
        local here = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        local db = ns.quests.QuestieDB and ns.quests.QuestieDB()
        local toolAdded = {}
        for _, p in ipairs(includeProfs and ns:ProfessionPlan() or {}) do
            local rank, max = A.Skill(p.name)
            local target = ns.skillPlan and ns.skillPlan.Pace(p.name, level) or A.ProfessionTarget(level)
            if rank and rank + 10 < target and rank < max and not (ns.skillPlan and ns.skillPlan:Handles(p.name)) then
                for _, spot in ipairs(ns.places:SpotsFor(p.name)) do
                    local points = {}
                    for _, npc in ipairs(spot.npcs or {}) do
                        for _, pt in ipairs(ns.places:Points(npc)) do points[#points + 1] = pt end
                    end
                    for _, o in ipairs(spot.objects or {}) do
                        if db and rank >= o.skill then
                            local obj = ns.quests:QuestieGet("GetObject", o.id)
                            if obj then addSpawns(points, obj.spawns, 400, here) end
                        end
                    end
                    if #points > 0 then
                        -- No pole (pick, ...) yet: buying one comes first.
                        local tool, missing
                        if ns.skillPlan and ns.skillPlan.ToolGoal then tool, missing = ns.skillPlan:ToolGoal(p.name) end
                        if tool and not toolAdded[tool.key] then
                            toolAdded[tool.key] = true
                            tool.optional, tool.weight = true, 1.2
                            out[#out + 1] = tool
                        end
                        -- A lure too (Shiny Bauble), from the same kind of vendor.
                        local lure = ns.skillPlan and ns.skillPlan.LureGoal and ns.skillPlan:LureGoal(p.name)
                        if lure and not toolAdded[lure.key] then
                            toolAdded[lure.key] = true
                            out[#out + 1] = lure
                        end
                        local guide = ns:Get("profGuide", p.name)
                        local details = { string.format("%s is behind your level: %d now, about %d is right for level %d.",
                                p.name, rank, target, UnitLevel("player")),
                                "Optional: only planned when it's roughly on the way." }
                        if guide and guide.tip then details[#details + 1] = guide.tip end
                        out[#out + 1] = {
                            key = "skill:" .. p.name, prof = p.name, optional = true, weight = 1.5, points = points,
                            title = spot.text, text = string.format("%s (%s %d, aim for %d)", spot.text, p.name, rank, target),
                            details = details,
                            blockedBy = missing and ("needs a " .. missing) or nil,
                        }
                    end
                end
            end
        end

        -- Class trainer, when spells are waiting (appears by itself when you
        -- level up into new spells). The trainer you last used, else the
        -- known class trainers for your class (Places.lua data + Questie).
        -- Cost: what you can pay for, cheapest first. If you can't afford any
        -- of it, the goal carries `cost` and the route skips it until you can
        -- (Nav.lua remembers skipped stops and brings them back by itself).
        local waiting, costs, unknownCost = 0, {}, false
        local ok, items = pcall(ns:Get("advisor", "trainer").check)
        if ok and items then
            waiting = #items
            for _, it in ipairs(items) do
                if it.cost then costs[#costs + 1] = it.cost else unknownCost = true end
            end
        end
        table.sort(costs)
        local money = GetMoney and GetMoney() or 0
        local canPay, spend = 0, 0
        for _, c in ipairs(costs) do
            if spend + c <= money then canPay, spend = canPay + 1, spend + c end
        end
        local total = 0
        for _, c in ipairs(costs) do total = total + c end
        local coin = function(c) return GetCoinTextureString and GetCoinTextureString(c) or (c .. "c") end
        if waiting > 0 then
            local _, class = UnitClass("player")
            local names = ns.db.trainer and ns.db.trainer.npc and { ns.db.trainer.npc }
                or ns.places:TrainersFor("class:" .. class)
            if ns.quests.NPCsByName then ns.quests:NPCsByName(names) end
            local points = {}
            for _, n in ipairs(names) do
                for _, pt in ipairs(ns.places:Points(n)) do points[#points + 1] = pt end
            end
            if #points > 0 then
                local text = string.format("Train %d spell(s) at your class trainer", waiting)
                if not unknownCost and canPay < waiting and canPay > 0 then
                    text = string.format("Train %d of %d spell(s) at your class trainer (money for %d)", canPay, waiting, canPay)
                end
                out[#out + 1] = {
                    -- A milestone: new ranks make every fight after it faster, so it
                    -- always makes the route and costs half as much "distance" as a
                    -- quest stop. It still fits around the quests on the way there.
                    key = "train:class", weight = 0.5, milestone = true, points = points,
                    npcs = names,
                    title = "Class training",
                    text = text,
                    -- Nothing affordable (and every cost known): the cheapest is what it takes.
                    cost = (not unknownCost and canPay == 0 and #costs > 0) and costs[1] or nil,
                    details = { "New spells or ranks are waiting: " .. table.concat(names, " / ") .. ".",
                                #costs > 0 and ("Cost: " .. coin(total) .. (unknownCost and " plus spells Flow hasn't seen priced" or "")) or nil },
                }
            end
        end
        return out
    end,
})

-- Game's own waypoints (clients that have them), used when Questie isn't installed.
ns:Register("navGoal", "native", {
    collect = function()
        if ns.quests:Source() and ns.quests:Source().label == "Questie" then return nil end
        if not (C_QuestLog and C_QuestLog.GetNextWaypoint) then return nil end
        local goals = {}
        for _, q in ipairs(questLog()) do
            local ok, map, x, y = pcall(C_QuestLog.GetNextWaypoint, q.id)
            if ok and map and x and y then
                goals[#goals + 1] = {
                    key = q.id .. ":wp", title = q.title,
                    text = (q.complete and "Turn in: " or "") .. (q.title or "quest"),
                    points = { { map = map, x = x, y = y } },
                    details = { "Quest: " .. (q.title or "?") },
                }
            end
        end
        return goals
    end,
})
