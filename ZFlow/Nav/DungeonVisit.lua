-- The dungeon you are in, in chat words (FLOW-PARITY B-48, lead section
-- 490 item 2; Flow's Modules/Nav/Dungeons.lua D.EnterLines and its dungeon
-- word).
--
--   the dungeon word   says the dungeon you are in: its name, how many of
--                      its quests are in your log and whether each is done,
--                      the ones you could still pick up and who gives them,
--                      and the bosses killed this visit. Outside a dungeon
--                      it says so and names the word for the list.
--
-- Chat words only. LOOK ONLY: nothing is accepted, shared, targeted or
-- clicked. No quest or dungeon table ships here: the quests are Questie's,
-- read through Nav/DungeonRead.lua (its index is read in slices while you
-- are inside), the kills are Nav/BossKills.lua's.
--
-- Pure parts:
--   V.Quests(pane, quests, log) -> have, missing
--       have: { { name, done } } the dungeon's quests in your log;
--       missing: { { name, from } } the ones to pick up before you go.
--   V.Summary(name, have, missing, kills, reported, max) -> lines
--   V.KillLine(kills, reported) -> the line of bosses killed
--
-- Client reads: instance, instanceName, questLog, and DungeonRead's own.
-- Not tested in game.
local _, ns = ...

local V = {}
ns.DungeonVisit = V

V.NAME = "dungeonVisit"
V.WORD = "dungeon"
V.HELP = "say the dungeon you are in: your quests for it and the bosses killed"
V.OUTSIDE = "you are not in a dungeon. Type %s dungeons for the dungeons and their quests."
V.NO_NAME = "the game does not say which dungeon this is."
V.NOT_KNOWN = "Questie has no dungeon of this name, so its quests are not known."
V.IN_LOG_ONE = "1 of its quests in your log"
V.IN_LOG = "%d of its quests in your log"
V.QUEST_DONE = "done, hand it in"
V.QUEST_OPEN = "not done"
V.NOT_IN_LOG = "Not in your log (%d): %s"
V.MORE = "; and %d more"
V.MAX = 6
V.KILLS = "Bosses killed this visit (%d): %s"
V.NO_KILL = "No boss killed yet this visit."
V.NO_REPORT = "The game does not report boss kills here."
V.A_BOSS = "a boss"
-- The instance kinds a dungeon is (client.instance().kind).
V.KINDS = { party = true, raid = true }

local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if ok then return v end
    return nil
end

-- A quest of the log is done when the game says so, or when it has
-- objectives and every one is done.
local function doneIn(row)
    if type(row) ~= "table" then return false end
    if row.complete == true then return true end
    local n = 0
    for _, o in ipairs(type(row.objectives) == "table" and row.objectives or {}) do
        if type(o) ~= "table" or o.done ~= true then return false end
        n = n + 1
    end
    return n > 0
end

