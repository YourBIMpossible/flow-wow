local _, ns = ...
-- Quest marks on enemy nameplates (G51, lead sections 226 and 227). An
-- enemy whose creature counts toward an unfinished objective of a quest in
-- your log gets a small yellow mark above its nameplate: the objective's
-- count ("3/8"), or "!" when its text carries none. The mark goes when the
-- objective is done, the quest is ready to hand in, or the plate goes.
--
-- WHICH CREATURES COUNT. Only from data, never from a name:
--   1. the installed Questie's objective data, asked at runtime through its
--      own loader (client.questieModule, as Nav/QuestRead.lua): a kill
--      objective's creature ids, an item objective's npcDrops. Objective i
--      of the log is taken to be Questie's ObjectiveData[i]. Nothing of
--      Questie's is copied or saved here.
--   2. for an item objective Questie names, your own learned drops
--      (Items/Drops.lua, "learned.drops"): a creature you looted that item
--      from yourself counts too.
--   Without Questie: no mark. Legacy Flow (Modules/QuestMarks.lua) matched
--   the plate's name against the objective's text ("Kobold Vermin slain:
--   3/8") for kills; that guess is not carried over.
--
-- LOOK ONLY: nothing clicks, targets, casts or writes a CVar; no frame is
-- secure. The client reads are FIRST GUESSES, not seen in game on 16001:
--   client.plates(fn), client.canAttack(unit), client.plateCreature(unit),
--   client.plateQuestMark(unit) (h.show, h.text, h.color),
--   client.questLog() through N.QuestLogRows, client.questieModule(name).
--
-- Pure:
--   PQ.Progress(text) -> "3/8" | nil
--   PQ.Index(rows, db, book) -> { [npc id] = { { quest, label, kind, from } } }
--     kind "kill" | "drop"; from "questie" | "learned"
--   PQ.Label(list) -> text | nil   each count once, at most PQ.MAX_LABELS
-- PQ.Declare(k, diag) -> api
--   api.status() -> { on, source, inView, shown, mobs }
--   api.lines()   what the word PQ.WORD prints
-- Updated on QUEST_LOG_UPDATE, UNIT_QUEST_LOG_CHANGED and
-- PLAYER_ENTERING_WORLD, read once PQ.WAIT seconds after the first of a
-- burst; a plate coming in is marked at once from what was read. No tick.
-- Setting (account): plateQuests.off (its row in Settings/Model.lua).
-- Not tested in game.
local PQ = {}
ns.PlateQuests = PQ

PQ.NAME = "plateQuests"
PQ.WORD = "questmarks"
PQ.HELP = "quest marks on enemy nameplates: what shows and why; questmarks on or questmarks off switches it"
PQ.OFF = "plateQuests.off"
-- When it appears, in one line (lead section 296): its settings row and the
-- buttons word say it, so a player who sees nothing can find out why.
PQ.WHEN = "Shows over an enemy that counts toward an unfinished objective in your quest log."
PQ.DROPS = "learned.drops"
PQ.WAIT = 0.5
PQ.LOOK = 0.5      -- seconds between looks at the switch (lead section 274 PM-3)
PQ.MARK = "!"
PQ.MAX_LABELS = 2
PQ.COLOR = { 1, 0.82, 0 }
PQ.EVENTS = { "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "PLAYER_ENTERING_WORLD" }
PQ.WORDS = {
    none = "not read yet",
    questie = "from Questie and your own loot",
    ["no questie"] = "Questie is not loaded: no marks",
    ["not read"] = "the quest log is not read yet",
    failed = "the last read failed",
}

function PQ.Progress(text)
    if type(text) ~= "string" then return nil end
    local have, need = text:match("(%d+)%s*/%s*(%d+)")
    if have == nil then return nil end
    return have .. "/" .. need
end

-- A number or a list of them -> the whole ids above 0, as a list.
local function ids(v)
    local out = {}
    if type(v) == "number" then v = { v } end
    if type(v) ~= "table" then return out end
    for _, n in ipairs(v) do
        if type(n) == "number" and n > 0 and n == math.floor(n) then out[#out + 1] = n end
    end
    return out
end

-- A function of a Questie module, called both ways Questie writes them, as
-- Nav/QuestRead.lua. Every lookup here answers a table: anything else from
-- either form (an error, a number, a text) is no answer (lead section 274
-- PM-2).
local function dbCall(db, name, id)
    if type(db) ~= "table" or type(db[name]) ~= "function" then return nil end
    local ok, v = pcall(db[name], id)
    if ok and type(v) == "table" then return v end
    ok, v = pcall(db[name], db, id)
    if ok and type(v) == "table" then return v end
    return nil
end

-- The names Questie gives for one objective: its own Text, and the name of
-- its creature or item. Lowercase; empty when Questie gives none.
local function odNames(db, od)
    local out = {}
    local function put(s)
        if type(s) == "string" and s ~= "" then out[#out + 1] = s:lower() end
    end
    put(od.Text)
    local fn
    if od.Type == "monster" then fn = "GetNPC" elseif od.Type == "item" then fn = "GetItem" end
    if fn then
        for _, id in ipairs(ids(od.Id)) do
            local thing = dbCall(db, fn, id)
            if thing then put(thing.name) end
        end
    end
    return out
end

local function named(names, text)
    for _, n in ipairs(names) do
        if text:find(n, 1, true) then return true end
    end
    return false
end

-- Lead section 274 PM-1: which of Questie's objectives log objective i is.
-- Where Questie names them, by name: data[i] when its name is in the
-- objective's text, else the one other objective whose name is; none, or
-- more than one: nil (no mark, never a guess). Where Questie names none of
-- them, by place (data[i]), as Nav/QuestRead.lua takes it.
local function matchOd(db, data, i, text)
    local all, anyNamed = {}, false
    for j, od in ipairs(data) do
        if type(od) == "table" then
            all[j] = odNames(db, od)
            if #all[j] > 0 then anyNamed = true end
        end
    end
    if not anyNamed then return data[i] end
    if type(text) ~= "string" then return nil end
    local lower = text:lower()
    if all[i] and named(all[i], lower) then return data[i] end
    local found
    for j, names in pairs(all) do
        if j ~= i and named(names, lower) then
            if found ~= nil then return nil end
            found = data[j]
        end
    end
    return found
end

-- The creatures you looted itemId from yourself.
local function learnedFrom(book, itemId)
    local out = {}
    local Items = ns.Items
    if type(book) ~= "table" or type(Items) ~= "table" or type(Items.Key) ~= "function" then return out end
    local key = Items.Key(itemId)
    if key == nil then return out end
    for npc, e in pairs(book) do
        local id = tonumber(npc)
        if id ~= nil and type(e) == "table" and type(e.items) == "table" and e.items[key] ~= nil then
            out[#out + 1] = id
        end
    end
    table.sort(out)
    return out
end

-- Parity rows C-17 and C-18, the data half (lead section 715), as Flow's
-- Modules/QuestMarks.lua (:1-20): what you do to a marked mob. Each entry
-- of PQ.Index carries what = "kill" | "loot" | "use". A creature objective
-- is "use" when the player's Questie says the quest hands an item
-- (quest.sourceItemId, a number) and the log line does not say "slain"
-- (the game's own words, as "Tested Silithid: 1/5"); else "kill". An item
-- objective is "loot". Read from Questie at runtime; nothing copied.
PQ.KINDS = { "kill", "loot", "use", "starts" }
function PQ.MonsterKind(quest, text)
    if type(quest) == "table" and type(quest.sourceItemId) == "number" and quest.sourceItemId > 0
        and type(text) == "string" and not text:lower():find("slain", 1, true) then
        return "use"
    end
    return "kill"
end

-- The kinds in a plate's list, each once, in PQ.KINDS order.
function PQ.Kinds(list)
    local has = {}
    if type(list) == "table" then
        for _, e in ipairs(list) do
            if type(e) == "table" and type(e.what) == "string" then has[e.what] = true end
        end
    end
    local out = {}
    for _, kind in ipairs(PQ.KINDS) do
        if has[kind] then out[#out + 1] = kind end
    end
    return out
end

-- Parity row C-19, the data half (lead sections 720/721), as Flow's
-- Modules/QuestMarks.lua (:24-26): the mobs that drop an item that starts
-- a quest you can take. From the player's own Questie at runtime: each
-- quest of db.QuestPointers whose Starts.Item lists an item, kept when
-- Nav/RoutePickups.lua P.Candidate(q, ctx) says you can take it (not in
-- your log, not done, for you, in reach, earlier quests done); then each
-- item's npcDrops. ctx is P.Candidate's: { level, log, me, done }.
-- -> { [npc id] = { { quest, label = PQ.MARK, kind = "start", from =
-- "questie", what = "starts" } } }. Anything missing or failing: {}.
-- Walking every quest is a large pass (lead section 723), sliced as
-- Nav/DungeonRead.lua's R.Step: PQ.StartsPass makes the state, each
-- PQ.StartsStep files the next n (PQ.SLICE) quests, PQ.StartsResult is
-- nil until it is done. The module steps it once a frame, out of a fight
-- only. PQ.Starts(db, ctx) walks the whole pass at once (tests, pure use).
PQ.SLICE = 200

function PQ.StartsPass(db, ctx)
    local P = ns.Nav and ns.Nav.RoutePickups
    if type(db) ~= "table" or type(ctx) ~= "table" or type(db.QuestPointers) ~= "table"
        or type(db.GetQuest) ~= "function" or type(P) ~= "table" or type(P.Candidate) ~= "function" then
        return { state = "none", out = {} }
    end
    local list = {}
    for id in pairs(db.QuestPointers) do
        if type(id) == "number" then list[#list + 1] = id end
    end
    table.sort(list)
    return { state = "building", ids = list, at = 0, out = {} }
end

function PQ.StartsStep(st, db, ctx, n)
    if type(st) ~= "table" or st.state ~= "building" then return end
    local P = ns.Nav and ns.Nav.RoutePickups
    if type(db) ~= "table" or type(P) ~= "table" or type(P.Candidate) ~= "function" then
        st.state = "none"
        return
    end
    local stop = math.min(#st.ids, st.at + (tonumber(n) or PQ.SLICE))
    for i = st.at + 1, stop do
        local id = st.ids[i]
        local q = dbCall(db, "GetQuest", id)
        local items
        if type(q) == "table" and type(q.Starts) == "table" then items = q.Starts.Item end
        if type(items) == "table" and #items > 0 then
            local cand = { Id = id, level = q.level, requiredLevel = q.requiredLevel,
                preQuestSingle = q.preQuestSingle, preQuestGroup = q.preQuestGroup,
                exclusiveTo = q.exclusiveTo, requiredRaces = q.requiredRaces,
                requiredClasses = q.requiredClasses, requiredMinRep = q.requiredMinRep,
                requiredMaxRep = q.requiredMaxRep, requiredSkill = q.requiredSkill,
                requiredSpell = q.requiredSpell }
            local okC, can = pcall(P.Candidate, cand, ctx)
            if okC and can == true then
                for _, itemId in ipairs(ids(items)) do
                    local item = dbCall(db, "GetItem", itemId)
                    if type(item) == "table" then
                        for _, npc in ipairs(ids(item.npcDrops)) do
                            local list = st.out[npc]
                            if list == nil then
                                list = {}
                                st.out[npc] = list
                            end
                            list[#list + 1] = { quest = id, label = PQ.MARK, kind = "start", from = "questie",
                                                what = "starts" }
                        end
                    end
                end
            end
        end
    end
    st.at = stop
    if st.at >= #st.ids then st.state = "ready" end
end

-- The pass's answer once it is done ("ready", or "none": nothing to walk),
-- else nil: not known yet.
function PQ.StartsResult(st)
    if type(st) ~= "table" then return nil end
    if st.state == "ready" or st.state == "none" then return st.out end
    return nil
end

function PQ.Starts(db, ctx)
    local st = PQ.StartsPass(db, ctx)
    while st.state == "building" do PQ.StartsStep(st, db, ctx) end
    return PQ.StartsResult(st) or {}
end

function PQ.Index(rows, db, book)
    local out = {}
    if type(rows) ~= "table" or type(db) ~= "table" then return out end
    local function add(npc, quest, label, kind, from, what)
        local list = out[npc]
        if list == nil then
            list = {}
            out[npc] = list
        end
        list[#list + 1] = { quest = quest, label = label, kind = kind, from = from, what = what }
    end
    for _, row in ipairs(rows) do
        if type(row) == "table" and row.complete ~= true and row.failed ~= true then
            local quest = dbCall(db, "GetQuest", row.id)
            local data
            if type(quest) == "table" then data = quest.ObjectiveData end
            if type(data) == "table" and type(row.objectives) == "table" then
                for i, o in ipairs(row.objectives) do
                    local od
                    if type(o) == "table" and o.done ~= true then od = matchOd(db, data, i, o.text) end
                    if type(o) == "table" and o.done ~= true and type(od) == "table" then
                        local label = PQ.Progress(o.text) or PQ.MARK
                        if od.Type == "monster" then
                            local what = PQ.MonsterKind(quest, o.text)
                            for _, npc in ipairs(ids(od.Id)) do add(npc, row.id, label, "kill", "questie", what) end
                        elseif od.Type == "item" then
                            local seen = {}
                            local item = dbCall(db, "GetItem", od.Id)
                            local drops
                            if type(item) == "table" then drops = item.npcDrops end
                            for _, npc in ipairs(ids(drops)) do
                                seen[npc] = true
                                add(npc, row.id, label, "drop", "questie", "loot")
                            end
                            for _, itemId in ipairs(ids(od.Id)) do
                                for _, npc in ipairs(learnedFrom(book, itemId)) do
                                    if not seen[npc] then
                                        seen[npc] = true
                                        add(npc, row.id, label, "drop", "learned", "loot")
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return out
end

function PQ.Label(list)
    if type(list) ~= "table" or #list == 0 then return nil end
    local parts, seen = {}, {}
    for _, e in ipairs(list) do
        if #parts >= PQ.MAX_LABELS then break end
        local s = type(e) == "table" and e.label
        if type(s) == "string" and not seen[s] then
            seen[s] = true
            parts[#parts + 1] = s
        end
    end
    if #parts == 0 then return nil end
    return table.concat(parts, " ")
end

-- One read of the client, or nil when it has no such read or it fails.
local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if not ok then return nil end
    return v
end

function PQ.Declare(k, diag)
    local api = {}
    local ctx
    local inView = {}        -- [unit] = true: the plates on screen
    local marks = {}         -- [unit] = the client's mark handle
    local shownOn = {}       -- [unit] = true: a mark showing
    local index              -- nil until read
    local source = "none"
    local cancelPlates, pending, cancelLook
    local wasOn = false

    local function on() return ctx ~= nil and ctx.settings:get(PQ.OFF) ~= true end

    local function hideOne(unit)
        local h = marks[unit]
        if h then h.show(false) end
        shownOn[unit] = nil
    end

    local function hideAll()
        for unit in pairs(marks) do hideOne(unit) end
    end

    local function drawOne(unit)
        local client = ctx.client
        local list
        if on() and type(index) == "table" and ask(client, "canAttack", unit) == true then
            local id = ask(client, "plateCreature", unit)
            if id ~= nil then list = index[id] end
        end
        local label = PQ.Label(list)
        if label == nil then
            hideOne(unit)
            return
        end
        local h = marks[unit]
        if not h then
            h = ask(client, "plateQuestMark", unit)
            if type(h) ~= "table" then return end
            marks[unit] = h
        end
        h.text(label)
        h.color(PQ.COLOR[1], PQ.COLOR[2], PQ.COLOR[3])
        h.show(true)
        shownOn[unit] = true
    end

    -- C-17/C-18: what a marked plate is for, for the icons the drawing lane
    -- makes: { kinds, label, target } or nil (no mark, not a nameplate
    -- unit, not on screen). target: client.plateIsTarget(unit), a CLIENT
    -- NEED (UnitIsUnit(unit, "target"), stubbed in Core/ClientFake.lua);
    -- true or false, nil when not read. Read only, never chosen.
    function api.markOf(unit)
        if type(unit) ~= "string" or not unit:find("^nameplate%d+$") or not inView[unit] then return nil end
        if not ctx or not on() or type(index) ~= "table" then return nil end
        local client = ctx.client
        if ask(client, "canAttack", unit) ~= true then return nil end
        local id = ask(client, "plateCreature", unit)
        local list
        if id ~= nil then list = index[id] end
        local label = PQ.Label(list)
        if label == nil then return nil end
        local target = ask(client, "plateIsTarget", unit)
        if type(target) ~= "boolean" then target = nil end
        return { kinds = PQ.Kinds(list), label = label, target = target }
    end

    local function drawAll()
        for unit in pairs(inView) do drawOne(unit) end
    end

    -- C-19: the log's own index, the starts pass and its answer.
    local logIndex, pass, passDb, passCtx, cancelPass, startsGot

    local function merged()
        local out = {}
        for npc, list in pairs(logIndex or {}) do
            local copy = {}
            for i, e in ipairs(list) do copy[i] = e end
            out[npc] = copy
        end
        for npc, list in pairs(startsGot or {}) do
            local into = out[npc]
            if into == nil then
                into = {}
                out[npc] = into
            end
            for _, e in ipairs(list) do into[#into + 1] = e end
        end
        return out
    end

    local function stopPass()
        if cancelPass then pcall(cancelPass) end
        cancelPass = nil
    end

    -- One slice a frame, only while the client says plainly you are out of
    -- a fight; in one (or not known) the pass waits.
    local function stepPass()
        if not ctx or type(pass) ~= "table" then return stopPass() end
        if ask(ctx.client, "inCombat") ~= false then return end
        local ok = pcall(PQ.StartsStep, pass, passDb, passCtx)
        if not ok then pass.state = "none" end
        local got = PQ.StartsResult(pass)
        if got ~= nil then
            stopPass()
            startsGot = got
            pass = nil
            if type(logIndex) == "table" then
                index = merged()
                drawAll()
            end
        end
    end

    local function startPass(db, client, rows)
        stopPass()
        startsGot, pass = nil, nil
        local level = tonumber(ask(client, "level"))
        if not level then return end
        local inLog = {}
        for _, row in ipairs(rows) do
            if type(row) == "table" and row.id ~= nil then inLog[row.id] = true end
        end
        local S = ns.DungeonStates
        local class = ask(client, "class")
        local classId
        if class and type(S) == "table" and type(S.CLASS_ID) == "table" then classId = S.CLASS_ID[class] end
        passDb = db
        passCtx = { level = level, log = inLog,
            me = { raceId = ask(client, "raceId"), classId = classId, faction = ask(client, "faction") },
            done = function(id) return ask(client, "questDone", id) end }
        local ok, st = pcall(PQ.StartsPass, db, passCtx)
        if not ok or type(st) ~= "table" or st.state ~= "building" then return end
        pass = st
        if type(client.onFrame) == "function" then
            local okF, cancel = pcall(client.onFrame, stepPass)
            if okF and type(cancel) == "function" then cancelPass = cancel end
        end
    end

    local function read()
        local client = ctx.client
        local N = ns.Nav
        local rows
        if type(N) == "table" and type(N.QuestLogRows) == "function" then rows = N.QuestLogRows(client) end
        if rows == nil then
            index, source = nil, "not read"
            return
        end
        local db = ask(client, "questieModule", "QuestieDB")
        if type(db) ~= "table" or type(db.GetQuest) ~= "function" then
            index, source = {}, "no questie"
            return
        end
        local ok, got = pcall(PQ.Index, rows, db, ctx.store:get("char", PQ.DROPS))
        -- C-19: the mobs that drop an item starting a quest you can take,
        -- read by a sliced pass (stepPass, a slice a frame, out of a fight);
        -- not known, so not marked, until it is done.
        if ok and type(got) == "table" then
            logIndex = got
            got = merged()
            startPass(db, client, rows)
        end
        if ok and type(got) == "table" then
            index, source = got, "questie"
        else
            index, source = nil, "failed"
        end
    end

    local function rebuild()
        pending = nil
        if not ctx then return end
        read()
        drawAll()
    end

    local function soon()
        if not ctx or pending then return end
        pending = ctx.sched:after(PQ.NAME, PQ.WAIT, rebuild)
    end

    local function onPlate(what, unit)
        if not ctx then return end
        -- A plate frame is handed out again: what was on it before goes.
        hideOne(unit)
        marks[unit] = nil
        if what == "added" then
            inView[unit] = true
            drawOne(unit)
        else
            inView[unit] = nil
        end
    end

    function api.status()
        local n, shown, mobs = 0, 0, 0
        for _ in pairs(inView) do n = n + 1 end
        for _ in pairs(shownOn) do shown = shown + 1 end
        if type(index) == "table" then
            for _ in pairs(index) do mobs = mobs + 1 end
        end
        return { on = on(), source = source, inView = n, shown = shown, mobs = mobs }
    end

    function api.lines()
        local s = api.status()
        return {
            ("quest marks on nameplates: %s; %d nameplate(s) in view, %d marked")
                :format(s.on and "on" or "off", s.inView, s.shown),
            ("  quest data: %s; %d creature(s) count toward your quests")
                :format(PQ.WORDS[s.source] or tostring(s.source), s.mobs),
        }
    end

    k:Setting({ key = PQ.OFF, scope = "account", type = "bool", default = false,
        label = "Hide quest marks on enemy nameplates", group = "combat.plates", help = PQ.WHEN,
        synonyms = { "quest", "nameplate", "objective", "mark", "kill" } })

    k:Module({
        name = PQ.NAME,
        needs = { "client", "settings", "bus", "sched", "store" },
        provides = { Status = api.status, Lines = api.lines, MarkOf = api.markOf },
        start = function(c)
            ctx = c
            cancelPlates = ask(c.client, "plates", onPlate)
            for _, event in ipairs(PQ.EVENTS) do c.bus:on(PQ.NAME, event, soon) end
            -- Lead section 274 PM-3: the settings tell no one of a change,
            -- so the switch alone is looked at every PQ.LOOK seconds (one
            -- setting read, no rebuild): off hides every mark, on reads again.
            wasOn = on()
            cancelLook = c.sched:every(PQ.NAME, PQ.LOOK, function()
                local now = on()
                if now == wasOn then return end
                wasOn = now
                if now then soon() else hideAll() end
            end, { when = "always" })
            soon()
        end,
        stop = function()
            if type(cancelPlates) == "function" then pcall(cancelPlates) end
            cancelPlates = nil
            if type(pending) == "function" then pcall(pending) end
            pending = nil
            if type(cancelLook) == "function" then pcall(cancelLook) end
            cancelLook = nil
            stopPass()
            pass, startsGot, logIndex = nil, nil, nil
            hideAll()
            inView, marks, shownOn, index, source = {}, {}, {}, nil, "none"
        end,
    })

    local function say(line)
        if ctx then ctx.client.print(ns.id.title .. ": " .. line) end
    end

    if diag and type(diag.commands) == "table" then
        diag.commands[PQ.WORD] = function(rest)
            if not ctx then return end
            local word = tostring(rest or ""):lower():match("^%s*(%S*)")
            if word == "on" or word == "off" then
                ctx.settings:set(PQ.OFF, word == "off")
                if word == "off" then hideAll() else soon() end
            end
            local lines = api.lines()
            say(lines[1])
            for i = 2, #lines do ctx.client.print(lines[i]) end
        end
        if type(diag.help) == "table" then diag.help[PQ.WORD] = PQ.HELP end
    end
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.plateQuests = PQ.Declare(ns, ns.diag)
