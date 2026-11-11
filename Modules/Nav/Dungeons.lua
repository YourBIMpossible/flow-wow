-------------------------------------------------------------------------------
-- Dungeon runs: which dungeon quests you can do on *this* trip, how to get
-- them before you go, and whether the trip beats questing.
--
-- Flow never plans "a dungeon". It plans one run at a time: the dungeon's
-- quests you can do now, at your level, in one wing. Later parts of a chain,
-- quests above you and other wings are the next run, and show up only once
-- they're ready. That handles phased dungeons with no per-dungeon scripts.
--
-- Each quest gets one state (D.State):
--   ready      in your log
--   pickup     doable now, the giver is outside
--   unlock     earlier quests come first; they're doable now and short:
--              they go on the route as "unlocks <quest>"
--   inside     starts inside (an item that drops there, a giver inside)
--   followup   needs an earlier part of this dungeon's chain, but the giver
--              is at the entrance or inside: same run
--   nextrun    needs an earlier part turned in outside, or is above you
--   notforyou  class, race, reputation, profession, faction, or ruled out
--              by a quest you did (the reason is kept, said once)
--   toolong    the lead-in is more than 3 quests, or starts above you
--
-- Reads Questie (and QuestieDB) at runtime; without them it stays hidden.
-- Flow ships no quest data.
-------------------------------------------------------------------------------

local _, ns = ...
local D = {}
ns.dungeons = D

D.LEVEL_ABOVE = 2      -- quests up to 2 levels above you count for this run
D.FLOOR = 5            -- quests more than 5 levels below you aren't worth it
D.MAX_STEPS = 3        -- lead-in quests allowed before "too long"
D.LONG_STEPS = 6       -- ... with "Include long lead-ins" on
D.MIN_QUESTS = 3       -- a run worth suggesting has at least this many quests
D.THRESHOLD = 1.25     -- and beats your questing XP per hour by this much
D.RUN_MINUTES = 45     -- a run's length until Flow has timed yours
D.KILLS = 100          -- elites killed in a run (rough, any dungeon)
D.PARTY_SHARE = 0.26   -- your part of a kill's XP in a group of 5 (with the group bonus)
D.STOP_MINUTES = 2     -- each pickup: talk, read, accept
D.RUN_SPEED = 7        -- yards per second on foot (mounts only make it better)
D.BREADCRUMB_YARDS = 150 -- a breadcrumb is taken when its giver is this close to a stop you make anyway