function V.Quests(pane, quests, log)
    local have, missing = {}, {}
    local byId = {}
    for _, row in ipairs(type(log) == "table" and log or {}) do
        if type(row) == "table" and row.id ~= nil then byId[row.id] = row end
    end
    for _, g in ipairs(type(pane) == "table" and type(pane.groups) == "table" and pane.groups or {}) do
        if type(g) == "table" and type(g.rows) == "table" then
            for _, r in ipairs(g.rows) do
                if g.id == "log" then
                    have[#have + 1] = { name = tostring(r.name), done = doneIn(byId[r.id]) }
                elseif g.id == "pickup" then
                    local q
                    if type(quests) == "table" then q = quests[r.id] end
                    local from
                    if type(q) == "table" and type(q.giverName) == "string" and q.giverName ~= "" then
                        from = q.giverName
                    end
                    missing[#missing + 1] = { name = tostring(r.name), from = from }
                end
            end
        end
    end
    local function byName(a, b) return a.name < b.name end
    table.sort(have, byName)
    table.sort(missing, byName)
    return have, missing
end

function V.KillLine(kills, reported)
    if reported == false then return V.NO_REPORT end
    local names = {}
    for _, e in ipairs(type(kills) == "table" and kills or {}) do
        if type(e) == "table" and type(e.name) == "string" and e.name ~= "" then
            names[#names + 1] = e.name
        else
            names[#names + 1] = V.A_BOSS
        end
    end
    if #names == 0 then return V.NO_KILL end
    return V.KILLS:format(#names, table.concat(names, ", "))
end

-- The quest lines of the summary: the first starts with the dungeon's name.
function V.QuestLines(name, have, missing, max)
    max = max or V.MAX
    local first = tostring(name) .. ": " .. V.IN_LOG:format(#have)
    if #have == 1 then first = tostring(name) .. ": " .. V.IN_LOG_ONE end
    if #have > 0 then
        local said = {}
        for i, q in ipairs(have) do
            local state = V.QUEST_OPEN
            if q.done then state = V.QUEST_DONE end
            said[i] = q.name .. " (" .. state .. ")"
        end
        first = first .. ": " .. table.concat(said, ", ")
    end
    local out = { first }
    if #missing > 0 then
        local said = {}
        for i = 1, math.min(max, #missing) do
            local m = missing[i]
            said[i] = m.name
            if m.from then said[i] = m.name .. " (" .. m.from .. ")" end
        end
        local line = V.NOT_IN_LOG:format(#missing, table.concat(said, "; "))
        if #missing > max then line = line .. V.MORE:format(#missing - max) end
        out[#out + 1] = line
    end
    return out
end

function V.Summary(name, have, missing, kills, reported, max)
    if type(have) ~= "table" then have = {} end
    if type(missing) ~= "table" then missing = {} end
    local out = V.QuestLines(name, have, missing, max)
    out[#out + 1] = V.KillLine(kills, reported)
    return out
end

function V.Declare(k, diag)
    local api = {}
    local ctx, st, cancelStep
    local id = k.id or ns.id
    local R = ns.DungeonRead

    local function client() return ctx and ctx.client or k.client end

    local function inside()
        local inst = ask(client(), "instance")
        return type(inst) == "table" and inst.inside == true and V.KINDS[inst.kind] == true
    end

    -- The reader's index, in slices out of the way of the frame; started
    -- again after one that failed or found no Questie.
    local function index()
        if st and st.state ~= "failed" and st.state ~= "noquestie" then return end
        if cancelStep then cancelStep() end
        cancelStep = nil
        st = R.Start(client())
        if st.state == "building" and ctx and ctx.sched then
            cancelStep = ctx.sched:every(V.NAME, 0.05, function()
                R.Step(st, client(), R.SLICE)
                if st.state ~= "building" then
                    if cancelStep then cancelStep() end
                    cancelStep = nil
                end
            end)
        end
    end

    local function killLine()
        local kills
        if type(k.use) == "function" then kills = k.use(ns.BossKills.NAME) end
        if type(kills) ~= "table" then return V.KillLine({}, nil) end
        local reported
        if type(kills.Reported) == "function" then reported = kills.Reported() end
        local list = {}
        if type(kills.Kills) == "function" then list = kills.Kills() end
        return V.KillLine(list, reported)
    end

    -- The quest lines for the dungeon of that name, or the one line that
    -- says why there are none yet.
    local function questLines(name)
        index()
        if not st or st.state == "noquestie" then return { name .. ": " .. ns.DungeonStates.WHY.noQuestie[1] } end
        if st.state == "failed" then return { name .. ": " .. (st.why or R.WHY_LIST)[1] } end
        if st.state == "building" then return { name .. ": " .. R.WHY_BUILDING[1] } end
        local d = R.DungeonNamed(st, name)
        if not d then return { name .. ": " .. V.NOT_KNOWN } end
        local pane = R.Pane(st, client(), d.key)
        if type(pane) ~= "table" then return { name .. ": " .. V.NOT_KNOWN } end
        local log
        if ns.Nav and type(ns.Nav.QuestLogRows) == "function" then log = ns.Nav.QuestLogRows(client()) end
        local have, missing = V.Quests(pane, st.quests, log)
        if #have == 0 and #missing == 0 and type(pane.why) == "table" then
            return { name .. ": " .. tostring(pane.why[1]) }
        end
        return V.QuestLines(name, have, missing)
    end

    -- The summary's lines; outside: nil.
    function api.Lines()
        if not inside() then return nil end
        local name = ask(client(), "instanceName")
        local out
        if type(name) ~= "string" or name == "" then
            out = { V.NO_NAME }
        else
            out = questLines(name)
        end
        out[#out + 1] = killLine()
        return out
    end

    local function say(lines)
        local c = client()
        if type(c) ~= "table" or type(c.print) ~= "function" then return end
        for i, line in ipairs(lines) do
            if i == 1 then c.print(id.title .. ": " .. line) else c.print("  " .. line) end
        end
    end

    if diag and type(diag.commands) == "table" then
        diag.commands[V.WORD] = function()
            local ok, lines = pcall(api.Lines)
            if not ok then
                k.problems:add(V.NAME, "word", tostring(lines))
                return
            end
            if not lines then return say({ V.OUTSIDE:format(tostring(id.slash)) }) end
            say(lines)
        end
        if type(diag.help) == "table" then diag.help[V.WORD] = V.HELP end
    end

    k:Module({
        name = V.NAME,
        needs = { "client", "store", "settings", "bus", "sched" },
        provides = { Lines = api.Lines },
        start = function(c)
            ctx = c
            -- Inside a dungeon the index is read ahead, so the word answers at once.
            local function entered()
                if inside() then index() end
            end
            for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do
                c.bus:on(V.NAME, event, entered)
            end
            entered()
        end,
        stop = function()
            if cancelStep then cancelStep() end
            cancelStep = nil
            ctx = nil
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.dungeonVisit = V.Declare(ns, ns.diag)
