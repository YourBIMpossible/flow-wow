local _, ns = ...
-- Dungeon chat lines and run timing (FLOW-PARITY B-47, B-48, B-56), a port
-- of legacy Flow's Modules/Nav/Dungeons.lua (EnterSplit, EnterLines,
-- onEnter, ns.commands.dungeon, LearnTime, onZone, finishRun).
--
-- B-47: on entering a dungeon, once per visit, a few chat lines: which of
-- its quests are in your log, and which you could have picked up and did
-- not, so a missed quest is seen at the door, not after the run. Local
-- chat only (client.print); nothing is sent.
-- B-48: the word `dungeon` says the same lines again, and the timing.
-- B-56: run timing. Entering starts a visit; leaving and coming back
-- within C.REENTER seconds (a death walk) is the same visit; C.REENTER
-- after leaving, the visit is a finished run and its minutes join the
-- dungeon's running average of the last ten (runs under 5 or over 240
-- minutes do not count). Kept per character under C.PATH.
--
-- Which dungeon and its quests: the instance name (client.instanceName)
-- matched by ns.DungeonRead.DungeonNamed, and its pane (R.Pane): the "log"
-- rows are had; the "pickup" and "inside" rows are the ones not in the log
-- that are for you now. Without Questie only the timing is kept.
--
-- Pure:
--   C.EnterLines(name, have, missing, max) -> lines
--   C.FromPane(pane) -> have (names, sorted), missing ({ name }, sorted)
--   C.LearnTime(rec, minutes) -> rec        rec = { avg, n }
--   C.Visit(inn, here, now) -> inn          inn = { key, t, left }
--   C.Finish(inn, now) -> minutes, rest
--   C.TimeLine(rec) -> line
--   C.SoFar(inn, here, now) -> minutes | nil
-- Not tested in game.
local C = {}
ns.DungeonChat = C

C.NAME = "dungeonChat"
C.WORD = "dungeon"
C.HELP = "dungeon: this dungeon's quests in your log and not, and how long your runs here take"
C.SETTING = "dungeon.enterLines"
C.PATH = "nav.dungeonTiming"       -- char: { inn = inn, times = { [name] = rec } }
C.MAX_NAMED = 6
C.REENTER = 600                    -- seconds: a death walk is the same run
C.KINDS = { party = true, raid = true }

