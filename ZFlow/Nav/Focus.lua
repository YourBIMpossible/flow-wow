local _, ns = ...
-- Z-Flow custom route: the quest lines the player picked (parity rows
-- A1-44, A1-45, A1-47, A1-48, lead section 477). A line is what "Go here
-- next" on a quest step stands for: the quests before it not done yet, the
-- quest, and the quests Questie chains after it, in the order they are done.
--   A1-44  Add(quest): the quest's line joins the custom route (quest lines
--          only: a step with no quest adds nothing).
--   A1-45  RemoveFrom(quest): the line now ends before that quest (its
--          first quest: the line goes); RemoveLine(quest): the whole line.
--   A1-47  a line whose quests are all done (none in the log, each done)
--          leaves with "Custom route: <title> is done."; the last one to
--          leave adds "Custom route finished: back to your usual route."
--   A1-48  `<slash> focus` lists the lines; `<slash> focus clear` clears.
-- Saved per character at char F.PATH ({ { quest, stop, title } }).
-- Quest data is asked of the installed Questie at runtime, as
-- Nav/QuestRead.lua asks it (client.questieModule("QuestieDB"), GetQuest),
-- and what is done of client.questDone, as QuestRead's prerequisite read;
-- QuestRead itself is not changed. Questie missing: a line is its one quest.
-- Not here yet: the menu rows that call Add / RemoveFrom / RemoveLine and
-- the route walking only these lines (they need files outside this row's
-- list), and A1-46, the bar under the tracker (UI, waits for Muse).
-- Compared with Flow Modules/Nav/Focus.lua: F.Before, F.After, F.Line,
-- F.Cut, F.AddKey, F.RemoveFrom, F.RemoveLine, F.Filter's done lines,
-- F.DumpLines and `/flow focus [clear]`. Flow's class-spell line names
-- (teach) are left out: no class quest data here.
-- LOOK ONLY: nothing is accepted, handed in or abandoned. Not tested in game.
--
-- Pure:
--   F.Before(id, get, isDone) -> ids    quests to do before id, earliest first
--   F.After(id, get) -> ids             quests chained after id, in order
--   F.Line(id, get, isDone) -> ids, title
--   F.Cut(ids, stop) -> ids             the ids before stop (nil: all)
--   F.Lines(lines, idsOf, slash) -> the word's lines
--     get(id) -> Questie's quest table or nil; isDone(id) -> true when done
ns.Nav = ns.Nav or {}
local N = ns.Nav
local F = {}
N.Focus = F

