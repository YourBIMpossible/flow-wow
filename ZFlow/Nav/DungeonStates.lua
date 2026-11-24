-- The Dungeon Quests pane's data (lead section 303 item 6). Pure: plain
-- quest tables in the shape Questie gives them, nothing read from the
-- client, nothing remembered. The window draws what S.Pane returns and
-- computes nothing itself.
--
-- S.State and S.Trace are a port of legacy Flow's Modules/Nav/Dungeons.lua
-- (D.State, D.Trace), the same rules and the same eight states:
--   ready      in your log
--   pickup     doable now, the giver is outside
--   unlock     earlier quests come first; they are doable now and short
--   inside     starts inside (an item that drops there, a giver inside)
--   followup   needs an earlier part of this dungeon's chain, but the giver
--              is at the entrance or inside: same run
--   nextrun    needs an earlier part turned in outside, or is above you
--   notforyou  class, race, faction, or ruled out by a quest you did
--   toolong    the lead-in is more than S.MAX_STEPS quests, or above you
-- and "done" for a quest you have handed in (not listed).
--
-- No quest data lives here: the quests are Questie's, read at runtime by
-- Nav/DungeonRead.lua. No third-party table, no DungeonJournal data.
--
--   S.State(q, ctx) -> state, info      info: the reason, or the steps (unlock)
--     ctx = { level, done = { [id] = true }, log = { [id] = true },
--             get(id) -> quest, eligible(q) -> ok, why,
--             dungeonOf(id) -> key, atEntrance(q) -> bool, inside(q) -> bool,
--             maxSteps (optional) }
--   S.Eligible(q, me) -> true | false, why | nil, why (cannot tell: kept)
--     me = { raceId, classId, faction ("Horde" / "Alliance") }; any may be nil
--   S.GROUPS, S.GroupOf(state) -> group id or nil
--   S.ChainText(q, get) -> "Step 3 of 7" or nil
--   S.Pane(input) -> pane
--     input = { available (Questie there), dungeon = { key, name }, quests, ctx }
--     pane  = { title, why = { what is missing, how to get it } or nil,
--               groups = { { id, title, folded, rows } }, count, unplaced }
--     row   = { id, name, level, state, note, chain, next }
--   S.Order(dungeons) -> a new list: lowest quest level first, then name;
--     a dungeon with no level known last
local _, ns = ...

local S = {}
ns.DungeonStates = S

S.LEVEL_ABOVE = 2   -- lead-in quests up to 2 levels above you count
S.MAX_STEPS = 3     -- lead-in quests allowed before "too long"
S.DEPTH = 8         -- a chain deeper than this is too long
S.CHAIN_MAX = 30    -- the most quests the chain line walks either way

-- The class token as the game gives it (client.class) to the class number
-- Questie's requiredClasses bits use (bit n - 1 for class n).
S.CLASS_ID = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5,
    SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11,
}

-- -------------------------------------------------------------- states

local function list(v) return type(v) == "table" and v or {} end

-- Whether bit n (1-based) is set in mask, by arithmetic: no bit library.
local function hasBit(mask, n)
    return math.floor(mask / 2 ^ (n - 1)) % 2 == 1
end

function S.Eligible(q, me)
    me = type(me) == "table" and me or {}
    local unsure = nil
    local races, classes = tonumber(q.requiredRaces), tonumber(q.requiredClasses)
    if races and races ~= 0 then
        if type(me.raceId) ~= "number" then
            unsure = unsure or "your race is not known"
        elseif not hasBit(races, me.raceId) then
            return false, "for another race or faction"
        end
    end
    if classes and classes ~= 0 then
        if type(me.classId) ~= "number" then
            unsure = unsure or "your class is not known"
        elseif not hasBit(classes, me.classId) then
            return false, "for another class"
        end
    end
    local f = q.giverFaction
    if (me.faction == "Alliance" and f == "H") or (me.faction == "Horde" and f == "A") then
        return false, "the other faction's quest"
    end
    if q.requiredMinRep or q.requiredMaxRep then unsure = unsure or "your reputation is not checked" end
    if q.requiredSkill then unsure = unsure or "your professions are not checked" end
    if q.requiredSpell and q.requiredSpell ~= 0 then unsure = unsure or "your spells are not checked" end
    if unsure then return nil, unsure end
    return true
end

