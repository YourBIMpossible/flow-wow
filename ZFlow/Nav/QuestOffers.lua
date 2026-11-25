local _, ns = ...

-- QuestOffers (C-new-1): which quests a quest giver showed you are NOT on
-- offer, so the route stops sending you to pick them up. Questie says who
-- starts a quest; only the giver's own window says whether they offer it
-- to you now (an event, a hidden prerequisite, a quest the server changed).
-- One talk is enough: when the giver's list is on screen and a quest Questie
-- says they start is not on it, that quest is dropped for ten minutes; a
-- second talk without it drops it for a day. Seen on offer again, it comes
-- back at once.
--
-- Nothing is authored here: the giver and their quests come from Questie at
-- runtime, what is on offer from the window the game shows.
--
-- Saved per character, char "learned.facts.notOffered"[questId] =
--   { at = client.clock(), npc = name }
-- (the place the import from Flow puts Flow's own list; its entries,
-- { firstAt, hiddenAt }, are read too).
--
-- Not judged: a window with no list of the giver's quests (nothing to
-- conclude), the seconds after you accept or hand in a quest (the list is
-- changing), quests done or in your log. When Questie could not be asked
-- (not loaded yet), the talk is kept and tried again a few times.
--
--   QO.Note(list, id, onOffer, now, npc) -> "pause" | "day" | "back" | nil
--     (pure; an entry is { firstAt, hiddenAt, npc }, Flow's own shape)
--   QO.Dropped(list, id, now) -> bool                                   (pure)
--   QO.Declare(k, diag) -> api
--     api.dropped(id)  true while the quest is dropped
--     api.clear()      empties the list, returns how many there were
--     api.waiting()    talks waiting to be tried again
--   the word: <slash> offers [clear]
--
-- CLIENT NEED: client.offeredQuests() -> { ids = { [id] = true },
-- titles = { [title] = true } } for the giver's window that is open, or nil
-- when it shows no list of their quests. Real reads (warcraft.wiki.gg):
-- C_GossipInfo.GetAvailableQuests() at GOSSIP_SHOW, GetNumAvailableQuests()
-- and GetAvailableTitle(i) at QUEST_GREETING; a list with only quests to
-- hand in still counts (nothing new on offer).
-- Not tested in game.
local QO = {}
ns.QuestOffers = QO

QO.NAME = "questOffers"
QO.PATH = "learned.facts.notOffered"
QO.WORD = "offers"
QO.EVENTS = { "GOSSIP_SHOW", "QUEST_GREETING" }
-- Lead section 806 (section 563): as Flow's Q.NoteOffer and Q:Offered
-- (Modules/Quests/QuestData.lua:342-344, :362-373, :421-430 at origin/local
-- 4ce93c83). One talk without the quest drops it for QO.PAUSE; a talk
-- without it again, at least QO.GAP after the first, drops it for QO.HIDE.
QO.PAUSE = 600    -- seconds a quest stays dropped after one talk without it
QO.GAP = 60       -- the second talk must be at least this long after the first
QO.HIDE = 86400   -- seconds a quest stays dropped once a second talk agrees
QO.QUIET = 5      -- seconds after an accept or hand-in when the list is changing
QO.RETRY = 10     -- seconds between tries of a talk Questie could not judge
QO.TRIES = 3      -- tries before such a talk is given up

QO.HELP = "list the quests left off your route because their giver didn't have them for you; \"clear\" puts them back"
QO.NONE = "no quests are left off your route for that."
QO.HEAD = "%d quest(s) left off your route because their giver didn't have them for you:"
QO.LINE = "  %s (%d), at %s"
QO.TAIL = "Type %s %s clear to put them back."
QO.CLEARED = "put %d quest(s) back on your route."
QO.UNKNOWN = "a quest giver"

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- (Entries are Flow's shape, so the list the import brings over reads as
-- it is: firstAt, the first talk without the quest; hiddenAt, the talk that
-- dropped it for a day.)
function QO.Dropped(list, id, now)
    if type(list) ~= "table" or not finite(now) then return false end
    local e = list[id]
    if type(e) ~= "table" then return false end
    if finite(e.hiddenAt) and now - e.hiddenAt < QO.HIDE then return true end
    if finite(e.firstAt) and now - e.firstAt < QO.PAUSE then return true end
    return false
end

-- The quests dropped now, as quest numbers in order: what the word lists
-- and what clear counts (one helper, so the two always agree; a key that
-- is no quest number is neither listed nor counted).
function QO.Listed(list, now)
    local ids = {}
    if type(list) ~= "table" then return ids end
    for id in pairs(list) do
        if type(id) == "number" and QO.Dropped(list, id, now) then ids[#ids + 1] = id end
    end
    table.sort(ids)
    return ids
end

function QO.Note(list, id, onOffer, now, npc)
    if type(list) ~= "table" then return nil end
    if onOffer then
        if list[id] == nil then return nil end
        list[id] = nil
        return "back"
    end
    if not finite(now) then return nil end
    local e = list[id]
    if type(e) ~= "table" or not finite(e.firstAt) then
        list[id] = { firstAt = now, npc = npc }
        return "pause"
    end
    if finite(e.hiddenAt) and now - e.hiddenAt < QO.HIDE then return nil end
    if now - e.firstAt >= QO.GAP then
        e.hiddenAt = now
        if npc ~= nil then e.npc = npc end
        return "day"
    end
    return nil
end

local function tableOr(v)
    if type(v) == "table" then return v end
    return {}
end

local function textOr(v, fallback)
    if type(v) == "string" and v ~= "" then return v end
    return fallback
end

local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if not ok then return nil end
    return v
end

-- The npc id inside a creature GUID ("Creature-0-server-instance-zone-npcId-spawn").
local function npcIdOf(guid)
    if type(guid) ~= "string" then return nil end
    return tonumber(guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)"))
end

-- Questie's giver: { name, questStarts } or nil, and whether Questie could
-- be asked at all (false: try again later).
local function giver(client, npcId)
    local db = ask(client, "questieModule", "QuestieDB")
    if type(db) ~= "table" or type(db.GetNPC) ~= "function" then return nil, false end
    local ok, npc = pcall(db.GetNPC, npcId)
    if not ok then return nil, false end
    if type(npc) ~= "table" or type(npc.questStarts) ~= "table" then return nil, true end
    return npc, true
end

local function questName(client, id)
    local db = ask(client, "questieModule", "QuestieDB")
    if type(db) ~= "table" or type(db.GetQuest) ~= "function" then return nil end
    local ok, q = pcall(db.GetQuest, id)
    if ok and type(q) == "table" and type(q.name) == "string" then return q.name end
    return nil
end

local function inLog(client)
    local set = {}
    local rows = ask(client, "questLog")
    if type(rows) == "table" then
        for _, r in ipairs(rows) do
            if type(r) == "table" and r.id then set[r.id] = true end
        end
    end
    return set
end

function QO.Declare(k, diag)
    local api = {}
    local ctx
    local changedAt
    local waiting = {}

    local function list()
        if not ctx then return {} end
        local v = ctx.store:get("char", QO.PATH)
        if type(v) == "table" then return v end
        return {}
    end

    local function now()
        if not ctx then return nil end
        local t = ask(ctx.client, "clock")
        if finite(t) then return t end
        return nil
    end

    function api.dropped(id)
        return QO.Dropped(list(), id, now())
    end

    -- Empties the whole list (a pause that has run out too) and returns how
    -- many quests were dropped right now: the ones the word lists.
    function api.clear()
        local l = list()
        local n = #QO.Listed(l, now())
        if ctx and next(l) ~= nil then ctx.store:set("char", QO.PATH, {}) end
        return n
    end

    function api.waiting() return #waiting end

    -- One talk judged: true when done (judged or nothing to judge), false
    -- when Questie could not be asked.
    local function judge(talk)
        local client = ctx.client
        local npc, asked = giver(client, talk.npcId)
        if not asked then return false end
        if not npc then return true end
        local l = list()
        local log = inLog(client)
        local changed = false
        for _, id in ipairs(npc.questStarts) do
            if ask(client, "questDone", id) ~= true and not log[id] then
                local name = questName(client, id)
                local on = talk.offered.ids[id] == true
                if name and talk.offered.titles[name] == true then on = true end
                if QO.Note(l, id, on, talk.at, talk.who or npc.name) then changed = true end
            end
        end
        if changed then ctx.store:set("char", QO.PATH, l) end
        return true
    end

    local retry
    local function schedule()
        if retry or #waiting == 0 then return end
        retry = ctx.sched:after(QO.NAME, QO.RETRY, function()
            retry = nil
            local still = {}
            for _, talk in ipairs(waiting) do
                talk.tries = talk.tries + 1
                if not judge(talk) and talk.tries < QO.TRIES then still[#still + 1] = talk end
            end
            waiting = still
            schedule()
        end)
    end

    local function seen()
        local client = ctx.client
        local t = ask(client, "now")
        if changedAt and finite(t) and t - changedAt < QO.QUIET then return end
        local who = ask(client, "serviceNpc")
        if type(who) ~= "table" then return end
        local npcId = npcIdOf(who.guid)
        if not npcId then return end
        local offered = ask(client, "offeredQuests")
        if type(offered) ~= "table" then return end
        local at = now()
        if not at then return end
        local talk = {
            npcId = npcId, who = textOr(who.name, nil), at = at, tries = 0,
            offered = { ids = tableOr(offered.ids), titles = tableOr(offered.titles) },
        }
        if not judge(talk) then
            waiting[#waiting + 1] = talk
            schedule()
        end
    end

    local function say(line) k.client.print(k.id.title .. ": " .. line) end

    local function run(arg)
        local word = tostring(arg or ""):lower():match("^%s*(%S*)")
        if word == "clear" then
            say(string.format(QO.CLEARED, api.clear()))
            return
        end
        local l = list()
        local ids = QO.Listed(l, now())
        if #ids == 0 then say(QO.NONE) return end
        say(string.format(QO.HEAD, #ids))
        for _, id in ipairs(ids) do
            local name = textOr(questName(ctx.client, id), tostring(id))
            local where = textOr(l[id].npc, QO.UNKNOWN)
            say(string.format(QO.LINE, name, id, where))
        end
        say(string.format(QO.TAIL, k.id.slash, QO.WORD))
    end

    if diag and type(diag.commands) == "table" then
        diag.commands[QO.WORD] = run
        if type(diag.help) == "table" then diag.help[QO.WORD] = QO.HELP end
    end

    k:Module({
        name = QO.NAME,
        needs = { "client", "store", "bus", "sched" },
        provides = { Dropped = api.dropped, Clear = api.clear },
        start = function(c)
            ctx = c
            local function changed()
                local t = ask(c.client, "now")
                if finite(t) then changedAt = t end
            end
            c.bus:on(QO.NAME, "QUEST_ACCEPTED", changed)
            c.bus:on(QO.NAME, "QUEST_TURNED_IN", changed)
            for _, e in ipairs(QO.EVENTS) do c.bus:on(QO.NAME, e, seen) end
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.questOffers = QO.Declare(ns, ns.diag)