F.NAME = "focus"
F.WORD = "focus"
F.HELP = "your custom route: the quest lines you picked; focus clear clears it"
F.PATH = "state.nav.focus"   -- char (where Import/FromFlow.lua puts Flow's nav.focus)
F.MAX_BACK = 12              -- Flow: F.MAX_BACK
F.MAX_AFTER = 20             -- Flow: F.MAX_AFTER
F.EVERY = 2                  -- seconds between looks for done lines (Flow's ticker)

F.ADDED = "Custom route: %s. Its steps are your route now."
F.DONE = "Custom route: %s is done."
F.FINISHED = "Custom route finished: back to your usual route."
F.HEADER = "custom route lines: %d"
F.LINE = "  %d. %s: quests %s"
F.CLEAR_HINT = "  %s focus clear"
F.CLEARED = "custom route cleared"
F.UNNAMED = "a quest line"

local function quest(get, id)
    local ok, q = pcall(get, id)
    if ok and type(q) == "table" then return q end
    return nil
end

local function list(v)
    return type(v) == "table" and v or {}
end

function F.Before(id, get, isDone, out, seen, depth)
    out, seen, depth = out or {}, seen or {}, depth or 0
    local q = quest(get, id)
    if not q or depth >= F.MAX_BACK then return out end
    local pres = {}
    for _, p in ipairs(list(q.preQuestGroup)) do
        if not isDone(p) then pres[#pres + 1] = p end
    end
    local single, any = list(q.preQuestSingle), false
    for _, p in ipairs(single) do if isDone(p) then any = true end end
    if not any and #single > 0 then pres[#pres + 1] = single[1] end
    for _, p in ipairs(pres) do
        if not seen[p] then
            seen[p] = true
            if quest(get, p) then
                F.Before(p, get, isDone, out, seen, depth + 1)
                out[#out + 1] = p
            end
        end
    end
    return out
end

function F.After(id, get)
    local out, seen, cur = {}, { [id] = true }, quest(get, id)
    for _ = 1, F.MAX_AFTER do
        local nextId = cur and tonumber(cur.nextQuestInChain)
        if not nextId or nextId == 0 or seen[nextId] then break end
        cur = quest(get, nextId)
        if not cur then break end
        seen[nextId] = true
        out[#out + 1] = nextId
    end
    return out
end

function F.Line(id, get, isDone)
    local ids, seen = {}, {}
    local function add(x) if not seen[x] then seen[x] = true; ids[#ids + 1] = x end end
    for _, p in ipairs(F.Before(id, get, isDone)) do add(p) end
    add(id)
    for _, n in ipairs(F.After(id, get)) do add(n) end
    local last = quest(get, ids[#ids]) or quest(get, id)
    local title = last and type(last.name) == "string" and last.name ~= "" and last.name or ("quest " .. tostring(id))
    return ids, title
end

function F.Cut(ids, stop)
    if stop == nil then return ids end
    local out = {}
    for _, x in ipairs(ids) do
        if x == stop then break end
        out[#out + 1] = x
    end
    return out
end

function F.Lines(lines, idsOf, slash)
    local out = { F.HEADER:format(#list(lines)) }
    for i, line in ipairs(list(lines)) do
        local ids, title = idsOf(line)
        local names = {}
        for j, x in ipairs(ids or {}) do names[j] = tostring(x) end
        out[#out + 1] = F.LINE:format(i, tostring(line.title or title or F.UNNAMED), table.concat(names, ", "))
    end
    out[#out + 1] = F.CLEAR_HINT:format(tostring(slash or "/zflow"))
    return out
end

function F.Declare(k, diag)
    local api = {}
    local ctx

    local function client() return ctx and ctx.client or k.client end
    local function store() return ctx and ctx.store or k.store end

    local function ask(name, ...)
        local c = client()
        if type(c) ~= "table" or type(c[name]) ~= "function" then return nil end
        local ok, v = pcall(c[name], ...)
        if ok then return v end
        return nil
    end

    local function tell(line)
        local c = client()
        if type(c) ~= "table" or type(c.print) ~= "function" then return end
        local id = k.id or ns.id
        c.print(id.title .. ": " .. tostring(line))
    end

    -- Questie's GetQuest (either call form, as QuestRead's), or nil.
    local function source()
        local db = ask("questieModule", "QuestieDB")
        if type(db) ~= "table" or type(db.GetQuest) ~= "function" then return nil end
        return function(id)
            local ok, v = pcall(db.GetQuest, id)
            if ok and v ~= nil then return v end
            ok, v = pcall(db.GetQuest, db, id)
            if ok then return v end
            return nil
        end
    end

    local function isDone(id) return ask("questDone", id) == true end

    local function saved()
        local s = store()
        if type(s) ~= "table" then return nil end
        local ok, v = pcall(s.get, s, "char", F.PATH)
        if ok and type(v) == "table" then return v end
        return nil
    end

    local function lines()
        local have = saved()
        if have then return have end
        local fresh = {}
        local s = store()
        if type(s) == "table" and s:set("char", F.PATH, fresh) then return saved() or fresh end
        return fresh
    end

    local function idsOf(line)
        if type(line) ~= "table" or line.quest == nil then return nil, nil end
        local get = source()
        if not get then return { line.quest }, line.title end
        local ids, title = F.Line(line.quest, get, isDone)
        return F.Cut(ids, line.stop), title
    end

    local function lineOf(id)
        for i, line in ipairs(saved() or {}) do
            for _, x in ipairs(idsOf(line) or {}) do
                if x == id then return i end
            end
        end
        return nil
    end

    function api.Add(id)
        id = tonumber(id)
        if not id then return nil end
        if lineOf(id) then return nil end
        local line = { quest = id }
        local _, title = idsOf(line)
        line.title = title
        local mine = lines()
        mine[#mine + 1] = line
        tell(F.ADDED:format(tostring(title or F.UNNAMED)))
        return title
    end

    function api.RemoveFrom(id)
        id = tonumber(id)
        local i = id and lineOf(id)
        if not i then return false end
        local mine = saved()
        local ids = idsOf(mine[i]) or {}
        if ids[1] == id then table.remove(mine, i) else mine[i].stop = id end
        return true
    end

    function api.RemoveLine(id)
        id = tonumber(id)
        local i = id and lineOf(id)
        if not i then return false end
        table.remove(saved(), i)
        return true
    end

    function api.Clear()
        local mine = saved()
        if not mine or #mine == 0 then return false end
        for i = #mine, 1, -1 do mine[i] = nil end
        return true
    end

    -- The quests of every line ({ [id] = true }), for the route reader.
    function api.Quests()
        local out = {}
        for _, line in ipairs(saved() or {}) do
            for _, x in ipairs(idsOf(line) or {}) do out[x] = true end
        end
        return out
    end

    function api.Lines()
        local id = k.id or ns.id
        return F.Lines(saved() or {}, idsOf, id and id.slash)
    end

    -- A1-47: lines whose quests are all done leave, each with a line.
    local function look()
        local mine = saved()
        if not mine or #mine == 0 or not source() then return end
        local inLog = {}
        for _, row in ipairs(N.QuestLogRows and N.QuestLogRows(client()) or {}) do inLog[row.id] = true end
        local any = false
        for i = #mine, 1, -1 do
            local ids, title = idsOf(mine[i])
            local left = false
            for _, x in ipairs(ids or {}) do
                if inLog[x] or not isDone(x) then left = true end
            end
            if ids and not left then
                tell(F.DONE:format(tostring(mine[i].title or title or F.UNNAMED)))
                table.remove(mine, i)
                any = true
            end
        end
        if any and #mine == 0 then tell(F.FINISHED) end
    end

    if diag and type(diag.commands) == "table" then
        diag.commands[F.WORD] = function(rest)
            if tostring(rest or ""):lower():match("^%s*(%S*)") == "clear" then
                api.Clear()
                tell(F.CLEARED)
                return
            end
            for _, line in ipairs(api.Lines()) do tell(line) end
        end
        if type(diag.help) == "table" then diag.help[F.WORD] = F.HELP end
    end

    k:Module({
        name = F.NAME,
        needs = { "client", "store" },
        provides = {
            Add = function(id) return api.Add(id) end,
            RemoveFrom = function(id) return api.RemoveFrom(id) end,
            RemoveLine = function(id) return api.RemoveLine(id) end,
            Clear = function() return api.Clear() end,
            Quests = function() return api.Quests() end,
            Lines = function() return api.Lines() end,
        },
        ticks = { { every = F.EVERY, when = "always", run = function() look() end } },
        start = function(c) ctx = c end,
        stop = function() ctx = nil end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.focus = F.Declare(ns, ns.diag)
