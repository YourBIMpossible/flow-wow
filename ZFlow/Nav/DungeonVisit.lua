-- The dungeon you are in, in chat words (FLOW-PARITY B-48, lead section
-- 490 item 2; Flow's Modules/Nav/Dungeons.lua D.EnterLines and its dungeon
-- word).
--
--   the dungeon word   says the dungeon you are in: its name, how many of
--                      its quests are in your log and whether each is done,
--                      the ones you could still pick up and who gives them,
--                      and the bosses killed this visit. Outside a dungeon
--                      it says so and names the word for the list.
--   on entering        (B-47, section 490 item 3) the quest lines of that
--                      summary are said once when you enter a dungeon: one
--                      line for the quests in your log, one for the ones to
--                      pick up. Nothing is said for a dungeon with no quest
--                      for you, or with the dungeon tracker setting off
--                      (UI/DungeonTracker.lua T.SETTING). They are not said
--                      again on a reload inside the same run.
--   run timing         (B-56, section 490 item 4) each run is timed from
--                      entering to leaving, by the client's clock. Going out
--                      and coming back within V.GRACE seconds (a death walk)
--                      is the same run. The last time of each dungeon is
--                      kept and said as one line, "Last run here: 32
--                      minutes", in the summary and in the dungeon tracker
--                      window. A run whose start or end the clock did not
--                      give has no time, and one shorter than V.SHORT or
--                      longer than V.LONG (a look inside, a night away) is
--                      not kept: the line then says the time is not known.
--
--   wings              (B-57, section 496 item 1) in a dungeon with wings
--                      (Nav/DungeonRead.lua R.WINGS) each wing is a run of
--                      its own. Which wing you are in is told from the last
--                      boss you killed this visit. From then on the summary
--                      is that wing's: its name ("Scarlet Monastery
--                      (Library)"), its quests (and the ones whose wing is
--                      not known), "1 of 2 in this wing" for its bosses, and
--                      its own run time. Before the first kill the summary
--                      is the whole dungeon's and one line says the wing is
--                      not known yet.
--                      Two wings one after the other (Twin, lead section
--                      550): wings that are instances of one name (the
--                      Scarlet Monastery's) look like walking back in. When
--                      a boss of another wing dies after you came back in,
--                      the first wing's run ends where you left it and the
--                      new wing is a run of its own from when you came in,
--                      with its own entering lines, said then (V.Split).
--                      One instance with two wings (Blackrock Spire,
--                      Stratholme): you never leave between them, so there
--                      is one run, and the last boss killed decides which
--                      wing it is recorded under, whole.
--
--   worth it?          (B-54, section 496 item 3) one line, "Your last run:
--                      about 1.8 times your questing XP per hour", in the
--                      summary and after the stops the dungeons word plans.
--                      Both rates are measured, never estimated: your
--                      questing XP per hour from the XP you gained outside
--                      dungeons (the last two hours of play, at least 15
--                      minutes of it), and the run's from the XP you gained
--                      inside it over its timed length (B-56). When either
--                      is not known nothing is said.
--                      The XP is read and its events listened to only once
--                      this character has been in a dungeon or asked one of
--                      the dungeon words (char V.MEASURE): a character that
--                      never does either costs no XP read of this module's
--                      (White's run, lead section 539: the info bar's "a
--                      hidden bar reads nothing" check). The info bar reads
--                      XP for its own row while it is shown; that is its
--                      own and is not counted here (Twin, section 550).
--
--   not known          (Plexy, lead section 504 CHANGES-2) whether you are in
--                      a dungeon has three answers: inside, outside, and
--                      not known (the client's instance read gave nothing,
--                      as Nav/BossKills.lua guards it). Not known changes
--                      nothing: the run you are in goes on, its clock is not
--                      stopped and it is not closed, nothing is said on
--                      "entering", and XP gained meanwhile goes to neither
--                      rate. The dungeon word says it cannot tell.
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
--   V.KillLine(kills, reported, total) -> the line of bosses killed
--       (total: how many bosses the wing has, when the wing is known)
--   V.Key(run) -> the name a run's time is kept under
--   V.Split(run, as) -> old, fresh, or nothing: the run cut in two when a
--       boss tells a wing other than the run's after you came back in
--   V.Step(run, name, now) -> run, changed, finished, seconds, xp
--       the saved run after an event: name is the dungeon you are in (nil:
--       outside), now the clock (nil: not known). finished: the name of a
--       run that ended; seconds: how long it took, or nil.
--   V.RunTime(run) -> seconds or nil      V.TimeText(seconds) -> words or nil
--   V.LastLine(seconds) -> the line
--   V.Gain(before, now) -> XP gained between two readings { cur, max,
--       level }, or nil when it cannot be told
--   V.RateFrom(samples, now) -> questing XP per hour, or nil (legacy Flow's
--       D.RateFrom): samples { { t, xp } } oldest first
--   V.Ratio(xp, seconds, rate) -> the run's XP per hour over rate, or nil
--
-- Client reads: instance, instanceName, questLog, and DungeonRead's own.
-- Client reads also: clock, xp, level.
-- Saved data also: char V.SAMPLES = { { t, xp } } the XP gained outside
-- dungeons, the newest V.SAMPLES_MAX; char V.RUN_XP = { [run name] = xp }
-- the XP gained in the last run of each, kept with its time.
-- Saved data: char V.RUN = { name, as, said, t, left, back, backLeft,
-- xpBack }: the run you are in (as: the wing's run name, once the wing is
-- known; back, backLeft, xpBack: when you last came back in, when you had
-- left, and the XP until then, kept for V.Split)
-- (t: the clock at entering, left: at leaving), so a reload inside it says
-- nothing twice and keeps its start. char V.TIMES = { [dungeon name] =
-- seconds }: the last run of each.
-- Not tested in game.
local _, ns = ...

local V = {}
ns.DungeonVisit = V

V.NAME = "dungeonVisit"
V.WORD = "dungeon"
V.RUN = "dungeon.run"
V.TIMES = "dungeon.times"
V.RUN_XP = "dungeon.runXp"
V.SAMPLES = "dungeon.xpSamples"
V.MEASURE = "dungeon.measure"
V.XP_EVENTS = { "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP" }
V.SAMPLES_MAX = 200
V.RATE_SPAN = 7200   -- questing rate: the last two hours
V.RATE_GAP = 600     -- a gap longer than this (a break) counts as this
V.RATE_MIN = 900     -- at least this much play, else the rate is not known
V.RATE = "Your last run: about %.1f times your questing XP per hour"
V.GRACE = 600
V.SHORT = 300
V.LONG = 240 * 60
V.LAST = "Last run here: %s"
V.LAST_UNKNOWN = "Last run here: time not known yet."
V.MINUTE, V.MINUTES = "1 minute", "%d minutes"
V.HOUR, V.HOURS = "1 hour", "%d hours"
V.HELP = "say the dungeon you are in: your quests for it and the bosses killed"
V.OUTSIDE = "you are not in a dungeon. Type %s dungeons for the dungeons and their quests."
V.CANNOT_TELL = "the game does not say right now whether you are in a dungeon. Ask again in a moment."
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
V.KILLS_WING = "Bosses killed this visit (%d of %d in this wing): %s"
V.WING_UNKNOWN = "Which wing this is is not known yet: it is told from the first boss you kill."
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

function V.KillLine(kills, reported, total)
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
    if type(total) == "number" and total > 0 then
        return V.KILLS_WING:format(#names, total, table.concat(names, ", "))
    end
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

local function clockOk(v)
    return type(v) == "number" and v == v and v > 0 and v ~= math.huge
end

local function num(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function V.Gain(before, now)
    if type(before) ~= "table" or type(now) ~= "table" then return nil end
    for _, v in ipairs({ before.cur or false, before.max or false, before.level or false,
                         now.cur or false, now.level or false }) do
        if not num(v) then return nil end
    end
    if now.level == before.level then return now.cur - before.cur end
    -- One level up: the rest of the old level and what is in the new one.
    if now.level == before.level + 1 then return (before.max - before.cur) + now.cur end
    return nil
end

function V.RateFrom(samples, now)
    if not clockOk(now) then return nil end
    local from = now - V.RATE_SPAN
    local xp, secs, last = 0, 0, nil
    for _, s in ipairs(type(samples) == "table" and samples or {}) do
        if type(s) == "table" and clockOk(s.t) and s.t >= from and s.t <= now then
            if last then
                secs = secs + math.min(s.t - last, V.RATE_GAP)
                if num(s.xp) then xp = xp + s.xp end
            end
            last = s.t
        end
    end
    if secs < V.RATE_MIN or xp <= 0 then return nil end
    return xp / secs * 3600
end

function V.Ratio(xp, seconds, rate)
    if not num(xp) or xp <= 0 or not clockOk(seconds) then return nil end
    if not num(rate) or rate <= 0 then return nil end
    return (xp / seconds * 3600) / rate
end

-- The XP a run gained, or nil when a reading was missed inside it.
function V.RunXp(run)
    if type(run) ~= "table" or run.noXp == true or not num(run.xp) or run.xp <= 0 then return nil end
    return run.xp
end

function V.Key(run)
    if type(run) ~= "table" then return nil end
    if type(run.as) == "string" and run.as ~= "" then return run.as end
    return run.name
end

-- Twin, lead section 550: a boss tells a wing other than the run's, after
-- you came back in. The run is cut in two: old ends where you left it, and
-- fresh is the new wing's, from when you came in, its lines not said yet.
-- Nothing when the run has no wing yet, the wing is the same, or you never
-- left (one instance with two wings).
function V.Split(run, as)
    if type(run) ~= "table" or type(run.as) ~= "string" or type(as) ~= "string" or as == run.as then return nil end
    if not clockOk(run.back) or not clockOk(run.backLeft) then return nil end
    local old = { name = run.name, as = run.as, t = run.t, left = run.backLeft }
    local fresh = { name = run.name, as = as, t = run.back }
    local before = 0
    if num(run.xpBack) and run.xpBack > 0 then
        before = run.xpBack
        old.xp = before
    end
    if num(run.xp) and run.xp - before > 0 then fresh.xp = run.xp - before end
    if run.noXp == true then old.noXp, fresh.noXp = true, true end
    return old, fresh
end

function V.RunTime(run)
    if type(run) ~= "table" or not clockOk(run.t) or not clockOk(run.left) or run.left < run.t then return nil end
    return run.left - run.t
end

function V.TimeText(seconds)
    if not clockOk(seconds) then return nil end
    local minutes = math.floor(seconds / 60 + 0.5)
    if minutes < 1 then minutes = 1 end
    local hours = math.floor(minutes / 60)
    minutes = minutes - hours * 60
    local parts = {}
    if hours == 1 then parts[#parts + 1] = V.HOUR elseif hours > 1 then parts[#parts + 1] = V.HOURS:format(hours) end
    if minutes == 1 then
        parts[#parts + 1] = V.MINUTE
    elseif minutes > 1 then
        parts[#parts + 1] = V.MINUTES:format(minutes)
    end
    return table.concat(parts, " ")
end

function V.LastLine(seconds)
    local text = V.TimeText(seconds)
    if not text then return V.LAST_UNKNOWN end
    return V.LAST:format(text)
end

function V.Step(run, name, now)
    local t
    if clockOk(now) then t = now end
    local has = type(run) == "table" and type(run.name) == "string"
    if name ~= nil then
        if has and run.name == name then
            -- A reload inside the run.
            if run.left == nil then return run, false end
            -- Out and back in soon: the same run goes on.
            if t and clockOk(run.left) and t >= run.left and t - run.left < V.GRACE then
                -- With the wing known, this may be another wing of the same
                -- name: where the run stood is kept for V.Split.
                if type(run.as) == "string" then
                    run.back, run.backLeft, run.xpBack = t, run.left, num(run.xp) and run.xp or 0
                end
                run.left = nil
                return run, true
            end
        end
        local fresh = { name = name, t = t }
        if has then return fresh, true, V.Key(run), V.RunTime(run), V.RunXp(run) end
        return fresh, true
    end
    if not has then return run, false end
    if run.left == nil then
        run.left = t or true
        return run, true
    end
    if not clockOk(run.left) or not t or t < run.left or t - run.left >= V.GRACE then
        return {}, true, V.Key(run), V.RunTime(run), V.RunXp(run)
    end
    return run, false
end

function V.Declare(k, diag)
    local api = {}
    local ctx, st, cancelStep
    local afterIndex
    local measure
    local id = k.id or ns.id
    local R = ns.DungeonRead

    local function client() return ctx and ctx.client or k.client end

    -- true: in a dungeon; false: not in one; nil: not known (the instance
    -- read did not answer). Not known is never read as outside.
    local function inside()
        local inst = ask(client(), "instance")
        if type(inst) ~= "table" or type(inst.inside) ~= "boolean" then return nil end
        return inst.inside == true and V.KINDS[inst.kind] == true
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
                    if afterIndex then afterIndex() end
                end
            end)
        end
    end

    -- The run you are in, as saved; a copy to change and save back.
    local function run()
        if not ctx then return nil end
        local ok, r = pcall(ctx.store.get, ctx.store, "char", V.RUN)
        if not ok or type(r) ~= "table" then return nil end
        local out = {}
        for key, v in pairs(r) do out[key] = v end
        return out
    end

    local function keep(r)
        if not ctx then return end
        local ok, yes, why = pcall(ctx.store.set, ctx.store, "char", V.RUN, r)
        if not ok then
            k.problems:add(V.NAME, "run", tostring(yes))
        elseif yes ~= true then
            k.problems:add(V.NAME, "run", tostring(why))
        end
    end

    -- A copy of a saved table of this character, or an empty one.
    local function saved(path)
        local out = {}
        if not ctx then return out end
        local ok, t = pcall(ctx.store.get, ctx.store, "char", path)
        if ok and type(t) == "table" then
            for key, v in pairs(t) do out[key] = v end
        end
        return out
    end

    local function save(path, value, what)
        local okSet, yes, why = pcall(ctx.store.set, ctx.store, "char", path, value)
        if not okSet then
            k.problems:add(V.NAME, what, tostring(yes))
        elseif yes ~= true then
            k.problems:add(V.NAME, what, tostring(why))
        end
    end

    -- What is kept for the run of that name: the game's name for a dungeon
    -- and Questie's may differ in case.
    local function pick(path, name)
        if type(name) ~= "string" then return nil end
        local t = saved(path)
        if t[name] ~= nil then return t[name] end
        local want = name:lower()
        for key, v in pairs(t) do
            if type(key) == "string" and key:lower() == want then return v end
        end
        return nil
    end

    local function lastOf(name)
        return pick(V.TIMES, name)
    end

    -- A run that ended: its time is kept when it has one of a run's length,
    -- and with it the XP it gained (B-54), or no XP when that is not known.
    local function record(name, seconds, xp)
        if not ctx or type(name) ~= "string" or not clockOk(seconds) then return end
        if seconds < V.SHORT or seconds > V.LONG then return end
        local times = saved(V.TIMES)
        times[name] = seconds
        save(V.TIMES, times, "times")
        local gained = saved(V.RUN_XP)
        if gained[name] ~= xp then
            gained[name] = xp
            save(V.RUN_XP, gained, "runXp")
        end
    end

    -- B-54: the "about N times" line for the run of that name, or nil when
    -- the run's rate or your questing rate is not measured.
    -- B-55: the same ratio as a number (Nav/DungeonBadge.lua), or nil.
    function api.Ratio(name)
        if not ctx or type(name) ~= "string" or name == "" then return nil end
        local rate = V.RateFrom(saved(V.SAMPLES), ask(client(), "clock"))
        return V.Ratio(pick(V.RUN_XP, name), pick(V.TIMES, name), rate)
    end

    function api.RateLine(name)
        if not ctx or type(name) ~= "string" or name == "" then return nil end
        -- Asked for a rate: from now on this character's XP is measured.
        if measure then measure() end
        local rate = V.RateFrom(saved(V.SAMPLES), ask(client(), "clock"))
        local ratio = V.Ratio(pick(V.RUN_XP, name), pick(V.TIMES, name), rate)
        if not ratio then return nil end
        return V.RATE:format(ratio)
    end

    -- The bosses killed this visit, and whether the game reports kills.
    local function killsNow()
        local kills
        if type(k.use) == "function" then kills = k.use(ns.BossKills.NAME) end
        if type(kills) ~= "table" then return {}, nil end
        local reported
        if type(kills.Reported) == "function" then reported = kills.Reported() end
        local list = {}
        if type(kills.Kills) == "function" then list = kills.Kills() end
        if type(list) ~= "table" then list = {} end
        return list, reported
    end

    -- B-57: the wing you are in, told from the last boss killed this visit
    -- that Questie names as a boss of one of dungeon d's wings. nil: the
    -- dungeon has no wings, or no such boss is killed yet.
    local function wingHere(d)
        if type(d) ~= "table" or type(st) ~= "table" or st.state ~= "ready" then return nil end
        local list = killsNow()
        for i = #list, 1, -1 do
            local e = list[i]
            if type(e) == "table" and type(e.name) == "string" then
                local ok, wing = pcall(R.WingOfBoss, st, client(), d.key, e.name)
                if ok and wing then return wing end
            end
        end
        return nil
    end

    -- The run name of the wing you are in, in the dungeon of that name; nil
    -- when the wing is not known.
    local function wingTitle(name)
        if type(st) ~= "table" or st.state ~= "ready" then return nil end
        local d = R.DungeonNamed(st, name)
        local wing = wingHere(d)
        if not wing then return nil end
        return R.WingTitle(st, d.key, wing)
    end

    -- The line of the last run of the dungeon of that name (the one you
    -- are in when no name is given), or of your wing of it once that is
    -- known; nil outside a dungeon.
    function api.LastLine(name)
        if name == nil then
            if not inside() then return nil end
            name = ask(client(), "instanceName")
        end
        if type(name) ~= "string" or name == "" then return nil end
        return V.LastLine(lastOf(wingTitle(name) or name))
    end

    -- The kills line; in a known wing only that wing's bosses count, out of
    -- how many it has.
    local function killLine(info)
        local list, reported = killsNow()
        if type(info) ~= "table" or not info.wing then return V.KillLine(list, reported) end
        local mine = {}
        for _, e in ipairs(list) do
            if type(e) == "table" and type(e.name) == "string"
                and R.WingOfBoss(st, client(), info.key, e.name) == info.wing then
                mine[#mine + 1] = e
            end
        end
        return V.KillLine(mine, reported, info.bosses)
    end

    -- The quest lines for the dungeon of that name, or the one line that
    -- says why there are none yet.
    -- Also answers how sure it is: "wait" (not read yet, or not readable
    -- now), "none" (read: no quest of this dungeon for you), "quests".
    local function questLines(name)
        index()
        if not st or st.state == "noquestie" then
            return { name .. ": " .. ns.DungeonStates.WHY.noQuestie[1] }, "wait"
        end
        if st.state == "failed" then return { name .. ": " .. (st.why or R.WHY_LIST)[1] }, "wait" end
        if st.state == "building" then return { name .. ": " .. R.WHY_BUILDING[1] }, "wait" end
        local d = R.DungeonNamed(st, name)
        if not d then return { name .. ": " .. V.NOT_KNOWN }, "none" end
        -- B-57: in a known wing the lines are that wing's.
        local info = { key = d.key, wings = R.Wings(st, d.key), wing = wingHere(d) }
        if info.wing then
            name = R.WingTitle(st, d.key, info.wing) or name
            for _, w in ipairs(info.wings or {}) do
                if w.name == info.wing then info.bosses = w.bosses end
            end
        end
        local pane = R.Pane(st, client(), d.key, info.wing)
        if type(pane) ~= "table" then return { name .. ": " .. V.NOT_KNOWN }, "wait", info end
        local log
        if ns.Nav and type(ns.Nav.QuestLogRows) == "function" then log = ns.Nav.QuestLogRows(client()) end
        local have, missing = V.Quests(pane, st.quests, log)
        if #have == 0 and #missing == 0 then
            local W = ns.DungeonStates.WHY
            if type(pane.why) == "table" and pane.why ~= W.noQuests and pane.why ~= W.unplaced then
                return { name .. ": " .. tostring(pane.why[1]) }, "wait", info
            end
            if type(pane.why) == "table" then return { name .. ": " .. tostring(pane.why[1]) }, "none", info end
            return V.QuestLines(name, have, missing), "none", info
        end
        return V.QuestLines(name, have, missing), "quests", info
    end

    -- The summary's lines; outside: nil; not known whether inside: nil and
    -- "unknown".
    function api.Lines()
        local isIn = inside()
        if isIn == nil then return nil, "unknown" end
        if not isIn then return nil end
        local name = ask(client(), "instanceName")
        local out, info
        if type(name) ~= "string" or name == "" then
            out = { V.NO_NAME }
        else
            local _
            out, _, info = questLines(name)
        end
        if type(info) == "table" and info.wings and not info.wing then out[#out + 1] = V.WING_UNKNOWN end
        out[#out + 1] = killLine(info)
        local last = api.LastLine(name)
        if last then out[#out + 1] = last end
        if type(name) == "string" then
            local rate = api.RateLine(wingTitle(name) or name)
            if rate then out[#out + 1] = rate end
        end
        return out
    end

    local function say(lines)
        local c = client()
        if type(c) ~= "table" or type(c.print) ~= "function" then return end
        for i, line in ipairs(lines) do
            if i == 1 then c.print(id.title .. ": " .. line) else c.print("  " .. line) end
        end
    end

    -- B-47: the quest lines, said once for the run you are in. pending:
    -- you are inside a run whose lines are not said yet.
    local pending = false
    local function sayEntered()
        if not pending or not ctx or not inside() then return end
        if ctx.settings:get(ns.DungeonTracker.SETTING) ~= true then return end
        local name = ask(client(), "instanceName")
        if type(name) ~= "string" or name == "" then return end
        local ok, lines, sure = pcall(questLines, name)
        if not ok then
            pending = false
            k.problems:add(V.NAME, "entered", tostring(lines))
            return
        end
        if sure == "wait" then return end
        pending = false
        local r = run()
        if not r or r.name ~= name then r = { name = name } end
        r.said = true
        keep(r)
        if sure == "quests" then say(lines) end
    end
    afterIndex = sayEntered

    -- Entering, leaving, a reload inside: which run this is.
    local function entered()
        local name
        local isIn = inside()
        -- Not known where you are: the run stays as it was.
        if isIn == nil then return end
        if isIn then
            index()
            -- In a dungeon: from now on this character's XP is measured.
            if measure then measure() end
            name = ask(client(), "instanceName")
            -- Inside a dungeon the game does not name: nothing to keep.
            if type(name) ~= "string" or name == "" then return end
        end
        local r, changed, finished, seconds, xp = V.Step(run(), name, ask(client(), "clock"))
        if finished then record(finished, seconds, xp) end
        -- B-57: once the wing is known the run is that wing's.
        if name ~= nil and type(r) == "table" and r.name == name then
            local as = wingTitle(name)
            if as and r.as ~= as then
                -- Another wing after coming back in: two runs (section 550).
                local old, fresh = V.Split(r, as)
                if old then
                    record(V.Key(old), V.RunTime(old), V.RunXp(old))
                    r = fresh
                else
                    r.as = as
                end
                changed = true
            end
        end
        if changed then keep(r) end
        pending = name ~= nil and type(r) == "table" and r.said ~= true
        sayEntered()
    end

    -- B-54: the XP gained since the last reading goes to the run you are
    -- in, or, outside a dungeon, to the samples your questing rate is
    -- worked out from. A reading that is missed inside a run leaves that
    -- run's XP not known.
    local lastXp
    local function onXp()
        if not ctx then return end
        local xp = ask(client(), "xp")
        local now
        if type(xp) == "table" then now = { cur = xp.cur, max = xp.max, level = ask(client(), "level") } end
        local gained = V.Gain(lastXp, now)
        local isIn = inside()
        -- A reading missed inside, or XP gained while it is not known where
        -- you are: the run in progress no longer has a known XP.
        local missed = isIn == true and lastXp ~= nil and gained == nil
        local unplaced = isIn == nil and gained ~= nil and gained > 0
        if missed or unplaced then
            local r = run()
            if r and type(r.name) == "string" and r.left == nil and r.noXp ~= true then
                r.noXp = true
                keep(r)
            end
        end
        lastXp = now
        if not gained or gained <= 0 then return end
        -- Not known where: it counts for neither rate.
        if isIn == nil then return end
        if isIn then
            local r = run()
            if r and type(r.name) == "string" and r.left == nil then
                r.xp = (num(r.xp) and r.xp or 0) + gained
                keep(r)
            end
            return
        end
        local t = ask(client(), "clock")
        if not clockOk(t) then return end
        local list = {}
        for _, s in ipairs(saved(V.SAMPLES)) do list[#list + 1] = s end
        list[#list + 1] = { t = t, xp = gained }
        while #list > V.SAMPLES_MAX do table.remove(list, 1) end
        save(V.SAMPLES, list, "samples")
    end

    -- B-54: starts measuring XP for this character, once: the first XP
    -- reading and the XP events. Kept, so later sessions measure from login.
    local measuring = false
    measure = function()
        if measuring or not ctx then return end
        measuring = true
        local ok, on = pcall(ctx.store.get, ctx.store, "char", V.MEASURE)
        if not ok or on ~= true then save(V.MEASURE, true, "measure") end
        for _, event in ipairs(V.XP_EVENTS) do
            ctx.bus:on(V.NAME, event, function() onXp() end)
        end
        onXp()
    end

    -- Whether this module is measuring XP: its own XP read and its own
    -- listeners, whatever else in the add-on listens to the same events.
    function api.Measuring() return measuring end

    if diag and type(diag.commands) == "table" then
        diag.commands[V.WORD] = function()
            if measure then measure() end
            -- A run that ended since the last event is closed first.
            if ctx then pcall(entered) end
            local ok, lines, why = pcall(api.Lines)
            if not ok then
                k.problems:add(V.NAME, "word", tostring(lines))
                return
            end
            if not lines and why == "unknown" then return say({ V.CANNOT_TELL }) end
            if not lines then return say({ V.OUTSIDE:format(tostring(id.slash)) }) end
            say(lines)
        end
        if type(diag.help) == "table" then diag.help[V.WORD] = V.HELP end
    end

    k:Module({
        name = V.NAME,
        needs = { "client", "store", "settings", "bus", "sched" },
        provides = { Lines = api.Lines, LastLine = api.LastLine, RateLine = api.RateLine, Ratio = api.Ratio,
                     Measuring = api.Measuring },
        start = function(c)
            ctx = c
            -- Inside a dungeon the index is read ahead, so the word answers
            -- at once and the entering lines are said when it is read.
            for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do
                c.bus:on(V.NAME, event, function() entered() end)
            end
            -- Lines that had to wait (Questie not there yet, your level not
            -- read yet) are tried again when the quest log changes.
            c.bus:on(V.NAME, "QUEST_LOG_UPDATE", function()
                if pending then sayEntered() end
            end)
            -- B-54: XP gained, for the run or for your questing rate, only
            -- for a character that has been in a dungeon or asked before.
            local okM, on = pcall(c.store.get, c.store, "char", V.MEASURE)
            if okM and on == true then measure() end
            -- B-57: a boss killed may tell which wing this run is.
            c.bus:on(V.NAME, ns.BossKills.EVENT, function() entered() end)
            entered()
        end,
        stop = function()
            if cancelStep then cancelStep() end
            cancelStep = nil
            measuring = false
            ctx = nil
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.dungeonVisit = V.Declare(ns, ns.diag)