-- Wings Questie keeps as their own areas (only Dire Maul files its creatures
-- under them; the others give a wing its own entrance).
D.WING = {
    [10008] = "Library", [10009] = "Armory", [10010] = "Cathedral",
    [10022] = "North", [10023] = "West", [10024] = "West", [10025] = "West",
    [10026] = "East", [10027] = "East",
}
-- Wings told apart by their bosses (Questie files every creature in these
-- under the one dungeon). A quest that targets a boss, or an item a boss
-- drops, is that boss's wing; any other creature goes to the wing whose
-- boss levels it fits. { name, title (the run's name), bosses = { npc ids } }
D.WINGS = {
    [796] = {   -- Scarlet Monastery
        { name = "Graveyard", bosses = { 3983, 4543, 6488, 6489, 6490 } },
        { name = "Library", bosses = { 3974, 6487 } },
        { name = "Armory", bosses = { 3975 } },
        { name = "Cathedral", bosses = { 4542, 3976, 3977 } },
    },
    [1583] = {  -- Blackrock Spire
        { name = "Lower", title = "Lower Blackrock Spire", bosses = { 9196, 9236, 9237, 10596, 10584, 9736,
            10220, 10268, 9568, 9596, 9718, 10376, 10509, 9219 } },
        { name = "Upper", title = "Upper Blackrock Spire", bosses = { 9816, 10264, 10899, 10429, 10339,
            10430, 10363, 16042 } },
    },
    [2017] = {  -- Stratholme
        { name = "Live", title = "Stratholme (Live)", bosses = { 10558, 10516, 10808, 11032, 10997, 10811,
            10813, 10393, 11143 } },
        { name = "Undead", title = "Stratholme (Undead)", bosses = { 10435, 10437, 10438, 10439, 10436,
            10440, 10809 } },
    },
}
-- Dire Maul's wings (and Stratholme's Gauntlet) are listed as dungeons of
-- their own: one dungeon.
local ALIAS = { [10022] = 2557, [10023] = 2557, [10024] = 2557, [10025] = 2557, [10026] = 2557, [10027] = 2557,
                [10001] = 2017 }
-- Battlegrounds Questie lists with the dungeons.
local SKIP = { [2597] = true, [3277] = true, [3358] = true }

local band = bit and bit.band

local function count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end

-------------------------------------------------------------------------------
-- Pure logic (tested in Tests.lua)
-------------------------------------------------------------------------------

-- The quests that must come first, traced back to what you can do now.
-- q: a Questie quest ({ Id, name, level, requiredLevel, preQuestGroup,
-- preQuestSingle, exclusiveTo }). ctx:
--   get(id) -> quest or nil;  done, log : { [id] = true }
--   eligible(q) -> ok, why;   dungeonOf(id) -> dungeon key or nil
--   atEntrance(q) -> true when its giver is at the entrance or inside
-- Returns the steps in the order you do them ({ id, name, level, minLevel,
-- inLog }), or nil, reason ("nextrun" | "followup" | "notforyou" | "toolong"), why.
function D.Trace(q, ctx)
    local myDungeon = ctx.dungeonOf and ctx.dungeonOf(q.Id)
    local trace
    local function need(id, node, depth, path)
        if ctx.done[id] then return {} end
        if path[id] then return nil, "toolong", "a chain that loops" end
        if myDungeon and ctx.dungeonOf(id) == myDungeon then
            -- An earlier part of this dungeon's own chain.
            if node == q and ctx.atEntrance and ctx.atEntrance(q) then return nil, "followup" end
            return nil, "nextrun", "after an earlier part"
        end
        if ctx.log[id] then return { { id = id, inLog = true } } end
        local p = ctx.get(id)
        if not p then return nil, "notforyou", "an earlier quest Flow can't find" end
        local ok, why = ctx.eligible(p)
        if not ok then return nil, "notforyou", why end
        for _, ex in ipairs(p.exclusiveTo or {}) do
            if ctx.done[ex] or ctx.log[ex] then return nil, "notforyou", "ruled out by a quest you did" end
        end
        path[id] = true
        local sub, r, w = trace(p, depth + 1, path)
        path[id] = nil
        if not sub then return nil, r, w end
        sub[#sub + 1] = { id = id, name = p.name, level = p.level, minLevel = p.requiredLevel }
        return sub
    end
    trace = function(node, depth, path)
        if depth > 8 then return nil, "toolong", "a very long chain" end
        local out = {}
        for _, id in ipairs(node.preQuestGroup or {}) do            -- all of them
            local s, r, w = need(id, node, depth, path)
            if not s then return nil, r, w end
            for _, st in ipairs(s) do out[#out + 1] = st end
        end
        local single = node.preQuestSingle or {}
        if #single > 0 then                                          -- one of them
            local best, firstR, firstW
            for _, id in ipairs(single) do
                if ctx.done[id] then best = {} break end
                local s, r, w = need(id, node, depth, path)
                if s and (not best or #s < #best) then best = s end
                if not s and not firstR then firstR, firstW = r, w end
            end
            if not best then return nil, firstR, firstW end
            for _, st in ipairs(best) do out[#out + 1] = st end
        end
        return out
    end
    local steps, r, w = trace(q, 0, { [q.Id or 0] = true })
    if not steps then return nil, r, w end
    local seen, out = {}, {}
    for _, st in ipairs(steps) do
        if not seen[st.id] then seen[st.id] = true; out[#out + 1] = st end
    end
    return out
end

-- One quest's state (see the top of the file). ctx as D.Trace, plus level,
-- maxSteps, inside(q) -> starts inside. Returns state, info: the reason
-- (notforyou, toolong, nextrun) or the lead-in steps (unlock).
function D.State(q, ctx)
    local id = q.Id
    if ctx.done[id] then return "done" end
    if ctx.log[id] then return "ready" end
    local ok, why = ctx.eligible(q)
    if not ok then return "notforyou", why end
    for _, ex in ipairs(q.exclusiveTo or {}) do
        if ctx.done[ex] or ctx.log[ex] then return "notforyou", "ruled out by a quest you did" end
    end
    if (q.requiredLevel or 0) > ctx.level then return "nextrun", "from level " .. q.requiredLevel end
    local steps, reason, why2 = D.Trace(q, ctx)
    if not steps then return reason, why2 end
    local todo = 0
    for _, st in ipairs(steps) do
        if not st.inLog then
            todo = todo + 1
            if (st.minLevel or 0) > ctx.level or (st.level or 0) > ctx.level + D.LEVEL_ABOVE then
                return "toolong", "a lead-in above your level"
            end
        end
    end
    if todo > (ctx.maxSteps or D.MAX_STEPS) then
        return "toolong", string.format("a long lead-in (%d quests)", todo)
    end
    if #steps > 0 then return "unlock", steps end
    if ctx.inside and ctx.inside(q) then return "inside" end
    return "pickup"
end

-- Cuts the quests into runs: one per dungeon wing, with the quests that fit
-- this trip. entries: { { id, name, level, dungeon, dungeonName, wing, state,
-- info, wingTitle (the run's name, optional) } }. Quests above level +
-- LEVEL_ABOVE are the next run; below floor they're ignored (unless they're
-- in your log). Returns the runs with at least one quest, most quests first:
--   { key, dungeon, wing, name, ready, pickups, inside, followups = { ids },
--     unlocks = { { id, steps } }, leadIns = { steps to pick up },
--     quests = { ids counted }, levels = { [id] = level }, next = n,
--     skipped = { [why] = n }, toolong = { { id, name, why } }, count = n }
function D.CutRuns(entries, level, floor)
    local runs, order = {}, {}
    for _, e in ipairs(entries) do
        local key = tostring(e.dungeon) .. ":" .. (e.wing or "")
        local run = runs[key]
        if not run then
            run = { key = key, dungeon = e.dungeon, wing = e.wing,
                    name = e.wingTitle or ((e.dungeonName or "?") .. (e.wing and (" " .. e.wing) or "")),
                    ready = {}, pickups = {}, inside = {}, followups = {}, unlocks = {}, leadIns = {}, breadcrumbs = {},
                    quests = {}, levels = {}, next = 0, skipped = {}, toolong = {}, count = 0 }
            runs[key] = run
            order[#order + 1] = run
        end
        local lv = e.level or 0
        local s = e.state
        if s == "done" then
            -- nothing
        elseif s == "notforyou" then
            local why = e.info or "not for you"
            run.skipped[why] = (run.skipped[why] or 0) + 1
        elseif s == "toolong" then
            run.toolong[#run.toolong + 1] = { id = e.id, name = e.name, why = e.info }
        elseif s == "nextrun" or lv > level + D.LEVEL_ABOVE then
            run.next = run.next + 1
        elseif s ~= "ready" and floor and lv < floor then
            -- grey: not worth it
        else
            local list = (s == "ready" and run.ready) or (s == "pickup" and run.pickups)
                or (s == "inside" and run.inside) or (s == "followup" and run.followups)
            if s == "unlock" then
                run.unlocks[#run.unlocks + 1] = { id = e.id, steps = e.info }
                for _, st in ipairs(e.info or {}) do
                    if not st.inLog then
                        local dup = false
                        for _, have in ipairs(run.leadIns) do if have.id == st.id then dup = true break end end
                        if not dup then st.unlocks = e.name; run.leadIns[#run.leadIns + 1] = st end
                    end
                end
            elseif list then
                list[#list + 1] = e.id
            end
            if list or s == "unlock" then
                run.quests[#run.quests + 1] = e.id
                run.levels[e.id] = lv
                run.count = run.count + 1
            end
        end
    end
    local out = {}
    for _, run in ipairs(order) do if run.count > 0 then out[#out + 1] = run end end
    table.sort(out, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.key < b.key
    end)
    return out
end

-- The dungeon a quest's objectives are in. tops: one entry per objective,
-- where its creatures / objects / item droppers are: a dungeon key, false
-- (somewhere outside, or more than one place) or nil (Questie doesn't say).
-- Every objective Questie places must be in the same dungeon; else nil.
function D.ObjectivesTop(tops)
    local top
    for i = 1, #tops do
        local t = tops[i]
        if t == false then return nil end
        if t ~= nil then
            if top and top ~= t then return nil end
            top = t
        end
    end
    return top
end

-- The wing a quest belongs to. objectives: { { creatures = { { id, level } } } }
-- (the creature to kill, or the ones that drop the item); wings: { { name,
-- bosses = { [id] = true }, lo, hi } } (boss levels). A boss is 2 votes for
-- its wing; any other creature 1 vote for the one wing whose levels it fits
-- (within 2). Most votes wins, a tie the later wing; no votes: the quest's
-- level. Returns the wing or nil.
function D.WingFor(objectives, wings, questLevel)
    if not (wings and #wings > 0) then return nil end
    local function byLevel(lv)
        local best, bd, tie = nil, math.huge, false
        for i, w in ipairs(wings) do
            local d = (lv < w.lo and w.lo - lv) or (lv > w.hi and lv - w.hi) or 0
            if d < bd then best, bd, tie = i, d, false elseif d == bd then tie = true end
        end
        if best and not tie and bd <= 2 then return best end
    end
    local votes = {}
    for _, o in ipairs(objectives or {}) do
        local hit, boss = {}, false
        for _, c in ipairs(o.creatures or {}) do
            for i, w in ipairs(wings) do
                if w.bosses[c.id] then hit[i], boss = 2, true end
            end
        end
        if not boss then
            for _, c in ipairs(o.creatures or {}) do
                local i = c.level and byLevel(c.level)
                if i then hit[i] = 1 end
            end
        end
        for i, v in pairs(hit) do votes[i] = (votes[i] or 0) + v end
    end
    local best, bv = nil, 0
    for i = 1, #wings do
        local v = votes[i] or 0
        if v > 0 and v >= bv then best, bv = i, v end
    end
    if not best and questLevel then best = byLevel(questLevel) end
    return best and wings[best] or nil
end

-- The breadcrumbs worth taking: those whose giver is within radius yards of
-- a stop you make anyway. cands: { { at = { cont, wx, wy }, ... } }.
function D.NearStops(cands, stops, radius)
    local out = {}
    for _, c in ipairs(cands or {}) do
        for _, s in ipairs(stops or {}) do
            if c.at and s.cont == c.at.cont then
                local dx, dy = s.wx - c.at.wx, s.wy - c.at.wy
                if dx * dx + dy * dy <= radius * radius then out[#out + 1] = c break end
            end
        end
    end
    return out
end

-- Minutes to gather the pickups on foot, nearest first, ending at the
-- entrance. from, stops, entrance: { cont, wx, wy } (world yards); another
-- continent counts as a long trip.
function D.GatherMinutes(from, stops, entrance)
    local function dist(a, b)
        if not (a and b) then return 0 end
        if a.cont ~= b.cont then return 1500 end
        local dx, dy = a.wx - b.wx, a.wy - b.wy
        return math.sqrt(dx * dx + dy * dy)
    end
    local left, at, yards = {}, from, 0
    for i, s in ipairs(stops or {}) do left[i] = s end
    while #left > 0 do
        local bi, bd = 1, math.huge
        for i, s in ipairs(left) do
            local d = dist(at, s)
            if d < bd then bi, bd = i, d end
        end
        yards = yards + bd
        at = table.remove(left, bi)
    end
    if entrance then yards = yards + dist(at, entrance) end
    return #(stops or {}) * D.STOP_MINUTES + yards / D.RUN_SPEED / 60
end

-- Is the run worth it? o = { level, rate (your XP per hour), runMinutes,
-- gatherMinutes, estimate(questLevel), share(questLevel, myLevel) }.
-- Returns { questXP, mobXP, minutes, perHour, ratio (nil without a rate) }.
function D.Worth(run, o)
    local questXP = 0
    local function add(lv)
        if lv and lv > 0 then questXP = questXP + o.estimate(lv) * o.share(lv, o.level) end
    end
    for _, id in ipairs(run.quests) do add(run.levels[id]) end
    for _, st in ipairs(run.leadIns) do add(st.level) end
    for _, st in ipairs(run.breadcrumbs or {}) do add(st.level) end
    local mobXP = D.KILLS * (o.level * 5 + 45) * 2 * D.PARTY_SHARE
    local minutes = (o.runMinutes or D.RUN_MINUTES) + (o.gatherMinutes or 0)
    local perHour = (questXP + mobXP) / minutes * 60
    return { questXP = questXP, mobXP = mobXP, minutes = minutes, perHour = perHour,
             ratio = (o.rate and o.rate > 0) and perHour / o.rate or nil }
end

-- Your questing XP per hour from samples ({ { t = seconds, xp = gained } },
-- oldest first): the last 2 hours, gaps over 10 minutes (a break, a trip
-- to the auction house) count as 10. Needs 15 minutes of play, else nil.
function D.RateFrom(samples, now)
    local from = now - 7200
    local xp, secs, last = 0, 0, nil
    for _, s in ipairs(samples or {}) do
        if s.t >= from and s.t <= now then
            if last then
                secs = secs + math.min(s.t - last, 600)
                xp = xp + (s.xp or 0)
            end
            last = s.t
        end
    end
    if secs < 900 then return nil end
    return xp / secs * 3600
end

-- Learns a dungeon's run time: a running average of your last 10 runs
-- (minutes). Runs under 5 or over 240 minutes (a peek inside, a night
-- away) don't count. rec: { avg, n } or nil.
function D.LearnTime(rec, minutes)
    if not minutes or minutes < 5 or minutes > 240 then return rec end
    if not rec or not rec.avg then return { avg = minutes, n = 1 } end
    local n = math.min((rec.n or 1) + 1, 10)
    return { avg = rec.avg + (minutes - rec.avg) / n, n = n }
end

-------------------------------------------------------------------------------
-- Questie
-------------------------------------------------------------------------------

local function module(name)
    if not QuestieLoader then return nil end
    local ok, m = pcall(QuestieLoader.ImportModule, QuestieLoader, name)
    return ok and m or nil
end

local function db() return ns.quests and ns.quests.QuestieDB and ns.quests.QuestieDB() end

function D:Available()
    local src = ns:Get("questSource", "questie")
    return src ~= nil and src.available() and module("ZoneDB") ~= nil
end

-- Dungeons: { [top area] = { key, name, areas = { [area] = true },
-- entrances = { { zone, x, y } }, wingEntrance = { [wing] = entrances },
-- ids = { quest ids }, minQ, maxQ } }; area -> top.
local dungeons, areaTop
local function buildDungeons()
    local zdb = module("ZoneDB")
    local ok, list = pcall(function() return zdb:GetDungeons() end)
    if not (ok and type(list) == "table") then return false end
    dungeons, areaTop = {}, {}
    local function top(area)
        local key = ALIAS[area] or area
        local d = dungeons[key]
        if not d then
            local entry = list[key] or {}
            local nameOk, name = pcall(function() return zdb:GetLocalizedDungeonName(key) end)
            d = { key = key, name = (nameOk and name) or entry[1] or ("Dungeon " .. key),
                  areas = { [key] = true }, entrances = entry[4] or {}, wingEntrance = {}, ids = {} }
            dungeons[key] = d
            areaTop[key] = key
        end
        return d
    end
    for area, entry in pairs(list) do
        if not SKIP[area] and type(entry) == "table" then
            local d = top(area)
            d.areas[area] = true
            areaTop[area] = d.key
            if D.WING[area] and entry[4] then d.wingEntrance[D.WING[area]] = entry[4] end
            for _, alt in ipairs(entry[2] or {}) do
                d.areas[alt] = true
                areaTop[alt] = d.key
            end
        end
    end
    return true
end

-- Where Questie places things: the dungeon (key), false (outside or more
-- than one place) or nil (nowhere). Cached; reads QuestieDB directly.
local function placer(qdb)
    local function q(fn, id, field)
        if not (fn and id) then return nil end
        local ok, v = pcall(fn, id, field)
        return ok and v or nil
    end
    local function topOf(spawns)
        if type(spawns) ~= "table" then return nil end
        local t
        for zone in pairs(spawns) do
            local z = areaTop[zone]
            if not z or (t and t ~= z) then return false end
            t = z
        end
        return t
    end
    local function merge(a, b)
        if a == false or b == false then return false end
        if a == nil then return b end
        if b == nil or a == b then return a end
        return false
    end
    local npcTop, objTop, itemTop = {}, {}, {}
    local P = {}
    function P.npc(id)
        if npcTop[id] == nil then
            local t = topOf(q(qdb.QueryNPCSingle, id, "spawns"))
            npcTop[id] = (t == nil) and "none" or t
        end
        local t = npcTop[id]
        if t == "none" then return nil end
        return t
    end
    function P.object(id)
        if objTop[id] == nil then
            local t = topOf(q(qdb.QueryObjectSingle, id, "spawns"))
            objTop[id] = (t == nil) and "none" or t
        end
        local t = objTop[id]
        if t == "none" then return nil end
        return t
    end
    function P.item(id)
        if itemTop[id] == nil then
            local t
            for _, n in ipairs(q(qdb.QueryItemSingle, id, "npcDrops") or {}) do t = merge(t, P.npc(n)) end
            for _, o in ipairs(q(qdb.QueryItemSingle, id, "objectDrops") or {}) do t = merge(t, P.object(o)) end
            itemTop[id] = (t == nil) and "none" or t
        end
        local t = itemTop[id]
        if t == "none" then return nil end
        return t
    end
    -- Raw objectives: { creatures, objects, items, reputation, kill credit }.
    function P.quest(obj)
        if type(obj) ~= "table" then return nil end
        local tops = {}
        for _, c in ipairs(obj[1] or {}) do tops[#tops + 1] = P.npc(c[1]) end
        for _, o in ipairs(obj[2] or {}) do tops[#tops + 1] = P.object(o[1]) end
        for _, it in ipairs(obj[3] or {}) do tops[#tops + 1] = P.item(it[1]) end
        for _, kc in ipairs(type(obj[5]) == "table" and obj[5] or {}) do
            local t
            for _, n in ipairs(kc[1] or {}) do t = merge(t, P.npc(n)) end
            tops[#tops + 1] = t
        end
        return D.ObjectivesTop(tops)
    end
    return P
end

-- Which quests belong to which dungeon: the quest's zone, else where all
-- its objectives are (a quest filed under the giver's zone). Built once, in
-- the background, a few hundred quests a frame.
local indexState = "none"   -- none | building | ready | failed
local dungeonOfId, wingOfZone = {}, {}
local function buildIndex()
    if indexState ~= "none" then return end
    local src = ns:Get("questSource", "questie")
    if not (src and src.available()) then return end
    if not buildDungeons() then indexState = "failed" return end
    indexState = "building"
    local qdb = db()
    local query = qdb and qdb.QueryQuestSingle
    local co = coroutine.create(function()
        local ids = src.allIds()
        local per = query and 300 or 40
        local place = query and placer(qdb)
        local work = 0
        for _, id in ipairs(ids) do
            local zone
            if query then
                local ok, z = pcall(query, id, "zoneOrSort")
                zone = ok and z or nil
            else
                local raw = ns.quests:QuestieGet("GetQuest", id)
                zone = raw and raw.zoneOrSort
            end
            local t = zone and zone > 0 and areaTop[zone]
            work = work + 1
            if not t and place then
                local ok, obj = pcall(query, id, "objectives")
                t = ok and place.quest(obj) or nil
                zone = nil
                work = work + 4
            end
            if t then
                local d = dungeons[t]
                d.ids[#d.ids + 1] = id
                dungeonOfId[id] = t
                wingOfZone[id] = D.WING[zone]
                local lv
                if query then
                    local ok, l = pcall(query, id, "questLevel")
                    lv = ok and l or nil
                end
                if lv and lv > 0 then
                    d.minQ = math.min(d.minQ or lv, lv)
                    d.maxQ = math.max(d.maxQ or lv, lv)
                end
            end
            if work >= per then work = 0; coroutine.yield() end
        end
    end)
    local function step()
        if InCombatLockdown() then C_Timer.After(1, step) return end
        local ok, err = coroutine.resume(co)
        if not ok then
            indexState = "failed"
            ns:Log("quests", "dungeon index failed: " .. tostring(err))
            return
        end
        if coroutine.status(co) == "dead" then
            indexState = "ready"
            D.dirty = true
        else
            C_Timer.After(0, step)
        end
    end
    step()
end

-------------------------------------------------------------------------------
-- Who can do what (the parts of a quest's requirements Questie knows)
-------------------------------------------------------------------------------

local PROFESSION = {
    [129] = "First Aid", [164] = "Blacksmithing", [165] = "Leatherworking", [171] = "Alchemy",
    [182] = "Herbalism", [185] = "Cooking", [186] = "Mining", [197] = "Tailoring",
    [202] = "Engineering", [333] = "Enchanting", [356] = "Fishing", [393] = "Skinning",
}

local npcCache = {}
local function npc(id)
    if not id then return nil end
    if npcCache[id] == nil then npcCache[id] = ns.quests:QuestieGet("GetNPC", id) or false end
    return npcCache[id] or nil
end

local function starterNPC(q) return q.Starts and q.Starts.NPC and npc(q.Starts.NPC[1]) end

function D.Eligible(q)
    if band then
        local _, _, raceID = UnitRace("player")
        local _, _, classID = UnitClass("player")
        if q.requiredRaces and q.requiredRaces ~= 0 and raceID
            and band(q.requiredRaces, 2 ^ (raceID - 1)) == 0 then return false, "for another race or faction" end
        if q.requiredClasses and q.requiredClasses ~= 0 and classID
            and band(q.requiredClasses, 2 ^ (classID - 1)) == 0 then return false, "for another class" end
    end
    if q.requiredMinRep or q.requiredMaxRep then
        local rep = module("QuestieReputation")
        if rep and rep.HasFactionAndReputationLevel then
            local ok, aboveMin, hasMin, belowMax, hasMax = pcall(rep.HasFactionAndReputationLevel, rep,
                q.requiredMinRep, q.requiredMaxRep)
            if ok and not (aboveMin and hasMin and belowMax and hasMax) then
                local fid = (q.requiredMinRep or q.requiredMaxRep)[1]
                local name = fid and GetFactionInfoByID and GetFactionInfoByID(fid)
                return false, "needs reputation" .. (name and (" with " .. name) or "")
            end
        end
    end
    if q.requiredSkill then
        local prof = module("QuestieProfessions")
        if prof and prof.HasProfessionAndSkillLevel then
            local ok, has, level = pcall(prof.HasProfessionAndSkillLevel, prof, q.requiredSkill)
            if ok and not (has and level) then
                local name = PROFESSION[q.requiredSkill[1]] or "a profession"
                return false, "needs " .. name .. ((q.requiredSkill[2] or 0) > 0 and (" " .. q.requiredSkill[2]) or "")
            end
        end
    end
    if q.requiredSpell and q.requiredSpell ~= 0 and IsSpellKnown then
        local known = IsSpellKnown(math.abs(q.requiredSpell))
        if q.requiredSpell > 0 and not known then return false, "needs a spell you don't have" end
        if q.requiredSpell < 0 and known then return false, "ruled out by a spell you know" end
    end
    local giver = starterNPC(q)
    local mine = UnitFactionGroup and UnitFactionGroup("player")
    local f = giver and giver.friendlyToFaction
    if f and ((mine == "Alliance" and f == "H") or (mine == "Horde" and f == "A")) then
        return false, "the other faction's quest"
    end
    return true
end

-- Where a quest's giver is: inside the dungeon, or at its entrance (within
-- a few yards of the doorway on the zone map).
local function giverInside(q, d)
    local g = starterNPC(q)
    if not (g and g.spawns) then return false end
    local any = false
    for zone in pairs(g.spawns) do
        if not d.areas[zone] then return false end
        any = true
    end
    return any
end

local function giverAtEntrance(q, d)
    if giverInside(q, d) then return true end
    local g = starterNPC(q)
    if not (g and g.spawns) then return false end
    for _, e in ipairs(d.entrances) do
        for _, c in ipairs(g.spawns[e[1]] or {}) do
            if math.abs(c[1] - e[2]) < 4 and math.abs(c[2] - e[3]) < 4 then return true end
        end
    end
    return false
end

local function startsInside(q, d)
    local s = q.Starts or {}
    if not (s.NPC and s.NPC[1]) and not (s.GameObject and s.GameObject[1]) and s.Item and s.Item[1] then
        return true   -- an item that drops in there
    end
    return giverInside(q, d)
end

-- A dungeon's boss-defined wings, each with the level band of its bosses
-- (built once per dungeon).
local wingCache = {}
local function wingsOf(d)
    if wingCache[d.key] ~= nil then return wingCache[d.key] or nil end
    local out = {}
    for _, def in ipairs(D.WINGS[d.key] or {}) do
        local w = { name = def.name, title = def.title, bosses = {} }
        for _, id in ipairs(def.bosses) do
            w.bosses[id] = true
            local n = npc(id)
            local lo = n and n.minLevel
            if lo and lo > 0 then
                local hi = n.maxLevel or lo
                w.lo = math.min(w.lo or lo, lo)
                w.hi = math.max(w.hi or hi, hi)
            end
        end
        if w.lo then out[#out + 1] = w end
    end
    wingCache[d.key] = #out >= 2 and out or false
    return wingCache[d.key] or nil
end

local function creature(id)
    local n = npc(id)
    local lo = n and n.minLevel
    return { id = id, level = (lo and lo > 0) and math.floor((lo + (n.maxLevel or lo)) / 2) or nil }
end

local function droppers(itemId)
    local qdb = db()
    if not (qdb and qdb.QueryItemSingle) then return {} end
    local ok, list = pcall(qdb.QueryItemSingle, itemId, "npcDrops")
    return (ok and type(list) == "table") and list or {}
end

-- The wing a quest belongs to: { name, title } or nil. Its zone (Dire Maul),
-- else its bosses and creature levels (D.WINGS), else where most of its
-- creatures are filed.
local function wingOf(id, q, d)
    if wingOfZone[id] then return { name = wingOfZone[id] } end
    local wings = wingsOf(d)
    if wings then
        local objectives = {}
        for _, o in ipairs(q.ObjectiveData or {}) do
            local cs = {}
            if o.Type == "monster" and o.Id then
                cs[1] = creature(o.Id)
            elseif o.Type == "killcredit" then
                for _, n in ipairs(o.IdList or {}) do cs[#cs + 1] = creature(n) end
            elseif o.Type == "item" and o.Id then
                for _, n in ipairs(droppers(o.Id)) do cs[#cs + 1] = creature(n) end
            end
            if #cs > 0 then objectives[#objectives + 1] = { creatures = cs } end
        end
        return D.WingFor(objectives, wings, q.level)
    end
    if count(d.wingEntrance) == 0 then return nil end
    local votes = {}
    for _, o in ipairs(q.ObjectiveData or {}) do
        local m = o.Type == "monster" and npc(o.Id)
        for zone in pairs(m and m.spawns or {}) do
            local w = D.WING[zone]
            if w then votes[w] = (votes[w] or 0) + 1 end
        end
    end
    local best, bn = nil, 0
    for w, n in pairs(votes) do if n > bn then best, bn = w, n end end
    return best and { name = best } or nil
end

-------------------------------------------------------------------------------
-- Runs (cached; recomputed when your log or level changes)
-------------------------------------------------------------------------------

D.dirty = true
local runs, lastCompute = nil, 0

local function charData(field)
    ns.db.nav[field] = ns.db.nav[field] or {}
    return ns.db.nav[field]
end
ns:PerCharacter("nav.dungeonRun")
ns:PerCharacter("nav.dungeonIn")
ns:PerCharacter("nav.dungeonTimes")
ns:PerCharacter("nav.xpSamples")
ns:PerCharacter("nav.dungeonLong")

function D:Suggest() return ns.db.nav.dungeonSuggest ~= false end
function D:LongLeadIns(top) return charData("dungeonLong")[top] == true end

local function areaPoint(zone, x, y)
    local map = ns.quests:UiMapForArea(zone)
    return map and { map = map, x = x / 100, y = y / 100 } or nil
end

local function starterPoints(q)
    local g = starterNPC(q)
    if not (g and g.spawns) then return {} end
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
    return (ns.quests.SpreadPoints({ g.spawns }, 6, { map = map })) or {}
end

local function world(p)
    if not (p and ns.nav and ns.nav.ToWorld) then return nil end
    local cont, wx, wy = ns.nav:ToWorld(p.map, p.x, p.y)
    return cont and { cont = cont, wx = wx, wy = wy } or nil
end

-- The run's entrance: the wing's own door, else the nearest of the dungeon's.
local function entranceOf(run, from)
    local d = dungeons[run.dungeon]
    local list = (run.wing and d.wingEntrance[run.wing]) or d.entrances
    local best, bd
    for _, e in ipairs(list or {}) do
        local p = areaPoint(e[1], e[2], e[3])
        local w = world(p)
        local dd = (from and w and from.cont == w.cont) and ((from.wx - w.wx) ^ 2 + (from.wy - w.wy) ^ 2) or math.huge
        if p and (not best or dd < bd) then best, bd = p, dd end
    end
    return best
end

local questCache = {}
local function quest(id)
    if questCache[id] == nil then questCache[id] = ns.quests:QuestieGet("GetQuest", id) or false end
    return questCache[id] or nil
end

function D.QuestingRate()
    local r = D.RateFrom(charData("xpSamples"), time())
    if r then return r, false end
    return ns.xpValue.Estimate(UnitLevel("player")) * 6, true
end

-- Breadcrumbs to the run's pickups and lead-ins you could take: not done,
-- none of the target's breadcrumbs in your log, your level, for you, and a
-- giver Flow can find. { { id, name, level, leadsTo, at = world point } }.
local function breadcrumbsFor(run, ctx)
    local out, seen = {}, {}
    local function open(bq)
        for _, p in ipairs(bq.preQuestGroup or {}) do if not ctx.done[p] then return false end end
        local single = bq.preQuestSingle or {}
        local any = #single == 0
        for _, p in ipairs(single) do if ctx.done[p] then any = true break end end
        for _, x in ipairs(bq.exclusiveTo or {}) do if ctx.done[x] or ctx.log[x] then return false end end
        return any
    end
    local function consider(targetId)
        local target = quest(targetId)
        local list = target and target.breadcrumbs
        local qdb = db()
        if list == nil and target and qdb and qdb.QueryQuestSingle then
            local ok, l = pcall(qdb.QueryQuestSingle, targetId, "breadcrumbs")
            list = ok and l or nil
        end
        if type(list) ~= "table" then return end
        for _, b in ipairs(list) do if ctx.log[b] then return end end
        for _, b in ipairs(list) do
            local bq = not seen[b] and not ctx.done[b] and quest(b)
            seen[b] = true
            if bq and (bq.requiredLevel or 0) <= ctx.level and open(bq) and D.Eligible(bq) then
                local at = world(starterPoints(bq)[1])
                if at then
                    out[#out + 1] = { id = b, name = bq.name, level = bq.level, leadsTo = target.name, at = at }
                end
            end
        end
    end
    for _, id in ipairs(run.pickups) do consider(id) end
    for _, st in ipairs(run.leadIns) do consider(st.id) end
    return out
end

local function compute()
    local level = UnitLevel("player")
    local Q = ns.quests
    questCache = {}
    local done = setmetatable({}, { __index = function(_, id) return Q:IsCompleted(id) end })
    local ctx = { get = quest, done = done, log = Q:LogIds(), level = level, eligible = D.Eligible,
                  dungeonOf = function(id) return dungeonOfId[id] end }
    local entries = {}
    for top, d in pairs(dungeons) do
        local relevant = #d.ids > 0 and (d.maxQ or 0) >= level - D.FLOOR and (d.minQ or 99) <= level + D.LEVEL_ABOVE
        if not relevant then
            for _, id in ipairs(d.ids) do if ctx.log[id] then relevant = true break end end
        end
        if relevant then
            ctx.maxSteps = D:LongLeadIns(top) and D.LONG_STEPS or D.MAX_STEPS
            ctx.inside = function(q) return startsInside(q, d) end
            ctx.atEntrance = function(q) return giverAtEntrance(q, d) end
            for _, id in ipairs(d.ids) do
                local q = quest(id)
                if q and (q.level or 0) > 0 then
                    local ok, st, info = pcall(D.State, q, ctx)
                    if ok then
                        local w = wingOf(id, q, d)
                        entries[#entries + 1] = { id = id, name = q.name, level = q.level, dungeon = top,
                            dungeonName = d.name, wing = w and w.name, wingTitle = w and w.title,
                            state = st, info = info }
                    end
                end
            end
        end
    end
    local out = D.CutRuns(entries, level, level - D.FLOOR)
    local rate, estimated = D.QuestingRate()
    local here = ns.nav and ns.nav:PlayerPos()
    local from = here and { cont = here.cont, wx = here.wx, wy = here.wy }
    local times = charData("dungeonTimes")
    for _, run in ipairs(out) do
        run.entrance = entranceOf(run, from)
        local stops = {}
        for _, id in ipairs(run.pickups) do
            local w = world(starterPoints(quest(id) or {})[1])
            if w then stops[#stops + 1] = w end
        end
        for _, st in ipairs(run.leadIns) do
            local w = world(starterPoints(quest(st.id) or {})[1])
            if w then stops[#stops + 1] = w end
        end
        run.breadcrumbs = D.NearStops(breadcrumbsFor(run, ctx), stops, D.BREADCRUMB_YARDS)
        for _, b in ipairs(run.breadcrumbs) do stops[#stops + 1] = b.at end
        run.gatherMinutes = from and D.GatherMinutes(from, stops, world(run.entrance)) or #stops * D.STOP_MINUTES
        local t = times[run.dungeon]
        run.runMinutes = (t and t.avg) or D.RUN_MINUTES
        run.worth = D.Worth(run, { level = level, rate = rate, runMinutes = run.runMinutes,
            gatherMinutes = run.gatherMinutes, estimate = ns.xpValue.Estimate, share = ns.xpValue.Share })
        run.estimatedRate = estimated
    end
    table.sort(out, function(a, b) return (a.worth.ratio or 0) > (b.worth.ratio or 0) end)
    return out
end

-- The runs at your level (best first), or nil while Questie's data is read.
function D:Runs()
    if not self:Available() then return nil end
    if indexState == "none" then buildIndex() end
    if indexState ~= "ready" then return nil end
    if (self.dirty or not runs) and not InCombatLockdown() and GetTime() - lastCompute > 3 then
        lastCompute = GetTime()
        local ok, r = pcall(compute)
        if ok then runs, self.dirty = r, false
        else ns:Log("quests", "dungeon runs failed: " .. tostring(r)) end
    end
    return runs
end

function D:Run(key)
    for _, run in ipairs(self:Runs() or {}) do if run.key == key then return run end end
end

-- The one run worth suggesting: at least MIN_QUESTS quests and THRESHOLD x
-- your questing rate. Only the best.
function D:Best()
    local best
    for _, run in ipairs(self:Runs() or {}) do
        local r = run.worth.ratio
        if run.count >= D.MIN_QUESTS and r and r >= D.THRESHOLD and (not best or r > best.worth.ratio) then best = run end
    end
    return best
end

function D:Prepared() return ns.db.nav.dungeonRun and ns.db.nav.dungeonRun.key end

function D:Prepare(key)
    local run = self:Run(key)
    if not run then return end
    ns.db.nav.dungeonRun = { key = key, dungeon = run.dungeon, name = run.name }
    local extra = {}
    if #run.leadIns > 0 then extra[#extra + 1] = string.format("%d unlock quests", #run.leadIns) end
    if #run.breadcrumbs > 0 then extra[#extra + 1] = string.format("%d on the way", #run.breadcrumbs) end
    ns:Print(string.format("%s: %d to pick up%s, then the entrance.", run.name,
        #run.pickups + #run.leadIns + #run.breadcrumbs,
        #extra > 0 and (" (" .. table.concat(extra, ", ") .. ")") or ""))
    if ns.nav and ns.nav.Collect then ns.nav:Collect() end
end

function D:Cancel()
    ns.db.nav.dungeonRun = {}
    if ns.nav and ns.nav.Collect then ns.nav:Collect() end
end

function D:GoToEntrance(key)
    local run = self:Run(key)
    if run and run.entrance then ns.waypoint:Set(run.entrance.map, run.entrance.x, run.entrance.y, run.name) end
end

-- The prepared run's pickups and lead-ins: the pickups provider leaves
-- these to us (so they're tagged with the dungeon and not listed twice).
local claimedFor, claimed = nil, {}
function D:Claims(id)
    local key = self:Prepared()
    if not key then return false end
    local run = self:Run(key)
    if run ~= claimedFor then
        claimedFor, claimed = run, {}
        for _, q in ipairs(run and run.pickups or {}) do claimed[q] = true end
        for _, st in ipairs(run and run.leadIns or {}) do claimed[st.id] = true end
        for _, b in ipairs(run and run.breadcrumbs or {}) do claimed[b.id] = true end
    end
    return claimed[id] == true
end

-------------------------------------------------------------------------------
-- Inside: the route shows only the dungeon's quests
-------------------------------------------------------------------------------

local function currentDungeon()
    if not (IsInInstance and dungeons) then return nil end
    local inside, kind = IsInInstance()
    if not inside or kind ~= "party" then return nil end
    local name = GetInstanceInfo and GetInstanceInfo()
    if not name then return nil end
    for key, d in pairs(dungeons) do
        if d.name == name then return key end
        for area in pairs(d.areas) do
            if C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(area) == name then return key end
        end
    end
end

local function questOf(key)
    return tonumber(key:match("^(%d+):") or key:match("^pickup:(%d+)$") or "")
end

function D:FilterInside(list)
    local here = currentDungeon()
    if not here then return list end
    local out = {}
    for _, g in ipairs(list) do
        local id = g.key and questOf(g.key)
        local k = g.key or ""
        if (id and dungeonOfId[id] == here) or k:find("^user:") or k:find("^help:") or g.kind == "party" then
            out[#out + 1] = g
        end
    end
    -- None of your quests here are filed under this dungeon: keep the route.
    for _, g in ipairs(out) do
        local id = g.key and questOf(g.key)
        if id then return out end
    end
    return list
end

-------------------------------------------------------------------------------
-- Route stops for a prepared run
-------------------------------------------------------------------------------

ns:Register("navGoal", "dungeon", {
    collect = function()
        local key = D:Prepared()
        if not key then return nil end
        local run = D:Run(key)
        if not run then return nil end
        local goals = {}
        local function pickup(id, why)
            local q = quest(id)
            if not q or ns.quests:InLog(id) then return end
            local pts = starterPoints(q)
            if #pts == 0 then return end
            local g = starterNPC(q)
            goals[#goals + 1] = {
                key = "pickup:" .. id, weight = 1.0, level = q.level,
                npcs = g and g.name and { g.name } or nil, kind = "accept", points = pts,
                title = q.name, text = "Accept: " .. (q.name or "quest") .. " (" .. why .. ")",
                details = { string.format("Level %d quest from %s.", q.level or 0, g and g.name or "?"),
                            "For your " .. run.name .. " run." },
            }
        end
        for _, id in ipairs(run.pickups) do pickup(id, "for " .. run.name) end
        for _, st in ipairs(run.leadIns) do pickup(st.id, "unlocks " .. (st.unlocks or "a dungeon quest")) end
        for _, b in ipairs(run.breadcrumbs or {}) do pickup(b.id, "leads to " .. (b.leadsTo or "a dungeon quest")) end
        -- The entrance, last; not while you're in there or just came out.
        local been = ns.db.nav.dungeonIn
        if #goals == 0 and run.entrance and not currentDungeon() and not (been and been.key == run.dungeon) then
            goals[1] = {
                key = "dungeon:" .. run.key, weight = 0.8, kind = "waypoint", points = { run.entrance },
                title = run.name, text = "Enter " .. run.name,
                details = { string.format("%d quests for this run.", run.count) },
            }
        end
        return goals
    end,
})

-------------------------------------------------------------------------------
-- In a group: the run's quests your party is missing
-------------------------------------------------------------------------------

-- { { id, names = { who lacks it } } } for run quests in your log.
function D:PartyMissing(run)
    local out = {}
    if not (run and ns.party and ns.party:InGroup() and ns.partyHelp and ns.partyHelp.All) then return out end
    local all = ns.partyHelp.All() or {}
    for _, id in ipairs(run.ready) do
        local names = {}
        for name, prog in pairs(all) do
            if type(prog) == "table" and prog[id] == nil then names[#names + 1] = name end
        end
        if #names > 0 then out[#out + 1] = { id = id, names = names } end
    end
    return out
end

function D:ShareMissing(run)
    if not (ns.questShare and ns.questShare.Queue) then return end
    for _, m in ipairs(self:PartyMissing(run)) do ns.questShare.Queue(m.id, false) end
end

-------------------------------------------------------------------------------
-- Words
-------------------------------------------------------------------------------

local function ratioText(run)
    return run.worth.ratio and string.format("%.1fx", run.worth.ratio) or "?"
end

function D.Summary(run, solo)
    local lines = {}
    lines[#lines + 1] = string.format("%s: about %s your questing XP per hour%s.", run.name, ratioText(run),
        run.estimatedRate and " (estimated)" or "")
    local parts = {}
    if #run.ready > 0 then parts[#parts + 1] = #run.ready .. " ready" end
    if #run.pickups > 0 then parts[#parts + 1] = #run.pickups .. " to pick up" end
    if #run.leadIns > 0 then parts[#parts + 1] = #run.leadIns .. " lead-in" .. (#run.leadIns > 1 and "s" or "") end
    local nb = #(run.breadcrumbs or {})
    if nb > 0 then parts[#parts + 1] = nb .. " breadcrumb" .. (nb > 1 and "s" or "") .. " on the way" end
    if #run.inside > 0 then parts[#parts + 1] = #run.inside .. " start inside" end
    if #run.followups > 0 then parts[#parts + 1] = #run.followups .. " follow-up" .. (#run.followups > 1 and "s" or "") end
    if #parts > 0 then lines[#lines + 1] = table.concat(parts, ", ") .. "." end
    if run.next > 0 then lines[#lines + 1] = run.next .. " more next run." end
    for why, n in pairs(run.skipped) do lines[#lines + 1] = string.format("Not for you (%d): %s.", n, why) end
    for _, t in ipairs(run.toolong) do lines[#lines + 1] = "Skipped " .. (t.name or "?") .. ": " .. (t.why or "long lead-in") .. "." end
    lines[#lines + 1] = string.format("About %d min (%d to gather).", math.floor(run.worth.minutes + 0.5),
        math.floor(run.gatherMinutes + 0.5))
    if solo then lines[#lines + 1] = "Needs a group." end
    return lines
end

-------------------------------------------------------------------------------
-- The arrow menu's "Dungeons" section
-------------------------------------------------------------------------------

local function runMenu(run)
    local prepared = D:Prepared() == run.key
    local items = { { title = true, text = run.name } }
    for _, line in ipairs(D.Summary(run, not ns.party:InGroup())) do
        items[#items + 1] = { text = "|cffaaaaaa" .. line .. "|r", disabled = true }
    end
    items[#items + 1] = { sep = true }
    if prepared then
        items[#items + 1] = { text = "Cancel this run", func = function() D:Cancel() end }
    else
        items[#items + 1] = { text = "Prepare this run", func = function() D:Prepare(run.key) end }
    end
    items[#items + 1] = { text = "Straight to the entrance", disabled = not run.entrance,
        func = function() D:GoToEntrance(run.key) end }
    local long = charData("dungeonLong")
    items[#items + 1] = { text = "Include long lead-ins", checked = long[run.dungeon] == true,
        func = function() long[run.dungeon] = not long[run.dungeon] or nil; D.dirty = true end }
    local missing = D:PartyMissing(run)
    if #missing > 0 then
        items[#items + 1] = { text = string.format("Share quests (%d)", #missing), func = function() D:ShareMissing(run) end }
    end
    ns.menu:Open(items)
end

function D:MenuItems()
    if not self:Available() then return {} end
    local items = { { sep = true }, { title = true, text = "Dungeons" } }
    local list = self:Runs()
    if not list then
        items[#items + 1] = { text = "|cffaaaaaaReading Questie's dungeons...|r", disabled = true }
    elseif #list == 0 then
        items[#items + 1] = { text = "|cffaaaaaaNo dungeon quests at your level|r", disabled = true }
    else
        local prepared = self:Prepared()
        for i, run in ipairs(list) do
            if i > 6 then break end
            items[#items + 1] = {
                text = string.format("%s: %d quest%s, %s", run.name, run.count, run.count > 1 and "s" or "", ratioText(run)),
                checked = prepared == run.key,
                func = function() C_Timer.After(0.05, function() runMenu(run) end) end,
            }
        end
    end
    items[#items + 1] = { text = "Suggest dungeons", checked = self:Suggest(),
        func = function() ns.db.nav.dungeonSuggest = not self:Suggest() end }
    return items
end

-------------------------------------------------------------------------------
-- Status icon above the Flow key (rendered where the status registry is)
-------------------------------------------------------------------------------

local statusCache, statusAt = nil, 0
ns:Register("status", "dungeon", {
    order = 40,
    get = function()
        if GetTime() - statusAt < 2 then return statusCache end
        statusAt = GetTime()
        statusCache = nil
        if not (D:Suggest() and D:Available()) or currentDungeon() then return nil end
        local run = D:Prepared() and D:Run(D:Prepared()) or D:Best()
        if not run then return nil end
        local solo = not ns.party:InGroup()
        local prepared = D:Prepared() == run.key
        statusCache = {
            icon = "Interface\\Icons\\INV_Misc_Key_04",
            text = ratioText(run),
            color = solo and { 0.7, 0.7, 0.7 } or { 0.4, 1, 0.4 },
            tip = table.concat(D.Summary(run, solo), "\n"),
            click = function() if prepared then D:Cancel() else D:Prepare(run.key) end end,
            clickText = prepared and "Cancel this run" or "Prepare this run",
        }
        return statusCache
    end,
})

-------------------------------------------------------------------------------
-- Events: XP rate, run times, staying current
-------------------------------------------------------------------------------

local lastXP, lastMax, lastLevel
local function onXP()
    local xp, max, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
    if lastXP and not (IsInInstance and IsInInstance()) then
        local gained = (level > lastLevel) and ((lastMax - lastXP) + xp) or (xp - lastXP)
        if gained > 0 then
            local s = charData("xpSamples")
            s[#s + 1] = { t = time(), xp = gained }
            while #s > 200 do table.remove(s, 1) end
        end
    end
    lastXP, lastMax, lastLevel = xp, max, level
end

-- Run timing: entering -> leaving. A death walk (out and back in within 10
-- minutes) is the same run.
local function onZone()
    local here = currentDungeon()
    local inn = ns.db.nav.dungeonIn
    if here then
        if inn and inn.key == here and inn.left and time() - inn.left < 600 then
            inn.left = nil
        elseif not (inn and inn.key == here and not inn.left) then
            ns.db.nav.dungeonIn = { key = here, t = time() }
        end
        D.dirty = true
        return
    end
    if inn and inn.key and not inn.left then inn.left = time() end
end

local function finishRun()
    local inn = ns.db.nav.dungeonIn
    if not (inn and inn.key and inn.left and time() - inn.left >= 600) then return end
    local times = charData("dungeonTimes")
    times[inn.key] = D.LearnTime(times[inn.key], (inn.left - inn.t) / 60)
    local run = ns.db.nav.dungeonRun
    if run and run.dungeon == inn.key then ns.db.nav.dungeonRun = {} end
    ns.db.nav.dungeonIn = {}
    D.dirty = true
end

local function dirty() D.dirty = true end
ns:On("PLAYER_XP_UPDATE", onXP)
ns:On("PLAYER_ENTERING_WORLD", function()
    onXP()
    C_Timer.After(5, function() buildIndex(); finishRun(); onZone() end)
end)
ns:On("ZONE_CHANGED_NEW_AREA", function() finishRun(); onZone() end)
ns:On("QUEST_LOG_UPDATE", dirty)
ns:On("QUEST_TURNED_IN", dirty)
ns:On("PLAYER_LEVEL_UP", dirty)