C.ADVICE = "Some may need an earlier quest first. Leave and pick them up, or ask your group to share them."
C.NOT_TIMED = "No run here timed yet; your next one is timed."
C.NOT_INSIDE = "You are not in a dungeon."
C.NOT_KNOWN = "Not known which dungeon this is yet, or its quests are still being read."
C.SO_FAR = "This visit: %d min so far."

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function C.EnterLines(name, have, missing, max)
    max = max or C.MAX_NAMED
    have = type(have) == "table" and have or {}
    missing = type(missing) == "table" and missing or {}
    local out = {}
    if #have == 0 and #missing == 0 then return out end
    local list = ""
    if #have > 0 then list = ": " .. table.concat(have, ", ") end
    out[1] = string.format("%s: %d of its quests in your log%s", tostring(name), #have, list)
    if #missing > 0 then
        local names = {}
        for i = 1, math.min(max, #missing) do
            local m = missing[i]
            local text = tostring(m.name)
            if m.from then text = text .. " (" .. tostring(m.from) .. ")" end
            names[i] = text
        end
        local more = ""
        if #missing > max then more = string.format("; and %d more", #missing - max) end
        out[2] = string.format("Not in your log (%d): %s%s", #missing, table.concat(names, "; "), more)
        out[3] = C.ADVICE
    end
    return out
end

local MISSING = { pickup = true, inside = true }

function C.FromPane(pane)
    local have, missing = {}, {}
    local groups = type(pane) == "table" and type(pane.groups) == "table" and pane.groups or {}
    for _, g in ipairs(groups) do
        for _, r in ipairs(type(g) == "table" and type(g.rows) == "table" and g.rows or {}) do
            if type(r) == "table" and type(r.name) == "string" then
                if g.id == "log" then
                    have[#have + 1] = r.name
                elseif MISSING[g.id] then
                    missing[#missing + 1] = { name = r.name, from = r.from }
                end
            end
        end
    end
    table.sort(have)
    table.sort(missing, function(a, b) return a.name < b.name end)
    return have, missing
end

function C.LearnTime(rec, minutes)
    if not finite(minutes) or minutes < 5 or minutes > 240 then return rec end
    if type(rec) ~= "table" or not finite(rec.avg) then return { avg = minutes, n = 1 } end
    local n = math.min((rec.n or 1) + 1, 10)
    return { avg = rec.avg + (minutes - rec.avg) / n, n = n }
end

function C.Visit(inn, here, now)
    if type(inn) ~= "table" or inn.key == nil then inn = nil end
    if here ~= nil then
        if inn and inn.key == here and inn.left and now - inn.left < C.REENTER then
            return { key = inn.key, t = inn.t }
        end
        if inn and inn.key == here and not inn.left then return inn end
        return { key = here, t = now }
    end
    if inn and not inn.left then return { key = inn.key, t = inn.t, left = now } end
    return inn
end

function C.Finish(inn, now)
    if type(inn) ~= "table" or inn.key == nil or not finite(inn.left) or not finite(inn.t) then return nil, inn end
    if now - inn.left < C.REENTER then return nil, inn end
    return (inn.left - inn.t) / 60, nil
end

function C.TimeLine(rec)
    if type(rec) ~= "table" or not finite(rec.avg) then return C.NOT_TIMED end
    return string.format("Your runs here: about %d min (%d timed).", math.floor(rec.avg + 0.5), rec.n or 1)
end

function C.SoFar(inn, here, now)
    if type(inn) ~= "table" or inn.key ~= here or here == nil or inn.left or not finite(inn.t) then return nil end
    return math.floor((now - inn.t) / 60)
end

local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if ok then return v end
    return nil
end

function C.Declare(k, diag)
    local api = {}
    local ctx, st, cancelStep
    local saidFor
    local R = ns.DungeonRead

    local function client() return ctx and ctx.client or k.client end
    local function id() return k.id or ns.id end

    local function say(text)
        local c = client()
        if type(c) ~= "table" or type(c.print) ~= "function" then return end
        c.print(id().title .. ": " .. tostring(text))
    end

    local function here()
        local c = client()
        local inst = ask(c, "instance")
        if type(inst) ~= "table" or inst.inside ~= true or not C.KINDS[inst.kind] then return nil end
        return ask(c, "instanceName")
    end

    local function now()
        local t = ask(client(), "now")
        if finite(t) then return t end
        return nil
    end

    local function saved()
        local v = ctx and ctx.store:get("char", C.PATH)
        if type(v) ~= "table" then v = {} end
        if type(v.times) ~= "table" then v.times = {} end
        return v
    end

    local function save(v)
        local ok, why = ctx.store:set("char", C.PATH, v)
        if not ok then k.problems:add(C.NAME, "save", tostring(why)) end
    end

    -- The dungeon's lines (B-47), or nil while its quests cannot be told.
    local function lines(name)
        if not (R and st and st.state == "ready") then return nil end
        local d = R.DungeonNamed(st, name)
        if not d then return nil end
        local pane = R.Pane(st, client(), d.key)
        if type(pane) ~= "table" or pane.why then return nil end
        local have, missing = C.FromPane(pane)
        return C.EnterLines(d.name or name, have, missing)
    end

    local function index(after)
        if not R or (st and st.state ~= "failed" and st.state ~= "noquestie") then return end
        st = R.Start(client())
        if st.state == "building" and ctx and ctx.sched then
            cancelStep = ctx.sched:every(C.NAME, 0.05, function()
                R.Step(st, client(), R.SLICE)
                if st.state ~= "building" then
                    if cancelStep then cancelStep() end
                    cancelStep = nil
                    after()
                end
            end)
        end
    end

    -- B-47: once per visit, when the quests can be told.
    local function sayEnter()
        local name = here()
        if not name then saidFor = nil; return end
        if name == saidFor or ctx.settings:get(C.SETTING) ~= true then return end
        local got = lines(name)
        if not got then return end
        saidFor = name
        for _, l in ipairs(got) do say(l) end
    end

    -- B-56: the visit and the finished run.
    local function onZone()
        local t = now()
        if not t then return end
        local v = saved()
        local minutes, rest = C.Finish(v.inn, t)
        if minutes then
            local inn = v.inn
            v.times[inn.key] = C.LearnTime(v.times[inn.key], minutes)
        end
        v.inn = C.Visit(rest, here(), t)
        save(v)
        index(sayEnter)
        sayEnter()
    end

    -- B-48: the word.
    function api.Summary()
        local name = here()
        if not name then return say(C.NOT_INSIDE) end
        index(api.Summary)
        local got = lines(name)
        if got and #got > 0 then
            for _, l in ipairs(got) do say(l) end
        elseif not got then
            say(C.NOT_KNOWN)
        end
        local v = saved()
        local t = now()
        if t then
            local so = C.SoFar(v.inn, name, t)
            if so then say(C.SO_FAR:format(so)) end
        end
        say(C.TimeLine(v.times[name]))
    end

    if diag and type(diag.commands) == "table" then
        diag.commands[C.WORD] = function() api.Summary() end
        if type(diag.help) == "table" then diag.help[C.WORD] = C.HELP end
    end

    k:Setting({ key = C.SETTING, scope = "account", type = "bool", default = true,
        label = "Dungeon quests on entering", group = "party",
        help = "When you enter a dungeon, says in chat which of its quests are in your log and which you could"
            .. " still pick up. Only in your own chat window.",
        synonyms = { "dungeon", "instance", "quests", "enter", "missing" } })

    k:Module({
        name = C.NAME,
        needs = { "client", "store", "settings", "sched" },
        provides = { Summary = api.Summary },
        start = function(c)
            ctx = c
            for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do
                c.client.listen(event, function()
                    local ok, err = pcall(onZone)
                    if not ok then k.problems:add(C.NAME, "zone", tostring(err)) end
                end)
            end
        end,
        stop = function()
            if cancelStep then pcall(cancelStep) end
            cancelStep, st, saidFor = nil, nil, nil
        end,
    })
    return api
end

ns.dungeonChat = C.Declare(ns, ns.diag)