-- The quests that must come first, traced back to what you can do now:
-- the steps in the order you do them ({ id, name, level, minLevel, inLog }),
-- or nil, reason ("nextrun" | "followup" | "notforyou" | "toolong"), why.
function S.Trace(q, ctx)
    local myDungeon = ctx.dungeonOf and ctx.dungeonOf(q.Id)
    local trace
    local function need(id, node, depth, path)
        if ctx.done[id] then return {} end
        if path[id] then return nil, "toolong", "a chain that loops" end
        if myDungeon and ctx.dungeonOf(id) == myDungeon then
            if node == q and ctx.atEntrance and ctx.atEntrance(q) then return nil, "followup" end
            return nil, "nextrun", "after an earlier part"
        end
        if ctx.log[id] then return { { id = id, inLog = true } } end
        local p = ctx.get(id)
        if not p then return nil, "notforyou", "an earlier quest not in the quest data" end
        local ok, why = ctx.eligible(p)
        if ok == false then return nil, "notforyou", why end
        for _, ex in ipairs(list(p.exclusiveTo)) do
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
        if depth > S.DEPTH then return nil, "toolong", "a very long chain" end
        local out = {}
        for _, id in ipairs(list(node.preQuestGroup)) do
            local s, r, w = need(id, node, depth, path)
            if not s then return nil, r, w end
            for _, st in ipairs(s) do out[#out + 1] = st end
        end
        local single = list(node.preQuestSingle)
        if #single > 0 then
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
        if not seen[st.id] then
            seen[st.id] = true
            out[#out + 1] = st
        end
    end
    return out
end

function S.State(q, ctx)
    local id = q.Id
    if ctx.done[id] then return "done" end
    if ctx.log[id] then return "ready" end
    local ok, why = ctx.eligible(q)
    if ok == false then return "notforyou", why end
    for _, ex in ipairs(list(q.exclusiveTo)) do
        if ctx.done[ex] or ctx.log[ex] then return "notforyou", "ruled out by a quest you did" end
    end
    if (q.requiredLevel or 0) > ctx.level then return "nextrun", "from level " .. q.requiredLevel end
    local steps, reason, why2 = S.Trace(q, ctx)
    if not steps then return reason, why2 end
    local todo = 0
    for _, st in ipairs(steps) do
        if not st.inLog then
            todo = todo + 1
            if (st.minLevel or 0) > ctx.level or (st.level or 0) > ctx.level + S.LEVEL_ABOVE then
                return "toolong", "a lead-in above your level"
            end
        end
    end
    if todo > (ctx.maxSteps or S.MAX_STEPS) then
        return "toolong", string.format("a long lead-in (%d quests)", todo)
    end
    if #steps > 0 then return "unlock", steps end
    if ctx.inside and ctx.inside(q) then return "inside" end
    return "pickup"
end

-- -------------------------------------------------------------- the pane

S.GROUPS = {
    { id = "log", title = "In your log" },
    { id = "pickup", title = "Pick up before you go" },
    { id = "inside", title = "Inside" },
    { id = "later", title = "Later" },
    { id = "notforyou", title = "Not for you", folded = true },
}

local GROUP_OF = {
    ready = "log", pickup = "pickup", unlock = "pickup", inside = "inside", followup = "inside",
    nextrun = "later", toolong = "later", notforyou = "notforyou",
}

function S.GroupOf(state) return GROUP_OF[state] end

-- What the player does next with a quest in each state, said under its row
-- (row.next). A quest not for you has nothing to do.
S.NEXT = {
    ready = "Do it on this run.",
    pickup = "Pick it up before you go in.",
    unlock = "Do the quests named first, then pick this one up.",
    inside = "You pick it up inside, during the run.",
    followup = "It opens during the run; pick it up there.",
    nextrun = "Come back for it on a later run.",
    toolong = "Its lead-in is long; leave it for a later run.",
}

-- What the pane says instead of rows: what is missing, then how to get it.
S.WHY = {
    noQuestie = { "Dungeon quests need Questie.",
        "Install or enable the Questie add-on and the quests will appear here." },
    noDungeon = { "No dungeon picked.", "Pick a dungeon on the left." },
    noQuests = { "No quests known for this dungeon.",
        "Questie lists no quest here for this character." },
    unplaced = { "These quests could not be sorted.",
        "Type the slash command with diag to see what went wrong." },
}

-- The quest before q: its single lead-in, else the first of its group.
local function before(q)
    local single, group = list(q.preQuestSingle), list(q.preQuestGroup)
    return single[1] or group[1]
end

function S.ChainText(q, get)
    if type(q) ~= "table" or type(get) ~= "function" then return nil end
    local seen = { [q.Id or 0] = true }
    local back, at = 0, q
    while back < S.CHAIN_MAX do
        local id = before(at)
        if id == nil or seen[id] then break end
        seen[id] = true
        back = back + 1
        local p = get(id)
        if type(p) ~= "table" then break end
        at = p
    end
    local ahead
    ahead, at = 0, q
    while ahead < S.CHAIN_MAX do
        local id = at.nextQuestInChain
        if type(id) ~= "number" or id == 0 or seen[id] then break end
        seen[id] = true
        ahead = ahead + 1
        local p = get(id)
        if type(p) ~= "table" then break end
        at = p
    end
    local total = back + 1 + ahead
    if total < 2 then return nil end
    return string.format("Step %d of %d", back + 1, total)
end

-- The note under a row: when a level-locked quest opens, what comes first,
-- or why it is not for you or later.
local function noteOf(q, state, info, level)
    if state == "nextrun" and (q.requiredLevel or 0) > level then
        return "Available at Level " .. q.requiredLevel
    end
    if state == "unlock" and type(info) == "table" then
        local names = {}
        for _, st in ipairs(info) do
            if not st.inLog then names[#names + 1] = tostring(st.name or ("quest " .. tostring(st.id))) end
        end
        if #names > 0 then return "First: " .. table.concat(names, ", ") end
        return nil
    end
    if type(info) == "string" then return info end
    return nil
end

local function byLevel(a, b)
    local la, lb = a.level or 0, b.level or 0
    if la ~= lb then return la < lb end
    return tostring(a.name) < tostring(b.name)
end

local function empty(why, title)
    return { title = title, why = why, groups = {}, count = 0, unplaced = 0 }
end

function S.Pane(input)
    input = type(input) == "table" and input or {}
    if input.available ~= true then return empty(S.WHY.noQuestie) end
    local d = input.dungeon
    if type(d) ~= "table" then return empty(S.WHY.noDungeon) end
    local title = tostring(d.name or "")
    local ctx = input.ctx
    local pane = { title = title, groups = {}, count = 0, unplaced = 0 }
    local at = {}
    for i, g in ipairs(S.GROUPS) do
        pane.groups[i] = { id = g.id, title = g.title, folded = g.folded == true, rows = {} }
        at[g.id] = pane.groups[i]
    end
    for _, q in ipairs(list(input.quests)) do
        local ok, state, info = false, nil, nil
        if type(q) == "table" and type(ctx) == "table" then ok, state, info = pcall(S.State, q, ctx) end
        local gid = ok and GROUP_OF[state] or nil
        if not ok then
            pane.unplaced = pane.unplaced + 1
        elseif gid then
            local getter = ctx.get
            local okC, chain = pcall(S.ChainText, q, getter)
            local rows = at[gid].rows
            rows[#rows + 1] = {
                id = q.Id, name = tostring(q.name or ("Quest " .. tostring(q.Id))), level = q.level,
                state = state, note = noteOf(q, state, info, ctx.level or 0), chain = okC and chain or nil,
                next = S.NEXT[state],
            }
            pane.count = pane.count + 1
        end
    end
    for _, g in ipairs(pane.groups) do table.sort(g.rows, byLevel) end
    if pane.count == 0 then pane.why = pane.unplaced > 0 and S.WHY.unplaced or S.WHY.noQuests end
    return pane
end

-- The one place every objective of a quest shares (lead section 305, a port
-- of legacy D.ObjectivesTop): tops holds, per objective, a dungeon key, nil
-- (placed nowhere) or false (more than one place). nil when there is no
-- one place.
function S.ObjectivesTop(tops)
    local top
    for i = 1, #(type(tops) == "table" and tops or {}) do
        local t = tops[i]
        if t == false then return nil end
        if t ~= nil then
            if top and top ~= t then return nil end
            top = t
        end
    end
    return top
end

function S.Order(dungeons)
    local out = {}
    for _, d in ipairs(list(dungeons)) do
        if type(d) == "table" then out[#out + 1] = d end
    end
    table.sort(out, function(a, b)
        local la, lb = tonumber(a.minQ), tonumber(b.minQ)
        if la and lb and la ~= lb then return la < lb end
        if la and not lb then return true end
        if lb and not la then return false end
        return tostring(a.name) < tostring(b.name)
    end)
    return out
end

-- Lead DISPATCH 343: the words the Dungeon Quests window shows for a
-- dungeon, worked out here so the window computes nothing.
--   S.LevelText(d) -> "Levels 18-22" | "Level 27" | nil   from d.minQ, d.maxQ
--   S.ListText(d)  -> "The Deadmines (18-22)", or the name alone
--   S.CountText(n) -> "1 quest" | "n quests" | "No quests"
local function range(d)
    if type(d) ~= "table" then return nil, nil end
    local lo, hi = tonumber(d.minQ), tonumber(d.maxQ)
    if not lo then return nil, nil end
    return lo, hi or lo
end

function S.LevelText(d)
    local lo, hi = range(d)
    if not lo then return nil end
    if lo == hi then return "Level " .. lo end
    return "Levels " .. lo .. "-" .. hi
end

function S.ListText(d)
    local name = tostring(type(d) == "table" and d.name or "")
    local lo, hi = range(d)
    if not lo then return name end
    if lo == hi then return name .. " (" .. lo .. ")" end
    return name .. " (" .. lo .. "-" .. hi .. ")"
end

function S.CountText(n)
    n = tonumber(n) or 0
    if n <= 0 then return "No quests" end
    if n == 1 then return "1 quest" end
    return n .. " quests"
end
